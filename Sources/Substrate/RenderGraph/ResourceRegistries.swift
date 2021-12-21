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

// We use TransientRegistryArray rather than a regular array so that the compiler can optimise away retains/releases by knowing that the registries are immortal.
struct TransientRegistryArray<T: TransientRegistry> {
    let registry0: T
    let registry1: T
    let registry2: T
    let registry3: T
    let registry4: T
    let registry5: T
    let registry6: T
    let registry7: T
    
    init() {
        self.registry0 = .init(transientRegistryIndex: 0)
        self.registry1 = .init(transientRegistryIndex: 1)
        self.registry2 = .init(transientRegistryIndex: 2)
        self.registry3 = .init(transientRegistryIndex: 3)
        self.registry4 = .init(transientRegistryIndex: 4)
        self.registry5 = .init(transientRegistryIndex: 5)
        self.registry6 = .init(transientRegistryIndex: 6)
        self.registry7 = .init(transientRegistryIndex: 7)
    }
    
    subscript(index: Int) -> T {
        precondition((0..<8).contains(index))
        return withUnsafeBytes(of: self) { buffer in
            return buffer.baseAddress!.assumingMemoryBound(to: T.self)[index]
        }
    }
}

final class TransientRegistryManager {
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

protocol ResourceProperties {
    associatedtype Descriptor
    init(capacity: Int)
    func deallocate()
    func initialize(index: Int, descriptor: Descriptor, heap: Heap?, flags: ResourceFlags)
    func deinitialize(from index: Int, count: Int)
}

protocol SharedResourceProperties: ResourceProperties {
    var usagesOptional: UnsafeMutablePointer<ChunkArray<ResourceUsage>>? { get }
}

protocol PersistentResourceProperties: ResourceProperties {
    var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { get }
}

struct EmptyProperties<Descriptor>: PersistentResourceProperties & SharedResourceProperties {
    init(capacity: Int) {}
    func deallocate() {}
    func initialize(index: Int, descriptor: Descriptor, heap: Heap?, flags: ResourceFlags) {}
    func deinitialize(from index: Int, count: Int) {}
    
    var usagesOptional: UnsafeMutablePointer<ChunkArray<ResourceUsage>>? { nil }
    var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { nil }
}

protocol TransientRegistry {
    associatedtype Resource: ResourceProtocolImpl
    init(transientRegistryIndex: Int)
    func allocateHandle(flags: ResourceFlags) -> Resource
    func initialize(resource: Resource, descriptor: Resource.Descriptor)
    func allocate(descriptor: Resource.Descriptor, flags: ResourceFlags) -> Resource
    func clear()
    
    var generation: UInt8 { get }
    func sharedProperties(index: Int) -> (chunk: Resource.SharedProperties, indexInChunk: Int)
    func transientProperties(index: Int) -> (chunk: Resource.TransientProperties, indexInChunk: Int)
}

class TransientChunkRegistry<Resource: ResourceProtocolImpl>: TransientRegistry {
    class var maxChunks: Int { 2048 }
    
    var lock = SpinLock()
    
    let transientRegistryIndex : Int
    var count = 0
    let sharedPropertyChunks : UnsafeMutablePointer<Resource.SharedProperties>
    let transientPropertyChunks : UnsafeMutablePointer<Resource.TransientProperties>
    var allocatedChunkCount = 0
    var generation : UInt8 = 0
    
    required init(transientRegistryIndex: Int) {
        self.transientRegistryIndex = transientRegistryIndex
        self.sharedPropertyChunks = .allocate(capacity: Self.maxChunks)
        self.transientPropertyChunks = .allocate(capacity: Self.maxChunks)
    }
    
    deinit {
        self.clear()
        for i in 0..<self.chunkCount {
            self.sharedPropertyChunks[i].deallocate()
            self.transientPropertyChunks[i].deallocate()
        }
        self.sharedPropertyChunks.deallocate()
        self.transientPropertyChunks.deallocate()
    }
    
    func sharedProperties(index: Int) -> (chunk: Resource.SharedProperties, indexInChunk: Int) {
        let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Resource.itemsPerChunk)
        return (self.sharedPropertyChunks[chunkIndex], indexInChunk)
    }
    
