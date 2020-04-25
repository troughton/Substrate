//
//  ResourceRegistries.swift
//  RenderAPI
//
//  Created by Thomas Roughton on 24/07/18.
//

import FrameGraphUtilities
import Dispatch
import Foundation
import CAtomics

// Registries in this file fall into two main types.
// Fixed-capacity registries (transient buffers, transient textures, and transient argument buffer arrays) have permanently-allocated storage.
// Chunk-based registries allocate storage in blocks. This avoids excessive memory usage while simultaneously ensuring that the memory for a resource is never reallocated (which would cause issues in multithreaded contexts, requiring locks for all access).


public final class TransientRegistryManager {
    public static let instance = TransientRegistryManager()
    
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

@usableFromInline final class TransientBufferRegistry {

    @usableFromInline static let instances = (0..<TransientRegistryManager.maxTransientRegistries).map { i in TransientBufferRegistry(transientRegistryIndex: i) }
    
    @usableFromInline let transientRegistryIndex : Int
    @usableFromInline var capacity : Int
    @usableFromInline var count = UnsafeMutablePointer<AtomicInt>.allocate(capacity: 1)
    @usableFromInline var generation : UInt8 = 0
    
    @usableFromInline var descriptors : UnsafeMutablePointer<BufferDescriptor>! = nil
    @usableFromInline var deferredSliceActions : UnsafeMutablePointer<[DeferredBufferSlice]>! = nil
    @usableFromInline var usages : UnsafeMutablePointer<ResourceUsagesList>! = nil
    @usableFromInline var labels : UnsafeMutablePointer<String?>! = nil
    
    init(transientRegistryIndex: Int) {
        self.transientRegistryIndex = transientRegistryIndex
        self.capacity = 0
    }
    
    func initialise(capacity: Int) {
        assert(self.capacity == 0)
        
        self.capacity = capacity
        
        self.count.initialize(to: AtomicInt(0))
        self.descriptors = UnsafeMutablePointer.allocate(capacity: self.capacity)
        self.deferredSliceActions = UnsafeMutablePointer.allocate(capacity: self.capacity)
        self.usages = UnsafeMutablePointer.allocate(capacity: self.capacity)
        self.labels = UnsafeMutablePointer.allocate(capacity: self.capacity)
    }
    
    deinit {
        self.clear()
        
        self.count.deallocate()
        self.descriptors?.deallocate()
        self.deferredSliceActions?.deallocate()
        self.usages?.deallocate()
        self.labels?.deallocate()
    }
    
    @usableFromInline
    func allocate(descriptor: BufferDescriptor, flags: ResourceFlags) -> UInt64 {
        
        let index = CAtomicsAdd(self.count, 1, .relaxed)
        self.ensureCapacity(index + 1)
        
        self.descriptors.advanced(by: index).initialize(to: descriptor)
        self.deferredSliceActions.advanced(by: index).initialize(to: [])
        self.usages.advanced(by: index).initialize(to: ResourceUsagesList())
        self.labels.advanced(by: index).initialize(to: nil)
        
        assert(index <= 0x1FFFFFFF, "Too many bits required to encode the resource's index.")
        
        return UInt64(truncatingIfNeeded: index) | (UInt64(self.generation) << Resource.generationBitsRange.lowerBound) | UInt64(self.transientRegistryIndex) << Resource.transientRegistryIndexBitsRange.lowerBound
    }
    
    @usableFromInline
    func ensureCapacity(_ capacity: Int) {
        assert(capacity <= self.capacity)
    }
    
    @usableFromInline
    func clear() {
        let count = CAtomicsExchange(self.count, 0, .relaxed)
        self.descriptors.deinitialize(count: count)
        self.deferredSliceActions.deinitialize(count: count)
        self.usages.deinitialize(count: count)
        self.labels.deinitialize(count: count)
        
        self.generation = self.generation &+ 1
        
        assert(CAtomicsLoad(self.count, .relaxed) == 0)
    }
}

@usableFromInline final class PersistentBufferRegistry {
    
    @usableFromInline static let instance = PersistentBufferRegistry()
    
    @usableFromInline
    struct Chunk {
        @usableFromInline static let itemsPerChunk = 4096
        
        @usableFromInline let stateFlags : UnsafeMutablePointer<ResourceStateFlags>
        /// The index that must be completed on the GPU for each queue before the CPU can read from this memory.
        @usableFromInline let readWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The index that must be completed on the GPU for each queue before the CPU can write to this memory.
        @usableFromInline let writeWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        @usableFromInline let descriptors : UnsafeMutablePointer<BufferDescriptor>
        @usableFromInline let usages : UnsafeMutablePointer<ResourceUsagesList>
        @usableFromInline let heaps : UnsafeMutablePointer<Heap?>
        @usableFromInline let generations : UnsafeMutablePointer<UInt8>
        @usableFromInline let labels : UnsafeMutablePointer<String?>
        
        init() {
            self.stateFlags = .allocate(capacity: Chunk.itemsPerChunk)
            self.readWaitIndices = .allocate(capacity: Chunk.itemsPerChunk)
            self.writeWaitIndices = .allocate(capacity: Chunk.itemsPerChunk)
            self.descriptors = .allocate(capacity: Chunk.itemsPerChunk)
            self.usages = .allocate(capacity: Chunk.itemsPerChunk)
            self.heaps = .allocate(capacity: Chunk.itemsPerChunk)
            self.generations = .allocate(capacity: Chunk.itemsPerChunk)
            self.labels = .allocate(capacity: Chunk.itemsPerChunk)
            
            self.generations.initialize(repeating: 0, count: Chunk.itemsPerChunk)
        }
        
