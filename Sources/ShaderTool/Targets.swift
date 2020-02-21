//
//  Target.swift
//  
//
//  Created by Thomas Roughton on 7/12/19.
//

import Foundation
import SPIRV_Cross

enum Target : Hashable, CaseIterable {
    case macOSMetal
    case iOSMetal
    case vulkan
    
    static var defaultTarget : Target {
#if os(iOS) || os(tvOS) || os(watchOS)
        return .iOSMetal
#elseif os(macOS)
        return .macOSMetal
#else
        return .vulkan
#endif
    }
    
    var spvcBackend : spvc_backend {
        switch self {
        case .macOSMetal, .iOSMetal:
            return SPVC_BACKEND_MSL
        case .vulkan:
            return SPVC_BACKEND_NONE
        }
    }
    
    var targetDefine : String {
        switch self {
        case .macOSMetal:
            return "TARGET_METAL_MACOS"
        case .iOSMetal:
            return "TARGET_METAL_IOS"
        case .vulkan:
            return "TARGET_VULKAN"
        }
    }
    
    var outputDirectory : String {
        switch self {
        case .macOSMetal:
            return "Metal"
        case .iOSMetal:
            return "Metal-iOS"
        case .vulkan:
            return "Vulkan"
        }
    }
    
    var spirvDirectory : String {
        switch self {
        case .vulkan:
            return self.outputDirectory
        default:
            return self.outputDirectory + "/SPIRV"
        }
    }
    
    var compiler : TargetCompiler? {
        switch self {
        case .macOSMetal, .iOSMetal:
            return MetalCompiler(target: self)
        case .vulkan:
            return nil // We've already compiled to SPIR-V, so there's nothing else to do.
        }
    }
}

enum CompilerError : Error {
    case shaderErrors
    case libraryGenerationFailed(Error)
}

protocol TargetCompiler {
    func compile(spirvCompilers: [SPIRVCompiler], sourceDirectory: URL, outputDirectory: URL, withDebugInformation debug: Bool) throws
}

final class MetalCompiler : TargetCompiler {
    let target: Target
    let driver : MetalDriver
    
    init(target: Target) {
        precondition(target == .macOSMetal || target == .iOSMetal)
        self.target = target
        self.driver = MetalDriver(target: target)!
    }
    
    private func makeMSLVersion(major: Int, minor: Int, patch: Int) -> UInt32 {
        return UInt32(major * 10000 + minor * 100 + patch)
    }
    
    func compile(spirvCompilers: [SPIRVCompiler], sourceDirectory: URL, outputDirectory: URL, withDebugInformation debug: Bool) throws {
        var sourceFiles = [(metalSource: URL, airFile: URL)]()
        var needsRegenerateLibrary = false
        var hadErrors = false
        
        let airDirectory = outputDirectory.appendingPathComponent("AIR")
        try FileManager.default.createDirectoryIfNeeded(at: airDirectory)
        
        for compiler in spirvCompilers where compiler.file.target == self.target {
            do {
                var options : spvc_compiler_options! = nil
                spvc_compiler_create_compiler_options(compiler.compiler, &options)
                
                spvc_compiler_options_set_uint(options, SPVC_COMPILER_OPTION_MSL_VERSION, makeMSLVersion(major: 2, minor: 1, patch: 0))
                spvc_compiler_options_set_bool(options, SPVC_COMPILER_OPTION_MSL_ARGUMENT_BUFFERS, 1)
                spvc_compiler_options_set_bool(options, SPVC_COMPILER_OPTION_MSL_FORCE_ACTIVE_ARGUMENT_BUFFER_RESOURCES, 1)
                spvc_compiler_options_set_uint(options, SPVC_COMPILER_OPTION_MSL_PLATFORM, self.target == .iOSMetal ? SPVC_MSL_PLATFORM_IOS.rawValue : SPVC_MSL_PLATFORM_MACOS.rawValue)
                
                spvc_compiler_install_compiler_options(compiler.compiler, options)
            }
            
            let outputFileName = compiler.file.sourceFile.renderPass + "-" + compiler.file.entryPoint.name
            
            var metalFileURL = outputDirectory.appendingPathComponent(outputFileName + ".metal")
            let airFileURL = airDirectory.appendingPathComponent(outputFileName + ".air")
            do {
                // Generate the compiled source unconditionally, since we need it to compute bindings for reflection.
                let compiledSource = try compiler.compiledSource()
                
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
        
        for (metalFileURL, airFileURL) in sourceFiles {
            do {
                if airFileURL.needsGeneration(sourceFile: metalFileURL) {
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
                let metalLibraryPath = outputDirectory.appendingPathComponent("Library.metallib")
                print("\(self.target): Linking Metal library at \(metalLibraryPath.path)")
                try self.driver.generateLibrary(airFiles: sourceFiles.map { $1 }, outputLibrary: metalLibraryPath).waitUntilExit()
            }
            catch {
                throw CompilerError.libraryGenerationFailed(error)
            }
        }
    }
}