    func transientProperties(index: Int) -> (chunk: Resource.TransientProperties, indexInChunk: Int) {
        let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Resource.itemsPerChunk)
        return (self.transientPropertyChunks[chunkIndex], indexInChunk)
    }
    
    func allocateHandle(flags: ResourceFlags) -> Resource {
        return self.lock.withLock {
            
            let index = self.count
            if index == self.allocatedChunkCount * Resource.itemsPerChunk {
                self.allocateChunk(index / Resource.itemsPerChunk)
            }
            
            assert(index <= 0x1FFFFFFF, "Too many bits required to encode the resource's index.")
            
            self.count += 1
            
            let handle = UInt64(truncatingIfNeeded: index) |
            (UInt64(self.generation) << Resource.generationBitsRange.lowerBound) |
            (UInt64(self.transientRegistryIndex) << Resource.transientRegistryIndexBitsRange.lowerBound) |
            (UInt64(flags.rawValue) << Resource.flagBitsRange.lowerBound) |
            (UInt64(Resource.resourceType.rawValue) << Resource.typeBitsRange.lowerBound)
            return Resource(handle: handle)
        }
    }
    
    func initialize(resource: Resource, descriptor: Resource.Descriptor) {
        let (chunkIndex, indexInChunk) = resource.index.quotientAndRemainder(dividingBy: Resource.itemsPerChunk)
        self.sharedPropertyChunks[chunkIndex].initialize(index: indexInChunk, descriptor: descriptor, heap: nil, flags: resource.flags)
        self.transientPropertyChunks[chunkIndex].initialize(index: indexInChunk, descriptor: descriptor, heap: nil, flags: resource.flags)
    }
    
    func allocate(descriptor: Resource.Descriptor, flags: ResourceFlags) -> Resource {
        let resource = self.allocateHandle(flags: flags)
        self.initialize(resource: resource, descriptor: descriptor)
        return resource
    }
    
    var chunkCount : Int {
        if self.count == 0 { return 0 }
        let lastUsedIndex = self.count - 1
        return (lastUsedIndex / Resource.itemsPerChunk) + 1
    }
    
    func allocateChunk(_ index: Int) {
        assert(index < Self.maxChunks)
        assert(index == self.allocatedChunkCount)
        self.sharedPropertyChunks.advanced(by: index).initialize(to: .init(capacity: Resource.itemsPerChunk))
        self.transientPropertyChunks.advanced(by: index).initialize(to: .init(capacity: Resource.itemsPerChunk))
        self.allocatedChunkCount += 1
    }
    
    func clear() {
        self.lock.withLock {
            for chunkIndex in 0..<self.chunkCount {
                let countInChunk = min(self.count - chunkIndex * Resource.itemsPerChunk, Resource.itemsPerChunk)
                self.sharedPropertyChunks[chunkIndex].deinitialize(from: 0, count: countInChunk)
                self.transientPropertyChunks[chunkIndex].deinitialize(from: 0, count: countInChunk)
            }
            self.count = 0
            
            self.generation = self.generation &+ 1
        }
    }
}

class TransientFixedSizeRegistry<Resource: ResourceProtocolImpl>: TransientRegistry {
    let transientRegistryIndex : Int
    var capacity : Int
    var count = UnsafeMutablePointer<Int.AtomicRepresentation>.allocate(capacity: 1)
    var generation : UInt8 = 0
    
    var sharedStorage : Resource.SharedProperties!
    var transientStorage : Resource.TransientProperties!
    
    required init(transientRegistryIndex: Int) {
        self.transientRegistryIndex = transientRegistryIndex
        self.capacity = 0
    }
    
    func initialise(capacity: Int) {
        assert(self.capacity == 0)
        
        self.capacity = capacity
        
        self.count.initialize(to: Int.AtomicRepresentation(0))
        self.sharedStorage = .init(capacity: self.capacity)
        self.transientStorage = .init(capacity: self.capacity)
    }
    
    deinit {
        self.clear()
        self.count.deallocate()
        self.sharedStorage.deallocate()
        self.transientStorage.deallocate()
    }
    
    func sharedProperties(index: Int) -> (chunk: Resource.SharedProperties, indexInChunk: Int) {
        return (self.sharedStorage, index)
    }
    
    func transientProperties(index: Int) -> (chunk: Resource.TransientProperties, indexInChunk: Int) {
        return (self.transientStorage, index)
    }
    
    func allocateHandle(flags: ResourceFlags) -> Resource {
        let index = Int.AtomicRepresentation.atomicLoadThenWrappingIncrement(at: self.count, ordering: .relaxed)
        self.ensureCapacity(index + 1)
        
        assert(index <= 0x1FFFFFFF, "Too many bits required to encode the resource's index.")
        
        let handle = UInt64(truncatingIfNeeded: index) |
        (UInt64(self.generation) << Resource.generationBitsRange.lowerBound) |
        (UInt64(self.transientRegistryIndex) << Resource.transientRegistryIndexBitsRange.lowerBound) |
        (UInt64(flags.rawValue) << Resource.flagBitsRange.lowerBound) |
        (UInt64(Resource.resourceType.rawValue) << Resource.typeBitsRange.lowerBound)
        return Resource(handle: handle)
    }
    
    func initialize(resource: Resource, descriptor: Resource.Descriptor) {
        self.sharedStorage.initialize(index: resource.index, descriptor: descriptor, heap: nil, flags: resource.flags)
        self.transientStorage.initialize(index: resource.index, descriptor: descriptor, heap: nil, flags: resource.flags)
    }
    