        func deallocate() {
            self.stateFlags.deallocate()
            self.readWaitIndices.deallocate()
            self.writeWaitIndices.deallocate()
            self.descriptors.deallocate()
            self.usages.deallocate()
            self.heaps.deallocate()
            self.generations.deallocate()
            self.labels.deallocate()
        }
    }
    
    @usableFromInline static let maxChunks = 128
    
    @usableFromInline var lock = SpinLock()
    
    @usableFromInline var freeIndices = RingBuffer<Int>()
    @usableFromInline var maxIndex = 0
    @usableFromInline let enqueuedDisposals = ExpandingBuffer<Buffer>()
    @usableFromInline let chunks : UnsafeMutablePointer<Chunk>
    
    init() {
        self.chunks = .allocate(capacity: Self.maxChunks)
    }
    
    @usableFromInline
    func allocate(descriptor: BufferDescriptor, heap: Heap?, flags: ResourceFlags) -> UInt64 {
        return self.lock.withLock {
            let index : Int
            if let reusedIndex = self.freeIndices.popFirst() {
                index = reusedIndex
            } else {
                index = self.maxIndex
                if self.maxIndex % Chunk.itemsPerChunk == 0 {
                    self.allocateChunk(self.maxIndex / Chunk.itemsPerChunk)
                }
                self.maxIndex += 1
            }
            
            let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Chunk.itemsPerChunk)
            
            self.chunks[chunkIndex].stateFlags.advanced(by: indexInChunk).initialize(to: [])
            self.chunks[chunkIndex].readWaitIndices.advanced(by: indexInChunk).initialize(to: SIMD8(repeating: 0))
            self.chunks[chunkIndex].writeWaitIndices.advanced(by: indexInChunk).initialize(to: SIMD8(repeating: 0))
            self.chunks[chunkIndex].descriptors.advanced(by: indexInChunk).initialize(to: descriptor)
            self.chunks[chunkIndex].usages.advanced(by: indexInChunk).initialize(to: ResourceUsagesList())
            self.chunks[chunkIndex].heaps.advanced(by: indexInChunk).initialize(to: heap)
            self.chunks[chunkIndex].labels.advanced(by: indexInChunk).initialize(to: nil)
            
            let generation = self.chunks[chunkIndex].generations[indexInChunk]
            
            return UInt64(truncatingIfNeeded: index) | (UInt64(generation) << Resource.generationBitsRange.lowerBound)
        }
    }
    
    @usableFromInline var chunkCount : Int {
        if self.maxIndex == 0 { return 0 }
        return (self.maxIndex / Chunk.itemsPerChunk) + 1
    }
    
    @usableFromInline
    func allocateChunk(_ index: Int) {
        assert(index < Self.maxChunks)
        self.chunks.advanced(by: index).initialize(to: Chunk())
    }
    
    private func disposeImmediately(buffer: Buffer) {
        RenderBackend.dispose(buffer: buffer)
        
        let index = buffer.index
        let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Chunk.itemsPerChunk)
        
        self.chunks[chunkIndex].stateFlags.advanced(by: indexInChunk).deinitialize(count: 1)
        self.chunks[chunkIndex].readWaitIndices.advanced(by: indexInChunk).deinitialize(count: 1)
        self.chunks[chunkIndex].writeWaitIndices.advanced(by: indexInChunk).deinitialize(count: 1)
        self.chunks[chunkIndex].descriptors.advanced(by: indexInChunk).deinitialize(count: 1)
        self.chunks[chunkIndex].heaps.advanced(by: indexInChunk).deinitialize(count: 1)
        self.chunks[chunkIndex].labels.advanced(by: indexInChunk).deinitialize(count: 1)
        
        self.chunks[chunkIndex].generations[indexInChunk] = self.chunks[chunkIndex].generations[indexInChunk] &+ 1
        
        self.freeIndices.append(index)
    }
    
    func clear() {
        assert(!self.lock.isLocked)
        
        for buffer in self.enqueuedDisposals {
            self.disposeImmediately(buffer: buffer)
        }
        
        self.enqueuedDisposals.removeAll()
        
        for chunkIndex in 0..<self.chunkCount {
            self.chunks[chunkIndex].usages.assign(repeating: ResourceUsagesList(), count: Chunk.itemsPerChunk)
        }
    }
    
    func dispose(_ buffer: Buffer, atEndOfFrame: Bool = true) {
        self.lock.withLock {
            if atEndOfFrame {
                self.enqueuedDisposals.append(buffer)
            } else {
                self.disposeImmediately(buffer: buffer)
            }
        }
    }
}

public enum TextureViewBaseInfo {
    case buffer(Buffer.TextureViewDescriptor)
    case texture(Texture.TextureViewDescriptor)
}

@usableFromInline final class TransientTextureRegistry {
    @usableFromInline static let instances = (0..<TransientRegistryManager.maxTransientRegistries).map { i in TransientTextureRegistry(transientRegistryIndex: i) }
    
    @usableFromInline let transientRegistryIndex : Int
    @usableFromInline var capacity : Int
    @usableFromInline let count = UnsafeMutablePointer<AtomicInt>.allocate(capacity: 1)
    @usableFromInline var generation : UInt8 = 0
    
