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
import FrameGraphUtilities

extension VulkanBackend {
    func generateEventCommands(queue: Queue, resourceMap: FrameResourceMap<VulkanBackend>, frameCommandInfo: FrameCommandInfo<VulkanBackend>, commandGenerator: ResourceCommandGenerator<VulkanBackend>, compactedResourceCommands: inout [CompactedResourceCommand<VulkanCompactedResourceCommandType>]) {
        // MARK: - Generate the events
        
        let dependencies: DependencyTable<FineDependency?> = commandGenerator.commandEncoderDependencies
        
        let commandEncoderCount = frameCommandInfo.commandEncoders.count
        let reductionMatrix = dependencies.transitiveReduction(hasDependency: { $0 != nil })
        
        let allocator = ThreadLocalTagAllocator(tag: FrameGraphContextImpl<VulkanBackend>.resourceCommandArrayTag)
        
        for sourceIndex in (0..<commandEncoderCount) { // sourceIndex always points to the producing pass.
            let dependentRange = min(sourceIndex + 1, commandEncoderCount)..<commandEncoderCount
            
            var signalStages: VkPipelineStageFlagBits = []
            var signalIndex = -1
            for dependentIndex in dependentRange where reductionMatrix.dependency(from: dependentIndex, on: sourceIndex) {
                let dependency = dependencies.dependency(from: dependentIndex, on: sourceIndex)!
                
                for (resource, producingUsage, consumingUsage) in dependency.resources {
                    let pixelFormat = resource.texture?.descriptor.pixelFormat ?? .invalid
                    let isDepthOrStencil = pixelFormat.isDepth || pixelFormat.isStencil
                    signalStages.formUnion(producingUsage.type.shaderStageMask(isDepthOrStencil: isDepthOrStencil, stages: producingUsage.stages))
                }
                
                signalIndex = max(signalIndex, dependency.signal.index)
            }
            
            if signalIndex < 0 { continue }
            
            let label = "Encoder \(sourceIndex) Event"
            let commandBufferSignalValue = frameCommandInfo.signalValue(commandBufferIndex: frameCommandInfo.commandEncoders[sourceIndex].commandBufferIndex)
            let fence = VulkanEventHandle(label: label, queue: queue, commandBufferIndex: commandBufferSignalValue)
            
            compactedResourceCommands.append(CompactedResourceCommand<VulkanCompactedResourceCommandType>(command: .signalEvent(fence.event, afterStages: signalStages), index: signalIndex, order: .after))
            
            for dependentIndex in dependentRange where reductionMatrix.dependency(from: dependentIndex, on: sourceIndex) {
                let dependency = dependencies.dependency(from: dependentIndex, on: sourceIndex)!
                var destinationStages: VkPipelineStageFlagBits = []
                
                var bufferBarriers = [VkBufferMemoryBarrier]()
                var imageBarriers = [VkImageMemoryBarrier]()
                
//                assert(self.device.queueFamilyIndex(queue: queue, encoderType: sourceEncoderType) == self.device.queueFamilyIndex(queue: queue, encoderType: destinationEncoderType), "Queue ownership transfers must be handled with a pipeline barrier rather than an event")
                
                for (resource, producingUsage, consumingUsage) in dependency.resources {
                    var isDepthOrStencil = false
                    
                    if let buffer = resource.buffer {
                        var barrier = VkBufferMemoryBarrier()
                        barrier.buffer = resourceMap[buffer].buffer.vkBuffer
                        barrier.offset = 0
                        barrier.size = VK_WHOLE_SIZE // TODO: track at a more fine-grained level.
                        barrier.srcAccessMask = producingUsage.type.accessMask(isDepthOrStencil: false).rawValue
                        barrier.dstAccessMask = consumingUsage.type.accessMask(isDepthOrStencil: false).rawValue
                        barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
                        barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
                        bufferBarriers.append(barrier)
                    } else if let texture = resource.texture {
                        let pixelFormat = texture.descriptor.pixelFormat
                        isDepthOrStencil = pixelFormat.isDepth || pixelFormat.isStencil
                        
                        var barrier = VkImageMemoryBarrier()
                        barrier.image = resourceMap[texture].image.vkImage
                        barrier.srcAccessMask = producingUsage.type.accessMask(isDepthOrStencil: isDepthOrStencil).rawValue
                        barrier.dstAccessMask = consumingUsage.type.accessMask(isDepthOrStencil: isDepthOrStencil).rawValue
                        barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
                        barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
                        barrier.oldLayout = producingUsage.type.imageLayout(isDepthOrStencil: isDepthOrStencil)
                        barrier.newLayout = consumingUsage.type.imageLayout(isDepthOrStencil: isDepthOrStencil)
                        barrier.subresourceRange = VkImageSubresourceRange(aspectMask: texture.descriptor.pixelFormat.aspectFlags, baseMipLevel: 0, levelCount: UInt32(texture.descriptor.mipmapLevelCount), baseArrayLayer: 0, layerCount: UInt32(texture.descriptor.arrayLength))
                        imageBarriers.append(barrier)
                    } else {
                        fatalError()
                    }
                    
                    destinationStages.formUnion(consumingUsage.type.shaderStageMask(isDepthOrStencil: isDepthOrStencil, stages: consumingUsage.stages))
                }
                
                let bufferBarriersPtr: UnsafeMutablePointer<VkBufferMemoryBarrier> = allocator.allocate(capacity: bufferBarriers.count)
                bufferBarriersPtr.initialize(from: bufferBarriers, count: bufferBarriers.count)
                
                let imageBarriersPtr: UnsafeMutablePointer<VkImageMemoryBarrier> = allocator.allocate(capacity: imageBarriers.count)
                imageBarriersPtr.initialize(from: imageBarriers, count: imageBarriers.count)
                
                let command: VulkanCompactedResourceCommandType = .waitForEvents(UnsafeBufferPointer(start: fence.eventPointer, count: 1),
                                                                                 sourceStages: signalStages, destinationStages: destinationStages,
                                                                                 memoryBarriers: UnsafeBufferPointer<VkMemoryBarrier>(start: nil, count: 0),
                                                                                 bufferMemoryBarriers: UnsafeBufferPointer<VkBufferMemoryBarrier>(start: bufferBarriersPtr, count: bufferBarriers.count),
                                                                                 imageMemoryBarriers: UnsafeBufferPointer<VkImageMemoryBarrier>(start: imageBarriersPtr, count: imageBarriers.count))
                
                compactedResourceCommands.append(CompactedResourceCommand<VulkanCompactedResourceCommandType>(command: command, index: dependency.wait.index, order: .before))
            }
        }
    }
    
