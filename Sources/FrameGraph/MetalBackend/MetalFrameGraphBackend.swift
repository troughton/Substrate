//
//  MetalFrameGraph.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 23/12/17.
//

#if canImport(Metal)

import Metal
import FrameGraphUtilities
import CAtomics

enum MetalPreMetalFrameResourceCommands {
    
    // These commands mutate the MetalResourceRegistry and should be executed before render pass execution:
    case materialiseBuffer(Buffer)
    case materialiseTexture(Texture, usage: MetalTextureUsageProperties)
    case materialiseTextureView(Texture, usage: MetalTextureUsageProperties)
    case materialiseArgumentBuffer(_ArgumentBuffer)
    case materialiseArgumentBufferArray(_ArgumentBufferArray)
    case disposeResource(Resource)
    
    case waitForCommandBuffer(index: UInt64, queue: Queue)
    case updateCommandBufferWaitIndex(Resource)
    
    var isMaterialiseArgumentBuffer : Bool {
        switch self {
        case .materialiseArgumentBuffer, .materialiseArgumentBufferArray:
            return true
        default:
            return false
        }
    }
    
    func execute(resourceRegistry: MetalTransientResourceRegistry, resourceMap: MetalFrameResourceMap, stateCaches: MetalStateCaches, queue: Queue, waitEventValues: inout QueueCommandIndices, signalEventValue: UInt64) {
        let queueIndex = Int(queue.index)
        
        switch self {
        case .materialiseBuffer(let buffer):
            resourceRegistry.allocateBufferIfNeeded(buffer)
            waitEventValues[queueIndex] = max(resourceRegistry.bufferWaitEvents[buffer]!.waitValue, waitEventValues[queueIndex])
            buffer.applyDeferredSliceActions()
            
        case .materialiseTexture(let texture, let usage):
            resourceRegistry.allocateTextureIfNeeded(texture, usage: usage)
            if let textureWaitEvent = resourceRegistry.textureWaitEvents[texture] {
                waitEventValues[queueIndex] = max(textureWaitEvent.waitValue, waitEventValues[queueIndex])
            } else {
                assert(texture.flags.contains(.windowHandle))
            }
            
        case .materialiseTextureView(let texture, let usage):
            resourceRegistry.allocateTextureView(texture, properties: usage)
            
        case .materialiseArgumentBuffer(let argumentBuffer):
            let mtlBufferReference : MTLBufferReference
            if argumentBuffer.flags.contains(.persistent) {
                mtlBufferReference = resourceMap.persistentRegistry.allocateArgumentBufferIfNeeded(argumentBuffer)
            } else {
                mtlBufferReference = resourceRegistry.allocateArgumentBufferIfNeeded(argumentBuffer)
                waitEventValues[queueIndex] = max(resourceRegistry.argumentBufferWaitEvents[argumentBuffer]!.waitValue, waitEventValues[queueIndex])
            }
            argumentBuffer.setArguments(storage: mtlBufferReference, resourceMap: resourceMap, stateCaches: stateCaches)
            
            
        case .materialiseArgumentBufferArray(let argumentBuffer):
            let mtlBufferReference : MTLBufferReference
            if argumentBuffer.flags.contains(.persistent) {
                mtlBufferReference = resourceMap.persistentRegistry.allocateArgumentBufferArrayIfNeeded(argumentBuffer)
            } else {
                mtlBufferReference = resourceRegistry.allocateArgumentBufferArrayIfNeeded(argumentBuffer)
                waitEventValues[queueIndex] = max(resourceRegistry.argumentBufferArrayWaitEvents[argumentBuffer]!.waitValue, waitEventValues[queueIndex])
            }
            argumentBuffer.setArguments(storage: mtlBufferReference, resourceMap: resourceMap, stateCaches: stateCaches)
            
        case .disposeResource(let resource):
            let disposalWaitEvent = MetalContextWaitEvent(waitValue: signalEventValue)
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
            
        case .updateCommandBufferWaitIndex(let resource):
            // TODO: split out reads and writes.
            resource[waitIndexFor: queue, accessType: .read] = signalEventValue
            resource[waitIndexFor: queue, accessType: .write] = signalEventValue
        }
    }
}

enum MetalFrameResourceCommands {
    // These commands need to be executed during render pass execution and do not modify the MetalResourceRegistry.
    case useResource(Resource, usage: MTLResourceUsage, stages: MTLRenderStages)
    case memoryBarrier(Resource, afterStages: MTLRenderStages, beforeStages: MTLRenderStages)
    case updateFence(MetalFenceHandle, afterStages: MTLRenderStages)
    case waitForFence(MetalFenceHandle, beforeStages: MTLRenderStages)
    case waitForHeapAliasingFences(resource: ResourceProtocol.Handle, resourceType: ResourceType, beforeStages: MTLRenderStages)
}

