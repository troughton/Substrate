//
//  MetalFrameGraph.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 23/12/17.
//

import SwiftFrameGraph
import Metal

enum WaitFence {
    case read
    case write
}

enum ResourceCommands {
    case materialiseBuffer(Buffer)
    case materialiseTexture(Texture, usage: MTLTextureUsage)
    case disposeBuffer(Buffer, readFence: Int?, writeFences: [Int]?) // readFence must be waited on before reading, writeFences must be waited on before writing.
    case disposeTexture(Texture, readFence: Int?, writeFences: [Int]?)
    
    case useResource(Resource, usage: MTLResourceUsage)
    
    case textureBarrier
    case updateFence(id: Int, afterStages: MTLRenderStages?)
    case waitForFence(id: Int, beforeStages: MTLRenderStages?)
    
    case retainFence(id: Int)
    case releaseFence(id: Int)
    case releaseMultiframeFences(resource: ResourceProtocol.Handle, resourceType: ResourceType)
    
    case waitForMultiframeFence(resource: ResourceProtocol.Handle, resourceType: ResourceType, waitFence: WaitFence, beforeStages: MTLRenderStages?)
    case storeMultiframeBuffer(buffer: Buffer, readFence: Int?, writeFences: [Int]?)
    case storeMultiframeTexture(texture: Texture, readFence: Int?, writeFences: [Int]?)
    
    var priority : Int {
        switch self {
        case .materialiseTexture, .materialiseBuffer:
            return 0
        case .retainFence:
            return 2
        case .releaseFence, .releaseMultiframeFences:
            return 3
        case .storeMultiframeBuffer, .storeMultiframeTexture:
            return 4
        case .disposeBuffer, .disposeTexture:
            return 5
        default:
            return 1
        }
    }
}

struct ResourceCommand : Comparable {
    var command : ResourceCommands
    var index : Int
    var order : PerformOrder
    
    public static func ==(lhs: ResourceCommand, rhs: ResourceCommand) -> Bool {
        return lhs.index == rhs.index && lhs.order == rhs.order &&
            lhs.command.priority == rhs.command.priority
    }
    
    public static func <(lhs: ResourceCommand, rhs: ResourceCommand) -> Bool {
        if lhs.index < rhs.index { return true }
        if lhs.index == rhs.index {
            if lhs.order < rhs.order {
                return true
            }
            if lhs.order == rhs.order {
                return lhs.command.priority < rhs.command.priority
            }
        }
        return false
    }
}

public final class MetalFrameGraph : FrameGraphBackend {
    
    let resourceRegistry : ResourceRegistry
    let stateCaches : StateCaches
    
    let commandQueue : MTLCommandQueue
    
    var currentRenderTargetDescriptor : RenderTargetDescriptor? = nil
    
    init(device: MTLDevice, resourceRegistry: ResourceRegistry, stateCaches: StateCaches) {
        self.commandQueue = device.makeCommandQueue()!
        self.resourceRegistry = resourceRegistry
        self.stateCaches = stateCaches
    }
    
    public func beginFrameResourceAccess() {
        self.resourceRegistry.frameGraphHasResourceAccess = true
    }
    
