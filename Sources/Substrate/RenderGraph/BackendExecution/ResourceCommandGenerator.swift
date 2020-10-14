//
//  ResourceCommandGenerator.swift
//  
//
//  Created by Thomas Roughton on 6/04/20.
//

import SubstrateUtilities

/// The value to wait for on the event associated with this RenderGraph context.
struct ContextWaitEvent {
    var waitValue : UInt64 = 0
    var afterStages : RenderStages = []
}

struct CompactedResourceCommand<T> : Comparable {
    var command : T
    var index : Int
    var order : PerformOrder
    
    public static func ==(lhs: CompactedResourceCommand<T>, rhs: CompactedResourceCommand<T>) -> Bool {
        return lhs.index == rhs.index && lhs.order == rhs.order
    }
    
    public static func <(lhs: CompactedResourceCommand<T>, rhs: CompactedResourceCommand<T>) -> Bool {
        if lhs.index < rhs.index { return true }
        if lhs.index == rhs.index, lhs.order < rhs.order {
            return true
        }
        return false
    }
}

extension Range where Bound: AdditiveArithmetic {
    func offset(by: Bound) -> Self {
        return (self.lowerBound + by)..<(self.upperBound + by)
    }
}

enum PreFrameCommands {
    
    // These commands mutate the ResourceRegistry and should be executed before render pass execution:
    case materialiseBuffer(Buffer)
    case materialiseTexture(Texture)
    case materialiseTextureView(Texture)
    case materialiseArgumentBuffer(_ArgumentBuffer)
    case materialiseArgumentBufferArray(_ArgumentBufferArray)
    case disposeResource(Resource, afterStages: RenderStages)
    
    case waitForHeapAliasingFences(resource: Resource, waitDependency: FenceDependency)
    
    case waitForCommandBuffer(index: UInt64, queue: Queue)
    case updateCommandBufferWaitIndex(Resource, accessType: ResourceAccessType)
    
    var isMaterialiseNonArgumentBufferResource: Bool {
        switch self {
        case .materialiseBuffer, .materialiseTexture, .materialiseTextureView:
            return true
        default:
            return false
        }
    }
    
