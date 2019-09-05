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

class MetalHeapResourceAllocator : MetalBufferAllocator, MetalTextureAllocator {
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
    
    var heap : MTLHeap? = nil
    
    struct ResourceReference<R> {
        var resource : R
        var framesUnused : Int = 0
        
        init(resource: R) {
            self.resource = resource
        }
    }
    
    static let historyFrames = 30 // The number of frames to keep track of the memory usage for
    
    private var frameMemoryUsages = [Int](repeating: 0, count: MetalHeapResourceAllocator.historyFrames)
    
    private var buffers = [ResourceReference<MTLBufferReference>]()
    private var textures = [ResourceReference<MTLTextureReference>]()
    
    // Semantically an 'array of sets', where the array is indexed by the aliasing indices.
    // When a resource is deposited, it overwrites the fences for all of the indices it aliases with.
    private var aliasingFences : [[MTLFenceReference]] = [[]]
    
    private var waitEventValue : UInt64 = 0
    private var nextFrameWaitEventValue : UInt64 = 0
    
    let device : MTLDevice
    
    public init(device: MTLDevice) {
        self.device = device
    }
    
    func resetHeap() {
        self.aliasingFences = [[]]
        self.nextAliasingIndex = 0
        self.aliasingRange = AliasingInfo(aliasesThrough: 0)
        
        self.resourceAliasInfo.removeAll()
        self.inUseResources.removeAll()
        
        self.buffers.removeAll()
        self.textures.removeAll()
    }
    
    func reserveCapacity(_ capacity: Int) {
        if (self.heap?.currentAllocatedSize ?? 0) < capacity {
            let descriptor = MTLHeapDescriptor()
            descriptor.size = max((self.heap?.currentAllocatedSize ?? 0) * 2, capacity)
            self.heap = self.device.makeHeap(descriptor: descriptor)!
            self.resetHeap()
        }
    }
    
    public func cycleFrames() {
        assert(self.inUseResources.isEmpty)
        assert(self.aliasingRange.aliasedFrom == .max && self.aliasingRange.aliasesThrough == 0)
        
        self.waitEventValue = self.nextFrameWaitEventValue
        
        for i in (1..<MetalHeapResourceAllocator.historyFrames).reversed() {
            self.frameMemoryUsages[i] = self.frameMemoryUsages[i - 1]
        }
        self.frameMemoryUsages[0] = self.heap?.currentAllocatedSize ?? 0
        
        let memoryHighWaterMark = self.frameMemoryUsages.max()!
        
        if (self.heap?.size ?? 0) > 2 * memoryHighWaterMark {
            self.heap = nil
            self.reserveCapacity(memoryHighWaterMark)
        }
        
        do {
            var i = 0
            while i < self.buffers.count {
                self.buffers[i].framesUnused += 1
                
                if self.buffers[i].framesUnused > 5 {
                    let buffer = self.buffers.remove(at: i, preservingOrder: false)
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
                    texture.resource._texture.release()
                } else {
                    i += 1
                }
            }
        }
    }
    
    private func bufferWithLength(_ length: Int, resourceOptions: MTLResourceOptions) -> MTLBufferReference? {
        var bestIndex = -1
        var bestLength = Int.max
        
        for (i, bufferRef) in self.buffers.enumerated() {
            let buffer = bufferRef.resource.buffer
            
            if buffer.length >= length, buffer.length < bestLength,
                self.canUseResource(buffer) {
                assert(resourceOptions.matches(storageMode: buffer.storageMode, cpuCacheMode: buffer.cpuCacheMode))
                bestIndex = i
                bestLength = buffer.length
            }
        }
        
        if bestIndex != -1 {
            let resourceRef = self.buffers.remove(at: bestIndex, preservingOrder: false)
            return resourceRef.resource
        } else {
            return nil
        }
    }
    
