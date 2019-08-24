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
    
    func collectTextureWithDescriptor(_ descriptor: MTLTextureDescriptor) -> (MTLTextureReference, MetalResourceFences) {
        return (MTLTextureReference(texture: Unmanaged.passRetained(device.makeTexture(descriptor: descriptor)!)),
                MetalResourceFences())
    }
    
    func collectBufferWithLength(_ length: Int, options: MTLResourceOptions) -> (MTLBufferReference, MetalResourceFences) {
        return (MTLBufferReference(buffer: Unmanaged.passRetained(device.makeBuffer(length: length, options: options)!), offset: 0),
                MetalResourceFences())
    }
    
    func depositBuffer(_ buffer: MTLBufferReference, fences: MetalResourceFences) {
        fences.readWaitFence.release()
        for fence in fences.writeWaitFences {
            fence.release()
        }
        buffer._buffer.release()
    }
    
    func depositTexture(_ texture: MTLTextureReference, fences: MetalResourceFences) {
        fences.readWaitFence.release()
        for fence in fences.writeWaitFences {
            fence.release()
        }
        texture._texture.release()
    }
    
    func cycleFrames() {
    }
}

#endif // canImport(Metal)
