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
    var heap : MTLHeap? = nil
    
    static let historyFrames = 30 // The number of frames to keep track of the memory usage for
    
    private var frameMemoryUsages = [Int](repeating: 0, count: MetalHeapResourceAllocator.historyFrames)
    
    // Semantically an 'array of sets', where the array is indexed by the aliasing indices.
    // When a resource is deposited, it overwrites the fences for all of the indices it aliases with.
    private var aliasingFences : [MetalFenceHandle] = []
    private var fenceAliasingIndices : [Int] = []
    private var nextAliasingIndex = 0
    private var resourceAliasingIndices = [ObjectIdentifier : Int]()
    
    private var waitEventValue : UInt64 = 0
    private var nextFrameWaitEventValue : UInt64 = 0
    
    let device : MTLDevice
    
    public init(device: MTLDevice) {
        self.device = device
    }
    
    func resetHeap() {
        self.aliasingFences.removeAll(keepingCapacity: true)
        self.nextAliasingIndex = 0
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

        assert(self.resourceAliasingIndices.isEmpty)
        assert(self.heap?.usedSize ?? 0 == 0)
        self.resetHeap()
    }

    private func useResource(_ resource: MTLResource) -> [MetalFenceHandle] {
        let aliasingIndex = self.nextAliasingIndex
        self.resourceAliasingIndices[ObjectIdentifier(resource)] = aliasingIndex
      
        return self.aliasingFences
    }
    
    private func depositResource(_ resource: MTLResource, fences: [MetalFenceHandle], waitEvent: MetalWaitEvent) {
        let aliasingIndex = self.resourceAliasingIndices.removeValue(forKey: ObjectIdentifier(resource))!

        guard resource.heap === self.heap else {
            return // We've reallocated the heap since this resource was allocated.
        }

        var i = 0
        while i < self.aliasingFences.count {
            if self.fenceAliasingIndices[i] < aliasingIndex {
                self.fenceAliasingIndices.remove(at: i, preservingOrder: false)
                self.aliasingFences.remove(at: i, preservingOrder: false)
            } else {
                i += 1
            }
        }
        
        self.aliasingFences.append(contentsOf: fences)
        self.fenceAliasingIndices.append(contentsOf: repeatElement(self.nextAliasingIndex, count: fences.count))
        resource.makeAliasable()

        self.nextAliasingIndex += 1
        self.nextFrameWaitEventValue = waitEvent.waitValue
    }
    
    public func collectTextureWithDescriptor(_ descriptor: MTLTextureDescriptor) -> (MTLTextureReference, [MetalFenceHandle], MetalWaitEvent) {
        let sizeAndAlign = self.device.heapTextureSizeAndAlign(descriptor: descriptor)
        let availableSize = self.heap?.maxAvailableSize(alignment: sizeAndAlign.align) ?? 0
        var textureOpt : MTLTextureReference? = nil
        if availableSize >= sizeAndAlign.size {
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
        
        let fences = self.useResource(texture.resource)
        return (texture, fences, MetalWaitEvent(waitValue: self.waitEventValue))
    }
    
    public func depositTexture(_ texture: MTLTextureReference, fences: [MetalFenceHandle], waitEvent: MetalWaitEvent) {
        self.depositResource(texture.resource, fences: fences, waitEvent: waitEvent)
    }
    
    public func collectBufferWithLength(_ length: Int, options: MTLResourceOptions) -> (MTLBufferReference, [MetalFenceHandle], MetalWaitEvent) {
        let sizeAndAlign = self.device.heapBufferSizeAndAlign(length: length, options: options)
        let availableSize = self.heap?.maxAvailableSize(alignment: sizeAndAlign.align) ?? 0
        var bufferOpt : MTLBufferReference? = nil
        if availableSize >= sizeAndAlign.size {
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

        self.nextAliasingIndex += 1
        
        let fences = self.useResource(buffer.resource)
        return (buffer, fences, MetalWaitEvent(waitValue: self.waitEventValue))
    }
    
    public func depositBuffer(_ buffer: MTLBufferReference, fences: [MetalFenceHandle], waitEvent: MetalWaitEvent) {
        self.depositResource(buffer.resource, fences: fences, waitEvent: waitEvent)
    }
}

#endif // canImport(Metal)