    @usableFromInline var descriptors : UnsafeMutablePointer<TextureDescriptor>! = nil
    @usableFromInline var usages : UnsafeMutablePointer<ResourceUsagesList>! = nil
    
    @usableFromInline var labels : UnsafeMutablePointer<String?>! = nil
    @usableFromInline var baseResources : UnsafeMutablePointer<Resource?>! = nil
    @usableFromInline var textureViewInfos : UnsafeMutablePointer<TextureViewBaseInfo?>! = nil
    
    init(transientRegistryIndex: Int) {
        self.transientRegistryIndex = transientRegistryIndex
        self.capacity = 0
    }
    
    func initialise(capacity: Int) {
        self.capacity = capacity
        self.count.initialize(to: AtomicInt(0))
        self.descriptors = UnsafeMutablePointer.allocate(capacity: self.capacity)
        self.usages = UnsafeMutablePointer.allocate(capacity: self.capacity)
        self.labels = UnsafeMutablePointer.allocate(capacity: self.capacity)
        self.baseResources = UnsafeMutablePointer.allocate(capacity: self.capacity)
        self.textureViewInfos = UnsafeMutablePointer.allocate(capacity: self.capacity)
    }
    
    deinit {
        self.clear()
        
        self.count.deallocate()
        self.descriptors?.deallocate()
        self.usages?.deallocate()
        self.labels?.deallocate()
        self.baseResources?.deallocate()
        self.textureViewInfos?.deallocate()
    }
    
    @usableFromInline
    func allocate(descriptor: TextureDescriptor, flags: ResourceFlags) -> UInt64 {
        let index = CAtomicsAdd(self.count, 1, .relaxed)
        self.ensureCapacity(index + 1)
        assert(index <= 0x1FFFFFFF, "Too many bits required to encode the resource's index.")
        
        self.descriptors.advanced(by: index).initialize(to: descriptor)
        self.usages.advanced(by: index).initialize(to: ResourceUsagesList())
        self.labels.advanced(by: index).initialize(to: nil)
        self.baseResources.advanced(by: index).initialize(to: nil)
        self.textureViewInfos.advanced(by: index).initialize(to: nil)
        
        return UInt64(truncatingIfNeeded: index) | (UInt64(self.generation) << Resource.generationBitsRange.lowerBound) | UInt64(self.transientRegistryIndex) << Resource.transientRegistryIndexBitsRange.lowerBound
    }
    
    @usableFromInline
    func allocate(descriptor: Buffer.TextureViewDescriptor, baseResource: Buffer) -> UInt64 {
        let index = CAtomicsAdd(self.count, 1, .relaxed)
        self.ensureCapacity(index + 1)
        assert(index <= 0x1FFFFFFF, "Too many bits required to encode the resource's index.")
        
        self.descriptors.advanced(by: index).initialize(to: descriptor.descriptor)
        self.usages.advanced(by: index).initialize(to: ResourceUsagesList())
        self.labels.advanced(by: index).initialize(to: nil)
        self.baseResources.advanced(by: index).initialize(to: Resource(baseResource))
        self.textureViewInfos.advanced(by: index).initialize(to: .buffer(descriptor))
        
        baseResource.descriptor.usageHint.formUnion(.textureView)
        
        return UInt64(truncatingIfNeeded: index) | (UInt64(self.generation) << Resource.generationBitsRange.lowerBound) | UInt64(self.transientRegistryIndex) << Resource.transientRegistryIndexBitsRange.lowerBound
    }
    
    @usableFromInline
    func allocate(descriptor viewDescriptor: Texture.TextureViewDescriptor, baseResource: Texture) -> UInt64 {
        let index = CAtomicsAdd(self.count, 1, .relaxed)
        self.ensureCapacity(index + 1)
        assert(index <= 0x1FFFFFFF, "Too many bits required to encode the resource's index.")
        
        var descriptor = baseResource.descriptor
        descriptor.pixelFormat = viewDescriptor.pixelFormat
        descriptor.textureType = viewDescriptor.textureType
        if viewDescriptor.slices.lowerBound != -1 {
            descriptor.arrayLength = viewDescriptor.slices.count
        }
        if viewDescriptor.levels.lowerBound != -1 {
            descriptor.mipmapLevelCount = viewDescriptor.levels.count
        }
        
        baseResource.descriptor.usageHint.formUnion(.pixelFormatView)
        
        self.descriptors.advanced(by: index).initialize(to: descriptor)
        self.usages.advanced(by: index).initialize(to:  ResourceUsagesList())
        self.labels.advanced(by: index).initialize(to: nil)
        self.baseResources.advanced(by: index).initialize(to: Resource(baseResource))
        self.textureViewInfos.advanced(by: index).initialize(to: .texture(viewDescriptor))
        
        return UInt64(truncatingIfNeeded: index) | (UInt64(self.generation) << Resource.generationBitsRange.lowerBound)
    }
    
    @usableFromInline
    func ensureCapacity(_ capacity: Int) {
        assert(capacity <= self.capacity)
    }
    
    @usableFromInline
    func clear() {
        let count = CAtomicsExchange(self.count, 0, .relaxed)
        self.descriptors.deinitialize(count: count)
        self.usages.deinitialize(count: count)
        self.labels.deinitialize(count: count)
        self.baseResources.deinitialize(count: count)
        self.textureViewInfos.deinitialize(count: count)
        
        self.generation = self.generation &+ 1
        
        assert(CAtomicsLoad(self.count, .relaxed) == 0)
    }
}