    func allocate(descriptor: Resource.Descriptor, flags: ResourceFlags) -> Resource {
        let resource = self.allocateHandle(flags: flags)
        self.initialize(resource: resource, descriptor: descriptor)
        return resource
    }
    
    func ensureCapacity(_ capacity: Int) {
        assert(capacity <= self.capacity)
    }
    
    func clear() {
        let count = Int.AtomicRepresentation.atomicExchange(0, at: self.count, ordering: .relaxed)
        self.sharedStorage.deinitialize(from: 0, count: count)
        self.transientStorage.deinitialize(from: 0, count: count)
        
        self.generation = self.generation &+ 1
        
        assert(Int.AtomicRepresentation.atomicLoad(at: self.count, ordering: .relaxed) == 0)
    }
}

class PersistentRegistry<Resource: ResourceProtocolImpl> {
    class var maxChunks: Int { 2048 }
    
    var lock = SpinLock()
    
    var freeIndices = RingBuffer<Int>()
    var nextFreeIndex = 0
    var enqueuedDisposals = [Resource]()
    let sharedChunks : UnsafeMutablePointer<Resource.SharedProperties>
    let persistentChunks : UnsafeMutablePointer<Resource.PersistentProperties>
    let generationChunks : UnsafeMutablePointer<UnsafeMutablePointer<UInt8>>
    
    init() {
        self.sharedChunks = .allocate(capacity: Self.maxChunks)
        self.persistentChunks = .allocate(capacity: Self.maxChunks)
        self.generationChunks = .allocate(capacity: Self.maxChunks)
    }
    
    func allocateHandle(flags: ResourceFlags) -> Resource {
        return self.lock.withLock {
            let index : Int
            if let reusedIndex = self.freeIndices.popFirst() {
                index = reusedIndex
            } else {
                index = self.nextFreeIndex
                if self.nextFreeIndex % Resource.itemsPerChunk == 0 {
                    self.allocateChunk(self.nextFreeIndex / Resource.itemsPerChunk)
                }
                self.nextFreeIndex += 1
            }
            
            let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Resource.itemsPerChunk)
            let generation = self.generationChunks[chunkIndex][indexInChunk]
            let handle =  UInt64(truncatingIfNeeded: index) |
            (UInt64(generation) << Resource.generationBitsRange.lowerBound) |
            (UInt64(flags.rawValue) << Resource.flagBitsRange.lowerBound) |
            (UInt64(Resource.resourceType.rawValue) << Resource.typeBitsRange.lowerBound)
            return Resource(handle: handle)
        }
    }
    
    func initialize(resource: Resource, descriptor: Resource.Descriptor, heap: Heap?, flags: ResourceFlags) {
        let (chunkIndex, indexInChunk) = resource.index.quotientAndRemainder(dividingBy: Resource.itemsPerChunk)
        self.sharedChunks[chunkIndex].initialize(index: indexInChunk, descriptor: descriptor, heap: heap, flags: flags)
        self.persistentChunks[chunkIndex].initialize(index: indexInChunk, descriptor: descriptor, heap: heap, flags: flags)
    }
    
    func allocate(descriptor: Resource.Descriptor, heap: Heap?, flags: ResourceFlags) -> Resource {
        let resource = self.allocateHandle(flags: flags)
        self.initialize(resource: resource, descriptor: descriptor, heap: heap, flags: flags)
        return resource
    }
    
    var chunkCount : Int {
        let lastUsedIndex = self.nextFreeIndex - 1
        if lastUsedIndex < 0 { return 0 }
        return (lastUsedIndex / Resource.itemsPerChunk) + 1
    }
    
    func allocateChunk(_ index: Int) {
        assert(index < Self.maxChunks)
        self.sharedChunks.advanced(by: index).initialize(to: .init(capacity: Resource.itemsPerChunk))
        self.persistentChunks.advanced(by: index).initialize(to: .init(capacity: Resource.itemsPerChunk))
        
        let generations = UnsafeMutablePointer<UInt8>.allocate(capacity: Resource.itemsPerChunk)
        generations.initialize(repeating: 0, count: Resource.itemsPerChunk)
        self.generationChunks.advanced(by: index).initialize(to: generations)
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
        let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Resource.itemsPerChunk)
        
        self.sharedChunks[chunkIndex].deinitialize(from: indexInChunk, count: 1)
        self.persistentChunks[chunkIndex].deinitialize(from: indexInChunk, count: 1)
        self.generationChunks[chunkIndex][indexInChunk] = self.generationChunks[chunkIndex][indexInChunk] &+ 1
        
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
            let renderGraphInactiveMask: UInt8 = ~(1 << afterRenderGraph.queue.index)
            
            let chunkCount = self.chunkCount
            for chunkIndex in 0..<chunkCount {
                let baseItem = chunkIndex * Resource.itemsPerChunk
                let chunkItemCount = min(self.nextFreeIndex - baseItem, Resource.itemsPerChunk)
                self.sharedChunks[chunkIndex].usagesOptional?.assign(repeating: ChunkArray(), count: chunkItemCount)
                
                if let activeRenderGraphs = self.persistentChunks[chunkIndex].activeRenderGraphsOptional {
                    for i in 0..<chunkItemCount {
                        UInt8.AtomicRepresentation.atomicLoadThenBitwiseAnd(with: renderGraphInactiveMask, at: activeRenderGraphs.advanced(by: i), ordering: .relaxed)
                    }
                }
            }
            
            self.processEnqueuedDisposals()
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