struct MetalPreMetalFrameResourceCommand : Comparable {
    var command : MetalPreMetalFrameResourceCommands
    var passIndex : Int
    var index : Int
    var order : PerformOrder
    
    public static func ==(lhs: MetalPreMetalFrameResourceCommand, rhs: MetalPreMetalFrameResourceCommand) -> Bool {
        return lhs.index == rhs.index && lhs.order == rhs.order && lhs.command.isMaterialiseArgumentBuffer == rhs.command.isMaterialiseArgumentBuffer
    }
    
    public static func <(lhs: MetalPreMetalFrameResourceCommand, rhs: MetalPreMetalFrameResourceCommand) -> Bool {
        if lhs.index < rhs.index { return true }
        if lhs.index == rhs.index, lhs.order < rhs.order {
            return true
        }
        // Materialising argument buffers always needs to happen last, after materialising all resources within it.
        if lhs.index == rhs.index, lhs.order == rhs.order, !lhs.command.isMaterialiseArgumentBuffer && rhs.command.isMaterialiseArgumentBuffer {
            return true
        }
        return false
    }
}

struct MetalFrameResourceCommand : Comparable {
    var command : MetalFrameResourceCommands
    var index : Int
    var order : PerformOrder
    
    public static func ==(lhs: MetalFrameResourceCommand, rhs: MetalFrameResourceCommand) -> Bool {
        return lhs.index == rhs.index && lhs.order == rhs.order
    }
    
    public static func <(lhs: MetalFrameResourceCommand, rhs: MetalFrameResourceCommand) -> Bool {
        if lhs.index < rhs.index { return true }
        if lhs.index == rhs.index, lhs.order < rhs.order {
            return true
        }
        return false
    }
}

struct MetalTextureUsageProperties {
    var usage : MTLTextureUsage
    #if os(iOS)
    var canBeMemoryless : Bool
    #endif
    
    init(usage: MTLTextureUsage, canBeMemoryless: Bool = false) {
        self.usage = usage
        #if os(iOS)
        self.canBeMemoryless = canBeMemoryless
        #endif
    }
    
    init(_ usage: TextureUsage) {
        self.init(usage: MTLTextureUsage(usage), canBeMemoryless: false)
    }
}

final class MetalFrameGraphContext : _FrameGraphContext {
    public var accessSemaphore: Semaphore
    
    let backend : MetalBackend
    let resourceRegistry : MetalTransientResourceRegistry
    
    var queueCommandBufferIndex : UInt64 = 0
    let syncEvent : MTLEvent
    
    let commandQueue : MTLCommandQueue
    let captureScope : MTLCaptureScope
    
    public let transientRegistryIndex: Int
    var frameGraphQueue : Queue
    
    var currentRenderTargetDescriptor : RenderTargetDescriptor? = nil
    
    public init(backend: MetalBackend, inflightFrameCount: Int, transientRegistryIndex: Int) {
        self.backend = backend
        self.commandQueue = backend.device.makeCommandQueue()!
        self.frameGraphQueue = Queue()
        self.transientRegistryIndex = transientRegistryIndex
        self.resourceRegistry = MetalTransientResourceRegistry(device: backend.device, inflightFrameCount: inflightFrameCount, transientRegistryIndex: transientRegistryIndex)
        self.accessSemaphore = Semaphore(value: Int32(inflightFrameCount))
        
        self.captureScope = MTLCaptureManager.shared().makeCaptureScope(device: backend.device)
        self.captureScope.label = "FrameGraph Execution"
        self.syncEvent = backend.device.makeEvent()!
        
        backend.queueSyncEvents[Int(self.frameGraphQueue.index)] = self.syncEvent
    }
    
    deinit {
        backend.queueSyncEvents[Int(self.frameGraphQueue.index)] = nil
        self.frameGraphQueue.dispose()
    }
    
    public func beginFrameResourceAccess() {
        self.backend.setActiveContext(self)
    }
    
    var resourceMap : MetalFrameResourceMap {
        return MetalFrameResourceMap(persistentRegistry: self.backend.resourceRegistry, transientRegistry: self.resourceRegistry)
    }
    
    // Generates a render target descriptor, if applicable, for each pass.
    // MetalRenderTargetDescriptor is a reference type, so we can check if two passes share a render target
    // (and therefore MTLRenderCommandEncoder)
    // storedTextures contain all textures that are stored to (i.e. textures that aren't eligible to be memoryless on iOS).
    func generateRenderTargetDescriptors(passes: [RenderPassRecord], resourceUsages: ResourceUsages, storedTextures: inout [Texture]) -> [MetalRenderTargetDescriptor?] {
        var descriptors = [MetalRenderTargetDescriptor?](repeating: nil, count: passes.count)
        
        var currentDescriptor : MetalRenderTargetDescriptor? = nil
        for (i, passRecord) in passes.enumerated() {
            if let renderPass = passRecord.pass as? DrawRenderPass {
                if let descriptor = currentDescriptor {
                    currentDescriptor = descriptor.descriptorMergedWithPass(renderPass, resourceUsages: resourceUsages, storedTextures: &storedTextures)
                } else {
                    currentDescriptor = MetalRenderTargetDescriptor(renderPass: renderPass)
                }
            } else {
                currentDescriptor?.finalise(resourceUsages: resourceUsages, storedTextures: &storedTextures)
                currentDescriptor = nil
            }
            
            descriptors[i] = currentDescriptor
        }
        
        currentDescriptor?.finalise(resourceUsages: resourceUsages, storedTextures: &storedTextures)
        
        return descriptors
    }
    
