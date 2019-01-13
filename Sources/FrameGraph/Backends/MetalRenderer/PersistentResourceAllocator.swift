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
    
    var fenceRetainFunc : ((MTLFenceType) -> Void)? = nil // Never used.
    var fenceReleaseFunc : ((MTLFenceType) -> Void)! = nil // Used whenever a resource is disposed.
    
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
        for fence in buffer.usageFences.readWaitFences {
            fenceReleaseFunc(fence)
        }
        for fence in buffer.usageFences.writeWaitFences {
            fenceReleaseFunc(fence)
        }
    }
    
    func depositTexture(_ texture: MTLTextureReference) {
        for fence in texture.usageFences.readWaitFences {
            fenceReleaseFunc(fence)
        }
        for fence in texture.usageFences.writeWaitFences {
            fenceReleaseFunc(fence)
        }
    }
    
    func cycleFrames() {
    }
}



