//
//  PersistentResourceAllocator.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 23/12/17.
//

import Utilities
import Metal

final class PersistentResourceAllocator : BufferAllocator, TextureAllocator {
    let device : MTLDevice
    
    init(device: MTLDevice) {
        self.device = device
    }
    
    func collectTextureWithDescriptor(_ descriptor: MTLTextureDescriptor) -> MTLTextureReference {
        return MTLTextureReference(texture: device.makeTexture(descriptor: descriptor)!)
    }
    
    func collectBufferWithLength(_ length: Int, options: MTLResourceOptions) -> MTLBufferReference {
        return MTLBufferReference(buffer: device.makeBuffer(length: length, options: options)!, offset: 0)
    }
    
    func depositBuffer(_ buffer: MTLBufferReference) {
    }
    
    func depositTexture(_ texture: MTLTextureReference) {
    }
    
    func cycleFrames() {
    }
}



