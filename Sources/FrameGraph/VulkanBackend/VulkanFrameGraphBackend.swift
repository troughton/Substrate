//
//  VkFrameGraphContext.swift
//  VkRenderer
//
//  Created by Joseph Bennett on 2/01/18.
//

#if canImport(Vulkan)
import Vulkan
import Dispatch
import FrameGraphCExtras

public final class VulkanFrameGraphContext : _FrameGraphContext {
    
    let device: VulkanDevice
    let resourceRegistry : ResourceRegistry
    
    let shaderLibrary: VulkanShaderLibrary
    let stateCaches: StateCaches

    private let commandBufferResourcesQueue = DispatchQueue(label: "Command Buffer Resources management.")
    private var inactiveCommandBufferResources = [Unmanaged<CommandBufferResources>]()

    init(device: VulkanDevice, resourceRegistry: ResourceRegistry, shaderLibrary: VulkanShaderLibrary) {
        self.device = device
        self.resourceRegistry = resourceRegistry
        
        self.shaderLibrary = shaderLibrary
        self.stateCaches = StateCaches(device: self.device, shaderLibrary: shaderLibrary)
    }

    // Thread-safe.
    public func markCommandBufferResourcesCompleted(_ resources: [CommandBufferResources]) {
        self.commandBufferResourcesQueue.sync {
            for resource in resources {
                self.inactiveCommandBufferResources.append(Unmanaged.passRetained(resource))
            }
        }
    }  

    public func beginFrameResourceAccess() {
        self.resourceRegistry.frameGraphHasResourceAccess = true
    }

    // We need to make sure the resources are released on the main Vulkan thread.
    func clearInactiveCommandBufferResources() {
        var inactiveResources : [Unmanaged<CommandBufferResources>]? = nil
        self.commandBufferResourcesQueue.sync {
            inactiveResources = self.inactiveCommandBufferResources
            self.inactiveCommandBufferResources.removeAll()
        }
        for resource in inactiveResources! {
            resource.release()
        }
    }
    
    public func executeFrameGraph(passes: [RenderPassRecord], resourceUsages: ResourceUsages, commands: [FrameGraphCommand], completion: @escaping () -> Void) {
        defer { self.resourceRegistry.cycleFrames() }
        
        self.clearInactiveCommandBufferResources()

        let renderTargetDescriptors = self.generateRenderTargetDescriptors(passes: passes, resourceUsages: resourceUsages)
        
        var resourceCommands = self.generateResourceCommands(passes: passes, resourceUsages: resourceUsages, renderTargetDescriptors: renderTargetDescriptors)
        
        let encoderManager = EncoderManager(frameGraph: self)
        
        for (i, passRecord) in passes.enumerated() {
            switch passRecord.pass.passType {
            case .blit:
                let commandEncoder = encoderManager.blitCommandEncoder()
                
                commandEncoder.executeCommands(commands[passRecord.commandRange!], resourceCommands: &resourceCommands)
                
            case .draw:
                let commandEncoder = encoderManager.renderCommandEncoder(descriptor: renderTargetDescriptors[i]!)
                
                // Special case: run any resource commands needed _before_ we start the render pass.
                commandEncoder.executeResourceCommands(resourceCommands: &resourceCommands, order: .before, commandIndex: passRecord.commandRange!.lowerBound)
                
                commandEncoder.beginPass(passRecord)
                
                commandEncoder.executeCommands(commands[passRecord.commandRange!], resourceCommands: &resourceCommands)
                
                let _ = commandEncoder.endPass(passRecord)
                
            case .compute:
                let commandEncoder = encoderManager.computeCommandEncoder()
                
                commandEncoder.executeCommands(commands[passRecord.commandRange!], resourceCommands: &resourceCommands)
                
            case .cpu, .external:
                break
            }
        }
        
        // Trigger callback once GPU is finished processing frame.
        encoderManager.endEncoding(completion: completion)
        
        for swapChain in self.resourceRegistry.windowReferences.values {
            swapChain.submit()
        }
        
        self.resourceRegistry.frameGraphHasResourceAccess = false
    }
    
