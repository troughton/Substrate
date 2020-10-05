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

extension VkImageSubresourceRange {
    func overlaps(with otherRange: VkImageSubresourceRange) -> Bool {
        let layersOverlap = (self.baseArrayLayer..<(self.baseArrayLayer + self.layerCount)).overlaps(otherRange.baseArrayLayer..<otherRange.baseArrayLayer + otherRange.layerCount)
        let levelsOverlap = (self.baseMipLevel..<(self.baseMipLevel + self.levelCount)).overlaps(otherRange.baseMipLevel..<(otherRange.baseMipLevel + otherRange.levelCount))
        return layersOverlap && levelsOverlap
    }
}

extension Array where Element == VkImageMemoryBarrier {
    mutating func appendBarrier(_ barrier: VkImageMemoryBarrier) {
        assert(!self.contains(where: { $0.image == barrier.image && $0.subresourceRange.overlaps(with: barrier.subresourceRange) }), "Trying to add barrier \(barrier) but \(self.first(where: { $0.image == barrier.image && $0.subresourceRange.overlaps(with: barrier.subresourceRange) })!) already exists")
        self.append(barrier)
    }
    
    mutating func appendBarriers(_ barriers: [VkImageMemoryBarrier]) {
        for barrier in barriers {
            assert(!self.contains(where: { $0.image == barrier.image && $0.subresourceRange.overlaps(with: barrier.subresourceRange) }), "Trying to add barrier \(barrier) but \(self.first(where: { $0.image == barrier.image && $0.subresourceRange.overlaps(with: barrier.subresourceRange) })!) already exists")
        }
        self.append(contentsOf: barriers)
    }
}

extension VulkanBackend {
    
    func processImageSubresourceRanges(_ activeMask: inout SubresourceMask, textureDescriptor: TextureDescriptor, allocator: AllocatorType, action: (VkImageSubresourceRange) -> Void) {
        var subresourceRange = VkImageSubresourceRange(aspectMask: textureDescriptor.pixelFormat.aspectFlags, baseMipLevel: 0, levelCount: UInt32(textureDescriptor.mipmapLevelCount), baseArrayLayer: 0, layerCount: UInt32(textureDescriptor.arrayLength))
        for level in 0..<textureDescriptor.mipmapLevelCount {
            for slice in 0..<textureDescriptor.slicesPerLevel {
                if activeMask[slice: slice, level: level, descriptor: textureDescriptor] {
                    subresourceRange.baseArrayLayer = UInt32(slice)
                    subresourceRange.baseMipLevel = UInt32(level)
                    
                    let endSlice = (0..<textureDescriptor.slicesPerLevel).dropFirst(slice + 1).first(where: { !activeMask[slice: $0, level: level, descriptor: textureDescriptor] }) ?? textureDescriptor.slicesPerLevel
                    subresourceRange.layerCount = UInt32(endSlice - slice)
                 
                    let endLevel = (0..<textureDescriptor.mipmapLevelCount).dropFirst(level + 1).first(where: { testLevel in
                        !(slice..<endSlice).allSatisfy({ activeMask[slice: $0, level: testLevel, descriptor: textureDescriptor] })
                    }) ?? textureDescriptor.mipmapLevelCount

                    subresourceRange.levelCount = UInt32(endLevel - level)
                    assert(endLevel - level <= textureDescriptor.mipmapLevelCount)
                    
                    for l in level..<endLevel {
                        for s in slice..<endSlice {
                            activeMask[slice: s, level: l, descriptor: textureDescriptor, allocator: allocator] = false
                        }
                    }
                    action(subresourceRange)
                }
            }
        }
    }
    