    func execute<Backend: SpecificRenderBackend, Dependency: Substrate.Dependency>(commandIndex: Int, commandGenerator: ResourceCommandGenerator<Backend>, context: RenderGraphContextImpl<Backend>, storedTextures: [Texture], encoderDependencies: inout DependencyTable<Dependency?>, waitEventValues: inout QueueCommandIndices, signalEventValue: UInt64) {
        let queue = context.renderGraphQueue
        let queueIndex = Int(queue.index)
        let resourceMap = context.resourceMap
        let resourceRegistry = context.resourceRegistry
        
        switch self {
        case .materialiseBuffer(let buffer):
            // If the resource hasn't already been allocated and is transient, we should force it to be GPU private since the CPU is guaranteed not to use it.
            _ = resourceRegistry.allocateBufferIfNeeded(buffer, forceGPUPrivate: !buffer._usesPersistentRegistry && buffer._deferredSliceActions.isEmpty)
            
            let waitEvent = buffer.flags.contains(.historyBuffer) ? resourceRegistry.historyBufferResourceWaitEvents[Resource(buffer)] : resourceRegistry.bufferWaitEvents[buffer]
            
            waitEventValues[queueIndex] = max(waitEvent!.waitValue, waitEventValues[queueIndex])
            buffer.applyDeferredSliceActions()
            
        case .materialiseTexture(let texture):
            // If the resource hasn't already been allocated and is transient, we should force it to be GPU private since the CPU is guaranteed not to use it.
            _ = resourceRegistry.allocateTextureIfNeeded(texture, forceGPUPrivate: !texture._usesPersistentRegistry, frameStoredTextures: storedTextures)
            if let textureWaitEvent = (texture.flags.contains(.historyBuffer) ? resourceRegistry.historyBufferResourceWaitEvents[Resource(texture)] : resourceRegistry.textureWaitEvents[texture]) {
                waitEventValues[queueIndex] = max(textureWaitEvent.waitValue, waitEventValues[queueIndex])
            } else {
                precondition(texture.flags.contains(.windowHandle))
            }
            
        case .materialiseTextureView(let texture):
            _ = resourceRegistry.allocateTextureView(texture, resourceMap: resourceMap)
            
        case .materialiseArgumentBuffer(let argumentBuffer):
            let argBufferReference : Backend.ArgumentBufferReference
            if argumentBuffer.flags.contains(.persistent) {
                argBufferReference = resourceMap.persistentRegistry.allocateArgumentBufferIfNeeded(argumentBuffer)
            } else {
                argBufferReference = resourceRegistry.allocateArgumentBufferIfNeeded(argumentBuffer)
                waitEventValues[queueIndex] = max(resourceRegistry.argumentBufferWaitEvents?[argumentBuffer]!.waitValue ?? 0, waitEventValues[queueIndex])
            }
            Backend.fillArgumentBuffer(argumentBuffer, storage: argBufferReference, firstUseCommandIndex: commandIndex, resourceMap: resourceMap)
            
            
        case .materialiseArgumentBufferArray(let argumentBuffer):
            let argBufferReference : Backend.ArgumentBufferArrayReference
            if argumentBuffer.flags.contains(.persistent) {
                argBufferReference = resourceMap.persistentRegistry.allocateArgumentBufferArrayIfNeeded(argumentBuffer)
            } else {
                argBufferReference = resourceRegistry.allocateArgumentBufferArrayIfNeeded(argumentBuffer)
                waitEventValues[queueIndex] = max(resourceRegistry.argumentBufferArrayWaitEvents?[argumentBuffer]!.waitValue ?? 0, waitEventValues[queueIndex])
            }
            Backend.fillArgumentBufferArray(argumentBuffer, storage: argBufferReference, firstUseCommandIndex: commandIndex, resourceMap: resourceMap)
    
        case .disposeResource(let resource, let afterStages):
            let disposalWaitEvent = ContextWaitEvent(waitValue: signalEventValue, afterStages: afterStages)
            if let buffer = resource.buffer {
                resourceRegistry.disposeBuffer(buffer, waitEvent: disposalWaitEvent)
            } else if let texture = resource.texture {
                resourceRegistry.disposeTexture(texture, waitEvent: disposalWaitEvent)
            } else if let argumentBuffer = resource.argumentBuffer {
                resourceRegistry.disposeArgumentBuffer(argumentBuffer, waitEvent: disposalWaitEvent)
            } else {
                fatalError()
            }
            
        case .waitForCommandBuffer(let index, let waitQueue):
            waitEventValues[Int(waitQueue.index)] = max(index, waitEventValues[Int(waitQueue.index)])
            
        case .updateCommandBufferWaitIndex(let resource, let accessType):
            resource[waitIndexFor: queue, accessType: accessType] = signalEventValue
            
        case .waitForHeapAliasingFences(let resource, let waitDependency):
            resourceRegistry.withHeapAliasingFencesIfPresent(for: resource.handle, perform: { fenceDependencies in
                for signalDependency in fenceDependencies {
                    let dependency = Dependency(signal: signalDependency, wait: waitDependency)
                    
                    let newDependency = encoderDependencies.dependency(from: dependency.wait.encoderIndex, on: dependency.signal.encoderIndex)?.merged(with: dependency) ?? dependency
                    encoderDependencies.setDependency(from: dependency.wait.encoderIndex, on: dependency.signal.encoderIndex, to: newDependency)
                }
            })
        }
    }
}

struct BarrierScope: OptionSet {
    let rawValue: Int
    
    static let buffers: BarrierScope = BarrierScope(rawValue: 1 << 0)
    static let textures: BarrierScope = BarrierScope(rawValue: 1 << 1)
    static let renderTargets: BarrierScope = BarrierScope(rawValue: 1 << 2)
}