    func generateRenderTargetDescriptors(passes: [RenderPassRecord], resourceUsages: ResourceUsages) -> [VulkanRenderTargetDescriptor?] {
        var descriptors = [VulkanRenderTargetDescriptor?](repeating: nil, count: passes.count)
        
        var currentDescriptor : VulkanRenderTargetDescriptor? = nil
        for (i, renderPassRecord) in passes.enumerated() {
            if renderPassRecord.pass is DrawRenderPass {
                if let descriptor = currentDescriptor {
                    currentDescriptor = descriptor.descriptorMergedWithPass(renderPassRecord, resourceUsages: resourceUsages)
                } else {
                    currentDescriptor = VulkanRenderTargetDescriptor(renderPass: renderPassRecord)
                }
            } else {
                currentDescriptor?.finalise(resourceUsages: resourceUsages)
                currentDescriptor = nil
            }
            
            descriptors[i] = currentDescriptor
        }
        
        currentDescriptor?.finalise(resourceUsages: resourceUsages)
        
        return descriptors
    }
    
    func generateResourceCommands(passes: [RenderPassRecord], resourceUsages: ResourceUsages, renderTargetDescriptors: [VulkanRenderTargetDescriptor?]) -> [ResourceCommand] {
        var commands = [ResourceCommand]()
        
        var eventId = 0
        var semaphoreId = 0
        
        resourceLoop: for resource in resourceUsages.allResources {
            let usages = resource.usages
            if usages.isEmpty { continue }

            var usageIterator = usages.makeIterator()
            
            // Find the first used render pass.
            var previousUsage : ResourceUsage
            repeat {
                guard let usage = usageIterator.next() else {
                    continue resourceLoop // no active usages for this resource
                }
                previousUsage = usage
            } while !previousUsage.renderPassRecord.isActive || (previousUsage.stages == .cpuBeforeRender && previousUsage.type != .unusedArgumentBuffer)
            
            let materialiseIndex = previousUsage.commandRange.lowerBound
            
            while previousUsage.type == .unusedArgumentBuffer || previousUsage.type == .unusedRenderTarget {
                previousUsage = usageIterator.next()!
            }

            let firstUsage = previousUsage
            
            while let usage = usageIterator.next()  {
                if !usage.renderPassRecord.isActive || usage.stages == .cpuBeforeRender { continue }
                defer { previousUsage = usage }

                if !previousUsage.isWrite && !usage.isWrite { continue }

                if previousUsage.type == usage.type && previousUsage.type.isRenderTarget {
                    continue
                }
                
                do {
                    // Manage memory dependency.
                    
                    var isDepthStencil = false
                    if let texture = resource.texture, texture.descriptor.pixelFormat.isDepth || texture.descriptor.pixelFormat.isStencil {
                        isDepthStencil = true
                    }
                    
                    let passUsage = previousUsage
                    let dependentUsage = usage
                    
                    let passCommandIndex = passUsage.commandRange.upperBound - 1
                    let dependentCommandIndex = dependentUsage.commandRange.lowerBound
                    
                    let sourceAccessMask = passUsage.type.accessMask(isDepthOrStencil: isDepthStencil)
                    let destinationAccessMask = dependentUsage.type.accessMask(isDepthOrStencil: isDepthStencil)
                    
                    let sourceMask = passUsage.type.shaderStageMask(isDepthOrStencil: isDepthStencil, stages: passUsage.stages)
                    let destinationMask = dependentUsage.type.shaderStageMask(isDepthOrStencil: isDepthStencil, stages: dependentUsage.stages)
                    
                    let sourceLayout = resource.type == .texture ? passUsage.type.imageLayout(isDepthOrStencil: isDepthStencil) : VK_IMAGE_LAYOUT_UNDEFINED
                    let destinationLayout = resource.type == .texture ? dependentUsage.type.imageLayout(isDepthOrStencil: isDepthStencil) : VK_IMAGE_LAYOUT_UNDEFINED

                    if !passUsage.type.isRenderTarget, dependentUsage.type.isRenderTarget,
                        renderTargetDescriptors[passUsage.renderPassRecord.passIndex] !== renderTargetDescriptors[dependentUsage.renderPassRecord.passIndex] {
                        renderTargetDescriptors[dependentUsage.renderPassRecord.passIndex]!.initialLayouts[resource.texture!] = sourceLayout
                    }
                    
                    if passUsage.type.isRenderTarget, !dependentUsage.type.isRenderTarget,
                        renderTargetDescriptors[passUsage.renderPassRecord.passIndex] !== renderTargetDescriptors[dependentUsage.renderPassRecord.passIndex] {
                        renderTargetDescriptors[passUsage.renderPassRecord.passIndex]!.finalLayouts[resource.texture!] = destinationLayout
                    }
                    
                    let barrier : ResourceMemoryBarrier
                    
                    if let texture = resource.texture {
                        var imageBarrierInfo = VkImageMemoryBarrier()
                        imageBarrierInfo.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER
                        imageBarrierInfo.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
                        imageBarrierInfo.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
                        imageBarrierInfo.srcAccessMask = VkAccessFlags(sourceAccessMask)
                        imageBarrierInfo.dstAccessMask = VkAccessFlags(destinationAccessMask)
                        imageBarrierInfo.oldLayout = sourceLayout
                        imageBarrierInfo.newLayout = destinationLayout
                        imageBarrierInfo.subresourceRange = VkImageSubresourceRange(aspectMask: texture.descriptor.pixelFormat.aspectFlags, baseMipLevel: 0, levelCount: UInt32(texture.descriptor.mipmapLevelCount), baseArrayLayer: 0, layerCount: UInt32(texture.descriptor.arrayLength))
                        
                        barrier = .texture(texture, imageBarrierInfo)
                    } else if let buffer = resource.buffer {
                        var bufferBarrierInfo = VkBufferMemoryBarrier()
                        bufferBarrierInfo.sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER
                        bufferBarrierInfo.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
                        bufferBarrierInfo.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
                        bufferBarrierInfo.srcAccessMask = VkAccessFlags(sourceAccessMask)
                        bufferBarrierInfo.dstAccessMask = VkAccessFlags(destinationAccessMask)
                        bufferBarrierInfo.offset = 0
                        bufferBarrierInfo.size = VK_WHOLE_SIZE
                        
                        barrier = .buffer(buffer, bufferBarrierInfo)
                    } else {
                        fatalError()
                    }
                    
                    var memoryBarrierInfo = MemoryBarrierInfo(sourceMask: sourceMask, destinationMask: destinationMask, barrier: barrier)
            
                    if passUsage.renderPassRecord.pass.passType == .draw || dependentUsage.renderPassRecord.pass.passType == .draw {

                        let renderTargetDescriptor = (renderTargetDescriptors[passUsage.renderPassRecord.passIndex] ?? renderTargetDescriptors[dependentUsage.renderPassRecord.passIndex])! // Add to the first pass if possible, the second pass if not.
                        
                        var subpassDependency = VkSubpassDependency()
                        subpassDependency.dependencyFlags = 0 // FIXME: ideally should be VkDependencyFlags(VK_DEPENDENCY_BY_REGION_BIT) for all cases except temporal AA.
                        if let passUsageSubpass = renderTargetDescriptor.subpassForPassIndex(passUsage.renderPassRecord.passIndex) {
                            subpassDependency.srcSubpass = UInt32(passUsageSubpass.index)
                        } else {
                            subpassDependency.srcSubpass = VK_SUBPASS_EXTERNAL
                        }
                        subpassDependency.srcStageMask = VkPipelineStageFlags(sourceMask)
                        subpassDependency.srcAccessMask = VkAccessFlags(sourceAccessMask)
                        if let destinationUsageSubpass = renderTargetDescriptor.subpassForPassIndex(dependentUsage.renderPassRecord.passIndex) {
                            subpassDependency.dstSubpass = UInt32(destinationUsageSubpass.index)
                        } else {
                            subpassDependency.dstSubpass = VK_SUBPASS_EXTERNAL
                        }
                        subpassDependency.dstStageMask = VkPipelineStageFlags(destinationMask)
                        subpassDependency.dstAccessMask = VkAccessFlags(destinationAccessMask)
                        
                        // If the dependency is on an attachment, then we can let the subpass dependencies handle it, _unless_ both usages are in the same subpass.
                        // Otherwise, an image should always be in the right layout when it's materialised. The only case it won't be is if it's used in one way in
                        // a draw render pass (e.g. as a read texture) and then needs to transition layout before being used in a different type of pass.
                        
                        if subpassDependency.srcSubpass == subpassDependency.dstSubpass {
                            guard case .texture(let textureHandle, var imageBarrierInfo) = barrier else {
                                print("Source: \(passUsage), destination: \(dependentUsage)")
                                fatalError("We can't insert pipeline barriers within render passes for buffers.")
                            }

                            if imageBarrierInfo.oldLayout != imageBarrierInfo.newLayout {
                                imageBarrierInfo.oldLayout = VK_IMAGE_LAYOUT_GENERAL
                                imageBarrierInfo.newLayout = VK_IMAGE_LAYOUT_GENERAL
                                memoryBarrierInfo.barrier = .texture(textureHandle, imageBarrierInfo)
                            }

                            // Insert a subpass self-dependency.
                            commands.append(ResourceCommand(type: .pipelineBarrier(memoryBarrierInfo), index: dependentCommandIndex, order: .before))
                            
                            renderTargetDescriptor.addDependency(subpassDependency)
                        } else if   sourceLayout != destinationLayout, // guaranteed to not be a buffer since buffers have UNDEFINED image layouts above.
                                    !passUsage.type.isRenderTarget, !dependentUsage.type.isRenderTarget {
                            // We need to insert a pipeline barrier to handle a layout transition.
                            // We can therefore avoid a subpass dependency in most cases.
                            
                            if subpassDependency.srcSubpass == VK_SUBPASS_EXTERNAL {
                                // Insert a pipeline barrier before the start of the Render Command Encoder.
                                let firstPassInVkRenderPass = renderTargetDescriptors[dependentUsage.renderPassRecord.passIndex]!.renderPasses.first!
                                let dependencyIndex = firstPassInVkRenderPass.commandRange!.lowerBound

                                assert(dependencyIndex <= dependentUsage.commandRange.lowerBound)

                                commands.append(ResourceCommand(type: .pipelineBarrier(memoryBarrierInfo), index: dependencyIndex, order: .before))
                            } else if subpassDependency.dstSubpass == VK_SUBPASS_EXTERNAL {
                                // Insert a pipeline barrier before the next command after the render command encoder ends.
                                let lastPassInVkRenderPass = renderTargetDescriptors[dependentUsage.renderPassRecord.passIndex]!.renderPasses.last!
                                let dependencyIndex = lastPassInVkRenderPass.commandRange!.upperBound

                                assert(dependencyIndex <= passUsage.commandRange.lowerBound)

                                commands.append(ResourceCommand(type: .pipelineBarrier(memoryBarrierInfo), index: dependencyIndex, order: .before))
                            } else {
                                // Insert a subpass self-dependency and a pipeline barrier.
                                fatalError("This should have been handled by the subpassDependency.srcSubpass == subpassDependency.dstSubpass case.")

                                // commands.append(ResourceCommand(type: .pipelineBarrier(memoryBarrierInfo), index: dependentCommandIndex, order: .before))
                                // subpassDependency.srcSubpass = subpassDependency.dstSubpass
                                // renderTargetDescriptor.addDependency(subpassDependency)
                            }
                        } else {
                            // A subpass dependency should be enough to handle this case.
                            renderTargetDescriptor.addDependency(subpassDependency)
                        }
                        
                    } else {
                        
                        if self.device.physicalDevice.queueFamilyIndex(renderPassType: passUsage.renderPassRecord.pass.passType) != self.device.physicalDevice.queueFamilyIndex(renderPassType: dependentUsage.renderPassRecord.pass.passType) {
                            // Assume that the resource has a concurrent sharing mode.
                            // If the sharing mode is concurrent, then we only need to insert a barrier for an image layout transition.
                            // Otherwise, we would need to do a queue ownership transfer.
                            
                            // TODO: we should make all persistent resources concurrent if necessary, and all frame resources exclusive (unless they have two consecutive reads).
                            // The logic here will then change to insert a pipeline barrier on each queue with an ownership transfer, unconditional on being a buffer or texture.
                            
                            if case .texture = barrier { // We only need to insert a barrier to do a layout transition.
                                //  commands.append(ResourceCommand(type: .pipelineBarrier(memoryBarrierInfo), index: passCommandIndex - 1, order: .after))
                                commands.append(ResourceCommand(type: .pipelineBarrier(memoryBarrierInfo), index: dependentCommandIndex, order: .before))
                            }
                            // Also use a semaphore, since they're on different queues
                            commands.append(ResourceCommand(type: .signalSemaphore(id: semaphoreId, afterStages: sourceMask), index: passCommandIndex, order: .after))
                            commands.append(ResourceCommand(type: .waitForSemaphore(id: semaphoreId, beforeStages: destinationMask), index: dependentCommandIndex, order: .before))
                            semaphoreId += 1
                        } else if previousUsage.isWrite || usage.isWrite {
                            // If either of these take place within a render pass, they need to be inserted as pipeline barriers instead and added
                            // as subpass dependencise if relevant. 

                            commands.append(ResourceCommand(type: .signalEvent(id: eventId, afterStages: sourceMask), index: passCommandIndex, order: .after))
                            commands.append(ResourceCommand(type: .waitForEvent(id: eventId, info: memoryBarrierInfo), index: dependentCommandIndex, order: .before))
                            eventId += 1
                        } else if case .texture = barrier, sourceLayout != destinationLayout { // We only need to insert a barrier to do a layout transition.
                            // TODO: We could minimise the number of layout transitions with a lookahead approach.
                            commands.append(ResourceCommand(type: .pipelineBarrier(memoryBarrierInfo), index: dependentCommandIndex, order: .before))
                        }
                    }
                    
                }
            }

            let lastUsage = previousUsage
            
            let historyBufferCreationFrame = resource.flags.contains(.historyBuffer) && !resource.stateFlags.contains(.initialised)
            let historyBufferUseFrame = resource.flags.contains(.historyBuffer) && resource.stateFlags.contains(.initialised)
            
            // Insert commands to materialise and dispose of the resource.
            
            if let buffer = resource.buffer {

                var isModified = false
                var queueFamilies : QueueFamilies = []
                var bufferUsage : VkBufferUsageFlagBits = []

                if buffer.flags.contains(.historyBuffer) {
                    bufferUsage.formUnion(VkBufferUsageFlagBits(buffer.descriptor.usageHint))
                }

                for usage in usages where usage.renderPassRecord.isActive && usage.stages != .cpuBeforeRender {
                    switch usage.renderPassRecord.pass.passType {
                    case .draw:
                        queueFamilies.formUnion(.graphics)
                    case .compute:
                        queueFamilies.formUnion(.compute)
                    case .blit:
                        queueFamilies.formUnion(.copy)
                    case .cpu, .external:
                        break
                    }
                    
                    switch usage.type {
                    case .constantBuffer:
                        bufferUsage.formUnion(.uniformBuffer)
                    case .read:
                        bufferUsage.formUnion([.uniformTexelBuffer, .storageBuffer, .storageTexelBuffer])
                    case .write, .readWrite:
                        isModified = true
                        bufferUsage.formUnion([.storageBuffer, .storageTexelBuffer])
                    case .blitSource:
                        bufferUsage.formUnion(.transferSource)
                    case .blitDestination:
                        isModified = true
                        bufferUsage.formUnion(.transferDestination)
                    case .blitSynchronisation:
                        isModified = true
                        bufferUsage.formUnion([.transferSource, .transferDestination])
                    case .vertexBuffer:
                        bufferUsage.formUnion(.vertexBuffer)
                    case .indexBuffer:
                        bufferUsage.formUnion(.indexBuffer)
                    case .indirectBuffer:
                        bufferUsage.formUnion(.indirectBuffer)
                    case .readWriteRenderTarget, .writeOnlyRenderTarget, .inputAttachmentRenderTarget, .unusedRenderTarget, .sampler, .inputAttachment:
                        fatalError()
                    case .unusedArgumentBuffer:
                        break
                    }
                }
                
                commands.append(
                    ResourceCommand(type:
                        .materialiseBuffer(buffer, usage: bufferUsage, sharingMode: VulkanSharingMode(queueFamilies: queueFamilies, indices: self.device.physicalDevice.queueFamilyIndices)),
                                    index: materialiseIndex, order: .before)
                )
                
                if !historyBufferCreationFrame && !buffer.flags.contains(.persistent) {
                    commands.append(ResourceCommand(type: .disposeBuffer(buffer), index: lastUsage.commandRange.upperBound - 1, order: .after))
                } else {
                    if isModified { // FIXME: what if we're reading from something that the next frame will modify?
                        let sourceMask = lastUsage.type.shaderStageMask(isDepthOrStencil: false, stages: lastUsage.stages)
                    
                        commands.append(ResourceCommand(type: .storeResource(Resource(buffer), finalLayout: nil, afterStages: sourceMask), index: lastUsage.commandRange.upperBound - 1, order: .after))
                    }
                }
                
            } else if let texture = resource.texture {
                let isDepthStencil = texture.descriptor.pixelFormat.isDepth || texture.descriptor.pixelFormat.isStencil
                
                var isModified = false
                var queueFamilies : QueueFamilies = []
                
                var textureUsage : VkImageUsageFlagBits = []
                if texture.flags.contains(.historyBuffer) {
                    textureUsage.formUnion(VkImageUsageFlagBits(texture.descriptor.usageHint, pixelFormat: texture.descriptor.pixelFormat))
                }
                
                var previousUsage : ResourceUsage? = nil
                
                for usage in usages where usage.renderPassRecord.isActive && usage.stages != .cpuBeforeRender {
                    defer { previousUsage = usage }
                    
                    switch usage.renderPassRecord.pass.passType {
                    case .draw:
                        queueFamilies.formUnion(.graphics)
                    case .compute:
                        queueFamilies.formUnion(.compute)
                    case .blit:
                        queueFamilies.formUnion(.copy)
                    case .cpu, .external:
                        break
                    }
                    
                    switch usage.type {
                    case .read:
                        textureUsage.formUnion(.sampled)
                    case .write, .readWrite:
                        isModified = true
                        textureUsage.formUnion(.storage)
                    case .inputAttachment:
                        textureUsage.formUnion(.inputAttachment)
                    case .unusedRenderTarget:
                        if isDepthStencil {
                            textureUsage.formUnion(.depthStencilAttachment)
                        } else {
                            textureUsage.formUnion(.colorAttachment)
                        }
                    case .readWriteRenderTarget, .writeOnlyRenderTarget:
                        isModified = true
                        if isDepthStencil {
                            textureUsage.formUnion(.depthStencilAttachment)
                        } else {
                            textureUsage.formUnion(.colorAttachment)
                        }
                    case .inputAttachmentRenderTarget:
                        textureUsage.formUnion(.inputAttachment)
                    case .blitSource:
                        textureUsage.formUnion(.transferSource)
                    case .blitDestination:
                        isModified = true
                        textureUsage.formUnion(.transferDestination)
                    case .blitSynchronisation:
                        isModified = true
                        textureUsage.formUnion([.transferSource, .transferDestination])
                    case .vertexBuffer, .indexBuffer, .indirectBuffer, .constantBuffer, .sampler:
                        fatalError()
                    case .unusedArgumentBuffer:
                        break
                    }
                }
                
                do {

                    let textureAlreadyExists = texture.flags.contains(.persistent) || historyBufferUseFrame

                    let destinationAccessMask = firstUsage.type.accessMask(isDepthOrStencil: isDepthStencil)
                    let destinationMask = firstUsage.type.shaderStageMask(isDepthOrStencil: isDepthStencil, stages: firstUsage.stages)
                    let destinationLayout = firstUsage.type.imageLayout(isDepthOrStencil: isDepthStencil)
                    
                    var imageBarrierInfo = VkImageMemoryBarrier()
                    imageBarrierInfo.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER
                    imageBarrierInfo.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
                    imageBarrierInfo.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
                    imageBarrierInfo.srcAccessMask = VkAccessFlags([] as VkAccessFlagBits) // since it's already been synchronised in a different way.
                    imageBarrierInfo.dstAccessMask = VkAccessFlags(destinationAccessMask)
                    imageBarrierInfo.oldLayout = textureAlreadyExists ? VK_IMAGE_LAYOUT_PREINITIALIZED : VK_IMAGE_LAYOUT_UNDEFINED
                    imageBarrierInfo.newLayout = firstUsage.type.isRenderTarget ? imageBarrierInfo.oldLayout : destinationLayout
                    imageBarrierInfo.subresourceRange = VkImageSubresourceRange(aspectMask: texture.descriptor.pixelFormat.aspectFlags, baseMipLevel: 0, levelCount: UInt32(texture.descriptor.mipmapLevelCount), baseArrayLayer: 0, layerCount: UInt32(texture.descriptor.arrayLength))
                    
                    let commandType = ResourceCommandType.materialiseTexture(texture, usage: textureUsage, sharingMode: VulkanSharingMode(queueFamilies: queueFamilies, indices: self.device.physicalDevice.queueFamilyIndices), destinationMask: destinationMask, barrier: imageBarrierInfo)
                    

                    var materialiseIndex = materialiseIndex
                    if firstUsage.renderPassRecord.pass.passType == .draw {
                        // Materialise the texture (performing layout transitions) before we begin the Vulkan render pass.
                        let firstPass = renderTargetDescriptors[firstUsage.renderPassRecord.passIndex]!.renderPasses.first!
                        materialiseIndex = firstPass.commandRange!.lowerBound

                        if firstUsage.type.isRenderTarget {
                            // We're not doing a layout transition here, so set the initial layout for the render pass
                            // to the texture's current, actual layout.
                            if let vulkanTexture = self.resourceRegistry[texture] {
                                renderTargetDescriptors[firstUsage.renderPassRecord.passIndex]!.initialLayouts[texture] = vulkanTexture.layout
                            }
                        }
                    }
                    
                    commands.append(
                        ResourceCommand(type: commandType,
                                        index: materialiseIndex, order: .before))
                }
                
                let needsStore = historyBufferCreationFrame || texture.flags.contains(.persistent)
                if !needsStore || texture.flags.contains(.windowHandle) {
                    // We need to dispose window handle textures just to make sure their texture references are removed from the resource registry.
                    commands.append(ResourceCommand(type: .disposeTexture(texture), index: lastUsage.commandRange.upperBound - 1, order: .after))
                } 
                if needsStore && isModified {
                    let sourceMask = lastUsage.type.shaderStageMask(isDepthOrStencil: isDepthStencil, stages: lastUsage.stages)
                    
                    var finalLayout : VkImageLayout? = nil
                    
                    if lastUsage.type.isRenderTarget {
                        renderTargetDescriptors[lastUsage.renderPassRecord.passIndex]!.finalLayouts[texture] = VK_IMAGE_LAYOUT_GENERAL
                        finalLayout = VK_IMAGE_LAYOUT_GENERAL
                    }

                    commands.append(ResourceCommand(type: .storeResource(Resource(texture), finalLayout: finalLayout, afterStages: sourceMask), index: lastUsage.commandRange.upperBound - 1, order: .after))
                }
                
            }
        }
        
        commands.sort(by: >)
        return commands
    }
    
}

