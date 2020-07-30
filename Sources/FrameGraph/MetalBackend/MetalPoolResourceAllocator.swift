//
//  MetalPoolResourceAllocator.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 23/12/17.
//

#if canImport(Metal)

import FrameGraphUtilities
import Metal

// The pool allocators should be used only for resources that are CPU backed (i.e. that cannot be heap allocated).

final class MetalPoolResourceAllocator : MetalBufferAllocator, MetalTextureAllocator {
    
    struct ResourceReference<R> {
        let resource : R
        var waitEvent : ContextWaitEvent
        var framesUnused : Int = 0
        
        init(resource: R, waitEvent: ContextWaitEvent) {
            self.resource = resource
            self.waitEvent = waitEvent
        }
    }
    
    let device : MTLDevice
    
    private var buffers : [[ResourceReference<MTLBufferReference>]]
    private var textures : [[ResourceReference<MTLTextureReference>]]
    
    private var buffersUsedThisFrame = [ResourceReference<MTLBufferReference>]()
    private var texturesUsedThisFrame = [ResourceReference<MTLTextureReference>]()
    
    let numFrames : Int
    private var currentIndex : Int = 0
    
    init(device: MTLDevice, numFrames: Int = 1) {
        self.numFrames = numFrames
        self.device = device
        self.buffers = [[ResourceReference<MTLBufferReference>]](repeating: [ResourceReference<MTLBufferReference>](), count: numFrames)
        self.textures = [[ResourceReference<MTLTextureReference>]](repeating: [ResourceReference<MTLTextureReference>](), count: numFrames)
    }
    
    private func textureFittingDescriptor(_ descriptor: MTLTextureDescriptor) -> (MTLTextureReference, ContextWaitEvent)? {
        
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
                let resourceRef = self.textures[currentIndex].remove(at: i, preservingOrder: false)
                return (resourceRef.resource, resourceRef.waitEvent)
            }
        }
        
        return nil
    }
    
    private func bufferWithLength(_ length: Int, resourceOptions: MTLResourceOptions) -> (MTLBufferReference, ContextWaitEvent)? {
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
            let resourceRef = self.buffers[currentIndex].remove(at: bestIndex, preservingOrder: false)
            return (resourceRef.resource, resourceRef.waitEvent)
        } else {
            return nil
        }
    }
    
    func collectTextureWithDescriptor(_ descriptor: MTLTextureDescriptor) -> (MTLTextureReference, [FenceDependency], ContextWaitEvent) {
        if let texture = self.textureFittingDescriptor(descriptor) {
            return (texture.0, [], texture.1)
        } else {
            return (MTLTextureReference(texture: Unmanaged.passRetained(device.makeTexture(descriptor: descriptor)!)), [], ContextWaitEvent())
        }
    }
    
    func collectBufferWithLength(_ length: Int, options: MTLResourceOptions) -> (MTLBufferReference, [FenceDependency], ContextWaitEvent) {
        if let buffer = self.bufferWithLength(length, resourceOptions: options) {
            return (buffer.0, [], buffer.1)
        } else {
            return (MTLBufferReference(buffer: Unmanaged.passRetained(device.makeBuffer(length: length, options: options)!), offset: 0), [], ContextWaitEvent())
        }
    }
    
    func depositBuffer(_ buffer: MTLBufferReference, fences: [FenceDependency], waitEvent: ContextWaitEvent) {
        assert(fences.isEmpty)
        let resourceRef = ResourceReference(resource: buffer, waitEvent: waitEvent)
        // Delay returning the resource to the pool until the start of the next frame so we don't need to track hazards within the frame.
        // This slightly increases memory usage but greatly simplifies resource tracking, and besides, heaps should be used instead
        // for cases where memory usage is important.
        self.buffersUsedThisFrame.append(resourceRef)
    }
    
    func depositTexture(_ texture: MTLTextureReference, fences: [FenceDependency], waitEvent: ContextWaitEvent) {
        assert(fences.isEmpty)
        let resourceRef = ResourceReference(resource: texture, waitEvent: waitEvent)
        // Delay returning the resource to the pool until the start of the next frame so we don't need to track hazards within the frame.
        // This slightly increases memory usage but greatly simplifies resource tracking, and besides, heaps should be used instead
        // for cases where memory usage is important.
        self.texturesUsedThisFrame.append(resourceRef)
    }
    
    func cycleFrames() {
        do {
            var i = 0
            while i < self.buffers[self.currentIndex].count {
                self.buffers[self.currentIndex][i].framesUnused += 1
                
                if self.buffers[self.currentIndex][i].framesUnused > 5 {
                    let buffer = self.buffers[self.currentIndex].remove(at: i, preservingOrder: false)
                    buffer.resource._buffer.release()
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
                
                if self.textures[self.currentIndex][i].framesUnused > 5 {
                    let texture = self.textures[self.currentIndex].remove(at: i, preservingOrder: false)
                    texture.resource._texture.release()
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

#endif // canImport(Metal)
