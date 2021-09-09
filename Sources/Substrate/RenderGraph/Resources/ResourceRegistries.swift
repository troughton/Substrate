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
    var readWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { get }
    var writeWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { get }
}

struct EmptyProperties<Descriptor>: PersistentResourceProperties & SharedResourceProperties {
    init(capacity: Int) {}
    func deallocate() {}
    func initialize(index: Int, descriptor: Descriptor, heap: Heap?, flags: ResourceFlags) {}
    func deinitialize(from index: Int, count: Int) {}
    
    var usagesOptional: UnsafeMutablePointer<ChunkArray<ResourceUsage>>? { nil }
    var readWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { nil }
    var writeWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { nil }
    var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { nil }
}

protocol TransientRegistry {
    associatedtype Resource: ResourceProtocolImpl
    func allocateHandle(flags: ResourceFlags) -> Resource
    func initialize(resource: Resource, descriptor: Resource.Descriptor)
    func allocate(descriptor: Resource.Descriptor, flags: ResourceFlags) -> Resource
    func clear()
    
    var generation: UInt8 { get }
    func sharedProperties(index: Int) -> (chunk: Resource.SharedProperties, indexInChunk: Int)
    func transientProperties(index: Int) -> (chunk: Resource.TransientProperties, indexInChunk: Int)
    func labelPointer(index: Int) -> UnsafeMutablePointer<String?>
}

class TransientChunkRegistry<Resource: ResourceProtocolImpl>: TransientRegistry {
    class var maxChunks: Int { 2048 }
    
    var lock = SpinLock()
    
    let transientRegistryIndex : Int
    var count = 0
    let sharedPropertyChunks : UnsafeMutablePointer<Resource.SharedProperties>?
    let transientPropertyChunks : UnsafeMutablePointer<Resource.TransientProperties>?
    let labelChunks : UnsafeMutablePointer<UnsafeMutablePointer<String?>>
    var allocatedChunkCount = 0
    var generation : UInt8 = 0
    
    init(transientRegistryIndex: Int) {
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
        
        self.labelChunks = .allocate(capacity: Self.maxChunks)
    }
    
    deinit {
        self.clear()
        for i in 0..<self.chunkCount {
            self.sharedPropertyChunks?[i].deallocate()
            self.transientPropertyChunks?[i].deallocate()
        }
        self.sharedPropertyChunks?.deallocate()
        self.transientPropertyChunks?.deallocate()
    }
    
