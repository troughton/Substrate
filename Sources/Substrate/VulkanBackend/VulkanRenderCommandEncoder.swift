//
//  RenderCommandEncoder.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 8/01/18.
//

#if canImport(Vulkan)
import Vulkan
@_implementationOnly import SubstrateCExtras
import SubstrateUtilities

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
    
    //
    static let `default` = DynamicStateCreateInfo(states: [VK_DYNAMIC_STATE_VIEWPORT,
                                                           VK_DYNAMIC_STATE_SCISSOR,
                                                           VK_DYNAMIC_STATE_DEPTH_BIAS,
                                                           VK_DYNAMIC_STATE_BLEND_CONSTANTS,
                                                           VK_DYNAMIC_STATE_STENCIL_REFERENCE,
                                                           
                                                           VK_DYNAMIC_STATE_CULL_MODE_EXT,
                                                           VK_DYNAMIC_STATE_FRONT_FACE_EXT,
                                                           VK_DYNAMIC_STATE_PRIMITIVE_TOPOLOGY_EXT,
                                                           VK_DYNAMIC_STATE_PRIMITIVE_RESTART_ENABLE_EXT,
//                                                           VK_DYNAMIC_STATE_DEPTH_TEST_ENABLE_EXT,
//                                                           VK_DYNAMIC_STATE_DEPTH_WRITE_ENABLE_EXT,
//                                                           VK_DYNAMIC_STATE_DEPTH_COMPARE_OP_EXT,
//                                                           VK_DYNAMIC_STATE_STENCIL_TEST_ENABLE_EXT,
//                                                           VK_DYNAMIC_STATE_STENCIL_OP_EXT,
    ])
}

struct VulkanRenderPipelineDescriptor : Hashable {

    let shaderLibrary : VulkanShaderLibrary
    let compatibleRenderPass: VulkanCompatibleRenderPass

    var hasChanged: Bool = false
    var pipelineReflection : VulkanPipelineReflection! = nil

    var descriptor : RenderPipelineDescriptor! = nil { 
        didSet { 
            let key = PipelineLayoutKey.graphics(vertexShader: descriptor.vertexFunction.name, fragmentShader: descriptor.fragmentFunction.name)
            self.pipelineReflection = shaderLibrary.reflection(for: key)
            self.layout = self.shaderLibrary.pipelineLayout(for: .graphics(vertexShader: descriptor.vertexFunction.name, fragmentShader: descriptor.fragmentFunction.name))
            self.hasChanged = true 
        } 
    }

    var primitiveType: PrimitiveType? = nil // Triangles, lines, or points; the exact subtype is set dynamically.
    var depthStencil : DepthStencilDescriptor? = nil { didSet { self.hasChanged = hasChanged || depthStencil != oldValue } }
    var layout: VkPipelineLayout! = nil { didSet { self.hasChanged = hasChanged || layout != oldValue } }

    var subpassIndex: Int = 0 { didSet { self.hasChanged = hasChanged || subpassIndex != oldValue } }

    init(shaderLibrary: VulkanShaderLibrary, compatibleRenderPass: VulkanCompatibleRenderPass) {
        self.shaderLibrary = shaderLibrary
        self.compatibleRenderPass = compatibleRenderPass
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(self.descriptor)
        hasher.combine(self.depthStencil)
        hasher.combine(self.layout)

        hasher.combine(self.subpassIndex)
        hasher.combine(self.compatibleRenderPass)
    }

    static func ==(lhs: VulkanRenderPipelineDescriptor, rhs: VulkanRenderPipelineDescriptor) -> Bool {
        guard lhs.descriptor == rhs.descriptor else { return false }
        guard lhs.primitiveType == rhs.primitiveType else { return false }
        guard lhs.layout == rhs.layout else { return false }
        guard lhs.subpassIndex == rhs.subpassIndex else { return false }

        guard lhs.compatibleRenderPass == rhs.compatibleRenderPass else {
            return false
        }

        return true
    }