@usableFromInline final class PersistentTextureRegistry {
    @usableFromInline static let instance = PersistentTextureRegistry()
    
    @usableFromInline
    struct Chunk {
        @usableFromInline static let itemsPerChunk = 4096
        
        @usableFromInline let stateFlags : UnsafeMutablePointer<ResourceStateFlags>
        /// The index that must be completed on the GPU for each queue before the CPU can read from this memory.
        @usableFromInline let readWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The index that must be completed on the GPU for each queue before the CPU can write to this memory.
        @usableFromInline let writeWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        @usableFromInline let descriptors : UnsafeMutablePointer<TextureDescriptor>
        @usableFromInline let usages : UnsafeMutablePointer<ResourceUsagesList>
        @usableFromInline let heaps : UnsafeMutablePointer<Heap?>
        @usableFromInline let generations : UnsafeMutablePointer<UInt8>
        @usableFromInline let labels : UnsafeMutablePointer<String?>
        
        init() {
            self.stateFlags = .allocate(capacity: Chunk.itemsPerChunk)
            self.readWaitIndices = .allocate(capacity: Chunk.itemsPerChunk)
            self.writeWaitIndices = .allocate(capacity: Chunk.itemsPerChunk)
            self.descriptors = .allocate(capacity: Chunk.itemsPerChunk)
            self.usages = .allocate(capacity: Chunk.itemsPerChunk)
            self.heaps = .allocate(capacity: Chunk.itemsPerChunk)
            self.generations = .allocate(capacity: Chunk.itemsPerChunk)
            self.labels = .allocate(capacity: Chunk.itemsPerChunk)
            
            self.generations.initialize(repeating: 0, count: Chunk.itemsPerChunk)
        }
        
        func deallocate() {
            self.stateFlags.deallocate()
            self.readWaitIndices.deallocate()
            self.writeWaitIndices.deallocate()
            self.descriptors.deallocate()
            self.usages.deallocate()
            self.heaps.deallocate()
            self.generations.deallocate()
            self.labels.deallocate()
        }
    }
    
    @usableFromInline static let maxChunks = 128
    
    @usableFromInline var lock = SpinLock()
    
    @usableFromInline var freeIndices = RingBuffer<Int>()
    @usableFromInline var maxIndex = 0
    @usableFromInline let enqueuedDisposals = ExpandingBuffer<Texture>()
    @usableFromInline let chunks : UnsafeMutablePointer<Chunk>
    
    init() {
        self.chunks = .allocate(capacity: Self.maxChunks)
    }
    
    @usableFromInline
    func allocate(descriptor: TextureDescriptor, heap: Heap?, flags: ResourceFlags) -> UInt64 {
        return self.lock.withLock {
            let index : Int
            if let reusedIndex = self.freeIndices.popFirst() {
                index = reusedIndex
            } else {
                index = self.maxIndex
                if self.maxIndex % Chunk.itemsPerChunk == 0 {
                    self.allocateChunk(self.maxIndex / Chunk.itemsPerChunk)
                }
                self.maxIndex += 1
            }
            
            let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Chunk.itemsPerChunk)
            
            self.chunks[chunkIndex].stateFlags.advanced(by: indexInChunk).initialize(to: [])
            self.chunks[chunkIndex].readWaitIndices.advanced(by: indexInChunk).initialize(to: SIMD8(repeating: 0))
            self.chunks[chunkIndex].writeWaitIndices.advanced(by: indexInChunk).initialize(to: SIMD8(repeating: 0))
            self.chunks[chunkIndex].descriptors.advanced(by: indexInChunk).initialize(to: descriptor)
            self.chunks[chunkIndex].usages.advanced(by: indexInChunk).initialize(to: ResourceUsagesList())
            self.chunks[chunkIndex].heaps.advanced(by: indexInChunk).initialize(to: heap)
            self.chunks[chunkIndex].labels.advanced(by: indexInChunk).initialize(to: nil)
            
            let generation = self.chunks[chunkIndex].generations[indexInChunk]
            
            return UInt64(truncatingIfNeeded: index) | (UInt64(generation) << Resource.generationBitsRange.lowerBound)
        }
    }
    
    @usableFromInline var chunkCount : Int {
        if self.maxIndex == 0 { return 0 }
        return (self.maxIndex / Chunk.itemsPerChunk) + 1
    }
    
    @usableFromInline
    func allocateChunk(_ index: Int) {
        assert(index < Self.maxChunks)
        self.chunks.advanced(by: index).initialize(to: Chunk())
    }
    
    func clear() {
        assert(!self.lock.isLocked)
        
        for texture in self.enqueuedDisposals {
            RenderBackend.dispose(texture: texture)
            
            let index = texture.index
            let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Chunk.itemsPerChunk)
            
            self.chunks[chunkIndex].stateFlags.advanced(by: indexInChunk).deinitialize(count: 1)
            self.chunks[chunkIndex].readWaitIndices.advanced(by: indexInChunk).deinitialize(count: 1)
            self.chunks[chunkIndex].writeWaitIndices.advanced(by: indexInChunk).deinitialize(count: 1)
            self.chunks[chunkIndex].descriptors.advanced(by: indexInChunk).deinitialize(count: 1)
            self.chunks[chunkIndex].heaps.advanced(by: indexInChunk).deinitialize(count: 1)
            self.chunks[chunkIndex].labels.advanced(by: indexInChunk).deinitialize(count: 1)

            self.chunks[chunkIndex].generations[indexInChunk] = self.chunks[chunkIndex].generations[indexInChunk] &+ 1
            
            self.freeIndices.append(index)
        }
        self.enqueuedDisposals.removeAll()
        
        for chunkIndex in 0..<self.chunkCount {
            self.chunks[chunkIndex].usages.assign(repeating: ResourceUsagesList(), count: Chunk.itemsPerChunk)
        }
    }
    
    func dispose(_ texture: Texture) {
        self.lock.withLock {
            self.enqueuedDisposals.append(texture)
        }
    }
}