    // For fence tracking - support at most one dependency between each set of two render passes. Make the fence update as early as possible, and make the fence wait as late as possible.
    struct Dependency {
        /// dependentUsage is the usage within the dependent pass.
        var dependentIndex : Int
        var dependentStages : RenderStages
        /// passUsage is the usage within the current pass (the pass that's depended upon).
        var passIndex : Int
        var passStages : RenderStages
        
        init(dependentUsage: ResourceUsage, passUsage: ResourceUsage) {
            self.dependentIndex = dependentUsage.commandRange.lowerBound
            self.dependentStages = dependentUsage.stages
            
            self.passIndex = passUsage.commandRange.last! // - 1 because the range is open.
            self.passStages = passUsage.stages
        }
        
        public func merged(with otherDependency: Dependency) -> Dependency {
            var result = self
            result.dependentIndex = min(result.dependentIndex, otherDependency.dependentIndex)
            result.dependentStages.formUnion(otherDependency.dependentStages)
            
            result.passIndex = max(result.passIndex, otherDependency.passIndex)
            result.passStages.formUnion(otherDependency.passStages)
            return result
        }
    }
    
    var resourceRegistryPreFrameCommands = [MetalPreMetalFrameResourceCommand]()
    
    var resourceCommands = [MetalFrameResourceCommand]()
    var renderTargetTextureProperties = [Texture : MetalTextureUsageProperties]()
    var commandEncoderDependencies = DependencyTable<Dependency?>(capacity: 1, defaultValue: nil)
    
