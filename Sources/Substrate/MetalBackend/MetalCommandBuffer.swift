//
//  MetalCommandBuffer.swift
//  Substrate
//
//  Created by Thomas Roughton on 21/06/20.
//

#if canImport(Metal)
@preconcurrency import Metal
@preconcurrency import MetalKit
import SubstrateUtilities

final class MetalCommandBuffer: BackendCommandBuffer {
    typealias Backend = MetalBackend
    
    let backend: MetalBackend
    let transientRegistry: MetalTransientResourceRegistry?
    let commandBuffer: MTLCommandBuffer
    let commandInfo: FrameCommandInfo<MetalRenderTargetDescriptor>
    let compactedResourceCommands: [CompactedResourceCommand<MetalCompactedResourceCommandType>]
    
    var drawablesToPresentOnScheduled = [Drawable]()
    
    init(backend: MetalBackend,
         queue: MTLCommandQueue,
         transientRegistry: MetalTransientResourceRegistry?,
         commandInfo: FrameCommandInfo<MetalRenderTargetDescriptor>,
         compactedResourceCommands: [CompactedResourceCommand<MetalCompactedResourceCommandType>]) {
        self.backend = backend
        self.transientRegistry = transientRegistry
    
        if backend.enableValidation, #available(OSX 10.16, iOS 14.0, *) {
            let commandBufferDescriptor = MTLCommandBufferDescriptor()
            commandBufferDescriptor.errorOptions = .encoderExecutionStatus
            if MTLResourceOptions.substrateTrackedHazards == .hazardTrackingModeUntracked {
                commandBufferDescriptor.retainedReferences = false
            }
            self.commandBuffer = queue.makeCommandBuffer(descriptor: commandBufferDescriptor)!
        } else {
            if MTLResourceOptions.substrateTrackedHazards == .hazardTrackingModeUntracked {
                self.commandBuffer = queue.makeCommandBufferWithUnretainedReferences()!
            } else {
                self.commandBuffer = queue.makeCommandBuffer()!
            }
        }
        
