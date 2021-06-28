//
//  ResourceRegistries.swift
//  RenderAPI
//
//  Created by Thomas Roughton on 24/07/18.
//

import SubstrateUtilities
import Dispatch
import Foundation
import Atomics

// Registries in this file fall into two main types.
// Fixed-capacity registries (transient buffers, transient textures, and transient argument buffer arrays) have permanently-allocated storage.
// Chunk-based registries allocate storage in blocks. This avoids excessive memory usage while simultaneously ensuring that the memory for a resource is never reallocated (which would cause issues in multithreaded contexts, requiring locks for all access).

@usableFromInline final class TransientRegistryManager {
    public static let maxTransientRegistries = UInt8.bitWidth
    
    static var allocatedRegistries : UInt8 = 0
    static var lock = SpinLock()
    
    public static func allocate() -> Int {
        return self.lock.withLock {
            for i in 0..<self.allocatedRegistries.bitWidth {
                if self.allocatedRegistries & (1 << i) == 0 {
                    self.allocatedRegistries |= (1 << i)
                    
                    return i
                }
            }
            
            fatalError("Only \(Self.maxTransientRegistries) transient registries may exist at any time.")
        }
    }
    
    public static func free(_ index: Int) {
        self.lock.withLock {
            assert(self.allocatedRegistries & (1 << index) != 0, "Registry index being disposed is not allocated.")
            self.allocatedRegistries &= ~(1 << index)
        }
    }
}

@usableFromInline
protocol ResourceRegistryChunk {
    associatedtype Descriptor
    
    init()
    func deallocate()
    func initialize(index: Int, descriptor: Descriptor)
    func deinitialize(count: Int)
    
    static var itemsPerChunk: Int { get }
}

@usableFromInline class TransientChunkRegistry<Resource: ResourceProtocol, Chunk: ResourceRegistryChunk> {
    @usableFromInline class var maxChunks: Int { 2048 }
    
    @usableFromInline var lock = SpinLock()
    
    @usableFromInline let transientRegistryIndex : Int
    @usableFromInline var count = 0
    @usableFromInline let chunks : UnsafeMutablePointer<Chunk>
    @usableFromInline var allocatedChunkCount = 0
    @usableFromInline var generation : UInt8 = 0
    
    init(transientRegistryIndex: Int) {
        self.transientRegistryIndex = transientRegistryIndex
        self.chunks = .allocate(capacity: Self.maxChunks)
    }
    
    deinit {
        self.clear()
        for i in 0..<self.chunkCount {
            self.chunks[i].deallocate()
        }
        self.chunks.deallocate()
    }
    
    
    @usableFromInline
    func allocateHandle(flags: ResourceFlags) -> UInt64 {
        return self.lock.withLock {
            
            let index = self.count
            if index == self.allocatedChunkCount * Chunk.itemsPerChunk {
                self.allocateChunk(index / Chunk.itemsPerChunk)
            }
            
            assert(index <= 0x1FFFFFFF, "Too many bits required to encode the resource's index.")
            
            self.count += 1
            
            return UInt64(truncatingIfNeeded: index) |
            (UInt64(self.generation) << Resource.generationBitsRange.lowerBound) |
            (UInt64(self.transientRegistryIndex) << Resource.transientRegistryIndexBitsRange.lowerBound) |
            (UInt64(flags.rawValue) << Resource.flagBitsRange.lowerBound) |
            (UInt64(Resource.resourceType.rawValue) << Resource.typeBitsRange.lowerBound)
        }
    }
    
    @usableFromInline
    func initialize(resource: Resource, descriptor: Chunk.Descriptor) {
        let (chunkIndex, indexInChunk) = resource.index.quotientAndRemainder(dividingBy: Chunk.itemsPerChunk)
        self.chunks[chunkIndex].initialize(index: indexInChunk, descriptor: descriptor)
    }
    
    @usableFromInline
    func allocate(descriptor: Chunk.Descriptor, flags: ResourceFlags) -> UInt64 {
        let resource = Resource(handle: self.allocateHandle(flags: flags))
        self.initialize(resource: resource, descriptor: descriptor)
        return resource.handle
    }
    
    @usableFromInline var chunkCount : Int {
        if self.count == 0 { return 0 }
        let lastUsedIndex = self.count - 1
        return (lastUsedIndex / Chunk.itemsPerChunk) + 1
    }
    
    @usableFromInline
    func allocateChunk(_ index: Int) {
        assert(index < Self.maxChunks)
        assert(index == self.allocatedChunkCount)
        self.chunks.advanced(by: index).initialize(to: Chunk())
        self.allocatedChunkCount += 1
    }
    
    func clear() {
        self.lock.withLock {
            for chunkIndex in 0..<self.chunkCount {
                let countInChunk = min(self.count - chunkIndex * Chunk.itemsPerChunk, Chunk.itemsPerChunk)
                self.chunks[chunkIndex].deinitialize(count: countInChunk)
            }
            self.count = 0
            
            self.generation = self.generation &+ 1
        }
    }
}

@usableFromInline
protocol TransientFixedSizeRegistryStorage {
    associatedtype Descriptor
    init(capacity: Int)
    func deallocate()
    
    func initialize(index: Int, descriptor: Descriptor, flags: ResourceFlags)
    func deinitialize(count: Int)
}

@usableFromInline class TransientFixedSizeRegistry<Resource: ResourceProtocol, Storage: TransientFixedSizeRegistryStorage> {
    @usableFromInline let transientRegistryIndex : Int
    @usableFromInline var capacity : Int
    @usableFromInline var count = UnsafeMutablePointer<Int.AtomicRepresentation>.allocate(capacity: 1)
    @usableFromInline var generation : UInt8 = 0
    
    @usableFromInline var storage : Storage!
    
    init(transientRegistryIndex: Int) {
        self.transientRegistryIndex = transientRegistryIndex
        self.capacity = 0
    }
    
    func initialise(capacity: Int) {
        assert(self.capacity == 0)
        
        self.capacity = capacity
        
        self.count.initialize(to: Int.AtomicRepresentation(0))
        self.storage = .init(capacity: self.capacity)
    }
    
    deinit {
        self.clear()
        self.count.deallocate()
        self.storage.deallocate()
    }

    @usableFromInline
    func allocateHandle(flags: ResourceFlags) -> UInt64 {
        let index = Int.AtomicRepresentation.atomicLoadThenWrappingIncrement(at: self.count, ordering: .relaxed)
        self.ensureCapacity(index + 1)
        
        assert(index <= 0x1FFFFFFF, "Too many bits required to encode the resource's index.")
        
        return UInt64(truncatingIfNeeded: index) |
        (UInt64(self.generation) << Resource.generationBitsRange.lowerBound) |
        (UInt64(self.transientRegistryIndex) << Resource.transientRegistryIndexBitsRange.lowerBound) |
        (UInt64(flags.rawValue) << Resource.flagBitsRange.lowerBound) |
        (UInt64(Resource.resourceType.rawValue) << Resource.typeBitsRange.lowerBound)
    }
    
    @usableFromInline
    func initialize(resource: Resource, descriptor: Storage.Descriptor) {
        self.storage.initialize(index: resource.index, descriptor: descriptor, flags: resource.flags)
    }
    
    @usableFromInline
    func allocate(descriptor: Storage.Descriptor, flags: ResourceFlags) -> UInt64 {
        let resource = Resource(handle: self.allocateHandle(flags: flags))
        self.initialize(resource: resource, descriptor: descriptor)
        return resource.handle
    }
    
