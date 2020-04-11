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

enum MetalCompactedFrameResourceCommands {
    // These commands need to be executed during render pass execution and do not modify the MetalResourceRegistry.
    case useResources(UnsafeMutableBufferPointer<MTLResource>, usage: MTLResourceUsage, stages: MTLRenderStages)
    case resourceMemoryBarrier(resources: UnsafeMutableBufferPointer<MTLResource>, afterStages: MTLRenderStages, beforeStages: MTLRenderStages)
    case scopedMemoryBarrier(scope: MTLBarrierScope, afterStages: MTLRenderStages, beforeStages: MTLRenderStages)
    case updateFence(MetalFenceHandle, afterStages: MTLRenderStages)
    case waitForFence(MetalFenceHandle, beforeStages: MTLRenderStages)
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
    let commandGenerator: ResourceCommandGenerator<MetalBackend>
    var compactedResourceCommands = [MetalCompactedResourceCommand]()
    
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
        
        self.commandGenerator = ResourceCommandGenerator()
        
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
    
    var resourceMap : FrameResourceMap<MetalBackend> {
        return FrameResourceMap<MetalBackend>(persistentRegistry: self.backend.resourceRegistry, transientRegistry: self.resourceRegistry)
    }
    
    static var resourceCommandArrayTag: TaggedHeap.Tag {
        return UInt64(bitPattern: Int64("FrameGraph Compacted Resource Commands".hashValue))
    }
    
    func generateFenceCommands(frameCommandInfo: FrameCommandInfo<MetalBackend>, commandGenerator: ResourceCommandGenerator<MetalBackend>) {
        // MARK: - Generate the fences
        
        let dependencies = commandGenerator.commandEncoderDependencies
            
        let commandEncoderCount = frameCommandInfo.commandEncoders.count
        let reductionMatrix = dependencies.transitiveReduction(hasDependency: { $0 != nil })
        
        for sourceIndex in (0..<commandEncoderCount) { // sourceIndex always points to the producing pass.
            let dependentRange = min(sourceIndex + 1, commandEncoderCount)..<commandEncoderCount
            
            var signalStages : MTLRenderStages = []
            var signalIndex = -1
            for dependentIndex in dependentRange where reductionMatrix.dependency(from: dependentIndex, on: sourceIndex) {
                let dependency = dependencies.dependency(from: dependentIndex, on: sourceIndex)!
                signalStages.formUnion(MTLRenderStages(dependency.signal.stages))
                signalIndex = max(signalIndex, dependency.signal.index)
            }
            
            if signalIndex < 0 { continue }
            
            let label = "Encoder \(sourceIndex) Fence"
            let commandBufferSignalValue = frameCommandInfo.signalValue(commandBufferIndex: frameCommandInfo.commandEncoders[sourceIndex].commandBufferIndex)
            let fence = MetalFenceHandle(label: label, queue: self.frameGraphQueue, commandBufferIndex: commandBufferSignalValue)
            
            self.compactedResourceCommands.append(MetalCompactedResourceCommand(command: .updateFence(fence, afterStages: signalStages), index: signalIndex, order: .after))
            
            for dependentIndex in dependentRange where reductionMatrix.dependency(from: dependentIndex, on: sourceIndex) {
                let dependency = dependencies.dependency(from: dependentIndex, on: sourceIndex)!
                self.compactedResourceCommands.append(MetalCompactedResourceCommand(command: .waitForFence(fence, beforeStages: MTLRenderStages(dependency.wait.stages)), index: dependency.wait.index, order: .before))
            }
        }
    }
    
    func generateCompactedResourceCommands(commandInfo: FrameCommandInfo<MetalBackend>, commandGenerator: ResourceCommandGenerator<MetalBackend>) {
        guard !commandGenerator.commands.isEmpty else { return }
        
        self.generateFenceCommands(frameCommandInfo: commandInfo, commandGenerator: commandGenerator)
        
        
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
            #if os(macOS) || targetEnvironment(macCatalyst)
            let isRTBarrier = barrierScope.contains(.renderTargets)
            #else
            let isRTBarrier = false
            #endif
            if barrierResources.count <= 8, !isRTBarrier {
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
                return unsafeBitCast(self.resourceMap[texture]._texture, to: Unmanaged<MTLResource>.self)
            } else if let argumentBuffer = resource.argumentBuffer {
                return unsafeBitCast(self.resourceMap[argumentBuffer]._buffer, to: Unmanaged<MTLResource>.self)
            }
            fatalError()
        }
        