struct TextureProperties: SharedResourceProperties {
    struct TransientTextureProperties: ResourceProperties {
        var baseResources : UnsafeMutablePointer<Resource?>
        var textureViewInfos : UnsafeMutablePointer<TextureViewBaseInfo?>
        
        init(capacity: Int) {
            self.baseResources = UnsafeMutablePointer.allocate(capacity: capacity)
            self.textureViewInfos = UnsafeMutablePointer.allocate(capacity: capacity)
        }
        
        func deallocate() {
            self.baseResources.deallocate()
            self.textureViewInfos.deallocate()
        }
        
        func initialize(index: Int, descriptor: TextureDescriptor, heap: Heap?, flags: ResourceFlags) {
            self.baseResources.advanced(by: index).initialize(to: nil)
            self.textureViewInfos.advanced(by: index).initialize(to: nil)
        }
        
        func initialize(index: Int, descriptor: Buffer.TextureViewDescriptor, baseResource: Buffer) {
            self.baseResources.advanced(by: index).initialize(to: Resource(baseResource))
            self.textureViewInfos.advanced(by: index).initialize(to: .buffer(descriptor))
        }
        
        func initialize(index: Int, viewDescriptor: Texture.TextureViewDescriptor, baseResource: Texture) {
            self.baseResources.advanced(by: index).initialize(to: Resource(baseResource))
            self.textureViewInfos.advanced(by: index).initialize(to: .texture(viewDescriptor))
        }
        
        func deinitialize(from index: Int, count: Int) {
            self.baseResources.advanced(by: index).deinitialize(count: count)
            self.textureViewInfos.advanced(by: index).deinitialize(count: count)
        }
    }
    struct PersistentTextureProperties: PersistentResourceProperties {
        let stateFlags : UnsafeMutablePointer<ResourceStateFlags>
        /// The index that must be completed on the GPU for each queue before the CPU can read from this resource's memory.
        let readWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The index that must be completed on the GPU for each queue before the CPU can write to this resource's memory.
        let writeWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The RenderGraphs that are currently using this resource.
        let activeRenderGraphs : UnsafeMutablePointer<UInt8.AtomicRepresentation>
        let heaps : UnsafeMutablePointer<Heap?>
        
        init(capacity: Int) {
            self.stateFlags = .allocate(capacity: capacity)
            self.readWaitIndices = .allocate(capacity: capacity)
            self.writeWaitIndices = .allocate(capacity: capacity)
            self.activeRenderGraphs = .allocate(capacity: capacity)
            self.heaps = .allocate(capacity: capacity)
        }
        
        func deallocate() {
            self.stateFlags.deallocate()
            self.readWaitIndices.deallocate()
            self.writeWaitIndices.deallocate()
            self.activeRenderGraphs.deallocate()
            self.heaps.deallocate()
        }
        
        func initialize(index: Int, descriptor: TextureDescriptor, heap: Heap?, flags: ResourceFlags) {
            self.stateFlags.advanced(by: index).initialize(to: [])
            self.readWaitIndices.advanced(by: index).initialize(to: SIMD8(repeating: 0))
            self.writeWaitIndices.advanced(by: index).initialize(to: SIMD8(repeating: 0))
            self.activeRenderGraphs.advanced(by: index).initialize(to: UInt8.AtomicRepresentation(0))
            self.heaps.advanced(by: index).initialize(to: heap)
        }
        
        func deinitialize(from index: Int, count: Int) {
            self.stateFlags.advanced(by: index).deinitialize(count: count)
            self.readWaitIndices.advanced(by: index).deinitialize(count: count)
            self.writeWaitIndices.advanced(by: index).deinitialize(count: count)
            self.activeRenderGraphs.advanced(by: index).deinitialize(count: count)
            self.heaps.advanced(by: index).deinitialize(count: count)
        }
        
        var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { self.activeRenderGraphs }
    }
    
    var descriptors : UnsafeMutablePointer<TextureDescriptor>
    var usages : UnsafeMutablePointer<ChunkArray<ResourceUsage>>
    
    var labels : UnsafeMutablePointer<String?>
    