    // Generates a render target descriptor, if applicable, for each pass.
    // MetalRenderTargetDescriptor is a reference type, so we can check if two passes share a render target
    // (and therefore MTLRenderCommandEncoder)
    func generateRenderTargetDescriptors(passes: [RenderPassRecord], resourceUsages: ResourceUsages) -> [MetalRenderTargetDescriptor?] {
        var descriptors = [MetalRenderTargetDescriptor?](repeating: nil, count: passes.count)
        
        var currentDescriptor : MetalRenderTargetDescriptor? = nil
        for (i, passRecord) in passes.enumerated() {
            if let renderPass = passRecord.pass as? DrawRenderPass {
                if let descriptor = currentDescriptor {
                    currentDescriptor = descriptor.descriptorMergedWithPass(renderPass, resourceUsages: resourceUsages)
                } else {
                    currentDescriptor = MetalRenderTargetDescriptor(renderPass: renderPass)
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
    
    func sharesCommandEncoders(_ passA: RenderPassRecord, _ passB: RenderPassRecord, passes: [RenderPassRecord], renderTargetDescriptors: [MetalRenderTargetDescriptor?]) -> Bool {
        if passA.passIndex == passB.passIndex {
            return true
        }
        if passA.pass.passType == .draw, renderTargetDescriptors[passA.passIndex] === renderTargetDescriptors[passB.passIndex] {
            return true
        }
        
        let referenceType = passB.pass.passType
        for i in passA.passIndex..<passB.passIndex {
            if passes[i].pass.passType != referenceType {
                return false
            }
        }
        
        return true
    }
    
    func generateCommandEncoderIndices(passes: [RenderPassRecord], renderTargetDescriptors: [MetalRenderTargetDescriptor?]) -> ([Int], count: Int) {
        var encoderIndex = 0
        var passEncoderIndices = [Int](repeating: 0, count: passes.count)
        
        for (i, pass) in passes.enumerated().dropFirst() {
            let previousPass = passes[i - 1]
            assert(pass.passIndex != previousPass.passIndex)
        
            if previousPass.pass.passType != pass.pass.passType || renderTargetDescriptors[previousPass.passIndex] !== renderTargetDescriptors[pass.passIndex] {
                encoderIndex += 1
            }
            
            passEncoderIndices[i] = encoderIndex
        }
        
        return (passEncoderIndices, encoderIndex + 1)
    }
    
    // For fence tracking - support at most one dependency between each set of two render passes. Make the fence update as early as possible, and make the fence wait as late as possible.
    //
    // No fences are needed between compute command encoders, and CCEs automatically manage hazards in between dispatchThreadgroups calls.
    //
    // Fences are needed between different types of command encoders.
    
    struct Dependency {
        /// dependentUsage is the usage within the dependent pass.
        var dependentUsage : ResourceUsage
        /// passUsage is the usage within the current pass (the pass that's depended upon).
        var passUsage : ResourceUsage
        
        init(dependentUsage: ResourceUsage, passUsage: ResourceUsage) {
            self.dependentUsage = dependentUsage
            self.passUsage = passUsage
        }
    }
    
    var resourceCommands = [ResourceCommand]()
    var renderTargetTextureUsages = [Texture : MTLTextureUsage]()
    var commandEncoderDependencies = [[Dependency]]()
    
    func generateResourceCommands(passes: [RenderPassRecord], resourceUsages: ResourceUsages, renderTargetDescriptors: [MetalRenderTargetDescriptor?]) {
        let (passCommandEncoderIndices, commandEncoderCount) = self.generateCommandEncoderIndices(passes: passes, renderTargetDescriptors: renderTargetDescriptors)
        
        if self.commandEncoderDependencies.count < commandEncoderCount {
            commandEncoderDependencies.append(contentsOf: repeatElement([Dependency](), count: commandEncoderCount - self.commandEncoderDependencies.count))
        }
        
        var fenceId = 0
        
        resourceLoop: for resource in resourceUsages.allResources {
            let resourceType = resource.type
            
            let usages = resource.usages
            if usages.isEmpty { continue }
            
            do {
                // Track resource residency.
                
                var commandIndex = 0
                var previousPass : RenderPassRecord? = nil
                var resourceUsage : MTLResourceUsage = []
                
                for usage in usages where usage.renderPass.isActive && usage.inArgumentBuffer && usage.stages != .cpuBeforeRender {
                    
                    defer { previousPass = usage.renderPass }
                    
                    if let previousPassUnwrapped = previousPass, passCommandEncoderIndices[previousPassUnwrapped.passIndex] != passCommandEncoderIndices[usage.renderPass.passIndex] {
                        self.resourceCommands.append(ResourceCommand(command: .useResource(resource, usage: resourceUsage), index: commandIndex, order: .before))
                        previousPass = nil
                    }
                    
                    if previousPass == nil {
                        resourceUsage = []
                        commandIndex = usage.commandRange.lowerBound
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
                }
                
                if previousPass != nil {
                    self.resourceCommands.append(ResourceCommand(command: .useResource(resource, usage: resourceUsage), index: commandIndex, order: .before))
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
            } while !previousUsage.renderPass.isActive || previousUsage.type == .unusedArgumentBuffer

            let firstUsage = previousUsage
            
            var readsSinceLastWrite = firstUsage.isRead ? [firstUsage] : []
            var previousWrite = firstUsage.isWrite ? firstUsage : nil
            
            // We're retrieving a resource from the resource registry that may have fences attached associated with the previous frame.
            // We need to wait on the read fence or write fence until the first write in this frame.
            if firstUsage.isWrite {
                self.resourceCommands.append(ResourceCommand(command: .waitForMultiframeFence(resource: resource.handle, resourceType: resourceType, waitFence: .write, beforeStages: MTLRenderStages(firstUsage.stages.first)), index: firstUsage.commandRange.lowerBound, order: .before))
                
            } else {
                self.resourceCommands.append(ResourceCommand(command: .waitForMultiframeFence(resource: resource.handle, resourceType: resourceType, waitFence: .read, beforeStages: MTLRenderStages(firstUsage.stages.first)), index: firstUsage.commandRange.lowerBound, order: .before))
            }
            
            while let usage = usageIterator.next()  {
                if !usage.renderPass.isActive || usage.stages == .cpuBeforeRender {
                    continue
                }
                
                if usage.isWrite {
                    assert(!resource.flags.contains(.immutableOnceInitialised) || !resource.stateFlags.contains(.initialised), "A resource with the flag .immutableOnceInitialised is being written to in \(usage) when it has already been initialised.")
                    
                    for previousRead in readsSinceLastWrite where passCommandEncoderIndices[previousRead.renderPass.passIndex] != passCommandEncoderIndices[usage.renderPass.passIndex] {
                        let dependency = Dependency(dependentUsage: usage, passUsage: previousRead)
                        commandEncoderDependencies[passCommandEncoderIndices[previousRead.renderPass.passIndex]].append(dependency)
                    }
                    
                    if let previousWrite = previousWrite, passCommandEncoderIndices[previousWrite.renderPass.passIndex] != passCommandEncoderIndices[usage.renderPass.passIndex] {
                        let dependency = Dependency(dependentUsage: usage, passUsage: previousWrite)
                        commandEncoderDependencies[passCommandEncoderIndices[previousWrite.renderPass.passIndex]].append(dependency)
                    }
                    
                } else if usage.isRead, let previousWrite = previousWrite {
                    // usage.isRead
                    
                    if usage.renderPass.pass is DrawRenderPass, usage.type != .readWriteRenderTarget, renderTargetDescriptors[previousWrite.renderPass.passIndex] === renderTargetDescriptors[usage.renderPass.passIndex] {
                        if previousWrite.type.isRenderTarget && previousWrite.type != .unusedRenderTarget {
                            // Insert a texture barrier.
                            self.resourceCommands.append(ResourceCommand(command: .textureBarrier, index: usage.commandRange.lowerBound, order: .before))
                        }
                    } else if passCommandEncoderIndices[previousWrite.renderPass.passIndex] != passCommandEncoderIndices[usage.renderPass.passIndex] {
                        let dependency = Dependency(dependentUsage: usage, passUsage: previousWrite)
                        commandEncoderDependencies[passCommandEncoderIndices[previousWrite.renderPass.passIndex]].append(dependency)
                    }
                }
                
                if previousWrite == nil, passCommandEncoderIndices[usage.renderPass.passIndex] != passCommandEncoderIndices[previousUsage.renderPass.passIndex] {
                    // No previous writes in the frame, so we need to wait on possible fences from the previous frame.
                    // We only need to do this once per command encoder.
                    let waitFence = usage.isWrite ? WaitFence.write : WaitFence.read
                    self.resourceCommands.append(ResourceCommand(command: .waitForMultiframeFence(resource: resource.handle, resourceType: resourceType, waitFence: waitFence, beforeStages: MTLRenderStages(usage.stages.first)), index: usage.commandRange.lowerBound, order: .before))
                }
                
                if usage.isWrite {
                    readsSinceLastWrite.removeAll(keepingCapacity: true)
                    previousWrite = usage
                }
                if usage.isRead {
                    readsSinceLastWrite.append(usage)
                }
                
                previousUsage = usage
            }
            
            let lastUsage = previousUsage
            
            self.resourceCommands.append(ResourceCommand(command: .releaseMultiframeFences(resource: resource.handle, resourceType: resourceType), index: lastUsage.commandRange.upperBound - 1, order: .after))
            
            var storeWriteFences : [Int]? = nil
            var storeReadFence : Int? = nil
            
            if resourceRegistry.needsWaitFencesOnFrameCompletion(resource: resource) {
                // Reads need to wait for all previous writes to complete.
                // Writes need to wait for all previous reads and writes to complete.
                
                if let previousWrite = previousWrite {
                    let updateFenceId = fenceId
                    storeReadFence = updateFenceId
                    storeWriteFences = [updateFenceId]
                    fenceId += 1
                    
                    self.resourceCommands.append(ResourceCommand(command: .updateFence(id: updateFenceId, afterStages: MTLRenderStages(previousWrite.stages.last)), index: previousWrite.commandRange.upperBound - 1, order: .after))
                }
                
                if !resource.flags.contains(.immutableOnceInitialised) {
                    var writeFences = storeWriteFences ?? []
                    for read in readsSinceLastWrite {
                        let updateFenceId = fenceId
                        writeFences.append(updateFenceId)
                        fenceId += 1
                        
                        self.resourceCommands.append(ResourceCommand(command: .updateFence(id: updateFenceId, afterStages: MTLRenderStages(read.stages.last)), index: read.commandRange.upperBound - 1, order: .after))
                    }
                    storeWriteFences = writeFences
                }
            }
            
            let historyBufferUseFrame = resource.flags.contains(.historyBuffer) && resource.stateFlags.contains(.initialised)
            
            // Insert commands to materialise and dispose of the resource.
            if !resource.flags.contains(.persistent) || resource.flags.contains(.windowHandle) {
                if let buffer = resource.buffer {
                    if !historyBufferUseFrame {
                        self.resourceCommands.append(ResourceCommand(command: .materialiseBuffer(buffer), index: firstUsage.commandRange.lowerBound, order: .before))
                    }
                    
                    if resource.flags.contains(.historyBuffer) && !resource.stateFlags.contains(.initialised) {
                        self.resourceCommands.append(ResourceCommand(command: .storeMultiframeBuffer(buffer: buffer, readFence: storeReadFence, writeFences: storeWriteFences), index: lastUsage.commandRange.upperBound - 1, order: .after))
                    } else {
                        self.resourceCommands.append(ResourceCommand(command: .disposeBuffer(buffer, readFence: storeReadFence, writeFences: storeWriteFences), index: lastUsage.commandRange.upperBound - 1, order: .after))
                    }
    
                } else {
                    let texture = resource.texture!
                    var textureUsage : MTLTextureUsage = []
                    for usage in usages {
                        switch usage.type {
                        case .read:
                            textureUsage.formUnion(.shaderRead)
                        case .write:
                            textureUsage.formUnion(.shaderWrite)
                        case .readWriteRenderTarget, .writeOnlyRenderTarget:
                            textureUsage.formUnion(.renderTarget)
                        default:
                            break
                        }
                    }
                    if textureUsage.contains(.renderTarget) {
                        self.renderTargetTextureUsages[texture] = textureUsage
                    }
                    
                    if !historyBufferUseFrame {
                        self.resourceCommands.append(ResourceCommand(command: .materialiseTexture(texture, usage: textureUsage), index: firstUsage.commandRange.lowerBound, order: .before))
                    }
                    
                    if resource.flags.contains(.historyBuffer) && !resource.stateFlags.contains(.initialised) {
                        self.resourceCommands.append(ResourceCommand(command: .storeMultiframeTexture(texture: texture, readFence: storeReadFence, writeFences: storeWriteFences), index: lastUsage.commandRange.upperBound - 1, order: .after))
                    } else {
                        self.resourceCommands.append(ResourceCommand(command: .disposeTexture(texture, readFence: storeReadFence, writeFences: storeWriteFences), index: lastUsage.commandRange.upperBound - 1, order: .after))
                    }
                }
            } else if storeReadFence != nil || storeWriteFences != nil { // If we did anything with the resource..
                if let buffer = resource.buffer {
                    self.resourceCommands.append(ResourceCommand(command: .storeMultiframeBuffer(buffer: buffer, readFence: storeReadFence, writeFences: storeWriteFences), index: lastUsage.commandRange.upperBound - 1, order: .after))
                } else {
                    let texture = resource.texture!
                    self.resourceCommands.append(ResourceCommand(command: .storeMultiframeTexture(texture: texture, readFence: storeReadFence, writeFences: storeWriteFences), index: lastUsage.commandRange.upperBound - 1, order: .after))
                }
            }
        }
        
        do {
            // Process the dependencies, joining duplicates.
            // TODO: Remove transitive dependencies.
            for commandEncoderIndex in 0..<commandEncoderCount { // passIndex always points to the producing pass.
                var dependencyIndex = 0
                while dependencyIndex < commandEncoderDependencies[commandEncoderIndex].count {
                    let dependency = commandEncoderDependencies[commandEncoderIndex][dependencyIndex]
                    
                    var passCommandIndex = dependency.passUsage.commandRange.upperBound
                    var passStages = dependency.passUsage.stages
                    var dependentCommandIndex = dependency.dependentUsage.commandRange.lowerBound
                    var dependentStages = dependency.dependentUsage.stages
                    
                    var otherDependencyIndex = dependencyIndex + 1
                    while otherDependencyIndex < commandEncoderDependencies[commandEncoderIndex].count {
                        let otherDependency = commandEncoderDependencies[commandEncoderIndex][otherDependencyIndex]
                        if passCommandEncoderIndices[dependency.dependentUsage.renderPass.passIndex] == passCommandEncoderIndices[otherDependency.dependentUsage.renderPass.passIndex] {
                            
                            // Update as late as necessary
                            if passCommandIndex <= otherDependency.passUsage.commandRange.upperBound {
                                passStages.formUnion(otherDependency.passUsage.stages)
                                passCommandIndex = otherDependency.passUsage.commandRange.upperBound
                            }
                            
                            // Wait as early as necessary
                            if dependentCommandIndex >= otherDependency.dependentUsage.commandRange.lowerBound {
                                dependentStages.formUnion(otherDependency.dependentUsage.stages)
                                dependentCommandIndex = otherDependency.dependentUsage.commandRange.lowerBound
                            }
                            
                            commandEncoderDependencies[commandEncoderIndex].remove(at: otherDependencyIndex)
                        } else {
                            otherDependencyIndex += 1
                        }
                    }
                    
                    // This may introduce duplicate updates, so we merge the updates in checkResourceCommands.
                    // Doing it this way allows us to keep a one to one mapping here.
                    let sourceEncoder = passCommandEncoderIndices[dependency.passUsage.renderPass.passIndex]
                    let dependentEncoder = passCommandEncoderIndices[dependency.dependentUsage.renderPass.passIndex]
                    if sourceEncoder != dependentEncoder {
                        self.resourceCommands.append(ResourceCommand(command: .updateFence(id: fenceId, afterStages: MTLRenderStages(passStages.last)), index: passCommandIndex - 1, order: .after)) // - 1 because of upperBound
                        self.resourceCommands.append(ResourceCommand(command: .retainFence(id: fenceId), index: passCommandIndex - 1, order: .after))
                        
                        self.resourceCommands.append(ResourceCommand(command: .waitForFence(id: fenceId, beforeStages: MTLRenderStages(dependentStages.first)), index: dependentCommandIndex, order: .before))
                        self.resourceCommands.append(ResourceCommand(command: .releaseFence(id: fenceId), index: dependentCommandIndex, order: .before))
                        fenceId += 1
                    }
                    
                    dependencyIndex += 1
                }
            }
        }
        
        self.resourceCommands.sort()
    }
    
    var resourceCommandIndex = 0
    
    func checkResourceCommands(phase: PerformOrder, commandIndex: Int, encoder: MTLCommandEncoder) {
        var hasPerformedTextureBarrier = false
        var updatedFenceAndStage : (Int, MTLRenderStages?)? = nil
        while resourceCommandIndex < resourceCommands.count, commandIndex == resourceCommands[resourceCommandIndex].index, phase == resourceCommands[resourceCommandIndex].order {
            defer { resourceCommandIndex += 1 }
            
            switch resourceCommands[resourceCommandIndex].command {
            case .materialiseBuffer(let buffer):
                self.resourceRegistry.allocateBufferIfNeeded(buffer)
                buffer.applyDeferredSliceActions()
                
            case .materialiseTexture(let texture, let usage):
                self.resourceRegistry.allocateTextureIfNeeded(texture, usage: usage)
                
            case .disposeBuffer(let buffer, let readFence, let writeFences):
                var mtlReadFence : MTLFence? = nil
                var mtlWriteFences : [MTLFence]? = nil
                
                if resourceRegistry.needsWaitFencesOnDispose(size: buffer.descriptor.length, storageMode: buffer.descriptor.storageMode, flags: buffer.flags) {
                    mtlReadFence = self.resourceRegistry.fenceWithOptionalId(readFence)
                    mtlWriteFences = writeFences?.map { self.resourceRegistry.fenceWithId($0) }
                    
                    mtlReadFence.map { self.resourceRegistry.retainFence($0) } // Retain the fences before disposal since they'll last across multiple frames.
                    mtlWriteFences?.forEach { self.resourceRegistry.retainFence($0) }
                }
                
                self.resourceRegistry.disposeBuffer(buffer, readFence: mtlReadFence, writeFences: mtlWriteFences)
                
                if buffer.flags.contains(.historyBuffer) {
                    assert(buffer.stateFlags.contains(.initialised))
                    buffer.dispose() // Automatically dispose used history buffers.
                }
                
            case .disposeTexture(let texture, let readFence, let writeFences):
                var mtlReadFence : MTLFence? = nil
                var mtlWriteFences : [MTLFence]? = nil
                
                if resourceRegistry.needsWaitFencesOnDispose(size: Int.max, storageMode: texture.descriptor.storageMode, flags: texture.flags) {
                    mtlReadFence = self.resourceRegistry.fenceWithOptionalId(readFence)
                    mtlWriteFences = writeFences?.map { self.resourceRegistry.fenceWithId($0) }
                    
                    mtlReadFence.map { self.resourceRegistry.retainFence($0) } // Retain the fences before disposal since they'll last across multiple frames.
                    mtlWriteFences?.forEach { self.resourceRegistry.retainFence($0) }
                }
                
                self.resourceRegistry.disposeTexture(texture, readFence: mtlReadFence, writeFences: mtlWriteFences)
                
                if texture.flags.contains(.historyBuffer) {
                    assert(texture.stateFlags.contains(.initialised))
                    texture.dispose() // Automatically dispose used history buffers.
                }
                
            case .textureBarrier:
                if !hasPerformedTextureBarrier {
                    (encoder as! MTLRenderCommandEncoder).textureBarrier()
                    hasPerformedTextureBarrier = true
                }
                
            case .retainFence(let id):
                resourceRegistry.retainFenceWithId(id)
                
            case .releaseFence(let id):
                resourceRegistry.releaseFenceWithId(id, addToPoolImmediately: false)
                
            case .updateFence(let id, let afterStages):
                if let (updatedFence, stages) = updatedFenceAndStage, stages == afterStages {
                    resourceRegistry.remapFenceId(id, toExistingFenceWithId: updatedFence) // We can combine together multiple fences that update at the same time.
                } else {
                    let fence = self.resourceRegistry.fenceWithId(id) // Store happens after update, so isMultiframe can be safely passed as false here since it will be overriden later if necessary.
                    encoder.updateFence(fence, afterStages: afterStages)
                    updatedFenceAndStage = (id, afterStages)
                }
                
            case .waitForFence(let id, let beforeStages):
                let fence = self.resourceRegistry.fenceWithId(id)
                encoder.waitForFence(fence, beforeStages: beforeStages)
                
            case .waitForMultiframeFence(let resource, let resourceType, let waitFence, let beforeStages):
                if case .buffer = resourceType {
                    let bufferRef = self.resourceRegistry[buffer: resource]!
                    if case .write = waitFence, let fences = bufferRef.writeWaitFences {
                        for fence in fences {
                            encoder.waitForFence(fence, beforeStages: beforeStages)
                        }
                    } else if let fence = bufferRef.readWaitFence {
                        encoder.waitForFence(fence, beforeStages: beforeStages)
                    }
                } else {
                    let textureRef = self.resourceRegistry[textureReference: resource]!
                    if case .write = waitFence, let fences = textureRef.writeWaitFences {
                        for fence in fences {
                            encoder.waitForFence(fence, beforeStages: beforeStages)
                        }
                    } else if let fence = textureRef.readWaitFence {
                        encoder.waitForFence(fence, beforeStages: beforeStages)
                    }
                }
                
            case .releaseMultiframeFences(let resource, let resourceType):
                
                if case .buffer = resourceType {
                    let bufferRef = self.resourceRegistry[buffer: resource]!
                    bufferRef.writeWaitFences?.forEach {
                        resourceRegistry.releaseFence($0, addToPoolImmediately: true)
                    }
                    bufferRef.writeWaitFences = nil
                    bufferRef.readWaitFence.map { resourceRegistry.releaseFence($0, addToPoolImmediately: true) }
                    bufferRef.readWaitFence = nil
                } else {
                    let textureRef = self.resourceRegistry[textureReference: resource]!
                    textureRef.writeWaitFences?.forEach {
                        resourceRegistry.releaseFence($0, addToPoolImmediately: true)
                    }
                    textureRef.writeWaitFences = nil
                    textureRef.readWaitFence.map { resourceRegistry.releaseFence($0, addToPoolImmediately: true) }
                    textureRef.readWaitFence = nil
                }
                
                
            case .storeMultiframeTexture(let texture, let readFence, let writeFences):
                let textureRef = self.resourceRegistry[textureReference: texture]!
                if let readFence = readFence {
                    textureRef.readWaitFence = self.resourceRegistry.fenceWithId(readFence)
                    self.resourceRegistry.retainFence(textureRef.readWaitFence!)
                }
                if let writeFences = writeFences {
                    textureRef.writeWaitFences = writeFences.map { self.resourceRegistry.fenceWithId($0) }
                    textureRef.writeWaitFences!.forEach { self.resourceRegistry.retainFence($0) }
                }
                
                texture.markAsInitialised()
                
            case .storeMultiframeBuffer(let buffer, let readFence, let writeFences):
                let bufferRef = self.resourceRegistry[buffer]!
                if let readFence = readFence {
                    bufferRef.readWaitFence = self.resourceRegistry.fenceWithId(readFence)
                    self.resourceRegistry.retainFence(bufferRef.readWaitFence!)
                }
                if let writeFences = writeFences {
                    bufferRef.writeWaitFences = writeFences.map { self.resourceRegistry.fenceWithId($0) }
                    bufferRef.writeWaitFences!.forEach { self.resourceRegistry.retainFence($0) }
                }
                
                buffer.markAsInitialised()
                
            case .useResource(let resource, let usage):
                let mtlResource : MTLResource
                
                if let texture = resource.texture {
                    mtlResource = self.resourceRegistry[texture]!
                } else if let buffer = resource.buffer {
                    mtlResource = self.resourceRegistry[buffer]!.buffer
                } else {
                    preconditionFailure()
                }
                
                if let encoder = encoder as? MTLRenderCommandEncoder {
                    encoder.useResource(mtlResource, usage: usage)
                } else if let encoder = encoder as? MTLComputeCommandEncoder {
                    encoder.useResource(mtlResource, usage: usage)
                }
            }
        }
    }
    
    public func executeFrameGraph(passes: [RenderPassRecord], resourceUsages: ResourceUsages, commands: [FrameGraphCommand], completion: @escaping () -> Void) {
        defer { self.resourceRegistry.cycleFrames() }
        
        let renderTargetDescriptors = self.generateRenderTargetDescriptors(passes: passes, resourceUsages: resourceUsages)
        self.generateResourceCommands(passes: passes, resourceUsages: resourceUsages, renderTargetDescriptors: renderTargetDescriptors)
        
        let commandBuffer = self.commandQueue.makeCommandBuffer()!
        let encoderManager = EncoderManager(commandBuffer: commandBuffer, resourceRegistry: self.resourceRegistry)
        
        self.resourceCommandIndex = 0
        
        let (passCommandEncoders, commandEncoderCount) = generateCommandEncoderIndices(passes: passes, renderTargetDescriptors: renderTargetDescriptors)
        var commandEncoderNames = [String](repeating: "", count: commandEncoderCount)
        
        var startIndex = 0
        for i in 0..<commandEncoderCount {
            let endIndex = passCommandEncoders[startIndex...].firstIndex(where: { $0 != i }) ?? passCommandEncoders.endIndex
            
            if endIndex - startIndex <= 3 {
                let applicablePasses = passes[startIndex..<endIndex].lazy.map { $0.pass.name }.joined(separator: ", ")
                commandEncoderNames[i] = applicablePasses
            } else {
                commandEncoderNames[i] = "[\(passes[startIndex].pass.name)...\(passes[endIndex - 1].pass.name)] (\(endIndex - startIndex) passes)"
            }
            startIndex = endIndex
        }
        
        for (i, passRecord) in passes.enumerated() {
            switch passRecord.pass.passType {
            case .blit:
                let commandEncoder = encoderManager.blitCommandEncoder()
                if commandEncoder.label == nil {
                    commandEncoder.label = commandEncoderNames[passCommandEncoders[i]]
                }
                
                commandEncoder.pushDebugGroup(passRecord.pass.name)
                
                commandEncoder.executeCommands(commands[passRecord.commandRange!], resourceCheck: checkResourceCommands, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
                
                commandEncoder.popDebugGroup()
                
            case .draw:
                let commandEncoder = encoderManager.renderCommandEncoder(descriptor: renderTargetDescriptors[i]!, textureUsages: renderTargetTextureUsages)
                if commandEncoder.label == nil {
                    commandEncoder.label = commandEncoderNames[passCommandEncoders[i]]
                }
                
                commandEncoder.pushDebugGroup(passRecord.pass.name)
                
                commandEncoder.executePass(commands: commands[passRecord.commandRange!], resourceCheck: checkResourceCommands, renderTarget: renderTargetDescriptors[i]!.descriptor, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
                
                commandEncoder.popDebugGroup()                
            case .compute:
                let commandEncoder = encoderManager.computeCommandEncoder()
                if commandEncoder.label == nil {
                    commandEncoder.label = commandEncoderNames[passCommandEncoders[i]]
                }
                
                commandEncoder.pushDebugGroup(passRecord.pass.name)
                
                commandEncoder.executePass(commands: commands[passRecord.commandRange!], resourceCheck: checkResourceCommands, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
                
                commandEncoder.popDebugGroup()
                
            case .cpu:
                break
            }
        }
        
        assert(self.resourceCommandIndex == self.resourceCommands.count)

        encoderManager.endEncoding()
        
        for drawable in self.resourceRegistry.frameDrawables {
            commandBuffer.present(drawable)
        }
        
        commandBuffer.addCompletedHandler { (commandBuffer) in
            completion()
        }
        
        commandBuffer.commit()
        
        self.resourceRegistry.frameGraphHasResourceAccess = false
        
        self.resourceCommands.removeAll(keepingCapacity: true)
        self.renderTargetTextureUsages.removeAll(keepingCapacity: true)
        for i in 0..<self.commandEncoderDependencies.count {
            self.commandEncoderDependencies[i].removeAll(keepingCapacity: true)
        }
    }
}


extension MTLCommandEncoder {
    public func waitForFence(_ fence: MTLFence, beforeStages: MTLRenderStages?) {
        if let encoder = self as? MTLRenderCommandEncoder {
            encoder.wait(for: fence, before: beforeStages!)
        } else if let encoder = self as? MTLComputeCommandEncoder {
            encoder.waitForFence(fence)
        } else {
            (self as! MTLBlitCommandEncoder).waitForFence(fence)
        }
    }
    
    public func updateFence(_ fence: MTLFence, afterStages: MTLRenderStages?) {
        if let encoder = self as? MTLRenderCommandEncoder {
            encoder.update(fence, after: afterStages!)
        } else if let encoder = self as? MTLComputeCommandEncoder {
            encoder.updateFence(fence)
        } else {
            (self as! MTLBlitCommandEncoder).updateFence(fence)
        }
    }
}