        for command in commandGenerator.commands {
            if command.index > barrierLastIndex {
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
        
                var computedUsageType: MTLResourceUsage = []
                if resource.type == .texture, usage == .read {
                    computedUsageType.formUnion(.sample)
                }
                if usage.isRead {
                    computedUsageType.formUnion(.read)
                }
                if usage.isWrite {
                    computedUsageType.formUnion(.write)
                }
                
                if !allowReordering {
                    let memory = allocator.allocate(capacity: 1) as UnsafeMutablePointer<Unmanaged<MTLResource>>
                    memory.initialize(to: mtlResource)
                    let bufferPointer = UnsafeMutableBufferPointer<MTLResource>(start: UnsafeMutableRawPointer(memory).assumingMemoryBound(to: MTLResource.self), count: 1)
                    self.compactedResourceCommands.append(.init(command: .useResources(bufferPointer, usage: computedUsageType, stages: MTLRenderStages(stages)), index: command.index, order: .before))
                } else {
                    let key = MetalResidentResource(resource: mtlResource, stages: MTLRenderStages(stages), usage: computedUsageType)
                    let (inserted, _) = encoderResidentResources.insert(key)
                    if inserted {
                        encoderUseResources[UseResourceKey(stages: MTLRenderStages(stages), usage: computedUsageType), default: []].append(mtlResource)
                    }
                    encoderUseResourceCommandIndex = min(command.index, encoderUseResourceCommandIndex)
                }
                
            case .memoryBarrier(let resource, let scope, let afterStages, let beforeCommand, let beforeStages):
                if barrierResources.count < 8 {
                    barrierResources.append(getResource(resource))
                }
                barrierScope.formUnion(MTLBarrierScope(scope))
                barrierAfterStages.formUnion(MTLRenderStages(afterStages))
                barrierBeforeStages.formUnion(MTLRenderStages(beforeStages))
                barrierLastIndex = min(beforeCommand, barrierLastIndex)
            }
        }
        
        if barrierLastIndex < .max {
            addBarrier()
        }
        useResources()
        
        self.compactedResourceCommands.sort()
    }
    
    public func executeFrameGraph(passes: [RenderPassRecord], dependencyTable: DependencyTable<SwiftFrameGraph.DependencyType>, resourceUsages: ResourceUsages, completion: @escaping () -> Void) {
        self.resourceRegistry.prepareFrame()
        
        defer {
            TaggedHeap.free(tag: Self.resourceCommandArrayTag)
            
            self.resourceRegistry.cycleFrames()

            self.commandGenerator.reset()
            self.compactedResourceCommands.removeAll(keepingCapacity: true)
            
            assert(self.backend.activeContext === self)
            self.backend.activeContext = nil
        }
        
        if passes.isEmpty {
            completion()
            self.accessSemaphore.signal()
            return
        }
        
        var frameCommandInfo = FrameCommandInfo<MetalBackend>(passes: passes, resourceUsages: resourceUsages, initialCommandBufferSignalValue: self.queueCommandBufferIndex + 1)
        self.commandGenerator.generateCommands(passes: passes, resourceUsages: resourceUsages, transientRegistry: self.resourceRegistry, frameCommandInfo: &frameCommandInfo)
        self.commandGenerator.executePreFrameCommands(queue: self.frameGraphQueue, resourceMap: self.resourceMap, frameCommandInfo: &frameCommandInfo)
        self.generateCompactedResourceCommands(commandInfo: frameCommandInfo, commandGenerator: self.commandGenerator)
        
        func executePass(_ passRecord: RenderPassRecord, i: Int, encoderInfo: FrameCommandInfo<MetalBackend>.CommandEncoderInfo, encoderManager: MetalEncoderManager) {
            switch passRecord.pass.passType {
            case .blit:
                let commandEncoder = encoderManager.blitCommandEncoder()
                if commandEncoder.encoder.label == nil {
                    commandEncoder.encoder.label = encoderInfo.name
                }
                
                commandEncoder.executePass(passRecord, resourceCommands: compactedResourceCommands, resourceMap: self.resourceMap, stateCaches: backend.stateCaches)
                
            case .draw:
                guard let commandEncoder = encoderManager.renderCommandEncoder(descriptor: encoderInfo.renderTargetDescriptor!, textureUsages: self.commandGenerator.renderTargetTextureProperties, resourceMap: self.resourceMap, stateCaches: backend.stateCaches) else {
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