    /// - param storedTextures: textures that are stored as part of a render target (and therefore can't be memoryless on iOS)
    func generateResourceCommands(passes: [RenderPassRecord], resourceUsages: ResourceUsages, renderTargetDescriptors: [MetalRenderTargetDescriptor?], storedTextures: [Texture], lastCommandBufferIndex: UInt64) {
        if passes.isEmpty {
            return
        }
        
        let (passCommandEncoderIndices, _, commandEncoderCount) = MetalEncoderManager.generateCommandEncoderIndices(passes: passes, renderTargetDescriptors: renderTargetDescriptors)
        
        self.commandEncoderDependencies.resizeAndClear(capacity: commandEncoderCount, clearValue: nil)
        
        resourceLoop: for resource in resourceUsages.allResources {
            let resourceType = resource.type
            
            let usages = resource.usages
            
            if usages.isEmpty { continue }
            
            do {
                // Track resource residency.
                
                var commandIndex = Int.max
                var previousPass : RenderPassRecord? = nil
                var resourceUsage : MTLResourceUsage = []
                var resourceStages : MTLRenderStages = []
                
                for usage in usages
                    where usage.renderPassRecord.isActive &&
                        usage.renderPassRecord.pass.passType != .external &&
                        /* usage.inArgumentBuffer && */
                        usage.stages != .cpuBeforeRender &&
                        !usage.type.isRenderTarget {
                            
                            defer { previousPass = usage.renderPassRecord }
                            
                            if let previousPassUnwrapped = previousPass, passCommandEncoderIndices[previousPassUnwrapped.passIndex] != passCommandEncoderIndices[usage.renderPassRecord.passIndex] {
                                self.resourceCommands.append(MetalFrameResourceCommand(command: .useResource(resource, usage: resourceUsage, stages: resourceStages), index: commandIndex, order: .before))
                                previousPass = nil
                            }
                            
                            if previousPass == nil {
                                resourceUsage = []
                                resourceStages = []
                                commandIndex = usage.commandRange.lowerBound
                            } else {
                                commandIndex = min(commandIndex, usage.commandRange.lowerBound)
                            }
                            
                            if resourceType == .texture, usage.type == .read {
                                resourceUsage.formUnion(.sample)
                            }
                            if usage.isRead {
                                resourceUsage.formUnion(.read)
                            }
                            if usage.isWrite {
                                resourceUsage.formUnion(.write)
                            }
                            
                            resourceStages.formUnion(MTLRenderStages(usage.stages))
                }
                
                if previousPass != nil {
                    self.resourceCommands.append(MetalFrameResourceCommand(command: .useResource(resource, usage: resourceUsage, stages: resourceStages), index: commandIndex, order: .before))
                }
            }
            
            var usageIterator = usages.makeIterator()
            
            // Find the first used render pass.
            var previousUsage : ResourceUsage
            repeat {
                guard let usage = usageIterator.next() else {
                    continue resourceLoop // no active usages for this resource.
                }
                previousUsage = usage
            } while !previousUsage.renderPassRecord.isActive || previousUsage.stages == .cpuBeforeRender
            
            
            var firstUsage = previousUsage
            
            if !firstUsage.isWrite {
                
                // Scan forward from the 'first usage' until we find the _actual_ first usage - that is, the usage whose command range comes first.
                // The 'first usage' might only not actually be the first if the first usages are all reads.
                
                var firstUsageIterator = usageIterator // Since the usageIterator is a struct, this will copy the iterator.
                while let nextUsage = firstUsageIterator.next(), !nextUsage.isWrite {
                    if nextUsage.renderPassRecord.isActive, nextUsage.type != .unusedRenderTarget, nextUsage.commandRange.lowerBound < firstUsage.commandRange.lowerBound {
                        firstUsage = nextUsage
                    }
                }
            }
            
            var readsSinceLastWrite = (firstUsage.isRead && !firstUsage.isWrite) ? [firstUsage] : []
            var previousWrite = firstUsage.isWrite ? firstUsage : nil
            
            if resourceRegistry.isAliasedHeapResource(resource: resource) {
                assert(firstUsage.isWrite || firstUsage.type == .unusedRenderTarget, "Heap resource \(resource) is read from without ever being written to.")
                self.resourceCommands.append(MetalFrameResourceCommand(command: .waitForHeapAliasingFences(resource: resource.handle, resourceType: resourceType, beforeStages: MTLRenderStages(firstUsage.stages.first)), index: firstUsage.commandRange.lowerBound, order: .before))
                
            }
            
            while let usage = usageIterator.next()  {
                if !usage.affectsGPUBarriers {
                    continue
                }
                
                if usage.isWrite {
                    assert(!resource.flags.contains(.immutableOnceInitialised) || !resource.stateFlags.contains(.initialised), "A resource with the flag .immutableOnceInitialised is being written to in \(usage) when it has already been initialised.")
                    
                    for previousRead in readsSinceLastWrite where passCommandEncoderIndices[previousRead.renderPassRecord.passIndex] != passCommandEncoderIndices[usage.renderPassRecord.passIndex] {
                        let dependency = Dependency(dependentUsage: usage, passUsage: previousRead)
                        
                        let fromEncoder = passCommandEncoderIndices[usage.renderPassRecord.passIndex]
                        let onEncoder = passCommandEncoderIndices[previousRead.renderPassRecord.passIndex]
                        commandEncoderDependencies.setDependency(from: fromEncoder,
                                                                 on: onEncoder,
                                                                 to: commandEncoderDependencies.dependency(from: fromEncoder, on: onEncoder)?.merged(with: dependency) ?? dependency)
                    }
                }
                
                // Only insert a barrier for the first usage following a write.
                if usage.isRead, previousUsage.isWrite,
                    passCommandEncoderIndices[previousUsage.renderPassRecord.passIndex] == passCommandEncoderIndices[usage.renderPassRecord.passIndex]  {
                    if !(previousUsage.type.isRenderTarget && (usage.type == .writeOnlyRenderTarget || usage.type == .readWriteRenderTarget)) {
                        assert(!usage.stages.isEmpty || usage.renderPassRecord.pass.passType != .draw)
                        assert(!previousUsage.stages.isEmpty || previousUsage.renderPassRecord.pass.passType != .draw)
                        self.resourceCommands.append(MetalFrameResourceCommand(command: .memoryBarrier(Resource(resource), afterStages: MTLRenderStages(previousUsage.stages.last), beforeStages: MTLRenderStages(usage.stages.first)), index: usage.commandRange.lowerBound, order: .before))
                            
                    }
                }
                
                if (usage.isRead || usage.isWrite), let previousWrite = previousWrite, passCommandEncoderIndices[previousWrite.renderPassRecord.passIndex] != passCommandEncoderIndices[usage.renderPassRecord.passIndex] {
                    let dependency = Dependency(dependentUsage: usage, passUsage: previousWrite)
                    
                    let fromEncoder = passCommandEncoderIndices[usage.renderPassRecord.passIndex]
                    let onEncoder = passCommandEncoderIndices[previousWrite.renderPassRecord.passIndex]
                    commandEncoderDependencies.setDependency(from: fromEncoder,
                                                             on: onEncoder,
                                                             to: commandEncoderDependencies.dependency(from: fromEncoder, on: onEncoder)?.merged(with: dependency) ?? dependency)
                }
                
                if usage.isWrite {
                    readsSinceLastWrite.removeAll(keepingCapacity: true)
                    previousWrite = usage
                }
                if usage.isRead, !usage.isWrite {
                    readsSinceLastWrite.append(usage)
                }
                
                if usage.commandRange.endIndex > previousUsage.commandRange.endIndex { // FIXME: this is only necessary because resource commands are executed sequentially; this will only be false if both usage and previousUsage are reads, and so it doesn't matter which order they happen in.
                    // A better solution would be to effectively compile all resource commands ahead of time - doing so will also enable multithreading and out-of-order execution of render passes.
                    previousUsage = usage
                }
            }
            
            let lastUsage = previousUsage
            
            defer {
                if previousWrite != nil, resource.flags.intersection([.historyBuffer, .persistent]) != [] {
                    resource.markAsInitialised()
                }
            }
            
            let historyBufferUseFrame = resource.flags.contains(.historyBuffer) && resource.stateFlags.contains(.initialised)
            
            #if os(iOS)
            var canBeMemoryless = false
            #else
            let canBeMemoryless = false
            #endif
            
            // Insert commands to materialise and dispose of the resource.
            if let argumentBuffer = resource.argumentBuffer {
                // Unlike textures and buffers, we materialise persistent argument buffers at first use rather than immediately.
                if !historyBufferUseFrame {
                    self.resourceRegistryPreFrameCommands.append(MetalPreMetalFrameResourceCommand(command: .materialiseArgumentBuffer(argumentBuffer), passIndex: firstUsage.renderPassRecord.passIndex, index: firstUsage.commandRange.lowerBound, order: .before))
                }
                
                if !resource.flags.contains(.persistent), !resource.flags.contains(.historyBuffer) || resource.stateFlags.contains(.initialised) {
                    if historyBufferUseFrame {
                        self.resourceRegistry.registerInitialisedHistoryBufferForDisposal(resource: resource)
                    } else {
                        self.resourceRegistryPreFrameCommands.append(MetalPreMetalFrameResourceCommand(command: .disposeResource(resource), passIndex: lastUsage.renderPassRecord.passIndex, index: lastUsage.commandRange.last!, order: .after))
                    }
                } else if resource.flags.contains(.persistent), (!resource.stateFlags.contains(.initialised) || !resource.flags.contains(.immutableOnceInitialised)) {
                    for queue in QueueRegistry.allQueues {
                        // TODO: separate out the wait index for the first read from the first write.
                        let waitIndex = resource[waitIndexFor: queue, accessType: previousWrite != nil ? .readWrite : .read]
                        self.resourceRegistryPreFrameCommands.append(MetalPreMetalFrameResourceCommand(command: .waitForCommandBuffer(index: waitIndex, queue: queue), passIndex: firstUsage.renderPassRecord.passIndex, index: firstUsage.commandRange.last!, order: .before))
                    }
                    self.resourceRegistryPreFrameCommands.append(MetalPreMetalFrameResourceCommand(command: .updateCommandBufferWaitIndex(resource), passIndex: lastUsage.renderPassRecord.passIndex, index: lastUsage.commandRange.last!, order: .after))
                }
                
            } else if !resource.flags.contains(.persistent) || resource.flags.contains(.windowHandle) {
                if let buffer = resource.buffer {
                    if !historyBufferUseFrame {
                        self.resourceRegistryPreFrameCommands.append(MetalPreMetalFrameResourceCommand(command: .materialiseBuffer(buffer), passIndex: firstUsage.renderPassRecord.passIndex, index: firstUsage.commandRange.lowerBound, order: .before))
                    }
                    
                    if !resource.flags.contains(.historyBuffer) || resource.stateFlags.contains(.initialised) {
                        if historyBufferUseFrame {
                            self.resourceRegistry.registerInitialisedHistoryBufferForDisposal(resource: resource)
                        } else {
                            self.resourceRegistryPreFrameCommands.append(MetalPreMetalFrameResourceCommand(command: .disposeResource(resource), passIndex: lastUsage.renderPassRecord.passIndex, index: lastUsage.commandRange.last!, order: .after))
                        }
                    }
                    
                } else if let texture = resource.texture {
                    var textureUsage : MTLTextureUsage = []
                    
                    for usage in usages {
                        switch usage.type {
                        case .read:
                            textureUsage.formUnion(.shaderRead)
                        case .write:
                            textureUsage.formUnion(.shaderWrite)
                        case .readWrite:
                            textureUsage.formUnion([.shaderRead, .shaderWrite])
                        case .readWriteRenderTarget, .writeOnlyRenderTarget, .inputAttachmentRenderTarget, .unusedRenderTarget:
                            textureUsage.formUnion(.renderTarget)
                        default:
                            break
                        }
                    }
                    
                    if texture.descriptor.usageHint.contains(.pixelFormatView) {
                        textureUsage.formUnion(.pixelFormatView)
                    }
                    
                    #if os(iOS)
                    canBeMemoryless = (texture.flags.intersection([.persistent, .historyBuffer]) == [] || (texture.flags.contains(.persistent) && texture.descriptor.usageHint == .renderTarget))
                        && textureUsage == .renderTarget
                        && !storedTextures.contains(texture)
                    let properties = MetalTextureUsageProperties(usage: textureUsage, canBeMemoryless: canBeMemoryless)
                    #else
                    let properties = MetalTextureUsageProperties(usage: textureUsage)
                    #endif
                    
                    assert(properties.usage != .unknown)
                    
                    if textureUsage.contains(.renderTarget) {
                        self.renderTargetTextureProperties[texture] = properties
                    }
                    
                    if !historyBufferUseFrame {
                        if texture.isTextureView {
                            self.resourceRegistryPreFrameCommands.append(MetalPreMetalFrameResourceCommand(command: .materialiseTextureView(texture, usage: properties), passIndex: firstUsage.renderPassRecord.passIndex, index: firstUsage.commandRange.lowerBound, order: .before))
                        } else {
                            self.resourceRegistryPreFrameCommands.append(MetalPreMetalFrameResourceCommand(command: .materialiseTexture(texture, usage: properties), passIndex: firstUsage.renderPassRecord.passIndex, index: firstUsage.commandRange.lowerBound, order: .before))
                        }
                    }
                    
                    if !resource.flags.contains(.historyBuffer) || resource.stateFlags.contains(.initialised) {
                        if historyBufferUseFrame {
                            self.resourceRegistry.registerInitialisedHistoryBufferForDisposal(resource: Resource(texture))
                        } else {
                            self.resourceRegistryPreFrameCommands.append(MetalPreMetalFrameResourceCommand(command: .disposeResource(resource), passIndex: lastUsage.renderPassRecord.passIndex, index: lastUsage.commandRange.last!, order: .after))
                        }
                        
                    }
                }
            } else if resource.flags.contains(.persistent), (!resource.stateFlags.contains(.initialised) || !resource.flags.contains(.immutableOnceInitialised)) {
                for queue in QueueRegistry.allQueues {
                    // TODO: separate out the wait index for the first read from the first write.
                    let waitIndex = resource[waitIndexFor: queue, accessType: previousWrite != nil ? .readWrite : .read]
                    self.resourceRegistryPreFrameCommands.append(MetalPreMetalFrameResourceCommand(command: .waitForCommandBuffer(index: waitIndex, queue: queue), passIndex: firstUsage.renderPassRecord.passIndex, index: firstUsage.commandRange.last!, order: .before))
                }
                self.resourceRegistryPreFrameCommands.append(MetalPreMetalFrameResourceCommand(command: .updateCommandBufferWaitIndex(resource), passIndex: lastUsage.renderPassRecord.passIndex, index: lastUsage.commandRange.last!, order: .after))
            }
            
            if resourceRegistry.isAliasedHeapResource(resource: resource), !canBeMemoryless {
                // Reads need to wait for all previous writes to complete.
                // Writes need to wait for all previous reads and writes to complete.
                
                var storeFences : [MetalFenceHandle] = []
                
                // We only need to wait for the write to complete if there have been no reads since the write; otherwise, we wait on the reads
                // which in turn have a transitive dependency on the write.
                if readsSinceLastWrite.isEmpty, let previousWrite = previousWrite, previousWrite.renderPassRecord.pass.passType != .external {
                    let label = "(Aliasing fence for \(resource), type \(resource.type) with last write: \(previousWrite.type))"
                    let updateFence = MetalFenceHandle(label: label, queue: self.frameGraphQueue, commandBufferIndex: lastCommandBufferIndex)
                    storeFences = [updateFence]
                    
                    self.resourceCommands.append(MetalFrameResourceCommand(command: .updateFence(updateFence, afterStages: MTLRenderStages(previousWrite.stages.last)), index: previousWrite.commandRange.last!, order: .after))
                }
                
                for read in readsSinceLastWrite where read.renderPassRecord.pass.passType != .external {
                    let label = "(Aliasing fence for \(resource), type \(resource.type) with last read: \(read.type))"
                    let updateFence = MetalFenceHandle(label: label, queue: self.frameGraphQueue, commandBufferIndex: lastCommandBufferIndex)
                    storeFences.append(updateFence)
                    
                    self.resourceCommands.append(MetalFrameResourceCommand(command: .updateFence(updateFence, afterStages: MTLRenderStages(read.stages.last)), index: read.commandRange.last!, order: .after))
                }
                
                // setDisposalFences retains its fences.
                self.resourceRegistry.setDisposalFences(on: resource, to: storeFences)
            }
            
        }
        
        // Process the dependencies, joining duplicates.
        // TODO: Remove transitive dependencies.
        for sourceIndex in 0..<commandEncoderCount { // passIndex always points to the producing pass.
            for dependentIndex in min(sourceIndex + 1, commandEncoderCount)..<commandEncoderCount {
                if let dependency = self.commandEncoderDependencies.dependency(from: dependentIndex, on: sourceIndex) {
                    let label = "(Encoder \(sourceIndex) to Encoder \(dependentIndex))"
                    let fence = MetalFenceHandle(label: label, queue: self.frameGraphQueue, commandBufferIndex: lastCommandBufferIndex)
                    self.resourceCommands.append(MetalFrameResourceCommand(command: .updateFence(fence, afterStages: MTLRenderStages(dependency.passStages.last)), index: dependency.passIndex, order: .after))
                    
                    self.resourceCommands.append(MetalFrameResourceCommand(command: .waitForFence(fence, beforeStages: MTLRenderStages(dependency.dependentStages.first)), index: dependency.dependentIndex, order: .before))
                }
            }
        }
        
        self.resourceRegistryPreFrameCommands.sort()
        self.resourceCommands.sort()
    }
    
