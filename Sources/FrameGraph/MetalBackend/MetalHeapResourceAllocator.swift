//
//  MetalHeapResourceAllocator.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 23/12/17.
//

#if canImport(Metal)

import FrameGraphUtilities
import Metal

// TODO: Look at best practices in https://developer.apple.com/library/content/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/ResourceHeaps/ResourceHeaps.html
// Notably: use different heaps for different types of render targets resources, and use a separate heap for persistent resources.

// Should operate as a resource pool, but with the distinction that a resource can't be used if any of the resources it may alias against are still in use.
// When a resource is first disposed, we give it an index and make it aliasable.
// Any resource with an index higher than that cannot be used while a resource with a lower index is still in use.

protocol MetalHeapResourceAllocator : MetalResourceAllocator {}

// TODO: dispose (and call 'release' on) old, unused resources.

class MetalHeap {
    struct AliasingInfo {
        var aliasesThrough : Int
        var aliasedFrom = Int.max
        
        init(aliasesThrough: Int) {
            self.aliasesThrough = aliasesThrough
        }
    }
    
    struct MTLFenceReference {
        var fence : MetalFenceHandle
        
        // We don't need to wait on fences with the same aliasing index (aliasesThrough) and frame
        var aliasingIndex : Int
    }
    
    var aliasingRange = AliasingInfo(aliasesThrough: 0)
    var nextAliasingIndex = 0
    
    var resourceAliasInfo = [ObjectIdentifier : AliasingInfo]()
    var inUseResources = Set<ObjectIdentifier>()
    
    let heap : MTLHeap
    let framePurgeability : MTLPurgeableState
    
    struct ResourceReference<R> {
        var resource : R
        var fenceState : MetalResourceFences
        var framesUnused : Int = 0
        
        init(resource: R, fenceState: MetalResourceFences) {
            self.resource = resource
            self.fenceState = fenceState
        }
    }
    
    private var buffers = [ResourceReference<MTLBufferReference>]()
    private var textures = [ResourceReference<MTLTextureReference>]()
    
    // Semantically an 'array of sets', where the array is indexed by the aliasing indices.
    // When a resource is deposited, it overwrites the fences for all of the indices it aliases with.
    // Special case: if all fences share an aliasingIndex and frame, wait on the fences associated with the resource instaed
    private var aliasingFences : [[MTLFenceReference]] = [[]]
    
    public init(heap: MTLHeap, framePurgeability: MTLPurgeableState) {
        self.heap = heap
        assert(heap.storageMode == .private)
        self.framePurgeability = framePurgeability
    }
    
    public func cycleFrames() {
        assert(self.inUseResources.isEmpty)
        assert(self.aliasingRange.aliasedFrom == .max && self.aliasingRange.aliasesThrough == 0)
        
        do {
            var i = 0
            while i < self.buffers.count {
                self.buffers[i].framesUnused += 1
                
                if self.buffers[i].framesUnused > 5 {
                    let buffer = self.buffers.remove(at: i, preservingOrder: false)
                    buffer.fenceState.readWaitFence.release()
                    for fence in buffer.fenceState.writeWaitFences {
                        fence.release()
                    }
                    buffer.resource._buffer.release()
                } else {
                    i += 1
                }
            }
        }
        
        do {
            var i = 0
            while i < self.textures.count {
                self.textures[i].framesUnused += 1
                
                if self.textures[i].framesUnused > 5 {
                    let texture = self.textures.remove(at: i, preservingOrder: false)
                    texture.fenceState.readWaitFence.release()
                    for fence in texture.fenceState.writeWaitFences {
                        fence.release()
                    }
                    texture.resource._texture.release()
                } else {
                    i += 1
                }
            }
        }
        
        self.heap.setPurgeableState(framePurgeability)
    }
    
    private func bufferWithLength(_ length: Int, resourceOptions: MTLResourceOptions) -> (MTLBufferReference, MetalResourceFences)? {
        var bestIndex = -1
        var bestLength = Int.max
        
        for (i, bufferRef) in self.buffers.enumerated() {
            let buffer = bufferRef.resource.buffer
            
            if buffer.length >= length, buffer.length < bestLength,
                resourceOptions.matches(storageMode: buffer.storageMode, cpuCacheMode: buffer.cpuCacheMode),
                self.canUseResource(buffer) {
                bestIndex = i
                bestLength = buffer.length
            }
        }
        
        if bestIndex != -1 {
            let resourceRef = self.buffers.remove(at: bestIndex, preservingOrder: false)
            return (resourceRef.resource, resourceRef.fenceState)
        } else {
            return nil
        }
    }
    