// Unlike the other transient registries, the transient argument buffer registry is chunk-based.
// This is because the number of argument buffers used within a frame can @usableFromInline vary dramatically, and so a pre-assigned maximum is more likely to be hit.
@usableFromInline final class TransientArgumentBufferRegistry {
    
    @usableFromInline static let instances = (0..<TransientRegistryManager.maxTransientRegistries).map { i in TransientArgumentBufferRegistry(transientRegistryIndex: i) }
    
    @usableFromInline
    struct Chunk {
        @usableFromInline static let itemsPerChunk = 2048
        
        @usableFromInline let usages : UnsafeMutablePointer<ResourceUsagesList>
        @usableFromInline let encoders : UnsafeMutablePointer<AtomicOptionalRawPointer> // Some opaque backend type that can construct the argument buffer
        @usableFromInline let enqueuedBindings : UnsafeMutablePointer<ExpandingBuffer<(FunctionArgumentKey, Int, _ArgumentBuffer.ArgumentResource)>>
        @usableFromInline let bindings : UnsafeMutablePointer<ExpandingBuffer<(ResourceBindingPath, _ArgumentBuffer.ArgumentResource)>>
        @usableFromInline let sourceArrays : UnsafeMutablePointer<_ArgumentBufferArray?>
        
        @usableFromInline let labels : UnsafeMutablePointer<String?>
        
        init() {
            self.usages = .allocate(capacity: Chunk.itemsPerChunk)
            self.encoders = .allocate(capacity: Chunk.itemsPerChunk)
            self.enqueuedBindings = .allocate(capacity: Chunk.itemsPerChunk)
            self.bindings = .allocate(capacity: Chunk.itemsPerChunk)
            self.sourceArrays = .allocate(capacity: Chunk.itemsPerChunk)
            self.labels = .allocate(capacity: Chunk.itemsPerChunk)
        }
        
        func deallocate() {
            self.usages.deallocate()
            self.encoders.deallocate()
            self.enqueuedBindings.deallocate()
            self.bindings.deallocate()
            self.sourceArrays.deallocate()
            self.labels.deallocate()
        }
    }
    
    @usableFromInline static let maxChunks = 256
    
    @usableFromInline var lock = SpinLock()
    
    @usableFromInline let transientRegistryIndex : Int
    @usableFromInline let inlineDataAllocator : ExpandingBuffer<UInt8>
    @usableFromInline var count = 0
    @usableFromInline let chunks : UnsafeMutablePointer<Chunk>
    @usableFromInline var allocatedChunkCount = 0
    @usableFromInline var generation : UInt8 = 0
    
    init(transientRegistryIndex: Int) {
        self.transientRegistryIndex = transientRegistryIndex
        self.inlineDataAllocator = ExpandingBuffer()
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
    func allocate(flags: ResourceFlags) -> UInt64 {
        return self.lock.withLock {
            
            let index = self.count
            if index == self.allocatedChunkCount * Chunk.itemsPerChunk {
                self.allocateChunk(index / Chunk.itemsPerChunk)
            }
            
            assert(index <= 0x1FFFFFFF, "Too many bits required to encode the resource's index.")
            
            let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Chunk.itemsPerChunk)
            
            self.chunks[chunkIndex].usages.advanced(by: indexInChunk).initialize(to: ResourceUsagesList())
            self.chunks[chunkIndex].encoders.advanced(by: indexInChunk).initialize(to: AtomicOptionalRawPointer(nil))
            self.chunks[chunkIndex].enqueuedBindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
            self.chunks[chunkIndex].bindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
            self.chunks[chunkIndex].sourceArrays.advanced(by: indexInChunk).initialize(to: nil)
            self.chunks[chunkIndex].labels.advanced(by: indexInChunk).initialize(to: nil)
            self.count += 1
            
            return UInt64(truncatingIfNeeded: index) | (UInt64(self.generation) << Resource.generationBitsRange.lowerBound) | UInt64(self.transientRegistryIndex) << Resource.transientRegistryIndexBitsRange.lowerBound
        }
    }
    