    @usableFromInline
    func ensureCapacity(_ capacity: Int) {
        assert(capacity <= self.capacity)
    }
    
    @usableFromInline
    func clear() {
        let count = Int.AtomicRepresentation.atomicExchange(0, at: self.count, ordering: .relaxed)
        self.storage.deinitialize(count: count)
        
        self.generation = self.generation &+ 1
        
        assert(Int.AtomicRepresentation.atomicLoad(at: self.count, ordering: .relaxed) == 0)
    }
}

@usableFromInline
protocol PersistentRegistryChunk {
    associatedtype Descriptor
    
    init()
    func deallocate()
    func initialize(index: Int, descriptor: Descriptor, heap: Heap?, flags: ResourceFlags)
    func deinitialize(index: Int)
    var usages: UnsafeMutablePointer<ChunkArray<ResourceUsage>> { get }
    var activeRenderGraphs: UnsafeMutablePointer<UInt8.AtomicRepresentation> { get }
    var generations: UnsafeMutablePointer<UInt8> { get }
    static var itemsPerChunk: Int { get }
}

@usableFromInline class PersistentRegistry<Resource: ResourceProtocol, Chunk: PersistentRegistryChunk> {
    @usableFromInline class var maxChunks: Int { 2048 }
    
    @usableFromInline var lock = SpinLock()
    
    @usableFromInline var freeIndices = RingBuffer<Int>()
    @usableFromInline var nextFreeIndex = 0
    @usableFromInline var enqueuedDisposals = [Resource]()
    @usableFromInline let chunks : UnsafeMutablePointer<Chunk>
    
    init() {
        self.chunks = .allocate(capacity: Self.maxChunks)
    }
    
    @usableFromInline
    func allocateHandle(flags: ResourceFlags) -> UInt64 {
        return self.lock.withLock {
            let index : Int
            if let reusedIndex = self.freeIndices.popFirst() {
                index = reusedIndex
            } else {
                index = self.nextFreeIndex
                if self.nextFreeIndex % Chunk.itemsPerChunk == 0 {
                    self.allocateChunk(self.nextFreeIndex / Chunk.itemsPerChunk)
                }
                self.nextFreeIndex += 1
            }
            
            let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Chunk.itemsPerChunk)
            let generation = self.chunks[chunkIndex].generations[indexInChunk]
            return UInt64(truncatingIfNeeded: index) |
            (UInt64(generation) << Resource.generationBitsRange.lowerBound) |
            (UInt64(flags.rawValue) << Resource.flagBitsRange.lowerBound) |
            (UInt64(Resource.resourceType.rawValue) << Resource.typeBitsRange.lowerBound)
        }
    }
    
    @usableFromInline
    func initialize(resource: Resource, descriptor: Chunk.Descriptor, heap: Heap?, flags: ResourceFlags) {
        let (chunkIndex, indexInChunk) = resource.index.quotientAndRemainder(dividingBy: Chunk.itemsPerChunk)
        self.chunks[chunkIndex].initialize(index: indexInChunk, descriptor: descriptor, heap: heap, flags: flags)
    }
    
    @usableFromInline
    func allocate(descriptor: Chunk.Descriptor, heap: Heap?, flags: ResourceFlags) -> UInt64 {
        let resource = Resource(handle: self.allocateHandle(flags: flags))
        self.initialize(resource: resource, descriptor: descriptor, heap: heap, flags: flags)
        return resource.handle
    }
    
    @usableFromInline var chunkCount : Int {
        let lastUsedIndex = self.nextFreeIndex - 1
        if lastUsedIndex < 0 { return 0 }
        return (lastUsedIndex / Chunk.itemsPerChunk) + 1
    }
    
    @usableFromInline
    func allocateChunk(_ index: Int) {
        assert(index < Self.maxChunks)
        self.chunks.advanced(by: index).initialize(to: Chunk())
    }
    
    private func disposeImmediately(_ resource: Resource) {
        switch resource.type {
        case .buffer:
            RenderBackend.dispose(buffer: Buffer(handle: resource.handle))
        case .texture:
            RenderBackend.dispose(texture: Texture(handle: resource.handle))
        case .argumentBuffer:
            RenderBackend.dispose(argumentBuffer: ArgumentBuffer(handle: resource.handle))
        case .argumentBufferArray:
            RenderBackend.dispose(argumentBufferArray: ArgumentBufferArray(handle: resource.handle))
        case .heap:
            RenderBackend.dispose(heap: Heap(handle: resource.handle))
        default:
            fatalError()
        }
        
        let index = resource.index
        let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Chunk.itemsPerChunk)
        
        self.chunks[chunkIndex].deinitialize(index: indexInChunk)
        self.chunks[chunkIndex].generations[indexInChunk] = self.chunks[chunkIndex].generations[indexInChunk] &+ 1
        
        self.freeIndices.append(index)
    }
    
    func processEnqueuedDisposals() {
        var i = 0
        while i < self.enqueuedDisposals.count {
            let resource = self.enqueuedDisposals[i]
            
            if !resource.isKnownInUse {
                self.disposeImmediately(resource)
                self.enqueuedDisposals.remove(at: i, preservingOrder: false)
            } else {
                i += 1
            }
        }
    }
    
    func clear(afterRenderGraph: RenderGraph) {
        self.lock.withLock {
            self.processEnqueuedDisposals()
            
            let renderGraphInactiveMask: UInt8 = ~(1 << afterRenderGraph.queue.index)
            
            for chunkIndex in 0..<self.chunkCount {
                self.chunks[chunkIndex].usages.assign(repeating: ChunkArray(), count: Chunk.itemsPerChunk)
                
                for i in 0..<Chunk.itemsPerChunk {
                    UInt8.AtomicRepresentation.atomicLoadThenBitwiseAnd(with: renderGraphInactiveMask, at: self.chunks[chunkIndex].activeRenderGraphs.advanced(by: i), ordering: .relaxed)
                }
            }
        }
    }
    
    func dispose(_ resource: Resource) {
        self.lock.withLock {
            if resource.isKnownInUse {
                self.enqueuedDisposals.append(resource)
            } else {
                self.disposeImmediately(resource)
            }
        }
    }
}

public enum TextureViewBaseInfo {
    case buffer(Buffer.TextureViewDescriptor)
    case texture(Texture.TextureViewDescriptor)
}

@usableFromInline
struct TransientTextureRegistryStorage: TransientFixedSizeRegistryStorage {
    
    @usableFromInline var descriptors : UnsafeMutablePointer<TextureDescriptor>
    @usableFromInline var usages : UnsafeMutablePointer<ChunkArray<ResourceUsage>>
    
    @usableFromInline var labels : UnsafeMutablePointer<String?>
    @usableFromInline var baseResources : UnsafeMutablePointer<Resource?>
    @usableFromInline var textureViewInfos : UnsafeMutablePointer<TextureViewBaseInfo?>
    
    @usableFromInline
    init(capacity: Int) {
        self.descriptors = UnsafeMutablePointer.allocate(capacity: capacity)
        self.usages = UnsafeMutablePointer.allocate(capacity: capacity)
        self.labels = UnsafeMutablePointer.allocate(capacity: capacity)
        self.baseResources = UnsafeMutablePointer.allocate(capacity: capacity)
        self.textureViewInfos = UnsafeMutablePointer.allocate(capacity: capacity)
    }
    