    private func textureFittingDescriptor(_ descriptor: MTLTextureDescriptor) -> (MTLTextureReference, MetalResourceFences)? {
        for (i, textureRef) in self.textures.enumerated() {
            let texture = textureRef.resource.texture
            
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
                let resourceRef = self.textures.remove(at: i, preservingOrder: false)
                return (resourceRef.resource, resourceRef.fenceState)
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
    
    private func useResource<R : MTLResourceReference>(_ resource: inout R, fenceState: inout MetalResourceFences) {
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
        if self.aliasingFences[aliasingIndex].allSatisfy({ !$0.fence.isValid || ($0.aliasingIndex == aliasingIndex && $0.fence.frame == FrameGraph.currentFrameIndex) }) {
            // Do nothing; wait on the writeWaitFences already associated with the resource
        } else {
            fenceState.writeWaitFences.forEach {
                $0.release()
            }
            fenceState.writeWaitFences.removeAll(keepingCapacity: true)
            
            let applicableFences = self.aliasingFences[aliasingIndex].lazy.filter({ $0.fence.isValid && ($0.aliasingIndex != aliasingIndex || $0.fence.frame != FrameGraph.currentFrameIndex) }).map { $0.fence }
            
            for fence in applicableFences {
                fence.retain()
                fenceState.writeWaitFences.append(fence)
            }
        }
    }
    
    private func depositResource<R : MTLResourceReference>(_ resource: inout R, fences: inout MetalResourceFences) {
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
        
        fences.readWaitFence.release()
        fences.readWaitFence = .invalid
        
        
        let processIndex : (Int, inout R, inout MetalResourceFences) -> Void = { index, resource, fences in
            var i = 0
            while i < self.aliasingFences[index].count {
                // Overwrite the existing fences with the most recent fence.
                // This is safe since the most recent fence will be dependent on the previous fences.
                let fence = self.aliasingFences[index][i]
                if fence.aliasingIndex != aliasingInfo.aliasesThrough || !fence.fence.isValid || fence.fence.frame != FrameGraph.currentFrameIndex {
                    self.aliasingFences[index].remove(at: i, preservingOrder: false)
                    fence.fence.release()
                } else {
                    i += 1
                }
            }
            
            for fence in fences.writeWaitFences {
                self.aliasingFences[index].append(MTLFenceReference(fence: fence, aliasingIndex: aliasingInfo.aliasesThrough))
                fence.retain()
            }
        }
        
        (0...aliasingInfo.aliasesThrough).forEach { processIndex($0, &resource, &fences) }
        (aliasingInfo.aliasedFrom..<self.nextAliasingIndex).forEach { processIndex($0, &resource, &fences) }
    }
    
    public func collectTextureWithDescriptor(_ descriptor: MTLTextureDescriptor, size: Int, alignment: Int) -> (MTLTextureReference, MetalResourceFences)? {
        var tupleOpt = self.textureFittingDescriptor(descriptor)
        if tupleOpt == nil, self.nextAliasingIndex < self.aliasingRange.aliasedFrom, self.heap.maxAvailableSize(alignment: alignment) >= size {
            assert(descriptor.usage != .unknown)
            #if os(macOS)
            tupleOpt = (MTLTextureReference(texture: Unmanaged.passRetained(self.heap.makeTexture(descriptor: descriptor)!)),
                          MetalResourceFences())
            #else
            tupleOpt = (MTLTextureReference(texture: Unmanaged.passRetained(self.heap.makeTexture(descriptor: descriptor))),
                          MetalResourceFences())
            #endif
        }
        guard var tuple = tupleOpt else { return nil }
        
        self.useResource(&tuple.0, fenceState: &tuple.1)
        
        return tuple
    }
    
    public func depositTexture(_ texture: MTLTextureReference, fences: MetalResourceFences) {
        var resourceRef = ResourceReference(resource: texture, fenceState: fences)
        self.depositResource(&resourceRef.resource, fences: &resourceRef.fenceState)
        self.textures.append(resourceRef)
    }
    
    public func collectBufferWithLength(_ length: Int, options: MTLResourceOptions, size: Int, alignment: Int) -> (MTLBufferReference, MetalResourceFences)? {
        var tupleOpt = self.bufferWithLength(length, resourceOptions: options)
        if tupleOpt == nil, self.nextAliasingIndex < self.aliasingRange.aliasedFrom, self.heap.maxAvailableSize(alignment: alignment) >= size {
            #if os(macOS)
            tupleOpt = (MTLBufferReference(buffer: Unmanaged.passRetained(self.heap.makeBuffer(length: length, options: options)!), offset: 0),
                         MetalResourceFences())
            #else
            tupleOpt = (MTLBufferReference(buffer: Unmanaged.passRetained(self.heap.makeBuffer(length: length, options: options)), offset: 0),
                         MetalResourceFences())
            
            #endif
        }
        guard var tuple = tupleOpt else { return nil }
        
        self.useResource(&tuple.0, fenceState: &tuple.1)
        
        return tuple
    }
    
    public func depositBuffer(_ buffer: MTLBufferReference, fences: MetalResourceFences) {
        var resourceRef = ResourceReference(resource: buffer, fenceState: fences)
        self.depositResource(&resourceRef.resource, fences: &resourceRef.fenceState)
        self.buffers.append(resourceRef)
    }
}

class SingleFrameHeapResourceAllocator : MetalHeapResourceAllocator, MetalBufferAllocator, MetalTextureAllocator {
    
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
    
    func collectTextureWithDescriptor(_ descriptor: MTLTextureDescriptor) -> (MTLTextureReference, MetalResourceFences) {
        
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
    
    func depositTexture(_ texture: MTLTextureReference, fences: MetalResourceFences) {
        self.heaps.first(where: { $0.heap === texture.texture.heap })!.depositTexture(texture, fences: fences)
    }
    
    func collectBufferWithLength(_ length: Int, options: MTLResourceOptions) -> (MTLBufferReference, MetalResourceFences) {
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
    
    func depositBuffer(_ buffer: MTLBufferReference, fences: MetalResourceFences) {
        self.heaps.first(where: { $0.heap === buffer.buffer.heap })!.depositBuffer(buffer, fences: fences)
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

class MultiFrameHeapResourceAllocator : MetalHeapResourceAllocator, MetalBufferAllocator, MetalTextureAllocator {
    let device : MTLDevice
    let descriptor : MTLHeapDescriptor
    
    private let heapSize : Int
    private let framePurgeability : MTLPurgeableState
    
    let frameCount : Int
    var currentFrameIndex = 0
    
    let heaps : [SingleFrameHeapResourceAllocator]
    
    public init(device: MTLDevice, defaultDescriptor descriptor: MTLHeapDescriptor, framePurgeability: MTLPurgeableState, numFrames: Int) {
        self.device = device
        self.descriptor = descriptor
        self.heapSize = descriptor.size
        self.framePurgeability = framePurgeability
        
        self.frameCount = numFrames
        self.heaps = (0..<numFrames).map { _ in SingleFrameHeapResourceAllocator(device: device, defaultDescriptor: descriptor, framePurgeability: framePurgeability) }
        
        assert(descriptor.storageMode == .private)
    }
    
    func collectTextureWithDescriptor(_ descriptor: MTLTextureDescriptor) -> (MTLTextureReference, MetalResourceFences) {
        return self.heaps[currentFrameIndex].collectTextureWithDescriptor(descriptor)
    }
    
    func depositTexture(_ texture: MTLTextureReference, fences: MetalResourceFences) {
        self.heaps[currentFrameIndex].depositTexture(texture, fences: fences)
    }
    
    func collectBufferWithLength(_ length: Int, options: MTLResourceOptions) -> (MTLBufferReference, MetalResourceFences) {
        return self.heaps[currentFrameIndex].collectBufferWithLength(length, options: options)
    }
    
    func depositBuffer(_ buffer: MTLBufferReference, fences: MetalResourceFences) {
        self.heaps[currentFrameIndex].depositBuffer(buffer, fences: fences)
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

#endif // canImport(Metal)
