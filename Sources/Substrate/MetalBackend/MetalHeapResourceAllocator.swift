//
//  MetalHeapResourceAllocator.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 23/12/17.
//

#if canImport(Metal)

import SubstrateUtilities
@preconcurrency import Metal

// TODO: Look at best practices in https://developer.apple.com/library/content/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/ResourceHeaps/ResourceHeaps.html
// Notably: use different heaps for different types of render targets resources, and use a separate heap for persistent resources.

// Should operate as a resource pool, but with the distinction that a resource can't be used if any of the resources it may alias against are still in use.
// When a resource is first disposed, we give it an index and make it aliasable.
// Any resource with an index higher than that cannot be used while a resource with a lower index is still in use.

class MetalHeapResourceAllocator : MetalBufferAllocator, MetalTextureAllocator {
    let queue: Queue
    var heap : MTLHeap? = nil
    
    static let historyFrames = 30 // The number of frames to keep track of the memory usage for
    
    private var frameMemoryUsages = [Int](repeating: 0, count: MetalHeapResourceAllocator.historyFrames)
    
    // Semantically an 'array of sets', where the array is indexed by the aliasing indices.
    // When a resource is deposited, it overwrites the fences for all of the indices it aliases with.
    private var aliasingFences : [FenceDependency] = []
    private var fenceAliasingIndices : [Int] = []
    private var nextAliasingIndex = 0
    private var resourceAliasingIndices = [ObjectIdentifier : Int]()
    
    private var frameBuffers = [Unmanaged<MTLBuffer>]()
    private var frameTextures = [Unmanaged<MTLTexture>]()

    private var waitEvent : ContextWaitEvent = .init()
    private var nextFrameWaitEvent : ContextWaitEvent = .init()
    
    private var isPurgeable = false
    
    let device : MTLDevice
    
    public init(device: MTLDevice, queue: Queue) {
        self.device = device
        self.queue = queue
    }
    
    func resetHeap() {
        self.aliasingFences.removeAll(keepingCapacity: true)
        self.nextAliasingIndex = 0
    }
    
    func makePurgeable() {
        if let heap = self.heap {
            heap.setPurgeableState(.empty)
        }
        self.isPurgeable = true
    }
    