    @usableFromInline
    func allocate(flags: ResourceFlags, sourceArray: _ArgumentBufferArray) -> UInt64 {
        return self.lock.withLock {
            let index = self.count
            if index == self.allocatedChunkCount * Chunk.itemsPerChunk {
                self.allocateChunk(index / Chunk.itemsPerChunk)
            }
            
            assert(index <= 0x1FFFFFFF, "Too many bits required to encode the resource's index.")
            
            let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Chunk.itemsPerChunk)
            
            self.chunks[chunkIndex].usages.advanced(by: indexInChunk).initialize(to: ResourceUsagesList())
            self.chunks[chunkIndex].encoders.advanced(by: indexInChunk).initialize(to: AtomicOptionalRawPointer(nil))
            self.chunks[chunkIndex].enqueuedBindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
            self.chunks[chunkIndex].bindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
            self.chunks[chunkIndex].sourceArrays.advanced(by: indexInChunk).initialize(to: sourceArray)
            self.chunks[chunkIndex].labels.advanced(by: indexInChunk).initialize(to: nil)
            self.count += 1
            
            return UInt64(truncatingIfNeeded: index) | (UInt64(self.generation) << Resource.generationBitsRange.lowerBound) | UInt64(self.transientRegistryIndex) << Resource.transientRegistryIndexBitsRange.lowerBound
        }
    }
    
    @usableFromInline var chunkCount : Int {
        if self.count == 0 { return 0 }
        return (self.count / Chunk.itemsPerChunk) + 1
    }
    
    @usableFromInline
    func allocateChunk(_ index: Int) {
        assert(index < Self.maxChunks)
        assert(index == self.allocatedChunkCount)
        self.chunks.advanced(by: index).initialize(to: Chunk())
        self.allocatedChunkCount += 1
    }
    
    func clear() {
        assert(!self.lock.isLocked)
        
        for chunkIndex in 0..<self.chunkCount {
            let countInChunk = min(self.count - chunkIndex * Chunk.itemsPerChunk, Chunk.itemsPerChunk)
            self.chunks[chunkIndex].usages.deinitialize(count: countInChunk)
            self.chunks[chunkIndex].encoders.deinitialize(count: countInChunk)
            self.chunks[chunkIndex].enqueuedBindings.deinitialize(count: countInChunk)
            self.chunks[chunkIndex].bindings.deinitialize(count: countInChunk)
            self.chunks[chunkIndex].sourceArrays.deinitialize(count: countInChunk)
            self.chunks[chunkIndex].labels.deinitialize(count: countInChunk)
        }
        self.count = 0
        
        self.generation = self.generation &+ 1
    }
}

@usableFromInline final class PersistentArgumentBufferRegistry {
    @usableFromInline static let instance = PersistentArgumentBufferRegistry()
    
    @usableFromInline
    struct Chunk {
        @usableFromInline static let itemsPerChunk = 2048
        
        @usableFromInline let usages : UnsafeMutablePointer<ResourceUsagesList>
        @usableFromInline let encoders : UnsafeMutablePointer<AtomicOptionalRawPointer> // Some opaque backend type that can construct the argument buffer
        @usableFromInline let enqueuedBindings : UnsafeMutablePointer<ExpandingBuffer<(FunctionArgumentKey, Int, _ArgumentBuffer.ArgumentResource)>>
        @usableFromInline let bindings : UnsafeMutablePointer<ExpandingBuffer<(ResourceBindingPath, _ArgumentBuffer.ArgumentResource)>>
        @usableFromInline let inlineDataStorage : UnsafeMutablePointer<Data>
        @usableFromInline let sourceArrays : UnsafeMutablePointer<_ArgumentBufferArray>
        @usableFromInline let heaps : UnsafeMutablePointer<Heap?>
        /// The index that must be completed on the GPU for each queue before the CPU can read from this memory.
        @usableFromInline let readWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The index that must be completed on the GPU for each queue before the CPU can write to this memory.
        @usableFromInline let writeWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
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
            self.generations.deallocate()
            self.labels.deallocate()
        }
    }
    
    @usableFromInline static let maxChunks = 256
    
    @usableFromInline var lock = SpinLock()
    
    @usableFromInline var freeIndices = RingBuffer<Int>()
    @usableFromInline var maxIndex = 0
    
    @usableFromInline let enqueuedDisposals = ExpandingBuffer<_ArgumentBuffer>()
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
                index = self.maxIndex
                if index % Chunk.itemsPerChunk == 0 {
                    self.allocateChunk(index / Chunk.itemsPerChunk)
                }
                self.maxIndex += 1
            }
            
            let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Chunk.itemsPerChunk)
            
            self.chunks[chunkIndex].usages.advanced(by: indexInChunk).initialize(to: ResourceUsagesList())
            self.chunks[chunkIndex].encoders.advanced(by: indexInChunk).initialize(to: AtomicOptionalRawPointer(nil))
            self.chunks[chunkIndex].enqueuedBindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
            self.chunks[chunkIndex].bindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
            self.chunks[chunkIndex].inlineDataStorage.advanced(by: indexInChunk).initialize(to: Data())
            self.chunks[chunkIndex].heaps.advanced(by: indexInChunk).initialize(to: nil)
            self.chunks[chunkIndex].readWaitIndices.advanced(by: indexInChunk).initialize(to: SIMD8(repeating: 0))
            self.chunks[chunkIndex].writeWaitIndices.advanced(by: indexInChunk).initialize(to: SIMD8(repeating: 0))
            self.chunks[chunkIndex].labels.advanced(by: indexInChunk).initialize(to: nil)
            
            let generation = self.chunks[chunkIndex].generations[indexInChunk]
            
            return UInt64(truncatingIfNeeded: index) | (UInt64(generation) << Resource.generationBitsRange.lowerBound)
        }
    }
    
    @usableFromInline
    func allocate(flags: ResourceFlags, sourceArray: _ArgumentBufferArray) -> UInt64 {
        return self.lock.withLock {
            let index : Int
            if let reusedIndex = self.freeIndices.popFirst() {
                index = reusedIndex
            } else {
                index = self.maxIndex
                if index % Chunk.itemsPerChunk == 0 {
                    self.allocateChunk(index / Chunk.itemsPerChunk)
                }
                self.maxIndex += 1
            }
            
            let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Chunk.itemsPerChunk)
            
            
            self.chunks[chunkIndex].usages.advanced(by: indexInChunk).initialize(to: ResourceUsagesList())
            self.chunks[chunkIndex].encoders.advanced(by: indexInChunk).initialize(to: AtomicOptionalRawPointer(nil))
            self.chunks[chunkIndex].enqueuedBindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
            self.chunks[chunkIndex].bindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
            self.chunks[chunkIndex].inlineDataStorage.advanced(by: indexInChunk).initialize(to: Data())
            self.chunks[chunkIndex].sourceArrays.advanced(by: indexInChunk).initialize(to: sourceArray)
            self.chunks[chunkIndex].heaps.advanced(by: indexInChunk).initialize(to: nil)
            self.chunks[chunkIndex].readWaitIndices.advanced(by: indexInChunk).deinitialize(count: 1)
            self.chunks[chunkIndex].writeWaitIndices.advanced(by: indexInChunk).deinitialize(count: 1)
            self.chunks[chunkIndex].labels.advanced(by: indexInChunk).initialize(to: nil)
            
            let generation = self.chunks[chunkIndex].generations[indexInChunk]
            
            return UInt64(truncatingIfNeeded: index) | (UInt64(generation) << Resource.generationBitsRange.lowerBound)
        }
    }
    
    @usableFromInline var chunkCount : Int {
        if self.maxIndex == 0 { return 0 }
        return (self.maxIndex / Chunk.itemsPerChunk) + 1
    }
    
    @usableFromInline
    func allocateChunk(_ index: Int) {
        assert(index < Self.maxChunks)
        self.chunks.advanced(by: index).initialize(to: Chunk())
    }
    
    func clear() {
        assert(!self.lock.isLocked)
        
        for argumentBuffer in self.enqueuedDisposals {
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
        self.enqueuedDisposals.removeAll()
        
        for chunkIndex in 0..<self.chunkCount {
            self.chunks[chunkIndex].usages.assign(repeating: ResourceUsagesList(), count: Chunk.itemsPerChunk)
        }
    }
    
    func dispose(_ buffer: _ArgumentBuffer) {
        self.lock.withLock {
            self.enqueuedDisposals.append(buffer)
        }
    }
}

