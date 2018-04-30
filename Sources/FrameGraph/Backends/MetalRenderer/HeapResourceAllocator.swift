//
//  HeapResourceAllocator.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 23/12/17.
//

import Utilities
import Metal

// TODO: Look at best practices in https://developer.apple.com/library/content/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/ResourceHeaps/ResourceHeaps.html
// Notably: use different heaps for different types of render targets resources, and use a separate heap for persistent resources.

// Should operate as a resource pool, but with the distinction that a resource can't be used if any of the resources it may alias against are still in use.
// When a resource is first disposed, we give it an index and make it aliasable.
// Any resource with an index higher than that cannot be used while a resource with a lower index is still in use.

class MetalHeap {
    struct AliasingInfo {
        var aliasesThrough : Int
        var aliasedFrom = Int.max
        
        init(aliasesThrough: Int) {
            self.aliasesThrough = aliasesThrough
        }
    }
    
    var aliasingRange = AliasingInfo(aliasesThrough: 0)
    var nextAliasingIndex = 0
    
    var resourceAliasInfo = [ObjectIdentifier : AliasingInfo]()
    var inUseResources = Set<ObjectIdentifier>()
    
    let heap : MTLHeap
    let framePurgeability : MTLPurgeableState
    
    private var buffers = [MTLBuffer]()
    private var textures = [MTLTexture]()
    
    public init(heap: MTLHeap, framePurgeability: MTLPurgeableState) {
        self.heap = heap
        self.framePurgeability = framePurgeability
    }
    
    public func cycleFrames() {
        self.heap.setPurgeableState(framePurgeability)
    }
    
    private func bufferWithLength(_ length: Int, resourceOptions: MTLResourceOptions) -> MTLBuffer? {
        var bestIndex = -1
        var bestLength = Int.max
        
        for (i, buffer) in self.buffers.enumerated() {
            if !self.canUseResource(buffer) {
                continue
            }
            
            if buffer.length >= length, buffer.length < bestLength,
                resourceOptions.matches(storageMode: buffer.storageMode, cpuCacheMode: buffer.cpuCacheMode) {
                bestIndex = i
                bestLength = buffer.length
            }
        }
        
        if bestIndex != -1 {
            return self.buffers.remove(at: bestIndex, preservingOrder: false)
        } else {
            return nil
        }
    }
    
    private func textureFittingDescriptor(_ descriptor: MTLTextureDescriptor) -> MTLTexture? {
        for (i, texture) in self.textures.enumerated() {
            if !self.canUseResource(texture) {
                continue
            }
            
            if  descriptor.textureType      == texture.textureType &&
                descriptor.pixelFormat      == texture.pixelFormat &&
                descriptor.width            == texture.width &&
                descriptor.height           == texture.height &&
                descriptor.depth            == texture.depth &&
                descriptor.mipmapLevelCount == texture.mipmapLevelCount &&
                descriptor.sampleCount      == texture.sampleCount &&
                descriptor.arrayLength      == texture.arrayLength &&
                descriptor.storageMode      == texture.storageMode &&
                descriptor.cpuCacheMode     == texture.cpuCacheMode &&
                descriptor.usage            == texture.usage {
                return self.textures.remove(at: i, preservingOrder: false)
            }
        }
        
        return nil
    }
    
    
    // Condition: no other resource that may alias this resource is in use.
    // This can occur either when a resource is in use that was allocated after the makeAliasable() call
    // for the current resource, or else when a resource that was made aliasable before the current resource
    // was allocated is in use.
    private func canUseResource(_ resource: MTLResource) -> Bool {
        let aliasInfo = self.resourceAliasInfo[ObjectIdentifier(resource)]!
        return self.aliasingRange.aliasedFrom > aliasInfo.aliasesThrough &&
               aliasInfo.aliasedFrom > self.aliasingRange.aliasesThrough
    }
    
    private func useResource(_ resource: MTLResource) {
        if self.inUseResources.isEmpty {
            self.heap.setPurgeableState(.nonVolatile)
        }
        self.inUseResources.insert(ObjectIdentifier(resource))
        
        if resourceAliasInfo[ObjectIdentifier(resource)] == nil {
            resourceAliasInfo[ObjectIdentifier(resource)] = AliasingInfo(aliasesThrough: self.nextAliasingIndex)
        }
        let aliasingInfo = resourceAliasInfo[ObjectIdentifier(resource)]!
        self.aliasingRange.aliasedFrom = min(self.aliasingRange.aliasedFrom, aliasingInfo.aliasedFrom)
        self.aliasingRange.aliasesThrough = max(self.aliasingRange.aliasesThrough, aliasingInfo.aliasesThrough)
    }
    