    @usableFromInline
    func deallocate() {
        self.descriptors.deallocate()
        self.usages.deallocate()
        self.labels.deallocate()
        self.baseResources.deallocate()
        self.textureViewInfos.deallocate()
    }
    
    @usableFromInline
    func initialize(index: Int, descriptor: TextureDescriptor, flags: ResourceFlags) {
        self.descriptors.advanced(by: index).initialize(to: descriptor)
        self.usages.advanced(by: index).initialize(to: ChunkArray())
        self.labels.advanced(by: index).initialize(to: nil)
        self.baseResources.advanced(by: index).initialize(to: nil)
        self.textureViewInfos.advanced(by: index).initialize(to: nil)
    }
    
    @usableFromInline
    func initialize(index: Int, descriptor: Buffer.TextureViewDescriptor, baseResource: Buffer) {
        self.descriptors.advanced(by: index).initialize(to: descriptor.descriptor)
        self.usages.advanced(by: index).initialize(to: ChunkArray())
        self.labels.advanced(by: index).initialize(to: nil)
        self.baseResources.advanced(by: index).initialize(to: Resource(baseResource))
        self.textureViewInfos.advanced(by: index).initialize(to: .buffer(descriptor))
    }
    
    @usableFromInline
    func initialize(index: Int, viewDescriptor: Texture.TextureViewDescriptor, baseResource: Texture) {
        var descriptor = baseResource.descriptor
        descriptor.pixelFormat = viewDescriptor.pixelFormat
        descriptor.textureType = viewDescriptor.textureType
        if viewDescriptor.slices.lowerBound != -1 {
            descriptor.arrayLength = viewDescriptor.slices.count
        }
        if viewDescriptor.levels.lowerBound != -1 {
            descriptor.mipmapLevelCount = viewDescriptor.levels.count
        }
        self.descriptors.advanced(by: index).initialize(to: descriptor)
        self.usages.advanced(by: index).initialize(to:  ChunkArray())
        self.labels.advanced(by: index).initialize(to: nil)
        self.baseResources.advanced(by: index).initialize(to: Resource(baseResource))
        self.textureViewInfos.advanced(by: index).initialize(to: .texture(viewDescriptor))
    }
    
    @usableFromInline
    func deinitialize(count: Int) {
        self.descriptors.deinitialize(count: count)
        self.usages.deinitialize(count: count)
        self.labels.deinitialize(count: count)
        self.baseResources.deinitialize(count: count)
        self.textureViewInfos.deinitialize(count: count)
    }
}

@usableFromInline final class TransientTextureRegistry: TransientFixedSizeRegistry<Texture, TransientTextureRegistryStorage> {
    @usableFromInline static let instances = (0..<TransientRegistryManager.maxTransientRegistries).map { i in TransientTextureRegistry(transientRegistryIndex: i) }
    
    @usableFromInline
    func allocate(descriptor: Buffer.TextureViewDescriptor, baseResource: Buffer, flags: ResourceFlags) -> UInt64 {
        let index = Int.AtomicRepresentation.atomicLoadThenWrappingIncrement(at: self.count, ordering: .relaxed)
        self.ensureCapacity(index + 1)
        assert(index <= 0x1FFFFFFF, "Too many bits required to encode the resource's index.")
        
        self.storage.initialize(index: index, descriptor: descriptor, baseResource: baseResource)
        
        baseResource.descriptor.usageHint.formUnion(.textureView)
        
        return UInt64(truncatingIfNeeded: index) |
        (UInt64(self.generation) << Resource.generationBitsRange.lowerBound) |
        (UInt64(self.transientRegistryIndex) << Resource.transientRegistryIndexBitsRange.lowerBound) |
        (UInt64(flags.rawValue) << Resource.flagBitsRange.lowerBound) |
        (UInt64(Texture.resourceType.rawValue) << Resource.typeBitsRange.lowerBound)
    }
    
    @usableFromInline
    func allocate(descriptor viewDescriptor: Texture.TextureViewDescriptor, baseResource: Texture, flags: ResourceFlags) -> UInt64 {
        let index = Int.AtomicRepresentation.atomicLoadThenWrappingIncrement(at: self.count, ordering: .relaxed)
        self.ensureCapacity(index + 1)
        assert(index <= 0x1FFFFFFF, "Too many bits required to encode the resource's index.")
        
        self.storage.initialize(index: index, viewDescriptor: viewDescriptor, baseResource: baseResource)
        baseResource.descriptor.usageHint.formUnion(.pixelFormatView)
        
        return UInt64(truncatingIfNeeded: index) |
        (UInt64(self.generation) << Resource.generationBitsRange.lowerBound) |
        (UInt64(self.transientRegistryIndex) << Resource.transientRegistryIndexBitsRange.lowerBound) |
        (UInt64(flags.rawValue) << Resource.flagBitsRange.lowerBound) |
        (UInt64(Texture.resourceType.rawValue) << Resource.typeBitsRange.lowerBound)
    }
}

@usableFromInline
struct TransientBufferRegistryStorage: TransientFixedSizeRegistryStorage {
    @usableFromInline var descriptors : UnsafeMutablePointer<BufferDescriptor>! = nil
    @usableFromInline var deferredSliceActions : UnsafeMutablePointer<[DeferredBufferSlice]>! = nil
    @usableFromInline var usages : UnsafeMutablePointer<ChunkArray<ResourceUsage>>! = nil
    @usableFromInline var labels : UnsafeMutablePointer<String?>! = nil
    
    @usableFromInline
    init(capacity: Int) {
        self.descriptors = UnsafeMutablePointer.allocate(capacity: capacity)
        self.deferredSliceActions = UnsafeMutablePointer.allocate(capacity: capacity)
        self.usages = UnsafeMutablePointer.allocate(capacity: capacity)
        self.labels = UnsafeMutablePointer.allocate(capacity: capacity)
    }
    
    @usableFromInline
    func deallocate() {
        self.descriptors?.deallocate()
        self.deferredSliceActions?.deallocate()
        self.usages?.deallocate()
        self.labels?.deallocate()
    }
    
    @usableFromInline
    func initialize(index: Int, descriptor: BufferDescriptor, flags: ResourceFlags) {
        self.descriptors.advanced(by: index).initialize(to: descriptor)
        self.deferredSliceActions.advanced(by: index).initialize(to: [])
        self.usages.advanced(by: index).initialize(to: ChunkArray())
        self.labels.advanced(by: index).initialize(to: nil)
    }
    
    @usableFromInline
    func deinitialize(count: Int) {
        self.descriptors.deinitialize(count: count)
        self.deferredSliceActions.deinitialize(count: count)
        self.usages.deinitialize(count: count)
        self.labels.deinitialize(count: count)
    }
}

@usableFromInline final class TransientBufferRegistry: TransientFixedSizeRegistry<Buffer, TransientBufferRegistryStorage> {
    @usableFromInline static let instances = (0..<TransientRegistryManager.maxTransientRegistries).map { i in TransientBufferRegistry(transientRegistryIndex: i) }
}

@usableFromInline struct PersistentBufferRegistryChunk: PersistentRegistryChunk {
    @usableFromInline static let itemsPerChunk = 256
    