    func compactResourceCommands(queue: Queue, resourceMap: FrameResourceMap<VulkanBackend>, commandInfo: FrameCommandInfo<VulkanBackend>, commandGenerator: ResourceCommandGenerator<VulkanBackend>, into compactedResourceCommands: inout [CompactedResourceCommand<VulkanCompactedResourceCommandType>]) {
        
        guard !commandGenerator.commands.isEmpty else { return }
        assert(compactedResourceCommands.isEmpty)
        
        self.generateEventCommands(queue: queue, resourceMap: resourceMap, frameCommandInfo: commandInfo, commandGenerator: commandGenerator, compactedResourceCommands: &compactedResourceCommands)
        
        
        let allocator = ThreadLocalTagAllocator(tag: FrameGraphContextImpl<VulkanBackend>.resourceCommandArrayTag)
        
        var currentEncoderIndex = 0
        var currentEncoder = commandInfo.commandEncoders[currentEncoderIndex]
        var currentPassIndex = 0
        
        var bufferBarriers = [VkBufferMemoryBarrier]()
        var imageBarriers = [VkImageMemoryBarrier]()
        
        var barrierAfterStages: VkPipelineStageFlagBits = []
        var barrierBeforeStages: VkPipelineStageFlagBits = []
        var barrierLastIndex: Int = .max
        
        let addBarrier: (inout [CompactedResourceCommand<VulkanCompactedResourceCommandType>]) -> Void = { compactedResourceCommands in
            
            let bufferBarriersPtr: UnsafeMutablePointer<VkBufferMemoryBarrier> = allocator.allocate(capacity: bufferBarriers.count)
            bufferBarriersPtr.initialize(from: bufferBarriers, count: bufferBarriers.count)
            
            let imageBarriersPtr: UnsafeMutablePointer<VkImageMemoryBarrier> = allocator.allocate(capacity: imageBarriers.count)
            imageBarriersPtr.initialize(from: imageBarriers, count: imageBarriers.count)
            
            let command: VulkanCompactedResourceCommandType = .pipelineBarrier(sourceStages: barrierAfterStages,
                                                                               destinationStages: barrierBeforeStages,
                                                                               dependencyFlags: VkDependencyFlagBits(rawValue: 0),
                                                                               memoryBarriers: UnsafeBufferPointer<VkMemoryBarrier>(start: nil, count: 0),
                                                                               bufferMemoryBarriers: UnsafeBufferPointer<VkBufferMemoryBarrier>(start: bufferBarriersPtr, count: bufferBarriers.count),
                                                                               imageMemoryBarriers: UnsafeBufferPointer<VkImageMemoryBarrier>(start: imageBarriersPtr, count: imageBarriers.count))
            compactedResourceCommands.append(.init(command: command, index: barrierLastIndex, order: .before))

            bufferBarriers.removeAll(keepingCapacity: true)
            imageBarriers.removeAll(keepingCapacity: true)
            barrierAfterStages = []
            barrierBeforeStages = []
            barrierLastIndex = .max
        }
        
        for command in commandGenerator.commands {
            if command.index > barrierLastIndex {
                addBarrier(&compactedResourceCommands)
            }
            
            while !commandInfo.passes[currentPassIndex].commandRange!.contains(command.index) {
                currentPassIndex += 1
            }
            
            while !currentEncoder.commandRange.contains(command.index) {
                currentEncoderIndex += 1
                currentEncoder = commandInfo.commandEncoders[currentEncoderIndex]
                
                assert(bufferBarriers.isEmpty)
                assert(imageBarriers.isEmpty)
            }
            
            // Strategy:
            // useResource should be batched together by usage to as early as possible in the encoder.
            // memoryBarriers should be as late as possible.
            switch command.command {
            case .useResource(let resource, let usage, let stages, let allowReordering):
                // Check whether we need to do a layout transition for an image resource.
                
                guard resource.type == .texture else {
                    break
                }
                
                // TODO: check for layout transitions.
                
            case .memoryBarrier(let resource, let afterUsage, let afterStages, let beforeCommand, let beforeUsage, let beforeStages):
                
                let pixelFormat =  resource.texture?.descriptor.pixelFormat ?? .invalid
                let isDepthOrStencil = pixelFormat.isDepth || pixelFormat.isStencil
                
                let sourceLayout = afterUsage.imageLayout(isDepthOrStencil: isDepthOrStencil)
                let destinationLayout = beforeUsage.imageLayout(isDepthOrStencil: isDepthOrStencil)
                
                let sourceMask = afterUsage.shaderStageMask(isDepthOrStencil: isDepthOrStencil, stages: afterStages)
                let destinationMask = beforeUsage.shaderStageMask(isDepthOrStencil: isDepthOrStencil, stages: beforeStages)
                
                let sourceAccessMask = afterUsage.accessMask(isDepthOrStencil: isDepthOrStencil).rawValue
                let destinationAccessMask = beforeUsage.accessMask(isDepthOrStencil: isDepthOrStencil).rawValue
                
                if let renderTargetDescriptor = currentEncoder.renderTargetDescriptor {
                    var subpassDependency = VkSubpassDependency()
                    subpassDependency.dependencyFlags = 0 // FIXME: ideally should be VkDependencyFlags(VK_DEPENDENCY_BY_REGION_BIT) for all cases except temporal AA.
                    if let passUsageSubpass = renderTargetDescriptor.subpassForPassIndex(currentPassIndex) {
                        subpassDependency.srcSubpass = UInt32(passUsageSubpass.index)
                    } else {
                        subpassDependency.srcSubpass = VK_SUBPASS_EXTERNAL
                    }
                    subpassDependency.srcStageMask = sourceMask.rawValue
                    subpassDependency.srcAccessMask = sourceAccessMask
                    
                    let dependentPass = commandInfo.passes[currentPassIndex...].first(where: { $0.commandRange!.contains(beforeCommand) })!
                    if let destinationUsageSubpass = renderTargetDescriptor.subpassForPassIndex(dependentPass.passIndex) {
                        subpassDependency.dstSubpass = UInt32(destinationUsageSubpass.index)
                    } else {
                        subpassDependency.dstSubpass = VK_SUBPASS_EXTERNAL
                    }
                    subpassDependency.dstStageMask = destinationMask.rawValue
                    subpassDependency.dstAccessMask = destinationAccessMask

                    // If the dependency is on an attachment, then we can let the subpass dependencies handle it, _unless_ both usages are in the same subpass.
                    // Otherwise, an image should always be in the right layout when it's materialised. The only case it won't be is if it's used in one way in
                    // a draw render pass (e.g. as a read texture) and then needs to transition layout before being used in a different type of pass.

                    if subpassDependency.srcSubpass == subpassDependency.dstSubpass {
                        precondition(resource.type == .texture, "We can only insert pipeline barriers within render passes for textures.")

                        renderTargetDescriptor.addDependency(subpassDependency)
                    } else if sourceLayout != destinationLayout, // guaranteed to not be a buffer since buffers have UNDEFINED image layouts above.
                                !afterUsage.isRenderTarget, !beforeUsage.isRenderTarget {
                        // We need to insert a pipeline barrier to handle a layout transition.
                        // We can therefore avoid a subpass dependency in most cases.

                        if subpassDependency.srcSubpass == VK_SUBPASS_EXTERNAL {
                            // Insert a pipeline barrier before the start of the Render Command Encoder.
                        } else if subpassDependency.dstSubpass == VK_SUBPASS_EXTERNAL {
                            // Insert a pipeline barrier before the next command after the render command encoder ends.
                        } else {
                            // Insert a subpass self-dependency and a pipeline barrier.
                            fatalError("This should have been handled by the subpassDependency.srcSubpass == subpassDependency.dstSubpass case.")

                            // resourceCommands.append(VulkanFrameResourceCommand(command: .pipelineBarrier(memoryBarrierInfo), index: dependentCommandIndex, order: .before))
                            // subpassDependency.srcSubpass = subpassDependency.dstSubpass
                            // renderTargetDescriptor.addDependency(subpassDependency)
                        }
                    } else {
                        // A subpass dependency should be enough to handle this case.
                        renderTargetDescriptor.addDependency(subpassDependency)
                        continue
                    }
                }
                
                if let buffer = resource.buffer {
                    var barrier = VkBufferMemoryBarrier()
                    barrier.buffer = resourceMap[buffer].buffer.vkBuffer
                    barrier.offset = 0
                    barrier.size = VK_WHOLE_SIZE // TODO: track at a more fine-grained level.
                    barrier.srcAccessMask = afterUsage.accessMask(isDepthOrStencil: false).rawValue
                    barrier.dstAccessMask = beforeUsage.accessMask(isDepthOrStencil: false).rawValue
                    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
                    barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
                    bufferBarriers.append(barrier)
                } else if let texture = resource.texture {
                    
                    var barrier = VkImageMemoryBarrier()
                    barrier.image = resourceMap[texture].image.vkImage
                    barrier.srcAccessMask = sourceAccessMask
                    barrier.dstAccessMask = destinationAccessMask
                    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
                    barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
                    barrier.oldLayout = afterUsage.imageLayout(isDepthOrStencil: isDepthOrStencil)
                    barrier.newLayout = beforeUsage.imageLayout(isDepthOrStencil: isDepthOrStencil)
                    barrier.subresourceRange = VkImageSubresourceRange(aspectMask: texture.descriptor.pixelFormat.aspectFlags, baseMipLevel: 0, levelCount: UInt32(texture.descriptor.mipmapLevelCount), baseArrayLayer: 0, layerCount: UInt32(texture.descriptor.arrayLength))
                    imageBarriers.append(barrier)
                }
                
                barrierAfterStages.formUnion(sourceMask)
                barrierBeforeStages.formUnion(destinationMask)
                barrierLastIndex = min(beforeCommand, barrierLastIndex)
            }
        }
        
        if barrierLastIndex < .max {
            addBarrier(&compactedResourceCommands)
        }
        
        compactedResourceCommands.sort()
    }
    
//    func generateResourceCommands(passes: [RenderPassRecord], resourceUsages: ResourceUsages, renderTargetDescriptors: [VulkanRenderTargetDescriptor?], lastCommandBufferIndex: UInt64) {
//
//        resourceLoop: for resource in resourceUsages.allResources {
//            let usages = resource.usages
//            if usages.isEmpty { continue }
//
//            var usageIterator = usages.makeIterator()
//
//            // Find the first used render pass.
//            var previousUsage : ResourceUsage
//            repeat {
//                guard let usage = usageIterator.next() else {
//                    continue resourceLoop // no active usages for this resource
//                }
//                previousUsage = usage
//            } while !previousUsage.renderPassRecord.isActive || (previousUsage.stages == .cpuBeforeRender && previousUsage.type != .unusedArgumentBuffer)
//
//            let materialisePass = previousUsage.renderPassRecord.passIndex
//            let materialiseIndex = previousUsage.commandRange.lowerBound
//
//            while previousUsage.type == .unusedArgumentBuffer || previousUsage.type == .unusedRenderTarget {
//                previousUsage = usageIterator.next()!
//            }
//
//            let firstUsage = previousUsage
//
//            while let usage = usageIterator.next()  {
//                if !usage.renderPassRecord.isActive || usage.stages == .cpuBeforeRender { continue }
//                defer { previousUsage = usage }
//
//                if !previousUsage.isWrite && !usage.isWrite { continue }
//
//                if previousUsage.type == usage.type && previousUsage.type.isRenderTarget {
//                    continue
//                }
//
//                do {
//                    // Manage memory dependency.
//
//                    var isDepthStencil = false
//                    if let texture = resource.texture, texture.descriptor.pixelFormat.isDepth || texture.descriptor.pixelFormat.isStencil {
//                        isDepthStencil = true
//                    }
//
//                    let passUsage = previousUsage
//                    let dependentUsage = usage
//
//                    let passCommandIndex = passUsage.commandRange.upperBound - 1
//                    let dependentCommandIndex = dependentUsage.commandRange.lowerBound
//
//                    let sourceAccessMask = passUsage.type.accessMask(isDepthOrStencil: isDepthStencil)
//                    let destinationAccessMask = dependentUsage.type.accessMask(isDepthOrStencil: isDepthStencil)
//
//                    let sourceMask = passUsage.type.shaderStageMask(isDepthOrStencil: isDepthStencil, stages: passUsage.stages)
//                    let destinationMask = dependentUsage.type.shaderStageMask(isDepthOrStencil: isDepthStencil, stages: dependentUsage.stages)
//
//                    let sourceLayout = resource.type == .texture ? passUsage.type.imageLayout(isDepthOrStencil: isDepthStencil) : VK_IMAGE_LAYOUT_UNDEFINED
//                    let destinationLayout = resource.type == .texture ? dependentUsage.type.imageLayout(isDepthOrStencil: isDepthStencil) : VK_IMAGE_LAYOUT_UNDEFINED
//
//                    if !passUsage.type.isRenderTarget, dependentUsage.type.isRenderTarget,
//                        renderTargetDescriptors[passUsage.renderPassRecord.passIndex] !== renderTargetDescriptors[dependentUsage.renderPassRecord.passIndex] {
//                        renderTargetDescriptors[dependentUsage.renderPassRecord.passIndex]!.initialLayouts[resource.texture!] = sourceLayout
//                    }
//
//                    if passUsage.type.isRenderTarget, !dependentUsage.type.isRenderTarget,
//                        renderTargetDescriptors[passUsage.renderPassRecord.passIndex] !== renderTargetDescriptors[dependentUsage.renderPassRecord.passIndex] {
//                        renderTargetDescriptors[passUsage.renderPassRecord.passIndex]!.finalLayouts[resource.texture!] = destinationLayout
//                    }
//
//                    let barrier : ResourceMemoryBarrier
//
//                    if let texture = resource.texture {
//                        var imageBarrierInfo = VkImageMemoryBarrier()
//                        imageBarrierInfo.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER
//                        imageBarrierInfo.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
//                        imageBarrierInfo.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
//                        imageBarrierInfo.srcAccessMask = VkAccessFlags(sourceAccessMask)
//                        imageBarrierInfo.dstAccessMask = VkAccessFlags(destinationAccessMask)
//                        imageBarrierInfo.oldLayout = sourceLayout
//                        imageBarrierInfo.newLayout = destinationLayout
//                        imageBarrierInfo.subresourceRange = VkImageSubresourceRange(aspectMask: texture.descriptor.pixelFormat.aspectFlags, baseMipLevel: 0, levelCount: UInt32(texture.descriptor.mipmapLevelCount), baseArrayLayer: 0, layerCount: UInt32(texture.descriptor.arrayLength))
//
//                        barrier = .texture(texture, imageBarrierInfo)
//                    } else if let buffer = resource.buffer {
//                        var bufferBarrierInfo = VkBufferMemoryBarrier()
//                        bufferBarrierInfo.sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER
//                        bufferBarrierInfo.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
//                        bufferBarrierInfo.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
//                        bufferBarrierInfo.srcAccessMask = VkAccessFlags(sourceAccessMask)
//                        bufferBarrierInfo.dstAccessMask = VkAccessFlags(destinationAccessMask)
//                        bufferBarrierInfo.offset = 0
//                        bufferBarrierInfo.size = VK_WHOLE_SIZE
//
//                        barrier = .buffer(buffer, bufferBarrierInfo)
//                    } else {
//                        fatalError()
//                    }
//
//                    var memoryBarrierInfo = MemoryBarrierInfo(sourceMask: sourceMask, destinationMask: destinationMask, barrier: barrier)
//
//                    if passUsage.renderPassRecord.pass.passType == .draw || dependentUsage.renderPassRecord.pass.passType == .draw {
//
//                        let renderTargetDescriptor = (renderTargetDescriptors[passUsage.renderPassRecord.passIndex] ?? renderTargetDescriptors[dependentUsage.renderPassRecord.passIndex])! // Add to the first pass if possible, the second pass if not.
//
//                        var subpassDependency = VkSubpassDependency()
//                        subpassDependency.dependencyFlags = 0 // FIXME: ideally should be VkDependencyFlags(VK_DEPENDENCY_BY_REGION_BIT) for all cases except temporal AA.
//                        if let passUsageSubpass = renderTargetDescriptor.subpassForPassIndex(passUsage.renderPassRecord.passIndex) {
//                            subpassDependency.srcSubpass = UInt32(passUsageSubpass.index)
//                        } else {
//                            subpassDependency.srcSubpass = VK_SUBPASS_EXTERNAL
//                        }
//                        subpassDependency.srcStageMask = VkPipelineStageFlags(sourceMask)
//                        subpassDependency.srcAccessMask = VkAccessFlags(sourceAccessMask)
//                        if let destinationUsageSubpass = renderTargetDescriptor.subpassForPassIndex(dependentUsage.renderPassRecord.passIndex) {
//                            subpassDependency.dstSubpass = UInt32(destinationUsageSubpass.index)
//                        } else {
//                            subpassDependency.dstSubpass = VK_SUBPASS_EXTERNAL
//                        }
//                        subpassDependency.dstStageMask = VkPipelineStageFlags(destinationMask)
//                        subpassDependency.dstAccessMask = VkAccessFlags(destinationAccessMask)
//
//                        // If the dependency is on an attachment, then we can let the subpass dependencies handle it, _unless_ both usages are in the same subpass.
//                        // Otherwise, an image should always be in the right layout when it's materialised. The only case it won't be is if it's used in one way in
//                        // a draw render pass (e.g. as a read texture) and then needs to transition layout before being used in a different type of pass.
//
//                        if subpassDependency.srcSubpass == subpassDependency.dstSubpass {
//                            guard case .texture(let textureHandle, var imageBarrierInfo) = barrier else {
//                                print("Source: \(passUsage), destination: \(dependentUsage)")
//                                fatalError("We can't insert pipeline barriers within render passes for buffers.")
//                            }
//
//                            if imageBarrierInfo.oldLayout != imageBarrierInfo.newLayout {
//                                imageBarrierInfo.oldLayout = VK_IMAGE_LAYOUT_GENERAL
//                                imageBarrierInfo.newLayout = VK_IMAGE_LAYOUT_GENERAL
//                                memoryBarrierInfo.barrier = .texture(textureHandle, imageBarrierInfo)
//                            }
//
//                            // Insert a subpass self-dependency.
//                            resourceCommands.append(VulkanFrameResourceCommand(command: .pipelineBarrier(memoryBarrierInfo), index: dependentCommandIndex, order: .before))
//
//                            renderTargetDescriptor.addDependency(subpassDependency)
//                        } else if sourceLayout != destinationLayout, // guaranteed to not be a buffer since buffers have UNDEFINED image layouts above.
//                                    !passUsage.type.isRenderTarget, !dependentUsage.type.isRenderTarget {
//                            // We need to insert a pipeline barrier to handle a layout transition.
//                            // We can therefore avoid a subpass dependency in most cases.
//
//                            if subpassDependency.srcSubpass == VK_SUBPASS_EXTERNAL {
//                                // Insert a pipeline barrier before the start of the Render Command Encoder.
//                                let firstPassInVkRenderPass = renderTargetDescriptors[dependentUsage.renderPassRecord.passIndex]!.renderPasses.first!
//                                let dependencyIndex = firstPassInVkRenderPass.commandRange!.lowerBound
//
//                                assert(dependencyIndex <= dependentUsage.commandRange.lowerBound)
//
//                                resourceCommands.append(VulkanFrameResourceCommand(command: .pipelineBarrier(memoryBarrierInfo), index: dependencyIndex, order: .before))
//                            } else if subpassDependency.dstSubpass == VK_SUBPASS_EXTERNAL {
//                                // Insert a pipeline barrier before the next command after the render command encoder ends.
//                                let lastPassInVkRenderPass = renderTargetDescriptors[dependentUsage.renderPassRecord.passIndex]!.renderPasses.last!
//                                let dependencyIndex = lastPassInVkRenderPass.commandRange!.upperBound
//
//                                assert(dependencyIndex <= passUsage.commandRange.lowerBound)
//
//                                resourceCommands.append(VulkanFrameResourceCommand(command: .pipelineBarrier(memoryBarrierInfo), index: dependencyIndex, order: .before))
//                            } else {
//                                // Insert a subpass self-dependency and a pipeline barrier.
//                                fatalError("This should have been handled by the subpassDependency.srcSubpass == subpassDependency.dstSubpass case.")
//
//                                // resourceCommands.append(VulkanFrameResourceCommand(command: .pipelineBarrier(memoryBarrierInfo), index: dependentCommandIndex, order: .before))
//                                // subpassDependency.srcSubpass = subpassDependency.dstSubpass
//                                // renderTargetDescriptor.addDependency(subpassDependency)
//                            }
//                        } else {
//                            // A subpass dependency should be enough to handle this case.
//                            renderTargetDescriptor.addDependency(subpassDependency)
//                        }
//
//                    } else {
//
//                        let event = FenceDependency(label: "Memory dependency for \(resource)", queue: self.frameGraphQueue, commandBufferIndex: lastCommandBufferIndex)
//
//                        if self.backend.device.physicalDevice.queueFamilyIndex(renderPassType: passUsage.renderPassRecord.pass.passType) != self.backend.device.physicalDevice.queueFamilyIndex(renderPassType: dependentUsage.renderPassRecord.pass.passType) {
//                            // Assume that the resource has a concurrent sharing mode.
//                            // If the sharing mode is concurrent, then we only need to insert a barrier for an image layout transition.
//                            // Otherwise, we would need to do a queue ownership transfer.
//
//                            // TODO: we should make all persistent resources concurrent if necessary, and all frame resources exclusive (unless they have two consecutive reads).
//                            // The logic here will then change to insert a pipeline barrier on each queue with an ownership transfer, unconditional on being a buffer or texture.
//
//                            if case .texture = barrier { // We only need to insert a barrier to do a layout transition.
//                                //  resourceCommands.append(VulkanFrameResourceCommand(command: .pipelineBarrier(memoryBarrierInfo), index: passCommandIndex - 1, order: .after))
//                                resourceCommands.append(VulkanFrameResourceCommand(command: .pipelineBarrier(memoryBarrierInfo), index: dependentCommandIndex, order: .before))
//                            }
//                            // Also use a semaphore, since they're on different queues
//                            resourceCommands.append(VulkanFrameResourceCommand(command: .signalEvent(event, afterStages: sourceMask), index: passCommandIndex, order: .after))
//                            resourceCommands.append(VulkanFrameResourceCommand(command: .waitForEvent(event, info: memoryBarrierInfo), index: dependentCommandIndex, order: .before))
//                        } else if previousUsage.isWrite || usage.isWrite {
//                            // If either of these take place within a render pass, they need to be inserted as pipeline barriers instead and added
//                            // as subpass dependencise if relevant.
//
//                            resourceCommands.append(VulkanFrameResourceCommand(command: .signalEvent(event, afterStages: sourceMask), index: passCommandIndex, order: .after))
//                            resourceCommands.append(VulkanFrameResourceCommand(command: .waitForEvent(event, info: memoryBarrierInfo), index: dependentCommandIndex, order: .before))
//                        } else if case .texture = barrier, sourceLayout != destinationLayout { // We only need to insert a barrier to do a layout transition.
//                            // TODO: We could minimise the number of layout transitions with a lookahead approach.
//                            resourceCommands.append(VulkanFrameResourceCommand(command: .pipelineBarrier(memoryBarrierInfo), index: dependentCommandIndex, order: .before))
//                        }
//                    }
//
//                }
//            }
//
//            let lastUsage = previousUsage
//
//            let historyBufferCreationFrame = resource.flags.contains(.historyBuffer) && !resource.stateFlags.contains(.initialised)
//            let historyBufferUseFrame = resource.flags.contains(.historyBuffer) && resource.stateFlags.contains(.initialised)
//
//            // Insert commands to materialise and dispose of the resource.
//
//            if let buffer = resource.buffer {
//
//                var isModified = false
//                var queueFamilies : QueueCapabilities = []
//                var bufferUsage : VkBufferUsageFlagBits = []
//
//                if buffer.flags.contains(.historyBuffer) {
//                    bufferUsage.formUnion(VkBufferUsageFlagBits(buffer.descriptor.usageHint))
//                }
//
//                for usage in usages where usage.renderPassRecord.isActive && usage.stages != .cpuBeforeRender {
//                    switch usage.renderPassRecord.pass.passType {
//                    case .draw:
//                        queueFamilies.formUnion(.graphics)
//                    case .compute:
//                        queueFamilies.formUnion(.compute)
//                    case .blit:
//                        queueFamilies.formUnion(.copy)
//                    case .cpu, .external:
//                        break
//                    }
//
//                    switch usage.type {
//                    case .constantBuffer:
//                        bufferUsage.formUnion(.uniformBuffer)
//                    case .read:
//                        bufferUsage.formUnion([.uniformTexelBuffer, .storageBuffer, .storageTexelBuffer])
//                    case .write, .readWrite:
//                        isModified = true
//                        bufferUsage.formUnion([.storageBuffer, .storageTexelBuffer])
//                    case .blitSource:
//                        bufferUsage.formUnion(.transferSource)
//                    case .blitDestination:
//                        isModified = true
//                        bufferUsage.formUnion(.transferDestination)
//                    case .blitSynchronisation:
//                        isModified = true
//                        bufferUsage.formUnion([.transferSource, .transferDestination])
//                    case .vertexBuffer:
//                        bufferUsage.formUnion(.vertexBuffer)
//                    case .indexBuffer:
//                        bufferUsage.formUnion(.indexBuffer)
//                    case .indirectBuffer:
//                        bufferUsage.formUnion(.indirectBuffer)
//                    case .readWriteRenderTarget, .writeOnlyRenderTarget, .inputAttachmentRenderTarget, .unusedRenderTarget, .sampler, .inputAttachment:
//                        fatalError()
//                    case .unusedArgumentBuffer:
//                        break
//                    }
//                }
//
//                preFrameResourceCommands.append(
//                    VulkanPreFrameResourceCommand(command:
//                        .materialiseBuffer(buffer, usage: bufferUsage),
//                                                  passIndex: firstUsage.renderPassRecord.passIndex,
//                                    index: materialiseIndex, order: .before)
//                )
//
//                if !historyBufferCreationFrame && !buffer.flags.contains(.persistent) {
//                    preFrameResourceCommands.append(VulkanPreFrameResourceCommand(command: .disposeResource(Resource(buffer)), passIndex: lastUsage.renderPassRecord.passIndex, index: lastUsage.commandRange.upperBound - 1, order: .after))
//                } else {
//                    if isModified { // FIXME: what if we're reading from something that the next frame will modify?
//                        let sourceMask = lastUsage.type.shaderStageMask(isDepthOrStencil: false, stages: lastUsage.stages)
//
//                        fatalError("Do we need a pipeline barrier here? We should at least make sure we set the semaphore to wait on.")
//                    }
//                }
//
//            } else if let texture = resource.texture {
//                let isDepthStencil = texture.descriptor.pixelFormat.isDepth || texture.descriptor.pixelFormat.isStencil
//
//                var isModified = false
//                var queueFamilies : QueueCapabilities = []
//
//                var textureUsage : VkImageUsageFlagBits = []
//                if texture.flags.contains(.historyBuffer) {
//                    textureUsage.formUnion(VkImageUsageFlagBits(texture.descriptor.usageHint, pixelFormat: texture.descriptor.pixelFormat))
//                }
//
//                var previousUsage : ResourceUsage? = nil
//
//                for usage in usages where usage.renderPassRecord.isActive && usage.stages != .cpuBeforeRender {
//                    defer { previousUsage = usage }
//
//                    switch usage.renderPassRecord.pass.passType {
//                    case .draw:
//                        queueFamilies.formUnion(.graphics)
//                    case .compute:
//                        queueFamilies.formUnion(.compute)
//                    case .blit:
//                        queueFamilies.formUnion(.copy)
//                    case .cpu, .external:
//                        break
//                    }
//
//                    switch usage.type {
//                    case .read:
//                        textureUsage.formUnion(.sampled)
//                    case .write, .readWrite:
//                        isModified = true
//                        textureUsage.formUnion(.storage)
//                    case .inputAttachment:
//                        textureUsage.formUnion(.inputAttachment)
//                    case .unusedRenderTarget:
//                        if isDepthStencil {
//                            textureUsage.formUnion(.depthStencilAttachment)
//                        } else {
//                            textureUsage.formUnion(.colorAttachment)
//                        }
//                    case .readWriteRenderTarget, .writeOnlyRenderTarget:
//                        isModified = true
//                        if isDepthStencil {
//                            textureUsage.formUnion(.depthStencilAttachment)
//                        } else {
//                            textureUsage.formUnion(.colorAttachment)
//                        }
//                    case .inputAttachmentRenderTarget:
//                        textureUsage.formUnion(.inputAttachment)
//                    case .blitSource:
//                        textureUsage.formUnion(.transferSource)
//                    case .blitDestination:
//                        isModified = true
//                        textureUsage.formUnion(.transferDestination)
//                    case .blitSynchronisation:
//                        isModified = true
//                        textureUsage.formUnion([.transferSource, .transferDestination])
//                    case .vertexBuffer, .indexBuffer, .indirectBuffer, .constantBuffer, .sampler:
//                        fatalError()
//                    case .unusedArgumentBuffer:
//                        break
//                    }
//                }
//
//                do {
//                    let textureAlreadyExists = texture.flags.contains(.persistent) || historyBufferUseFrame
//
//                    let destinationAccessMask = firstUsage.type.accessMask(isDepthOrStencil: isDepthStencil)
//                    let destinationMask = firstUsage.type.shaderStageMask(isDepthOrStencil: isDepthStencil, stages: firstUsage.stages)
//                    let destinationLayout = firstUsage.type.imageLayout(isDepthOrStencil: isDepthStencil)
//
//                    var imageBarrierInfo = VkImageMemoryBarrier()
//                    imageBarrierInfo.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER
//                    imageBarrierInfo.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
//                    imageBarrierInfo.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
//                    imageBarrierInfo.srcAccessMask = VkAccessFlags([] as VkAccessFlagBits) // since it's already been synchronised in a different way.
//                    imageBarrierInfo.dstAccessMask = VkAccessFlags(destinationAccessMask)
//                    imageBarrierInfo.oldLayout = textureAlreadyExists ? VK_IMAGE_LAYOUT_PREINITIALIZED : VK_IMAGE_LAYOUT_UNDEFINED
//                    imageBarrierInfo.newLayout = firstUsage.type.isRenderTarget ? imageBarrierInfo.oldLayout : destinationLayout
//                    imageBarrierInfo.subresourceRange = VkImageSubresourceRange(aspectMask: texture.descriptor.pixelFormat.aspectFlags, baseMipLevel: 0, levelCount: UInt32(texture.descriptor.mipmapLevelCount), baseArrayLayer: 0, layerCount: UInt32(texture.descriptor.arrayLength))
//
//                    let commandType = VulkanPreFrameResourceCommands.materialiseTexture(texture, usage: textureUsage, destinationMask: destinationMask, barrier: imageBarrierInfo)
//
//
//                    if firstUsage.renderPassRecord.pass.passType == .draw {
//                        // Materialise the texture (performing layout transitions) before we begin the Vulkan render pass.
//                        let firstPass = renderTargetDescriptors[firstUsage.renderPassRecord.passIndex]!.renderPasses.first!
//
//                        if firstUsage.type.isRenderTarget {
//                            // We're not doing a layout transition here, so set the initial layout for the render pass
//                            // to the texture's current, actual layout.
//                            let vulkanTexture = resourceMap[texture]
//                            renderTargetDescriptors[firstUsage.renderPassRecord.passIndex]!.initialLayouts[texture] = vulkanTexture.layout
//                        }
//                    }
//
//                    preFrameResourceCommands.append(
//                        VulkanPreFrameResourceCommand(command: commandType,
//                                                      passIndex: materialisePass, index: materialiseIndex, order: .before))
//                }
//
//                let needsStore = historyBufferCreationFrame || texture.flags.contains(.persistent)
//                if !needsStore || texture.flags.contains(.windowHandle) {
//                    // We need to dispose window handle textures just to make sure their texture references are removed from the resource registry.
//                    preFrameResourceCommands.append(VulkanPreFrameResourceCommand(command: .disposeResource(Resource(texture)), passIndex: lastUsage.renderPassRecord.passIndex, index: lastUsage.commandRange.upperBound - 1, order: .after))
//                }
//                if needsStore && isModified {
//                    let sourceMask = lastUsage.type.shaderStageMask(isDepthOrStencil: isDepthStencil, stages: lastUsage.stages)
//
//                    var finalLayout : VkImageLayout? = nil
//
//                    if lastUsage.type.isRenderTarget {
//                        renderTargetDescriptors[lastUsage.renderPassRecord.passIndex]!.finalLayouts[texture] = VK_IMAGE_LAYOUT_GENERAL
//                        finalLayout = VK_IMAGE_LAYOUT_GENERAL
//                    }
//
//
//                    fatalError("Do we need a pipeline barrier here? We should at least make sure we set the semaphore to wait on, and maybe a pipeline barrier is necessary as well for non render-target textures.")
//                }
//
//            }
//        }
//
//        self.preFrameResourceCommands.sort()
//        self.resourceCommands.sort()
//    }
    
}

