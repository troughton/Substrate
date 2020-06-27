//
//  RenderCommandEncoder.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 8/01/18.
//

#if canImport(Vulkan)
import Vulkan
import FrameGraphCExtras
import FrameGraphUtilities

struct DynamicStateCreateInfo {
    let buffer : FixedSizeBuffer<VkDynamicState>
    var info : VkPipelineDynamicStateCreateInfo
    
    init(states: FixedSizeBuffer<VkDynamicState>) {
        self.buffer = states
        self.info = VkPipelineDynamicStateCreateInfo()
        self.info.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO
        self.info.dynamicStateCount = UInt32(states.count)
        self.info.pDynamicStates = UnsafePointer(states.buffer)
    }
    
    static let `default` = DynamicStateCreateInfo(states: [VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR, VK_DYNAMIC_STATE_DEPTH_BIAS, VK_DYNAMIC_STATE_BLEND_CONSTANTS, VK_DYNAMIC_STATE_STENCIL_REFERENCE])
}

struct VulkanRenderPipelineDescriptor : Hashable {
    var descriptor : RenderPipelineDescriptor
    var depthStencil : DepthStencilDescriptor?
    var primitiveType: PrimitiveType
    var cullMode : CullMode
    var depthClipMode : DepthClipMode
    var frontFaceWinding : Winding
    var layout : VkPipelineLayout

    func withVulkanPipelineCreateInfo(renderPass: VulkanRenderPass, subpass: UInt32, renderTargetDescriptor: RenderTargetDescriptor, pipelineReflection: VulkanPipelineReflection, stateCaches: VulkanStateCaches, _ withInfo: (inout VkGraphicsPipelineCreateInfo) -> Void) {
        
        var functionNames = [FixedSizeBuffer<CChar>]()
        
        let specialisationInfo = stateCaches[self.descriptor.functionConstants, pipelineReflection: pipelineReflection]
        let specialisationInfoPtr = specialisationInfo == nil ? nil : escapingPointer(to: &specialisationInfo!.info)
        
        var stages = [VkPipelineShaderStageCreateInfo]()
        
        for (name, stageFlag) in [(self.descriptor.vertexFunction, VK_SHADER_STAGE_VERTEX_BIT), (self.descriptor.fragmentFunction, VK_SHADER_STAGE_FRAGMENT_BIT)] {
            guard let name = name else { continue }
            let module = stateCaches.shaderLibrary.moduleForFunction(name)!
            
            let entryPoint = module.entryPointForFunction(named: name)
            let cEntryPoint = entryPoint.withCString { (cString) -> FixedSizeBuffer<CChar> in
                let buffer = FixedSizeBuffer(capacity: name.utf8.count + 1, defaultValue: 0 as CChar)
                buffer.buffer.assign(from: cString, count: name.utf8.count)
                return buffer
            }
            
            functionNames.append(cEntryPoint)
            
            var stage = VkPipelineShaderStageCreateInfo()
            stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO
            stage.pName = UnsafePointer(cEntryPoint.buffer)
            stage.stage = stageFlag
            stage.pSpecializationInfo = specialisationInfoPtr
            stage.module = module.vkModule
            stages.append(stage)
        }
        
        let vertexInputState = stateCaches[self.descriptor.vertexDescriptor]
        
        var inputAssemblyState = VkPipelineInputAssemblyStateCreateInfo()
        inputAssemblyState.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
        inputAssemblyState.primitiveRestartEnable = true
        inputAssemblyState.topology = VkPrimitiveTopology(self.primitiveType)
        
        var rasterisationState = VkPipelineRasterizationStateCreateInfo()
        rasterisationState.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO
        rasterisationState.depthClampEnable = VkBool32(self.depthClipMode == .clamp)
        rasterisationState.rasterizerDiscardEnable = VkBool32(!self.descriptor.isRasterizationEnabled)
        rasterisationState.polygonMode = VK_POLYGON_MODE_FILL
        rasterisationState.cullMode = VkCullModeFlags(self.cullMode)
        rasterisationState.frontFace = VkFrontFace(self.frontFaceWinding)
        rasterisationState.depthBiasEnable = true
        rasterisationState.depthBiasConstantFactor = 0
        rasterisationState.depthBiasClamp = 0.0
        rasterisationState.depthBiasSlopeFactor = 0
        rasterisationState.lineWidth = 1.0
        
        var multisampleState = VkPipelineMultisampleStateCreateInfo(self.descriptor, sampleCount: 1)
        multisampleState.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
        multisampleState.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT
        multisampleState.sampleShadingEnable = false
        multisampleState.alphaToOneEnable = VkBool32(self.descriptor.isAlphaToOneEnabled)
        multisampleState.alphaToCoverageEnable = VkBool32(self.descriptor.isAlphaToCoverageEnabled)
        
        let depthStencilState : VkPipelineDepthStencilStateCreateInfo
        if let depthStencil = self.depthStencil {
            depthStencilState = VkPipelineDepthStencilStateCreateInfo(descriptor: depthStencil, referenceValue: 0)
        } else {
            var dsState = VkPipelineDepthStencilStateCreateInfo()
            dsState.sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO
            dsState.depthTestEnable = false
            dsState.depthWriteEnable = false
            depthStencilState = dsState
        }
        
        let colorBlendState = ColorBlendStateCreateInfo(descriptor: self.descriptor, renderTargetDescriptor: renderTargetDescriptor)
        
        let dynamicState = DynamicStateCreateInfo.default
        
        var viewportState = VkPipelineViewportStateCreateInfo() // overridden by dynamic state.
        viewportState.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO
        viewportState.viewportCount = 1
        viewportState.scissorCount = 1
        
        var tesselationState = VkPipelineTessellationStateCreateInfo()
        tesselationState.sType = VK_STRUCTURE_TYPE_PIPELINE_TESSELLATION_STATE_CREATE_INFO
        
        var states = (vertexInputState, inputAssemblyState, rasterisationState, multisampleState, depthStencilState, colorBlendState, dynamicState, tesselationState, viewportState)
        withExtendedLifetime(states) {
            stages.withUnsafeBufferPointer { stages in
                var pipelineInfo = VkGraphicsPipelineCreateInfo()
                pipelineInfo.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO
                
                pipelineInfo.stageCount = UInt32(stages.count)
                pipelineInfo.pStages = stages.baseAddress
                
                pipelineInfo.layout = self.layout
                
                pipelineInfo.pVertexInputState = escapingPointer(to: &states.0.info)
                pipelineInfo.pInputAssemblyState = escapingPointer(to: &states.1)
                pipelineInfo.pRasterizationState = escapingPointer(to: &states.2)
                pipelineInfo.pMultisampleState = escapingPointer(to: &states.3)
                pipelineInfo.pDepthStencilState = escapingPointer(to: &states.4)
                pipelineInfo.pColorBlendState = escapingPointer(to: &states.5.info)
                pipelineInfo.pDynamicState = escapingPointer(to: &states.6.info)
                pipelineInfo.pTessellationState = escapingPointer(to: &states.7)
                pipelineInfo.pViewportState = escapingPointer(to: &states.8)
            
                pipelineInfo.renderPass = renderPass.vkPass
                pipelineInfo.subpass = subpass
                
                withInfo(&pipelineInfo)
            }
            
        }
    }
}