    @usableFromInline let stateFlags : UnsafeMutablePointer<ResourceStateFlags>
    /// The index that must be completed on the GPU for each queue before the CPU can read from this resource's memory.
    @usableFromInline let readWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
    /// The index that must be completed on the GPU for each queue before the CPU can write to this resource's memory.
    @usableFromInline let writeWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
    /// The RenderGraphs that are currently using this resource.
    @usableFromInline let activeRenderGraphs : UnsafeMutablePointer<UInt8.AtomicRepresentation>
    @usableFromInline let descriptors : UnsafeMutablePointer<BufferDescriptor>
    @usableFromInline let usages : UnsafeMutablePointer<ChunkArray<ResourceUsage>>
    @usableFromInline let heaps : UnsafeMutablePointer<Heap?>
    @usableFromInline let generations : UnsafeMutablePointer<UInt8>
    @usableFromInline let labels : UnsafeMutablePointer<String?>
    
    @usableFromInline
    init() {
        self.stateFlags = .allocate(capacity: Self.itemsPerChunk)
        self.readWaitIndices = .allocate(capacity: Self.itemsPerChunk)
        self.writeWaitIndices = .allocate(capacity: Self.itemsPerChunk)
        self.activeRenderGraphs = .allocate(capacity: Self.itemsPerChunk)
        self.descriptors = .allocate(capacity: Self.itemsPerChunk)
        self.usages = .allocate(capacity: Self.itemsPerChunk)
        self.heaps = .allocate(capacity: Self.itemsPerChunk)
        self.generations = .allocate(capacity: Self.itemsPerChunk)
        self.labels = .allocate(capacity: Self.itemsPerChunk)
        
        self.generations.initialize(repeating: 0, count: Self.itemsPerChunk)
    }
    
    @usableFromInline
    func deallocate() {
        self.stateFlags.deallocate()
        self.readWaitIndices.deallocate()
        self.writeWaitIndices.deallocate()
        self.activeRenderGraphs.deallocate()
        self.descriptors.deallocate()
        self.usages.deallocate()
        self.heaps.deallocate()
        self.generations.deallocate()
        self.labels.deallocate()
    }
    
    @usableFromInline
    func initialize(index: Int, descriptor: BufferDescriptor, heap: Heap?, flags: ResourceFlags) {
        self.stateFlags.advanced(by: index).initialize(to: [])
        self.readWaitIndices.advanced(by: index).initialize(to: SIMD8(repeating: 0))
        self.writeWaitIndices.advanced(by: index).initialize(to: SIMD8(repeating: 0))
        self.activeRenderGraphs.advanced(by: index).initialize(to: UInt8.AtomicRepresentation(0))
        self.descriptors.advanced(by: index).initialize(to: descriptor)
        self.usages.advanced(by: index).initialize(to: ChunkArray())
        self.heaps.advanced(by: index).initialize(to: heap)
        self.labels.advanced(by: index).initialize(to: nil)
    }
    
    @usableFromInline
    func deinitialize(index: Int) {
        self.stateFlags.advanced(by: index).deinitialize(count: 1)
        self.readWaitIndices.advanced(by: index).deinitialize(count: 1)
        self.writeWaitIndices.advanced(by: index).deinitialize(count: 1)
        self.activeRenderGraphs.advanced(by: index).deinitialize(count: 1)
        self.descriptors.advanced(by: index).deinitialize(count: 1)
        self.heaps.advanced(by: index).deinitialize(count: 1)
        self.labels.advanced(by: index).deinitialize(count: 1)
    }
}

@usableFromInline final class PersistentBufferRegistry: PersistentRegistry<Buffer, PersistentBufferRegistryChunk> {
    @usableFromInline static let instance = PersistentBufferRegistry()
    public typealias Chunk = PersistentBufferRegistryChunk
}

@usableFromInline
struct PersistentTextureRegistryChunk: PersistentRegistryChunk {
    @usableFromInline static let itemsPerChunk = 256
    
    @usableFromInline let stateFlags : UnsafeMutablePointer<ResourceStateFlags>
    /// The index that must be completed on the GPU for each queue before the CPU can read from this resource's memory.
    @usableFromInline let readWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
    /// The index that must be completed on the GPU for each queue before the CPU can write to this resource's memory.
    @usableFromInline let writeWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
    /// The RenderGraphs that are currently using this resource.
    @usableFromInline let activeRenderGraphs : UnsafeMutablePointer<UInt8.AtomicRepresentation>
    @usableFromInline let descriptors : UnsafeMutablePointer<TextureDescriptor>
    @usableFromInline let usages : UnsafeMutablePointer<ChunkArray<ResourceUsage>>
    @usableFromInline let heaps : UnsafeMutablePointer<Heap?>
    @usableFromInline let generations : UnsafeMutablePointer<UInt8>
    @usableFromInline let labels : UnsafeMutablePointer<String?>
    
    @usableFromInline
    init() {
        self.stateFlags = .allocate(capacity: Self.itemsPerChunk)
        self.readWaitIndices = .allocate(capacity: Self.itemsPerChunk)
        self.writeWaitIndices = .allocate(capacity: Self.itemsPerChunk)
        self.activeRenderGraphs = .allocate(capacity: Self.itemsPerChunk)
        self.descriptors = .allocate(capacity: Self.itemsPerChunk)
        self.usages = .allocate(capacity: Self.itemsPerChunk)
        self.heaps = .allocate(capacity: Self.itemsPerChunk)
        self.generations = .allocate(capacity: Self.itemsPerChunk)
        self.labels = .allocate(capacity: Self.itemsPerChunk)
        
        self.generations.initialize(repeating: 0, count: Self.itemsPerChunk)
    }
    
    @usableFromInline
    func deallocate() {
        self.stateFlags.deallocate()
        self.readWaitIndices.deallocate()
        self.writeWaitIndices.deallocate()
        self.activeRenderGraphs.deallocate()
        self.descriptors.deallocate()
        self.usages.deallocate()
        self.heaps.deallocate()
        self.generations.deallocate()
        self.labels.deallocate()
    }
    
    @usableFromInline
    func initialize(index: Int, descriptor: TextureDescriptor, heap: Heap?, flags: ResourceFlags) {
        self.stateFlags.advanced(by: index).initialize(to: [])
        self.readWaitIndices.advanced(by: index).initialize(to: SIMD8(repeating: 0))
        self.writeWaitIndices.advanced(by: index).initialize(to: SIMD8(repeating: 0))
        self.activeRenderGraphs.advanced(by: index).initialize(to: UInt8.AtomicRepresentation(0))
        self.descriptors.advanced(by: index).initialize(to: descriptor)
        self.usages.advanced(by: index).initialize(to: ChunkArray())
        self.heaps.advanced(by: index).initialize(to: heap)
        self.labels.advanced(by: index).initialize(to: nil)
    }
    
    @usableFromInline
    func deinitialize(index: Int) {
        self.stateFlags.advanced(by: index).deinitialize(count: 1)
        self.readWaitIndices.advanced(by: index).deinitialize(count: 1)
        self.writeWaitIndices.advanced(by: index).deinitialize(count: 1)
        self.activeRenderGraphs.advanced(by: index).deinitialize(count: 1)
        self.descriptors.advanced(by: index).deinitialize(count: 1)
        self.heaps.advanced(by: index).deinitialize(count: 1)
        self.labels.advanced(by: index).deinitialize(count: 1)
    }
}