    init(capacity: Int) {
        self.descriptors = UnsafeMutablePointer.allocate(capacity: capacity)
        self.usages = UnsafeMutablePointer.allocate(capacity: capacity)
        self.labels = UnsafeMutablePointer.allocate(capacity: capacity)
    }
    
    func deallocate() {
        self.descriptors.deallocate()
        self.usages.deallocate()
        self.labels.deallocate()
    }
    
    func initialize(index: Int, descriptor: TextureDescriptor, heap: Heap?, flags: ResourceFlags) {
        self.descriptors.advanced(by: index).initialize(to: descriptor)
        self.usages.advanced(by: index).initialize(to: ChunkArray())
        self.labels.advanced(by: index).initialize(to: nil)
    }
    
    func initialize(index: Int, descriptor: Buffer.TextureViewDescriptor, baseResource: Buffer) {
        self.descriptors.advanced(by: index).initialize(to: descriptor.descriptor)
        self.usages.advanced(by: index).initialize(to: ChunkArray())
        self.labels.advanced(by: index).initialize(to: nil)
    }
    
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
    }
    
    func deinitialize(from index: Int, count: Int) {
        self.descriptors.advanced(by: index).deinitialize(count: count)
        self.usages.advanced(by: index).deinitialize(count: count)
        self.labels.advanced(by: index).deinitialize(count: count)
    }
    
    var usagesOptional: UnsafeMutablePointer<ChunkArray<ResourceUsage>>? { self.usages }
}

final class TransientTextureRegistry: TransientFixedSizeRegistry<Texture> {
    static let instances = TransientRegistryArray<TransientTextureRegistry>()
    
    func allocate(descriptor: Buffer.TextureViewDescriptor, baseResource: Buffer, flags: ResourceFlags) -> Texture {
        let resource = self.allocateHandle(flags: flags)
        self.sharedStorage.initialize(index: resource.index, descriptor: descriptor, baseResource: baseResource)
        self.transientStorage.initialize(index: resource.index, descriptor: descriptor, baseResource: baseResource)
        baseResource.descriptor.usageHint.formUnion(.textureView)
        
        return resource
    }
    
    func allocate(descriptor viewDescriptor: Texture.TextureViewDescriptor, baseResource: Texture, flags: ResourceFlags) -> Texture {
        let resource = self.allocateHandle(flags: flags)
        self.sharedStorage.initialize(index: resource.index, viewDescriptor: viewDescriptor, baseResource: baseResource)
        self.transientStorage.initialize(index: resource.index, viewDescriptor: viewDescriptor, baseResource: baseResource)

        if baseResource.descriptor.pixelFormat.channelCount != viewDescriptor.pixelFormat.channelCount || baseResource.descriptor.pixelFormat.bytesPerPixel != viewDescriptor.pixelFormat.bytesPerPixel {
            baseResource.descriptor.usageHint.formUnion(.pixelFormatView)
        }
        
        return resource
    }
}

@usableFromInline
struct BufferProperties: SharedResourceProperties {
    
    struct TransientProperties: ResourceProperties {
        var deferredSliceActions : UnsafeMutablePointer<[DeferredBufferSlice]>
        
        @usableFromInline
        init(capacity: Int) {
            self.deferredSliceActions = UnsafeMutablePointer.allocate(capacity: capacity)
        }
        
        @usableFromInline
        func deallocate() {
            self.deferredSliceActions.deallocate()
        }
        
        @usableFromInline
        func initialize(index: Int, descriptor: BufferDescriptor, heap: Heap?, flags: ResourceFlags) {
            self.deferredSliceActions.advanced(by: index).initialize(to: [])
        }
        
        @usableFromInline
        func deinitialize(from index: Int, count: Int) {
            self.deferredSliceActions.advanced(by: index).deinitialize(count: count)
        }
    }
    
    struct PersistentProperties: PersistentResourceProperties {
        
        let stateFlags : UnsafeMutablePointer<ResourceStateFlags>
        /// The index that must be completed on the GPU for each queue before the CPU can read from this resource's memory.
        let readWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The index that must be completed on the GPU for each queue before the CPU can write to this resource's memory.
        let writeWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The RenderGraphs that are currently using this resource.
        let activeRenderGraphs : UnsafeMutablePointer<UInt8.AtomicRepresentation>
        let heaps : UnsafeMutablePointer<Heap?>
        
        @usableFromInline
        init(capacity: Int) {
            self.stateFlags = .allocate(capacity: capacity)
            self.readWaitIndices = .allocate(capacity: capacity)
            self.writeWaitIndices = .allocate(capacity: capacity)
            self.activeRenderGraphs = .allocate(capacity: capacity)
            self.heaps = .allocate(capacity: capacity)
        }
        
        @usableFromInline
        func deallocate() {
            self.stateFlags.deallocate()
            self.readWaitIndices.deallocate()
            self.writeWaitIndices.deallocate()
            self.activeRenderGraphs.deallocate()
            self.heaps.deallocate()
        }
        