    func generateEventCommands(queue: Queue, resourceMap: FrameResourceMap<VulkanBackend>, frameCommandInfo: FrameCommandInfo<VulkanBackend>, commandGenerator: ResourceCommandGenerator<VulkanBackend>, compactedResourceCommands: inout [CompactedResourceCommand<VulkanCompactedResourceCommandType>]) {
        // MARK: - Generate the events
        
        let dependencies: DependencyTable<FineDependency?> = commandGenerator.commandEncoderDependencies
        
        let commandEncoderCount = frameCommandInfo.commandEncoders.count
        let reductionMatrix = dependencies.transitiveReduction(hasDependency: { $0 != nil })
        
        let allocator = ThreadLocalTagAllocator(tag: .frameGraphResourceCommandArrayTag)
        
        for sourceIndex in (0..<commandEncoderCount) { // sourceIndex always points to the producing pass.
            let dependentRange = min(sourceIndex + 1, commandEncoderCount)..<commandEncoderCount
            
            var signalStages: VkPipelineStageFlagBits = []
            var signalIndex = -1
            for dependentIndex in dependentRange where reductionMatrix.dependency(from: dependentIndex, on: sourceIndex) {
                let dependency = dependencies.dependency(from: dependentIndex, on: sourceIndex)!
                
                for (resource, producingUsage, _) in dependency.resources {
                    let pixelFormat = resource.texture?.descriptor.pixelFormat ?? .invalid
                    let isDepthOrStencil = pixelFormat.isDepth || pixelFormat.isStencil
                    signalStages.formUnion(producingUsage.type.shaderStageMask(isDepthOrStencil: isDepthOrStencil, stages: producingUsage.stages))
                }
                
                signalIndex = max(signalIndex, dependency.signal.index)
            }
            
            if signalIndex < 0 { continue }
            
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
                        barrier.sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER
                        barrier.buffer = resourceMap[buffer].buffer.vkBuffer
                        barrier.offset = 0
                        barrier.size = VK_WHOLE_SIZE
                        if case .buffer(let rangeA) = producingUsage.activeRange, case .buffer(let rangeB) = consumingUsage.activeRange {
                            let range = min(rangeA.lowerBound, rangeB.lowerBound)..<max(rangeA.upperBound, rangeB.upperBound)
                            barrier.offset = VkDeviceSize(range.lowerBound)
                            barrier.size = VkDeviceSize(range.count)
                        }
                        barrier.srcAccessMask = producingUsage.type.accessMask(isDepthOrStencil: false).rawValue
                        barrier.dstAccessMask = consumingUsage.type.accessMask(isDepthOrStencil: false).rawValue
                        barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
                        barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
                        bufferBarriers.append(barrier)
                    } else if let texture = resource.texture {
                        let textureDescriptor = texture.descriptor
                        let pixelFormat = textureDescriptor.pixelFormat
                        isDepthOrStencil = pixelFormat.isDepth || pixelFormat.isStencil
                        
                        let image = resource.texture.map({ resourceMap[$0].image })!
                        
                        var barrier = VkImageMemoryBarrier()
                        barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER
                        barrier.image = resourceMap[texture].image.vkImage
                        barrier.srcAccessMask = producingUsage.type.accessMask(isDepthOrStencil: isDepthOrStencil).rawValue
                        barrier.dstAccessMask = consumingUsage.type.accessMask(isDepthOrStencil: isDepthOrStencil).rawValue
                        barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
                        barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
                        barrier.oldLayout = image.layout(commandIndex: producingUsage.commandRange.last!, subresourceRange: producingUsage.activeRange)
                        barrier.newLayout = image.layout(commandIndex: consumingUsage.commandRange.first!, subresourceRange: consumingUsage.activeRange)

                        if !producingUsage.isWrite, !consumingUsage.isWrite, barrier.oldLayout == barrier.newLayout {
                            continue // This would only be a layout transition barrrier, and we don't need to transition layouts.
                        }

                        if producingUsage.type.isRenderTarget || consumingUsage.type.isRenderTarget {
                            // Handle this through a subpass dependency.
                            // TODO: when we support queue ownership transfers, we may also need a pipeline barrier here.
                            var subpassDependency = VkSubpassDependency()
                            let renderTargetDescriptor: VulkanRenderTargetDescriptor
                            if producingUsage.type.isRenderTarget {
                                // We transitioned to the new layout at the end of the previous render pass.
                                // Add a subpass dependency and continue.
                                barrier.oldLayout = barrier.newLayout
                                renderTargetDescriptor = frameCommandInfo.commandEncoders[sourceIndex].renderTargetDescriptor!
                                subpassDependency.srcSubpass = UInt32(renderTargetDescriptor.subpasses.last!.index)
                                subpassDependency.dstSubpass = VK_SUBPASS_EXTERNAL
                            } else {
                                // The layout transition will be handled by the next render pass.
                                // Add a subpass dependency and continue.
                                barrier.newLayout = barrier.oldLayout
                                renderTargetDescriptor = frameCommandInfo.commandEncoders[dependentIndex].renderTargetDescriptor!
                                subpassDependency.srcSubpass = VK_SUBPASS_EXTERNAL
                                subpassDependency.dstSubpass = 0
                            }

                            subpassDependency.srcStageMask = producingUsage.type.shaderStageMask(isDepthOrStencil: isDepthOrStencil, stages: producingUsage.stages).rawValue
                            subpassDependency.srcAccessMask = barrier.srcAccessMask
                            subpassDependency.dstStageMask = consumingUsage.type.shaderStageMask(isDepthOrStencil: isDepthOrStencil, stages: consumingUsage.stages).rawValue
                            subpassDependency.dstAccessMask = barrier.dstAccessMask

                            renderTargetDescriptor.addDependency(subpassDependency) 
                            continue
                        } else {
                            let previousUsage = texture.usages.lazy.filter { $0.affectsGPUBarriers }.prefix(while: { !$0.commandRange.contains(consumingUsage.commandRange.first!) }).last
                            if let previousUsage = previousUsage, !previousUsage.isWrite {
                                // There were other reads before consumingUsage, of which the first would have performed the layout transition; therefore, we don't need to transition here.
                                barrier.oldLayout = barrier.newLayout
                            }
                        }
                        barrier.subresourceRange = VkImageSubresourceRange(aspectMask: textureDescriptor.pixelFormat.aspectFlags, baseMipLevel: 0, levelCount: UInt32(textureDescriptor.mipmapLevelCount), baseArrayLayer: 0, layerCount: UInt32(textureDescriptor.arrayLength))

                        switch (producingUsage.activeRange, consumingUsage.activeRange) {
                        case (.texture(let mask), .fullResource),
                         (.fullResource, .texture(let mask)):
                            if mask.value == .max {
                                imageBarriers.appendBarrier(barrier)
                            } else {
                                var activeMask = SubresourceMask(source: mask, subresourceCount: textureDescriptor.subresourceCount, allocator: AllocatorType(allocator))
                                processImageSubresourceRanges(&activeMask, textureDescriptor: textureDescriptor, allocator: AllocatorType(allocator)) {
                                    barrier.subresourceRange = $0
                                    imageBarriers.appendBarrier(barrier)
                                }
                            }
                            
                        case (.texture(let maskA), .texture(let maskB)):
                            var activeMask = SubresourceMask(source: maskA, subresourceCount: textureDescriptor.subresourceCount, allocator: AllocatorType(allocator))
                            activeMask.formIntersection(with: maskB, subresourceCount: textureDescriptor.subresourceCount, allocator: AllocatorType(allocator))
                            
                            processImageSubresourceRanges(&activeMask, textureDescriptor: textureDescriptor, allocator: AllocatorType(allocator)) {
                                barrier.subresourceRange = $0
                                imageBarriers.appendBarrier(barrier)
                            }
                            
                        case (.fullResource, .fullResource):
                            imageBarriers.appendBarrier(barrier)
                        default:
                            fatalError()
                        }
                        
                    } else {
                        fatalError()
                    }
                    
                    destinationStages.formUnion(consumingUsage.type.shaderStageMask(isDepthOrStencil: isDepthOrStencil, stages: consumingUsage.stages))
                }

