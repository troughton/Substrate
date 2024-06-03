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
@usableFromInline struct TransientRegistryArray<T: TransientRegistry> {
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

@usableFromInline protocol ResourceProperties {
    associatedtype Descriptor
    init(capacity: Int)
    func deallocate()
    func initialize(index: Int, descriptor: Descriptor, heap: Heap?, flags: ResourceFlags)
    func deinitialize(from index: Int, count: Int)
}

@usableFromInline protocol PersistentResourceProperties: ResourceProperties {
    var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { get }
    var readWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndex.AtomicRepresentation>? { get }
    var writeWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndex.AtomicRepresentation>? { get }
}

@usableFromInline struct EmptyProperties<Descriptor>: PersistentResourceProperties {
    @usableFromInline init(capacity: Int) {}
    @usableFromInline func deallocate() {}
    @usableFromInline func initialize(index: Int, descriptor: Descriptor, heap: Heap?, flags: ResourceFlags) {}
    @usableFromInline func deinitialize(from index: Int, count: Int) {}
    
    @usableFromInline var readWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndex.AtomicRepresentation>? { nil }
    @usableFromInline var writeWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndex.AtomicRepresentation>? { nil }
    @usableFromInline var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { nil }
}

@usableFromInline protocol TransientRegistry {
    associatedtype Resource: ResourceProtocolImpl
    init(transientRegistryIndex: Int)
    func allocateHandle(flags: ResourceFlags) -> Resource
    func initialize(resource: Resource, descriptor: Resource.Descriptor)
    func allocate(descriptor: Resource.Descriptor, flags: ResourceFlags) -> Resource
    func clear()
    
    var generation: UInt8 { get }
    func sharedResourceProperties(index: Int) -> (chunk: SharedResourceProperties<Resource.Descriptor>, indexInChunk: Int)
    func sharedProperties(index: Int) -> (chunk: Resource.SharedProperties, indexInChunk: Int)
    func transientProperties(index: Int) -> (chunk: Resource.TransientProperties, indexInChunk: Int)
    func labelPointer(index: Int) -> UnsafeMutablePointer<String?>
}

@usableFromInline struct SharedResourceProperties<Descriptor>: ResourceProperties {
    let labels: UnsafeMutablePointer<String?>
    let descriptors: UnsafeMutablePointer<Descriptor>?
    let backingResources: UnsafeMutablePointer<UnsafeMutableRawPointer?>
    let hazardTrackingGroups: UnsafeMutablePointer<_HazardTrackingGroup?>
    let usages: UnsafeMutablePointer<ChunkArray<RecordedResourceUsage>>?
    
#if canImport(Metal)
    let gpuAddresses: UnsafeMutablePointer<UInt64>
#endif
    
    @usableFromInline init(capacity: Int) {
        preconditionFailure()
    }
    
    @usableFromInline init(capacity: Int, tracksUsages: Bool) {
        self.labels = UnsafeMutablePointer.allocate(capacity: capacity)
        self.descriptors = MemoryLayout<Descriptor>.size > 0 ? UnsafeMutablePointer.allocate(capacity: capacity) : nil
        self.backingResources = UnsafeMutablePointer.allocate(capacity: capacity)
        self.hazardTrackingGroups = UnsafeMutablePointer.allocate(capacity: capacity)
        self.usages = tracksUsages ? UnsafeMutablePointer.allocate(capacity: capacity) : nil
        
#if canImport(Metal)
        self.gpuAddresses = UnsafeMutablePointer.allocate(capacity: capacity)
#endif
    }
    
    @usableFromInline func deallocate() {
        self.labels.deallocate()
        self.descriptors?.deallocate()
        self.backingResources.deallocate()
        self.hazardTrackingGroups.deallocate()
        self.usages?.deallocate()
        
#if canImport(Metal)
        self.gpuAddresses.deallocate()
#endif
    }
    
    @usableFromInline func initialize(index: Int, descriptor: Descriptor, heap: Heap?, flags: ResourceFlags) {
        self.labels.advanced(by: index).initialize(to: nil)
        self.descriptors?.advanced(by: index).initialize(to: descriptor)
        self.backingResources.advanced(by: index).initialize(to: nil)
        self.hazardTrackingGroups.advanced(by: index).initialize(to: nil)
        self.usages?.advanced(by: index).initialize(to: ChunkArray())
        
#if canImport(Metal)
        self.gpuAddresses.advanced(by: index).initialize(to: 0)
#endif
    }
    
