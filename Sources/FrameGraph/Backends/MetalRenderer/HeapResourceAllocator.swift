//
//  HeapResourceAllocator.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 23/12/17.
//

import Utilities
import Metal
import SwiftFrameGraph

// TODO: Look at best practices in https://developer.apple.com/library/content/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/ResourceHeaps/ResourceHeaps.html
// Notably: use different heaps for different types of render targets resources, and use a separate heap for persistent resources.

// Should operate as a resource pool, but with the distinction that a resource can't be used if any of the resources it may alias against are still in use.
// When a resource is first disposed, we give it an index and make it aliasable.
// Any resource with an index higher than that cannot be used while a resource with a lower index is still in use.

protocol HeapResourceAllocator : ResourceAllocator {}

class MetalHeap {
    struct AliasingInfo {
        var aliasesThrough : Int
        var aliasedFrom = Int.max
        
        init(aliasesThrough: Int) {
            self.aliasesThrough = aliasesThrough
        }
    }
    
    struct MTLFenceReference {
        var fence : MTLFenceType
        
        // We don't need to wait on fences with the same aliasing index (aliasesThrough) and frame
        var aliasingIndex : Int
        var frame : UInt64
    }
    
    var frame : UInt64 = 0
    
    var aliasingRange = AliasingInfo(aliasesThrough: 0)
    var nextAliasingIndex = 0
    
    var resourceAliasInfo = [ObjectIdentifier : AliasingInfo]()
    var inUseResources = Set<ObjectIdentifier>()
    
    let heap : MTLHeap
    let framePurgeability : MTLPurgeableState
    
    private var buffers = [MTLBufferReference]()
    private var textures = [MTLTextureReference]()
    
    // Semantically an 'array of sets', where the array is indexed by the aliasing indices.
    // When a resource is deposited, it overwrites the fences for all of the indices it aliases with.
    // Special case: if all fences share an aliasingIndex and frame, wait on the fences associated with the resource instaed
    private var aliasingFences : [[MTLFenceReference]] = [[]]
    
    var fenceRetainFunc : ((MTLFenceType) -> Void)! = nil
    var fenceReleaseFunc : ((MTLFenceType) -> Void)! = nil
    
    public init(heap: MTLHeap, framePurgeability: MTLPurgeableState) {
        self.heap = heap
        self.framePurgeability = framePurgeability
    }
    
    public func cycleFrames() {
        assert(self.inUseResources.isEmpty)
        assert(self.aliasingRange.aliasedFrom == .max && self.aliasingRange.aliasesThrough == 0)
        
        self.heap.setPurgeableState(framePurgeability)
        self.frame = self.frame &+ 1
    }
    
