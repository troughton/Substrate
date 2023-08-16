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
    let commandBuffer: MTLCommandBuffer
    let commandInfo: FrameCommandInfo<MetalRenderTargetDescriptor>
    let resourceMap: FrameResourceMap<MetalBackend>
    let compactedResourceCommands: [CompactedResourceCommand<MetalCompactedResourceCommandType>]
    
    var drawablesToPresentOnScheduled = [CAMetalDrawable]()
    
    init(backend: MetalBackend,
         queue: MTLCommandQueue,
         commandInfo: FrameCommandInfo<MetalRenderTargetDescriptor>,
         resourceMap: FrameResourceMap<MetalBackend>,
         compactedResourceCommands: [CompactedResourceCommand<MetalCompactedResourceCommandType>]) {
        self.backend = backend
    
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
        self.resourceMap = resourceMap
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
        
        switch encoderInfo.type {
        case .draw:
            let renderTargetDescriptor = self.commandInfo.commandEncoderRenderTargets[encoderIndex]!
            let mtlDescriptor : MTLRenderPassDescriptor
            do {
                mtlDescriptor = try await MTLRenderPassDescriptor(renderTargetDescriptor, resourceMap: self.resourceMap)
            } catch {
                print("Error creating pass descriptor: \(error)")
                return
            }
            
            let renderEncoder : FGMTLRenderCommandEncoder = /* MetalEncoderManager.useParallelEncoding ? FGMTLParallelRenderCommandEncoder(encoder: commandBuffer.makeParallelRenderCommandEncoder(descriptor: mtlDescriptor)!, renderPassDescriptor: mtlDescriptor) : */ FGMTLThreadRenderCommandEncoder(encoder: commandBuffer.makeRenderCommandEncoder(descriptor: mtlDescriptor)!, renderPassDescriptor: mtlDescriptor, isAppleSiliconGPU: backend.isAppleSiliconGPU)
            
        #if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
            renderEncoder.encoder.label = encoderInfo.name
        #endif
            
            for passRecord in self.commandInfo.passes[encoderInfo.passRange] {
                await renderEncoder.executePass(passRecord, resourceCommands: self.compactedResourceCommands, renderTarget: renderTargetDescriptor.descriptor, passRenderTarget: (passRecord.pass as! ProxyDrawRenderPass).renderTargetDescriptor, resourceMap: self.resourceMap, stateCaches: backend.stateCaches)
            }
            renderEncoder.endEncoding()
            
        case .compute:
            let dispatchType: MTLDispatchType = MTLResourceOptions.substrateTrackedHazards != .hazardTrackingModeUntracked ? .serial : .concurrent
            let mtlComputeEncoder = commandBuffer.makeComputeCommandEncoder(dispatchType: dispatchType
            )!
            let computeEncoder = FGMTLComputeCommandEncoder(encoder: mtlComputeEncoder, isAppleSiliconGPU: backend.isAppleSiliconGPU)
            
        #if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
            computeEncoder.encoder.label = encoderInfo.name
        #endif
            
            for passRecord in self.commandInfo.passes[encoderInfo.passRange] {
                await computeEncoder.executePass(passRecord, resourceCommands: self.compactedResourceCommands, resourceMap: self.resourceMap, stateCaches: backend.stateCaches)
            }
            computeEncoder.endEncoding()
            
        case .blit:
            let blitEncoder = FGMTLBlitCommandEncoder(encoder: commandBuffer.makeBlitCommandEncoder()!, isAppleSiliconGPU: backend.isAppleSiliconGPU)
            
        #if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
            blitEncoder.encoder.label = encoderInfo.name
        #endif
            
            for passRecord in self.commandInfo.passes[encoderInfo.passRange] {
                await blitEncoder.executePass(passRecord, resourceCommands: self.compactedResourceCommands, resourceMap: self.resourceMap, stateCaches: backend.stateCaches)
            }
            blitEncoder.endEncoding()
            
        case .external:
            let commandEncoder = FGMTLExternalCommandEncoder(commandBuffer: self.commandBuffer)
            
            for passRecord in self.commandInfo.passes[encoderInfo.passRange] {
                await commandEncoder.executePass(passRecord, resourceCommands: self.compactedResourceCommands, resourceMap: self.resourceMap, stateCaches: backend.stateCaches)
            }
            
        case .accelerationStructure:
            if #available(macOS 11.0, iOS 14.0, *) {
                let accelerationStructureEncoder = FGMTLAccelerationStructureCommandEncoder(encoder: commandBuffer.makeAccelerationStructureCommandEncoder()!, isAppleSiliconGPU: backend.isAppleSiliconGPU)
                
                #if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
                accelerationStructureEncoder.encoder.label = encoderInfo.name
                #endif
                
                for passRecord in self.commandInfo.passes[encoderInfo.passRange] {
                    await accelerationStructureEncoder.executePass(passRecord, resourceCommands: self.compactedResourceCommands, resourceMap: self.resourceMap, stateCaches: backend.stateCaches)
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
    
    func presentSwapchains(resourceRegistry: MetalTransientResourceRegistry, onPresented: (@Sendable (Texture, Result<OpaquePointer?, Error>) -> Void)?) {
        // Only contains drawables applicable to the render passes in the command buffer...
        for (texture, result) in resourceRegistry.frameDrawables {
            switch result {
            case .failure(let error):
                onPresented?(texture, .failure(error))
                continue
            case .success(let drawable):
                if let onPresented = onPresented {
                    drawable.addPresentedHandler { drawable in
                        withExtendedLifetime(drawable) {
                            onPresented(texture, .success(OpaquePointer(Unmanaged.passUnretained(drawable).toOpaque())))
                        }
                    }
                }
                
                if drawable.layer.presentsWithTransaction {
                    self.drawablesToPresentOnScheduled.append(drawable)
                    continue
                }
                
                self.commandBuffer.present(drawable)
            }
        }
        // because we reset the list after each command buffer submission.
        resourceRegistry.clearDrawables()
    }
    
    func presentDrawables(_ drawablesToPresent: [MTLDrawable]) {
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

#endif