enum VulkanResourceMemoryBarrier {
    case texture(Texture, VkImageMemoryBarrier)
    case buffer(Buffer, VkBufferMemoryBarrier)
}

struct VulkanMemoryBarrierInfo {
    var sourceMask : VkPipelineStageFlagBits
    var destinationMask : VkPipelineStageFlagBits
    var barrier : VulkanResourceMemoryBarrier
}

enum VulkanCompactedResourceCommandType {
    case signalEvent(VkEvent, afterStages: VkPipelineStageFlagBits)
    
    case waitForEvents(_ events: UnsafeBufferPointer<VkEvent?>, sourceStages: VkPipelineStageFlagBits, destinationStages: VkPipelineStageFlagBits, memoryBarriers: UnsafeBufferPointer<VkMemoryBarrier>, bufferMemoryBarriers: UnsafeBufferPointer<VkBufferMemoryBarrier>, imageMemoryBarriers: UnsafeBufferPointer<VkImageMemoryBarrier>)
    
    case pipelineBarrier(sourceStages: VkPipelineStageFlagBits, destinationStages: VkPipelineStageFlagBits, dependencyFlags: VkDependencyFlagBits, memoryBarriers: UnsafeBufferPointer<VkMemoryBarrier>, bufferMemoryBarriers: UnsafeBufferPointer<VkBufferMemoryBarrier>, imageMemoryBarriers: UnsafeBufferPointer<VkImageMemoryBarrier>)
}


#endif // canImport(Vulkan)