@usableFromInline final class TransientArgumentBufferArrayRegistry {
    @usableFromInline static let instances = (0..<TransientRegistryManager.maxTransientRegistries).map { i in TransientArgumentBufferArrayRegistry(transientRegistryIndex: i) }
    
    @usableFromInline let transientRegistryIndex: Int
    @usableFromInline var capacity : Int
    @usableFromInline var count = UnsafeMutablePointer<AtomicInt>.allocate(capacity: 1)
    @usableFromInline var generation : UInt8 = 0
    
    @usableFromInline var bindings : UnsafeMutablePointer<[_ArgumentBuffer?]>! = nil
    @usableFromInline var labels : UnsafeMutablePointer<String?>! = nil
    
    init(transientRegistryIndex: Int) {
        self.transientRegistryIndex = transientRegistryIndex
        self.capacity = 0
    }
    
    func initialise(capacity: Int) {
        self.capacity = capacity
        self.count.initialize(to: AtomicInt(0))
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
        let index = CAtomicsAdd(self.count, 1, .relaxed)
        assert(index < self.capacity)
        assert(index <= 0x1FFFFFFF, "Too many bits required to encode the resource's index.")
        
        self.bindings.advanced(by: index).initialize(to: [])
        self.labels.advanced(by: index).initialize(to: nil)
            
        return UInt64(truncatingIfNeeded: index) | (UInt64(self.generation) << Resource.generationBitsRange.lowerBound) | UInt64(self.transientRegistryIndex) << Resource.transientRegistryIndexBitsRange.lowerBound
    }
    
    @usableFromInline
    func clear() {
        let count = CAtomicsLoad(self.count, .relaxed)
        
        self.bindings.deinitialize(count: count)
        self.labels.deinitialize(count: count)
        let oldCount = CAtomicsExchange(self.count, 0, .relaxed)
        assert(oldCount == count)
        
        self.generation = self.generation &+ 1
    }
}

@usableFromInline final class PersistentArgumentBufferArrayRegistry {
    @usableFromInline static let instance = PersistentArgumentBufferArrayRegistry()
    
    @usableFromInline
    struct Chunk {
        @usableFromInline static let itemsPerChunk = 2048
        
        @usableFromInline let bindings : UnsafeMutablePointer<[_ArgumentBuffer?]>
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
    
    @usableFromInline static let maxChunks = 256
    
    @usableFromInline var lock = SpinLock()
    
    @usableFromInline var freeIndices = RingBuffer<Int>()
    @usableFromInline var maxIndex = 0
    
    @usableFromInline let enqueuedDisposals = ExpandingBuffer<_ArgumentBufferArray>()
    @usableFromInline let chunks : UnsafeMutablePointer<Chunk>
    
    init() {
        self.chunks = .allocate(capacity: Self.maxChunks)
    }
    
