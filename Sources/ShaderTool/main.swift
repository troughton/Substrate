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
            if lowercasedArg.contains("simulator") {
                self = .metal(platform: .iOSSimulator, deploymentTarget: version ?? "12.0")
            } else {
                self = .metal(platform: .iOS, deploymentTarget: version ?? "12.0")
            }
        } else if lowercasedArg.starts(with: "tvos") {
            if lowercasedArg.contains("simulator") {
                self = .metal(platform: .tvOSSimulator, deploymentTarget: version ?? "12.0")
            } else {
                self = .metal(platform: .tvOS, deploymentTarget: version ?? "12.0")
            }
        } else if lowercasedArg.starts(with: "visionos") {
            if lowercasedArg.contains("simulator") {
                self = .metal(platform: .visionOSSimulator, deploymentTarget: version ?? "1.0")
            } else {
                self = .metal(platform: .visionOS, deploymentTarget: version ?? "1.0")
            }
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
    var target: [Target] = []
    
    @Option(help: "Targets to include in the shader reflection but which should not be fully compiled.")
    var reflectionTarget: [Target] = []
    
    @Flag(help: "Compile the shaders with debug information.")
    var debug: Bool = false
    
    @Flag(help: "Skip HLSL legalization (done using SPIRV-Opt). HLSL legalization is usually required, but some well-behaved sources may not need it and it may be easier to view the cross-compiled sources with it disabled.")
    var skipHLSLLegalization: Bool = false
    
    @Flag(help: "Force position inputs and outputs to be marked as being invariant, ensuring the same result in different passes.")
    var invariantPosition: Bool = false

    func run() throws {
        let reflectionURL = URL(fileURLWithPath: reflectionFile)
        
        guard reflectionURL.pathExtension == "swift" else {
            throw ArgumentError.invalidReflectionFile(reflectionFile)
        }
        
        let compiler = try ShaderCompiler(directory: URL(fileURLWithPath: shaderDirectory),
                                          reflectionFile: reflectionURL,
                                          targets: target.isEmpty ? [Target.defaultTarget] : target,
                                          reflectionOnlyTargets: self.reflectionTarget,
                                          compileWithDebugInfo: self.debug,
                                          legalizeHLSL: !self.skipHLSLLegalization,
                                          invariantPosition: self.invariantPosition)
        compiler.compile()
        compiler.generateReflection()
    }
}

ShaderTool.main()