    @usableFromInline func deinitialize(from index: Int, count: Int) {
        self.labels.advanced(by: index).deinitialize(count: count)
        self.descriptors?.advanced(by: index).deinitialize(count: count)
        self.backingResources.advanced(by: index).deinitialize(count: count)
        self.hazardTrackingGroups.advanced(by: index).deinitialize(count: count)
        self.usages?.advanced(by: index).deinitialize(count: count)
        
#if canImport(Metal)
        self.gpuAddresses.advanced(by: index).deinitialize(count: count)
#endif
    }
}

@usableFromInline class TransientChunkRegistry<Resource: ResourceProtocolImpl>: TransientRegistry {
    class var maxChunks: Int { 2048 }
    
    var lock = SpinLock()
    
    let transientRegistryIndex : Int
    var count = 0
    let sharedResourcePropertyChunks : UnsafeMutablePointer<SharedResourceProperties<Resource.Descriptor>>
    let sharedPropertyChunks : UnsafeMutablePointer<Resource.SharedProperties>?
    let transientPropertyChunks : UnsafeMutablePointer<Resource.TransientProperties>?
    var allocatedChunkCount = 0
    @usableFromInline var generation : UInt8 = 0
    
    @usableFromInline required init(transientRegistryIndex: Int) {
        self.transientRegistryIndex = transientRegistryIndex
        if MemoryLayout<Resource.SharedProperties>.size > 0 {
            self.sharedPropertyChunks = .allocate(capacity: Self.maxChunks)
        } else {
            self.sharedPropertyChunks = nil
        }
        
        if MemoryLayout<Resource.TransientProperties>.size > 0 {
            self.transientPropertyChunks = .allocate(capacity: Self.maxChunks)
        } else {
            self.transientPropertyChunks = nil
        }
        
        self.sharedResourcePropertyChunks = .allocate(capacity: Self.maxChunks)
    }
    
    deinit {
        self.clear()
        for i in 0..<self.chunkCount {
            self.sharedResourcePropertyChunks[i].deallocate()
            self.sharedPropertyChunks?[i].deallocate()
            self.transientPropertyChunks?[i].deallocate()
        }
        self.sharedResourcePropertyChunks.deallocate()
        self.sharedPropertyChunks?.deallocate()
        self.transientPropertyChunks?.deallocate()
    }
    
    @usableFromInline func sharedResourceProperties(index: Int) -> (chunk: SharedResourceProperties<Resource.Descriptor>, indexInChunk: Int) {
        let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Resource.itemsPerChunk)
        return (self.sharedResourcePropertyChunks[chunkIndex], indexInChunk)
    }
    
    @usableFromInline func sharedProperties(index: Int) -> (chunk: Resource.SharedProperties, indexInChunk: Int) {
        guard let sharedPropertyChunks = self.sharedPropertyChunks else {
            return (Resource.SharedProperties(capacity: 0), 0)
        }

        let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Resource.itemsPerChunk)
        return (sharedPropertyChunks[chunkIndex], indexInChunk)
    }
    
    @usableFromInline func transientProperties(index: Int) -> (chunk: Resource.TransientProperties, indexInChunk: Int) {
        guard let transientPropertyChunks = self.transientPropertyChunks else {
            return (Resource.TransientProperties(capacity: 0), 0)
        }
        let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Resource.itemsPerChunk)
        return (transientPropertyChunks[chunkIndex], indexInChunk)
    }
    
    @usableFromInline func labelPointer(index: Int) -> UnsafeMutablePointer<String?> {
        let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Resource.itemsPerChunk)
        return self.sharedResourcePropertyChunks[chunkIndex].labels.advanced(by: indexInChunk)
    }
    
    @usableFromInline func allocateHandle(flags: ResourceFlags) -> Resource {
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
    
    @usableFromInline func initialize(resource: Resource, descriptor: Resource.Descriptor) {
        let (chunkIndex, indexInChunk) = resource.index.quotientAndRemainder(dividingBy: Resource.itemsPerChunk)
        self.sharedResourcePropertyChunks[chunkIndex].initialize(index: indexInChunk, descriptor: descriptor, heap: nil, flags: resource.flags)
        self.sharedPropertyChunks?[chunkIndex].initialize(index: indexInChunk, descriptor: descriptor, heap: nil, flags: resource.flags)
        self.transientPropertyChunks?[chunkIndex].initialize(index: indexInChunk, descriptor: descriptor, heap: nil, flags: resource.flags)
    }
    
    @usableFromInline func allocate(descriptor: Resource.Descriptor, flags: ResourceFlags) -> Resource {
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
        self.sharedResourcePropertyChunks.advanced(by: index).initialize(to: .init(capacity: Resource.itemsPerChunk, tracksUsages: Resource.tracksUsages))
        self.sharedPropertyChunks?.advanced(by: index).initialize(to: .init(capacity: Resource.itemsPerChunk))
        self.transientPropertyChunks?.advanced(by: index).initialize(to: .init(capacity: Resource.itemsPerChunk))
        self.allocatedChunkCount += 1
    }
    
    @usableFromInline func clear() {
        self.lock.withLock {
            for chunkIndex in 0..<self.chunkCount {
                let countInChunk = min(self.count - chunkIndex * Resource.itemsPerChunk, Resource.itemsPerChunk)
                self.sharedResourcePropertyChunks[chunkIndex].deinitialize(from: 0, count: countInChunk)
                self.sharedPropertyChunks?[chunkIndex].deinitialize(from: 0, count: countInChunk)
                self.transientPropertyChunks?[chunkIndex].deinitialize(from: 0, count: countInChunk)
            }
            self.count = 0
            
            self.generation = self.generation &+ 1
        }
    }
}