    func allocate(flags: ResourceFlags) -> UInt64 {
        return self.lock.withLock {
            let index : Int
            if let reusedIndex = self.freeIndices.popFirst() {
                index = reusedIndex
            } else {
                index = self.maxIndex
                if index % Chunk.itemsPerChunk == 0 {
                    self.allocateChunk(index / Chunk.itemsPerChunk)
                }
                self.maxIndex += 1
            }
            
            let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Chunk.itemsPerChunk)
            
            self.chunks[chunkIndex].bindings.advanced(by: indexInChunk).initialize(to: [])
            self.chunks[chunkIndex].heaps.advanced(by: indexInChunk).initialize(to: nil)
            self.chunks[chunkIndex].labels.advanced(by: indexInChunk).initialize(to: nil)
            
            let generation = self.chunks[chunkIndex].generations[indexInChunk]
            
            return UInt64(truncatingIfNeeded: index) | (UInt64(generation) << Resource.generationBitsRange.lowerBound)
        }
    }
    
    @usableFromInline
    var chunkCount : Int {
        if self.maxIndex == 0 { return 0 }
        return (self.maxIndex / Chunk.itemsPerChunk) + 1
    }
    
    @usableFromInline
    func allocateChunk(_ index: Int) {
        assert(index < Self.maxChunks)
        self.chunks.advanced(by: index).initialize(to: Chunk())
    }
    
    func clear() {
        assert(!self.lock.isLocked)
        
        for argumentBufferArray in self.enqueuedDisposals {
            RenderBackend.dispose(argumentBufferArray: argumentBufferArray)
            
            let index = argumentBufferArray.index
            let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Chunk.itemsPerChunk)
            
            self.chunks[chunkIndex].bindings.advanced(by: indexInChunk).deinitialize(count: 1)
            self.chunks[chunkIndex].bindings.advanced(by: indexInChunk).deinitialize(count: 1)
            self.chunks[chunkIndex].labels.advanced(by: indexInChunk).deinitialize(count: 1)

            self.chunks[chunkIndex].generations[indexInChunk] = self.chunks[chunkIndex].generations[indexInChunk] &+ 1
            
            self.freeIndices.append(index)
        }
        
        self.enqueuedDisposals.removeAll()
    }
    
    func dispose(_ buffer: _ArgumentBufferArray) {
        self.lock.withLock {
            self.enqueuedDisposals.append(buffer)
        }
    }
}


@usableFromInline final class HeapRegistry {
    
    @usableFromInline static let instance = HeapRegistry()
    
    @usableFromInline
    struct Chunk {
        @usableFromInline static let itemsPerChunk = 4096
        
        @usableFromInline let descriptors : UnsafeMutablePointer<HeapDescriptor>
        @usableFromInline let generations : UnsafeMutablePointer<UInt8>
        @usableFromInline let labels : UnsafeMutablePointer<String?>
        
        init() {
            self.descriptors = .allocate(capacity: Chunk.itemsPerChunk)
            self.generations = .allocate(capacity: Chunk.itemsPerChunk)
            self.labels = .allocate(capacity: Chunk.itemsPerChunk)
            
            self.generations.initialize(repeating: 0, count: Chunk.itemsPerChunk)
        }
        
        func deallocate() {
            self.descriptors.deallocate()
            self.generations.deallocate()
            self.labels.deallocate()
        }
    }
    
    @usableFromInline static let maxChunks = 128
    
    @usableFromInline var lock = SpinLock()
    
    @usableFromInline var freeIndices = RingBuffer<Int>()
    @usableFromInline var maxIndex = 0
    @usableFromInline let enqueuedDisposals = ExpandingBuffer<Heap>()
    @usableFromInline let chunks : UnsafeMutablePointer<Chunk>
    
    init() {
        self.chunks = .allocate(capacity: Self.maxChunks)
    }
    
    @usableFromInline
    func allocate(descriptor: HeapDescriptor) -> UInt64 {
        return self.lock.withLock {
            let index : Int
            if let reusedIndex = self.freeIndices.popFirst() {
                index = reusedIndex
            } else {
                index = self.maxIndex
                if self.maxIndex % Chunk.itemsPerChunk == 0 {
                    self.allocateChunk(self.maxIndex / Chunk.itemsPerChunk)
                }
                self.maxIndex += 1
            }
            
            let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: Chunk.itemsPerChunk)
            self.chunks[chunkIndex].descriptors.advanced(by: indexInChunk).initialize(to: descriptor)
            
            return UInt64(truncatingIfNeeded: index)
        }
    }
    
    @usableFromInline var chunkCount : Int {
        if self.maxIndex == 0 { return 0 }
        return (self.maxIndex / Chunk.itemsPerChunk) + 1
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
        
        self.chunks[chunkIndex].generations[indexInChunk] = self.chunks[chunkIndex].generations[indexInChunk] &+ 1
        
        self.freeIndices.append(index)
    }
    
    func clear() {
        assert(!self.lock.isLocked)
        
        for heap in self.enqueuedDisposals {
            self.disposeImmediately(heap: heap)
        }
        
        self.enqueuedDisposals.removeAll()
    }
    
    func dispose(_ heap: Heap, atEndOfFrame: Bool = true) {
        self.lock.withLock {
            if atEndOfFrame {
                self.enqueuedDisposals.append(heap)
            } else {
                self.disposeImmediately(heap: heap)
            }
        }
    }
}
