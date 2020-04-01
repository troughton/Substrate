import ArgumentParser
import Foundation

typealias URL = Foundation.URL

enum ArgumentError: Error {
    case invalidReflectionFile(String)
}

extension Target: ExpressibleByArgument {
    init?(argument: String) {
        let lowercasedArg = argument.lowercased()
        if lowercasedArg.starts(with: "macos") {
            self = .macOSMetal
        } else if lowercasedArg.starts(with: "ios") {
            self = .iOSMetal
        } else if lowercasedArg == "vulkan" {
            self = .vulkan
        } else {
            return nil
        }
    }
}

struct ShaderTool: ParsableCommand {
    @Argument(help: "The path to the shader directory. The directory is expected to contain a Source/RenderPasses folder, containing an HLSL file per render pass.")
    var shaderDirectory: String
    
    @Argument(help: "The path to output the reflection file.")
    var reflectionFile: String
    
    @Option(help: "The targets to compile for.")
    var target: [Target]
    
    @Flag(help: "Compile the shaders with debug information.")
    var debug: Bool

    func run() throws {
        let reflectionURL = URL(fileURLWithPath: reflectionFile)
        
        guard reflectionURL.pathExtension == "swift" else {
            throw ArgumentError.invalidReflectionFile(reflectionFile)
        }
        
        let compiler = try ShaderCompiler(directory: URL(fileURLWithPath: shaderDirectory),
                                          reflectionFile: reflectionURL,
                                          targets: target.isEmpty ? [Target.defaultTarget] : target,
                                          compileWithDebugInfo: self.debug)
        compiler.compile()
        compiler.generateReflection()
    }
}

ShaderTool.main()