enum FrameResourceCommands {
    // These commands need to be executed during render pass execution and do not modify the ResourceRegistry.
    case useResource(Resource, usage: ResourceUsageType, stages: RenderStages, allowReordering: Bool) // Must happen before the FrameResourceCommand command index.
    case memoryBarrier(Resource, afterUsage: ResourceUsageType, afterStages: RenderStages, beforeCommand: Int, beforeUsage: ResourceUsageType, beforeStages: RenderStages, activeRange: ActiveResourceRange) // beforeCommand is the command that this memory barrier must have been executed before, while the FrameResourceCommand's command index is the index that this must happen after.
}

struct PreFrameResourceCommand : Comparable {
    var command : PreFrameCommands
    var sortIndex : Int
    
    public init(command: PreFrameCommands, index: Int, order: PerformOrder) {
        self.command = command
        
        var sortIndex = index << 2
        if order == .after {
            sortIndex |= 0b10
        }
        if !command.isMaterialiseNonArgumentBufferResource {
            sortIndex |= 0b01  // Materialising argument buffers always needs to happen last, after materialising all resources within it.
        }
        self.sortIndex = sortIndex
    }
    
    public var index: Int {
        return self.sortIndex >> 2
    }
    
    public static func ==(lhs: PreFrameResourceCommand, rhs: PreFrameResourceCommand) -> Bool {
        return lhs.sortIndex == rhs.sortIndex
    }
    
    public static func <(lhs: PreFrameResourceCommand, rhs: PreFrameResourceCommand) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }
}

struct FrameResourceCommand : Comparable {
    var command : FrameResourceCommands
    var index : Int
    
    public static func ==(lhs: FrameResourceCommand, rhs: FrameResourceCommand) -> Bool {
        return lhs.index == rhs.index
    }
    
    public static func <(lhs: FrameResourceCommand, rhs: FrameResourceCommand) -> Bool {
        if lhs.index < rhs.index { return true }
        return false
    }
}

extension ChunkArray.RandomAccessView where Element == ResourceUsage {
    func indexOfPreviousWrite(before index: Int, resource: Resource) -> Int? {
        let usageActiveRange = index >= self.endIndex ? .fullResource : self[index].activeRange
        for i in (0..<index).reversed() {
            if self[i].affectsGPUBarriers, self[i].isWrite, self[i].activeRange.intersects(with: usageActiveRange, resource: resource) {
                return i
            }
        }
        return nil
    }

    func indexOfPreviousRead(before index: Int, resource: Resource) -> Int? {
        let usageActiveRange = index >= self.endIndex ? .fullResource : self[index].activeRange
        for i in (0..<index).reversed() {
            if self[i].affectsGPUBarriers, self[i].isRead, self[i].activeRange.intersects(with: usageActiveRange, resource: resource) {
                return i
            }
        }
        return nil
    }
}

final class ResourceCommandGenerator<Backend: SpecificRenderBackend> {
    typealias Dependency = Backend.InterEncoderDependencyType
    
    private var preFrameCommands = [PreFrameResourceCommand]()
    var commands = [FrameResourceCommand]()
    
    var commandEncoderDependencies = DependencyTable<Dependency?>(capacity: 1, defaultValue: nil)
    
    static var resourceCommandGeneratorTag: TaggedHeap.Tag {
        return UInt64(bitPattern: Int64("ResourceCommandGenerator".hashValue))
    }
    