    func withVulkanPipelineCreateInfo(renderPass: VulkanRenderPass, stateCaches: VulkanStateCaches, _ withInfo: (inout VkGraphicsPipelineCreateInfo) -> Void) {
        
        var functionNames = [FixedSizeBuffer<CChar>]()
        
        
        var stages = [VkPipelineShaderStageCreateInfo]()
        
        for (function, stageFlag) in [(self.descriptor.vertexFunction, VK_SHADER_STAGE_VERTEX_BIT), (self.descriptor.fragmentFunction, VK_SHADER_STAGE_FRAGMENT_BIT)] {
            let name = function.name
            guard !name.isEmpty else { continue }
            let module = stateCaches.shaderLibrary.moduleForFunction(name)!
            
            let specialisationInfo = stateCaches[function.constants, pipelineReflection: pipelineReflection]
            let specialisationInfoPtr = specialisationInfo == nil ? nil : escapingPointer(to: &specialisationInfo!.info)
            
            let entryPoint = module.entryPointForFunction(named: name)
            let cEntryPoint = entryPoint.withCString { (cString) -> FixedSizeBuffer<CChar> in
                let buffer = FixedSizeBuffer(capacity: name.utf8.count + 1, defaultValue: 0 as CChar)
                buffer.buffer.update(from: cString, count: name.utf8.count)
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
        inputAssemblyState.topology = VkPrimitiveTopology(self.primitiveType)
        
        var rasterisationState = VkPipelineRasterizationStateCreateInfo()
        rasterisationState.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO
        rasterisationState.depthClampEnable = VkBool32(self.depthStencil?.depthClipMode == .clamp)
        rasterisationState.rasterizerDiscardEnable = VkBool32(!self.descriptor.isRasterizationEnabled)
        rasterisationState.polygonMode = VkPolygonMode(self.descriptor.fillMode)
        rasterisationState.depthBiasEnable = true
        rasterisationState.depthBiasConstantFactor = 0
        rasterisationState.depthBiasClamp = 0.0
        rasterisationState.depthBiasSlopeFactor = 0
        rasterisationState.lineWidth = 1.0
        
        let sampleCount = self.compatibleRenderPass.attachments[0].sampleCount
        let multisampleState = VkPipelineMultisampleStateCreateInfo(self.descriptor, sampleCount: sampleCount)
        
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
        
        let colorBlendState = ColorBlendStateCreateInfo(descriptor: self.descriptor, colorAttachmentIndices: self.compatibleRenderPass.subpasses[self.subpassIndex].colorAttachmentIndices)
        
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
                pipelineInfo.subpass = UInt32(self.subpassIndex)
                
                withInfo(&pipelineInfo)
            }
            
        }
    }
}

class VulkanRenderCommandEncoder : VulkanResourceBindingCommandEncoder {
    
    let device : VulkanDevice
    let stateCaches : VulkanStateCaches
    let commandBufferResources : VulkanCommandBuffer
    let renderTarget : VulkanRenderTargetDescriptor
    let resourceMap: FrameResourceMap<VulkanBackend>
    
    var renderPass : VulkanRenderPass! = nil
    var currentDrawRenderPass : DrawRenderPass! = nil
    var pipelineDescriptor : VulkanRenderPipelineDescriptor
    
    var boundVertexBuffers = [Buffer?](repeating: nil, count: 8)
    var enqueuedBindings = [RenderGraphCommand]()

    var subpass: VulkanSubpass? = nil
    
    var currentPrimitiveType: PrimitiveType? = nil
    var currentWinding: Winding? = nil
    
    public init?(device: VulkanDevice, renderTarget: VulkanRenderTargetDescriptor, commandBufferResources: VulkanCommandBuffer, shaderLibrary: VulkanShaderLibrary, caches: VulkanStateCaches, resourceMap: FrameResourceMap<VulkanBackend>) {
        self.device = device
        self.renderTarget = renderTarget
        self.commandBufferResources = commandBufferResources
        self.stateCaches = caches
        self.resourceMap = resourceMap
        
        self.pipelineDescriptor = VulkanRenderPipelineDescriptor(shaderLibrary: shaderLibrary, compatibleRenderPass: renderTarget.compatibleRenderPass!)
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
        return self.pipelineDescriptor.layout
    }
    