@usableFromInline final class PersistentTextureRegistry: PersistentRegistry<Texture, PersistentTextureRegistryChunk> {
    @usableFromInline static let instance = PersistentTextureRegistry()
    public typealias Chunk = PersistentTextureRegistryChunk
}

@usableFromInline
struct TransientArgumentBufferRegistryChunk: ResourceRegistryChunk {
    @usableFromInline static let itemsPerChunk = 256
    
    @usableFromInline let usages : UnsafeMutablePointer<ChunkArray<ResourceUsage>>
    @usableFromInline let encoders : UnsafeMutablePointer<UnsafeRawPointer.AtomicOptionalRepresentation> // Some opaque backend type that can construct the argument buffer
    @usableFromInline let enqueuedBindings : UnsafeMutablePointer<ExpandingBuffer<(FunctionArgumentKey, Int, ArgumentBuffer.ArgumentResource)>>
    @usableFromInline let bindings : UnsafeMutablePointer<ExpandingBuffer<(ResourceBindingPath, ArgumentBuffer.ArgumentResource)>>
    @usableFromInline let sourceArrays : UnsafeMutablePointer<ArgumentBufferArray?>
    
    @usableFromInline let labels : UnsafeMutablePointer<String?>
    
    @usableFromInline
    typealias Descriptor = Void
    
    @usableFromInline
    init() {
        self.usages = .allocate(capacity: Self.itemsPerChunk)
        self.encoders = .allocate(capacity: Self.itemsPerChunk)
        self.enqueuedBindings = .allocate(capacity: Self.itemsPerChunk)
        self.bindings = .allocate(capacity: Self.itemsPerChunk)
        self.sourceArrays = .allocate(capacity: Self.itemsPerChunk)
        self.labels = .allocate(capacity: Self.itemsPerChunk)
    }
    
    @usableFromInline
    func deallocate() {
        self.usages.deallocate()
        self.encoders.deallocate()
        self.enqueuedBindings.deallocate()
        self.bindings.deallocate()
        self.sourceArrays.deallocate()
        self.labels.deallocate()
    }
    
    @usableFromInline
    func initialize(index indexInChunk: Int, descriptor: Void) {
        self.usages.advanced(by: indexInChunk).initialize(to: ChunkArray())
        self.encoders.advanced(by: indexInChunk).initialize(to: UnsafeRawPointer.AtomicOptionalRepresentation(nil))
        self.enqueuedBindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
        self.bindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
        self.sourceArrays.advanced(by: indexInChunk).initialize(to: nil)
        self.labels.advanced(by: indexInChunk).initialize(to: nil)
    }
    
    @usableFromInline
    func deinitialize(count: Int) {
        self.usages.deinitialize(count: count)
        self.encoders.deinitialize(count: count)
        self.enqueuedBindings.deinitialize(count: count)
        self.bindings.deinitialize(count: count)
        self.sourceArrays.deinitialize(count: count)
        self.labels.deinitialize(count: count)
    }
}

// Unlike the other transient registries, the transient argument buffer registry is chunk-based.
// This is because the number of argument buffers used within a frame can @usableFromInline vary dramatically, and so a pre-assigned maximum is more likely to be hit.
@usableFromInline final class TransientArgumentBufferRegistry: TransientChunkRegistry<ArgumentBuffer, TransientArgumentBufferRegistryChunk> {
    @usableFromInline static let instances = (0..<TransientRegistryManager.maxTransientRegistries).map { i in TransientArgumentBufferRegistry(transientRegistryIndex: i) }
    
    @usableFromInline override class var maxChunks: Int { 2048 }
    
    @usableFromInline let inlineDataAllocator : ExpandingBuffer<UInt8> = .init()
    
    @usableFromInline typealias Chunk = TransientArgumentBufferRegistryChunk
    
    @usableFromInline
    func allocate(flags: ResourceFlags, sourceArray: ArgumentBufferArray) -> UInt64 {
        return self.lock.withLock {
            let index = self.count
            if index == self.allocatedChunkCount * Chunk.itemsPerChunk {
                self.allocateChunk(index / Chunk.itemsPerChunk)
            }
            
            assert(index <= 0x1FFFFFFF, "Too many bits required to encode the resource's index.")
            
            let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Chunk.itemsPerChunk)
            
            self.chunks[chunkIndex].usages.advanced(by: indexInChunk).initialize(to: ChunkArray())
            self.chunks[chunkIndex].encoders.advanced(by: indexInChunk).initialize(to: UnsafeRawPointer.AtomicOptionalRepresentation(nil))
            self.chunks[chunkIndex].enqueuedBindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
            self.chunks[chunkIndex].bindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
            self.chunks[chunkIndex].sourceArrays.advanced(by: indexInChunk).initialize(to: sourceArray)
            self.chunks[chunkIndex].labels.advanced(by: indexInChunk).initialize(to: nil)
            self.count += 1
            
            return UInt64(truncatingIfNeeded: index) | (UInt64(self.generation) << Resource.generationBitsRange.lowerBound) | UInt64(self.transientRegistryIndex) << Resource.transientRegistryIndexBitsRange.lowerBound
        }
    }
}

@usableFromInline final class PersistentArgumentBufferRegistry {
    @usableFromInline static let instance = PersistentArgumentBufferRegistry()
    
    @usableFromInline
    struct Chunk {
        @usableFromInline static let itemsPerChunk = 2048
        
        @usableFromInline let usages : UnsafeMutablePointer<ChunkArray<ResourceUsage>>
        @usableFromInline let encoders : UnsafeMutablePointer<UnsafeRawPointer.AtomicOptionalRepresentation> // Some opaque backend type that can construct the argument buffer
        @usableFromInline let enqueuedBindings : UnsafeMutablePointer<ExpandingBuffer<(FunctionArgumentKey, Int, ArgumentBuffer.ArgumentResource)>>
        @usableFromInline let bindings : UnsafeMutablePointer<ExpandingBuffer<(ResourceBindingPath, ArgumentBuffer.ArgumentResource)>>
        @usableFromInline let inlineDataStorage : UnsafeMutablePointer<Data>
        @usableFromInline let sourceArrays : UnsafeMutablePointer<ArgumentBufferArray>
        @usableFromInline let heaps : UnsafeMutablePointer<Heap?>
        /// The index that must be completed on the GPU for each queue before the CPU can read from this resource's memory.
        @usableFromInline let readWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The index that must be completed on the GPU for each queue before the CPU can write to this resource's memory.
        @usableFromInline let writeWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The RenderGraphs that are currently using this resource.
        @usableFromInline let activeRenderGraphs : UnsafeMutablePointer<UInt8.AtomicRepresentation>
        @usableFromInline let generations : UnsafeMutablePointer<UInt8>
        
        @usableFromInline let labels : UnsafeMutablePointer<String?>
        
        init() {
            self.usages = .allocate(capacity: Chunk.itemsPerChunk)
            self.encoders = .allocate(capacity: Chunk.itemsPerChunk)
            self.enqueuedBindings = .allocate(capacity: Chunk.itemsPerChunk)
            self.bindings = .allocate(capacity: Chunk.itemsPerChunk)
            self.inlineDataStorage = .allocate(capacity: Chunk.itemsPerChunk)
            self.sourceArrays = .allocate(capacity: Chunk.itemsPerChunk)
            self.heaps = .allocate(capacity: Chunk.itemsPerChunk)
            self.readWaitIndices = .allocate(capacity: Chunk.itemsPerChunk)
            self.writeWaitIndices = .allocate(capacity: Chunk.itemsPerChunk)
            self.activeRenderGraphs = .allocate(capacity: Chunk.itemsPerChunk)
            self.generations = .allocate(capacity: Chunk.itemsPerChunk)
            self.labels = .allocate(capacity: Chunk.itemsPerChunk)
            
            self.generations.initialize(repeating: 0, count: Chunk.itemsPerChunk)
        }
        
