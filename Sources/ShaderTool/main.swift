import ArgumentParser
import Foundation

typealias URL = Foundation.URL

enum ArgumentError: Error {
    case invalidReflectionFile(String)
}

extension Target: ExpressibleByArgument {
    init?(argument: String) {
        let lowercasedArg = argument.lowercased()
        let versionStartIndex = lowercasedArg.firstIndex(where: { $0.isNumber })
        let version = versionStartIndex.map { String(lowercasedArg[$0...]) }
        
        if lowercasedArg.starts(with: "macos-applesilicon") || lowercasedArg.starts(with: "macos-apple-silicon") {
            self = .metal(platform: .macOSAppleSilicon, deploymentTarget: version ?? "10.16")
        } else if lowercasedArg.starts(with: "macos") {
            self = .metal(platform: .macOS, deploymentTarget: version ?? "10.14")
        } else if lowercasedArg.starts(with: "ios") {
            self = .metal(platform: .iOS, deploymentTarget: version ?? "12.0")
        } else if lowercasedArg.starts(with: "vulkan") {
            self = .vulkan(version: version ?? "1.1")
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
    
    @Flag(help: "Skip HLSL legalization (done using SPIRV-Opt). HLSL legalization is usually required, but some well-behaved sources may not need it and it may be easier to view the cross-compiled sources with it disabled.")
    var skipHLSLLegalization: Bool

    func run() throws {
        let reflectionURL = URL(fileURLWithPath: reflectionFile)
        
        guard reflectionURL.pathExtension == "swift" else {
            throw ArgumentError.invalidReflectionFile(reflectionFile)
        }
        
        let compiler = try ShaderCompiler(directory: URL(fileURLWithPath: shaderDirectory),
                                          reflectionFile: reflectionURL,
                                          targets: target.isEmpty ? [Target.defaultTarget] : target,
                                          compileWithDebugInfo: self.debug,
                                          legalizeHLSL: !self.skipHLSLLegalization)
        compiler.compile()
        compiler.generateReflection()
    }
}

ShaderTool.main()