    func processResourceResidency(resource: Resource, frameCommandInfo: FrameCommandInfo<Backend>) {
        guard Backend.requiresResourceResidencyTracking else { return }
        
        var resourceIsRenderTarget = false
        do {
            // Track resource residency.
            var previousEncoderIndex: Int = -1
            var previousUsageType: ResourceUsageType = .unusedArgumentBuffer
            var previousUsageStages: RenderStages = []
            
            for usage in resource.usages
                where usage.renderPassRecord.pass.passType != .external
                    //                        && usage.inArgumentBuffer
                     {
                        assert(usage.stages != .cpuBeforeRender) // CPU-only usages should have been filtered out by the RenderGraph
                        assert(usage.renderPassRecord.isActive) // Only usages for active render passes should be here.
                        
                        if usage.type.isRenderTarget {
                            resourceIsRenderTarget = true
                            if usage.type != .inputAttachmentRenderTarget || !RenderBackend.requiresEmulatedInputAttachments {
                                continue
                            }
                        }
                        
                        let usageEncoderIndex = frameCommandInfo.encoderIndex(for: usage.renderPassRecord)
                        
                        if usage.type != previousUsageType || usage.stages != previousUsageStages || usageEncoderIndex != previousEncoderIndex {
                            self.commands.append(FrameResourceCommand(command: .useResource(resource, usage: usage.type, stages: usage.stages, allowReordering: !resourceIsRenderTarget && usageEncoderIndex != previousEncoderIndex), // Keep the useResource call as late as possible for render targets, and don't allow reordering within an encoder.
                                index: usage.commandRange.lowerBound))
                        }
                        
                        previousUsageType = usage.type
                        previousEncoderIndex = usageEncoderIndex
                        previousUsageStages = usage.stages
            }
        }
    }
    
    
    func processInputAttachmentUsage(_ usage: ResourceUsage, resource: Resource, activeRange: ActiveResourceRange) {
        guard RenderBackend.requiresEmulatedInputAttachments else { return }
        // To simulate input attachments on desktop platforms, we need to insert a render target barrier between every draw.
        let applicableRange = usage.commandRange
        
        let commands = usage.renderPassRecord.commands!
        let passCommandRange = usage.renderPassRecord.commandRange!
        var previousCommandIndex = -1
        
        let rangeInPass = applicableRange.offset(by: -passCommandRange.lowerBound)
        for i in rangeInPass {
            let command = commands[i]
            if command.isDrawCommand {
                let commandIndex = i + passCommandRange.lowerBound
                if previousCommandIndex >= 0 {
                    self.commands.append(FrameResourceCommand(command: .memoryBarrier(Resource(resource), afterUsage: usage.type, afterStages: usage.stages, beforeCommand: commandIndex, beforeUsage: usage.type, beforeStages: usage.stages, activeRange: activeRange), index: previousCommandIndex))
//                            self.commands.append(FrameResourceCommand(command: .useResource(resource, usage: .read, stages: usage.stages, allowReordering: false), index: commandIndex))
                }
                previousCommandIndex = commandIndex
            }
        }
    }
    
