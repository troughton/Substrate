//
//  File.swift
//  
//
//  Created by Thomas Roughton on 3/12/19.
//

import Foundation
import SPIRV_Cross

final class SPIRVContext {
    let spvContext : spvc_context
    
    init() {
        var context : spvc_context! = nil
        spvc_context_create(&context)
        guard context != nil else { fatalError("Could't create SPIR-V context") }
        self.spvContext = context
    }
    
    deinit {
        spvc_context_destroy(self.spvContext)
    }
    
    var lastErrorString : String {
        return String(cString: spvc_context_get_last_error_string(self.spvContext))
    }
}

struct RenderTargetAttachment {
    let name : String
    let index : Int
}

final class SPIRVCompiler {
    enum CompilerError : Error {
        case spirvParseFailed(String)
        case compilerCreationFailed(String)
        case compilationFailed(String)
    }
    
    let context : SPIRVContext
    let file : SPIRVFile
    let compiler : spvc_compiler
    var currentEntryPoint : EntryPoint? = nil
    
    var shaderResources : spvc_resources? = nil
    
    init(file: SPIRVFile, context: SPIRVContext) throws {
        self.context = context
        self.file = file
        
        let spv = try Data(contentsOf: file.url)
        
        var ir : spvc_parsed_ir! = nil
        let _ = spv.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> spvc_result in
            return spvc_context_parse_spirv(context.spvContext, bytes.baseAddress?.assumingMemoryBound(to: SpvId.self), bytes.count / MemoryLayout<SpvId>.size, &ir)
        }
        guard ir != nil else { throw CompilerError.spirvParseFailed(context.lastErrorString) }
        
        var compiler : spvc_compiler! = nil
        spvc_context_create_compiler(context.spvContext, file.target.spvcBackend, ir, SPVC_CAPTURE_MODE_TAKE_OWNERSHIP, &compiler)
        
        guard compiler != nil else { throw CompilerError.compilerCreationFailed(context.lastErrorString) }
        self.compiler = compiler
    }
    
    func compiledSource() throws -> String {
        var source : UnsafePointer<CChar>! = nil
        let result = spvc_compiler_compile(self.compiler, &source)
        guard result == SPVC_SUCCESS else {
            throw CompilerError.compilationFailed(String(cString: spvc_context_get_last_error_string(self.context.spvContext)))
        }
        
        return String(cString: source)
    }
    
    func setEntryPoint(_ entryPoint: EntryPoint) -> Bool {
        let result = spvc_compiler_set_entry_point(self.compiler, entryPoint.name, entryPoint.type.executionModel)
        guard result == SPVC_SUCCESS else { return false }
        
        spvc_compiler_create_shader_resources(self.compiler, &self.shaderResources)
//        var activeSet : spvc_set! = nil
//        spvc_compiler_get_active_interface_variables(self.compiler, &activeSet)
//        spvc_compiler_create_shader_resources_for_active_variables(self.compiler, &self.shaderResources, activeSet)
        
        self.currentEntryPoint = entryPoint
        return true
    }
    
    var functionConstants : [FunctionConstant] {
        var specialisationConstants : UnsafePointer<spvc_specialization_constant>! = nil
        var specialisationConstantCount = 0
        
        spvc_compiler_get_specialization_constants(self.compiler, &specialisationConstants, &specialisationConstantCount)
        
        return (0..<specialisationConstantCount).map {
            FunctionConstant(constant: specialisationConstants[$0], compiler: self)
        }
    }
    
    var pushConstants : [PushConstant] {
        var reflectedResourceCount = 0
        var stagePushConstants : UnsafePointer<spvc_reflected_resource>! = nil
        spvc_resources_get_resource_list_for_type(self.shaderResources, SPVC_RESOURCE_TYPE_PUSH_CONSTANT, &stagePushConstants, &reflectedResourceCount)
        
        return (0..<reflectedResourceCount).map { i -> PushConstant in
            let constant = stagePushConstants[i]
            
            let name = constant.name.map { String(cString: $0) } ?? "pushConstants"
            let type = SPIRVType(compiler: self.compiler, typeId: constant.type_id)
            let range = 0..<type.size // FIXME: should query this from reflection using get_active_buffer_ranges
            return PushConstant(name: name, type: type, range: range)
        }
    }
    
    var attachments : [RenderTargetAttachment] {
        if self.currentEntryPoint?.type != .fragment {
            return []
        }
        
        var reflectedResources : UnsafePointer<spvc_reflected_resource>! = nil
        var reflectedResourceCount = 0
        spvc_resources_get_resource_list_for_type(self.shaderResources, SPVC_RESOURCE_TYPE_STAGE_OUTPUT, &reflectedResources, &reflectedResourceCount)
        // Behaviour: if there's only one SV_Target, emit 'main'
        // Otherwise, we're returning a struct, so use the struct variable names.
        
        return (0..<reflectedResourceCount).compactMap { i -> RenderTargetAttachment? in
            let resource = reflectedResources[i]
            let name = String(cString: resource.name)
            
            if !name.lowercased().contains("target") {
                return nil
            }
            
            let index = spvc_compiler_get_decoration(self.compiler, resource.id, SpvDecorationLocation)
            
            return RenderTargetAttachment(name: name, index: Int(index))
        }
    }
    
    var boundResources : [Resource] {
        
        var bindings : [Resource] = []
        
        var reflectedResources : UnsafePointer<spvc_reflected_resource>! = nil
        var reflectedResourceCount = 0
        
        let stage = self.currentEntryPoint!.type.stages
        
        spvc_resources_get_resource_list_for_type(self.shaderResources, SPVC_RESOURCE_TYPE_UNIFORM_BUFFER, &reflectedResources, &reflectedResourceCount)
        
        for i in 0..<reflectedResourceCount {
            bindings.append(Resource(compiler: self, resource: reflectedResources[i], type: .buffer, stage: stage, viewType: .uniformBuffer))
        }
        
        spvc_resources_get_resource_list_for_type(self.shaderResources, SPVC_RESOURCE_TYPE_STORAGE_BUFFER, &reflectedResources, &reflectedResourceCount)
        
        for i in 0..<reflectedResourceCount {
            bindings.append(Resource(compiler: self, resource: reflectedResources[i], type: .buffer, stage: stage, viewType: .storageBuffer))
        }
        
        spvc_resources_get_resource_list_for_type(self.shaderResources, SPVC_RESOURCE_TYPE_SEPARATE_IMAGE, &reflectedResources, &reflectedResourceCount)
        
        for i in 0..<reflectedResourceCount {
            bindings.append(Resource(compiler: self, resource: reflectedResources[i], type: .texture, stage: stage, viewType: .texture))
        }
        
        spvc_resources_get_resource_list_for_type(self.shaderResources, SPVC_RESOURCE_TYPE_STORAGE_IMAGE, &reflectedResources, &reflectedResourceCount)
        
        for i in 0..<reflectedResourceCount {
            bindings.append(Resource(compiler: self, resource: reflectedResources[i], type: .texture, stage: stage, viewType: .texture))
        }
        
        spvc_resources_get_resource_list_for_type(self.shaderResources, SPVC_RESOURCE_TYPE_SEPARATE_SAMPLERS, &reflectedResources, &reflectedResourceCount)
        
        for i in 0..<reflectedResourceCount {
            bindings.append(Resource(compiler: self, resource: reflectedResources[i], type: .sampler, stage: stage, viewType: .sampler))
        }
        
        return bindings
    }
}