    var pipelineReflection: VulkanPipelineReflection {
        return self.pipelineDescriptor.pipelineReflection
    }

    
    func prepareToDraw() {
        assert(self.pipelineDescriptor.descriptor != nil, "No render pipeline descriptor is set.")

        if self.pipelineDescriptor.hasChanged {
            defer {
                self.pipelineDescriptor.hasChanged = false
            }

            // Bind the pipeline before binding any resources.

            let pipeline = self.stateCaches[self.pipelineDescriptor, 
                                            renderPass: self.renderPass!]
            vkCmdBindPipeline(self.commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline)
        }

        for binding in self.enqueuedBindings {
            switch binding {
            case .setArgumentBuffer(let args):
                let bindingPath = args.pointee.bindingPath
                
                let argumentBuffer = args.pointee.argumentBuffer
                let vkArgumentBuffer = resourceMap[argumentBuffer]

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
            
            default:
                preconditionFailure()
            }
        }
        self.enqueuedBindings.removeAll(keepingCapacity: true)
    }
    
    private func beginPass(_ pass: RenderPassRecord) async throws {
        let drawPass = pass.pass as! DrawRenderPass
        self.currentDrawRenderPass = drawPass  
        self.subpass = self.renderTarget.subpassForPassIndex(pass.passIndex)  

        self.pipelineDescriptor.subpassIndex = self.subpass!.index
        
        let renderTargetSize = renderTarget.descriptor.size
        let renderTargetRect = VkRect2D(offset: VkOffset2D(x: 0, y: 0), extent: VkExtent2D(width: UInt32(renderTargetSize.width), height: UInt32(renderTargetSize.height)))
        
        if pass == self.renderTarget.renderPasses.first { // Set up the render target.
            self.renderPass = try await VulkanRenderPass(device: self.device, descriptor: renderTarget, resourceMap: self.resourceMap)
            commandBufferResources.renderPasses.append(renderPass)
            let framebuffer = try await VulkanFramebuffer(descriptor: renderTarget, renderPass: renderPass, device: self.device, resourceMap: self.resourceMap)
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
        // There's also a new extended dynamic state extension in 1.2 which might be worth 
        // looking at.
        
        var viewport = VkViewport(x: 0, y: Float(renderTargetRect.extent.height), width: Float(renderTargetRect.extent.width), height: -Float(renderTargetRect.extent.height), minDepth: 0, maxDepth: 1)
        vkCmdSetViewport(self.commandBuffer, 0, 1, &viewport)
        
        var scissor = renderTargetRect
        vkCmdSetScissor(self.commandBuffer, 0, 1, &scissor)
        
        vkCmdSetStencilReference(self.commandBuffer, VkStencilFaceFlags(VK_STENCIL_FRONT_AND_BACK), 0)

        vkCmdSetDepthBias(self.commandBuffer, 0.0, 0.0, 0.0)
    }
    
    /// Ends a pass and returns whether the command encoder is still valid.
    private func endPass(_ pass: RenderPassRecord) -> Bool {
        if pass == self.renderTarget.renderPasses.last {
            vkCmdEndRenderPass(self.commandBuffer)
            return false
        } else {
            let nextSubpass = self.renderTarget.subpassForPassIndex(pass.passIndex + 1)
            if nextSubpass !== self.subpass {
                vkCmdNextSubpass(self.commandBuffer, VK_SUBPASS_CONTENTS_INLINE)
            }
        }
        return true
    }
    
    
    func executePass(_ pass: RenderPassRecord, resourceCommands: [CompactedResourceCommand<VulkanCompactedResourceCommandType>], passRenderTarget: RenderTargetDescriptor) async {
        var resourceCommandIndex = resourceCommands.binarySearch { $0.index < pass.commandRange!.lowerBound }
        
        let firstCommandIndex = pass.commandRange!.first!
        let lastCommandIndex = pass.commandRange!.last!

        // Check for any commands that need to be executed before the render pass.
        self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .before, commandIndex: firstCommandIndex)

        try! await self.beginPass(pass)

        // FIXME: need to insert this logic:
//        if passRenderTarget.depthAttachment == nil && passRenderTarget.stencilAttachment == nil, (self.renderPassDescriptor.depthAttachment.texture != nil || self.renderPassDescriptor.stencilAttachment.texture != nil) {
//            encoder.setDepthStencilState(stateCaches.defaultDepthState) // The render pass unexpectedly has a depth/stencil attachment, so make sure the depth stencil state is set to the default.
//        }
        
        for (i, command) in zip(pass.commandRange!, pass.commands) {
            if i > firstCommandIndex {
                self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .before, commandIndex: i)
            }
            
            self.executeCommand(command)
            
            if i < lastCommandIndex {
                self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .after, commandIndex: i)
            }
        }
        
        _ = self.endPass(pass) 
        
        // Check for any commands that need to be executed after the render pass.
        self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .after, commandIndex: lastCommandIndex)
    }
    
    func setPrimitiveType(_ primitiveType: PrimitiveType) {
        guard primitiveType != self.currentPrimitiveType else {
            return
        }

        let oldDescriptorType = self.pipelineDescriptor.primitiveType
        switch primitiveType {
        case .triangle, .triangleStrip:
            self.pipelineDescriptor.primitiveType = .triangle
        case .line, .lineStrip:
            self.pipelineDescriptor.primitiveType = .line
        case .point:
            self.pipelineDescriptor.primitiveType = .point
        }
        if self.pipelineDescriptor.primitiveType != oldDescriptorType {
            self.prepareToDraw()
        }
        
        vkCmdSetPrimitiveTopologyEXT(self.commandBuffer, VkPrimitiveTopology(primitiveType))
        
        let primitiveRestartEnabled: Bool
        switch primitiveType {
        case .triangle, .line, .point:
            primitiveRestartEnabled = false
        default:
            primitiveRestartEnabled = true
            // Disable primitive restart for list topologies
        }
        vkCmdSetPrimitiveRestartEnableEXT(self.commandBuffer, primitiveRestartEnabled ? 1 : 0)
        
        self.currentPrimitiveType = primitiveType
    }
    
    func executeCommand(_ command: RenderGraphCommand) {
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
            if let buffer = self.resourceMap[handle] {
                var vkBuffer = buffer.buffer.vkBuffer as VkBuffer?
                var offset = VkDeviceSize(args.pointee.offset) + VkDeviceSize(buffer.offset)
                vkCmdBindVertexBuffers(self.commandBuffer, args.pointee.index, 1, &vkBuffer, &offset)
            }

        case .setVertexBufferOffset(let offset, let index):
            let handle = self.boundVertexBuffers[Int(index)]!
            if let buffer = self.resourceMap[handle] {
                var vkBuffer = buffer.buffer.vkBuffer as VkBuffer?
                var offset = VkDeviceSize(offset) + VkDeviceSize(buffer.offset)
                vkCmdBindVertexBuffers(self.commandBuffer, index, 1, &vkBuffer, &offset)
            }
            
        case .setArgumentBuffer, .setBytes, 
            .setBufferOffset, .setBuffer, .setTexture, .setSamplerState:
            self.enqueuedBindings.append(command)
            
        case .setRenderPipelineDescriptor(let descriptorPtr):
            let descriptor = descriptorPtr.takeUnretainedValue().value
            self.pipelineDescriptor.descriptor = descriptor
            
        case .drawPrimitives(let args):
            self.setPrimitiveType(args.pointee.primitiveType)
            self.prepareToDraw()
            
            vkCmdDraw(self.commandBuffer, args.pointee.vertexCount, args.pointee.instanceCount, args.pointee.vertexStart, args.pointee.baseInstance)
            
        case .drawIndexedPrimitives(let args):
            self.setPrimitiveType(args.pointee.primitiveType)
            
            let buffer = resourceMap[args.pointee.indexBuffer]!
            vkCmdBindIndexBuffer(self.commandBuffer, buffer.buffer.vkBuffer, VkDeviceSize(args.pointee.indexBufferOffset) + VkDeviceSize(buffer.offset), VkIndexType(args.pointee.indexType))
            
            self.prepareToDraw()
            
            vkCmdDrawIndexed(self.commandBuffer, args.pointee.indexCount, args.pointee.instanceCount, 0, args.pointee.baseVertex, args.pointee.baseInstance)
            
        case .setViewport(let viewportPtr):
            var viewport = VkViewport(viewportPtr.pointee)
            vkCmdSetViewport(self.commandBuffer, 0, 1, &viewport)
            
        case .setFrontFacing(let winding):
            vkCmdSetFrontFaceEXT(self.commandBuffer, VkFrontFace(winding))
            
        case .setCullMode(let cullMode):
            vkCmdSetCullModeEXT(self.commandBuffer, VkCullModeFlags(cullMode))
            
        case .setDepthStencilDescriptor(let descriptorPtr):
            self.pipelineDescriptor.depthStencil = descriptorPtr.takeUnretainedValue().value
            
        case .setScissorRect(let scissorPtr):
            var scissor = VkRect2D(scissorPtr.pointee)
            vkCmdSetScissor(self.commandBuffer, 0, 1, &scissor)
            
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