        @usableFromInline
        func initialize(index: Int, descriptor: BufferDescriptor, heap: Heap?, flags: ResourceFlags) {
            self.stateFlags.advanced(by: index).initialize(to: [])
            self.readWaitIndices.advanced(by: index).initialize(to: SIMD8(repeating: 0))
            self.writeWaitIndices.advanced(by: index).initialize(to: SIMD8(repeating: 0))
            self.activeRenderGraphs.advanced(by: index).initialize(to: UInt8.AtomicRepresentation(0))
            self.heaps.advanced(by: index).initialize(to: heap)
        }
        
        @usableFromInline
        func deinitialize(from index: Int, count: Int) {
            self.stateFlags.advanced(by: index).deinitialize(count: count)
            self.readWaitIndices.advanced(by: index).deinitialize(count: count)
            self.writeWaitIndices.advanced(by: index).deinitialize(count: count)
            self.activeRenderGraphs.advanced(by: index).deinitialize(count: count)
            self.heaps.advanced(by: index).deinitialize(count: count)
        }
        
        var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? {
            return self.activeRenderGraphs
        }
    }
    
    var descriptors : UnsafeMutablePointer<BufferDescriptor>
    var usages : UnsafeMutablePointer<ChunkArray<ResourceUsage>>
    var labels : UnsafeMutablePointer<String?>
    
    init(capacity: Int) {
        self.descriptors = UnsafeMutablePointer.allocate(capacity: capacity)
        self.usages = UnsafeMutablePointer.allocate(capacity: capacity)
        self.labels = UnsafeMutablePointer.allocate(capacity: capacity)
    }
    
    func deallocate() {
        self.descriptors.deallocate()
        self.usages.deallocate()
        self.labels.deallocate()
    }
    
    func initialize(index: Int, descriptor: BufferDescriptor, heap: Heap?, flags: ResourceFlags) {
        self.descriptors.advanced(by: index).initialize(to: descriptor)
        self.usages.advanced(by: index).initialize(to: ChunkArray())
        self.labels.advanced(by: index).initialize(to: nil)
    }
    
    func deinitialize(from index: Int, count: Int) {
        self.descriptors.advanced(by: index).deinitialize(count: count)
        self.usages.advanced(by: index).deinitialize(count: count)
        self.labels.advanced(by: index).deinitialize(count: count)
    }
    
    var usagesOptional: UnsafeMutablePointer<ChunkArray<ResourceUsage>>? { self.usages }
}


final class TransientBufferRegistry: TransientFixedSizeRegistry<Buffer> {
    static let instances = TransientRegistryArray<TransientBufferRegistry>()
}

final class PersistentBufferRegistry: PersistentRegistry<Buffer> {
    static let instance = PersistentBufferRegistry()
}

final class PersistentTextureRegistry: PersistentRegistry<Texture> {
    static let instance = PersistentTextureRegistry()
}

struct ArgumentBufferProperties: SharedResourceProperties {
    struct PersistentArgumentBufferProperties: PersistentResourceProperties {
        let inlineDataStorage : UnsafeMutablePointer<Data>
        let heaps : UnsafeMutablePointer<Heap?>
        /// The index that must be completed on the GPU for each queue before the CPU can read from this resource's memory.
        let readWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The index that must be completed on the GPU for each queue before the CPU can write to this resource's memory.
        let writeWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The RenderGraphs that are currently using this resource.
        let activeRenderGraphs : UnsafeMutablePointer<UInt8.AtomicRepresentation>
        
        init(capacity: Int) {
            self.inlineDataStorage = .allocate(capacity: capacity)
            self.heaps = .allocate(capacity: capacity)
            self.readWaitIndices = .allocate(capacity: capacity)
            self.writeWaitIndices = .allocate(capacity: capacity)
            self.activeRenderGraphs = .allocate(capacity: capacity)
        }
        
        func deallocate() {
            self.inlineDataStorage.deallocate()
            self.heaps.deallocate()
            self.readWaitIndices.deallocate()
            self.writeWaitIndices.deallocate()
            self.activeRenderGraphs.deallocate()
        }
        
        func initialize(index indexInChunk: Int, descriptor: Void, heap: Heap?, flags: ResourceFlags) {
            self.inlineDataStorage.advanced(by: indexInChunk).initialize(to: Data())
            self.heaps.advanced(by: indexInChunk).initialize(to: nil)
            self.readWaitIndices.advanced(by: indexInChunk).initialize(to: SIMD8(repeating: 0))
            self.writeWaitIndices.advanced(by: indexInChunk).initialize(to: SIMD8(repeating: 0))
            self.activeRenderGraphs.advanced(by: indexInChunk).initialize(to: UInt8.AtomicRepresentation(0))
        }
        