    static func passCommandBufferIndices(passes: [RenderPassRecord]) -> [Int] {
        var indices = (0..<passes.count).map { _ in 0 }
        
        var currentIndex = 0
        
        var previousPassIsExternal = false
        var isWindowTextureEncoder = false
        
        for (i, passRecord) in passes.enumerated() {
            if previousPassIsExternal != (passRecord.pass.passType == .external) {
                // Wait for the previous command buffer to complete before executing.
                if i > 0 { currentIndex += 1 }
                previousPassIsExternal = passRecord.pass.passType == .external
            } else
            if passRecord.usesWindowTexture != isWindowTextureEncoder {
                if i > 0 { currentIndex += 1 }
                isWindowTextureEncoder = passRecord.usesWindowTexture
            }
            indices[i] = currentIndex
        }
        
        return indices
    }
    
    public func executeFrameGraph(passes: [RenderPassRecord], dependencyTable: DependencyTable<SwiftFrameGraph.DependencyType>, resourceUsages: ResourceUsages, completion: @escaping () -> Void) {
        defer { self.resourceRegistry.cycleFrames() }
        
        self.resourceRegistry.prepareFrame()
        
        let firstEncoderSignalValue = self.queueCommandBufferIndex + 1 // The first encoder's MTLEvent signal value is one higher than the previous value used.
        let passCommandBufferIndices = MetalFrameGraphContext.passCommandBufferIndices(passes: passes)
        
        var storedTextures = [Texture]()
        let renderTargetDescriptors = self.generateRenderTargetDescriptors(passes: passes, resourceUsages: resourceUsages, storedTextures: &storedTextures)
        self.generateResourceCommands(passes: passes, resourceUsages: resourceUsages, renderTargetDescriptors: renderTargetDescriptors, storedTextures: storedTextures, lastCommandBufferIndex: firstEncoderSignalValue + UInt64(passCommandBufferIndices.count))
        
        let (passCommandEncoders, commandEncoderNames, commandEncoderCount) = MetalEncoderManager.generateCommandEncoderIndices(passes: passes, renderTargetDescriptors: renderTargetDescriptors)
        
        
        var commandEncoderWaitEventValues = (0..<commandEncoderCount).map { _ in QueueCommandIndices(repeating: 0) }
        
        for command in self.resourceRegistryPreFrameCommands {
            let encoderIndex = passCommandEncoders[command.passIndex]
            let commandBufferIndex = passCommandBufferIndices[command.passIndex]
            command.command.execute(resourceRegistry: self.resourceRegistry, resourceMap: self.resourceMap, stateCaches: backend.stateCaches, queue: self.frameGraphQueue,
                                    waitEventValues: &commandEncoderWaitEventValues[encoderIndex], signalEventValue: UInt64(commandBufferIndex) + firstEncoderSignalValue)
        }
        
        self.resourceRegistryPreFrameCommands.removeAll(keepingCapacity: true)
        
        func executePass(_ passRecord: RenderPassRecord, i: Int, encoderManager: MetalEncoderManager) {
            switch passRecord.pass.passType {
            case .blit:
                let commandEncoder = encoderManager.blitCommandEncoder()
                if commandEncoder.encoder.label == nil {
                    commandEncoder.encoder.label = commandEncoderNames[passCommandEncoders[i]]
                }
                
                commandEncoder.executePass(passRecord, resourceCommands: resourceCommands, resourceMap: self.resourceMap, stateCaches: backend.stateCaches)
                
            case .draw:
                guard let commandEncoder = encoderManager.renderCommandEncoder(descriptor: renderTargetDescriptors[i]!, textureUsages: self.renderTargetTextureProperties, resourceCommands: resourceCommands, resourceMap: self.resourceMap, stateCaches: backend.stateCaches) else {
                    if _isDebugAssertConfiguration() {
                        print("Warning: skipping pass \(passRecord.pass.name) since the drawable for the render target could not be retrieved.")
                    }
                    
                    return
                }
                if commandEncoder.label == nil {
                    commandEncoder.label = commandEncoderNames[passCommandEncoders[i]]
                }
                
                commandEncoder.executePass(passRecord, resourceCommands: resourceCommands, renderTarget: renderTargetDescriptors[i]!.descriptor, passRenderTarget: (passRecord.pass as! DrawRenderPass).renderTargetDescriptor, resourceMap: self.resourceMap, stateCaches: backend.stateCaches)
            case .compute:
                let commandEncoder = encoderManager.computeCommandEncoder()
                if commandEncoder.encoder.label == nil {
                    commandEncoder.encoder.label = commandEncoderNames[passCommandEncoders[i]]
                }
                
                commandEncoder.executePass(passRecord, resourceCommands: resourceCommands, resourceMap: self.resourceMap, stateCaches: backend.stateCaches)
                
            case .external:
                let commandEncoder = encoderManager.externalCommandEncoder()
                commandEncoder.executePass(passRecord, resourceCommands: resourceCommands, resourceMap: self.resourceMap, stateCaches: backend.stateCaches)
                
            case .cpu:
                break
            }
        }
        
        self.captureScope.begin()
        defer { self.captureScope.end() }
        
        // Use separate command buffers for onscreen and offscreen work (Delivering Optimised Metal Apps and Games, WWDC 2019)
        
        let lastCommandBufferIndex = passCommandBufferIndices.last ?? 0
        
        var commandBuffer : MTLCommandBuffer? = nil
        var encoderManager : MetalEncoderManager? = nil
        
        var committedCommandBufferCount = 0
        var commandEncoderIndex = -1

        func processCommandBuffer() {
            encoderManager?.endEncoding()
            
            if let commandBuffer = commandBuffer {
                // Only contains drawables applicable to the render passes in the command buffer...
                for drawable in self.resourceRegistry.frameDrawables {
                    #if os(iOS)
                    commandBuffer.present(drawable, afterMinimumDuration: 1.0 / 60.0)
                    #else
                    commandBuffer.present(drawable)
                    #endif
                }
                // because we reset the list after each command buffer submission.
                self.resourceRegistry.clearDrawables()
                
                // Make sure that the sync event value is what we expect, so we don't update it past
                // the signal for another buffer before that buffer has completed.
                // We only need to do this if we haven't already waited in this command buffer for it.
                // if commandEncoderWaitEventValues[commandEncoderIndex] != self.queueCommandBufferIndex {
                //     commandBuffer.encodeWaitForEvent(self.syncEvent, value: self.queueCommandBufferIndex)
                // }
                // Then, signal our own completion.
                self.queueCommandBufferIndex += 1
                commandBuffer.encodeSignalEvent(self.syncEvent, value: self.queueCommandBufferIndex)

                let cbIndex = committedCommandBufferCount
                let queueCBIndex = self.queueCommandBufferIndex

                commandBuffer.addCompletedHandler { (commandBuffer) in
                    if let error = commandBuffer.error {
                        print("Error executing command buffer \(queueCBIndex): \(error)")
                    }
                    self.frameGraphQueue.lastCompletedCommand = queueCBIndex
                    if cbIndex == lastCommandBufferIndex { // Only call completion for the last command buffer.
                        completion()
                        self.accessSemaphore.signal()
                    }
                }
                
                self.frameGraphQueue.lastSubmittedCommand = queueCBIndex
                commandBuffer.commit()
                committedCommandBufferCount += 1
                
            }
            commandBuffer = nil
            encoderManager = nil
        }
        
        for (i, passRecord) in passes.enumerated() {
            let commandBufferIndex = passCommandBufferIndices[i]
            if commandBufferIndex != committedCommandBufferCount {
                processCommandBuffer()
            }
            
            if commandBuffer == nil {
                commandBuffer = self.commandQueue.makeCommandBuffer()!
                encoderManager = MetalEncoderManager(commandBuffer: commandBuffer!, resourceMap: self.resourceMap)
            }
            
            if commandEncoderIndex != passCommandBufferIndices[i] {
                commandEncoderIndex = passCommandBufferIndices[i]
                
                let waitEventValues = commandEncoderWaitEventValues[commandEncoderIndex]
                for queue in QueueRegistry.allQueues {
                    if waitEventValues[Int(queue.index)] > queue.lastCompletedCommand {
                        if let event = backend.queueSyncEvents[Int(queue.index)] {
                            commandBuffer!.encodeWaitForEvent(event, value: waitEventValues[Int(queue.index)])
                        } else {
                            // It's not a Metal queue, so the best we can do is sleep and wait until the queue is completd.
                            while queue.lastCompletedCommand < waitEventValues[Int(queue.index)] {
                                sleep(0)
                            }
                        }
                    }
                }
            }
            
            executePass(passRecord, i: i, encoderManager: encoderManager!)
        }
        
        processCommandBuffer()
        
        // Balance out the starting count of one for commandBufferCount
        if passCommandBufferIndices.isEmpty {
            completion()
            self.accessSemaphore.signal()
        }
        
        self.resourceCommands.removeAll(keepingCapacity: true)
        
        self.renderTargetTextureProperties.removeAll(keepingCapacity: true)
        
        assert(self.backend.activeContext === self)
        self.backend.activeContext = nil
    }
}

#endif // canImport(Metal)
