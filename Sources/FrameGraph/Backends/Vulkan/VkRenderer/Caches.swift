//
//  Caches.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 9/01/18.
//

import RenderAPI
import CVkRenderer

final class StateCaches {

    private struct RenderPipelineCacheKey : Hashable {
        var pipelineDescriptor : VulkanRenderPipelineDescriptor
        var renderTargetDescriptor : RenderTargetDescriptor
    }

    let device: VulkanDevice
    let shaderLibrary : VulkanShaderLibrary
    
    private var vertexInputStates = [VertexDescriptor : VertexInputStateCreateInfo]()
    private var functionSpecialisationStates = [AnyFunctionConstants : SpecialisationInfo]()
    private var samplers = [SamplerDescriptor : VkSampler]()
    private var currentPipelineReflection : PipelineReflection? = nil
    private var renderPipelines = [RenderPipelineCacheKey : VkPipeline?]()
    private var computePipelines = [VulkanComputePipelineDescriptor : VkPipeline?]()
    
    public let pipelineCache : VkPipelineCache
    
    public init(device: VulkanDevice, shaderLibrary: VulkanShaderLibrary) {
        self.device = device
        
        do {
            var cacheCreateInfo = VkPipelineCacheCreateInfo()
            cacheCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO
            
            var cache : VkPipelineCache? = nil
            vkCreatePipelineCache(self.device.vkDevice, &cacheCreateInfo, nil, &cache)
            
            self.pipelineCache = cache!
        }
        
        self.shaderLibrary = shaderLibrary
    }
    
    deinit {
        vkDestroyPipelineCache(self.device.vkDevice, self.pipelineCache, nil)
    }
    
    public subscript(pipelineDescriptor: VulkanRenderPipelineDescriptor, 
                     renderPass renderPass: VulkanRenderPass, 
                     subpass subpass: UInt32,
                     renderTargetDescriptor renderTargetDescriptor: RenderTargetDescriptor,
                     pipelineReflection pipelineReflection: PipelineReflection) -> VkPipeline? {
        let cacheKey = RenderPipelineCacheKey(pipelineDescriptor: pipelineDescriptor, renderTargetDescriptor: renderTargetDescriptor)
        if let pipeline = self.renderPipelines[cacheKey] {
            return pipeline
        }

        var pipeline : VkPipeline? = nil

        // TODO: investigate pipeline derivatives within a render pass to optimise pipeline switching.
        pipelineDescriptor.withVulkanPipelineCreateInfo(renderPass: renderPass, subpass: subpass, renderTargetDescriptor: renderTargetDescriptor, pipelineReflection: pipelineReflection, stateCaches: self) { createInfo in
            vkCreateGraphicsPipelines(self.device.vkDevice, self.pipelineCache, 1, &createInfo, nil, &pipeline)
        }
        self.renderPipelines[cacheKey] = pipeline

        return pipeline
    }

    public subscript(pipelineDescriptor: VulkanComputePipelineDescriptor, pipelineReflection pipelineReflection: PipelineReflection) -> VkPipeline? {
        if let pipeline = self.computePipelines[pipelineDescriptor] {
            return pipeline
        }

        var pipeline : VkPipeline? = nil

        // TODO: investigate pipeline derivatives within a render pass to optimise pipeline switching.
        pipelineDescriptor.withVulkanPipelineCreateInfo(pipelineReflection: pipelineReflection, stateCaches: self) { createInfo in
            vkCreateComputePipelines(self.device.vkDevice, self.pipelineCache, 1, &createInfo, nil, &pipeline)
        }
        
        self.computePipelines[pipelineDescriptor] = pipeline

        return pipeline
    }


    public subscript(functionConstants: AnyFunctionConstants?, pipelineReflection pipelineReflection: PipelineReflection) -> SpecialisationInfo? {
        guard let functionConstants = functionConstants else {
            return nil
        }
        
        if let state = self.functionSpecialisationStates[functionConstants] {
            return state
        }
        
        let info = SpecialisationInfo(functionConstants, constantIndices: pipelineReflection.specialisations)
        self.functionSpecialisationStates[functionConstants] = info
        
        return info
    }
    
    private let defaultVertexInputStateCreateInfo : VertexInputStateCreateInfo = {
        var descriptor = VertexDescriptor()
        descriptor.attributes[0].format = .float4
        descriptor.layouts[0].stepFunction = .perVertex
        descriptor.layouts[0].stride = 4 * MemoryLayout<Float>.size
        return VertexInputStateCreateInfo(descriptor: descriptor)
    }()
    
    public subscript(descriptor: VertexDescriptor?) -> VertexInputStateCreateInfo {
        guard let descriptor = descriptor else {
            return self.defaultVertexInputStateCreateInfo
        }
        
        if let state = self.vertexInputStates[descriptor] {
            return state
        }
        
        let info = VertexInputStateCreateInfo(descriptor: descriptor)
        self.vertexInputStates[descriptor] = info
        return info
    }
    
    public subscript(samplerDescriptor: SamplerDescriptor) -> VkSampler {
        if let sampler = self.samplers[samplerDescriptor] {
            return sampler
        }
        
        var samplerCreateInfo = VkSamplerCreateInfo(descriptor: samplerDescriptor)
        
        var sampler : VkSampler? = nil
        vkCreateSampler(self.device.vkDevice, &samplerCreateInfo, nil, &sampler)
        
        self.samplers[samplerDescriptor] = sampler
        
        return sampler!
    }
    
    public func setReflectionRenderPipeline(descriptor: RenderPipelineDescriptor, renderTarget: RenderTargetDescriptor) {
        self.currentPipelineReflection = self.shaderLibrary.reflection(for: .graphics(vertexShader: descriptor.vertexFunction!, fragmentShader: descriptor.fragmentFunction))
    }
    
    public func setReflectionComputePipeline(descriptor: ComputePipelineDescriptor) {
        self.currentPipelineReflection = self.shaderLibrary.reflection(for: .compute(descriptor.function))
    }
    
    public func bindingPath(argumentName: String, arrayIndex: Int) -> ResourceBindingPath? {
        for resource in self.currentPipelineReflection!.resources.values {
            if resource.name == argumentName {
                var bindingPath = resource.bindingPath
                bindingPath.arrayIndex = UInt32(arrayIndex)
                return ResourceBindingPath(bindingPath)
            }
        }
        return nil
    }

    public func bindingPath(argumentBuffer: ArgumentBuffer, argumentName: String) -> ResourceBindingPath? {
        
        // NOTE: There's currently no error checking that the argument buffer contents
        // aren't spread across multiple sets.

        if let (firstBoundPath, _) = argumentBuffer.bindings.first {
            let vulkanPath = VulkanResourceBindingPath(firstBoundPath)
            return ResourceBindingPath(
                VulkanResourceBindingPath(argumentBuffer: vulkanPath.set)
            )
        }

        for (pendingKey, _, _) in argumentBuffer.enqueuedBindings {
            if let path = pendingKey.computedBindingPath {
                let vulkanPath = VulkanResourceBindingPath(path)
                return ResourceBindingPath(
                    VulkanResourceBindingPath(argumentBuffer: vulkanPath.set)
                )
            }
        }

        return nil
    }
    
    public func argumentReflection(at path: ResourceBindingPath) -> ArgumentReflection? {
        let vulkanPath = VulkanResourceBindingPath(path)
        if let resource = self.currentPipelineReflection!.resources[vulkanPath] {
            return ArgumentReflection(resource)
        }
        return nil
    }
}


