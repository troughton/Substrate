//
//  MetalPersistentResourceAllocator.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 23/12/17.
//

#if canImport(Metal)

import FrameGraphUtilities
import Metal

final class MetalPersistentResourceAllocator : MetalBufferAllocator, MetalTextureAllocator {
    let device : MTLDevice
    
    init(device: MTLDevice) {
        self.device = device
    }
    
    func collectTextureWithDescriptor(_ descriptor: MTLTextureDescriptor) -> (MTLTextureReference, [MetalFenceHandle], MetalWaitEvent) {
        return (MTLTextureReference(texture: Unmanaged.passRetained(device.makeTexture(descriptor: descriptor)!)),
                [],
                MetalWaitEvent())
    }
    
    func collectBufferWithLength(_ length: Int, options: MTLResourceOptions) -> (MTLBufferReference, [MetalFenceHandle], MetalWaitEvent) {
        return (MTLBufferReference(buffer: Unmanaged.passRetained(device.makeBuffer(length: length, options: options)!), offset: 0),
                [],
                MetalWaitEvent())
    }
    
    func depositBuffer(_ buffer: MTLBufferReference, fences: [MetalFenceHandle], waitEvent: MetalWaitEvent) {
        buffer._buffer.release()
    }
    
    func depositTexture(_ texture: MTLTextureReference, fences: [MetalFenceHandle], waitEvent: MetalWaitEvent) {
        texture._texture.release()
    }
    
    func cycleFrames() {
    }
}

#endif // canImport(Metal)