@usableFromInline class TransientFixedSizeRegistry<Resource: ResourceProtocolImpl>: TransientRegistry {
    let transientRegistryIndex : Int
    var capacity : Int
    var count = UnsafeMutablePointer<Int.AtomicRepresentation>.allocate(capacity: 1)
    @usableFromInline var generation : UInt8 = 0
    
    var sharedPropertyStorage: SharedResourceProperties<Resource.Descriptor>!
    var sharedStorage : Resource.SharedProperties!
    var transientStorage : Resource.TransientProperties!
    var labels: UnsafeMutablePointer<String?>!
    
    @usableFromInline required init(transientRegistryIndex: Int) {
        self.transientRegistryIndex = transientRegistryIndex
        self.capacity = 0
    }
    
    func initialise(capacity: Int) {
        assert(self.capacity == 0)
        
        self.capacity = capacity
        
        self.count.initialize(to: Int.AtomicRepresentation(0))
        self.sharedPropertyStorage = .init(capacity: self.capacity, tracksUsages: Resource.tracksUsages)
        self.sharedStorage = .init(capacity: self.capacity)
        self.transientStorage = .init(capacity: self.capacity)
        self.labels = .allocate(capacity: self.capacity)
    }
    
    deinit {
        self.clear()
        self.count.deallocate()
        self.sharedPropertyStorage.deallocate()
        self.sharedStorage.deallocate()
        self.transientStorage.deallocate()
        self.labels.deallocate()
    }
    
    @usableFromInline func sharedResourceProperties(index: Int) -> (chunk: SharedResourceProperties<Resource.Descriptor>, indexInChunk: Int) {
        return (self.sharedPropertyStorage, index)
    }
    
    @usableFromInline func sharedProperties(index: Int) -> (chunk: Resource.SharedProperties, indexInChunk: Int) {
        return (self.sharedStorage, index)
    }
    
    @usableFromInline func transientProperties(index: Int) -> (chunk: Resource.TransientProperties, indexInChunk: Int) {
        return (self.transientStorage, index)
    }
    
    @usableFromInline func labelPointer(index: Int) -> UnsafeMutablePointer<String?> {
        return self.labels.advanced(by: index)
    }
    
    @usableFromInline func allocateHandle(flags: ResourceFlags) -> Resource {
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
    
    @usableFromInline func initialize(resource: Resource, descriptor: Resource.Descriptor) {
        self.sharedPropertyStorage.initialize(index: resource.index, descriptor: descriptor, heap: nil, flags: resource.flags)
        self.sharedStorage.initialize(index: resource.index, descriptor: descriptor, heap: nil, flags: resource.flags)
        self.transientStorage.initialize(index: resource.index, descriptor: descriptor, heap: nil, flags: resource.flags)
        self.labels.advanced(by: resource.index).initialize(to: nil)
    }
    
    @usableFromInline func allocate(descriptor: Resource.Descriptor, flags: ResourceFlags) -> Resource {
        let resource = self.allocateHandle(flags: flags)
        self.initialize(resource: resource, descriptor: descriptor)
        return resource
    }
    
    func ensureCapacity(_ capacity: Int) {
        assert(capacity <= self.capacity)
    }
    
    @usableFromInline func clear() {
        let count = Int.AtomicRepresentation.atomicExchange(0, at: self.count, ordering: .relaxed)
        self.sharedPropertyStorage.deinitialize(from: 0, count: count)
        self.sharedStorage.deinitialize(from: 0, count: count)
        self.transientStorage.deinitialize(from: 0, count: count)
        self.labels.deinitialize(count: count)
        
        self.generation = self.generation &+ 1
        
        assert(Int.AtomicRepresentation.atomicLoad(at: self.count, ordering: .relaxed) == 0)
    }
}

@usableFromInline class PersistentRegistry<Resource: ResourceProtocolImpl> {
    class var maxChunks: Int { 2048 }
    
    var lock = SpinLock()
    