    func reserveCapacity(_ capacity: Int) {
        if (self.heap?.currentAllocatedSize ?? 0) < capacity {
            if let heap = self.heap {
                CommandEndActionManager.enqueue(action: .release(Unmanaged.passRetained(heap)), after: self.waitEvent.waitValue + 1, on: self.queue)
            }
            
            let descriptor = MTLHeapDescriptor()
            descriptor.size = max(((self.heap?.currentAllocatedSize ?? 0) * 3) / 2, capacity)
            if #available(OSX 10.15, iOS 13.0, tvOS 13.0, *) {
                descriptor.hazardTrackingMode = .substrateTrackedHazards
            }
            self.heap = self.device.makeHeap(descriptor: descriptor)!
#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
            self.heap!.label = "Heap for MetalHeapResourceAllocator \(ObjectIdentifier(self))"
#endif
            self.resetHeap()
        }
    }
    
    public func cycleFrames() {
        self.waitEvent = self.nextFrameWaitEvent
        self.nextFrameWaitEvent = .init()
        
        if let currentAllocatedSize = self.heap?.currentAllocatedSize, currentAllocatedSize > 0 {
            for i in (1..<MetalHeapResourceAllocator.historyFrames).reversed() {
                self.frameMemoryUsages[i] = self.frameMemoryUsages[i - 1]
            }
            self.frameMemoryUsages[0] = self.heap?.currentAllocatedSize ?? 0
            
            let memoryHighWaterMark = self.frameMemoryUsages.max()!
            
            if memoryHighWaterMark > 0, (self.heap?.size ?? 0) > 2 * memoryHighWaterMark {
                CommandEndActionManager.enqueue(action: .release(Unmanaged.passRetained(self.heap!)), after: self.waitEvent.waitValue, on: self.queue)
                self.heap = nil
                self.reserveCapacity(memoryHighWaterMark)
            }
        }
       
        self.frameBuffers.forEach { $0.release() }
        self.frameTextures.forEach { $0.release() }
        
        self.frameBuffers.removeAll(keepingCapacity: true)
        self.frameTextures.removeAll(keepingCapacity: true)

        assert(self.resourceAliasingIndices.isEmpty)
        assert(self.heap?.usedSize ?? 0 == 0)
        self.resetHeap()
    }

    private func useResource(_ resource: MTLResource) -> [FenceDependency] {
        if self.isPurgeable {
            if let heap = self.heap {
                heap.setPurgeableState(.nonVolatile)
            }
            self.isPurgeable = false
        }
        
        let aliasingIndex = self.nextAliasingIndex
        self.resourceAliasingIndices[ObjectIdentifier(resource)] = aliasingIndex
      
        return self.aliasingFences
    }
    
    private func depositResource(_ resource: MTLResource, fences: [FenceDependency], waitEvent: ContextWaitEvent) {
        CommandEndActionManager.enqueue(action: .release(Unmanaged.passRetained(resource)), after: waitEvent.waitValue, on: self.queue)
        
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
        
        if self.nextFrameWaitEvent.waitValue < waitEvent.waitValue {
            self.nextFrameWaitEvent = waitEvent
        } else {
            self.nextFrameWaitEvent.afterStages.formUnion(waitEvent.afterStages)
        }
    }
    
    public func collectTextureWithDescriptor(_ descriptor: MTLTextureDescriptor) -> (MTLTextureReference, [FenceDependency], ContextWaitEvent) {
        let sizeAndAlign = self.device.heapTextureSizeAndAlign(descriptor: descriptor)
        let availableSize = self.heap?.maxAvailableSize(alignment: sizeAndAlign.align) ?? 0
        var textureOpt : MTLTextureReference? = nil
        if availableSize >= sizeAndAlign.size {
            assert(descriptor.usage != .unknown)
            textureOpt = MTLTextureReference(texture: Unmanaged.passRetained(self.heap!.makeTexture(descriptor: descriptor)!))
        }
        guard let texture = textureOpt else {
            self.reserveCapacity((self.heap?.size.roundedUpToMultiple(of: sizeAndAlign.align) ?? 0) + sizeAndAlign.size)
            return self.collectTextureWithDescriptor(descriptor)
        }
        
        let fences = self.useResource(texture.resource)
        return (texture, fences, self.waitEvent)
    }
    
    public func depositTexture(_ texture: MTLTextureReference, fences: [FenceDependency], waitEvent: ContextWaitEvent) {
        self.depositResource(texture.resource, fences: fences, waitEvent: waitEvent)
        self.frameTextures.append(texture._texture)
    }
    
    public func collectBufferWithLength(_ length: Int, options: MTLResourceOptions) -> (MTLBufferReference, [FenceDependency], ContextWaitEvent) {
        let sizeAndAlign = self.device.heapBufferSizeAndAlign(length: length, options: options)
        let availableSize = self.heap?.maxAvailableSize(alignment: sizeAndAlign.align) ?? 0
        var bufferOpt : MTLBufferReference? = nil
        if availableSize >= sizeAndAlign.size {
            bufferOpt = MTLBufferReference(buffer: Unmanaged.passRetained(self.heap!.makeBuffer(length: length, options: options)!), offset: 0)
        }
        guard let buffer = bufferOpt else {
            self.reserveCapacity((self.heap?.size.roundedUpToMultiple(of: sizeAndAlign.align) ?? 0) + sizeAndAlign.size)
            return self.collectBufferWithLength(length, options: options)
        }

        self.nextAliasingIndex += 1
        
        let fences = self.useResource(buffer.resource)
        return (buffer, fences, self.waitEvent)
    }
    
    public func depositBuffer(_ buffer: MTLBufferReference, fences: [FenceDependency], waitEvent: ContextWaitEvent) {
        self.depositResource(buffer.resource, fences: fences, waitEvent: waitEvent)
        self.frameBuffers.append(buffer._buffer)
    }
}

#endif // canImport(Metal)
