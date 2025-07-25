//
//  Target.swift
//  
//
//  Created by Thomas Roughton on 7/12/19.
//

import Foundation
import SPIRV_Cross

enum Target: Hashable {
    enum MetalPlatform: String, Hashable {
        case macOS
        case macOSAppleSilicon
        case iOS
        case tvOS
        case visionOS
        case iOSSimulator
        case tvOSSimulator
        case visionOSSimulator
        
        var isSimulator: Bool {
            switch self {
            case .iOSSimulator, .tvOSSimulator, .visionOSSimulator:
                return true
            default:
                return false
            }
        }
    }
    
    case metal(platform: MetalPlatform, deploymentTarget: String)
    case vulkan(version: String)
    
    static func ==(lhs: Target, rhs: Target) -> Bool {
        switch (lhs, rhs) {
        case (.metal(let platformA, _), .metal(let platformB, _)):
            return platformA == platformB
        case (.vulkan, .vulkan):
            return true
        default:
            return false
        }
    }
    
    static var defaultTarget : Target {
#if (os(iOS) || os(tvOS) || os(watchOS)) && !targetEnvironment(macCatalyst)
    return .metal(platform: .iOS, deploymentTarget: "12.0")
#elseif os(macOS) || targetEnvironment(macCatalyst)
#if arch(i386) || arch(x86_64)
    return .metal(platform: .macOS, deploymentTarget: "10.14")
#else
    return .metal(platform: .macOSAppleSilicon, deploymentTarget: "10.16")
#endif
#else
        return .vulkan(version: "1.1")
#endif
    }
    
    var metalPlatform: MetalPlatform? {
        switch self {
        case .metal(let platform, _):
            return platform
        default:
            return nil
        }
    }
    
    var metalVersion: (major: Int, minor: Int)? {
        switch self {
        case .metal(let platform, let deploymentTarget):
            let components = deploymentTarget.split(separator: ".")

            let majorVersion = components.first.flatMap { Int($0) } ?? 10
            let minorVersion = components.dropFirst().first.flatMap { Int($0) } ?? 0
            
            switch platform {
            case .macOS:
                switch (majorVersion, minorVersion) {
                case _ where majorVersion >= 14:
                    return (3, 0)
                case _ where majorVersion >= 11:
                    return (2, 3)
                case (10, 16):
                    return (2, 3)
                case (10, 15):
                    return (2, 2)
                case (10, 14):
                    return (2, 1)
                case (10, 13):
                    return (2, 0)
                case (10, 12):
                    return (1, 2)
                case (10, 11):
                    return (1, 1)
                default:
                    return (1, 0)
                }
            case .macOSAppleSilicon:
                return (2, 3)
            case .iOS, .tvOS, .iOSSimulator, .tvOSSimulator:
                switch majorVersion {
                case _ where majorVersion >= 14:
                    return (2, 3)
                case 13:
                    return (2, 2)
                case 12:
                    return (2, 1)
                case 11:
                    return (2, 0)
                case 10:
                    return (1, 2)
                case 9:
                    return (1, 1)
                default:
                    return (1, 0)
                }
            case .visionOS, .visionOSSimulator:
                return (3, 0)
            }
        default:
            return nil
        }
    }
    
    var isAppleSilicon: Bool {
        if let platform = self.metalPlatform, platform != .macOS {
            return true
        }
        return false
    }
    
    var isMetal: Bool {
        switch self {
        case .metal:
            return true
        default:
            return false
        }
    }
    
    var spvcBackend : spvc_backend {
        switch self {
        case .metal:
            return SPVC_BACKEND_MSL
        case .vulkan:
            return SPVC_BACKEND_NONE
        }
    }
    
    var targetDefines : [String] {
        switch self {
        case .metal(.macOS, _):
            return ["TARGET_METAL_MACOS"]
        case .metal(.macOSAppleSilicon, _):
            return ["TARGET_METAL_MACOS", "TARGET_METAL_APPLE_SILICON"]
        case .metal(.iOS, _):
            return ["TARGET_METAL_IOS", "TARGET_METAL_APPLE_SILICON"]
        case .metal(.tvOS, _):
            return ["TARGET_METAL_TVOS", "TARGET_METAL_APPLE_SILICON"]
        case .metal(.visionOS, _):
            return ["TARGET_METAL_VISIONOS", "TARGET_METAL_APPLE_SILICON"]
        case .metal(.iOSSimulator, _):
            return ["TARGET_METAL_IOS", "TARGET_METAL_SIMULATOR", "TARGET_METAL_APPLE_SILICON"]
        case .metal(.tvOSSimulator, _):
            return ["TARGET_METAL_TVOS", "TARGET_METAL_SIMULATOR", "TARGET_METAL_APPLE_SILICON"]
        case .metal(.visionOSSimulator, _):
            return ["TARGET_METAL_VISIONOS", "TARGET_METAL_SIMULATOR", "TARGET_METAL_APPLE_SILICON"]
        case .vulkan:
            return ["TARGET_VULKAN"]
        }
    }

