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
    
    // These commands mutate the ResourceRegistry and should be executed before render pass execution:
    case materialiseBuffer(Buffer)
    case materialiseTexture(Texture, usage: TextureUsageProperties)
    case materialiseTextureView(Texture, usage: TextureUsageProperties)
    case disposeResource(Resource.Handle)
    
    case retainFence(MTLFenceType)
    case releaseFence(MTLFenceType)
    case releaseMultiframeFences(resource: ResourceProtocol.Handle)
    case setDisposalFences(Resource, readWaitFence: MTLFenceType?, writeWaitFences: [MTLFenceType]?)
    
    // These commands need to be executed during render pass execution and do not modify the ResourceRegistry.
    
    case useResource(Resource, usage: MTLResourceUsage)
    case textureBarrier
    case memoryBarrier(Resource, afterStages: MTLRenderStages?, beforeStages: MTLRenderStages?)
    case updateFence(MTLFenceType, afterStages: MTLRenderStages?)
    case waitForFence(MTLFenceType, beforeStages: MTLRenderStages?)
    case waitForMultiframeFence(resource: ResourceProtocol.Handle, resourceType: ResourceType, waitFence: WaitFence, beforeStages: MTLRenderStages?)
    
    var priority : Int {
        switch self {
        case .materialiseTexture, .materialiseBuffer:
            return 0
        case .retainFence:
            return 2
        case .releaseFence, .releaseMultiframeFences:
            return 3
        case .setDisposalFences:
            return 4
        case .disposeResource:
            return 5
        default:
            return 1
        }
    }
    
    func execute(resourceRegistry: ResourceRegistry) {
        switch self {
        case .materialiseBuffer(let buffer):
            resourceRegistry.allocateBufferIfNeeded(buffer)
            buffer.applyDeferredSliceActions()
            
        case .materialiseTexture(let texture, let usage):
            resourceRegistry.allocateTextureIfNeeded(texture, usage: usage)
            
        case .materialiseTextureView(let texture, let usage):
            resourceRegistry.allocateTextureView(texture, properties: usage)
            
        case .retainFence(let fence):
            resourceRegistry.retainFence(fence)
            
        case .releaseFence(let fence):
            resourceRegistry.releaseFence(fence)
            
        case .releaseMultiframeFences(let resourceHandle):
            let resource = Resource(existingHandle: resourceHandle)
            
            if let buffer = resource.buffer {
                resourceRegistry.releaseMultiframeFences(on: buffer)
            } else if let texture = resource.texture {
                resourceRegistry.releaseMultiframeFences(on: texture)
            }
            
        case .setDisposalFences(let resource, let readWaitFence, let writeWaitFences):
            if let buffer = resource.buffer {
                resourceRegistry.setDisposalFences(buffer, readFence: readWaitFence, writeFences: writeWaitFences)
            } else if let texture = resource.texture {
                resourceRegistry.setDisposalFences(texture, readFence: readWaitFence, writeFences: writeWaitFences)
            }
            
        case .disposeResource(let resourceHandle):
            let resource = Resource(existingHandle: resourceHandle)
            if let buffer = resource.buffer {
                resourceRegistry.disposeBuffer(buffer, keepingReference: true)
            } else if let texture = resource.texture {
                resourceRegistry.disposeTexture(texture, keepingReference: true)
                
            } else {
                fatalError()
            }
            
        default:
            fatalError()
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

struct TextureUsageProperties {
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
    
    var resourceRegistryPreFrameCommands = [ResourceCommand]()
    
    var resourceCommands = [ResourceCommand]()
    var renderTargetTextureProperties = [Texture : TextureUsageProperties]()
    var commandEncoderDependencies = [[Dependency]]()
    
    /// - param storedTextures: textures that are stored as part of a render target (and therefore can't be memoryless on iOS)
    func generateResourceCommands(passes: [RenderPassRecord], resourceUsages: ResourceUsages, renderTargetDescriptors: [MetalRenderTargetDescriptor?], storedTextures: [Texture]) {
        let (passCommandEncoderIndices, _, commandEncoderCount) = EncoderManager.generateCommandEncoderIndices(passes: passes, renderTargetDescriptors: renderTargetDescriptors)
        
        if self.commandEncoderDependencies.count < commandEncoderCount {
            commandEncoderDependencies.append(contentsOf: repeatElement([Dependency](), count: commandEncoderCount - self.commandEncoderDependencies.count))
        }
        
        resourceLoop: for resource in resourceUsages.allResources {
            let resourceType = resource.type
            
            let usages = resource.usages
            if usages.isEmpty { continue }
            
            do {
                // Track resource residency.
                
                var commandIndex = 0
                var previousPass : RenderPassRecord? = nil
                var resourceUsage : MTLResourceUsage = []
                
                for usage in usages where usage.renderPassRecord.isActive && usage.inArgumentBuffer && usage.stages != .cpuBeforeRender {
                    
                    defer { previousPass = usage.renderPassRecord }
                    
                    if let previousPassUnwrapped = previousPass, passCommandEncoderIndices[previousPassUnwrapped.passIndex] != passCommandEncoderIndices[usage.renderPassRecord.passIndex] {
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
            } while !previousUsage.renderPassRecord.isActive || previousUsage.type == .unusedArgumentBuffer
            
            
            var firstUsage = previousUsage
            
            if !firstUsage.isWrite {
                
                // Scan forward from the 'first usage' until we find the _actual_ first usage - that is, the usage whose command range comes first.
                // The 'first usage' might only not actually be the first if the first usages are all reads.
                
                var firstUsageIterator = usageIterator // Since the usageIterator is a struct, this will copy the iterator.
                while let nextUsage = firstUsageIterator.next(), nextUsage.isRead {
                    if nextUsage.renderPassRecord.isActive, nextUsage.type != .unusedRenderTarget, nextUsage.commandRange.lowerBound < firstUsage.commandRange.lowerBound {
                        firstUsage = nextUsage
                    }
                }
            }
            
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
                if !usage.renderPassRecord.isActive || usage.stages == .cpuBeforeRender {
                    continue
                }
                
                if usage.isWrite {
                    assert(!resource.flags.contains(.immutableOnceInitialised) || !resource.stateFlags.contains(.initialised), "A resource with the flag .immutableOnceInitialised is being written to in \(usage) when it has already been initialised.")
                    
                    for previousRead in readsSinceLastWrite where passCommandEncoderIndices[previousRead.renderPassRecord.passIndex] != passCommandEncoderIndices[usage.renderPassRecord.passIndex] {
                        let dependency = Dependency(dependentUsage: usage, passUsage: previousRead)
                        commandEncoderDependencies[passCommandEncoderIndices[previousRead.renderPassRecord.passIndex]].append(dependency)
                    }
                }
                
                // Only insert a barrier for the first usage following a write.
                if usage.isRead, previousUsage.isWrite,
                    passCommandEncoderIndices[previousUsage.renderPassRecord.passIndex] == passCommandEncoderIndices[usage.renderPassRecord.passIndex]  {
                        if !(previousUsage.type.isRenderTarget && (usage.type == .writeOnlyRenderTarget || usage.type == .readWriteRenderTarget)) {
                            if #available(OSX 10.14, *) {
                                self.resourceCommands.append(ResourceCommand(command: .memoryBarrier(Resource(resource), afterStages: MTLRenderStages(previousUsage.stages.last), beforeStages: MTLRenderStages(usage.stages.first)), index: usage.commandRange.lowerBound, order: .before))
                                
                            } else {
                                if previousUsage.type.isRenderTarget, (usage.type != .writeOnlyRenderTarget && usage.type != .readWriteRenderTarget) {
                                    // Insert a texture barrier.
                                    self.resourceCommands.append(ResourceCommand(command: .textureBarrier, index: usage.commandRange.lowerBound, order: .before))
                                }
                            }
                        }
                }
                
                if (usage.isRead || usage.isWrite), let previousWrite = previousWrite, passCommandEncoderIndices[previousWrite.renderPassRecord.passIndex] != passCommandEncoderIndices[usage.renderPassRecord.passIndex] {
                    let dependency = Dependency(dependentUsage: usage, passUsage: previousWrite)
                    commandEncoderDependencies[passCommandEncoderIndices[previousWrite.renderPassRecord.passIndex]].append(dependency)
                }
                
                if previousWrite == nil, passCommandEncoderIndices[usage.renderPassRecord.passIndex] != passCommandEncoderIndices[previousUsage.renderPassRecord.passIndex] {
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
                
                if usage.commandRange.endIndex > previousUsage.commandRange.endIndex { // FIXME: this is only necessary because resource commands are executed sequentially; this will only be false if both usage and previousUsage are reads, and so it doesn't matter which order they happen in.
                    // A better solution would be to effectively compile all resource commands ahead of time - doing so will also enable multithreading and out-of-order execution of render passes.
                    previousUsage = usage
                }
            }
            
            let lastUsage = previousUsage
            
            self.resourceRegistryPreFrameCommands.append(ResourceCommand(command: .releaseMultiframeFences(resource: resource.handle), index: lastUsage.commandRange.upperBound - 1, order: .after))

            defer {
                if resource.flags.intersection([.historyBuffer, .persistent]) != [] {
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
            if !resource.flags.contains(.persistent) || resource.flags.contains(.windowHandle) {
                if let buffer = resource.buffer {
                    if !historyBufferUseFrame {
                        self.resourceRegistryPreFrameCommands.append(ResourceCommand(command: .materialiseBuffer(buffer), index: firstUsage.commandRange.lowerBound, order: .before))
                    }
                    
                    if !resource.flags.contains(.historyBuffer) || resource.stateFlags.contains(.initialised) {
                        if historyBufferUseFrame {
                            self.resourceRegistry.registerInitialisedHistoryBufferForDisposal(resource: Resource(buffer))
                        } else {
                            self.resourceRegistryPreFrameCommands.append(ResourceCommand(command: .disposeResource(buffer.handle), index: lastUsage.commandRange.upperBound - 1, order: .after))
                        }
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
                        case .readWriteRenderTarget, .writeOnlyRenderTarget, .inputAttachmentRenderTarget:
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
                    let properties = TextureUsageProperties(usage: textureUsage, canBeMemoryless: canBeMemoryless)
                    #else
                    let properties = TextureUsageProperties(usage: textureUsage)
                    #endif
                    
                    if textureUsage.contains(.renderTarget) {
                        self.renderTargetTextureProperties[texture] = properties
                    }
                    
                    if !historyBufferUseFrame {
                        if texture.isTextureView {
                            self.resourceRegistryPreFrameCommands.append(ResourceCommand(command: .materialiseTextureView(texture, usage: properties), index: firstUsage.commandRange.lowerBound, order: .before))
                        } else {
                            self.resourceRegistryPreFrameCommands.append(ResourceCommand(command: .materialiseTexture(texture, usage: properties), index: firstUsage.commandRange.lowerBound, order: .before))
                        }
                    }
                    
                    if !resource.flags.contains(.historyBuffer) || resource.stateFlags.contains(.initialised) {
                        if historyBufferUseFrame {
                            self.resourceRegistry.registerInitialisedHistoryBufferForDisposal(resource: Resource(texture))
                        } else {
                            self.resourceRegistryPreFrameCommands.append(ResourceCommand(command: .disposeResource(texture.handle), index: lastUsage.commandRange.upperBound - 1, order: .after))
                        }
                        
                    }
                }
            }
            
            do {
                var storeWriteFences : [MTLFenceType]? = nil
                var storeReadFence : MTLFenceType? = nil
                
                if resourceRegistry.needsWaitFencesOnFrameCompletion(resource: resource), !canBeMemoryless {
                    // Reads need to wait for all previous writes to complete.
                    // Writes need to wait for all previous reads and writes to complete.
                    
                    if let previousWrite = previousWrite {
                        let updateFence = self.resourceRegistry.allocateFence()
                        storeReadFence = updateFence
                        storeWriteFences = [updateFence]
                        
                        self.resourceCommands.append(ResourceCommand(command: .updateFence(updateFence, afterStages: MTLRenderStages(previousWrite.stages.last)), index: previousWrite.commandRange.upperBound - 1, order: .after))
                        
                        // allocateFence returns a fence with a +1 retain count, so release it at the end of the frame.
                        self.resourceRegistryPreFrameCommands.append(ResourceCommand(command: .releaseFence(updateFence), index: .max, order: .after))
                    }
                    
                    if !resource.flags.contains(.immutableOnceInitialised) {
                        var writeFences = storeWriteFences ?? []
                        for read in readsSinceLastWrite {
                            let updateFence = self.resourceRegistry.allocateFence()
                            writeFences.append(updateFence)
                            
                            self.resourceCommands.append(ResourceCommand(command: .updateFence(updateFence, afterStages: MTLRenderStages(read.stages.last)), index: read.commandRange.upperBound - 1, order: .after))
                            
                            // allocateFence returns a fence with a +1 retain count, so release it at the end of the frame.
                            self.resourceRegistryPreFrameCommands.append(ResourceCommand(command: .releaseFence(updateFence), index: .max, order: .after))
                        }
                        storeWriteFences = writeFences
                    }
                    
                    // setDisposalFences retains its fences.
                    self.resourceRegistryPreFrameCommands.append(ResourceCommand(command: .setDisposalFences(resource, readWaitFence: storeReadFence, writeWaitFences: storeWriteFences), index: lastUsage.commandRange.upperBound - 1, order: .after))
                }
            }
            
        }
        
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
                    if passCommandEncoderIndices[dependency.dependentUsage.renderPassRecord.passIndex] == passCommandEncoderIndices[otherDependency.dependentUsage.renderPassRecord.passIndex] {
                        
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
                let sourceEncoder = passCommandEncoderIndices[dependency.passUsage.renderPassRecord.passIndex]
                let dependentEncoder = passCommandEncoderIndices[dependency.dependentUsage.renderPassRecord.passIndex]
                if sourceEncoder != dependentEncoder {
                    let fence = resourceRegistry.allocateFence()
                    self.resourceCommands.append(ResourceCommand(command: .updateFence(fence, afterStages: MTLRenderStages(passStages.last)), index: passCommandIndex - 1, order: .after)) // - 1 because of upperBound
                    
                    self.resourceCommands.append(ResourceCommand(command: .waitForFence(fence, beforeStages: MTLRenderStages(dependentStages.first)), index: dependentCommandIndex, order: .before))
                    self.resourceRegistryPreFrameCommands.append(ResourceCommand(command: .releaseFence(fence), index: dependentCommandIndex, order: .before))
                }
                
                dependencyIndex += 1
            }
        }
        
        self.resourceCommands.sort()
        self.resourceRegistryPreFrameCommands.sort()
    }
    
    public func executeFrameGraph(passes: [RenderPassRecord], resourceUsages: ResourceUsages, commands: [FrameGraphCommand], completion: @escaping () -> Void) {
        defer { self.resourceRegistry.cycleFrames() }
        
        var storedTextures = [Texture]()
        let renderTargetDescriptors = self.generateRenderTargetDescriptors(passes: passes, resourceUsages: resourceUsages, storedTextures: &storedTextures)
        self.generateResourceCommands(passes: passes, resourceUsages: resourceUsages, renderTargetDescriptors: renderTargetDescriptors, storedTextures: storedTextures)
        
        for command in self.resourceRegistryPreFrameCommands {
            command.command.execute(resourceRegistry: self.resourceRegistry)
        }
        self.resourceRegistryPreFrameCommands.removeAll(keepingCapacity: true)
    
        
        let commandBuffer = self.commandQueue.makeCommandBuffer()!
        let encoderManager = EncoderManager(commandBuffer: commandBuffer, resourceRegistry: self.resourceRegistry)
        
        let (passCommandEncoders, commandEncoderNames, _) = EncoderManager.generateCommandEncoderIndices(passes: passes, renderTargetDescriptors: renderTargetDescriptors)
        
        for (i, passRecord) in passes.enumerated() {
            switch passRecord.pass.passType {
            case .blit:
                let commandEncoder = encoderManager.blitCommandEncoder()
                if commandEncoder.encoder.label == nil {
                    commandEncoder.encoder.label = commandEncoderNames[passCommandEncoders[i]]
                }
                
                commandEncoder.executePass(commands: commands[passRecord.commandRange!], resourceCommands: resourceCommands, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
                
            case .draw:
                guard let commandEncoder = encoderManager.renderCommandEncoder(descriptor: renderTargetDescriptors[i]!, textureUsages: self.renderTargetTextureProperties, commands: commands, resourceCommands: resourceCommands, resourceRegistry: resourceRegistry, stateCaches: stateCaches) else {
                    if _isDebugAssertConfiguration() {
                        print("Warning: skipping pass \(passRecord.pass.name) since the drawable for the render target could not be retrieved.")
                    }
                    
                    continue
                }
                if commandEncoder.label == nil {
                    commandEncoder.label = commandEncoderNames[passCommandEncoders[i]]
                }
                
                commandEncoder.executePass(commands: commands[passRecord.commandRange!], resourceCommands: resourceCommands, renderTarget: renderTargetDescriptors[i]!.descriptor, passRenderTarget: (passRecord.pass as! DrawRenderPass).renderTargetDescriptor, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
            case .compute:
                let commandEncoder = encoderManager.computeCommandEncoder()
                if commandEncoder.encoder.label == nil {
                    commandEncoder.encoder.label = commandEncoderNames[passCommandEncoders[i]]
                }
                
                commandEncoder.executePass(commands: commands[passRecord.commandRange!], resourceCommands: resourceCommands, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
                
            case .external:
                let commandEncoder = encoderManager.externalCommandEncoder()
                commandEncoder.executePass(commands: commands[passRecord.commandRange!], resourceCommands: resourceCommands, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
                
            case .cpu:
                break
            }
        }
        
        encoderManager.endEncoding()
        
        for drawable in self.resourceRegistry.frameDrawables {
            #if os(iOS)
            commandBuffer.present(drawable, afterMinimumDuration: 1.0 / 60.0)
            #else
            commandBuffer.present(drawable)
            #endif
        }
        
        commandBuffer.addCompletedHandler { (commandBuffer) in
            completion()
        }
        
        commandBuffer.commit()
        
        self.resourceRegistry.frameGraphHasResourceAccess = false
        
        self.resourceCommands.removeAll(keepingCapacity: true)
        
        self.renderTargetTextureProperties.removeAll(keepingCapacity: true)
        for i in 0..<self.commandEncoderDependencies.count {
            self.commandEncoderDependencies[i].removeAll(keepingCapacity: true)
        }
    }
}
