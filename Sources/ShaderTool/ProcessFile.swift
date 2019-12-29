import Foundation
import SPIRV_Cross
import SwiftFrameGraph

//func processFile(outputFile: URL, renderPass: String, otherArguments: ArraySlice<String>) {
//    
//    var context : spvc_context! = nil
//    spvc_context_create(&context)
//    guard context != nil else { fatalError("Could't create SPIR-V context") }
//    
//    defer { spvc_context_destroy(context) }
//    
//    var pushConstants : spvc_reflected_resource? = nil
//    var pushConstantsPrinter = ReflectionPrinter()
//    var resources = [Resource]()
//    var constants = FunctionConstants()
//    var entryPoints = [(String, SpvExecutionModel)]()
//    
//    var entryPointsToSourcePasses = [String : String]()
//    
//    func processFile(name fileName: String) {
//        let file = URL(fileURLWithPath: fileName)
//        let spv = try! Data(contentsOf: file)
//        
//        var ir : spvc_parsed_ir! = nil
//        _ = spv.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> Void in
//            _ = spvc_context_parse_spirv(context, bytes.baseAddress?.assumingMemoryBound(to: SpvId.self), bytes.count / MemoryLayout<SpvId>.size, &ir)
//        }
//        guard ir != nil else { fatalError("Couldn't parse SPIR-V IR: \(String(cString: spvc_context_get_last_error_string(context)))") }
//        
//        var compiler : spvc_compiler! = nil
//        spvc_context_create_compiler(context, SPVC_BACKEND_MSL, ir, SPVC_CAPTURE_MODE_TAKE_OWNERSHIP, &compiler)
//        
//        guard compiler != nil else { fatalError("Couldn't create SPIR-V compiler: \(String(cString: spvc_context_get_last_error_string(context)))") }
//        
//        // Get stage outputs, construct a RenderPassOutput enum from it.
//        // Also output push constant structs and (ideally) inline ArgumentBuffer data.1
//        
//        var spvEntryPoints : UnsafePointer<spvc_entry_point>! = nil
//        var entryPointCount = 0
//        spvc_compiler_get_entry_points(compiler, &spvEntryPoints, &entryPointCount)
//        
//        for i in 0..<entryPointCount {
//            let entryPoint = spvEntryPoints[i]
//            
//            let entryPointName = String(cString: entryPoint.name)
//            entryPoints.append((entryPointName, entryPoint.execution_model))
//            let sourcePass = entryPointsToSourcePasses[entryPointName]
//            
//            spvc_compiler_set_entry_point(compiler, entryPoint.name, entryPoint.execution_model)
//            
//            var spvResources : spvc_resources? = nil
//            spvc_compiler_create_shader_resources(compiler, &spvResources)
//            
//            // Add all resources, but don't mark them as part of this stage.
//            resources.append(contentsOf: buildResourceList(compiler: compiler, spvResources: spvResources!, stage: [], sourcePass: sourcePass))
//            
//            let stage : RenderStages
//            switch entryPoint.execution_model {
//            case SpvExecutionModelVertex:
//                stage = .vertex
//            case SpvExecutionModelFragment:
//                stage = .fragment
//            case SpvExecutionModelGLCompute:
//                stage = .compute
//            default:
//                stage = []
//            }
//            
//            var activeVariables : spvc_set? = nil
//            spvc_compiler_get_active_interface_variables(compiler, &activeVariables)
//            
//            var spvStageActiveResources : spvc_resources? = nil
//            spvc_compiler_create_shader_resources_for_active_variables(compiler, &spvStageActiveResources, activeVariables)
//            
//            // Add all active resources again, and this time mark them as part of this stage.
//            resources.append(contentsOf: buildResourceList(compiler: compiler, spvResources: spvStageActiveResources!, stage: stage, sourcePass: sourcePass))
//            
//            // There can be only one set of push constants per pipeline.
//            var reflectedResourceCount = 0
//            var stagePushConstants : UnsafePointer<spvc_reflected_resource>? = nil
//            spvc_resources_get_resource_list_for_type(spvResources, SPVC_RESOURCE_TYPE_PUSH_CONSTANT, &stagePushConstants, &reflectedResourceCount)
//            
//            if reflectedResourceCount > 0, let stagePushConstants = stagePushConstants {
//                if pushConstants == nil {
//                   // printPushConstants(stagePushConstants.pointee, compiler: compiler, to: &pushConstantsPrinter)
//                }
//                
//                pushConstants = stagePushConstants.pointee
//            }
//            
////            if entryPoint.execution_model == SpvExecutionModelFragment {
////                fragmentStageOutputs.addOutputs(compiler: compiler, spvResources: spvResources!)
////            }
//        }
//        
//        var specialisationConstants : UnsafePointer<spvc_specialization_constant>! = nil
//        var specialisationConstantCount = 0
//        
//        spvc_compiler_get_specialization_constants(compiler, &specialisationConstants, &specialisationConstantCount)
//        constants.add(compiler: compiler, constants: specialisationConstants, count: specialisationConstantCount)
//    }
//    
//    do {
//        var argumentIterator = otherArguments.makeIterator()
//        
//        while let argument = argumentIterator.next() {
//            if argument == "--source-pass" {
//                let entryPointName = argumentIterator.next()!
//                let passName = argumentIterator.next()!
//                entryPointsToSourcePasses[entryPointName] = passName
//            }
//        }
//    }
//    
//    do {
//        var argumentIterator = otherArguments.makeIterator()
//        
//        while let argument = argumentIterator.next() {
//            if argument == "--source-pass" {
//                let _ = argumentIterator.next()
//                let _ = argumentIterator.next()
//                continue
//            }
//            
//            processFile(name: argument)
//        }
//    }
//    
//    var outputStream = ReflectionPrinter(buffer: """
//        import SwiftFrameGraph
//        import SwiftMath
//        
//        
//        public struct \(renderPass)Reflection : RenderPassReflection {
//        
//        """, indent: 1)
//    
//    func processEntryPoints(name: String, executionModel: SpvExecutionModel_) {
//        let filteredEntryPoints = entryPoints.filter { $0.1 == executionModel }
//        
//        guard !filteredEntryPoints.isEmpty else {
//            return
//        }
//        
//        if let sourcePass = entryPointsToSourcePasses[filteredEntryPoints.first!.0], filteredEntryPoints.allSatisfy({ entryPointsToSourcePasses[$0.0] == sourcePass }) {
//            outputStream.print("public typealias \(name) = \(sourcePass)Reflection.\(name)")
//            outputStream.newLine()
//            return
//        }
//        
//        outputStream.print("public enum \(name) : String {")
//        outputStream.beginScope()
//        
//        for (name, _) in filteredEntryPoints {
//            let entryPointFunctionNameStart = name.lastIndex(of: "_").map { name.index(after: $0) } ?? name.startIndex
//            var enumCaseName = String(name[entryPointFunctionNameStart...])
//            enumCaseName.replaceSubrange(enumCaseName.startIndex...enumCaseName.startIndex, with: enumCaseName[enumCaseName.startIndex].lowercased())
//            
//            outputStream.print("case \(enumCaseName) = \"\(name)\"")
//        }
//        
//        outputStream.endScope()
//        outputStream.print("}")
//        outputStream.newLine()
//    }
//    
//    processEntryPoints(name: "VertexFunction", executionModel: SpvExecutionModelVertex)
//    processEntryPoints(name: "FragmentFunction", executionModel: SpvExecutionModelFragment)
//    processEntryPoints(name: "ComputeFunction", executionModel: SpvExecutionModelGLCompute)
//    
//    
//   // fragmentStageOutputs.print(to: &outputStream)
//    
//    constants.print(to: &outputStream)
//    
//    outputStream.print(pushConstantsPrinter)
//    
//    for i in 0..<8 {
//        let argBuffer = ArgumentBuffer(resources: resources, set: i)
//        argBuffer.printStruct(to: &outputStream)
//    }
//    
//    outputStream.endScope()
//    outputStream.print("}")
//    
//    try! outputStream.buffer.write(toFile: outputFile.path, atomically: false, encoding: .utf8)
//    
//}