        func deallocate() {
            self.usages.deallocate()
            self.encoders.deallocate()
            self.enqueuedBindings.deallocate()
            self.bindings.deallocate()
            self.inlineDataStorage.deallocate()
            self.sourceArrays.deallocate()
            self.heaps.deallocate()
            self.readWaitIndices.deallocate()
            self.writeWaitIndices.deallocate()
            self.activeRenderGraphs.deallocate()
            self.generations.deallocate()
            self.labels.deallocate()
        }
    }
    
    @usableFromInline static let maxChunks = 256
    
    @usableFromInline var lock = SpinLock()
    
    @usableFromInline var freeIndices = RingBuffer<Int>()
    @usableFromInline var nextFreeIndex = 0
    
    @usableFromInline var enqueuedDisposals = [ArgumentBuffer]()
    @usableFromInline let chunks : UnsafeMutablePointer<Chunk>
    
    init() {
        self.chunks = .allocate(capacity: Self.maxChunks)
    }
    
    @usableFromInline
    func allocate(flags: ResourceFlags) -> UInt64 {
        return self.lock.withLock {
            let index : Int
            if let reusedIndex = self.freeIndices.popFirst() {
                index = reusedIndex
            } else {
                index = self.nextFreeIndex
                if index % Chunk.itemsPerChunk == 0 {
                    self.allocateChunk(index / Chunk.itemsPerChunk)
                }
                self.nextFreeIndex += 1
            }
            
            let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Chunk.itemsPerChunk)
            
            self.chunks[chunkIndex].usages.advanced(by: indexInChunk).initialize(to: ChunkArray())
            self.chunks[chunkIndex].encoders.advanced(by: indexInChunk).initialize(to: UnsafeRawPointer.AtomicOptionalRepresentation(nil))
            self.chunks[chunkIndex].enqueuedBindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
            self.chunks[chunkIndex].bindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
            self.chunks[chunkIndex].inlineDataStorage.advanced(by: indexInChunk).initialize(to: Data())
            self.chunks[chunkIndex].heaps.advanced(by: indexInChunk).initialize(to: nil)
            self.chunks[chunkIndex].readWaitIndices.advanced(by: indexInChunk).initialize(to: SIMD8(repeating: 0))
            self.chunks[chunkIndex].writeWaitIndices.advanced(by: indexInChunk).initialize(to: SIMD8(repeating: 0))
            self.chunks[chunkIndex].activeRenderGraphs.advanced(by: indexInChunk).initialize(to: UInt8.AtomicRepresentation(0))
            self.chunks[chunkIndex].labels.advanced(by: indexInChunk).initialize(to: nil)
            
            let generation = self.chunks[chunkIndex].generations[indexInChunk]
            
            return UInt64(truncatingIfNeeded: index) |
            (UInt64(generation) << Resource.generationBitsRange.lowerBound) |
            (UInt64(flags.rawValue) << Resource.flagBitsRange.lowerBound) |
            (UInt64(ResourceType.argumentBuffer.rawValue) << Resource.typeBitsRange.lowerBound)
        }
    }
    
    @usableFromInline
    func allocate(flags: ResourceFlags, sourceArray: ArgumentBufferArray) -> UInt64 {
        return self.lock.withLock {
            let index : Int
            if let reusedIndex = self.freeIndices.popFirst() {
                index = reusedIndex
            } else {
                index = self.nextFreeIndex
                if index % Chunk.itemsPerChunk == 0 {
                    self.allocateChunk(index / Chunk.itemsPerChunk)
                }
                self.nextFreeIndex += 1
            }
            
            let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Chunk.itemsPerChunk)
            
            
            self.chunks[chunkIndex].usages.advanced(by: indexInChunk).initialize(to: ChunkArray())
            self.chunks[chunkIndex].encoders.advanced(by: indexInChunk).initialize(to: UnsafeRawPointer.AtomicOptionalRepresentation(nil))
            self.chunks[chunkIndex].enqueuedBindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
            self.chunks[chunkIndex].bindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
            self.chunks[chunkIndex].inlineDataStorage.advanced(by: indexInChunk).initialize(to: Data())
            self.chunks[chunkIndex].sourceArrays.advanced(by: indexInChunk).initialize(to: sourceArray)
            self.chunks[chunkIndex].heaps.advanced(by: indexInChunk).initialize(to: nil)
            self.chunks[chunkIndex].readWaitIndices.advanced(by: indexInChunk).deinitialize(count: 1)
            self.chunks[chunkIndex].writeWaitIndices.advanced(by: indexInChunk).deinitialize(count: 1)
            self.chunks[chunkIndex].activeRenderGraphs.advanced(by: indexInChunk).deinitialize(count: 1)
            self.chunks[chunkIndex].labels.advanced(by: indexInChunk).initialize(to: nil)
            
            let generation = self.chunks[chunkIndex].generations[indexInChunk]
            
            return UInt64(truncatingIfNeeded: index) |
            (UInt64(generation) << Resource.generationBitsRange.lowerBound) |
            (UInt64(flags.rawValue) << Resource.flagBitsRange.lowerBound) |
            (UInt64(ResourceType.argumentBufferArray.rawValue) << Resource.typeBitsRange.lowerBound)
        }
    }
    
    @usableFromInline var chunkCount : Int {
        let lastUsedIndex = self.nextFreeIndex - 1
        if lastUsedIndex < 0 { return 0 }
        return (lastUsedIndex / Chunk.itemsPerChunk) + 1
    }
    
    @usableFromInline
    func allocateChunk(_ index: Int) {
        assert(index < Self.maxChunks)
        self.chunks.advanced(by: index).initialize(to: Chunk())
    }
    
    private func disposeImmediately(argumentBuffer: ArgumentBuffer) {
        RenderBackend.dispose(argumentBuffer: argumentBuffer)
        
        let index = argumentBuffer.index
        let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Chunk.itemsPerChunk)
        
        self.chunks[chunkIndex].usages.advanced(by: indexInChunk).deinitialize(count: 1)
        self.chunks[chunkIndex].encoders.advanced(by: indexInChunk).deinitialize(count: 1)
        self.chunks[chunkIndex].enqueuedBindings.advanced(by: indexInChunk).deinitialize(count: 1)
        self.chunks[chunkIndex].bindings.advanced(by: indexInChunk).deinitialize(count: 1)
        self.chunks[chunkIndex].inlineDataStorage.advanced(by: indexInChunk).deinitialize(count: 1)
        self.chunks[chunkIndex].sourceArrays.advanced(by: indexInChunk).deinitialize(count: 1)
        self.chunks[chunkIndex].heaps.advanced(by: indexInChunk).deinitialize(count: 1)
        self.chunks[chunkIndex].labels.advanced(by: indexInChunk).deinitialize(count: 1)
        
        self.chunks[chunkIndex].generations[indexInChunk] = self.chunks[chunkIndex].generations[indexInChunk] &+ 1
        
        self.freeIndices.append(index)
    }
    
    
    func processEnqueuedDisposals() {
        var i = 0
        while i < self.enqueuedDisposals.count {
            let argumentBuffer = self.enqueuedDisposals[i]
            
            if !argumentBuffer.isKnownInUse {
                self.disposeImmediately(argumentBuffer: argumentBuffer)
                self.enqueuedDisposals.remove(at: i, preservingOrder: false)
            } else {
                i += 1
            }
        }
    }
    
    func clear(afterRenderGraph: RenderGraph) {
        self.lock.withLock {
            let renderGraphInactiveMask: UInt8 = ~(1 << afterRenderGraph.queue.index)
            
            for chunkIndex in 0..<self.chunkCount {
                self.chunks[chunkIndex].usages.assign(repeating: ChunkArray(), count: Chunk.itemsPerChunk)
                
                for i in 0..<Chunk.itemsPerChunk {
                    UInt8.AtomicRepresentation.atomicLoadThenBitwiseAnd(with: renderGraphInactiveMask, at: self.chunks[chunkIndex].activeRenderGraphs.advanced(by: i), ordering: .relaxed)
                }
            }
            
            self.processEnqueuedDisposals()
        }
    }
    
    func dispose(_ buffer: ArgumentBuffer) {
        self.lock.withLock {
            if buffer.isKnownInUse {
                self.enqueuedDisposals.append(buffer)
            } else {
                self.disposeImmediately(argumentBuffer: buffer)
            }
        }
    }
}