    func sharedProperties(index: Int) -> (chunk: Resource.SharedProperties, indexInChunk: Int) {
        guard let sharedPropertyChunks = self.sharedPropertyChunks else {
            return (Resource.SharedProperties(capacity: 0), 0)
        }

        let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Resource.itemsPerChunk)
        return (sharedPropertyChunks[chunkIndex], indexInChunk)
    }
    
    func transientProperties(index: Int) -> (chunk: Resource.TransientProperties, indexInChunk: Int) {
        guard let transientPropertyChunks = self.transientPropertyChunks else {
            return (Resource.TransientProperties(capacity: 0), 0)
        }
        let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Resource.itemsPerChunk)
        return (transientPropertyChunks[chunkIndex], indexInChunk)
    }
    
    func labelPointer(index: Int) -> UnsafeMutablePointer<String?> {
        let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Resource.itemsPerChunk)
        return self.labelChunks[chunkIndex].advanced(by: indexInChunk)
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
        self.sharedPropertyChunks?[chunkIndex].initialize(index: indexInChunk, descriptor: descriptor, heap: nil, flags: resource.flags)
        self.transientPropertyChunks?[chunkIndex].initialize(index: indexInChunk, descriptor: descriptor, heap: nil, flags: resource.flags)
        self.labelChunks[chunkIndex].advanced(by: indexInChunk).initialize(to: nil)
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
        self.sharedPropertyChunks?.advanced(by: index).initialize(to: .init(capacity: Resource.itemsPerChunk))
        self.transientPropertyChunks?.advanced(by: index).initialize(to: .init(capacity: Resource.itemsPerChunk))
        self.labelChunks.advanced(by: index).initialize(to: .allocate(capacity: Resource.itemsPerChunk))
        self.allocatedChunkCount += 1
    }
    
    func clear() {
        self.lock.withLock {
            for chunkIndex in 0..<self.chunkCount {
                let countInChunk = min(self.count - chunkIndex * Resource.itemsPerChunk, Resource.itemsPerChunk)
                self.sharedPropertyChunks?[chunkIndex].deinitialize(from: 0, count: countInChunk)
                self.transientPropertyChunks?[chunkIndex].deinitialize(from: 0, count: countInChunk)
                self.labelChunks[chunkIndex].deinitialize(count: countInChunk)
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
    var labels: UnsafeMutablePointer<String?>!
    
    init(transientRegistryIndex: Int) {
        self.transientRegistryIndex = transientRegistryIndex
        self.capacity = 0
    }
    
    func initialise(capacity: Int) {
        assert(self.capacity == 0)
        
        self.capacity = capacity
        
        self.count.initialize(to: Int.AtomicRepresentation(0))
        self.sharedStorage = .init(capacity: self.capacity)
        self.transientStorage = .init(capacity: self.capacity)
        self.labels = .allocate(capacity: self.capacity)
    }
    
    deinit {
        self.clear()
        self.count.deallocate()
        self.sharedStorage.deallocate()
        self.transientStorage.deallocate()
        self.labels.deallocate()
    }
    
    func sharedProperties(index: Int) -> (chunk: Resource.SharedProperties, indexInChunk: Int) {
        return (self.sharedStorage, index)
    }
    
    func transientProperties(index: Int) -> (chunk: Resource.TransientProperties, indexInChunk: Int) {
        return (self.transientStorage, index)
    }
    
    func labelPointer(index: Int) -> UnsafeMutablePointer<String?> {
        return self.labels.advanced(by: index)
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
        self.labels.advanced(by: resource.index).initialize(to: nil)
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
        self.labels.deinitialize(count: count)
        
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
    let sharedChunks : UnsafeMutablePointer<Resource.SharedProperties>?
    let persistentChunks : UnsafeMutablePointer<Resource.PersistentProperties>?
    let labelChunks: UnsafeMutablePointer<UnsafeMutablePointer<String?>>
    let hazardTrackingGroupChunks : UnsafeMutablePointer<UnsafeMutablePointer<HazardTrackingGroup<Resource>?>>
    let generationChunks : UnsafeMutablePointer<UnsafeMutablePointer<UInt8>>
    
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
        self.labelChunks = .allocate(capacity: Self.maxChunks)
        self.hazardTrackingGroupChunks = .allocate(capacity: Self.maxChunks)
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
        self.sharedChunks?[chunkIndex].initialize(index: indexInChunk, descriptor: descriptor, heap: heap, flags: flags)
        self.persistentChunks?[chunkIndex].initialize(index: indexInChunk, descriptor: descriptor, heap: heap, flags: flags)
        self.hazardTrackingGroupChunks[chunkIndex].advanced(by: indexInChunk).initialize(to: nil)
        self.labelChunks[chunkIndex].advanced(by: indexInChunk).initialize(to: nil)
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
        self.sharedChunks?.advanced(by: index).initialize(to: .init(capacity: Resource.itemsPerChunk))
        self.persistentChunks?.advanced(by: index).initialize(to: .init(capacity: Resource.itemsPerChunk))
        self.labelChunks.advanced(by: index).initialize(to: .allocate(capacity: Resource.itemsPerChunk))
        self.hazardTrackingGroupChunks.advanced(by: index).initialize(to: .allocate(capacity: Resource.itemsPerChunk))
        
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
        case .accelerationStructure:
            RenderBackend.dispose(accelerationStructure: AccelerationStructure(handle: resource.handle))
        case .visibleFunctionTable:
            RenderBackend.dispose(visibleFunctionTable: VisibleFunctionTable(handle: resource.handle))
        case .intersectionFunctionTable:
            RenderBackend.dispose(intersectionFunctionTable: IntersectionFunctionTable(handle: resource.handle))
        case .hazardTrackingGroup:
            break
        default:
            fatalError()
        }
        
        let index = resource.index
        let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Resource.itemsPerChunk)
        
        self.sharedChunks?[chunkIndex].deinitialize(from: indexInChunk, count: 1)
        self.persistentChunks?[chunkIndex].deinitialize(from: indexInChunk, count: 1)
        self.labelChunks[chunkIndex].advanced(by: indexInChunk).deinitialize(count: 1)
        self.hazardTrackingGroupChunks[chunkIndex].advanced(by: indexInChunk).deinitialize(count: 1)
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
            self.processEnqueuedDisposals()
            
            let renderGraphInactiveMask: UInt8 = ~(1 << afterRenderGraph.queue.index)
            
            let chunkCount = self.chunkCount
            for chunkIndex in 0..<chunkCount {
                let baseItem = chunkIndex * Resource.itemsPerChunk
                let chunkItemCount = min(self.nextFreeIndex - baseItem, Resource.itemsPerChunk)
                self.sharedChunks?[chunkIndex].usagesOptional?.assign(repeating: ChunkArray(), count: chunkItemCount)
                
                if let activeRenderGraphs = self.persistentChunks?[chunkIndex].activeRenderGraphsOptional {
                    for i in 0..<chunkItemCount {
                        UInt8.AtomicRepresentation.atomicLoadThenBitwiseAnd(with: renderGraphInactiveMask, at: activeRenderGraphs.advanced(by: i), ordering: .relaxed)
                    }
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
