//
//  Caches.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 9/01/18.
//

#if canImport(Vulkan)
import Vulkan
import FrameGraphCExtras

final class VulkanStateCaches {
    let device: VulkanDevice
    let shaderLibrary : VulkanShaderLibrary
    
    private var vertexInputStates = [VertexDescriptor : VertexInputStateCreateInfo]()
    private var functionSpecialisationStates = [FunctionConstants : SpecialisationInfo]()
    private var currentPipelineReflection : VulkanPipelineReflection? = nil
    private var renderPipelines = [VulkanRenderPipelineDescriptor : VkPipeline?]()
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
                     subpass subpass: UInt32) -> VkPipeline? {
        if let pipeline = self.renderPipelines[pipelineDescriptor] {
            return pipeline
        }

        var pipeline : VkPipeline? = nil

        // TODO: investigate pipeline derivatives within a render pass to optimise pipeline switching.
        pipelineDescriptor.withVulkanPipelineCreateInfo(renderPass: renderPass, subpass: subpass, stateCaches: self) { createInfo in
            vkCreateGraphicsPipelines(self.device.vkDevice, self.pipelineCache, 1, &createInfo, nil, &pipeline).check()
        }
        self.renderPipelines[pipelineDescriptor] = pipeline

        return pipeline
    }

    public subscript(pipelineDescriptor: VulkanComputePipelineDescriptor, pipelineReflection pipelineReflection: VulkanPipelineReflection) -> VkPipeline? {
        if let pipeline = self.computePipelines[pipelineDescriptor] {
            return pipeline
        }

        var pipeline : VkPipeline? = nil

        // TODO: investigate pipeline derivatives within a render pass to optimise pipeline switching.
        pipelineDescriptor.withVulkanPipelineCreateInfo(pipelineReflection: pipelineReflection, stateCaches: self) { createInfo in
            vkCreateComputePipelines(self.device.vkDevice, self.pipelineCache, 1, &createInfo, nil, &pipeline).check()
        }
        
        self.computePipelines[pipelineDescriptor] = pipeline

        return pipeline
    }


    public subscript(functionConstants: FunctionConstants?, pipelineReflection pipelineReflection: VulkanPipelineReflection) -> SpecialisationInfo? {
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
        let descriptor = VertexDescriptor()
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
    
    public func reflection(for descriptor: RenderPipelineDescriptor, renderTarget: RenderTargetDescriptor) -> VulkanPipelineReflection {
        return self.shaderLibrary.reflection(for: .graphics(vertexShader: descriptor.vertexFunction!, fragmentShader: descriptor.fragmentFunction))
    }
    
    public func reflection(for descriptor: ComputePipelineDescriptor) -> VulkanPipelineReflection {
        return self.shaderLibrary.reflection(for: .compute(descriptor.function))
    }
}

#endif // canImport(Vulkan)
