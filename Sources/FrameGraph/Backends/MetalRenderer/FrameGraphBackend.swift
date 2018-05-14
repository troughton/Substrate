//
//  MetalFrameGraph.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 23/12/17.
//

import RenderAPI
import FrameGraph
import Metal

enum ResourceCommands {
    case materialiseBuffer(Buffer)
    case materialiseTexture(Texture, usage: MTLTextureUsage)
    case disposeBuffer(Buffer)
    case disposeTexture(Texture)
    
    case useResource(Resource, usage: MTLResourceUsage)
    
    case textureBarrier
    case updateFence(id: Int, afterStages: MTLRenderStages?)
    case waitForFence(id: Int, beforeStages: MTLRenderStages?)
    
    var isMaterialise : Bool {
        switch self {
        case .materialiseTexture, .materialiseBuffer:
            return true
        default:
            return false
        }
    }
}

struct ResourceCommand : Comparable {
    var command : ResourceCommands
    var index : Int
    var order : PerformOrder
    
    public static func ==(lhs: ResourceCommand, rhs: ResourceCommand) -> Bool {
        return lhs.index == rhs.index && lhs.order == rhs.order &&
            lhs.command.isMaterialise == rhs.command.isMaterialise
    }
    
    public static func <(lhs: ResourceCommand, rhs: ResourceCommand) -> Bool {
        if lhs.index < rhs.index { return true }
        if lhs.index == rhs.index {
            if lhs.order < rhs.order {
                return true
            }
            if lhs.order == rhs.order, lhs.command.isMaterialise && !rhs.command.isMaterialise {
                return true
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
    
    // For fence tracking - support at most one dependency between each set of two render passes. Make the fence update as early as possible, and make the fence wait as late as possible.
    //
    // No fences are needed between compute command encoders, and CCEs automatically manage hazards in between dispatchThreadgroups calls.
    //
    // Fences are needed between different types of command encoders.
    
    func generateResourceCommands(passes: [RenderPassRecord], resourceUsages: ResourceUsages, renderTargetDescriptors: [MetalRenderTargetDescriptor?]) -> ([ResourceCommand], [Texture: MTLTextureUsage]) {
        
        var commands = [ResourceCommand]()
        var renderTargetTextureUsages = [Texture : MTLTextureUsage]()
        
        class Dependency {
            /// dependentUsage is the usage within the dependent pass.
            var dependentUsage : ResourceUsage
            /// passUsage is the usage within the current pass (the pass that's depended upon).
            var passUsage : ResourceUsage
            
            init(dependentUsage: ResourceUsage, passUsage: ResourceUsage) {
                self.dependentUsage = dependentUsage
                self.passUsage = passUsage
            }
        }
        
        var passDependencies = [[Dependency]](repeating: [Dependency](), count: passes.count)
        
        resourceLoop: for resource in resourceUsages.allResources {
            let usages = resourceUsages[usagesFor: resource]
            if usages.isEmpty { continue }
            
            do {
                // Track resource residency.
                
                var commandIndex = 0
                var previousPass : RenderPassRecord? = nil
                var resourceUsage : MTLResourceUsage = []
                
                for usage in usages where usage.renderPass.isActive && usage.type != .argumentBufferUnused && usage.inArgumentBuffer {
                    defer { previousPass = usage.renderPass }
                    
                    if let previousPassUnwrapped = previousPass, !sharesCommandEncoders(previousPassUnwrapped, usage.renderPass, passes: passes, renderTargetDescriptors: renderTargetDescriptors) {
                        commands.append(ResourceCommand(command: .useResource(resource, usage: resourceUsage), index: commandIndex, order: .before))
                        previousPass = nil
                    }
                    
                    if previousPass == nil {
                        resourceUsage = []
                        commandIndex = usage.commandRange.lowerBound
                    }
                    
                    if resource is Texture, usage.type == .read {
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
                    commands.append(ResourceCommand(command: .useResource(resource, usage: resourceUsage), index: commandIndex, order: .before))
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
            } while !previousUsage.renderPass.isActive || previousUsage.type == .argumentBufferUnused

            let firstUsage = previousUsage
            
            while let usage = usageIterator.next()  {
                if !usage.renderPass.isActive || usage.type == .argumentBufferUnused {
                    continue
                }
                
                if usage.type != previousUsage.type, !(previousUsage.type.isRenderTarget && usage.type.isRenderTarget), previousUsage.type != .read {
                    if usage.renderPass.pass is DrawRenderPass, renderTargetDescriptors[previousUsage.renderPass.passIndex] === renderTargetDescriptors[usage.renderPass.passIndex] {
                        
                        if previousUsage.type.isRenderTarget, usage.isRead {
                            // Insert a texture barrier.
                            commands.append(ResourceCommand(command: .textureBarrier, index: usage.commandRange.lowerBound, order: .before))
                        }
                    } else if (usage.renderPass.pass.passType != previousUsage.renderPass.pass.passType) || (usage.renderPass.pass.passType == .draw && previousUsage.renderPass.pass.passType == .draw) {
                        let dependency = Dependency(dependentUsage: usage, passUsage: previousUsage)
                        passDependencies[previousUsage.renderPass.passIndex].append(dependency)
                    }
                }
                
                previousUsage = usage
            }
            
            let lastUsage = previousUsage
            
            let historyBufferUseFrame = resource.flags.contains([.historyBuffer, .initialised])
            
            // Insert commands to materialise and dispose of the resource.
            if !resource.flags.contains(.persistent) || resource.flags.contains(.windowHandle) {
                if let buffer = resource as? Buffer {
                    if !historyBufferUseFrame {
                        commands.append(ResourceCommand(command: .materialiseBuffer(buffer), index: firstUsage.commandRange.lowerBound, order: .before))
                    }
                    
                    commands.append(ResourceCommand(command: .disposeBuffer(buffer), index: lastUsage.commandRange.upperBound - 1, order: .after))
    
                } else {
                    let texture = resource as! Texture
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
                        renderTargetTextureUsages[texture] = textureUsage
                    }
                    
                    if !historyBufferUseFrame {
                        commands.append(ResourceCommand(command: .materialiseTexture(texture, usage: textureUsage), index: firstUsage.commandRange.lowerBound, order: .before))
                    }
                    
                    commands.append(ResourceCommand(command: .disposeTexture(texture), index: lastUsage.commandRange.upperBound - 1, order: .after))
                    
                }
            }
        }
        
        var fenceId = 0
        
        // Process the dependencies, joining duplicates.
        for passIndex in 0..<passes.count { // passIndex always points to the producing pass.
            var dependencyIndex = 0
            while dependencyIndex < passDependencies[passIndex].count {
                let dependency = passDependencies[passIndex][dependencyIndex]
                
                var passCommandIndex = dependency.passUsage.commandRange.upperBound
                var passStages = dependency.passUsage.stages
                var dependentCommandIndex = dependency.dependentUsage.commandRange.lowerBound
                var dependentStages = dependency.dependentUsage.stages
                
                var otherDependencyIndex = dependencyIndex + 1
                while otherDependencyIndex < passDependencies[passIndex].count {
                    let otherDependency = passDependencies[passIndex][otherDependencyIndex]
                    if dependency.dependentUsage.renderPass === otherDependency.dependentUsage.renderPass {
                        
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
                        
                        passDependencies[passIndex].remove(at: otherDependencyIndex)
                    } else {
                        otherDependencyIndex += 1
                    }
                }
                
                commands.append(ResourceCommand(command: .updateFence(id: fenceId, afterStages: MTLRenderStages(passStages.last)), index: passCommandIndex - 1, order: .after)) // - 1 because of upperBound
                commands.append(ResourceCommand(command: .waitForFence(id: fenceId, beforeStages: MTLRenderStages(dependentStages.first)), index: dependentCommandIndex, order: .before))
                fenceId += 1
                
                dependencyIndex += 1
            }
        }
        
        commands.sort()
        return (commands, renderTargetTextureUsages)
    }
    
    public func executeFrameGraph(passes: [RenderPassRecord], resourceUsages: ResourceUsages, commands: [FrameGraphCommand], completion: @escaping () -> Void) {
        defer { self.resourceRegistry.cycleFrames() }
        
        let renderTargetDescriptors = self.generateRenderTargetDescriptors(passes: passes, resourceUsages: resourceUsages)
        let (resourceCommands, renderTargetTextureUsages) = self.generateResourceCommands(passes: passes, resourceUsages: resourceUsages, renderTargetDescriptors: renderTargetDescriptors)
        
        
        var resourceCommandIndex = 0
        
        func checkResourceCommands(phase: PerformOrder, commandIndex: Int, encoder: MTLCommandEncoder) {
            var hasPerformedTextureBarrier = false
            while resourceCommandIndex < resourceCommands.count, commandIndex == resourceCommands[resourceCommandIndex].index, phase == resourceCommands[resourceCommandIndex].order {
                defer { resourceCommandIndex += 1}
                
                switch resourceCommands[resourceCommandIndex].command {
                case .materialiseBuffer(let buffer):
                    self.resourceRegistry.allocateBufferIfNeeded(buffer)
                    buffer.applyDeferredSliceActions()
                    
                case .materialiseTexture(let texture, let usage):
                    self.resourceRegistry.allocateTextureIfNeeded(texture, usage: usage)
                    
                case .disposeBuffer(let buffer):
                    if buffer.flags.contains([.historyBuffer, .initialised]) ||
                       buffer.flags.intersection([.historyBuffer, .persistent]) == [] {
                        
                        self.resourceRegistry.disposeBuffer(buffer)
                    } 

                    if buffer.flags.intersection([.persistent, .historyBuffer]) != [] {
                        buffer.markAsInitialised()
                    }
                    
                case .disposeTexture(let texture):
                    if texture.flags.contains([.historyBuffer, .initialised]) ||
                       texture.flags.intersection([.historyBuffer, .persistent]) == [] {
                        
                        self.resourceRegistry.disposeTexture(texture)
                    } 

                    if texture.flags.intersection([.persistent, .historyBuffer]) != [] {
                        texture.markAsInitialised()
                    }
                    
                case .textureBarrier:
                    if !hasPerformedTextureBarrier {
                        (encoder as! MTLRenderCommandEncoder).textureBarrier()
                        hasPerformedTextureBarrier = true
                    }
                    
                case .updateFence(let id, let afterStages):
                    let fence = self.resourceRegistry.fenceWithId(id)
                    if let encoder = encoder as? MTLRenderCommandEncoder {
                        encoder.update(fence, after: afterStages!)
                    } else if let encoder = encoder as? MTLComputeCommandEncoder {
                        encoder.updateFence(fence)
                    } else {
                        (encoder as! MTLBlitCommandEncoder).updateFence(fence)
                    }
                    
                case .waitForFence(let id, let beforeStages):
                    let fence = self.resourceRegistry.fenceWithId(id)
                    if let encoder = encoder as? MTLRenderCommandEncoder {
                        encoder.wait(for: fence, before: beforeStages!)
                    } else if let encoder = encoder as? MTLComputeCommandEncoder {
                        encoder.waitForFence(fence)
                    } else {
                        (encoder as! MTLBlitCommandEncoder).waitForFence(fence)
                    }
                case .useResource(let resource, let usage):
                    let mtlResource : MTLResource
                    
                    if let texture = resource as? Texture {
                        mtlResource = self.resourceRegistry[texture]!
                    } else if let buffer = resource as? Buffer {
                        mtlResource = self.resourceRegistry[buffer]!.buffer
                    } else {
                        fatalError()
                    }
                    
                    if let encoder = encoder as? MTLRenderCommandEncoder {
                        encoder.useResource(mtlResource, usage: usage)
                    } else if let encoder = encoder as? MTLComputeCommandEncoder {
                        encoder.useResource(mtlResource, usage: usage)
                    }
                }
            }
        }
        
        let commandBuffer = self.commandQueue.makeCommandBuffer()!
        let encoderManager = EncoderManager(commandBuffer: commandBuffer, resourceRegistry: self.resourceRegistry)
        
        for (i, passRecord) in passes.enumerated() {
            switch passRecord.pass.passType {
            case .blit:
                let commandEncoder = encoderManager.blitCommandEncoder()
                commandEncoder.pushDebugGroup(passRecord.pass.name)
                
                commandEncoder.executeCommands(commands[passRecord.commandRange!], resourceCheck: checkResourceCommands, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
                
                commandEncoder.popDebugGroup()
                
            case .draw:
                let commandEncoder = encoderManager.renderCommandEncoder(descriptor: renderTargetDescriptors[i]!, textureUsages: renderTargetTextureUsages)
                commandEncoder.pushDebugGroup(passRecord.pass.name)
                
                commandEncoder.executePass(commands: commands[passRecord.commandRange!], resourceCheck: checkResourceCommands, renderTarget: renderTargetDescriptors[i]!.descriptor, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
                
                commandEncoder.popDebugGroup()                
            case .compute:
                let commandEncoder = encoderManager.computeCommandEncoder()
                commandEncoder.pushDebugGroup(passRecord.pass.name)
                
                commandEncoder.executePass(commands: commands[passRecord.commandRange!], resourceCheck: checkResourceCommands, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
                
                commandEncoder.popDebugGroup()
                
            case .cpu:
                break
            }
        }

        encoderManager.endEncoding()
        
        for drawable in self.resourceRegistry.frameDrawables {
            commandBuffer.present(drawable)
        }
        
        commandBuffer.addCompletedHandler { (commandBuffer) in
            completion()
        }
        
        commandBuffer.commit()
        
         self.resourceRegistry.frameGraphHasResourceAccess = false
    }
    
    
}
