//
//  ResourceCommandGenerator.swift
//  
//
//  Created by Thomas Roughton on 6/04/20.
//

import FrameGraphUtilities


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
        self.init(usage: usage, canBeMemoryless: false)
    }
}

/// The value to wait for on the event associated with this FrameGraph context.
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

enum PreFrameCommands<Dependency: SwiftFrameGraph.Dependency> {
    
    // These commands mutate the ResourceRegistry and should be executed before render pass execution:
    case materialiseBuffer(Buffer, usage: BufferUsage)
    case materialiseTexture(Texture, usage: TextureUsageProperties)
    case materialiseTextureView(Texture, usage: TextureUsageProperties)
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
    
    func execute<Backend: SpecificRenderBackend>(resourceRegistry: Backend.TransientResourceRegistry, resourceMap: FrameResourceMap<Backend>, queue: Queue, encoderDependencies: inout DependencyTable<Dependency?>, waitEventValues: inout QueueCommandIndices, signalEventValue: UInt64) {
        let queueIndex = Int(queue.index)
        
        switch self {
        case .materialiseBuffer(let buffer, let usage):
            // If the resource hasn't already been allocated and is transient, we should force it to be GPU private since the CPU is guaranteed not to use it.
            _ = resourceRegistry.allocateBufferIfNeeded(buffer, usage: usage, forceGPUPrivate: !buffer._usesPersistentRegistry && buffer._deferredSliceActions.isEmpty)
            
            let waitEvent = buffer.flags.contains(.historyBuffer) ? resourceRegistry.historyBufferResourceWaitEvents[Resource(buffer)] : resourceRegistry.bufferWaitEvents[buffer]
            
            waitEventValues[queueIndex] = max(waitEvent!.waitValue, waitEventValues[queueIndex])
            buffer.applyDeferredSliceActions()
            
        case .materialiseTexture(let texture, let usage):
            // If the resource hasn't already been allocated and is transient, we should force it to be GPU private since the CPU is guaranteed not to use it.
            _ = resourceRegistry.allocateTextureIfNeeded(texture, usage: usage, forceGPUPrivate: !texture._usesPersistentRegistry)
            if let textureWaitEvent = (texture.flags.contains(.historyBuffer) ? resourceRegistry.historyBufferResourceWaitEvents[Resource(texture)] : resourceRegistry.textureWaitEvents[texture]) {
                waitEventValues[queueIndex] = max(textureWaitEvent.waitValue, waitEventValues[queueIndex])
            } else {
                precondition(texture.flags.contains(.windowHandle))
            }
            
        case .materialiseTextureView(let texture, let usage):
            _ = resourceRegistry.allocateTextureView(texture, usage: usage, resourceMap: resourceMap)
            
        case .materialiseArgumentBuffer(let argumentBuffer):
            let argBufferReference : Backend.ArgumentBufferReference
            if argumentBuffer.flags.contains(.persistent) {
                argBufferReference = resourceMap.persistentRegistry.allocateArgumentBufferIfNeeded(argumentBuffer)
            } else {
                argBufferReference = resourceRegistry.allocateArgumentBufferIfNeeded(argumentBuffer)
                waitEventValues[queueIndex] = max(resourceRegistry.argumentBufferWaitEvents?[argumentBuffer]!.waitValue ?? 0, waitEventValues[queueIndex])
            }
            Backend.fillArgumentBuffer(argumentBuffer, storage: argBufferReference, resourceMap: resourceMap)
            
            
        case .materialiseArgumentBufferArray(let argumentBuffer):
            let argBufferReference : Backend.ArgumentBufferArrayReference
            if argumentBuffer.flags.contains(.persistent) {
                argBufferReference = resourceMap.persistentRegistry.allocateArgumentBufferArrayIfNeeded(argumentBuffer)
            } else {
                argBufferReference = resourceRegistry.allocateArgumentBufferArrayIfNeeded(argumentBuffer)
                waitEventValues[queueIndex] = max(resourceRegistry.argumentBufferArrayWaitEvents?[argumentBuffer]!.waitValue ?? 0, waitEventValues[queueIndex])
            }
            Backend.fillArgumentBufferArray(argumentBuffer, storage: argBufferReference, resourceMap: resourceMap)
            
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
    case useResource(Resource, usage: ResourceUsageType, stages: RenderStages, allowReordering: Bool)
    case memoryBarrier(Resource, afterUsage: ResourceUsageType, afterStages: RenderStages, beforeCommand: Int, beforeUsage: ResourceUsageType, beforeStages: RenderStages) // beforeCommand is the command that this memory barrier must have been executed before.
}

struct PreFrameResourceCommand<Dependency: SwiftFrameGraph.Dependency> : Comparable {
    var command : PreFrameCommands<Dependency>
    var encoderIndex : Int
    var index : Int
    var order : PerformOrder
    
    public static func ==(lhs: PreFrameResourceCommand, rhs: PreFrameResourceCommand) -> Bool {
        return lhs.index == rhs.index &&
            lhs.order == rhs.order &&
            lhs.command.isMaterialiseNonArgumentBufferResource == rhs.command.isMaterialiseNonArgumentBufferResource
    }
    
    public static func <(lhs: PreFrameResourceCommand, rhs: PreFrameResourceCommand) -> Bool {
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

final class ResourceCommandGenerator<Backend: SpecificRenderBackend> {
    typealias Dependency = Backend.InterEncoderDependencyType
    
    private var preFrameCommands = [PreFrameResourceCommand<Dependency>]()
    var commands = [FrameResourceCommand]()
    
    var renderTargetTextureProperties = [Texture : TextureUsageProperties]()
    var commandEncoderDependencies = DependencyTable<Dependency?>(capacity: 1, defaultValue: nil)
    
    func processResourceResidency(resource: Resource, frameCommandInfo: FrameCommandInfo<Backend>) {
        guard resource.type == .texture || Backend.requiresResourceResidencyTracking else { return }
        
        var resourceIsRenderTarget = false
        do {
            // Track resource residency.
            var previousEncoderIndex: Int = -1
            var previousUsageType: ResourceUsageType = .unusedArgumentBuffer
            var previousUsageStages: RenderStages = []
            
            for usage in resource.usages
                where usage.renderPassRecord.isActive &&
                    usage.renderPassRecord.pass.passType != .external &&
                    //                        usage.inArgumentBuffer &&
                    usage.stages != .cpuBeforeRender {
                        if usage.type.isRenderTarget {
                            resourceIsRenderTarget = true
                            continue
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
    
    func generateCommands(passes: [RenderPassRecord], resourceUsages: ResourceUsages, transientRegistry: Backend.TransientResourceRegistry, frameCommandInfo: inout FrameCommandInfo<Backend>) {
        if passes.isEmpty {
            return
        }
        
        self.commandEncoderDependencies.resizeAndClear(capacity: frameCommandInfo.commandEncoders.count, clearValue: nil)
        
        resourceLoop: for resource in resourceUsages.allResources {
            let usages = resource.usages
            if usages.isEmpty { continue }
            
            self.processResourceResidency(resource: resource, frameCommandInfo: frameCommandInfo)
            
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
            
            if Backend.TransientResourceRegistry.isAliasedHeapResource(resource: resource) {
                let fenceDependency = FenceDependency(encoderIndex: frameCommandInfo.encoderIndex(for: firstUsage.renderPassRecord), index: firstUsage.commandRange.lowerBound, stages: firstUsage.stages)
                self.preFrameCommands.append(PreFrameResourceCommand(command: .waitForHeapAliasingFences(resource: resource, waitDependency: fenceDependency), encoderIndex: frameCommandInfo.encoderIndex(for: firstUsage.renderPassRecord), index: firstUsage.commandRange.lowerBound, order: .before))
                
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
                        let dependency = Dependency(resource: resource, producingUsage: previousRead, producingEncoder: onEncoder, consumingUsage: usage, consumingEncoder: fromEncoder)
                        
                        commandEncoderDependencies.setDependency(from: fromEncoder,
                                                                 on: onEncoder,
                                                                 to: commandEncoderDependencies.dependency(from: fromEncoder, on: onEncoder)?.merged(with: dependency) ?? dependency)
                    }
                }
                
                // Only insert a barrier for the first usage following a write.
                if usage.isRead, previousUsage.isWrite,
                    frameCommandInfo.encoderIndex(for: previousUsage.renderPassRecord) == frameCommandInfo.encoderIndex(for: usage.renderPassRecord),
                    !(previousUsage.type.isRenderTarget && (usage.type == .writeOnlyRenderTarget || usage.type == .readWriteRenderTarget)) {
                    
                    assert(!usage.stages.isEmpty || usage.renderPassRecord.pass.passType != .draw)
                    assert(!previousUsage.stages.isEmpty || previousUsage.renderPassRecord.pass.passType != .draw)
                    
                    #if os(macOS) || targetEnvironment(macCatalyst)
                    let isRTBarrier = previousUsage.type.isRenderTarget || usage.type.isRenderTarget
                    #else
                    let isRTBarrier = false
                    #endif
                    
                    if isRTBarrier, usage._renderPass.toOpaque() == previousUsage._renderPass.toOpaque(), previousUsage.commandRange.upperBound > usage.commandRange.lowerBound {
                        // We have overlapping usages, so we need to insert a render target barrier before every draw.
                        let applicableRange = max(previousUsage.commandRangeInPass.lowerBound, usage.commandRangeInPass.lowerBound)..<min(previousUsage.commandRangeInPass.upperBound, usage.commandRangeInPass.upperBound)
                        
                        let commands = usage.renderPassRecord.commands!
                        let passCommandRange = usage.renderPassRecord.commandRange!
                        for i in applicableRange {
                            let command = commands[i]
                            if command.isDrawCommand {
                                let commandIndex = i + passCommandRange.lowerBound
                                self.commands.append(FrameResourceCommand(command: .memoryBarrier(Resource(resource), afterUsage: previousUsage.type, afterStages: previousUsage.stages, beforeCommand: commandIndex, beforeUsage: usage.type, beforeStages: usage.stages), index: commandIndex))
                            }
                        }
                        
                    } else {
                        self.commands.append(FrameResourceCommand(command: .memoryBarrier(Resource(resource), afterUsage: previousUsage.type, afterStages: previousUsage.stages, beforeCommand: usage.commandRange.lowerBound, beforeUsage: usage.type, beforeStages: usage.stages), index: previousUsage.commandRange.last!))
                    }
                }
                
                if (usage.isRead || usage.isWrite), let previousWrite = previousWrite, frameCommandInfo.encoderIndex(for: previousWrite.renderPassRecord) != frameCommandInfo.encoderIndex(for: usage.renderPassRecord) {
                    let fromEncoder = frameCommandInfo.encoderIndex(for: usage.renderPassRecord)
                    let onEncoder = frameCommandInfo.encoderIndex(for: previousWrite.renderPassRecord)
                    let dependency = Dependency(resource: resource, producingUsage: previousWrite, producingEncoder: onEncoder, consumingUsage: usage, consumingEncoder: fromEncoder)
                    
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
            if historyBufferUseFrame {
                resource.dispose() // This will dispose it in the FrameGraph persistent allocator, which will in turn call dispose in the resource registry at the end of the frame.
            }
            
            #if (os(iOS) || os(tvOS) || os(watchOS)) && !targetEnvironment(macCatalyst)
            var canBeMemoryless = false
            #else
            let canBeMemoryless = false
            #endif
            
            let firstCommandEncoderIndex = frameCommandInfo.encoderIndex(for: firstUsage.renderPassRecord)
            // We dispose at the end of a command encoder since resources can't alias against each other within a command encoder.
            let lastCommandEncoderIndex = frameCommandInfo.encoderIndex(for: lastUsage.renderPassRecord)
            let disposalIndex = frameCommandInfo.commandEncoders[lastCommandEncoderIndex].commandRange.last!
            
            // Insert commands to materialise and dispose of the resource.
            if let argumentBuffer = resource.argumentBuffer {
                // Unlike textures and buffers, we materialise persistent argument buffers at first use rather than immediately.
                if !historyBufferUseFrame {
                    self.preFrameCommands.append(PreFrameResourceCommand(command: .materialiseArgumentBuffer(argumentBuffer), encoderIndex: firstCommandEncoderIndex, index: firstUsage.commandRange.lowerBound, order: .before))
                }
                
                if !resource.flags.contains(.persistent), !resource.flags.contains(.historyBuffer) || resource.stateFlags.contains(.initialised), !historyBufferUseFrame {
                    self.preFrameCommands.append(PreFrameResourceCommand(command: .disposeResource(resource, afterStages: lastUsage.stages), encoderIndex: lastCommandEncoderIndex, index: disposalIndex, order: .after))
                }
                
            } else if !resource.flags.contains(.persistent) || resource.flags.contains(.windowHandle) {
                if let buffer = resource.buffer {
                    var bufferUsage : BufferUsage = []
                    
                    if Backend.requiresBufferUsage {
                        for usage in usages {
                            switch usage.type {
                            case .read:
                                bufferUsage.formUnion(.shaderRead)
                            case .write:
                                bufferUsage.formUnion(.shaderWrite)
                            case .readWrite:
                                bufferUsage.formUnion([.shaderRead, .shaderWrite])
                            default:
                                break
                            }
                        }
                    }
                    
                    if !historyBufferUseFrame {
                        self.preFrameCommands.append(PreFrameResourceCommand(command: .materialiseBuffer(buffer, usage: bufferUsage), encoderIndex: firstCommandEncoderIndex, index: firstUsage.commandRange.lowerBound, order: .before))
                    }
                    
                    if !resource.flags.contains(.historyBuffer) || resource.stateFlags.contains(.initialised), !historyBufferUseFrame {
                        self.preFrameCommands.append(PreFrameResourceCommand(command: .disposeResource(resource, afterStages: lastUsage.stages), encoderIndex: lastCommandEncoderIndex, index: disposalIndex, order: .after))
                    }
                    
                } else if let texture = resource.texture {
                    var textureUsage : TextureUsage = []
                    
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
                            self.preFrameCommands.append(PreFrameResourceCommand(command: .materialiseTextureView(texture, usage: properties), encoderIndex: firstCommandEncoderIndex, index: firstUsage.commandRange.lowerBound, order: .before))
                        } else {
                            self.preFrameCommands.append(PreFrameResourceCommand(command: .materialiseTexture(texture, usage: properties), encoderIndex: firstCommandEncoderIndex, index: firstUsage.commandRange.lowerBound, order: .before))
                        }
                    }
                    
                    if !resource.flags.contains(.historyBuffer) || resource.stateFlags.contains(.initialised), !historyBufferUseFrame {
                        self.preFrameCommands.append(PreFrameResourceCommand(command: .disposeResource(resource, afterStages: lastUsage.stages), encoderIndex: lastCommandEncoderIndex, index: disposalIndex, order: .after))
                        
                    }
                }
            }
            
            if resource.flags.intersection([.persistent, .historyBuffer]) != [] {
                for queue in QueueRegistry.allQueues {
                    // TODO: separate out the wait index for the first read from the first write.
                    let waitIndex = resource[waitIndexFor: queue, accessType: previousWrite != nil ? .readWrite : .read]
                    self.preFrameCommands.append(PreFrameResourceCommand(command: .waitForCommandBuffer(index: waitIndex, queue: queue), encoderIndex: firstCommandEncoderIndex, index: firstUsage.commandRange.first!, order: .before))
                }
                
                if resource.type == .texture, Backend.requiresTextureLayoutTransitions {
                    self.commands.append(FrameResourceCommand(command: .useResource(resource, usage: firstUsage.type, stages: firstUsage.stages, allowReordering: true), index: firstUsage.commandRange.first!))
                }

                if !resource.stateFlags.contains(.initialised) || !resource.flags.contains(.immutableOnceInitialised) {
                    if lastUsage.isWrite {
                        self.preFrameCommands.append(PreFrameResourceCommand(command: .updateCommandBufferWaitIndex(resource, accessType: .readWrite), encoderIndex: lastCommandEncoderIndex, index: lastUsage.commandRange.last!, order: .after))
                    } else {
                        if let lastWrite = previousWrite {
                            self.preFrameCommands.append(PreFrameResourceCommand(command: .updateCommandBufferWaitIndex(resource, accessType: .readWrite), encoderIndex: frameCommandInfo.encoderIndex(for: lastWrite.renderPassRecord), index: lastWrite.commandRange.last!, order: .after))
                        }
                        for read in readsSinceLastWrite {
                            self.preFrameCommands.append(PreFrameResourceCommand(command: .updateCommandBufferWaitIndex(resource, accessType: .write), encoderIndex: frameCommandInfo.encoderIndex(for: read.renderPassRecord), index: read.commandRange.last!, order: .after))
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
                if readsSinceLastWrite.isEmpty, let previousWrite = previousWrite, previousWrite.renderPassRecord.pass.passType != .external {
                    storeFences = [FenceDependency(encoderIndex: frameCommandInfo.encoderIndex(for: previousWrite.renderPassRecord), index: previousWrite.commandRange.last!, stages: previousWrite.stages)]
                }
                
                for read in readsSinceLastWrite where read.renderPassRecord.pass.passType != .external {
                    storeFences.append(FenceDependency(encoderIndex: frameCommandInfo.encoderIndex(for: read.renderPassRecord), index: read.commandRange.last!, stages: read.stages))
                }
                
                transientRegistry.setDisposalFences(on: resource, to: storeFences)
            }
            
        }
        
        self.commands.sort()
    }
    
    func executePreFrameCommands(queue: Queue, resourceMap: FrameResourceMap<Backend>, frameCommandInfo: inout FrameCommandInfo<Backend>) {
        self.preFrameCommands.sort()
        for command in self.preFrameCommands {
            let commandBufferIndex = frameCommandInfo.commandEncoders[command.encoderIndex].commandBufferIndex
            command.command.execute(resourceRegistry: resourceMap.transientRegistry, resourceMap: resourceMap, queue: queue,
                                    encoderDependencies: &self.commandEncoderDependencies,
                                    waitEventValues: &frameCommandInfo.commandEncoders[command.encoderIndex].queueCommandWaitIndices, signalEventValue: frameCommandInfo.signalValue(commandBufferIndex: commandBufferIndex))
        }
        
        self.preFrameCommands.removeAll(keepingCapacity: true)
    }
    
    func reset() {
        self.commands.removeAll(keepingCapacity: true)
        self.renderTargetTextureProperties.removeAll(keepingCapacity: true)
    }
}
