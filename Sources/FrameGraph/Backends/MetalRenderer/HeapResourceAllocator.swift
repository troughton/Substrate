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

// FIXME: aliasing resources need to have fences between the use of any resources they alias with.

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
    
    private var buffers = [MTLBufferReference]()
    private var textures = [MTLTextureReference]()
    
    public init(heap: MTLHeap, framePurgeability: MTLPurgeableState) {
        self.heap = heap
        self.framePurgeability = framePurgeability
    }
    
    public func cycleFrames() {
        self.heap.setPurgeableState(framePurgeability)
    }
    
    private func bufferWithLength(_ length: Int, resourceOptions: MTLResourceOptions) -> MTLBufferReference? {
        var bestIndex = -1
        var bestLength = Int.max
        
        for (i, bufferRef) in self.buffers.enumerated() {
            let buffer = bufferRef.buffer
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
    
    private func textureFittingDescriptor(_ descriptor: MTLTextureDescriptor) -> MTLTextureReference? {
        for (i, textureRef) in self.textures.enumerated() {
            let texture = textureRef.texture
            
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
    
    public func collectTextureWithDescriptor(_ descriptor: MTLTextureDescriptor, size: Int, alignment: Int) -> MTLTextureReference? {
        var texture = self.textureFittingDescriptor(descriptor)
        if texture == nil, self.nextAliasingIndex < self.aliasingRange.aliasedFrom, self.heap.maxAvailableSize(alignment: alignment) >= size {
            texture = MTLTextureReference(texture: self.heap.makeTexture(descriptor: descriptor))
        }
        if let texture = texture {
            self.useResource(texture.texture)
        }
        
        return texture
    }
    
    public func depositTexture(_ texture: MTLTextureReference) {
        self.textures.append(texture)
        self.depositResource(texture.texture)
    }
    
    public func collectBufferWithLength(_ length: Int, options: MTLResourceOptions, size: Int, alignment: Int) -> MTLBufferReference? {
        var buffer = self.bufferWithLength(length, resourceOptions: options)
        if buffer == nil, self.nextAliasingIndex < self.aliasingRange.aliasedFrom, self.heap.maxAvailableSize(alignment: alignment) >= size {
            buffer = MTLBufferReference(buffer: self.heap.makeBuffer(length: length, options: options), offset: 0)
        }
        if let buffer = buffer {
            self.useResource(buffer.buffer)
        }
        return buffer
    }
    
    public func depositBuffer(_ buffer: MTLBufferReference) {
        self.buffers.append(buffer)
        self.depositResource(buffer.buffer)
    }
}

class HeapResourceAllocator : BufferAllocator, TextureAllocator {
    
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
    
    func collectTextureWithDescriptor(_ descriptor: MTLTextureDescriptor) -> MTLTextureReference {
        
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
    
    func depositTexture(_ texture: MTLTextureReference) {
        self.heaps.first(where: { $0.heap === texture.texture.heap })!.depositTexture(texture)
    }
    
    func collectBufferWithLength(_ length: Int, options: MTLResourceOptions) -> MTLBufferReference {
        let sizeAndAlign = self.device.heapBufferSizeAndAlign(length: length, options: options)
        
        for heap in self.heaps {
            if let bufferRef = heap.collectBufferWithLength(length, options: options, size: sizeAndAlign.size, alignment: sizeAndAlign.align) {
                return bufferRef
            }
        }
        
        self.descriptor.size = max(sizeAndAlign.size, self.heapSize)
        
        let mtlHeap = self.device.makeHeap(descriptor: self.descriptor)!
        let heap = MetalHeap(heap: mtlHeap, framePurgeability: self.framePurgeability)
        self.heaps.append(heap)
        
        return heap.collectBufferWithLength(length, options: options, size: sizeAndAlign.size, alignment: sizeAndAlign.align)!
    }
    
    func depositBuffer(_ buffer: MTLBufferReference) {
        self.heaps.first(where: { $0.heap === buffer.buffer.heap })!.depositBuffer(buffer)
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

class MultiFrameHeapResourceAllocator : BufferAllocator, TextureAllocator {
    let device : MTLDevice
    let descriptor : MTLHeapDescriptor
    
    private let heapSize : Int
    private let framePurgeability : MTLPurgeableState
    
    let frameCount : Int
    
    let heaps : [HeapResourceAllocator]
    var currentFrameIndex = 0
    
    public init(device: MTLDevice, defaultDescriptor descriptor: MTLHeapDescriptor, framePurgeability: MTLPurgeableState, numFrames: Int) {
        self.device = device
        self.descriptor = descriptor
        self.heapSize = descriptor.size
        self.framePurgeability = framePurgeability
        
        self.frameCount = numFrames
        self.heaps = (0..<numFrames).map { _ in HeapResourceAllocator(device: device, defaultDescriptor: descriptor, framePurgeability: framePurgeability) }
        
        assert(descriptor.storageMode == .private)
    }
    
    func collectTextureWithDescriptor(_ descriptor: MTLTextureDescriptor) -> MTLTextureReference {
        return self.heaps[currentFrameIndex].collectTextureWithDescriptor(descriptor)
    }
    
    func depositTexture(_ texture: MTLTextureReference) {
        self.heaps[currentFrameIndex].depositTexture(texture)
    }
    
    func collectBufferWithLength(_ length: Int, options: MTLResourceOptions) -> MTLBufferReference {
        return self.heaps[currentFrameIndex].collectBufferWithLength(length, options: options)
    }
    
    func depositBuffer(_ buffer: MTLBufferReference) {
        self.heaps[currentFrameIndex].depositBuffer(buffer)
    }
    
    public func cycleFrames() {
        self.heaps[currentFrameIndex].cycleFrames()
        
        self.currentFrameIndex = (self.currentFrameIndex &+ 1) % self.frameCount
    }
    
    public var totalAllocatedSize : Int {
        var total = 0
        for heap in self.heaps { total += heap.totalAllocatedSize }
        return total
    }
}