    private func bufferWithLength(_ length: Int, resourceOptions: MTLResourceOptions) -> MTLBufferReference? {
        var bestIndex = -1
        var bestLength = Int.max
        
        for (i, bufferRef) in self.buffers.enumerated() {
            let buffer = bufferRef.buffer
            
            if buffer.length >= length, buffer.length < bestLength,
                resourceOptions.matches(storageMode: buffer.storageMode, cpuCacheMode: buffer.cpuCacheMode),
                self.canUseResource(buffer) {
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
                descriptor.usage            == texture.usage,
                self.canUseResource(texture) {
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
    
    private func useResource<R : MTLResourceReference>(_ resource: inout R) {
        if self.inUseResources.isEmpty {
            self.heap.setPurgeableState(.nonVolatile)
        }
        self.inUseResources.insert(ObjectIdentifier(resource.resource))
        
        if resourceAliasInfo[ObjectIdentifier(resource.resource)] == nil {
            resourceAliasInfo[ObjectIdentifier(resource.resource)] = AliasingInfo(aliasesThrough: self.nextAliasingIndex)
        }
        let aliasingInfo = resourceAliasInfo[ObjectIdentifier(resource.resource)]!
        self.aliasingRange.aliasedFrom = min(self.aliasingRange.aliasedFrom, aliasingInfo.aliasedFrom)
        self.aliasingRange.aliasesThrough = max(self.aliasingRange.aliasesThrough, aliasingInfo.aliasesThrough)
        
        // The resource needs to wait on any fences from within the aliasedFrom...aliasesThrough range
        
        let aliasingIndex = aliasingInfo.aliasesThrough
        if self.aliasingFences[aliasingIndex].allSatisfy({ $0.aliasingIndex == aliasingIndex && $0.frame == self.frame }) {
            // Do nothing; wait on the writeWaitFences already associated with the resource
        } else {
            resource.usageFences.writeWaitFences.forEach(self.fenceReleaseFunc)
            resource.usageFences.writeWaitFences.removeAll(keepingCapacity: true)
            
            let applicableFences = self.aliasingFences[aliasingIndex].lazy.filter({ $0.aliasingIndex != aliasingIndex || $0.frame != self.frame }).map { $0.fence }
            
            for fence in applicableFences {
                self.fenceRetainFunc(fence)
                resource.usageFences.writeWaitFences.append(fence)
            }
        }
    }
    
    private func depositResource<R : MTLResourceReference>(_ resource: inout R) {
        self.inUseResources.remove(ObjectIdentifier(resource.resource))
        
        var aliasingInfo = self.resourceAliasInfo[ObjectIdentifier(resource.resource)]!
        if aliasingInfo.aliasedFrom == Int.max {
            resource.resource.makeAliasable()
            
            self.nextAliasingIndex += 1
            self.aliasingFences.append([])
            
            aliasingInfo.aliasedFrom = self.nextAliasingIndex
            self.resourceAliasInfo[ObjectIdentifier(resource.resource)]!.aliasedFrom = self.nextAliasingIndex
        }
        do {
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
        
        for waitFence in resource.usageFences.readWaitFences {
            // Heap resources should not have read wait fences since they are always transient.
            self.fenceReleaseFunc(waitFence)
        }
        resource.usageFences.readWaitFences.removeAll(keepingCapacity: true)
        
        
        let processIndex : (Int, inout R) -> Void = { index, resource in
            var i = 0
            while i < self.aliasingFences[index].count {
                // Overwrite the existing fences with the most recent fence.
                // This is safe since the most recent fence will be dependant on the previous fences.
                let fence = self.aliasingFences[index][i]
                if fence.aliasingIndex != aliasingInfo.aliasesThrough || fence.frame != self.frame {
                    self.aliasingFences[index].remove(at: i, preservingOrder: false)
                    self.fenceReleaseFunc(fence.fence)
                } else {
                    i += 1
                }
            }
            
            for fence in resource.usageFences.writeWaitFences {
                self.aliasingFences[index].append(MTLFenceReference(fence: fence, aliasingIndex: aliasingInfo.aliasesThrough, frame: self.frame))
                self.fenceRetainFunc(fence)
            }
        }
        
        (0...aliasingInfo.aliasesThrough).forEach { processIndex($0, &resource) }
        (aliasingInfo.aliasedFrom..<self.nextAliasingIndex).forEach { processIndex($0, &resource) }
    }
    
    public func collectTextureWithDescriptor(_ descriptor: MTLTextureDescriptor, size: Int, alignment: Int) -> MTLTextureReference? {
        var textureOpt = self.textureFittingDescriptor(descriptor)
        if textureOpt == nil, self.nextAliasingIndex < self.aliasingRange.aliasedFrom, self.heap.maxAvailableSize(alignment: alignment) >= size {
            textureOpt = MTLTextureReference(texture: self.heap.makeTexture(descriptor: descriptor))
        }
        guard var texture = textureOpt else { return nil }
        
        self.useResource(&texture)
        
        return texture
    }
    
    public func depositTexture(_ texture: MTLTextureReference) {
        var texture = texture
        self.depositResource(&texture)
        self.textures.append(texture)
    }
    
    public func collectBufferWithLength(_ length: Int, options: MTLResourceOptions, size: Int, alignment: Int) -> MTLBufferReference? {
        var bufferOpt = self.bufferWithLength(length, resourceOptions: options)
        if bufferOpt == nil, self.nextAliasingIndex < self.aliasingRange.aliasedFrom, self.heap.maxAvailableSize(alignment: alignment) >= size {
            bufferOpt = MTLBufferReference(buffer: self.heap.makeBuffer(length: length, options: options), offset: 0)
        }
        guard var buffer = bufferOpt else { return nil }
        
        self.useResource(&buffer)
        
        return buffer
    }
    
    public func depositBuffer(_ buffer: MTLBufferReference) {
        var buffer = buffer
        self.depositResource(&buffer)
        self.buffers.append(buffer)
    }
}

class SingleFrameHeapResourceAllocator : HeapResourceAllocator, BufferAllocator, TextureAllocator {
    
    let device : MTLDevice
    let descriptor : MTLHeapDescriptor
    
    private let heapSize : Int
    private let framePurgeability : MTLPurgeableState
    
    var heaps = [MetalHeap]()

    var fenceRetainFunc : ((MTLFenceType) -> Void)! = nil {
        didSet {
            self.heaps.forEach { $0.fenceRetainFunc = fenceRetainFunc }
        }
    }
    
    var fenceReleaseFunc : ((MTLFenceType) -> Void)! = nil {
        didSet {
            self.heaps.forEach { $0.fenceReleaseFunc = fenceReleaseFunc }
        }
    }
    
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
        heap.fenceRetainFunc = self.fenceRetainFunc
        heap.fenceReleaseFunc = self.fenceReleaseFunc
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
        heap.fenceRetainFunc = self.fenceRetainFunc
        heap.fenceReleaseFunc = self.fenceReleaseFunc
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

class MultiFrameHeapResourceAllocator : HeapResourceAllocator, BufferAllocator, TextureAllocator {
    let device : MTLDevice
    let descriptor : MTLHeapDescriptor
    
    private let heapSize : Int
    private let framePurgeability : MTLPurgeableState
    
    let frameCount : Int
    
    let heaps : [SingleFrameHeapResourceAllocator]
    var currentFrameIndex = 0

    var fenceRetainFunc : ((MTLFenceType) -> Void)! = nil {
        didSet {
            self.heaps.forEach { $0.fenceRetainFunc = fenceRetainFunc }
        }
    }
    
    var fenceReleaseFunc : ((MTLFenceType) -> Void)! = nil {
        didSet {
            self.heaps.forEach { $0.fenceReleaseFunc = fenceReleaseFunc }
        }
    }
    
    public init(device: MTLDevice, defaultDescriptor descriptor: MTLHeapDescriptor, framePurgeability: MTLPurgeableState, numFrames: Int) {
        self.device = device
        self.descriptor = descriptor
        self.heapSize = descriptor.size
        self.framePurgeability = framePurgeability
        
        self.frameCount = numFrames
        self.heaps = (0..<numFrames).map { _ in SingleFrameHeapResourceAllocator(device: device, defaultDescriptor: descriptor, framePurgeability: framePurgeability) }
        
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