class VulkanRenderCommandEncoder : VulkanResourceBindingCommandEncoder {
    
    class PipelineState {
        let shaderLibrary : VulkanShaderLibrary
        var hasChanged = true
        
        init(shaderLibrary: VulkanShaderLibrary) {
            self.shaderLibrary = shaderLibrary
        }
        
        var descriptor : RenderPipelineDescriptor! = nil {
            didSet {
                
                let key = PipelineLayoutKey.graphics(vertexShader: descriptor.vertexFunction!, fragmentShader: descriptor.fragmentFunction)
                self.pipelineReflection = shaderLibrary.reflection(for: key)
                
                _layout = nil // FIXME: we also need to invalidate the layout in the more subtle case where the descriptor layout changes.
                
                self.hasChanged = true
            }
        }
        
        var pipelineReflection : VulkanPipelineReflection! = nil
        
        var subpass : Int = 0 {
            didSet {
                self.hasChanged = true
            }
        }
        
        var depthStencil : DepthStencilDescriptor? = nil {
            didSet {
                self.hasChanged = true
            }
        }
        
        var primitiveType: PrimitiveType = .triangle {
            didSet {
                if oldValue != self.primitiveType {
                    self.hasChanged = true
                }
            }
        }
        
        var cullMode : CullMode = .none {
            didSet {
                if oldValue != self.cullMode {
                    self.hasChanged = true
                }
            }
        }
        
        var depthClipMode : DepthClipMode = .clip {
            didSet {
                if oldValue != self.depthClipMode {
                    self.hasChanged = true
                }
            }
        }
        
        var frontFaceWinding : Winding = .clockwise {
            didSet {
                if oldValue != self.frontFaceWinding {
                    self.hasChanged = true
                }
            }
        }
        
        private var _layout : VkPipelineLayout! = nil
        