                if signalStages.isEmpty || destinationStages.isEmpty {
                    // Everything has been handled by either pipeline barriers or subpass dependencies, so we don't need a vkCmdWaitEvents.
                    continue
                }

                let label = "Encoder \(sourceIndex) Event"
                let sourceEncoder = frameCommandInfo.commandEncoders[sourceIndex]
                let commandBufferSignalValue = frameCommandInfo.signalValue(commandBufferIndex: sourceEncoder.commandBufferIndex)
                let fence = VulkanEventHandle(label: label, queue: queue, commandBufferIndex: commandBufferSignalValue)

                if sourceEncoder.type == .draw {
                    signalIndex = max(signalIndex, sourceEncoder.commandRange.last!) // We can't signal within a VkRenderPass instance.
                }
                
                compactedResourceCommands.append(CompactedResourceCommand<VulkanCompactedResourceCommandType>(command: .signalEvent(fence.event, afterStages: signalStages), index: signalIndex, order: .after))
                
                let bufferBarriersPtr: UnsafeMutablePointer<VkBufferMemoryBarrier> = allocator.allocate(capacity: bufferBarriers.count)
                bufferBarriersPtr.initialize(from: bufferBarriers, count: bufferBarriers.count)
                
                let imageBarriersPtr: UnsafeMutablePointer<VkImageMemoryBarrier> = allocator.allocate(capacity: imageBarriers.count)
                imageBarriersPtr.initialize(from: imageBarriers, count: imageBarriers.count)
                
