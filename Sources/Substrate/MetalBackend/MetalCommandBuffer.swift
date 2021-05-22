//
//  MetalCommandBuffer.swift
//  Substrate
//
//  Created by Thomas Roughton on 21/06/20.
//

#if canImport(Metal)
import Metal
import MetalKit
import SubstrateUtilities

final class MetalCommandBuffer: BackendCommandBuffer {
    typealias Backend = MetalBackend
    
    let backend: MetalBackend
    let commandBuffer: MTLCommandBuffer
    let commandInfo: FrameCommandInfo<MetalBackend>
    let resourceMap: FrameResourceMap<MetalBackend>
    let compactedResourceCommands: [CompactedResourceCommand<MetalCompactedResourceCommandType>]
    
    var drawablesToPresentOnScheduled = [CAMetalDrawable]()
    
    init(backend: MetalBackend,
         queue: MTLCommandQueue,
         commandInfo: FrameCommandInfo<Backend>,
         resourceMap: FrameResourceMap<MetalBackend>,
         compactedResourceCommands: [CompactedResourceCommand<MetalCompactedResourceCommandType>]) {
        self.backend = backend
    
        if backend.enableValidation, #available(OSX 10.16, iOS 14.0, *) {
            let commandBufferDescriptor = MTLCommandBufferDescriptor()
            commandBufferDescriptor.errorOptions = .encoderExecutionStatus
            commandBufferDescriptor.retainedReferences = false
            self.commandBuffer = queue.makeCommandBuffer(descriptor: commandBufferDescriptor)!
        } else {
            self.commandBuffer = queue.makeCommandBufferWithUnretainedReferences()!
        }
        
        self.commandInfo = commandInfo
        self.resourceMap = resourceMap
        self.compactedResourceCommands = compactedResourceCommands
    }
    
    var gpuStartTime: Double {
        if #available(OSX 10.15, *) {
            return self.commandBuffer.gpuStartTime
        } else {
            return 0.0
        }
    }
    
    var gpuEndTime: Double {
        if #available(OSX 10.15, *) {
            return self.commandBuffer.gpuEndTime
        } else {
            return 0.0
        }
    }
    
    func encodeCommands(encoderIndex: Int) async {
        let encoderInfo = self.commandInfo.commandEncoders[encoderIndex]
        
        switch encoderInfo.type {
        case .draw:
            let mtlDescriptor : MTLRenderPassDescriptor
            do {
                mtlDescriptor = try MTLRenderPassDescriptor(encoderInfo.renderTargetDescriptor!, resourceMap: self.resourceMap)
            } catch {
                print("Error creating pass descriptor: \(error)")
                return
            }
            
            let renderEncoder : FGMTLRenderCommandEncoder = /* MetalEncoderManager.useParallelEncoding ? FGMTLParallelRenderCommandEncoder(encoder: commandBuffer.makeParallelRenderCommandEncoder(descriptor: mtlDescriptor)!, renderPassDescriptor: mtlDescriptor) : */ FGMTLThreadRenderCommandEncoder(encoder: commandBuffer.makeRenderCommandEncoder(descriptor: mtlDescriptor)!, renderPassDescriptor: mtlDescriptor, isAppleSiliconGPU: backend.isAppleSiliconGPU)
            renderEncoder.encoder.label = encoderInfo.name
            
            for passRecord in self.commandInfo.passes[encoderInfo.passRange] {
                await renderEncoder.executePass(passRecord, resourceCommands: self.compactedResourceCommands, renderTarget: encoderInfo.renderTargetDescriptor!.descriptor, passRenderTarget: (passRecord.pass as! DrawRenderPass).renderTargetDescriptor, resourceMap: self.resourceMap, stateCaches: backend.stateCaches)
            }
            renderEncoder.endEncoding()
            
        case .compute:
            let mtlComputeEncoder = commandBuffer.makeComputeCommandEncoder(dispatchType: .concurrent)!
            let computeEncoder = FGMTLComputeCommandEncoder(encoder: mtlComputeEncoder, isAppleSiliconGPU: backend.isAppleSiliconGPU)
            computeEncoder.encoder.label = encoderInfo.name
            
            for passRecord in self.commandInfo.passes[encoderInfo.passRange] {
                await computeEncoder.executePass(passRecord, resourceCommands: self.compactedResourceCommands, resourceMap: self.resourceMap, stateCaches: backend.stateCaches)
            }
            computeEncoder.endEncoding()
            
        case .blit:
            let blitEncoder = FGMTLBlitCommandEncoder(encoder: commandBuffer.makeBlitCommandEncoder()!, isAppleSiliconGPU: backend.isAppleSiliconGPU)
            blitEncoder.encoder.label = encoderInfo.name
            
            for passRecord in self.commandInfo.passes[encoderInfo.passRange] {
                blitEncoder.executePass(passRecord, resourceCommands: self.compactedResourceCommands, resourceMap: self.resourceMap, stateCaches: backend.stateCaches)
            }
            blitEncoder.endEncoding()
            
        case .external:
            let commandEncoder = FGMTLExternalCommandEncoder(commandBuffer: self.commandBuffer)
            
            for passRecord in self.commandInfo.passes[encoderInfo.passRange] {
                commandEncoder.executePass(passRecord, resourceCommands: self.compactedResourceCommands, resourceMap: self.resourceMap, stateCaches: backend.stateCaches)
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
    
    func presentSwapchains(resourceRegistry: MetalTransientResourceRegistry) {
        // Only contains drawables applicable to the render passes in the command buffer...
        for drawable in resourceRegistry.frameDrawables {
            if drawable.layer.presentsWithTransaction {
                self.drawablesToPresentOnScheduled.append(drawable)
                continue
            }
            
            #if (os(iOS) || os(tvOS) || os(watchOS)) && !targetEnvironment(macCatalyst)
            self.commandBuffer.present(drawable, afterMinimumDuration: 1.0 / 60.0)
            #else
            if #available(macOS 10.15.4, macCatalyst 13.4, *), backend.isAppleSiliconGPU {
                self.commandBuffer.present(drawable, afterMinimumDuration: 1.0 / 60.0)
            } else {
                self.commandBuffer.present(drawable)
            }
            #endif
        }
        // because we reset the list after each command buffer submission.
        resourceRegistry.clearDrawables()
    }
    
    func commit(onCompletion: @escaping (MetalCommandBuffer) -> Void) {
        self.commandBuffer.addCompletedHandler { _ in
            onCompletion(self)
        }
        self.commandBuffer.commit()
        
        let drawablesToPresent = self.drawablesToPresentOnScheduled
        self.drawablesToPresentOnScheduled = []
        if !drawablesToPresent.isEmpty {
            DispatchQueue.main.async {
                self.commandBuffer.waitUntilScheduled()
                for drawable in drawablesToPresent {
                    drawable.present()
                }
            }
        }
    }
    
    var error: Error? {
        return self.commandBuffer.error
    }
}

#endif