    private func depositResource(_ resource: MTLResource) {
        self.inUseResources.remove(ObjectIdentifier(resource))
        
        let aliasingInfo = self.resourceAliasInfo[ObjectIdentifier(resource)]!
        if aliasingInfo.aliasedFrom == Int.max {
            resource.makeAliasable()
            self.nextAliasingIndex += 1
            self.resourceAliasInfo[ObjectIdentifier(resource)]!.aliasedFrom = self.nextAliasingIndex
        } else {
            var through = 0
            var from = Int.max
            for resource in self.inUseResources {
                let resourceAliasing = self.resourceAliasInfo[resource]!
                through = max(through, resourceAliasing.aliasesThrough)
                from = min(from, resourceAliasing.aliasedFrom)
            }
            self.aliasingRange.aliasedFrom = from
            self.aliasingRange.aliasesThrough = through
        }
    }
    
    public func collectTextureWithDescriptor(_ descriptor: MTLTextureDescriptor, size: Int, alignment: Int) -> MTLTexture? {
        var texture = self.textureFittingDescriptor(descriptor)
        if texture == nil, self.nextAliasingIndex < self.aliasingRange.aliasedFrom, self.heap.maxAvailableSize(alignment: alignment) >= size {
            texture = self.heap.makeTexture(descriptor: descriptor)
        }
        if let texture = texture {
            self.useResource(texture)
        }
        
        return texture
    }
    
    public func depositTexture(_ texture: MTLTexture) {
        self.textures.append(texture)
        self.depositResource(texture)
    }
    
    public func collectBufferWithLength(_ length: Int, options: MTLResourceOptions, size: Int, alignment: Int) -> MTLBuffer? {
        var buffer = self.bufferWithLength(length, resourceOptions: options)
        if buffer == nil, self.nextAliasingIndex < self.aliasingRange.aliasedFrom, self.heap.maxAvailableSize(alignment: alignment) >= size {
            buffer = self.heap.makeBuffer(length: length, options: options)
        }
        if let buffer = buffer {
            self.useResource(buffer)
        }
        return buffer
    }
    
    public func depositBuffer(_ buffer: MTLBuffer) {
        self.buffers.append(buffer)
        self.depositResource(buffer)
    }
}

public class HeapResourceAllocator : BufferAllocator, TextureAllocator {
    
    let device : MTLDevice
    let descriptor : MTLHeapDescriptor
    
    private let heapSize : Int
    private let framePurgeability : MTLPurgeableState
    
    var heaps = [MetalHeap]()
    
    public init(device: MTLDevice, defaultDescriptor descriptor: MTLHeapDescriptor, framePurgeability: MTLPurgeableState) {
        self.device = device
        self.descriptor = descriptor
        self.heapSize = descriptor.size
        self.framePurgeability = framePurgeability
        
        assert(descriptor.storageMode == .private)
    }
    
    public func collectTextureWithDescriptor(_ descriptor: MTLTextureDescriptor) -> MTLTexture {
        
        let sizeAndAlign = self.device.heapTextureSizeAndAlign(descriptor: descriptor)
        
        for heap in self.heaps {
            if let texture = heap.collectTextureWithDescriptor(descriptor, size: sizeAndAlign.size, alignment: sizeAndAlign.align) {
                return texture
            }
        }
        
        self.descriptor.size = max(sizeAndAlign.size, self.heapSize)
        let mtlHeap = self.device.makeHeap(descriptor: self.descriptor)!
        let heap = MetalHeap(heap: mtlHeap, framePurgeability: self.framePurgeability)
        self.heaps.append(heap)
        return heap.collectTextureWithDescriptor(descriptor, size: sizeAndAlign.size, alignment: sizeAndAlign.align)!
    }
    
    public func depositTexture(_ texture: MTLTexture) {
        self.heaps.first(where: { $0.heap === texture.heap })!.depositTexture(texture)
    }
    
    func collectBufferWithLength(_ length: Int, options: MTLResourceOptions) -> MTLBufferReference {
        let sizeAndAlign = self.device.heapBufferSizeAndAlign(length: length, options: options)
        
        for heap in self.heaps {
            if let buffer = heap.collectBufferWithLength(length, options: options, size: sizeAndAlign.size, alignment: sizeAndAlign.align) {
                return MTLBufferReference(buffer: buffer, offset: 0)
            }
        }
        
        self.descriptor.size = max(sizeAndAlign.size, self.heapSize)
        
        let mtlHeap = self.device.makeHeap(descriptor: self.descriptor)!
        let heap = MetalHeap(heap: mtlHeap, framePurgeability: self.framePurgeability)
        self.heaps.append(heap)
        
        return MTLBufferReference(buffer: heap.collectBufferWithLength(length, options: options, size: sizeAndAlign.size, alignment: sizeAndAlign.align)!, offset: 0)
    }
    
    func depositBuffer(_ buffer: MTLBufferReference) {
        self.heaps.first(where: { $0.heap === buffer.buffer.heap })!.depositBuffer(buffer.buffer)
    }
    
    public func cycleFrames() {
        for heap in self.heaps {
            heap.cycleFrames()
        }
    }
    
    public var totalAllocatedSize : Int {
        var total = 0
        for heap in self.heaps { total += heap.heap.currentAllocatedSize }
        return total
    }
}

