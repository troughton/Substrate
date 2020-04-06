//
//  File.swift
//  
//
//  Created by Thomas Roughton on 6/04/20.
//

import Foundation


enum PreFrameResourceCommands {
    
    // These commands mutate the ResourceRegistry and should be executed before render pass execution:
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
    
    func execute(resourceRegistry: TransientResourceRegistry, resourceMap: FrameResourceMap, stateCaches: StateCaches, queue: Queue, encoderDependencies: inout DependencyTable<Dependency?>, waitEventValues: inout QueueCommandIndices, signalEventValue: UInt64) {
        let queueIndex = Int(queue.index)
        
        switch self {
        case .materialiseBuffer(let buffer, let usage):
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
            let disposalWaitEvent = ContextWaitEvent(waitValue: signalEventValue)
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
    case memoryBarrier(Resource, scope: BarrierScope, afterStages: RenderStages, beforeCommand: Int, beforeStages: RenderStages) // beforeCommand is the command that this memory barrier must have been executed before.
}

struct PreFrameResourceCommand : Comparable {
    var command : PreFrameResourceCommands
    var passIndex : Int
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

final class ResourceCommandGenerator {
    
    
    var resourceRegistryPreFrameCommands = [PreFrameResourceCommand]()
    var resourceCommands = [FrameResourceCommand]()
    var compactedResourceCommands = [CompactedResourceCommand]()
    
    var renderTargetTextureProperties = [Texture : TextureUsageProperties]()
    var commandEncoderDependencies = DependencyTable<Dependency?>(capacity: 1, defaultValue: nil)
    
    /// - param storedTextures: textures that are stored as part of a render target (and therefore can't be memoryless on iOS)
    func generateResourceCommands(passes: [RenderPassRecord], resourceUsages: ResourceUsages, frameCommandInfo: inout FrameCommandInfo) {
        
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
                var previousUsageType: ResourceUsageType = []
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
                            
                            var computedUsageType: ResourceUsageType = []
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
                                self.resourceCommands.append(FrameResourceCommand(command: .useResource(resource, usage: computedUsageType, stages: usage.stages, allowReordering: !resourceIsRenderTarget && usageEncoderIndex != previousEncoderIndex), // Keep the useResource call as late as possible for render targets, and don't allow reordering within an encoder.
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
                self.resourceRegistryPreFrameCommands.append(PreFrameResourceCommand(command: .waitForHeapAliasingFences(resource: resource, waitDependency: fenceDependency), passIndex: firstUsage.renderPassRecord.passIndex, index: firstUsage.commandRange.lowerBound, order: .before))
                
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
                    frameCommandInfo.encoderIndex(for: previousUsage.renderPassRecord) == frameCommandInfo.encoderIndex(for: usage.renderPassRecord),
                    !(previousUsage.type.isRenderTarget && (usage.type == .writeOnlyRenderTarget || usage.type == .readWriteRenderTarget)) {
                    
                    assert(!usage.stages.isEmpty || usage.renderPassRecord.pass.passType != .draw)
                    assert(!previousUsage.stages.isEmpty || previousUsage.renderPassRecord.pass.passType != .draw)
                    var scope: BarrierScope = []
                    
                    #if os(macOS) || targetEnvironment(macCatalyst)
                    let isRTBarrier = previousUsage.type.isRenderTarget || usage.type.isRenderTarget
                    if isRTBarrier {
                        scope.formUnion(.renderTargets)
                    }
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
                                self.resourceCommands.append(FrameResourceCommand(command: .memoryBarrier(Resource(resource), scope: scope, afterStages: previousUsage.stages, beforeCommand: commandIndex, beforeStages: MTLRenderStages(usage.stages)), index: commandIndex))
                            }
                        }
                        
                    } else {
                        if resource.type == .texture {
                            scope.formUnion(.textures)
                        } else if resource.type == .buffer || resource.type == .argumentBuffer || resource.type == .argumentBufferArray {
                            scope.formUnion(.buffers)
                        } else {
                            assertionFailure()
                        }
                        
                        self.resourceCommands.append(FrameResourceCommand(command: .memoryBarrier(Resource(resource), scope: scope, afterStages: previousUsage.stages, beforeCommand: usage.commandRange.lowerBound, beforeStages: usage.stages), index: previousUsage.commandRange.last!))
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
                    self.resourceRegistryPreFrameCommands.append(PreFrameResourceCommand(command: .materialiseArgumentBuffer(argumentBuffer), passIndex: firstUsage.renderPassRecord.passIndex, index: firstUsage.commandRange.lowerBound, order: .before))
                }
                
                if !resource.flags.contains(.persistent), !resource.flags.contains(.historyBuffer) || resource.stateFlags.contains(.initialised) {
                    if historyBufferUseFrame {
                        self.resourceRegistry.registerInitialisedHistoryBufferForDisposal(resource: resource)
                    } else {
                        self.resourceRegistryPreFrameCommands.append(PreFrameResourceCommand(command: .disposeResource(resource), passIndex: lastUsage.renderPassRecord.passIndex, index: lastUsage.commandRange.last!, order: .after))
                    }
                }
                
            } else if !resource.flags.contains(.persistent) || resource.flags.contains(.windowHandle) {
                if let buffer = resource.buffer {
                    if !historyBufferUseFrame {
                        self.resourceRegistryPreFrameCommands.append(PreFrameResourceCommand(command: .materialiseBuffer(buffer), passIndex: firstUsage.renderPassRecord.passIndex, index: firstUsage.commandRange.lowerBound, order: .before))
                    }
                    
                    if !resource.flags.contains(.historyBuffer) || resource.stateFlags.contains(.initialised) {
                        if historyBufferUseFrame {
                            self.resourceRegistry.registerInitialisedHistoryBufferForDisposal(resource: resource)
                        } else {
                            self.resourceRegistryPreFrameCommands.append(PreFrameResourceCommand(command: .disposeResource(resource), passIndex: lastUsage.renderPassRecord.passIndex, index: lastUsage.commandRange.last!, order: .after))
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
                            self.resourceRegistryPreFrameCommands.append(PreFrameResourceCommand(command: .materialiseTextureView(texture, usage: properties), passIndex: firstUsage.renderPassRecord.passIndex, index: firstUsage.commandRange.lowerBound, order: .before))
                        } else {
                            self.resourceRegistryPreFrameCommands.append(PreFrameResourceCommand(command: .materialiseTexture(texture, usage: properties), passIndex: firstUsage.renderPassRecord.passIndex, index: firstUsage.commandRange.lowerBound, order: .before))
                        }
                    }
                    
                    if !resource.flags.contains(.historyBuffer) || resource.stateFlags.contains(.initialised) {
                        if historyBufferUseFrame {
                            self.resourceRegistry.registerInitialisedHistoryBufferForDisposal(resource: Resource(texture))
                        } else {
                            self.resourceRegistryPreFrameCommands.append(PreFrameResourceCommand(command: .disposeResource(resource), passIndex: lastUsage.renderPassRecord.passIndex, index: lastUsage.commandRange.last!, order: .after))
                        }
                        
                    }
                }
            }
            
            if resource.flags.intersection([.persistent, .historyBuffer]) != [], (!resource.stateFlags.contains(.initialised) || !resource.flags.contains(.immutableOnceInitialised)) {
                for queue in QueueRegistry.allQueues {
                    // TODO: separate out the wait index for the first read from the first write.
                    let waitIndex = resource[waitIndexFor: queue, accessType: previousWrite != nil ? .readWrite : .read]
                    self.resourceRegistryPreFrameCommands.append(PreFrameResourceCommand(command: .waitForCommandBuffer(index: waitIndex, queue: queue), passIndex: firstUsage.renderPassRecord.passIndex, index: firstUsage.commandRange.last!, order: .before))
                }
                
                if lastUsage.isWrite {
                    self.resourceRegistryPreFrameCommands.append(PreFrameResourceCommand(command: .updateCommandBufferWaitIndex(resource, accessType: .readWrite), passIndex: lastUsage.renderPassRecord.passIndex, index: lastUsage.commandRange.last!, order: .after))
                } else {
                    if let lastWrite = previousWrite {
                        self.resourceRegistryPreFrameCommands.append(PreFrameResourceCommand(command: .updateCommandBufferWaitIndex(resource, accessType: .readWrite), passIndex: lastWrite.renderPassRecord.passIndex, index: lastWrite.commandRange.last!, order: .after))
                    }
                    for read in readsSinceLastWrite {
                        self.resourceRegistryPreFrameCommands.append(PreFrameResourceCommand(command: .updateCommandBufferWaitIndex(resource, accessType: .write), passIndex: read.renderPassRecord.passIndex, index: read.commandRange.last!, order: .after))
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
                let fence = FenceHandle(label: label, queue: self.frameGraphQueue, commandBufferIndex: commandBufferSignalValue)
                
                self.compactedResourceCommands.append(CompactedResourceCommand(command: .updateFence(fence, afterStages: signalStages), index: signalIndex, order: .after))
                
                for dependentIndex in dependentRange where reductionMatrix.dependency(from: dependentIndex, on: sourceIndex) {
                    let dependency = self.commandEncoderDependencies.dependency(from: dependentIndex, on: sourceIndex)!
                    self.compactedResourceCommands.append(CompactedResourceCommand(command: .waitForFence(fence, beforeStages: MTLRenderStages(dependency.wait.stages)), index: dependency.wait.index, order: .before))
                }
            }
        }
    }
}