        func initialize(index indexInChunk: Int, sourceArray: ArgumentBufferArray) {
            self.inlineDataStorage.advanced(by: indexInChunk).initialize(to: Data())
            self.heaps.advanced(by: indexInChunk).initialize(to: nil)
            self.readWaitIndices.advanced(by: indexInChunk).initialize(to: SIMD8(repeating: 0))
            self.writeWaitIndices.advanced(by: indexInChunk).initialize(to: SIMD8(repeating: 0))
            self.activeRenderGraphs.advanced(by: indexInChunk).initialize(to: UInt8.AtomicRepresentation(0))
        }
        
        func deinitialize(from indexInChunk: Int, count: Int) {
            self.inlineDataStorage.advanced(by: indexInChunk).deinitialize(count: count)
            self.heaps.advanced(by: indexInChunk).deinitialize(count: count)
        }
        
        var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { self.activeRenderGraphs }
    }
    
    let usages : UnsafeMutablePointer<ChunkArray<ResourceUsage>>
    let encoders : UnsafeMutablePointer<UnsafeRawPointer.AtomicOptionalRepresentation> // Some opaque backend type that can construct the argument buffer
    let enqueuedBindings : UnsafeMutablePointer<ExpandingBuffer<(FunctionArgumentKey, Int, ArgumentBuffer.ArgumentResource)>>
    let bindings : UnsafeMutablePointer<ExpandingBuffer<(ResourceBindingPath, ArgumentBuffer.ArgumentResource)>>
    let sourceArrays : UnsafeMutablePointer<ArgumentBufferArray?>
    
    let labels : UnsafeMutablePointer<String?>
    
    typealias Descriptor = Void
    
    init(capacity: Int) {
        self.usages = .allocate(capacity: capacity)
        self.encoders = .allocate(capacity: capacity)
        self.enqueuedBindings = .allocate(capacity: capacity)
        self.bindings = .allocate(capacity: capacity)
        self.sourceArrays = .allocate(capacity: capacity)
        self.labels = .allocate(capacity: capacity)
    }
    
    func deallocate() {
        self.usages.deallocate()
        self.encoders.deallocate()
        self.enqueuedBindings.deallocate()
        self.bindings.deallocate()
        self.sourceArrays.deallocate()
        self.labels.deallocate()
    }
    
    func initialize(index indexInChunk: Int, descriptor: Void, heap: Heap?, flags: ResourceFlags) {
        self.usages.advanced(by: indexInChunk).initialize(to: ChunkArray())
        self.encoders.advanced(by: indexInChunk).initialize(to: UnsafeRawPointer.AtomicOptionalRepresentation(nil))
        self.enqueuedBindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
        self.bindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
        self.sourceArrays.advanced(by: indexInChunk).initialize(to: nil)
        self.labels.advanced(by: indexInChunk).initialize(to: nil)
    }
    
    func initialize(index indexInChunk: Int, sourceArray: ArgumentBufferArray) {
        self.usages.advanced(by: indexInChunk).initialize(to: ChunkArray())
        self.encoders.advanced(by: indexInChunk).initialize(to: UnsafeRawPointer.AtomicOptionalRepresentation(nil))
        self.enqueuedBindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
        self.bindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
        self.sourceArrays.advanced(by: indexInChunk).initialize(to: sourceArray)
        self.labels.advanced(by: indexInChunk).initialize(to: nil)
    }
    
    func deinitialize(from index: Int, count: Int) {
        self.usages.advanced(by: index).deinitialize(count: count)
        self.encoders.advanced(by: index).deinitialize(count: count)
        self.enqueuedBindings.advanced(by: index).deinitialize(count: count)
        self.bindings.advanced(by: index).deinitialize(count: count)
        self.sourceArrays.advanced(by: index).deinitialize(count: count)
        self.labels.advanced(by: index).deinitialize(count: count)
    }
    
    var usagesOptional: UnsafeMutablePointer<ChunkArray<ResourceUsage>>? { self.usages }
}

// Unlike the other transient registries, the transient argument buffer registry is chunk-based.
// This is because the number of argument buffers used within a frame can vary dramatically, and so a pre-assigned maximum is more likely to be hit.
final class TransientArgumentBufferRegistry: TransientChunkRegistry<ArgumentBuffer> {
    static let instances = TransientRegistryArray<TransientArgumentBufferRegistry>()
    
    override class var maxChunks: Int { 2048 }
    
    let inlineDataAllocator : ExpandingBuffer<UInt8> = .init()
    
    func allocate(flags: ResourceFlags, sourceArray: ArgumentBufferArray) -> ArgumentBuffer {
        let resource = self.allocateHandle(flags: flags)
        let (chunkIndex, indexInChunk) = resource.index.quotientAndRemainder(dividingBy: ArgumentBuffer.itemsPerChunk)
        self.sharedPropertyChunks[chunkIndex].initialize(index: indexInChunk, sourceArray: sourceArray)
        return resource
    }
}


