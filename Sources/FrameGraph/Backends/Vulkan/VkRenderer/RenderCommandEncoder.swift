//
//  RenderCommandEncoder.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 8/01/18.
//

import RenderAPI
import SwiftMath
import FrameGraph
import CVkRenderer
import Utilities

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

    func withVulkanPipelineCreateInfo(renderPass: VulkanRenderPass, subpass: UInt32, renderTargetDescriptor: RenderTargetDescriptor, pipelineReflection: PipelineReflection, stateCaches: StateCaches, _ withInfo: (inout VkGraphicsPipelineCreateInfo) -> Void) {
        
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
        
        var multisampleState = VkPipelineMultisampleStateCreateInfo(self.descriptor)
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
        let bindingManager : ResourceBindingManager
        let shaderLibrary : VulkanShaderLibrary
        var hasChanged = true
        
        init(shaderLibrary: VulkanShaderLibrary, bindingManager: ResourceBindingManager) {
            self.shaderLibrary = shaderLibrary
            self.bindingManager = bindingManager
        }
        
        var descriptor : RenderPipelineDescriptor! = nil {
            didSet {
                
                let key = PipelineLayoutKey.graphics(vertexShader: descriptor.vertexFunction!, fragmentShader: descriptor.fragmentFunction)
                self.pipelineReflection = shaderLibrary.reflection(for: key)
                
                _layout = nil // FIXME: we also need to invalidate the layout in the more subtle case where the descriptor layout changes.
                
                self.hasChanged = true
            }
        }
        
        var pipelineReflection : PipelineReflection! = nil
        
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
            _layout = self.shaderLibrary.pipelineLayout(for: .graphics(vertexShader: descriptor.vertexFunction!, fragmentShader: descriptor.fragmentFunction), bindingManager: self.bindingManager)
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
    let stateCaches : StateCaches
    let commandBufferResources : CommandBufferResources
    let renderTarget : VulkanRenderTargetDescriptor
    let resourceRegistry: ResourceRegistry
    
    var renderPass : VulkanRenderPass! = nil
    var currentDrawRenderPass : DrawRenderPass! = nil
    var bindingManager : ResourceBindingManager! = nil
    var pipelineState : PipelineState! = nil
    
    var boundVertexBuffers = [ObjectIdentifier?](repeating: nil, count: 8)
    
    public init(device: VulkanDevice, renderTarget: VulkanRenderTargetDescriptor, commandBufferResources: CommandBufferResources, shaderLibrary: VulkanShaderLibrary, caches: StateCaches, resourceRegistry: ResourceRegistry) {
        self.device = device
        self.renderTarget = renderTarget
        self.commandBufferResources = commandBufferResources
        self.stateCaches = caches
        self.resourceRegistry = resourceRegistry
        
        self.bindingManager = ResourceBindingManager(encoder: self)
        self.pipelineState = PipelineState(shaderLibrary: shaderLibrary, bindingManager: bindingManager)
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
    
    var pipelineReflection: PipelineReflection {
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
        
        self.bindingManager.bindDescriptorSets()
    }
    
    public func beginPass(_ pass: RenderPassRecord) {
        self.currentDrawRenderPass = (pass.pass as! DrawRenderPass)        
        self.pipelineState.hasChanged = true
        
        let renderTargetSize = renderTarget.descriptor.size
        let renderTargetRect = VkRect2D(offset: VkOffset2D(x: 0, y: 0), extent: VkExtent2D(width: UInt32(renderTargetSize.width), height: UInt32(renderTargetSize.height)))
        
        if pass === self.renderTarget.renderPasses.first { // Set up the render target.
            
            self.renderPass = VulkanRenderPass(device: self.device, descriptor: renderTarget)
            commandBufferResources.renderPasses.append(renderPass)
            let framebuffer = VulkanFramebuffer(descriptor: renderTarget, renderPass: renderPass.vkPass, device: self.device, resourceRegistry: self.resourceRegistry)
            commandBufferResources.framebuffers.append(framebuffer)
            
            var clearValues = [VkClearValue]()
            if renderTarget.descriptor.depthAttachment != nil || renderTarget.descriptor.stencilAttachment != nil {
                let clearDepth = renderTarget.descriptor.depthAttachment?.clearDepth ?? 0.0
                let clearStencil = renderTarget.descriptor.stencilAttachment?.clearStencil ?? 0
                clearValues.append(VkClearValue(depthStencil: VkClearDepthStencilValue(depth: Float(clearDepth), stencil: clearStencil)))
            }
            
            for colorAttachment in renderTarget.descriptor.colorAttachments {
                if let clearColor = colorAttachment?.clearColor {
                    clearValues.append(VkClearValue(color: VkClearColorValue(float32: (Float(clearColor.red), Float(clearColor.green), Float(clearColor.blue), Float(clearColor.alpha)))))
                } else {
                    clearValues.append(VkClearValue())
                }
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
    public func endPass(_ pass: RenderPassRecord) -> Bool {
        if pass === self.renderTarget.renderPasses.last {
            vkCmdEndRenderPass(self.commandBuffer)

            for (textureIdentifier, layout) in self.renderTarget.finalLayouts {
                self.resourceRegistry[texture: textureIdentifier]!.layout = layout
            }

            return false
        } else if self.renderTarget.subpassForPassIndex(pass.passIndex) !== self.renderTarget.subpassForPassIndex(pass.passIndex + 1) {
            vkCmdNextSubpass(self.commandBuffer, VK_SUBPASS_CONTENTS_INLINE)
            self.pipelineState.subpass += 1
        }
        return true
    }
    
    
    func executeCommands(_ commands: ArraySlice<FrameGraphCommand>, resourceCommands: inout [ResourceCommand]) {
        for (i, command) in zip(commands.indices, commands) {
            self.executeResourceCommands(resourceCommands: &resourceCommands, order: .before, commandIndex: i)
            self.executeCommand(command)
            self.executeResourceCommands(resourceCommands: &resourceCommands, order: .after, commandIndex: i)
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
            self.boundVertexBuffers[Int(args.pointee.index)] = args.pointee.handle
            guard let handle = args.pointee.handle else { return }
            let buffer = self.resourceRegistry[buffer: handle]!
            self.commandBufferResources.buffers.append(buffer)

            var vkBuffer = buffer.vkBuffer as VkBuffer?
            var offset = VkDeviceSize(args.pointee.offset)
            vkCmdBindVertexBuffers(self.commandBuffer, args.pointee.index, 1, &vkBuffer, &offset)

        case .setVertexBufferOffset(let offset, let index):
            let handle = self.boundVertexBuffers[Int(index)]!
            let buffer = self.resourceRegistry[buffer: handle]!

            var vkBuffer = buffer.vkBuffer as VkBuffer?
            var offset = VkDeviceSize(offset)
            vkCmdBindVertexBuffers(self.commandBuffer, index, 1, &vkBuffer, &offset)
            
        case .setArgumentBuffer(let args):
            let bindingPath = args.pointee.bindingPath
            let vkBindingPath = VulkanResourceBindingPath(bindingPath)
            
            let argumentBuffer = args.pointee.argumentBuffer.takeUnretainedValue()
            let vkArgumentBuffer = resourceRegistry.allocateArgumentBufferIfNeeded(argumentBuffer, 
                                                                                    bindingPath: vkBindingPath, 
                                                                                    commandBufferResources: self.commandBufferResources, 
                                                                                    pipelineReflection: self.pipelineReflection, 
                                                                                    stateCaches: stateCaches)

            self.commandBufferResources.argumentBuffers.append(vkArgumentBuffer)

            var set : VkDescriptorSet? = vkArgumentBuffer.descriptorSet
            vkCmdBindDescriptorSets(self.commandBuffer, self.bindPoint, self.pipelineLayout, vkBindingPath.set, 1, &set, 0, nil)

        case .setBytes(let args):
            self.bindingManager.setBytes(args: args)
            
        case .setBufferOffset(let args):
            self.bindingManager.setBufferOffset(args: args)
            
        case .setBuffer(let args):
            self.bindingManager.setBuffer(args: args)
            
        case .setTexture(let args):
            self.bindingManager.setTexture(args: args)
            
        case .setSamplerState(let args):
            self.bindingManager.setSamplerState(args: args)
            
        case .setRenderPipelineDescriptor(let descriptorPtr):
            let descriptor = descriptorPtr.takeUnretainedValue().value
            self.pipelineState.descriptor = descriptor
            
        case .drawPrimitives(let args):
            self.pipelineState.primitiveType = args.pointee.primitiveType
            self.prepareToDraw()
            
            vkCmdDraw(self.commandBuffer, args.pointee.vertexCount, args.pointee.instanceCount, args.pointee.vertexStart, args.pointee.baseInstance)
            
        case .drawIndexedPrimitives(let args):
            self.pipelineState.primitiveType = args.pointee.primitiveType
            
            vkCmdBindIndexBuffer(self.commandBuffer, resourceRegistry[buffer: args.pointee.indexBuffer]!.vkBuffer, VkDeviceSize(args.pointee.indexBufferOffset), VkIndexType(args.pointee.indexType))
            
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