    var freeIndices = RingBuffer<Int>()
    var nextFreeIndex = 0
    var enqueuedDisposals = [Resource]()
    @usableFromInline let sharedPropertyChunks : UnsafeMutablePointer<SharedResourceProperties<Resource.Descriptor>>
    @usableFromInline let sharedChunks : UnsafeMutablePointer<Resource.SharedProperties>?
    @usableFromInline let persistentChunks : UnsafeMutablePointer<Resource.PersistentProperties>?
    @usableFromInline let generationChunks : UnsafeMutablePointer<UnsafeMutablePointer<UInt8>>
    
    init() {
        if MemoryLayout<Resource.SharedProperties>.size > 0 {
            self.sharedChunks = .allocate(capacity: Self.maxChunks)
        } else {
            self.sharedChunks = nil
        }
        if MemoryLayout<Resource.PersistentProperties>.size > 0 {
            self.persistentChunks = .allocate(capacity: Self.maxChunks)
        } else {
            self.persistentChunks = nil
        }
        self.sharedPropertyChunks = .allocate(capacity: Self.maxChunks)
        
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
            let handle = UInt64(truncatingIfNeeded: index) |
            (UInt64(generation) << Resource.generationBitsRange.lowerBound) |
            (UInt64(flags.rawValue) << Resource.flagBitsRange.lowerBound) |
            (UInt64(Resource.resourceType.rawValue) << Resource.typeBitsRange.lowerBound)
            return Resource(handle: handle)
        }
    }
    
    func initialize(resource: Resource, descriptor: Resource.Descriptor, heap: Heap?, flags: ResourceFlags) {
        let (chunkIndex, indexInChunk) = resource.index.quotientAndRemainder(dividingBy: Resource.itemsPerChunk)
        self.sharedPropertyChunks[chunkIndex].initialize(index: indexInChunk, descriptor: descriptor, heap: heap, flags: flags)
        self.sharedChunks?[chunkIndex].initialize(index: indexInChunk, descriptor: descriptor, heap: heap, flags: flags)
        self.persistentChunks?[chunkIndex].initialize(index: indexInChunk, descriptor: descriptor, heap: heap, flags: flags)
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
        self.sharedPropertyChunks.advanced(by: index).initialize(to: .init(capacity: Resource.itemsPerChunk, tracksUsages: Resource.tracksUsages))
        self.sharedChunks?.advanced(by: index).initialize(to: .init(capacity: Resource.itemsPerChunk))
        self.persistentChunks?.advanced(by: index).initialize(to: .init(capacity: Resource.itemsPerChunk))
        
        let generations = UnsafeMutablePointer<UInt8>.allocate(capacity: Resource.itemsPerChunk)
        generations.initialize(repeating: 0, count: Resource.itemsPerChunk)
        self.generationChunks.advanced(by: index).initialize(to: generations)
    }
    
    func disposeImmediately(_ resource: Resource, isFullyInitialised: Bool = true, disposeInBackend: Bool = true) {
        if disposeInBackend {
            RenderBackend.dispose(resource: resource)
        }
        
        let index = resource.index
        let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Resource.itemsPerChunk)
        
        if isFullyInitialised {
            self.sharedPropertyChunks[chunkIndex].deinitialize(from: indexInChunk, count: 1)
            self.sharedChunks?[chunkIndex].deinitialize(from: indexInChunk, count: 1)
            self.persistentChunks?[chunkIndex].deinitialize(from: indexInChunk, count: 1)
        }
        self.generationChunks[chunkIndex][indexInChunk] = self.generationChunks[chunkIndex][indexInChunk] &+ 1
        
        self.freeIndices.append(index)
    }
    
    func processEnqueuedDisposals() {
        var i = 0
        while i < self.enqueuedDisposals.count {
            let resource = self.enqueuedDisposals[i]
            
            if !resource.hasPendingRenderGraph {
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
                self.sharedPropertyChunks[chunkIndex].usages?.assign(repeating: ChunkArray(), count: chunkItemCount)
                
                if let activeRenderGraphs = self.persistentChunks?[chunkIndex].activeRenderGraphsOptional {
                    for i in 0..<chunkItemCount {
                        UInt8.AtomicRepresentation.atomicLoadThenBitwiseAnd(with: renderGraphInactiveMask, at: activeRenderGraphs.advanced(by: i), ordering: .relaxed)
                    }
                }
            }
            
            self.processEnqueuedDisposals()
        }
    }
    
    func dispose(_ resource: Resource, isFullyInitialised: Bool = true) {
        self.lock.withLock {
            if isFullyInitialised && resource.hasPendingRenderGraph {
                self.enqueuedDisposals.append(resource)
            } else {
                self.disposeImmediately(resource, isFullyInitialised: isFullyInitialised)
            }
        }
    }
}