final class PersistentArgumentBufferRegistry: PersistentRegistry<ArgumentBuffer> {
    static let instance = PersistentArgumentBufferRegistry()
    
    override class var maxChunks: Int { 256 }
    
    func allocate(flags: ResourceFlags, sourceArray: ArgumentBufferArray) -> ArgumentBuffer {
        let handle = self.allocateHandle(flags: flags)
        let (chunkIndex, indexInChunk) = handle.index.quotientAndRemainder(dividingBy: ArgumentBuffer.itemsPerChunk)
        self.sharedChunks[chunkIndex].initialize(index: indexInChunk, sourceArray: sourceArray)
        self.persistentChunks[chunkIndex].initialize(index: indexInChunk, sourceArray: sourceArray)
        return handle
    }
}

struct ArgumentBufferArrayProperties: SharedResourceProperties {
    struct PersistentArgumentBufferArrayProperties: PersistentResourceProperties {
        let heaps : UnsafeMutablePointer<Heap?>
        
        init(capacity: Int) {
            self.heaps = .allocate(capacity: capacity)
        }
        
        func deallocate() {
            self.heaps.deallocate()
        }
        
        func initialize(index: Int, descriptor: Void, heap: Heap?, flags: ResourceFlags) {
            self.heaps.advanced(by: index).initialize(to: heap)
        }
        
        func deinitialize(from index: Int, count: Int) {
            self.heaps.advanced(by: index).deinitialize(count: count)
        }
        
        var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { nil }
    }
    
    var bindings : UnsafeMutablePointer<[ArgumentBuffer?]>
    var labels : UnsafeMutablePointer<String?>
    
    init(capacity: Int) {
        self.bindings = .allocate(capacity: capacity)
        self.labels = .allocate(capacity: capacity)
    }
    
    func deallocate() {
        self.bindings.deallocate()
        self.labels.deallocate()
    }
    
    func initialize(index: Int, descriptor: Void, heap: Heap?, flags: ResourceFlags) {
        self.bindings.advanced(by: index).initialize(to: [])
        self.labels.advanced(by: index).initialize(to: nil)
    }
    
    func deinitialize(from index: Int, count: Int) {
        self.bindings.advanced(by: index).deinitialize(count: count)
        self.labels.advanced(by: index).deinitialize(count: count)
    }
    
    var usagesOptional: UnsafeMutablePointer<ChunkArray<ResourceUsage>>? { nil }
    
}

final class TransientArgumentBufferArrayRegistry: TransientFixedSizeRegistry<ArgumentBufferArray> {
    static let instances = TransientRegistryArray<TransientArgumentBufferArrayRegistry>()
}


final class PersistentArgumentBufferArrayRegistry: PersistentRegistry<ArgumentBufferArray> {
    static let instance = PersistentArgumentBufferArrayRegistry()
}


@usableFromInline
struct HeapProperties: PersistentResourceProperties {
    let descriptors : UnsafeMutablePointer<HeapDescriptor>
    let labels : UnsafeMutablePointer<String?>
    let childResources : UnsafeMutablePointer<Set<Resource>>
    /// The RenderGraphs that are currently using this resource.
    let activeRenderGraphs : UnsafeMutablePointer<UInt8.AtomicRepresentation>
    
    init(capacity: Int) {
        self.descriptors = .allocate(capacity: capacity)
        self.labels = .allocate(capacity: capacity)
        self.childResources = .allocate(capacity: capacity)
        self.activeRenderGraphs = .allocate(capacity: capacity)
    }
    
    func deallocate() {
        self.descriptors.deallocate()
        self.labels.deallocate()
        self.childResources.deallocate()
        self.activeRenderGraphs.deallocate()
    }
    
    func initialize(index: Int, descriptor: HeapDescriptor, heap: Heap?, flags: ResourceFlags) {
        self.descriptors.advanced(by: index).initialize(to: descriptor)
        self.labels.advanced(by: index).initialize(to: nil)
        self.childResources.advanced(by: index).initialize(to: [])
        self.activeRenderGraphs.advanced(by: index).initialize(to: UInt8.AtomicRepresentation(0))
    }
    
    func deinitialize(from index: Int, count: Int) {
        self.descriptors.advanced(by: index).deinitialize(count: count)
        self.labels.advanced(by: index).deinitialize(count: count)
        self.childResources.advanced(by: index).deinitialize(count: count)
        self.activeRenderGraphs.deinitialize(count: count)
    }
    
    var usagesOptional: UnsafeMutablePointer<ChunkArray<ResourceUsage>>? { nil }
    
    var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { self.activeRenderGraphs }
}

final class HeapRegistry: PersistentRegistry<Heap> {
    static let instance = HeapRegistry()
}