    var intermediatesDirectory : String {
        switch self {
        case .metal(let platform, _):
            return "Intermediates/Metal-\(platform.rawValue)"
        case .vulkan:
            return self.outputDirectory
        }
    }
    
    var outputDirectory : String {
        switch self {
        case .metal:
            return "Compiled"
        case .vulkan:
            return "Compiled/Vulkan"
        }
    }
    
    var spirvDirectory : String {
        switch self {
        case .vulkan:
            return self.intermediatesDirectory
        default:
            return self.intermediatesDirectory + "/SPIRV"
        }
    }
    
    var compiler : TargetCompiler? {
        switch self {
        case .metal:
            return MetalCompiler(target: self)
        case .vulkan:
            return nil // We've already compiled to SPIR-V, so there's nothing else to do.
        }
    }
}

extension Target: CustomStringConvertible {
    var description: String {
        switch self {
        case .metal(let platform, let deploymentTarget):
            return "Metal (\(platform.rawValue) \(deploymentTarget))"
        case .vulkan(let version):
            return "Vulkan (v\(version))"
        }
    }
}

enum CompilerError : Error {
    case shaderErrors
    case libraryGenerationFailed(Error)
}

protocol TargetCompiler {
    func compile(spirvCompilers: [SPIRVCompiler], sourceDirectory: URL, workingDirectory: URL, outputDirectory: URL, withDebugInformation debug: Bool) throws
}

final class MetalCompiler : TargetCompiler {
    let target: Target
    let driver : MetalDriver
    
    init(target: Target) {
        precondition(target.isMetal)
        self.target = target
        self.driver = MetalDriver(target: target)!
    }
    
    private func makeMSLVersion(major: Int, minor: Int, patch: Int) -> UInt32 {
        return UInt32(major * 10000 + minor * 100 + patch)
    }
    