                let command: VulkanCompactedResourceCommandType = .waitForEvents(UnsafeBufferPointer(start: fence.eventPointer, count: 1),
                                                                                 sourceStages: signalStages, destinationStages: destinationStages,
                                                                                 memoryBarriers: UnsafeBufferPointer<VkMemoryBarrier>(start: nil, count: 0),
                                                                                 bufferMemoryBarriers: UnsafeBufferPointer<VkBufferMemoryBarrier>(start: bufferBarriersPtr, count: bufferBarriers.count),
                                                                                 imageMemoryBarriers: UnsafeBufferPointer<VkImageMemoryBarrier>(start: imageBarriersPtr, count: imageBarriers.count))
                
                var waitIndex = dependency.wait.index
                let dependentEncoder = frameCommandInfo.commandEncoders[dependentIndex]
                if dependentEncoder.type == .draw {
                    waitIndex = dependentEncoder.commandRange.first! // We can't wait within a VkRenderPass instance.
                }

                compactedResourceCommands.append(CompactedResourceCommand<VulkanCompactedResourceCommandType>(command: command, index: waitIndex, order: .before))
            }
        }
    }
    
    func compactResourceCommands(queue: Queue, resourceMap: FrameResourceMap<VulkanBackend>, commandInfo: FrameCommandInfo<VulkanBackend>, commandGenerator: ResourceCommandGenerator<VulkanBackend>, into compactedResourceCommands: inout [CompactedResourceCommand<VulkanCompactedResourceCommandType>]) {
        
        guard !commandGenerator.commands.isEmpty else { return }
        assert(compactedResourceCommands.isEmpty)
        
        self.generateEventCommands(queue: queue, resourceMap: resourceMap, frameCommandInfo: commandInfo, commandGenerator: commandGenerator, compactedResourceCommands: &compactedResourceCommands)
        
        
        let allocator = ThreadLocalTagAllocator(tag: .frameGraphResourceCommandArrayTag)
        
        var currentEncoderIndex = 0
        var currentEncoder = commandInfo.commandEncoders[currentEncoderIndex]
        var currentPassIndex = 0
        
        var bufferBarriers = [VkBufferMemoryBarrier]()
        var imageBarriers = [VkImageMemoryBarrier]()
        
        var barrierAfterStages: VkPipelineStageFlagBits = []
        var barrierBeforeStages: VkPipelineStageFlagBits = []
        var barrierLastIndex: Int = .max
        
        var layoutTransitionOnlyBarriers = [VkImageMemoryBarrier]()
        var layoutTransitionOnlyBarrierBeforeStages: VkPipelineStageFlagBits = []
        var layoutTransitionOnlyBarrierLastIndex: Int = .max
        
        let addBarrier: (inout [CompactedResourceCommand<VulkanCompactedResourceCommandType>]) -> Void = { compactedResourceCommands in
            let combinedBarrierIndex = min(layoutTransitionOnlyBarrierLastIndex, barrierLastIndex)
            let barrierEncoder = commandInfo.commandEncoders.first(where: { $0.commandRange.contains(combinedBarrierIndex) })!
            if barrierEncoder.type != .draw {
                imageBarriers.appendBarriers(layoutTransitionOnlyBarriers)
                barrierAfterStages.formUnion(VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT)
                barrierBeforeStages.formUnion(layoutTransitionOnlyBarrierBeforeStages)
                barrierLastIndex = combinedBarrierIndex
                
                layoutTransitionOnlyBarriers.removeAll(keepingCapacity: true)
                layoutTransitionOnlyBarrierBeforeStages = []
                layoutTransitionOnlyBarrierLastIndex = .max
            }
            
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
        
        func processMemoryBarrier(resource: Resource, afterCommand: Int, afterUsageType: ResourceUsageType, afterStages: RenderStages, beforeCommand: Int, beforeUsageType: ResourceUsageType, beforeStages: RenderStages, activeRange: ActiveResourceRange) {
            var remainingRange = ActiveResourceRange.inactive // The subresource range not processed by this barrier.
            var activeRange = activeRange
            
            let pixelFormat =  resource.texture?.descriptor.pixelFormat ?? .invalid
            let isDepthOrStencil = pixelFormat.isDepth || pixelFormat.isStencil

            let sourceLayout: VkImageLayout
            let destinationLayout: VkImageLayout
            if let image = resource.texture.map({ resourceMap[$0].image }) {
                if afterUsageType == .frameStartLayoutTransitionCheck {
                    if !resource._usesPersistentRegistry {
                        sourceLayout = VK_IMAGE_LAYOUT_UNDEFINED
                    } else {
                        (sourceLayout, activeRange, remainingRange) = image.frameInitialLayout(for: activeRange, allocator: AllocatorType(allocator))
                    }
                } else {
                    sourceLayout = image.layout(commandIndex: afterCommand, subresourceRange: activeRange)
                }
                
                destinationLayout = image.layout(commandIndex: beforeCommand, subresourceRange: activeRange)

            } else {
                assert(resource.type != .texture || resource.flags.contains(.windowHandle))
                sourceLayout = VK_IMAGE_LAYOUT_UNDEFINED
                destinationLayout = VK_IMAGE_LAYOUT_UNDEFINED
            }
            
            defer {
                // It's possible there are multiple source layouts/subresource ranges, in which case we insert multiple barriers.
                if !remainingRange.isEqual(to: .inactive, resource: resource) {
                    processMemoryBarrier(resource: resource, afterCommand: afterCommand, afterUsageType: afterUsageType, afterStages: afterStages, beforeCommand: beforeCommand, beforeUsageType: beforeUsageType, beforeStages: beforeStages, activeRange: remainingRange)
                }
            }
            
            if sourceLayout == destinationLayout, afterUsageType == .frameStartLayoutTransitionCheck || (!afterUsageType.isWrite && !beforeUsageType.isWrite) {
                return // No layout transition needed, and no execution barrier needed, so we don't need to insert a memory barrier.
            }
            
            // We can't insert layout transition barriers during a render pass if the barriers are not applicable to that render encoder;
            // instead, defer them until compute work/as late as necessary.
            let isLayoutTransitionOnlyBarrierForDifferentEncoder = afterUsageType == .frameStartLayoutTransitionCheck && !currentEncoder.commandRange.contains(beforeCommand)
            
            let sourceMask = afterUsageType.shaderStageMask(isDepthOrStencil: isDepthOrStencil, stages: afterStages)
            let destinationMask = beforeUsageType.shaderStageMask(isDepthOrStencil: isDepthOrStencil, stages: beforeStages)
            
            let sourceAccessMask = afterUsageType.accessMask(isDepthOrStencil: isDepthOrStencil).rawValue
            let destinationAccessMask = beforeUsageType.accessMask(isDepthOrStencil: isDepthOrStencil).rawValue

            var beforeCommand = beforeCommand
            
            if let renderTargetDescriptor = currentEncoder.renderTargetDescriptor, beforeCommand > currentEncoder.commandRange.lowerBound, !isLayoutTransitionOnlyBarrierForDifferentEncoder {
                var subpassDependency = VkSubpassDependency()
                subpassDependency.dependencyFlags = VkDependencyFlags(VK_DEPENDENCY_BY_REGION_BIT) // FIXME: ideally should be VkDependencyFlags(VK_DEPENDENCY_BY_REGION_BIT) for all cases except temporal AA.
                if afterUsageType == .frameStartLayoutTransitionCheck {
                    subpassDependency.srcSubpass = VK_SUBPASS_EXTERNAL
                } else if let passUsageSubpass = renderTargetDescriptor.subpassForPassIndex(currentPassIndex) {
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
                    assert(subpassDependency.srcSubpass != VK_SUBPASS_EXTERNAL, "Dependent pass \(dependentPass.passIndex): Subpass dependency from \(afterUsageType) (afterCommand \(afterCommand)) to \(beforeUsageType) (beforeCommand \(beforeCommand)) for resource \(resource) is EXTERNAL to EXTERNAL, which is invalid.")
                    renderTargetDescriptor.addDependency(subpassDependency)
                } else if sourceLayout != destinationLayout, // guaranteed to not be a buffer since buffers have UNDEFINED image layouts above.
                          !afterUsageType.isRenderTarget, !beforeUsageType.isRenderTarget {
                    // We need to insert a pipeline barrier to handle a layout transition.
                    // We can therefore avoid a subpass dependency in most cases.

                    if subpassDependency.srcSubpass == VK_SUBPASS_EXTERNAL {
                        // Insert a pipeline barrier before the start of the Render Command Encoder.
                        beforeCommand = min(beforeCommand, currentEncoder.commandRange.lowerBound)
                    } else if subpassDependency.dstSubpass == VK_SUBPASS_EXTERNAL {
                        // Insert a pipeline barrier before the next command after the render command encoder ends.
                        assert(beforeCommand >= currentEncoder.commandRange.last!)
                    } else {
                        // Insert a subpass self-dependency and a pipeline barrier.
                        fatalError("This should have been handled by the subpassDependency.srcSubpass == subpassDependency.dstSubpass case.")

                        // resourceCommands.append(VulkanFrameResourceCommand(command: .pipelineBarrier(memoryBarrierInfo), index: dependentCommandIndex, order: .before))
                        // subpassDependency.srcSubpass = subpassDependency.dstSubpass
                        // renderTargetDescriptor.addDependency(subpassDependency)
                    }
                } else {
                    // A subpass dependency should be enough to handle this case, unless there are other layers we also need to transition.
                    // TODO: can we do better with fine-grained tracking of layouts and barriers for different layers?
                    renderTargetDescriptor.addDependency(subpassDependency)
                }
            }
            
            if let buffer = resource.buffer {
                var barrier = VkBufferMemoryBarrier()
                barrier.sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER
                barrier.buffer = resourceMap[buffer].buffer.vkBuffer
                barrier.offset = 0
                barrier.size = VK_WHOLE_SIZE // TODO: track at a more fine-grained level.
                if case .buffer(let range) = activeRange {
                    barrier.offset = VkDeviceSize(range.lowerBound)
                    barrier.size = VkDeviceSize(range.count)
                }
                barrier.srcAccessMask = sourceAccessMask
                barrier.dstAccessMask = destinationAccessMask
                barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
                barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
                bufferBarriers.append(barrier)
            } else if let texture = resource.texture {
                var barrier = VkImageMemoryBarrier()
                barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER
                barrier.image = resourceMap[texture].image.vkImage
                barrier.srcAccessMask = sourceAccessMask
                barrier.dstAccessMask = destinationAccessMask
                barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
                barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
                barrier.oldLayout = sourceLayout
                barrier.newLayout = destinationLayout

                barrier.subresourceRange = VkImageSubresourceRange(aspectMask: texture.descriptor.pixelFormat.aspectFlags, baseMipLevel: 0, levelCount: UInt32(texture.descriptor.mipmapLevelCount), baseArrayLayer: 0, layerCount: UInt32(texture.descriptor.arrayLength))
                switch activeRange {
                case .fullResource:
                    if isLayoutTransitionOnlyBarrierForDifferentEncoder {
                        layoutTransitionOnlyBarriers.appendBarrier(barrier)
                    } else {
                        imageBarriers.appendBarrier(barrier)
                    }
                case .texture(let mask):
                    if mask.value == .max {
                        if isLayoutTransitionOnlyBarrierForDifferentEncoder {
                            layoutTransitionOnlyBarriers.appendBarrier(barrier)
                        } else {
                            imageBarriers.appendBarrier(barrier)
                        }
                    } else {
                        var activeMask = SubresourceMask(source: mask, subresourceCount: texture.descriptor.subresourceCount, allocator: AllocatorType(allocator))
                        processImageSubresourceRanges(&activeMask, textureDescriptor: texture.descriptor, allocator: AllocatorType(allocator)) { range in
                            barrier.subresourceRange = range
                            assert(!imageBarriers.contains(where: { $0.image == barrier.image && $0.subresourceRange == range })) // Ensure we don't add duplicate barriers.
                            if isLayoutTransitionOnlyBarrierForDifferentEncoder {
                                layoutTransitionOnlyBarriers.appendBarrier(barrier)
                            } else {
                                imageBarriers.appendBarrier(barrier)
                            }
                        }
                    }
                default:
                    fatalError()
                }
            }
            
            if isLayoutTransitionOnlyBarrierForDifferentEncoder {
                layoutTransitionOnlyBarrierBeforeStages.formUnion(destinationMask)
                layoutTransitionOnlyBarrierLastIndex = min(beforeCommand, layoutTransitionOnlyBarrierLastIndex)
            } else {
                barrierAfterStages.formUnion(sourceMask)
                barrierBeforeStages.formUnion(destinationMask)
                barrierLastIndex = min(beforeCommand, barrierLastIndex)
            }
        }

        for command in commandGenerator.commands {
            if command.index >= barrierLastIndex || command.index >= layoutTransitionOnlyBarrierLastIndex { // For barriers, the barrier associated with command.index needs to happen _after_ any barriers required to happen _by_ barrierLastIndex
                addBarrier(&compactedResourceCommands)
            }
            if command.index >= layoutTransitionOnlyBarrierLastIndex { 
                // We may have only processed the non-layout-transition barriers if the encoder was a draw encoder (in a render pass);
                // we still need to ensure the layout transition barriers happen before the specified command index.
                assert(barrierLastIndex > command.index)
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
            case .useResource:
                fatalError("Vulkan does not track resource residency")
            case .memoryBarrier(let resource, let afterUsage, let afterStages, let beforeCommand, let beforeUsage, let beforeStages, let activeRange):
                processMemoryBarrier(resource: resource, afterCommand: command.index, afterUsageType: afterUsage, afterStages: afterStages, beforeCommand: beforeCommand, beforeUsageType: beforeUsage, beforeStages: beforeStages, activeRange: activeRange)
            }
        }
        
        if barrierLastIndex < .max {
            addBarrier(&compactedResourceCommands)
        }
        
        compactedResourceCommands.sort()
    }
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
