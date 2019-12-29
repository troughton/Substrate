import Foundation

typealias URL = Foundation.URL

guard CommandLine.arguments.count >= 3 else {
    print("Usage: ShaderReflectionGenerator shaderDirectory reflectionFile")
    exit(-1)
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1])

let reflectionFile = URL(fileURLWithPath: CommandLine.arguments[2])

guard reflectionFile.pathExtension == "swift" else {
    print("Reflection file \(reflectionFile) does not have the required extension '.swift'")
    exit(-1)
}

let compiler = try! ShaderCompiler(directory: directory,
                                   reflectionFile: reflectionFile)
compiler.compile()
compiler.generateReflection()
