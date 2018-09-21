//
//  PoolResourceAllocator.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 23/12/17.
//

import Utilities
import Metal

// The pool allocators should be used only for resources that are CPU backed (i.e. that cannot be heap allocated).

final class PoolResourceAllocator : BufferAllocator, TextureAllocator {
    
    struct ResourceReference<R> {
        let resource : R
        var framesUnused : Int = 0
        
        init(resource: R) {
            self.resource = resource
        }
    }
    
    let device : MTLDevice
    private var buffers : [[ResourceReference<MTLBufferReference>]]
    private var textures : [[ResourceReference<MTLTextureReference>]]
    
    private var buffersUsedThisFrame = [ResourceReference<MTLBufferReference>]()
    private var texturesUsedThisFrame = [ResourceReference<MTLTextureReference>]()
    
    let numFrames : Int
    private var currentIndex : Int = 0
    
    init(device: MTLDevice, numFrames: Int) {
        self.numFrames = numFrames
        self.device = device
        self.buffers = [[ResourceReference<MTLBufferReference>]](repeating: [ResourceReference<MTLBufferReference>](), count: numFrames)
        self.textures = [[ResourceReference<MTLTextureReference>]](repeating: [ResourceReference<MTLTextureReference>](), count: numFrames)
    }
    
    private func textureFittingDescriptor(_ descriptor: MTLTextureDescriptor) -> MTLTextureReference? {
        
        for (i, textureRef) in self.textures[currentIndex].enumerated() {
            if descriptor.textureType       == textureRef.resource.texture.textureType &&
                descriptor.pixelFormat      == textureRef.resource.texture.pixelFormat &&
                descriptor.width            == textureRef.resource.texture.width &&
                descriptor.height           == textureRef.resource.texture.height &&
                descriptor.depth            == textureRef.resource.texture.depth &&
                descriptor.mipmapLevelCount == textureRef.resource.texture.mipmapLevelCount &&
                descriptor.sampleCount      == textureRef.resource.texture.sampleCount &&
                descriptor.arrayLength      == textureRef.resource.texture.arrayLength &&
                descriptor.storageMode      == textureRef.resource.texture.storageMode &&
                descriptor.cpuCacheMode     == textureRef.resource.texture.cpuCacheMode &&
                descriptor.usage            == textureRef.resource.texture.usage {
                return self.textures[currentIndex].remove(at: i, preservingOrder: false).resource
            }
        }
        
        return nil
    }
    
    private func bufferWithLength(_ length: Int, resourceOptions: MTLResourceOptions) -> MTLBufferReference? {
        var bestIndex = -1
        var bestLength = Int.max
        
        for (i, bufferRef) in self.buffers[currentIndex].enumerated() {
            if bufferRef.resource.buffer.length >= length, bufferRef.resource.buffer.length < bestLength,
            resourceOptions.matches(storageMode: bufferRef.resource.buffer.storageMode, cpuCacheMode: bufferRef.resource.buffer.cpuCacheMode) {
                bestIndex = i
                bestLength = bufferRef.resource.buffer.length
            }
        }
        
        if bestIndex != -1 {
            return self.buffers[currentIndex].remove(at: bestIndex, preservingOrder: false).resource
        } else {
            return nil
        }
    }
    
    func collectTextureWithDescriptor(_ descriptor: MTLTextureDescriptor) -> MTLTextureReference {
        if let texture = self.textureFittingDescriptor(descriptor) {
            return texture
        } else {
            return MTLTextureReference(texture: device.makeTexture(descriptor: descriptor)!)
        }
    }
    
    func collectBufferWithLength(_ length: Int, options: MTLResourceOptions) -> MTLBufferReference {
        if let buffer = self.bufferWithLength(length, resourceOptions: options) {
            return buffer
        } else {
            return MTLBufferReference(buffer: device.makeBuffer(length: length, options: options)!, offset: 0)
        }
    }
    
    func depositBuffer(_ buffer: MTLBufferReference) {
        // We can't just put the resource back into the array for the current frame, since it's not safe to use it for another buffers.count frames.
        self.buffersUsedThisFrame.append(ResourceReference(resource: buffer))
    }
    
    func depositTexture(_ texture: MTLTextureReference) {
        // We can't just put the resource back into the array for the current frame, since it's not safe to use it for another buffers.count frames.
        self.texturesUsedThisFrame.append(ResourceReference(resource: texture))
    }
    
    func cycleFrames() {
        do {
            var i = 0
            while i < self.buffers[self.currentIndex].count {
                self.buffers[self.currentIndex][i].framesUnused += 1
                
                if self.buffers[self.currentIndex][i].framesUnused > 2 {
                    self.buffers[self.currentIndex].remove(at: i, preservingOrder: false)
                } else {
                    i += 1
                }
            }
            
            self.buffers[self.currentIndex].append(contentsOf: buffersUsedThisFrame)
            self.buffersUsedThisFrame.removeAll(keepingCapacity: true)
        }
        
        do {
            var i = 0
            while i < self.textures[self.currentIndex].count {
                self.textures[self.currentIndex][i].framesUnused += 1
                
                if self.textures[self.currentIndex][i].framesUnused > 2 {
                    self.textures[self.currentIndex].remove(at: i, preservingOrder: false)
                } else {
                    i += 1
                }
            }
            
            self.textures[self.currentIndex].append(contentsOf: texturesUsedThisFrame)
            self.texturesUsedThisFrame.removeAll(keepingCapacity: true)
        }
        
        self.currentIndex = (self.currentIndex + 1) % self.numFrames
    }
}