        self.commandInfo = commandInfo
        self.compactedResourceCommands = compactedResourceCommands
    }
    
    var gpuStartTime: DispatchTime {
        if #available(OSX 10.15, *) {
            return .init(uptimeNanoseconds: UInt64(self.commandBuffer.gpuStartTime * 1e9))
        } else {
            return .init(uptimeNanoseconds: 0)
        }
    }
    
    var gpuEndTime: DispatchTime {
        if #available(OSX 10.15, *) {
            return .init(uptimeNanoseconds: UInt64(self.commandBuffer.gpuEndTime * 1e9))
        } else {
            return .init(uptimeNanoseconds: 0)
        }
    }
    
    func encodeCommands(encoderIndex: Int) async {
        let encoderInfo = self.commandInfo.commandEncoders[encoderIndex]
        var encoderUsedResources = Set<UnsafeMutableRawPointer>()
        
        var resourceCommandIndex = self.compactedResourceCommands.binarySearch(predicate: { $0.index < encoderInfo.passRange.lowerBound })
        
        switch encoderInfo.type {
        case .draw:
            let renderTargetsDescriptor = self.commandInfo.commandEncoderRenderTargets[encoderIndex]!
            let mtlDescriptor : MTLRenderPassDescriptor
            do {
                mtlDescriptor = try await MTLRenderPassDescriptor(renderTargetsDescriptor, transientRegistry: self.transientRegistry)
            } catch {
                print("Error creating pass descriptor for encoder \(encoderInfo): \(error)")
                return
            }
            
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: mtlDescriptor)!
            
        #if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
            renderEncoder.label = encoderInfo.name
        #endif
            
            for passRecord in self.commandInfo.passes[encoderInfo.passRange] {
                renderEncoder.executeResourceCommands(resourceCommandIndex: &resourceCommandIndex, resourceCommands: self.compactedResourceCommands, usedResources: &encoderUsedResources, passIndex: passRecord.passIndex, order: .before, isAppleSiliconGPU: self.backend.isAppleSiliconGPU)
                
                let encoderImpl = MetalRenderCommandEncoder(passRecord: passRecord, encoder: renderEncoder, usedResources: encoderUsedResources, isAppleSiliconGPU: self.backend.isAppleSiliconGPU)
                let encoder = RenderCommandEncoder(renderPass: (passRecord.pass as! DrawRenderPass), passRecord: passRecord, impl: encoderImpl, renderTargetsDescriptor: renderTargetsDescriptor.descriptor)
                await (passRecord.pass as! DrawRenderPass).execute(renderCommandEncoder: encoder)
                encoder.endEncoding()
                
                renderEncoder.executeResourceCommands(resourceCommandIndex: &resourceCommandIndex, resourceCommands: self.compactedResourceCommands, usedResources: &encoderUsedResources, passIndex: passRecord.passIndex, order: .after, isAppleSiliconGPU: self.backend.isAppleSiliconGPU)
                
            }
            renderEncoder.endEncoding()
            
        case .compute:
            let dispatchType: MTLDispatchType = MTLResourceOptions.substrateTrackedHazards != .hazardTrackingModeUntracked ? .serial : .concurrent
            let computeEncoder = commandBuffer.makeComputeCommandEncoder(dispatchType: dispatchType)!
            
        #if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
            computeEncoder.label = encoderInfo.name
        #endif
            
            for passRecord in self.commandInfo.passes[encoderInfo.passRange] {
                computeEncoder.executeResourceCommands(resourceCommandIndex: &resourceCommandIndex, resourceCommands: self.compactedResourceCommands, usedResources: &encoderUsedResources, passIndex: passRecord.passIndex, order: .before, isAppleSiliconGPU: self.backend.isAppleSiliconGPU)
                
                let encoderImpl = MetalComputeCommandEncoder(encoder: computeEncoder, usedResources: encoderUsedResources, isAppleSiliconGPU: self.backend.isAppleSiliconGPU)
                let encoder = ComputeCommandEncoder(renderPass: (passRecord.pass as! ComputeRenderPass), passRecord: passRecord, impl: encoderImpl)
                await (passRecord.pass as! ComputeRenderPass).execute(computeCommandEncoder: encoder)
                encoder.endEncoding()
                
                computeEncoder.executeResourceCommands(resourceCommandIndex: &resourceCommandIndex, resourceCommands: self.compactedResourceCommands, usedResources: &encoderUsedResources, passIndex: passRecord.passIndex, order: .after, isAppleSiliconGPU: self.backend.isAppleSiliconGPU)
            }
            computeEncoder.endEncoding()
            
        case .blit:
            let blitEncoder = commandBuffer.makeBlitCommandEncoder()!
            
        #if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
            blitEncoder.label = encoderInfo.name
        #endif
            
            for passRecord in self.commandInfo.passes[encoderInfo.passRange] {
                blitEncoder.executeResourceCommands(resourceCommandIndex: &resourceCommandIndex, resourceCommands: self.compactedResourceCommands, passIndex: passRecord.passIndex, order: .before, isAppleSiliconGPU: self.backend.isAppleSiliconGPU)
                
                let encoderImpl = MetalBlitCommandEncoder(encoder: blitEncoder, isAppleSiliconGPU: self.backend.isAppleSiliconGPU)
                let encoder = BlitCommandEncoder(renderPass: (passRecord.pass as! BlitRenderPass), passRecord: passRecord, impl: encoderImpl)
                await (passRecord.pass as! BlitRenderPass).execute(blitCommandEncoder: encoder)
                encoder.endEncoding()
                
                blitEncoder.executeResourceCommands(resourceCommandIndex: &resourceCommandIndex, resourceCommands: self.compactedResourceCommands, passIndex: passRecord.passIndex, order: .after, isAppleSiliconGPU: self.backend.isAppleSiliconGPU)
            }
            blitEncoder.endEncoding()
            
        case .external:
            for passRecord in self.commandInfo.passes[encoderInfo.passRange] {
                let encoderImpl = MetalExternalCommandEncoder(commandBuffer: self.commandBuffer)
                let encoder = ExternalCommandEncoder(renderPass: (passRecord.pass as! ExternalRenderPass), passRecord: passRecord, impl: encoderImpl)
                await (passRecord.pass as! ExternalRenderPass).execute(externalCommandEncoder: encoder)
                encoder.endEncoding()
            }
            
        case .accelerationStructure:
            if #available(macOS 11.0, iOS 14.0, *) {
                let accelerationStructureEncoder = commandBuffer.makeAccelerationStructureCommandEncoder()!
                
                #if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
                accelerationStructureEncoder.label = encoderInfo.name
                #endif
                
                for passRecord in self.commandInfo.passes[encoderInfo.passRange] {
                    accelerationStructureEncoder.executeResourceCommands(resourceCommandIndex: &resourceCommandIndex, resourceCommands: self.compactedResourceCommands, passIndex: passRecord.passIndex, order: .before, isAppleSiliconGPU: self.backend.isAppleSiliconGPU)
                    
                    let encoderImpl = MetalAccelerationStructureCommandEncoder(encoder: accelerationStructureEncoder)
                    let encoder = AccelerationStructureCommandEncoder(accelerationStructureRenderPass: (passRecord.pass as! AccelerationStructureRenderPass), passRecord: passRecord, impl: encoderImpl)
                    (passRecord.pass as! AccelerationStructureRenderPass).execute(accelerationStructureCommandEncoder: encoder)
                    encoder.endEncoding()
                    
                    accelerationStructureEncoder.executeResourceCommands(resourceCommandIndex: &resourceCommandIndex, resourceCommands: self.compactedResourceCommands, passIndex: passRecord.passIndex, order: .after, isAppleSiliconGPU: self.backend.isAppleSiliconGPU)
                }
                accelerationStructureEncoder.endEncoding()
            } else {
                preconditionFailure()
            }
        case .cpu:
            break
        }
    }
    
    func waitForEvent(_ event: MTLEvent, value: UInt64) {
        self.commandBuffer.encodeWaitForEvent(event, value: value)
    }
    
    func signalEvent(_ event: MTLEvent, value: UInt64) {
        self.commandBuffer.encodeSignalEvent(event, value: value)
    }
    
    func presentSwapchains(resourceRegistry: MetalTransientResourceRegistry, onPresented: RenderGraph.SwapchainPresentedCallback?) {
        // Only contains drawables applicable to the render passes in the command buffer...
        for (texture, result) in resourceRegistry.frameDrawables {
            switch result {
            case .failure(let error):
                onPresented?(texture, .failure(error))
                continue
            case .success(let drawable):
                if let onPresented = onPresented {
                    drawable.addPresentedHandler {
                        withExtendedLifetime(drawable) {
                            onPresented(texture, .success(drawable))
                        }
                    }
                }
                
                self.drawablesToPresentOnScheduled.append(drawable)
            }
        }
        // because we reset the list after each command buffer submission.
        resourceRegistry.clearDrawables()
    }
    
    func presentDrawables(_ drawablesToPresent: [Drawable]) {
        for drawable in drawablesToPresent {
            drawable.present()
        }
    }
    
    func commit(onCompletion: @escaping (MetalCommandBuffer) -> Void) {
        self.commandBuffer.addCompletedHandler { _ in
            onCompletion(self)
        }
        
        let drawablesToPresent = self.drawablesToPresentOnScheduled
        self.drawablesToPresentOnScheduled = []
        if !drawablesToPresent.isEmpty {
            self.commandBuffer.addScheduledHandler { _ in
                self.presentDrawables(drawablesToPresent)
            }
        }
        
        self.commandBuffer.commit()
    }
    
    var error: Error? {
        return self.commandBuffer.error
    }
}

#if os(visionOS) && targetEnvironment(simulator)

protocol MTLDrawableExtensions: MTLDrawable {
    func addPresentedHandler(_ handler: MTLDrawablePresentedHandler)
}

#endif

#endif