        var layout : VkPipelineLayout {
            if let layout = _layout {
                return layout
            }
            _layout = self.shaderLibrary.pipelineLayout(for: .graphics(vertexShader: descriptor.vertexFunction!, fragmentShader: descriptor.fragmentFunction))
            return _layout
        }

        var vulkanPipelineDescriptor : VulkanRenderPipelineDescriptor {
            return VulkanRenderPipelineDescriptor(descriptor: self.descriptor,
                                                  depthStencil: self.depthStencil,
                                                  primitiveType: self.primitiveType,
                                                  cullMode: self.cullMode,
                                                  depthClipMode: self.depthClipMode,
                                                  frontFaceWinding: self.frontFaceWinding,
                                                  layout: self.layout)
        }
        
    }
    
    let device : VulkanDevice
    let stateCaches : VulkanStateCaches
    let commandBufferResources : VulkanCommandBuffer
    let renderTarget : VulkanRenderTargetDescriptor
    let resourceMap: FrameResourceMap<VulkanBackend>
    
    var renderPass : VulkanRenderPass! = nil
    var currentDrawRenderPass : DrawRenderPass! = nil
    var pipelineState : PipelineState! = nil
    
    var boundVertexBuffers = [Buffer?](repeating: nil, count: 8)
    
    public init?(device: VulkanDevice, renderTarget: VulkanRenderTargetDescriptor, commandBufferResources: VulkanCommandBuffer, shaderLibrary: VulkanShaderLibrary, caches: VulkanStateCaches, resourceMap: FrameResourceMap<VulkanBackend>) {
        self.device = device
        self.renderTarget = renderTarget
        self.commandBufferResources = commandBufferResources
        self.stateCaches = caches
        self.resourceMap = resourceMap
        
        self.pipelineState = PipelineState(shaderLibrary: shaderLibrary)
    }
    
    var queueFamily: QueueFamily {
        return .graphics
    }
    
    var bindPoint: VkPipelineBindPoint {
        return VK_PIPELINE_BIND_POINT_GRAPHICS
    }
    
    var commandBuffer : VkCommandBuffer {
        return self.commandBufferResources.commandBuffer
    }
    
    var pipelineLayout: VkPipelineLayout {
        return self.pipelineState.layout
    }
    
    var pipelineReflection: VulkanPipelineReflection {
        return self.pipelineState.pipelineReflection
    }
    
    func prepareToDraw() {
        if self.pipelineState.hasChanged {
            defer {
                self.pipelineState.hasChanged = false
            }

            let pipeline = self.stateCaches[self.pipelineState.vulkanPipelineDescriptor, 
                                            renderPass: self.renderPass, 
                                            subpass: UInt32(self.pipelineState.subpass), 
                                            renderTargetDescriptor: self.currentDrawRenderPass.renderTargetDescriptor,
                                            pipelineReflection: self.pipelineState.pipelineReflection]
            vkCmdBindPipeline(self.commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline)
        }
    }
    
    private func beginPass(_ pass: RenderPassRecord) throws {
        let drawPass = pass.pass as! DrawRenderPass
        self.currentDrawRenderPass = drawPass       
        self.pipelineState.hasChanged = true
        
        let renderTargetSize = renderTarget.descriptor.size
        let renderTargetRect = VkRect2D(offset: VkOffset2D(x: 0, y: 0), extent: VkExtent2D(width: UInt32(renderTargetSize.width), height: UInt32(renderTargetSize.height)))
        
        if pass === self.renderTarget.renderPasses.first { // Set up the render target.
            
            self.renderPass = VulkanRenderPass(device: self.device, descriptor: renderTarget)
            commandBufferResources.renderPasses.append(renderPass)
            let framebuffer = try VulkanFramebuffer(descriptor: renderTarget, renderPass: renderPass.vkPass, device: self.device, resourceMap: self.resourceMap)
            commandBufferResources.framebuffers.append(framebuffer)
            
            var clearValues = [VkClearValue]()
            if renderTarget.descriptor.depthAttachment != nil || renderTarget.descriptor.stencilAttachment != nil {
                clearValues.append(VkClearValue(depthStencil: VkClearDepthStencilValue(depth: Float(renderTarget.clearDepth), stencil: renderTarget.clearStencil)))
            }
            
            for clearColor in self.renderTarget.clearColors {
                clearValues.append(VkClearValue(color: clearColor))
            }
            
            clearValues.withUnsafeBufferPointer { clearValues in
                var beginInfo = VkRenderPassBeginInfo()
                beginInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO
                beginInfo.renderPass = renderPass.vkPass
                beginInfo.renderArea = renderTargetRect
                beginInfo.framebuffer = framebuffer.framebuffer
                beginInfo.clearValueCount = UInt32(clearValues.count)
                beginInfo.pClearValues = clearValues.baseAddress
                
                vkCmdBeginRenderPass(self.commandBuffer, &beginInfo, VK_SUBPASS_CONTENTS_INLINE)
            }
            
        }
        
        // TODO: We can infer which properties need to be dynamic and avoid this step.
        // For now, assume that all properties that are dynamic in Metal should also be
        // dynamic in Vulkan, and set sensible defaults.
        
        // See: https://www.khronos.org/registry/vulkan/specs/1.0/man/html/VkDynamicState.html
        
        var viewport = VkViewport(x: 0, y: Float(renderTargetRect.extent.height), width: Float(renderTargetRect.extent.width), height: -Float(renderTargetRect.extent.height), minDepth: 0, maxDepth: 1)
        vkCmdSetViewport(self.commandBuffer, 0, 1, &viewport)
        
        var scissor = renderTargetRect
        vkCmdSetScissor(self.commandBuffer, 0, 1, &scissor)
        
        vkCmdSetStencilReference(self.commandBuffer, VkStencilFaceFlags(VK_STENCIL_FRONT_AND_BACK), 0)

        vkCmdSetDepthBias(self.commandBuffer, 0.0, 0.0, 0.0)
    }
    
