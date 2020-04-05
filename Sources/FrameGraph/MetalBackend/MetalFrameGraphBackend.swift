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

enum MetalPreFrameResourceCommands {
    
    // These commands mutate the MetalResourceRegistry and should be executed before render pass execution:
    case materialiseBuffer(Buffer, usage: BufferUsage)
    case materialiseTexture(Texture, usage: TextureUsageProperties)
    case materialiseTextureView(Texture, usage: TextureUsageProperties)
    case materialiseArgumentBuffer(_ArgumentBuffer)
    case materialiseArgumentBufferArray(_ArgumentBufferArray)
    case disposeResource(Resource)
    
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
    
    func execute(resourceRegistry: MetalTransientResourceRegistry, resourceMap: MetalFrameResourceMap, stateCaches: MetalStateCaches, queue: Queue, encoderDependencies: inout DependencyTable<Dependency?>, waitEventValues: inout QueueCommandIndices, signalEventValue: UInt64) {
        let queueIndex = Int(queue.index)
        
        switch self {
        case .materialiseBuffer(let buffer):
            // If the resource hasn't already been allocated and is transient, we should force it to be GPU private since the CPU is guaranteed not to use it.
            resourceRegistry.allocateBufferIfNeeded(buffer, forceGPUPrivate: !buffer._usesPersistentRegistry && buffer._deferredSliceActions.isEmpty)
            
            let waitEvent = buffer.flags.contains(.historyBuffer) ? resourceRegistry.historyBufferResourceWaitEvents[Resource(buffer)] : resourceRegistry.bufferWaitEvents[buffer]
            
            waitEventValues[queueIndex] = max(waitEvent!.waitValue, waitEventValues[queueIndex])
            buffer.applyDeferredSliceActions()
            
        case .materialiseTexture(let texture, let usage):
            // If the resource hasn't already been allocated and is transient, we should force it to be GPU private since the CPU is guaranteed not to use it.
            resourceRegistry.allocateTextureIfNeeded(texture, usage: usage, forceGPUPrivate: !texture._usesPersistentRegistry)
            if let textureWaitEvent = (texture.flags.contains(.historyBuffer) ? resourceRegistry.historyBufferResourceWaitEvents[Resource(texture)] : resourceRegistry.textureWaitEvents[texture]) {
                waitEventValues[queueIndex] = max(textureWaitEvent.waitValue, waitEventValues[queueIndex])
            } else {
                precondition(texture.flags.contains(.windowHandle))
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

enum MetalFrameResourceCommands {
    // These commands need to be executed during render pass execution and do not modify the MetalResourceRegistry.
    case useResource(Resource, usage: MTLResourceUsage, stages: MTLRenderStages, allowReordering: Bool)
    case memoryBarrier(Resource, scope: MTLBarrierScope, afterStages: MTLRenderStages, beforeCommand: Int, beforeStages: MTLRenderStages) // beforeCommand is the command that this memory barrier must have been executed before.
}

enum MetalCompactedFrameResourceCommands {
    // These commands need to be executed during render pass execution and do not modify the MetalResourceRegistry.
    case useResources(UnsafeMutableBufferPointer<MTLResource>, usage: MTLResourceUsage, stages: MTLRenderStages)
    case resourceMemoryBarrier(resources: UnsafeMutableBufferPointer<MTLResource>, afterStages: MTLRenderStages, beforeStages: MTLRenderStages)
    case scopedMemoryBarrier(scope: MTLBarrierScope, afterStages: MTLRenderStages, beforeStages: MTLRenderStages)
    case updateFence(MetalFenceHandle, afterStages: MTLRenderStages)
    case waitForFence(MetalFenceHandle, beforeStages: MTLRenderStages)
}

struct MetalPreFrameResourceCommand : Comparable {
    var command : MetalPreFrameResourceCommands
    var passIndex : Int
    var index : Int
    var order : PerformOrder
    
    public static func ==(lhs: MetalPreFrameResourceCommand, rhs: MetalPreFrameResourceCommand) -> Bool {
        return lhs.index == rhs.index &&
            lhs.order == rhs.order &&
            lhs.command.isMaterialiseNonArgumentBufferResource == rhs.command.isMaterialiseNonArgumentBufferResource
    }
    
    public static func <(lhs: MetalPreFrameResourceCommand, rhs: MetalPreFrameResourceCommand) -> Bool {
        if lhs.index < rhs.index { return true }
        if lhs.index == rhs.index, lhs.order < rhs.order {
            return true
        }
        // Materialising argument buffers always needs to happen last, after materialising all resources within it.
        if lhs.index == rhs.index, lhs.order == rhs.order, lhs.command.isMaterialiseNonArgumentBufferResource && !rhs.command.isMaterialiseNonArgumentBufferResource {
            return true
        }
        return false
    }
}

struct MetalFrameResourceCommand : Comparable {
    var command : MetalFrameResourceCommands
    var index : Int
    
    public static func ==(lhs: MetalFrameResourceCommand, rhs: MetalFrameResourceCommand) -> Bool {
        return lhs.index == rhs.index
    }
    
    public static func <(lhs: MetalFrameResourceCommand, rhs: MetalFrameResourceCommand) -> Bool {
        if lhs.index < rhs.index { return true }
        return false
    }
}

struct MetalCompactedResourceCommand : Comparable {
    var command : MetalCompactedFrameResourceCommands
    var index : Int
    var order : PerformOrder
    
    public static func ==(lhs: MetalCompactedResourceCommand, rhs: MetalCompactedResourceCommand) -> Bool {
        return lhs.index == rhs.index && lhs.order == rhs.order
    }
    
    public static func <(lhs: MetalCompactedResourceCommand, rhs: MetalCompactedResourceCommand) -> Bool {
        if lhs.index < rhs.index { return true }
        if lhs.index == rhs.index, lhs.order < rhs.order {
            return true
        }
        return false
    }
}

struct TextureUsageProperties {
    var usage : TextureUsage
    #if (os(iOS) || os(tvOS) || os(watchOS)) && !targetEnvironment(macCatalyst)
    var canBeMemoryless : Bool
    #endif
    
    init(usage: TextureUsage, canBeMemoryless: Bool = false) {
        self.usage = usage
        #if (os(iOS) || os(tvOS) || os(watchOS)) && !targetEnvironment(macCatalyst)
        self.canBeMemoryless = canBeMemoryless
        #endif
    }
    
    init(_ usage: TextureUsage) {
        self.init(usage: MTLTextureUsage(usage), canBeMemoryless: false)
    }
}

struct UseResourceKey: Hashable {
    var stages: MTLRenderStages
    var usage: MTLResourceUsage
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(stages.rawValue)
        hasher.combine(usage.rawValue)
    }
    
    static func ==(lhs: UseResourceKey, rhs: UseResourceKey) -> Bool {
        return lhs.stages == rhs.stages && lhs.usage == rhs.usage
    }
}

struct MetalResidentResource: Hashable, Equatable {
    var resource: Unmanaged<MTLResource>
    var stages: MTLRenderStages
    var usage: MTLResourceUsage
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(resource.toOpaque())
        hasher.combine(stages.rawValue)
        hasher.combine(usage.rawValue)
    }
    
    static func ==(lhs: MetalResidentResource, rhs: MetalResidentResource) -> Bool {
        return lhs.resource.toOpaque() == rhs.resource.toOpaque() && lhs.stages == rhs.stages && lhs.usage == rhs.usage
    }
}

extension MTLRenderStages {
    var first: MTLRenderStages {
        if self.contains(.vertex) { return .vertex }
        return self
    }
    
    var last: MTLRenderStages {
        if self.contains(.fragment) { return .fragment }
        return self
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
        self.resourceRegistry = MetalTransientResourceRegistry(device: backend.device, inflightFrameCount: inflightFrameCount, transientRegistryIndex: transientRegistryIndex, persistentRegistry: backend.resourceRegistry)
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
    
    var resourceRegistryPreFrameCommands = [MetalPreFrameResourceCommand]()
    var resourceCommands = [MetalFrameResourceCommand]()
    var compactedResourceCommands = [MetalCompactedResourceCommand]()
    
    var renderTargetTextureProperties = [Texture : TextureUsageProperties]()
    var commandEncoderDependencies = DependencyTable<Dependency?>(capacity: 1, defaultValue: nil)
    
    /// - param storedTextures: textures that are stored as part of a render target (and therefore can't be memoryless on iOS)
    func generateResourceCommands(passes: [RenderPassRecord], resourceUsages: ResourceUsages, frameCommandInfo: inout MetalFrameCommandInfo) {
        
        if passes.isEmpty {
            return
        }
        
        self.commandEncoderDependencies.resizeAndClear(capacity: frameCommandInfo.commandEncoders.count, clearValue: nil)
        
        resourceLoop: for resource in resourceUsages.allResources {
            let resourceType = resource.type
            
            let usages = resource.usages
            
            if usages.isEmpty { continue }
            
            var resourceIsRenderTarget = false
            
            do {
                // Track resource residency.
                var previousEncoderIndex: Int = -1
                var previousUsageType: MTLResourceUsage = []
                var previousUsageStages: RenderStages = []
                
                for usage in usages
                    where usage.renderPassRecord.isActive &&
                        usage.renderPassRecord.pass.passType != .external &&
//                        usage.inArgumentBuffer &&
                        usage.stages != .cpuBeforeRender {
                            if usage.type.isRenderTarget {
                                resourceIsRenderTarget = true
                                continue
                            }
                            
                            let usageEncoderIndex = frameCommandInfo.encoderIndex(for: usage.renderPassRecord)
                        
                            var computedUsageType: MTLResourceUsage = []
                            if resourceType == .texture, usage.type == .read {
                                computedUsageType.formUnion(.sample)
                            }
                            if usage.isRead {
                                computedUsageType.formUnion(.read)
                            }
                            if usage.isWrite {
                                computedUsageType.formUnion(.write)
                            }
                            
                            if computedUsageType != previousUsageType || usage.stages != previousUsageStages || usageEncoderIndex != previousEncoderIndex {
                                self.resourceCommands.append(MetalFrameResourceCommand(command: .useResource(resource, usage: computedUsageType, stages: MTLRenderStages(usage.stages), allowReordering: !resourceIsRenderTarget && usageEncoderIndex != previousEncoderIndex), // Keep the useResource call as late as possible for render targets, and don't allow reordering within an encoder.
                                                                                       index: usage.commandRange.lowerBound))
                            }
                            
                            previousUsageType = computedUsageType
                            previousEncoderIndex = usageEncoderIndex
                            previousUsageStages = usage.stages
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
                let fenceDependency = FenceDependency(encoderIndex: frameCommandInfo.encoderIndex(for: firstUsage.renderPassRecord), index: firstUsage.commandRange.lowerBound, stages: firstUsage.stages)
                self.resourceRegistryPreFrameCommands.append(MetalPreFrameResourceCommand(command: .waitForHeapAliasingFences(resource: resource, waitDependency: fenceDependency), passIndex: firstUsage.renderPassRecord.passIndex, index: firstUsage.commandRange.lowerBound, order: .before))
                
            }
            
            while let usage = usageIterator.next()  {
                if !usage.affectsGPUBarriers {
                    continue
                }
                
                if usage.isWrite {
                    assert(!resource.flags.contains(.immutableOnceInitialised) || !resource.stateFlags.contains(.initialised), "A resource with the flag .immutableOnceInitialised is being written to in \(usage) when it has already been initialised.")
                    
                    for previousRead in readsSinceLastWrite where frameCommandInfo.encoderIndex(for: previousRead.renderPassRecord) != frameCommandInfo.encoderIndex(for: usage.renderPassRecord) {
                        let fromEncoder = frameCommandInfo.encoderIndex(for: usage.renderPassRecord)
                        let onEncoder = frameCommandInfo.encoderIndex(for: previousRead.renderPassRecord)
                        let dependency = Dependency(dependentUsage: usage, dependentEncoder: onEncoder, passUsage: previousRead, passEncoder: fromEncoder)
                        
                        commandEncoderDependencies.setDependency(from: fromEncoder,
                                                                 on: onEncoder,
                                                                 to: commandEncoderDependencies.dependency(from: fromEncoder, on: onEncoder)?.merged(with: dependency) ?? dependency)
                    }
                }
                
                // Only insert a barrier for the first usage following a write.
                if usage.isRead, previousUsage.isWrite,
                    frameCommandInfo.encoderIndex(for: previousUsage.renderPassRecord) == frameCommandInfo.encoderIndex(for: usage.renderPassRecord)  {
                    if !(previousUsage.type.isRenderTarget && (usage.type == .writeOnlyRenderTarget || usage.type == .readWriteRenderTarget)) {
                        assert(!usage.stages.isEmpty || usage.renderPassRecord.pass.passType != .draw)
                        assert(!previousUsage.stages.isEmpty || previousUsage.renderPassRecord.pass.passType != .draw)
                        var scope: MTLBarrierScope = []
                        #if os(macOS) || targetEnvironment(macCatalyst)
                        if previousUsage.type.isRenderTarget || usage.type.isRenderTarget {
                            scope.formUnion(.renderTargets)
                        }
                        #endif
                        if resource.type == .texture {
                            scope.formUnion(.textures)
                        } else if resource.type == .buffer || resource.type == .argumentBuffer || resource.type == .argumentBufferArray {
                            scope.formUnion(.buffers)
                        } else {
                            assertionFailure()
                        }
                        
                        self.resourceCommands.append(MetalFrameResourceCommand(command: .memoryBarrier(Resource(resource), scope: scope, afterStages: MTLRenderStages(previousUsage.stages), beforeCommand: usage.commandRange.lowerBound, beforeStages: MTLRenderStages(usage.stages)), index: previousUsage.commandRange.last!))
                            
                    }
                }
                
                if (usage.isRead || usage.isWrite), let previousWrite = previousWrite, frameCommandInfo.encoderIndex(for: previousWrite.renderPassRecord) != frameCommandInfo.encoderIndex(for: usage.renderPassRecord) {
                    let fromEncoder = frameCommandInfo.encoderIndex(for: usage.renderPassRecord)
                    let onEncoder = frameCommandInfo.encoderIndex(for: previousWrite.renderPassRecord)
                    let dependency = Dependency(dependentUsage: usage, dependentEncoder: onEncoder, passUsage: previousWrite, passEncoder: fromEncoder)
                    
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
            
            #if (os(iOS) || os(tvOS) || os(watchOS)) && !targetEnvironment(macCatalyst)
            var canBeMemoryless = false
            #else
            let canBeMemoryless = false
            #endif
            
            // Insert commands to materialise and dispose of the resource.
            if let argumentBuffer = resource.argumentBuffer {
                // Unlike textures and buffers, we materialise persistent argument buffers at first use rather than immediately.
                if !historyBufferUseFrame {
                    self.resourceRegistryPreFrameCommands.append(MetalPreFrameResourceCommand(command: .materialiseArgumentBuffer(argumentBuffer), passIndex: firstUsage.renderPassRecord.passIndex, index: firstUsage.commandRange.lowerBound, order: .before))
                }
                
                if !resource.flags.contains(.persistent), !resource.flags.contains(.historyBuffer) || resource.stateFlags.contains(.initialised) {
                    if historyBufferUseFrame {
                        self.resourceRegistry.registerInitialisedHistoryBufferForDisposal(resource: resource)
                    } else {
                        self.resourceRegistryPreFrameCommands.append(MetalPreFrameResourceCommand(command: .disposeResource(resource), passIndex: lastUsage.renderPassRecord.passIndex, index: lastUsage.commandRange.last!, order: .after))
                    }
                }
                
            } else if !resource.flags.contains(.persistent) || resource.flags.contains(.windowHandle) {
                if let buffer = resource.buffer {
                    if !historyBufferUseFrame {
                        self.resourceRegistryPreFrameCommands.append(MetalPreFrameResourceCommand(command: .materialiseBuffer(buffer), passIndex: firstUsage.renderPassRecord.passIndex, index: firstUsage.commandRange.lowerBound, order: .before))
                    }
                    
                    if !resource.flags.contains(.historyBuffer) || resource.stateFlags.contains(.initialised) {
                        if historyBufferUseFrame {
                            self.resourceRegistry.registerInitialisedHistoryBufferForDisposal(resource: resource)
                        } else {
                            self.resourceRegistryPreFrameCommands.append(MetalPreFrameResourceCommand(command: .disposeResource(resource), passIndex: lastUsage.renderPassRecord.passIndex, index: lastUsage.commandRange.last!, order: .after))
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
                    
                    #if (os(iOS) || os(tvOS) || os(watchOS)) && !targetEnvironment(macCatalyst)
                    canBeMemoryless = (texture.flags.intersection([.persistent, .historyBuffer]) == [] || (texture.flags.contains(.persistent) && texture.descriptor.usageHint == .renderTarget))
                        && textureUsage == .renderTarget
                        && !frameCommandInfo.storedTextures.contains(texture)
                    let properties = TextureUsageProperties(usage: textureUsage, canBeMemoryless: canBeMemoryless)
                    #else
                    let properties = TextureUsageProperties(usage: textureUsage)
                    #endif
                    
                    assert(properties.usage != .unknown)
                    
                    if textureUsage.contains(.renderTarget) {
                        self.renderTargetTextureProperties[texture] = properties
                    }
                    
                    if !historyBufferUseFrame {
                        if texture.isTextureView {
                            self.resourceRegistryPreFrameCommands.append(MetalPreFrameResourceCommand(command: .materialiseTextureView(texture, usage: properties), passIndex: firstUsage.renderPassRecord.passIndex, index: firstUsage.commandRange.lowerBound, order: .before))
                        } else {
                            self.resourceRegistryPreFrameCommands.append(MetalPreFrameResourceCommand(command: .materialiseTexture(texture, usage: properties), passIndex: firstUsage.renderPassRecord.passIndex, index: firstUsage.commandRange.lowerBound, order: .before))
                        }
                    }
                    
                    if !resource.flags.contains(.historyBuffer) || resource.stateFlags.contains(.initialised) {
                        if historyBufferUseFrame {
                            self.resourceRegistry.registerInitialisedHistoryBufferForDisposal(resource: Resource(texture))
                        } else {
                            self.resourceRegistryPreFrameCommands.append(MetalPreFrameResourceCommand(command: .disposeResource(resource), passIndex: lastUsage.renderPassRecord.passIndex, index: lastUsage.commandRange.last!, order: .after))
                        }
                        
                    }
                }
            }
            
            if resource.flags.intersection([.persistent, .historyBuffer]) != [], (!resource.stateFlags.contains(.initialised) || !resource.flags.contains(.immutableOnceInitialised)) {
                for queue in QueueRegistry.allQueues {
                    // TODO: separate out the wait index for the first read from the first write.
                    let waitIndex = resource[waitIndexFor: queue, accessType: previousWrite != nil ? .readWrite : .read]
                    self.resourceRegistryPreFrameCommands.append(MetalPreFrameResourceCommand(command: .waitForCommandBuffer(index: waitIndex, queue: queue), passIndex: firstUsage.renderPassRecord.passIndex, index: firstUsage.commandRange.last!, order: .before))
                }
                
                if lastUsage.isWrite {
                    self.resourceRegistryPreFrameCommands.append(MetalPreFrameResourceCommand(command: .updateCommandBufferWaitIndex(resource, accessType: .readWrite), passIndex: lastUsage.renderPassRecord.passIndex, index: lastUsage.commandRange.last!, order: .after))
                } else {
                    if let lastWrite = previousWrite {
                        self.resourceRegistryPreFrameCommands.append(MetalPreFrameResourceCommand(command: .updateCommandBufferWaitIndex(resource, accessType: .readWrite), passIndex: lastWrite.renderPassRecord.passIndex, index: lastWrite.commandRange.last!, order: .after))
                    }
                    for read in readsSinceLastWrite {
                        self.resourceRegistryPreFrameCommands.append(MetalPreFrameResourceCommand(command: .updateCommandBufferWaitIndex(resource, accessType: .write), passIndex: read.renderPassRecord.passIndex, index: read.commandRange.last!, order: .after))
                    }
                }
            }
            
            if resourceRegistry.isAliasedHeapResource(resource: resource), !canBeMemoryless {
                // Reads need to wait for all previous writes to complete.
                // Writes need to wait for all previous reads and writes to complete.
                
                var storeFences : [FenceDependency] = []
                
                // We only need to wait for the write to complete if there have been no reads since the write; otherwise, we wait on the reads
                // which in turn have a transitive dependency on the write.
                if readsSinceLastWrite.isEmpty, let previousWrite = previousWrite, previousWrite.renderPassRecord.pass.passType != .external {
                    storeFences = [FenceDependency(encoderIndex: frameCommandInfo.encoderIndex(for: previousWrite.renderPassRecord), index: previousWrite.commandRange.last!, stages: previousWrite.stages)]
                }
                
                for read in readsSinceLastWrite where read.renderPassRecord.pass.passType != .external {
                    storeFences.append(FenceDependency(encoderIndex: frameCommandInfo.encoderIndex(for: read.renderPassRecord), index: read.commandRange.last!, stages: read.stages))
                }
                
                // setDisposalFences retains its fences.
                self.resourceRegistry.setDisposalFences(on: resource, to: storeFences)
            }
            
        }
        
        self.resourceRegistryPreFrameCommands.sort()
        
        // MARK: - Execute the pre-frame resource commands.
        
        for command in self.resourceRegistryPreFrameCommands {
            let encoderIndex = frameCommandInfo.encoderIndex(for: command.passIndex)
            let commandBufferIndex = frameCommandInfo.commandEncoders[encoderIndex].commandBufferIndex
            command.command.execute(resourceRegistry: self.resourceRegistry, resourceMap: self.resourceMap, stateCaches: backend.stateCaches, queue: self.frameGraphQueue,
                                    encoderDependencies: &self.commandEncoderDependencies,
                                    waitEventValues: &frameCommandInfo.commandEncoders[encoderIndex].queueCommandWaitIndices, signalEventValue: frameCommandInfo.signalValue(commandBufferIndex: commandBufferIndex))
        }
        
        self.resourceRegistryPreFrameCommands.removeAll(keepingCapacity: true)
        
        // MARK: - Generate the fences
        
        // Process the dependencies, joining duplicates.
        do {
            
            let commandEncoderCount = frameCommandInfo.commandEncoders.count
            let reductionMatrix = self.commandEncoderDependencies.transitiveReduction(hasDependency: { $0 != nil })
            
            for sourceIndex in (0..<commandEncoderCount) { // sourceIndex always points to the producing pass.
                let dependentRange = min(sourceIndex + 1, commandEncoderCount)..<commandEncoderCount
                
                var signalStages : MTLRenderStages = []
                var signalIndex = -1
                for dependentIndex in dependentRange where reductionMatrix.dependency(from: dependentIndex, on: sourceIndex) {
                    let dependency = self.commandEncoderDependencies.dependency(from: dependentIndex, on: sourceIndex)!
                    signalStages.formUnion(MTLRenderStages(dependency.signal.stages))
                    signalIndex = max(signalIndex, dependency.signal.index)
                }
                
                if signalIndex < 0 { continue }
                
                let label = "Encoder \(sourceIndex) Fence"
                let commandBufferSignalValue = frameCommandInfo.signalValue(commandBufferIndex: frameCommandInfo.commandEncoders[sourceIndex].commandBufferIndex)
                let fence = MetalFenceHandle(label: label, queue: self.frameGraphQueue, commandBufferIndex: commandBufferSignalValue)
                
                self.compactedResourceCommands.append(MetalCompactedResourceCommand(command: .updateFence(fence, afterStages: signalStages), index: signalIndex, order: .after))
                
                for dependentIndex in dependentRange where reductionMatrix.dependency(from: dependentIndex, on: sourceIndex) {
                    let dependency = self.commandEncoderDependencies.dependency(from: dependentIndex, on: sourceIndex)!
                    self.compactedResourceCommands.append(MetalCompactedResourceCommand(command: .waitForFence(fence, beforeStages: MTLRenderStages(dependency.wait.stages)), index: dependency.wait.index, order: .before))
                }
            }
        }
        
        self.compactResourceCommands(commandInfo: frameCommandInfo)
    }
    
    static var resourceCommandArrayTag: TaggedHeap.Tag {
        return UInt64(bitPattern: Int64("MetalFrameGraph Compacted Resource Commands".hashValue))
    }
    
    func compactResourceCommands(commandInfo: MetalFrameCommandInfo) {
        guard !self.resourceCommands.isEmpty else { return }
        self.resourceCommands.sort()
        
        let allocator = ThreadLocalTagAllocator(tag: Self.resourceCommandArrayTag)
        
        var currentEncoderIndex = 0
        var currentEncoder = commandInfo.commandEncoders[currentEncoderIndex]
        
        
        var barrierResources: [Unmanaged<MTLResource>] = []
        barrierResources.reserveCapacity(8) // we use memoryBarrier(resource) for up to eight resources, and memoryBarrier(scope) otherwise.
        
        var barrierScope: MTLBarrierScope = []
        var barrierAfterStages: MTLRenderStages = []
        var barrierBeforeStages: MTLRenderStages = []
        var barrierLastIndex: Int = .max
        
        var encoderResidentResources = Set<MetalResidentResource>()
        
        var encoderUseResourceCommandIndex: Int = .max
        var encoderUseResources = [UseResourceKey: [Unmanaged<MTLResource>]]()
        
        let addBarrier = {
            if barrierResources.count <= 8 {
                let memory = allocator.allocate(capacity: barrierResources.count) as UnsafeMutablePointer<Unmanaged<MTLResource>>
                memory.assign(from: barrierResources, count: barrierResources.count)
                let bufferPointer = UnsafeMutableBufferPointer<MTLResource>(start: UnsafeMutableRawPointer(memory).assumingMemoryBound(to: MTLResource.self), count: barrierResources.count)
                
                self.compactedResourceCommands.append(.init(command: .resourceMemoryBarrier(resources: bufferPointer, afterStages: barrierAfterStages.last, beforeStages: barrierBeforeStages.first), index: barrierLastIndex, order: .before))
            } else {
                self.compactedResourceCommands.append(.init(command: .scopedMemoryBarrier(scope: barrierScope, afterStages: barrierAfterStages.last, beforeStages: barrierBeforeStages.first), index: barrierLastIndex, order: .before))
            }
            barrierResources.removeAll(keepingCapacity: true)
            barrierScope = []
            barrierAfterStages = []
            barrierBeforeStages = []
            barrierLastIndex = .max
        }
        
        let useResources = {
            for (key, resources) in encoderUseResources where !resources.isEmpty {
                let memory = allocator.allocate(capacity: resources.count) as UnsafeMutablePointer<Unmanaged<MTLResource>>
                memory.assign(from: resources, count: resources.count)
                let bufferPointer = UnsafeMutableBufferPointer<MTLResource>(start: UnsafeMutableRawPointer(memory).assumingMemoryBound(to: MTLResource.self), count: resources.count)
                
                self.compactedResourceCommands.append(.init(command: .useResources(bufferPointer, usage: key.usage, stages: key.stages), index: encoderUseResourceCommandIndex, order: .before))
            }
            encoderUseResourceCommandIndex = .max
            encoderUseResources.removeAll(keepingCapacity: true)
            encoderResidentResources.removeAll(keepingCapacity: true)
        }
        
        let getResource: (Resource) -> Unmanaged<MTLResource> = { resource in
             if let buffer = resource.buffer {
                return unsafeBitCast(self.resourceMap[buffer]._buffer, to: Unmanaged<MTLResource>.self)
             } else if let texture = resource.texture {
                return unsafeBitCast(self.resourceMap[textureReference: texture]._texture, to: Unmanaged<MTLResource>.self)
             } else if let argumentBuffer = resource.argumentBuffer {
                return unsafeBitCast(self.resourceMap[argumentBuffer]._buffer, to: Unmanaged<MTLResource>.self)
             }
            fatalError()
        }
        
        for command in resourceCommands {
            if command.index >= barrierLastIndex {
                addBarrier()
            }
            
            while !currentEncoder.commandRange.contains(command.index) {
                currentEncoderIndex += 1
                currentEncoder = commandInfo.commandEncoders[currentEncoderIndex]
                
                useResources()
                
                assert(barrierScope == [])
                assert(barrierResources.isEmpty)
            }

            // Strategy:
            // useResource should be batched together by usage to as early as possible in the encoder.
            // memoryBarriers should be as late as possible.
            switch command.command {
            case .useResource(let resource, let usage, let stages, let allowReordering):
                let mtlResource = getResource(resource)
                
                if !allowReordering {
                    let memory = allocator.allocate(capacity: 1) as UnsafeMutablePointer<Unmanaged<MTLResource>>
                    memory.initialize(to: mtlResource)
                    let bufferPointer = UnsafeMutableBufferPointer<MTLResource>(start: UnsafeMutableRawPointer(memory).assumingMemoryBound(to: MTLResource.self), count: 1)
                    self.compactedResourceCommands.append(.init(command: .useResources(bufferPointer, usage: usage, stages: stages), index: command.index, order: .before))
                } else {
                    let key = MetalResidentResource(resource: mtlResource, stages: stages, usage: usage)
                    let (inserted, _) = encoderResidentResources.insert(key)
                    if inserted {
                        encoderUseResources[UseResourceKey(stages: stages, usage: usage), default: []].append(mtlResource)
                    }
                    encoderUseResourceCommandIndex = min(command.index, encoderUseResourceCommandIndex)
                }
                
            case .memoryBarrier(let resource, let scope, let afterStages, let beforeCommand, let beforeStages):
                if barrierResources.count < 8 {
                    barrierResources.append(getResource(resource))
                }
                barrierScope.formUnion(scope)
                barrierAfterStages.formUnion(afterStages)
                barrierBeforeStages.formUnion(beforeStages)
                barrierLastIndex = min(beforeCommand, barrierLastIndex)
            }
        }
        
        if barrierLastIndex < .max {
            addBarrier()
        }
        useResources()
        
        self.compactedResourceCommands.sort()
        self.resourceCommands.removeAll(keepingCapacity: true)
    }
    
    public func executeFrameGraph(passes: [RenderPassRecord], dependencyTable: DependencyTable<SwiftFrameGraph.DependencyType>, resourceUsages: ResourceUsages, completion: @escaping () -> Void) {
        self.resourceRegistry.prepareFrame()
        
        defer {
            TaggedHeap.free(tag: Self.resourceCommandArrayTag)
            
            self.resourceRegistry.cycleFrames()

            self.compactedResourceCommands.removeAll(keepingCapacity: true)
            self.renderTargetTextureProperties.removeAll(keepingCapacity: true)
            
            assert(self.backend.activeContext === self)
            self.backend.activeContext = nil
        }
        
        if passes.isEmpty {
            completion()
            self.accessSemaphore.signal()
            return
        }
        
        var frameCommandInfo = MetalFrameCommandInfo(passes: passes, resourceUsages: resourceUsages, initialCommandBufferSignalValue: self.queueCommandBufferIndex + 1)
        
        self.generateResourceCommands(passes: passes, resourceUsages: resourceUsages, frameCommandInfo: &frameCommandInfo)
        
        func executePass(_ passRecord: RenderPassRecord, i: Int, encoderInfo: MetalFrameCommandInfo.CommandEncoderInfo, encoderManager: MetalEncoderManager) {
            switch passRecord.pass.passType {
            case .blit:
                let commandEncoder = encoderManager.blitCommandEncoder()
                if commandEncoder.encoder.label == nil {
                    commandEncoder.encoder.label = encoderInfo.name
                }
                
                commandEncoder.executePass(passRecord, resourceCommands: compactedResourceCommands, resourceMap: self.resourceMap, stateCaches: backend.stateCaches)
                
            case .draw:
                guard let commandEncoder = encoderManager.renderCommandEncoder(descriptor: encoderInfo.renderTargetDescriptor!, textureUsages: self.renderTargetTextureProperties, resourceMap: self.resourceMap, stateCaches: backend.stateCaches) else {
                    if _isDebugAssertConfiguration() {
                        print("Warning: skipping pass \(passRecord.pass.name) since the drawable for the render target could not be retrieved.")
                    }
                    
                    return
                }
                if commandEncoder.label == nil {
                    commandEncoder.label = encoderInfo.name
                }
                
                commandEncoder.executePass(passRecord, resourceCommands: compactedResourceCommands, renderTarget: encoderInfo.renderTargetDescriptor!.descriptor, passRenderTarget: (passRecord.pass as! DrawRenderPass).renderTargetDescriptor, resourceMap: self.resourceMap, stateCaches: backend.stateCaches)
            case .compute:
                let commandEncoder = encoderManager.computeCommandEncoder()
                if commandEncoder.encoder.label == nil {
                    commandEncoder.encoder.label = encoderInfo.name
                }
                
                commandEncoder.executePass(passRecord, resourceCommands: compactedResourceCommands, resourceMap: self.resourceMap, stateCaches: backend.stateCaches)
                
            case .external:
                let commandEncoder = encoderManager.externalCommandEncoder()
                commandEncoder.executePass(passRecord, resourceCommands: compactedResourceCommands, resourceMap: self.resourceMap, stateCaches: backend.stateCaches)
                
            case .cpu:
                break
            }
        }
        
        self.captureScope.begin()
        defer { self.captureScope.end() }
        
        // Use separate command buffers for onscreen and offscreen work (Delivering Optimised Metal Apps and Games, WWDC 2019)
        
        let lastCommandBufferIndex = frameCommandInfo.commandBufferCount - 1
        
        var commandBuffer : MTLCommandBuffer? = nil
        var encoderManager : MetalEncoderManager? = nil
        
        var committedCommandBufferCount = 0
        var previousCommandEncoderIndex = -1

        func processCommandBuffer() {
            encoderManager?.endEncoding()
            
            if let commandBuffer = commandBuffer {
                // Only contains drawables applicable to the render passes in the command buffer...
                for drawable in self.resourceRegistry.frameDrawables {
                    #if (os(iOS) || os(tvOS) || os(watchOS)) && !targetEnvironment(macCatalyst)
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
        
        var waitedEvents = QueueCommandIndices(repeating: 0)
        
        for (i, passRecord) in passes.enumerated() {
            let passCommandEncoderIndex = frameCommandInfo.encoderIndex(for: passRecord)
            let passEncoderInfo = frameCommandInfo.commandEncoders[passCommandEncoderIndex]
            let commandBufferIndex = passEncoderInfo.commandBufferIndex
            if commandBufferIndex != committedCommandBufferCount {
                processCommandBuffer()
            }
            
            if commandBuffer == nil {
                commandBuffer = self.commandQueue.makeCommandBuffer()!
                encoderManager = MetalEncoderManager(commandBuffer: commandBuffer!, resourceMap: self.resourceMap)
            }
            
            if previousCommandEncoderIndex != passCommandEncoderIndex {
                previousCommandEncoderIndex = passCommandEncoderIndex
                encoderManager?.endEncoding()
                
                let waitEventValues = passEncoderInfo.queueCommandWaitIndices
                for queue in QueueRegistry.allQueues {
                    if waitedEvents[Int(queue.index)] < waitEventValues[Int(queue.index)],
                        waitEventValues[Int(queue.index)] > queue.lastCompletedCommand {
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
                waitedEvents = pointwiseMax(waitEventValues, waitedEvents)
            }
            
            executePass(passRecord, i: i, encoderInfo: passEncoderInfo, encoderManager: encoderManager!)
        }
        
        processCommandBuffer()
    }
}

#endif // canImport(Metal)