enum ResourceMemoryBarrier {
    case texture(Texture, VkImageMemoryBarrier)
    case buffer(Buffer, VkBufferMemoryBarrier)
}

struct MemoryBarrierInfo {
    var sourceMask : VkPipelineStageFlagBits
    var destinationMask : VkPipelineStageFlagBits
    var barrier : ResourceMemoryBarrier
}

enum ResourceCommandType {
    case materialiseBuffer(Buffer, usage: VkBufferUsageFlagBits, sharingMode: VulkanSharingMode)
    case materialiseTexture(Texture, usage: VkImageUsageFlagBits, sharingMode: VulkanSharingMode, destinationMask: VkPipelineStageFlagBits, barrier: VkImageMemoryBarrier)
    case disposeBuffer(Buffer)
    case disposeTexture(Texture)
    
    case storeResource(Resource, finalLayout: VkImageLayout?, afterStages: VkPipelineStageFlagBits) // Creates a semaphore and sets it on the object to be queried next frame.
    
    case signalEvent(id: Int, afterStages: VkPipelineStageFlagBits)
    case waitForEvent(id: Int, info: MemoryBarrierInfo) // using vkCmdSetEvent/vkCmdWaitEvent.
    
    case signalSemaphore(id: Int, afterStages: VkPipelineStageFlagBits)
    case waitForSemaphore(id: Int, beforeStages: VkPipelineStageFlagBits) // these get added to the queue submission for the command buffer.
    
    case pipelineBarrier(MemoryBarrierInfo)
    
    var isMaterialise : Bool {
        switch self {
        case .materialiseTexture, .materialiseBuffer:
            return true
        default:
            return false
        }
    }
}

struct ResourceCommand : Comparable {
    var type : ResourceCommandType
    var index : Int
    var order : PerformOrder
    
    public static func ==(lhs: ResourceCommand, rhs: ResourceCommand) -> Bool {
        return lhs.index == rhs.index && lhs.order == rhs.order && lhs.type.isMaterialise == rhs.type.isMaterialise
    }
    
    public static func <(lhs: ResourceCommand, rhs: ResourceCommand) -> Bool {
        if lhs.index < rhs.index { return true }
        if lhs.index == rhs.index {
            if lhs.order < rhs.order {
                return true
            }
            return lhs.type.isMaterialise && !rhs.type.isMaterialise
        }
        return false
    }
}

#endif // canImport(Vulkan)