    func compile(spirvCompilers: [SPIRVCompiler], sourceDirectory: URL, workingDirectory: URL, outputDirectory: URL, withDebugInformation debug: Bool) throws {
        var sourceFiles = [(metalSource: URL, airFile: URL)]()
        var needsRegenerateLibrary = false
        var hadErrors = false
        
        let airDirectory = workingDirectory.appendingPathComponent("AIR")
        try FileManager.default.createDirectoryIfNeeded(at: airDirectory)
        
        for compiler in spirvCompilers where compiler.file.target == self.target {
            do {
                var options : spvc_compiler_options! = nil
                spvc_compiler_create_compiler_options(compiler.compiler, &options)
                
                let targetMetalVersion = self.target.metalVersion ?? (2, 1)
                spvc_compiler_options_set_uint(options, SPVC_COMPILER_OPTION_MSL_VERSION, makeMSLVersion(major: targetMetalVersion.major, minor: targetMetalVersion.minor, patch: 0))
                if targetMetalVersion.major >= 2 {
                    spvc_compiler_options_set_bool(options, SPVC_COMPILER_OPTION_MSL_ARGUMENT_BUFFERS, 1)
                    spvc_compiler_options_set_bool(options, SPVC_COMPILER_OPTION_MSL_FORCE_ACTIVE_ARGUMENT_BUFFER_RESOURCES, 1)
                    spvc_compiler_options_set_bool(options, SPVC_COMPILER_OPTION_MSL_ENABLE_DECORATION_BINDING, 1)
                    spvc_compiler_options_set_bool(options, SPVC_COMPILER_OPTION_MSL_IOS_USE_SIMDGROUP_FUNCTIONS, 1)
                }
                switch self.target {
                case .metal(.macOS, _):
                    spvc_compiler_options_set_uint(options, SPVC_COMPILER_OPTION_MSL_PLATFORM, UInt32(SPVC_MSL_PLATFORM_MACOS.rawValue))
                    spvc_compiler_options_set_bool(options, SPVC_COMPILER_OPTION_MSL_FRAMEBUFFER_FETCH_SUBPASS, 0)
                case .metal(.iOSSimulator, _), .metal(.visionOSSimulator, _), .metal(.tvOSSimulator, _):
                    spvc_compiler_options_set_uint(options, SPVC_COMPILER_OPTION_MSL_PLATFORM, UInt32(SPVC_MSL_PLATFORM_MACOS.rawValue))
                    spvc_compiler_options_set_bool(options, SPVC_COMPILER_OPTION_MSL_FRAMEBUFFER_FETCH_SUBPASS, 0)
                default:
                    spvc_compiler_options_set_uint(options, SPVC_COMPILER_OPTION_MSL_PLATFORM, UInt32(SPVC_MSL_PLATFORM_IOS.rawValue))
                    spvc_compiler_options_set_bool(options, SPVC_COMPILER_OPTION_MSL_FRAMEBUFFER_FETCH_SUBPASS, 1)
                    spvc_compiler_options_set_bool(options, SPVC_COMPILER_OPTION_MSL_IOS_USE_SIMDGROUP_FUNCTIONS, 1)
                }
                
                spvc_compiler_install_compiler_options(compiler.compiler, options)
            }
            
            let outputFileName = compiler.file.sourceFile.renderPass + "-" + compiler.file.entryPoint.name
            
            var metalFileURL = workingDirectory.appendingPathComponent(outputFileName + ".metal")
            let airFileURL = airDirectory.appendingPathComponent(outputFileName + ".air")
            do {
                // Generate the compiled source unconditionally, since we need it to compute bindings for reflection.
                let compiledSource = try compiler.compiledSource()
                
                guard !compiler.reflectionOnly else { return }
                
                if metalFileURL.needsGeneration(sourceFile: compiler.file.url) {
                    print("\(self.target): Compiling \(compiler.file.url.lastPathComponent)")
                    try compiledSource.write(to: metalFileURL, atomically: false, encoding: .ascii)
                    metalFileURL.removeCachedResourceValue(forKey: .contentModificationDateKey)
                }
                
                sourceFiles.append((metalFileURL, airFileURL))
                
            }
            catch {
                print("Error compiling file \(compiler.file):")
                print(error)
                hadErrors = true
            }
        }
        
        // Also include any source files in the Source/Metal folder.
        let metalSourcesDirectory = sourceDirectory.appendingPathComponent("Metal")
        if FileManager.default.fileExists(atPath: metalSourcesDirectory.path),
            let enumerator = FileManager.default.enumerator(at: metalSourcesDirectory, includingPropertiesForKeys: nil) {
            
            for case let metalFileURL as URL in enumerator where metalFileURL.pathExtension.lowercased() == "metal" {
                let outputFileName = metalFileURL.lastPathComponent
                let airFileURL = airDirectory.appendingPathComponent(outputFileName + ".air")
                
                sourceFiles.append((metalFileURL, airFileURL))
            }
        }
        
        let fileModificationTimes = computeSourceFileModificationTimes(sourceFiles.lazy.map { $0.metalSource })
        
        for (metalFileURL, airFileURL) in sourceFiles {
            do {
                if airFileURL.needsGeneration(sourceFile: metalFileURL, modificationDates: fileModificationTimes) {
                    try self.driver.compileToAIR(sourceFile: metalFileURL, destinationFile: airFileURL, withDebugInformation: debug).waitUntilExit()
                    
                    needsRegenerateLibrary = true
                }
            }
            catch {
                print("Error compiling Metal file \(metalFileURL):")
                print(error)
                hadErrors = true
            }
        }
        
        if hadErrors {
            throw CompilerError.shaderErrors
        }
        
        for i in 0..<sourceFiles.count {
            sourceFiles[i].airFile.removeCachedResourceValue(forKey: .contentModificationDateKey)
        }
        
        if needsRegenerateLibrary {
            do {
                try FileManager.default.createDirectoryIfNeeded(at: outputDirectory)
                
                let metalLibraryPath = outputDirectory.appendingPathComponent("Library-\(target.metalPlatform!.rawValue).metallib")
                print("\(self.target): Linking Metal library at \(metalLibraryPath.path)")
                try self.driver.generateLibrary(airFiles: sourceFiles.map { $1 }, outputLibrary: metalLibraryPath, withDebugInformation: debug).waitUntilExit()
            }
            catch {
                throw CompilerError.libraryGenerationFailed(error)
            }
        }
    }
}