    /// Ends a pass and returns whether the command encoder is still valid.
    private func endPass(_ pass: RenderPassRecord) -> Bool {
        if pass === self.renderTarget.renderPasses.last {
            vkCmdEndRenderPass(self.commandBuffer)

            for (texture, layout) in self.renderTarget.finalLayouts {
                self.resourceMap[texture].image.layout = layout
            }

            return false
        } else if self.renderTarget.subpassForPassIndex(pass.passIndex) !== self.renderTarget.subpassForPassIndex(pass.passIndex + 1) {
            vkCmdNextSubpass(self.commandBuffer, VK_SUBPASS_CONTENTS_INLINE)
            self.pipelineState.subpass += 1
        }
        return true
    }
    
    
    func executePass(_ pass: RenderPassRecord, resourceCommands: [CompactedResourceCommand<VulkanCompactedResourceCommandType>], passRenderTarget: RenderTargetDescriptor) {
        try! self.beginPass(pass)
        defer { _ = self.endPass(pass) }
        
        var resourceCommandIndex = resourceCommands.binarySearch { $0.index < pass.commandRange!.lowerBound }
       
        // FIXME: need to insert this logic:
//        if passRenderTarget.depthAttachment == nil && passRenderTarget.stencilAttachment == nil, (self.renderPassDescriptor.depthAttachment.texture != nil || self.renderPassDescriptor.stencilAttachment.texture != nil) {
//            encoder.setDepthStencilState(stateCaches.defaultDepthState) // The render pass unexpectedly has a depth/stencil attachment, so make sure the depth stencil state is set to the default.
//        }
        
        for (i, command) in zip(pass.commandRange!, pass.commands) {
            self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .before, commandIndex: i)
            self.executeCommand(command)
            self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .after, commandIndex: i)
        }
    }
    
    func executeCommand(_ command: FrameGraphCommand) {
        switch command {
        case .clearRenderTargets:
            break

        case .insertDebugSignpost(_):
            break
            
        case .setLabel(_):
            break
            
        case .pushDebugGroup(_):
            break
            
        case .popDebugGroup:
            break

        case .setVertexBuffer(let args):
            self.boundVertexBuffers[Int(args.pointee.index)] = args.pointee.buffer
            guard let handle = args.pointee.buffer else { return }
            let buffer = self.resourceMap[handle]
            self.commandBufferResources.buffers.append(buffer.buffer)

            var vkBuffer = buffer.buffer.vkBuffer as VkBuffer?
            var offset = VkDeviceSize(args.pointee.offset) + VkDeviceSize(buffer.offset)
            vkCmdBindVertexBuffers(self.commandBuffer, args.pointee.index, 1, &vkBuffer, &offset)

        case .setVertexBufferOffset(let offset, let index):
            let handle = self.boundVertexBuffers[Int(index)]!
            let buffer = self.resourceMap[handle]

            var vkBuffer = buffer.buffer.vkBuffer as VkBuffer?
            var offset = VkDeviceSize(offset) + VkDeviceSize(buffer.offset)
            vkCmdBindVertexBuffers(self.commandBuffer, index, 1, &vkBuffer, &offset)
            
        case .setArgumentBuffer(let args):
            let bindingPath = args.pointee.bindingPath
            
            let argumentBuffer = args.pointee.argumentBuffer
            let vkArgumentBuffer = resourceMap[argumentBuffer]

            self.commandBufferResources.argumentBuffers.append(vkArgumentBuffer)

            var set : VkDescriptorSet? = vkArgumentBuffer.descriptorSet
            vkCmdBindDescriptorSets(self.commandBuffer, self.bindPoint, self.pipelineLayout, bindingPath.set, 1, &set, 0, nil)

        case .setBytes(let args):
            let bindingPath = args.pointee.bindingPath
            let bytes = args.pointee.bytes
            let length = args.pointee.length
            
            let resourceInfo = self.pipelineReflection[bindingPath]
            
            switch resourceInfo.type {
            case .pushConstantBuffer:
                assert(resourceInfo.bindingRange.count == length, "The push constant size and the setBytes length must match.")
                vkCmdPushConstants(self.commandBuffer, self.pipelineLayout, VkShaderStageFlags(resourceInfo.accessedStages), resourceInfo.bindingRange.lowerBound, length, bytes)
                
            default:
                fatalError("Need to implement VK_EXT_inline_uniform_block or else fall back to a temporary staging buffer")
            }
            
        case .setBufferOffset(let args):
            fatalError("Currently unimplemented on Vulkan; should use vkCmdPushDescriptorSetKHR when implemented.")
            
        case .setBuffer(let args):
            fatalError("Currently unimplemented on Vulkan; should use vkCmdPushDescriptorSetKHR when implemented.")
            
        case .setTexture(let args):
            fatalError("Currently unimplemented on Vulkan; should use vkCmdPushDescriptorSetKHR when implemented.")
            
        case .setSamplerState(let args):
            fatalError("Currently unimplemented on Vulkan; should use vkCmdPushDescriptorSetKHR when implemented.")
            
        case .setRenderPipelineDescriptor(let descriptorPtr):
            let descriptor = descriptorPtr.takeUnretainedValue().value
            self.pipelineState.descriptor = descriptor
            
        case .drawPrimitives(let args):
            self.pipelineState.primitiveType = args.pointee.primitiveType
            self.prepareToDraw()
            
            vkCmdDraw(self.commandBuffer, args.pointee.vertexCount, args.pointee.instanceCount, args.pointee.vertexStart, args.pointee.baseInstance)
            
        case .drawIndexedPrimitives(let args):
            self.pipelineState.primitiveType = args.pointee.primitiveType
            
            let buffer = resourceMap[args.pointee.indexBuffer]
            vkCmdBindIndexBuffer(self.commandBuffer, buffer.buffer.vkBuffer, VkDeviceSize(args.pointee.indexBufferOffset) + VkDeviceSize(buffer.offset), VkIndexType(args.pointee.indexType))
            
            self.prepareToDraw()
            
            vkCmdDrawIndexed(self.commandBuffer, args.pointee.indexCount, args.pointee.instanceCount, 0, args.pointee.baseVertex, args.pointee.baseInstance)
            
        case .setViewport(let viewportPtr):
            var viewport = VkViewport(viewportPtr.pointee)
            vkCmdSetViewport(self.commandBuffer, 0, 1, &viewport)
            
        case .setFrontFacing(let winding):
            self.pipelineState.frontFaceWinding = winding
            
        case .setCullMode(let cullMode):
            self.pipelineState.cullMode = cullMode
            
        case .setDepthStencilDescriptor(let descriptorPtr):
            self.pipelineState.depthStencil = descriptorPtr.takeUnretainedValue().value
            
        case .setScissorRect(let scissorPtr):
            var scissor = VkRect2D(scissorPtr.pointee)
            vkCmdSetScissor(self.commandBuffer, 0, 1, &scissor)
            
        case .setDepthClipMode(let mode):
            self.pipelineState.depthClipMode = mode
            
        case .setDepthBias(let args):
            vkCmdSetDepthBias(self.commandBuffer, args.pointee.depthBias, args.pointee.clamp, args.pointee.slopeScale)
            
        case .setStencilReferenceValue(let value):
            vkCmdSetStencilReference(self.commandBuffer, VkStencilFaceFlags(VK_STENCIL_FRONT_AND_BACK), value)
            
        case .setStencilReferenceValues(let front, let back):
            vkCmdSetStencilReference(self.commandBuffer, VkStencilFaceFlags(VK_STENCIL_FACE_FRONT_BIT), front)
            vkCmdSetStencilReference(self.commandBuffer, VkStencilFaceFlags(VK_STENCIL_FACE_BACK_BIT), back)
            
        default:
            fatalError("Unhandled command \(command)")
        }
    }
}

#endif // canImport(Vulkan)
