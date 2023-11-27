//
//  File.swift
//  
//
//  Created by Thomas Roughton on 1/12/19.
//

import Foundation
import SPIRV_Cross
import Substrate

enum ShaderType : Hashable {
    case vertex
    case fragment
    case compute
    
    init?(string: String) {
        switch string.lowercased() {
        case "vertex":
            self = .vertex
        case "fragment", "pixel":
            self = .fragment
        case "compute":
            self = .compute
        default:
            return nil
        }
    }
    
    var shaderModel : String {
        switch self {
        case .vertex:
            return "vs_6_2"
        case .fragment:
            return "ps_6_2"
        case .compute:
            return "cs_6_2"
        }
    }
    
    var executionModel : SpvExecutionModel {
        switch self {
        case .vertex:
            return SpvExecutionModelVertex
        case .fragment:
            return SpvExecutionModelFragment
        case .compute:
            return SpvExecutionModelGLCompute
        }
    }
    
    var stages : RenderStages {
        switch self {
        case .vertex:
            return .vertex
        case .fragment:
            return .fragment
        case .compute:
            return .compute
        }
    }
}

enum DriverError : Error {
    case missingDriver(String)
    case invalidTarget(Target)
}

fileprivate func findExecutable(_ name: String) -> URL? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    task.arguments = [name]  

    let pipe = Pipe()
    task.standardOutput = pipe

    do {
        try task.run()
        
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        
        if !data.isEmpty,
            let string = String(data: data, encoding: String.Encoding.utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            FileManager.default.fileExists(atPath: string) {
            return URL(fileURLWithPath: string)
        }
    } catch {}
    
    let localBin = "/usr/local/bin/\(name)"
    let homebrewBin = "/opt/homebrew/bin/\(name)"
    let usrBin = "/usr/bin/\(name)"
    
    #if os(macOS)
    if FileManager.default.fileExists(atPath: localBin) {
        return URL(fileURLWithPath: localBin)
    }
    
    if FileManager.default.fileExists(atPath: homebrewBin) {
        return URL(fileURLWithPath: homebrewBin)
    }
    #endif
    
    if FileManager.default.fileExists(atPath: usrBin) {
        return URL(fileURLWithPath: usrBin)
    }
    
    if FileManager.default.fileExists(atPath: homebrewBin) {
        return URL(fileURLWithPath: homebrewBin)
    }

    return nil
}

final class DXCDriver {
    let url : URL
    
    init() throws {
        let driverName = "dxc"
        guard let url = findExecutable(driverName) else {
            throw DriverError.missingDriver(driverName)
        }
        self.url = url
    }
    
    func compile(sourceFile: URL, destinationFile: URL, entryPoint: String, type: ShaderType, target: Target) throws -> Process {
        let arguments = ["-enable-16bit-types",
                         "-E", entryPoint] +
            target.targetDefines.map { "-D" + $0 } +
            ["-D" + "EntryPoint_\(entryPoint)",
             "-fspv-target-env=vulkan1.1",
             "-fspv-reflect",
             "-HV", "2021",
             "-T", type.shaderModel,
             "-spirv", "-fcgl",
             "-Vd", sourceFile.path,
             "-Fo", destinationFile.path]
        return try Process.run(self.url, arguments: arguments, terminationHandler: nil)
    }
}

final class SPIRVOptDriver {
    let url : URL
    
    init() throws {
        let driverName = "spirv-opt"
        guard let url = findExecutable(driverName) else {
            throw DriverError.missingDriver(driverName)
        }
        self.url = url
    }
    
    func optimise(sourceFile: URL, destinationFile: URL) throws -> Process {
        let arguments = ["--preserve-bindings", "--preserve-spec-constants", "--legalize-hlsl",
                         sourceFile.path, "-o", destinationFile.path]
        return try Process.run(self.url, arguments: arguments, terminationHandler: nil)
    }
}

extension Target {
    fileprivate var metalSDK : String? {
        switch self {
        case .metal(.macOS, _), .metal(.macOSAppleSilicon, _):
            return "macosx"
        case .metal(.iOS, _):
            return "iphoneos"
        case .metal(.iOSSimulator, _):
            return "iphonesimulator"
        case .metal(.tvOS, _):
            return "tvos"
        case .metal(.tvOSSimulator, _):
            return "tvsimulator"
        case .metal(.visionOS, _):
            return "xros"
        case .metal(.visionOSSimulator, _):
            return "xrsimulator"
        default:
            return nil
        }
    }
    
    fileprivate var metalTargetVersion : String? {
        switch self {
        case .metal(.macOS, let deploymentTarget), .metal(.macOSAppleSilicon, let deploymentTarget):
            return "-mmacosx-version-min=\(deploymentTarget)"
        case .metal(.iOS, let deploymentTarget),
             .metal(.iOSSimulator, let deploymentTarget):
            return "-mios-version-min=\(deploymentTarget)"
        default:
            return nil
        }
    }
    
    fileprivate var metalStandardLibrary : String? {
        switch self {
        case .metal(.macOSAppleSilicon, _):
            return "-std=macos-metal2.3"
        default:
            return nil
        }
    }
}

final class MetalDriver {
    let url : URL
    let target : Target
    
    init?(target: Target) {
        switch target {
        case .metal:
            break
        default:
            return nil
        }
        
        self.url = URL(fileURLWithPath: "/usr/bin/xcrun")
        self.target = target
    }
    
    func compileToAIR(sourceFile: URL, destinationFile: URL, withDebugInformation debug: Bool) throws -> Process {
        var arguments = ["-sdk", target.metalSDK!,
                         "metal", "-c", "-ffast-math",
                         "-Wno-unused-const-variable", // Ignore warnings for unused function constants
                         "-Wno-unused-variable", // Ignore warnings for unused variables
            ]
        if debug {
            arguments.append(contentsOf: ["-gline-tables-only", "-MO", "-frecord-sources"])
        } else {
            arguments.append("-O")
        }
        
        for define in target.targetDefines {
            arguments.append("-D\(define)")
        }
        
        if let metalVersion = target.metalVersion, (metalVersion.major == 2 && metalVersion.minor >= 3) || metalVersion.major >= 3 {
            arguments.append("-fpreserve-invariance")
        }
        
        arguments.append(contentsOf: [
                            target.metalTargetVersion,
                            target.metalStandardLibrary,
                            sourceFile.path,
                            "-o", destinationFile.path].lazy.compactMap { $0 })
        
        return try Process.run(self.url, arguments: arguments, terminationHandler: nil)
    }
    
    func generateLibrary(airFiles: [URL], outputLibrary: URL) throws -> Process {
        let arguments = ["-sdk", target.metalSDK!, "metallib",
                         "-o", outputLibrary.path] + airFiles.map { $0.path }
        return try Process.run(self.url, arguments: arguments, terminationHandler: nil)
    }
}