    private func textureFittingDescriptor(_ descriptor: MTLTextureDescriptor) -> MTLTextureReference? {
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
                return resourceRef.resource
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
    
    private func useResource<R : MTLResourceReference>(_ resource: R) -> [MetalFenceHandle] {
        self.inUseResources.insert(ObjectIdentifier(resource.resource))
        
        if resourceAliasInfo[ObjectIdentifier(resource.resource)] == nil {
            resourceAliasInfo[ObjectIdentifier(resource.resource)] = AliasingInfo(aliasesThrough: self.nextAliasingIndex)
        }
        let aliasingInfo = resourceAliasInfo[ObjectIdentifier(resource.resource)]!
        self.aliasingRange.aliasedFrom = min(self.aliasingRange.aliasedFrom, aliasingInfo.aliasedFrom)
        self.aliasingRange.aliasesThrough = max(self.aliasingRange.aliasesThrough, aliasingInfo.aliasesThrough)
        
        // The resource needs to wait on any fences from within the aliasedFrom...aliasesThrough range
        
        let aliasingIndex = aliasingInfo.aliasesThrough
        let applicableFences = self.aliasingFences[aliasingIndex].lazy.filter({ $0.aliasingIndex != aliasingIndex }).map { $0.fence }
        return Array(applicableFences)
    }
    
    private func depositResource<R : MTLResourceReference>(_ resource: inout R, fences: [MetalFenceHandle], waitEvent: MetalWaitEvent) {
        self.inUseResources.remove(ObjectIdentifier(resource.resource))
        
        defer {
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

        guard var aliasingInfo = self.resourceAliasInfo[ObjectIdentifier(resource.resource)] else {
            return
        }

        if aliasingInfo.aliasedFrom == Int.max {
            resource.resource.makeAliasable()
            
            self.nextAliasingIndex += 1
            self.aliasingFences.append([])
            
            aliasingInfo.aliasedFrom = self.nextAliasingIndex
            self.resourceAliasInfo[ObjectIdentifier(resource.resource)]!.aliasedFrom = self.nextAliasingIndex
        }
        
        let processIndex : (Int, inout R, [MetalFenceHandle]) -> Void = { index, resource, fences in
            var i = 0
            while i < self.aliasingFences[index].count {
                // Overwrite the existing fences with the most recent fence.
                // This is safe since the most recent fence will be dependent on the previous fences.
                let fence = self.aliasingFences[index][i]
                if fence.aliasingIndex != aliasingInfo.aliasesThrough {
                    self.aliasingFences[index].remove(at: i, preservingOrder: false)
                } else {
                    i += 1
                }
            }
            
            for fence in fences {
                self.aliasingFences[index].append(MTLFenceReference(fence: fence, aliasingIndex: aliasingInfo.aliasesThrough))
            }
        }
        
        (0...aliasingInfo.aliasesThrough).forEach { processIndex($0, &resource, fences) }
        (aliasingInfo.aliasedFrom..<self.nextAliasingIndex).forEach { processIndex($0, &resource, fences) }
        
        self.nextFrameWaitEventValue = waitEvent.waitValue
    }
    
    public func collectTextureWithDescriptor(_ descriptor: MTLTextureDescriptor) -> (MTLTextureReference, [MetalFenceHandle], MetalWaitEvent) {
        var textureOpt = self.textureFittingDescriptor(descriptor)
        
        let sizeAndAlign = self.device.heapTextureSizeAndAlign(descriptor: descriptor)
        let availableSize = self.heap?.maxAvailableSize(alignment: sizeAndAlign.align) ?? 0
        if textureOpt == nil, self.nextAliasingIndex < self.aliasingRange.aliasedFrom, availableSize >= sizeAndAlign.size {
            assert(descriptor.usage != .unknown)
            #if os(macOS)
            textureOpt = MTLTextureReference(texture: Unmanaged.passRetained(self.heap!.makeTexture(descriptor: descriptor)!))
            #else
            textureOpt = MTLTextureReference(texture: Unmanaged.passRetained(self.heap!.makeTexture(descriptor: descriptor)))
            #endif
        }
        guard let texture = textureOpt else {
            self.reserveCapacity((self.heap?.size.roundedUpToMultiple(of: sizeAndAlign.align) ?? 0) + sizeAndAlign.size)
            return self.collectTextureWithDescriptor(descriptor)
        }
        
        let fences = self.useResource(texture)
        
        return (texture, fences, MetalWaitEvent(waitValue: self.waitEventValue))
    }
    
    public func depositTexture(_ texture: MTLTextureReference, fences: [MetalFenceHandle], waitEvent: MetalWaitEvent) {
        var resourceRef = ResourceReference(resource: texture)
        self.depositResource(&resourceRef.resource, fences: fences, waitEvent: waitEvent)
        
        if texture.resource.heap === self.heap {
            self.textures.append(resourceRef)
            self.nextFrameWaitEventValue = max(self.nextFrameWaitEventValue, waitEvent.waitValue)
        } // else we've reallocated the heap since this resource was allocated.
    }
    
    public func collectBufferWithLength(_ length: Int, options: MTLResourceOptions) -> (MTLBufferReference, [MetalFenceHandle], MetalWaitEvent) {
        var bufferOpt = self.bufferWithLength(length, resourceOptions: options)
        
        let sizeAndAlign = self.device.heapBufferSizeAndAlign(length: length, options: options)
        let availableSize = self.heap?.maxAvailableSize(alignment: sizeAndAlign.align) ?? 0
        if bufferOpt == nil, self.nextAliasingIndex < self.aliasingRange.aliasedFrom, availableSize >= sizeAndAlign.size {
            #if os(macOS)
            bufferOpt = MTLBufferReference(buffer: Unmanaged.passRetained(self.heap!.makeBuffer(length: length, options: options)!), offset: 0)
            #else
            bufferOpt = MTLBufferReference(buffer: Unmanaged.passRetained(self.heap!.makeBuffer(length: length, options: options)), offset: 0)
            #endif
        }
        guard let buffer = bufferOpt else {
            self.reserveCapacity((self.heap?.size.roundedUpToMultiple(of: sizeAndAlign.align) ?? 0) + sizeAndAlign.size)
            return self.collectBufferWithLength(length, options: options)
        }
        
        let fences = self.useResource(buffer)
        
        return (buffer, fences, MetalWaitEvent(waitValue: self.waitEventValue))
    }
    
    public func depositBuffer(_ buffer: MTLBufferReference, fences: [MetalFenceHandle], waitEvent: MetalWaitEvent) {
        var resourceRef = ResourceReference(resource: buffer)
        self.depositResource(&resourceRef.resource, fences: fences, waitEvent: waitEvent)

        if buffer.resource.heap === self.heap {
            self.buffers.append(resourceRef)
            self.nextFrameWaitEventValue = max(self.nextFrameWaitEventValue, waitEvent.waitValue)
        } // else we've reallocated the heap since this resource was allocated.
    }
}

#endif // canImport(Metal)