@usableFromInline final class TransientArgumentBufferArrayRegistry {
    @usableFromInline static let instances = (0..<TransientRegistryManager.maxTransientRegistries).map { i in TransientArgumentBufferArrayRegistry(transientRegistryIndex: i) }
    
    @usableFromInline let transientRegistryIndex: Int
    @usableFromInline var capacity : Int
    @usableFromInline var count = UnsafeMutablePointer<Int.AtomicRepresentation>.allocate(capacity: 1)
    @usableFromInline var generation : UInt8 = 0
    
    @usableFromInline var bindings : UnsafeMutablePointer<[ArgumentBuffer?]>! = nil
    @usableFromInline var labels : UnsafeMutablePointer<String?>! = nil
    
    init(transientRegistryIndex: Int) {
        self.transientRegistryIndex = transientRegistryIndex
        self.capacity = 0
    }
    
    func initialise(capacity: Int) {
        self.capacity = capacity
        self.count.initialize(to: Int.AtomicRepresentation(0))
        self.bindings = .allocate(capacity: capacity)
        self.labels = .allocate(capacity: capacity)
    }
    
    deinit {
        self.clear()
        self.bindings?.deallocate()
        self.labels?.deallocate()
    }
    
    @usableFromInline
    func allocate(flags: ResourceFlags) -> UInt64 {
        let index = Int.AtomicRepresentation.atomicLoadThenWrappingIncrement(at: self.count, ordering: .relaxed)
        assert(index < self.capacity)
        assert(index <= 0x1FFFFFFF, "Too many bits required to encode the resource's index.")
        
        self.bindings.advanced(by: index).initialize(to: [])
        self.labels.advanced(by: index).initialize(to: nil)
            
        return UInt64(truncatingIfNeeded: index) |
        (UInt64(self.generation) << Resource.generationBitsRange.lowerBound) |
        (UInt64(self.transientRegistryIndex) << Resource.transientRegistryIndexBitsRange.lowerBound) |
        (UInt64(flags.rawValue) << Resource.flagBitsRange.lowerBound) |
        (UInt64(ResourceType.argumentBufferArray.rawValue) << Resource.typeBitsRange.lowerBound)
    }
    
    @usableFromInline
    func clear() {
        let count = Int.AtomicRepresentation.atomicLoad(at: self.count, ordering: .relaxed)
        
        self.bindings.deinitialize(count: count)
        self.labels.deinitialize(count: count)
        let oldCount = Int.AtomicRepresentation.atomicExchange(0, at: self.count, ordering: .relaxed)
        assert(oldCount == count)
        
        self.generation = self.generation &+ 1
    }
}

@usableFromInline final class PersistentArgumentBufferArrayRegistry {
    @usableFromInline static let instance = PersistentArgumentBufferArrayRegistry()
    
    @usableFromInline
    struct Chunk {
        @usableFromInline static let itemsPerChunk = 256
        
        @usableFromInline let bindings : UnsafeMutablePointer<[ArgumentBuffer?]>
        @usableFromInline let heaps : UnsafeMutablePointer<Heap?>
        @usableFromInline let generations : UnsafeMutablePointer<UInt8>
        @usableFromInline let labels : UnsafeMutablePointer<String?>
        
        init() {
            self.bindings = .allocate(capacity: Chunk.itemsPerChunk)
            self.heaps = .allocate(capacity: Chunk.itemsPerChunk)
            self.generations = .allocate(capacity: Chunk.itemsPerChunk)
            self.labels = .allocate(capacity: Chunk.itemsPerChunk)
            
            self.generations.initialize(repeating: 0, count: Chunk.itemsPerChunk)
        }
        
        func deallocate() {
            self.bindings.deallocate()
            self.heaps.deallocate()
            self.generations.deallocate()
            self.labels.deallocate()
        }
    }
    
    @usableFromInline static let maxChunks = 2048
    
    @usableFromInline var lock = SpinLock()
    
    @usableFromInline var freeIndices = RingBuffer<Int>()
    @usableFromInline var nextFreeIndex = 0
    
    @usableFromInline var enqueuedDisposals = [ArgumentBufferArray]()
    @usableFromInline let chunks : UnsafeMutablePointer<Chunk>
    
    init() {
        self.chunks = .allocate(capacity: Self.maxChunks)
    }
    
    func allocate(flags: ResourceFlags) -> UInt64 {
        return self.lock.withLock {
            // FIXME: We should figure out how to handle enqueued disposals/resource tracking for argument buffer arrays.
            
            let index : Int
            if let reusedIndex = self.freeIndices.popFirst() {
                index = reusedIndex
            } else {
                index = self.nextFreeIndex
                if index % Chunk.itemsPerChunk == 0 {
                    self.allocateChunk(index / Chunk.itemsPerChunk)
                }
                self.nextFreeIndex += 1
            }
            
            let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Chunk.itemsPerChunk)
            
            self.chunks[chunkIndex].bindings.advanced(by: indexInChunk).initialize(to: [])
            self.chunks[chunkIndex].heaps.advanced(by: indexInChunk).initialize(to: nil)
            self.chunks[chunkIndex].labels.advanced(by: indexInChunk).initialize(to: nil)
            
            let generation = self.chunks[chunkIndex].generations[indexInChunk]
            
            return UInt64(truncatingIfNeeded: index) |
            (UInt64(generation) << Resource.generationBitsRange.lowerBound) |
            (UInt64(flags.rawValue) << Resource.flagBitsRange.lowerBound) |
            (UInt64(ResourceType.argumentBufferArray.rawValue) << Resource.typeBitsRange.lowerBound)
        }
    }
    
    @usableFromInline
    var chunkCount : Int {
        let lastUsedIndex = self.nextFreeIndex - 1
        if lastUsedIndex < 0 { return 0 }
        return (lastUsedIndex / Chunk.itemsPerChunk) + 1
    }
    
    @usableFromInline
    func allocateChunk(_ index: Int) {
        assert(index < Self.maxChunks)
        self.chunks.advanced(by: index).initialize(to: Chunk())
    }
    
    func disposeImmediately(argumentBufferArray: ArgumentBufferArray) {
        RenderBackend.dispose(argumentBufferArray: argumentBufferArray)
        
        let index = argumentBufferArray.index
        let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Chunk.itemsPerChunk)
        
        self.chunks[chunkIndex].bindings.advanced(by: indexInChunk).deinitialize(count: 1)
        self.chunks[chunkIndex].bindings.advanced(by: indexInChunk).deinitialize(count: 1)
        self.chunks[chunkIndex].labels.advanced(by: indexInChunk).deinitialize(count: 1)
        
        self.chunks[chunkIndex].generations[indexInChunk] = self.chunks[chunkIndex].generations[indexInChunk] &+ 1
        
        self.freeIndices.append(index)
    }
    
    func processEnqueuedDisposals() {
        var i = 0
        while i < self.enqueuedDisposals.count {
            let buffer = self.enqueuedDisposals[i]
            
            if !buffer.isKnownInUse {
                self.disposeImmediately(argumentBufferArray: buffer)
                self.enqueuedDisposals.remove(at: i, preservingOrder: false)
            } else {
                i += 1
            }
        }
    }
    
    func clear(afterRenderGraph: RenderGraph) {
        self.lock.withLock {
            self.processEnqueuedDisposals()
        }
    }
    
    func dispose(_ buffer: ArgumentBufferArray) {
        self.lock.withLock {
            if buffer.isKnownInUse {
                self.enqueuedDisposals.append(buffer)
            } else {
                self.disposeImmediately(argumentBufferArray: buffer)
            }
        }
    }
}