    func generateCommands(passes: [RenderPassRecord], usedResources: Set<Resource>, transientRegistry: Backend.TransientResourceRegistry, backend: Backend, frameCommandInfo: inout FrameCommandInfo<Backend>) {
        if passes.isEmpty {
            return
        }
        
        self.commandEncoderDependencies.resizeAndClear(capacity: frameCommandInfo.commandEncoders.count, clearValue: nil)
        let allocator = AllocatorType.threadLocalTag(ThreadLocalTagAllocator(tag: Self.resourceCommandGeneratorTag))
        defer { TaggedHeap.free(tag: Self.resourceCommandGeneratorTag) }
        
        resourceLoop: for resource in usedResources {
            if resource.usages.isEmpty { continue }
            
            self.processResourceResidency(resource: resource, frameCommandInfo: frameCommandInfo)
            
            let usagesArray = resource.usages.makeRandomAccessView(allocator: allocator)
            
            let firstUsage = usagesArray.first!
            
            if Backend.TransientResourceRegistry.isAliasedHeapResource(resource: resource) {
                let fenceDependency = FenceDependency(encoderIndex: frameCommandInfo.encoderIndex(for: firstUsage.renderPassRecord), index: firstUsage.commandRange.lowerBound, stages: firstUsage.stages)
                self.preFrameCommands.append(PreFrameResourceCommand(command: .waitForHeapAliasingFences(resource: resource, waitDependency: fenceDependency), index: firstUsage.commandRange.lowerBound, order: .before))
            }
            
            var remainingSubresources = ActiveResourceRange.inactive
            var remainingSubresourcesUsageIndex: Int = -1
            
            var activeSubresources = ActiveResourceRange.fullResource
            var usageIndex = usagesArray.startIndex
            var skipUntilAfterInapplicableUsage = false // When processing subresources, we skip until we encounter a usage that is incompatible with our current subresources, since every usage up until that point will have already been processed.
            
            while usageIndex < usagesArray.count {
                defer {
                    usageIndex += 1
                    
                    if usageIndex == usagesArray.count, !remainingSubresources.isEqual(to: .inactive, resource: resource) {
                        // Reset the tracked state to the remainingSubresources
                        activeSubresources = remainingSubresources
                        remainingSubresources = .inactive
                        usageIndex = remainingSubresourcesUsageIndex
                        skipUntilAfterInapplicableUsage = true
                    }
                }
                
                let usage = usagesArray[usageIndex]
                if !usage.affectsGPUBarriers {
                    continue
                }
                
                // Check for subresource tracking
                if resource.type == .texture { // We only track subresources for textures.
                    if usage.activeRange.isEqual(to: .fullResource, resource: resource) {
                        if !remainingSubresources.isEqual(to: .inactive, resource: resource) {
                            // Reset the tracked state to the remainingSubresources
                            activeSubresources = remainingSubresources
                            remainingSubresources = .inactive
                            
                            usageIndex = remainingSubresourcesUsageIndex - 1 // since it will have 1 added to it in the defer statement
                            skipUntilAfterInapplicableUsage = true
                            
                            continue
                        } else {
                            activeSubresources = .fullResource
                        }
                    } else {
                        let activeRangeIntersection = usage.activeRange.intersection(with: activeSubresources, resource: resource, allocator: allocator)
                        if activeRangeIntersection.isEqual(to: .inactive, resource: resource) {
                            skipUntilAfterInapplicableUsage = false
                            continue
                        } else if skipUntilAfterInapplicableUsage {
                            continue
                        } else if !activeRangeIntersection.isEqual(to: activeSubresources, resource: resource) {
                            if remainingSubresources.isEqual(to: .inactive, resource: resource) {
                                remainingSubresourcesUsageIndex = usageIndex
                            }
                            
                            remainingSubresources.formUnion(with: activeSubresources.subtracting(range: activeRangeIntersection, resource: resource, allocator: allocator), resource: resource, allocator: allocator)
                            activeSubresources = activeRangeIntersection
                        }
                    }
                }
                
                if usage.type == .inputAttachmentRenderTarget {
                    processInputAttachmentUsage(usage, resource: resource, activeRange: activeSubresources)
                }
                
                let previousWriteIndex = usagesArray.indexOfPreviousWrite(before: usageIndex, resource: resource)
                
                if usage.isWrite {
                    assert(!resource.flags.contains(.immutableOnceInitialised) || !resource.stateFlags.contains(.initialised), "A resource with the flag .immutableOnceInitialised is being written to in \(usage) when it has already been initialised.")
                    
                    // Process all the reads since the last write.
                    for previousReadIndex in ((previousWriteIndex ?? -1) + 1)..<usageIndex {
                        let previousRead = usagesArray[previousReadIndex]
                        guard previousRead.affectsGPUBarriers, previousRead.isRead, frameCommandInfo.encoderIndex(for: previousRead.renderPassRecord) != frameCommandInfo.encoderIndex(for: usage.renderPassRecord) else { continue }
                        
                        let fromEncoder = frameCommandInfo.encoderIndex(for: usage.renderPassRecord)
                        let onEncoder = frameCommandInfo.encoderIndex(for: previousRead.renderPassRecord)
                        let dependency = Dependency(resource: resource, producingUsage: previousRead, producingEncoder: onEncoder, consumingUsage: usage, consumingEncoder: fromEncoder)
                        
                        commandEncoderDependencies.setDependency(from: fromEncoder,
                                                                 on: onEncoder,
                                                                 to: commandEncoderDependencies.dependency(from: fromEncoder, on: onEncoder)?.merged(with: dependency) ?? dependency)
                    }
                }
                
                if let previousWrite = previousWriteIndex.map({ usagesArray[$0] }) {
                    if usage.isRead,
                        frameCommandInfo.encoderIndex(for: previousWrite.renderPassRecord) == frameCommandInfo.encoderIndex(for: usage.renderPassRecord),
                        !(previousWrite.type.isRenderTarget && usage.type == .readWriteRenderTarget) {
                        
                        assert(!usage.stages.isEmpty || usage.renderPassRecord.pass.passType != .draw)
                        assert(!previousWrite.stages.isEmpty || previousWrite.renderPassRecord.pass.passType != .draw)
                        
                        self.commands.append(FrameResourceCommand(command: .memoryBarrier(Resource(resource), afterUsage: previousWrite.type, afterStages: previousWrite.stages, beforeCommand: usage.commandRange.lowerBound, beforeUsage: usage.type, beforeStages: usage.stages, activeRange: activeSubresources), index: previousWrite.commandRange.last!))
                    }
                    
                    if (usage.isRead || usage.isWrite), frameCommandInfo.encoderIndex(for: previousWrite.renderPassRecord) != frameCommandInfo.encoderIndex(for: usage.renderPassRecord) {
                        let fromEncoder = frameCommandInfo.encoderIndex(for: usage.renderPassRecord)
                        let onEncoder = frameCommandInfo.encoderIndex(for: previousWrite.renderPassRecord)
                        let dependency = Dependency(resource: resource, producingUsage: previousWrite, producingEncoder: onEncoder, consumingUsage: usage, consumingEncoder: fromEncoder)
                        
                        commandEncoderDependencies.setDependency(from: fromEncoder,
                                                                 on: onEncoder,
                                                                 to: commandEncoderDependencies.dependency(from: fromEncoder, on: onEncoder)?.merged(with: dependency) ?? dependency)
                    }
                } else {
                    #if canImport(Vulkan)
                    if Backend.self == VulkanBackend.self, resource.type == .texture, !resource.flags.contains(.windowHandle) {
                        // We may need a pipeline barrier for image layout transitions or queue ownership transfers.
                        // Put the barrier as early as possible unless it's a render target barrier, in which case put it at the time of first usage
                        // so that it can be inserted as a subpass dependency.

                        if let previousRead = usagesArray.indexOfPreviousRead(before: usageIndex, resource: resource).map({ usagesArray[$0] }) {
                            if previousRead.type != usage.type { // We only need to check if the usage types differ, since otherwise the layouts are guaranteed to be the same.
                                let onEncoder = frameCommandInfo.encoderIndex(for: previousRead.renderPassRecord)
                                let fromEncoder = frameCommandInfo.encoderIndex(for: usage.renderPassRecord)
                                if fromEncoder == onEncoder {
                                    self.commands.append(FrameResourceCommand(command:
                                                                            .memoryBarrier(Resource(resource), afterUsage: previousRead.type, afterStages: previousRead.stages, beforeCommand: usage.commandRange.lowerBound, beforeUsage: usage.type, beforeStages: usage.stages, activeRange: activeSubresources),
                                                                     index: previousRead.commandRange.upperBound))
                                } else {
                                    let dependency = Dependency(resource: resource, producingUsage: previousRead, producingEncoder: onEncoder, consumingUsage: usage, consumingEncoder: fromEncoder)
                                    commandEncoderDependencies.setDependency(from: fromEncoder,
                                                                            on: onEncoder,
                                                                            to: commandEncoderDependencies.dependency(from: fromEncoder, on: onEncoder)?.merged(with: dependency) ?? dependency)

                                }
                            } 

                        } else if !usage.type.isRenderTarget { // Render target layout transitions are handled by the render pass.
                            self.commands.append(FrameResourceCommand(command:
                                                                    .memoryBarrier(Resource(resource), afterUsage: .frameStartLayoutTransitionCheck, afterStages: .cpuBeforeRender, beforeCommand: usage.commandRange.lowerBound, beforeUsage: usage.type, beforeStages: usage.stages, activeRange: activeSubresources),
                                                                  index: usage.type.isRenderTarget ? usage.commandRange.lowerBound : 0))
                        }
                    }
                    #endif
                }
            }
            
            let lastUsage = usagesArray.last!
            
            defer {
                if usagesArray.contains(where: { $0.isWrite }), resource.flags.intersection([.historyBuffer, .persistent]) != [] {
                    resource.markAsInitialised()
                }
            }
            
            let historyBufferUseFrame = resource.flags.contains(.historyBuffer) && resource.stateFlags.contains(.initialised)
            if historyBufferUseFrame {
                resource.dispose() // This will dispose it in the RenderGraph persistent allocator, which will in turn call dispose in the resource registry at the end of the frame.
            }
            
            var canBeMemoryless = false
            
            // We dispose at the end of a command encoder since resources can't alias against each other within a command encoder.
            let lastCommandEncoderIndex = frameCommandInfo.encoderIndex(for: lastUsage.renderPassRecord)
            let disposalIndex = frameCommandInfo.commandEncoders[lastCommandEncoderIndex].commandRange.last!
            
            // Insert commands to materialise and dispose of the resource.
            if let argumentBuffer = resource.argumentBuffer {
                // Unlike textures and buffers, we materialise persistent argument buffers at first use rather than immediately.
                if !historyBufferUseFrame {
                    self.preFrameCommands.append(PreFrameResourceCommand(command: .materialiseArgumentBuffer(argumentBuffer), index: firstUsage.commandRange.lowerBound, order: .before))
                }
                
                if !resource.flags.contains(.persistent), !resource.flags.contains(.historyBuffer) || resource.stateFlags.contains(.initialised), !historyBufferUseFrame {
                    self.preFrameCommands.append(PreFrameResourceCommand(command: .disposeResource(resource, afterStages: lastUsage.stages), index: disposalIndex, order: .after))
                }
                
            } else if !resource.flags.contains(.persistent) || resource.flags.contains(.windowHandle) {
                if let buffer = resource.buffer {
                    
                    if !historyBufferUseFrame {
                        self.preFrameCommands.append(PreFrameResourceCommand(command: .materialiseBuffer(buffer), index: firstUsage.commandRange.lowerBound, order: .before))
                    }
                    
                    if !resource.flags.contains(.historyBuffer) || resource.stateFlags.contains(.initialised), !historyBufferUseFrame {
                        self.preFrameCommands.append(PreFrameResourceCommand(command: .disposeResource(resource, afterStages: lastUsage.stages), index: disposalIndex, order: .after))
                    }
                    
                } else if let texture = resource.texture {
                    canBeMemoryless = backend.supportsMemorylessAttachments &&
                        (texture.flags.intersection([.persistent, .historyBuffer]) == [] || (texture.flags.contains(.persistent) && texture.descriptor.usageHint == .renderTarget))
                        && usagesArray.allSatisfy({ $0.type.isRenderTarget })
                        && !frameCommandInfo.storedTextures.contains(texture)
                    
                    if !historyBufferUseFrame {
                        if texture.isTextureView {
                            self.preFrameCommands.append(PreFrameResourceCommand(command: .materialiseTextureView(texture), index: firstUsage.commandRange.lowerBound, order: .before))
                        } else {
                            self.preFrameCommands.append(PreFrameResourceCommand(command: .materialiseTexture(texture), index: firstUsage.commandRange.lowerBound, order: .before))
                        }
                    }
                    
                    if !resource.flags.contains(.historyBuffer) || resource.stateFlags.contains(.initialised), !historyBufferUseFrame {
                        self.preFrameCommands.append(PreFrameResourceCommand(command: .disposeResource(resource, afterStages: lastUsage.stages), index: disposalIndex, order: .after))
                    }
                }
            }
            
            let lastWriteIndex = usagesArray.indexOfPreviousWrite(before: usagesArray.count, resource: resource)
            let lastWrite = lastWriteIndex.map { usagesArray[$0] }
            
            if resource.flags.intersection([.persistent, .historyBuffer]) != [] {
                // Prepare the resource for being used this frame. For Vulkan, this means computing the image layouts.
                if let buffer = resource.buffer {
                    transientRegistry.prepareMultiframeBuffer(buffer)
                } else if let texture = resource.texture {
                    transientRegistry.prepareMultiframeTexture(texture)
                }
                
                for queue in QueueRegistry.allQueues {
                    // TODO: separate out the wait index for the first read from the first write.
                    let waitIndex = resource[waitIndexFor: queue, accessType: lastWriteIndex != nil ? .readWrite : .read]
                    self.preFrameCommands.append(PreFrameResourceCommand(command: .waitForCommandBuffer(index: waitIndex, queue: queue), index: firstUsage.commandRange.first!, order: .before))
                }

                if !resource.stateFlags.contains(.initialised) || !resource.flags.contains(.immutableOnceInitialised) {
                    if lastUsage.isWrite {
                        self.preFrameCommands.append(PreFrameResourceCommand(command: .updateCommandBufferWaitIndex(resource, accessType: .readWrite), index: lastUsage.commandRange.last!, order: .after))
                    } else {
                        if let lastWrite = lastWrite {
                            self.preFrameCommands.append(PreFrameResourceCommand(command: .updateCommandBufferWaitIndex(resource, accessType: .readWrite), index: lastWrite.commandRange.last!, order: .after))
                        }
                        // Process all the reads since the last write.
                        for readIndex in ((lastWriteIndex ?? -1) + 1)..<usagesArray.count {
                            let read = usagesArray[readIndex]
                            guard read.affectsGPUBarriers, read.isRead else { continue }
                            
                            self.preFrameCommands.append(PreFrameResourceCommand(command: .updateCommandBufferWaitIndex(resource, accessType: .write), index: read.commandRange.last!, order: .after))
                        }
                    }
                }
            }
            
            if Backend.TransientResourceRegistry.isAliasedHeapResource(resource: resource), !canBeMemoryless {
                // Reads need to wait for all previous writes to complete.
                // Writes need to wait for all previous reads and writes to complete.
                
                var storeFences : [FenceDependency] = []
                
                // We only need to wait for the write to complete if there have been no reads since the write; otherwise, we wait on the reads
                // which in turn have a transitive dependency on the write.
                if let lastWriteIndex = lastWriteIndex, usagesArray.index(after: lastWriteIndex) == usagesArray.endIndex {
                    let lastWrite = lastWrite!
                    storeFences = [FenceDependency(encoderIndex: frameCommandInfo.encoderIndex(for: lastWrite.renderPassRecord), index: lastWrite.commandRange.last!, stages: lastWrite.stages)]
                }
                
                // Process all the reads since the last write.
                for readIndex in ((lastWriteIndex ?? -1) + 1)..<usagesArray.count {
                    let read = usagesArray[readIndex]
                    guard read.affectsGPUBarriers, read.isRead, read.renderPassRecord.pass.passType != .external else { continue }
                    
                    storeFences.append(FenceDependency(encoderIndex: frameCommandInfo.encoderIndex(for: read.renderPassRecord), index: read.commandRange.last!, stages: read.stages))
                }
                
                transientRegistry.setDisposalFences(on: resource, to: storeFences)
            }
        }
    }
    
    func executePreFrameCommands(context: RenderGraphContextImpl<Backend>, frameCommandInfo: inout FrameCommandInfo<Backend>) {
        self.preFrameCommands.sort()
        
        var commandEncoderIndex = 0
        for command in self.preFrameCommands {
            while command.index >= frameCommandInfo.commandEncoders[commandEncoderIndex].commandRange.upperBound {
                commandEncoderIndex += 1
            }
            let commandBufferIndex = frameCommandInfo.commandEncoders[commandEncoderIndex].commandBufferIndex
            command.command.execute(commandIndex: command.index,
                                    commandGenerator: self,
                                    context: context,
                                    storedTextures: frameCommandInfo.storedTextures,
                                    encoderDependencies: &self.commandEncoderDependencies,
                                    waitEventValues: &frameCommandInfo.commandEncoders[commandEncoderIndex].queueCommandWaitIndices, signalEventValue: frameCommandInfo.signalValue(commandBufferIndex: commandBufferIndex))
        }
        
        self.preFrameCommands.removeAll(keepingCapacity: true)
    }
    
    func reset() {
        self.commands.removeAll(keepingCapacity: true)
    }
}