@usableFromInline final class HeapRegistry {
    
    @usableFromInline static let instance = HeapRegistry()
    
    @usableFromInline
    struct Chunk {
        @usableFromInline static let itemsPerChunk = 256
        
        @usableFromInline let descriptors : UnsafeMutablePointer<HeapDescriptor>
        @usableFromInline let generations : UnsafeMutablePointer<UInt8>
        @usableFromInline let labels : UnsafeMutablePointer<String?>
        @usableFromInline let childResources : UnsafeMutablePointer<Set<Resource>>
        /// The RenderGraphs that are currently using this resource.
        @usableFromInline let activeRenderGraphs : UnsafeMutablePointer<UInt8.AtomicRepresentation>
        
        init() {
            self.descriptors = .allocate(capacity: Chunk.itemsPerChunk)
            self.generations = .allocate(capacity: Chunk.itemsPerChunk)
            self.labels = .allocate(capacity: Chunk.itemsPerChunk)
            self.childResources = .allocate(capacity: Chunk.itemsPerChunk)
            self.activeRenderGraphs = .allocate(capacity: Chunk.itemsPerChunk)
            
            self.generations.initialize(repeating: 0, count: Chunk.itemsPerChunk)
        }
        
        func deallocate() {
            self.descriptors.deallocate()
            self.generations.deallocate()
            self.labels.deallocate()
            self.childResources.deallocate()
            self.activeRenderGraphs.deallocate()
        }
    }
    
    @usableFromInline static let maxChunks = 2048
    
    @usableFromInline var lock = SpinLock()
    
    @usableFromInline var freeIndices = RingBuffer<Int>()
    @usableFromInline var nextFreeIndex = 0
    @usableFromInline var enqueuedDisposals = [Heap]()
    @usableFromInline let chunks : UnsafeMutablePointer<Chunk>
    
    init() {
        self.chunks = .allocate(capacity: Self.maxChunks)
    }
    
    @usableFromInline
    func allocate(descriptor: HeapDescriptor, flags: ResourceFlags) -> UInt64 {
        return self.lock.withLock {
            let index : Int
            if let reusedIndex = self.freeIndices.popFirst() {
                index = reusedIndex
            } else {
                index = self.nextFreeIndex
                if self.nextFreeIndex % Chunk.itemsPerChunk == 0 {
                    self.allocateChunk(self.nextFreeIndex / Chunk.itemsPerChunk)
                }
                self.nextFreeIndex += 1
            }
            
            let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Chunk.itemsPerChunk)
            self.chunks[chunkIndex].descriptors.advanced(by: indexInChunk).initialize(to: descriptor)
            self.chunks[chunkIndex].labels.advanced(by: indexInChunk).initialize(to: nil)
            self.chunks[chunkIndex].childResources.advanced(by: indexInChunk).initialize(to: [])
            self.chunks[chunkIndex].activeRenderGraphs.advanced(by: indexInChunk).initialize(to: UInt8.AtomicRepresentation(0))
            
            let generation = self.chunks[chunkIndex].generations[indexInChunk]
            
            return UInt64(truncatingIfNeeded: index) |
            (UInt64(generation) << Resource.generationBitsRange.lowerBound) |
            (UInt64(flags.rawValue) << Resource.flagBitsRange.lowerBound) |
            (UInt64(ResourceType.heap.rawValue) << Resource.typeBitsRange.lowerBound)
        }
    }
    
    @usableFromInline var chunkCount : Int {
        let lastUsedIndex = self.nextFreeIndex - 1
        if lastUsedIndex < 0 { return 0 }
        return (lastUsedIndex / Chunk.itemsPerChunk) + 1
    }
    
    @usableFromInline
    func allocateChunk(_ index: Int) {
        assert(index < Self.maxChunks)
        self.chunks.advanced(by: index).initialize(to: Chunk())
    }
    
    private func disposeImmediately(heap: Heap) {
        RenderBackend.dispose(heap: heap)
        
        let index = heap.index
        let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Chunk.itemsPerChunk)
        
        self.chunks[chunkIndex].descriptors.advanced(by: indexInChunk).deinitialize(count: 1)
        self.chunks[chunkIndex].labels.advanced(by: indexInChunk).deinitialize(count: 1)
        self.chunks[chunkIndex].childResources.advanced(by: indexInChunk).deinitialize(count: 1)
        self.chunks[chunkIndex].activeRenderGraphs.deinitialize(count: 1)
        
        self.chunks[chunkIndex].generations[indexInChunk] = self.chunks[chunkIndex].generations[indexInChunk] &+ 1
        
        self.freeIndices.append(index)
    }
    
    func processEnqueuedDisposals() {
        var i = 0
        while i < self.enqueuedDisposals.count {
            let heap = self.enqueuedDisposals[i]
            
            if !heap.isKnownInUse {
                self.disposeImmediately(heap: heap)
                self.enqueuedDisposals.remove(at: i, preservingOrder: false)
            } else {
                i += 1
            }
        }
    }
    
    func clear(afterRenderGraph: RenderGraph) {
        self.lock.withLock {
            let renderGraphInactiveMask: UInt8 = ~(1 << afterRenderGraph.queue.index)
            
            for chunkIndex in 0..<self.chunkCount {
                for i in 0..<Chunk.itemsPerChunk {
                    UInt8.AtomicRepresentation.atomicLoadThenBitwiseAnd(with: renderGraphInactiveMask, at: self.chunks[chunkIndex].activeRenderGraphs.advanced(by: i), ordering: .relaxed)
                }
            }
            
            self.processEnqueuedDisposals()
        }
    }
    
    func dispose(_ heap: Heap) {
        self.lock.withLock {
            if heap.isKnownInUse {
                self.enqueuedDisposals.append(heap)
            } else {
                self.disposeImmediately(heap: heap)
            }
        }
    }
}
