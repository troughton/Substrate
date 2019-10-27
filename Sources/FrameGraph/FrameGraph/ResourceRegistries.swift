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

public final class TransientBufferRegistry {
    public static let instance = TransientBufferRegistry()
    
    public let capacity = 16384
    public var count = UnsafeMutablePointer<AtomicInt>.allocate(capacity: 1)
    
    public let descriptors : UnsafeMutablePointer<BufferDescriptor>
    public let deferredSliceActions : UnsafeMutablePointer<[DeferredBufferSlice]>
    public let usages : UnsafeMutablePointer<ResourceUsagesList>
    public let labels : UnsafeMutablePointer<String?>
    
    public init() {
        self.count.initialize(to: AtomicInt(0))
        self.descriptors = UnsafeMutablePointer.allocate(capacity: self.capacity)
        self.deferredSliceActions = UnsafeMutablePointer.allocate(capacity: self.capacity)
        self.usages = UnsafeMutablePointer.allocate(capacity: self.capacity)
        self.labels = UnsafeMutablePointer.allocate(capacity: self.capacity)
    }
    
    @inlinable
    public func allocate(descriptor: BufferDescriptor, flags: ResourceFlags) -> UInt64 {
        
        let index = CAtomicsAdd(self.count, 1, .relaxed)
        self.ensureCapacity(index + 1)
        
        self.descriptors.advanced(by: index).initialize(to: descriptor)
        self.deferredSliceActions.advanced(by: index).initialize(to: [])
        self.usages.advanced(by: index).initialize(to: ResourceUsagesList())
        self.labels.advanced(by: index).initialize(to: nil)
        
        assert(index <= 0x1FFFFFFF, "Too many bits required to encode the resource's index.")
        
        return UInt64(truncatingIfNeeded: index) | ((FrameGraph.activeFrameGraph!.currentFrameIndex & 0xFF) << Resource.generationBitsRange.lowerBound)
    }
    
    @inlinable
    func ensureCapacity(_ capacity: Int) {
        assert(capacity <= self.capacity)
    }
    
    @inlinable
    public func clear() {
        let count = CAtomicsExchange(self.count, 0, .relaxed)
        self.descriptors.deinitialize(count: count)
        self.deferredSliceActions.deinitialize(count: count)
        self.usages.deinitialize(count: count)
        self.labels.deinitialize(count: count)
        
        assert(CAtomicsLoad(self.count, .relaxed) == 0)
    }
}

public final class PersistentBufferRegistry {
    
    public static let instance = PersistentBufferRegistry()
    
    public struct Chunk {
        public static let itemsPerChunk = 4096
        
        public let stateFlags : UnsafeMutablePointer<ResourceStateFlags>
        /// The index that must be completed on the GPU for each queue before the CPU can read from this memory.
        public let readWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The index that must be completed on the GPU for each queue before the CPU can write to this memory.
        public let writeWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        public let descriptors : UnsafeMutablePointer<BufferDescriptor>
        public let usages : UnsafeMutablePointer<ResourceUsagesList>
        public let heaps : UnsafeMutablePointer<Heap>
        public let generations : UnsafeMutablePointer<UInt8>
        public let labels : UnsafeMutablePointer<String?>
        
        public init() {
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
        
        public func deallocate() {
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
    
    public static let maxChunks = 128
    
    public var lock = SpinLock()
    
    public var freeIndices = RingBuffer<Int>()
    public var maxIndex = 0
    public let enqueuedDisposals = ExpandingBuffer<Buffer>()
    public let chunks : UnsafeMutablePointer<Chunk>
    
    public init() {
        self.chunks = .allocate(capacity: Self.maxChunks)
    }
    
    @inlinable
    public func allocate(descriptor: BufferDescriptor, heap: Heap?, flags: ResourceFlags) -> UInt64 {
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
            self.chunks[chunkIndex].heaps.advanced(by: indexInChunk).initialize(to: heap ?? Heap(handle: Resource.invalidResource.handle))
            self.chunks[chunkIndex].labels.advanced(by: indexInChunk).initialize(to: nil)
            
            let generation = self.chunks[chunkIndex].generations[indexInChunk]
            
            return UInt64(truncatingIfNeeded: index) | (UInt64(generation) << Resource.generationBitsRange.lowerBound)
        }
    }
    
    var chunkCount : Int {
        if self.maxIndex == 0 { return 0 }
        return (self.maxIndex / Chunk.itemsPerChunk) + 1
    }
    
    @inlinable
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
    
    public func clear() {
        assert(!self.lock.isLocked)
        
        for buffer in self.enqueuedDisposals {
            self.disposeImmediately(buffer: buffer)
        }
        
        self.enqueuedDisposals.removeAll()
        
        for chunkIndex in 0..<self.chunkCount {
            self.chunks[chunkIndex].usages.assign(repeating: ResourceUsagesList(), count: Chunk.itemsPerChunk)
        }
    }
    
    public func dispose(_ buffer: Buffer, atEndOfFrame: Bool = true) {
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

public final class TransientTextureRegistry {
    public static let instance = TransientTextureRegistry()
    
    public let capacity = 16384
    public var count = UnsafeMutablePointer<AtomicInt>.allocate(capacity: 1)
    
    public var descriptors : UnsafeMutablePointer<TextureDescriptor>
    public var usages : UnsafeMutablePointer<ResourceUsagesList>
    
    public var labels : UnsafeMutablePointer<String?>
    public var baseResources : UnsafeMutablePointer<Resource>
    public var textureViewInfos : UnsafeMutablePointer<TextureViewBaseInfo?>
    
    public init() {
        self.count.initialize(to: AtomicInt(0))
        self.descriptors = UnsafeMutablePointer.allocate(capacity: self.capacity)
        self.usages = UnsafeMutablePointer.allocate(capacity: self.capacity)
        self.labels = UnsafeMutablePointer.allocate(capacity: self.capacity)
        self.baseResources = UnsafeMutablePointer.allocate(capacity: self.capacity)
        self.textureViewInfos = UnsafeMutablePointer.allocate(capacity: self.capacity)
    }
    
    @inlinable
    public func allocate(descriptor: TextureDescriptor, flags: ResourceFlags) -> UInt64 {
        let index = CAtomicsAdd(self.count, 1, .relaxed)
        self.ensureCapacity(index + 1)
        assert(index <= 0x1FFFFFFF, "Too many bits required to encode the resource's index.")
        
        self.descriptors.advanced(by: index).initialize(to: descriptor)
        self.usages.advanced(by: index).initialize(to: ResourceUsagesList())
        self.labels.advanced(by: index).initialize(to: nil)
        self.baseResources.advanced(by: index).initialize(to: Resource.invalidResource)
        self.textureViewInfos.advanced(by: index).initialize(to: nil)
        
        return UInt64(truncatingIfNeeded: index) | ((FrameGraph.activeFrameGraph!.currentFrameIndex & 0xFF) << Resource.generationBitsRange.lowerBound)
    }
    
    @inlinable
    public func allocate(descriptor: Buffer.TextureViewDescriptor, baseResource: Buffer) -> UInt64 {
        let index = CAtomicsAdd(self.count, 1, .relaxed)
        self.ensureCapacity(index + 1)
        assert(index <= 0x1FFFFFFF, "Too many bits required to encode the resource's index.")
        
        self.descriptors.advanced(by: index).initialize(to: descriptor.descriptor)
        self.usages.advanced(by: index).initialize(to: ResourceUsagesList())
        self.labels.advanced(by: index).initialize(to: nil)
        self.baseResources.advanced(by: index).initialize(to: Resource(baseResource))
        self.textureViewInfos.advanced(by: index).initialize(to: .buffer(descriptor))
        
        baseResource.descriptor.usageHint.formUnion(.textureView)
        
        return UInt64(truncatingIfNeeded: index) | ((FrameGraph.activeFrameGraph!.currentFrameIndex & 0xFF) << Resource.generationBitsRange.lowerBound)
    }
    
    @inlinable
    public func allocate(descriptor viewDescriptor: Texture.TextureViewDescriptor, baseResource: Texture) -> UInt64 {
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
        
        return UInt64(truncatingIfNeeded: index) | ((FrameGraph.activeFrameGraph!.currentFrameIndex & 0xFF) << Resource.generationBitsRange.lowerBound)
    }
    
    @inlinable
    func ensureCapacity(_ capacity: Int) {
        assert(capacity <= self.capacity)
    }
    
    @inlinable
    public func clear() {
        let count = CAtomicsExchange(self.count, 0, .relaxed)
        self.descriptors.deinitialize(count: count)
        self.usages.deinitialize(count: count)
        self.labels.deinitialize(count: count)
        self.baseResources.deinitialize(count: count)
        self.textureViewInfos.deinitialize(count: count)
        
        assert(CAtomicsLoad(self.count, .relaxed) == 0)
    }
}

public final class PersistentTextureRegistry {
    public static let instance = PersistentTextureRegistry()
    
    public struct Chunk {
        public static let itemsPerChunk = 4096
        
        public let stateFlags : UnsafeMutablePointer<ResourceStateFlags>
        /// The index that must be completed on the GPU for each queue before the CPU can read from this memory.
        public let readWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The index that must be completed on the GPU for each queue before the CPU can write to this memory.
        public let writeWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        public let descriptors : UnsafeMutablePointer<TextureDescriptor>
        public let usages : UnsafeMutablePointer<ResourceUsagesList>
        public let heaps : UnsafeMutablePointer<Heap>
        public let generations : UnsafeMutablePointer<UInt8>
        public let labels : UnsafeMutablePointer<String?>
        
        public init() {
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
        
        public func deallocate() {
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
    
    public static let maxChunks = 128
    
    public var lock = SpinLock()
    
    public var freeIndices = RingBuffer<Int>()
    public var maxIndex = 0
    public let enqueuedDisposals = ExpandingBuffer<Texture>()
    public let chunks : UnsafeMutablePointer<Chunk>
    
    public init() {
        self.chunks = .allocate(capacity: Self.maxChunks)
    }
    
    @inlinable
    public func allocate(descriptor: TextureDescriptor, heap: Heap?, flags: ResourceFlags) -> UInt64 {
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
            self.chunks[chunkIndex].heaps.advanced(by: indexInChunk).initialize(to: heap ?? Heap(handle: Resource.invalidResource.handle))
            self.chunks[chunkIndex].labels.advanced(by: indexInChunk).initialize(to: nil)
            
            let generation = self.chunks[chunkIndex].generations[indexInChunk]
            
            return UInt64(truncatingIfNeeded: index) | (UInt64(generation) << Resource.generationBitsRange.lowerBound)
        }
    }
    
    var chunkCount : Int {
        if self.maxIndex == 0 { return 0 }
        return (self.maxIndex / Chunk.itemsPerChunk) + 1
    }
    
    @inlinable
    func allocateChunk(_ index: Int) {
        assert(index < Self.maxChunks)
        self.chunks.advanced(by: index).initialize(to: Chunk())
    }
    
    public func clear() {
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
    
    public func dispose(_ texture: Texture) {
        self.lock.withLock {
            self.enqueuedDisposals.append(texture)
        }
    }
}

// Unlike the other transient registries, the transient argument buffer registry is chunk-based.
// This is because the number of argument buffers used within a frame can vary dramatically, and so a pre-assigned maximum is more likely to be hit.
public final class TransientArgumentBufferRegistry {
    public static let instance = TransientArgumentBufferRegistry()
    
    public struct Chunk {
        public static let itemsPerChunk = 2048
        
        public let usages : UnsafeMutablePointer<ResourceUsagesList>
        public let encoders : UnsafeMutablePointer<AtomicOptionalRawPointer> // Some opaque backend type that can construct the argument buffer
        public let enqueuedBindings : UnsafeMutablePointer<ExpandingBuffer<(FunctionArgumentKey, Int, _ArgumentBuffer.ArgumentResource)>>
        public let bindings : UnsafeMutablePointer<ExpandingBuffer<(ResourceBindingPath, _ArgumentBuffer.ArgumentResource)>>
        public let sourceArrays : UnsafeMutablePointer<_ArgumentBufferArray>
        
        public let labels : UnsafeMutablePointer<String?>
        
        public init() {
            self.usages = .allocate(capacity: Chunk.itemsPerChunk)
            self.encoders = .allocate(capacity: Chunk.itemsPerChunk)
            self.enqueuedBindings = .allocate(capacity: Chunk.itemsPerChunk)
            self.bindings = .allocate(capacity: Chunk.itemsPerChunk)
            self.sourceArrays = .allocate(capacity: Chunk.itemsPerChunk)
            self.labels = .allocate(capacity: Chunk.itemsPerChunk)
        }
        
        public func deallocate() {
            self.usages.deallocate()
            self.encoders.deallocate()
            self.enqueuedBindings.deallocate()
            self.bindings.deallocate()
            self.sourceArrays.deallocate()
            self.labels.deallocate()
        }
    }
    
    public static let maxChunks = 256
    
    public var lock = SpinLock()
    
    public let inlineDataAllocator : ExpandingBuffer<UInt8>
    public var count = 0
    public let chunks : UnsafeMutablePointer<Chunk>
    public var allocatedChunkCount = 0
    
    public init() {
        self.inlineDataAllocator = ExpandingBuffer()
        self.chunks = .allocate(capacity: Self.maxChunks)
    }
    
    @inlinable
    public func allocate(flags: ResourceFlags) -> UInt64 {
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
            self.chunks[chunkIndex].sourceArrays.advanced(by: indexInChunk).initialize(to: _ArgumentBufferArray(handle: Resource.invalidResource.handle))
            self.chunks[chunkIndex].labels.advanced(by: indexInChunk).initialize(to: nil)
            self.count += 1
            
            return UInt64(truncatingIfNeeded: index) | ((FrameGraph.activeFrameGraph!.currentFrameIndex & 0xFF) << Resource.generationBitsRange.lowerBound)
        }
    }
    
    @inlinable
    public func allocate(flags: ResourceFlags, sourceArray: _ArgumentBufferArray) -> UInt64 {
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
            
            return UInt64(truncatingIfNeeded: index) | ((FrameGraph.activeFrameGraph!.currentFrameIndex & 0xFF) << Resource.generationBitsRange.lowerBound)
        }
    }
    
    var chunkCount : Int {
        if self.count == 0 { return 0 }
        return (self.count / Chunk.itemsPerChunk) + 1
    }
    
    @inlinable
    func allocateChunk(_ index: Int) {
        assert(index < Self.maxChunks)
        assert(index == self.allocatedChunkCount)
        self.chunks.advanced(by: index).initialize(to: Chunk())
        self.allocatedChunkCount += 1
    }
    
    public func clear() {
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
    }
}

public final class PersistentArgumentBufferRegistry {
    public static let instance = PersistentArgumentBufferRegistry()
    
    public struct Chunk {
        public static let itemsPerChunk = 2048
        
        public let usages : UnsafeMutablePointer<ResourceUsagesList>
        public let encoders : UnsafeMutablePointer<AtomicOptionalRawPointer> // Some opaque backend type that can construct the argument buffer
        public let enqueuedBindings : UnsafeMutablePointer<ExpandingBuffer<(FunctionArgumentKey, Int, _ArgumentBuffer.ArgumentResource)>>
        public let bindings : UnsafeMutablePointer<ExpandingBuffer<(ResourceBindingPath, _ArgumentBuffer.ArgumentResource)>>
        public let inlineDataStorage : UnsafeMutablePointer<Data>
        public let sourceArrays : UnsafeMutablePointer<_ArgumentBufferArray>
        public let heaps : UnsafeMutablePointer<Heap>
        public let generations : UnsafeMutablePointer<UInt8>
        
        public let labels : UnsafeMutablePointer<String?>
        
        public init() {
            self.usages = .allocate(capacity: Chunk.itemsPerChunk)
            self.encoders = .allocate(capacity: Chunk.itemsPerChunk)
            self.enqueuedBindings = .allocate(capacity: Chunk.itemsPerChunk)
            self.bindings = .allocate(capacity: Chunk.itemsPerChunk)
            self.inlineDataStorage = .allocate(capacity: Chunk.itemsPerChunk)
            self.sourceArrays = .allocate(capacity: Chunk.itemsPerChunk)
            self.heaps = .allocate(capacity: Chunk.itemsPerChunk)
            self.generations = .allocate(capacity: Chunk.itemsPerChunk)
            self.labels = .allocate(capacity: Chunk.itemsPerChunk)
            
            self.generations.initialize(repeating: 0, count: Chunk.itemsPerChunk)
        }
        
        public func deallocate() {
            self.usages.deallocate()
            self.encoders.deallocate()
            self.enqueuedBindings.deallocate()
            self.bindings.deallocate()
            self.inlineDataStorage.deallocate()
            self.sourceArrays.deallocate()
            self.heaps.deallocate()
            self.generations.deallocate()
            self.labels.deallocate()
        }
    }
    
    public static let maxChunks = 256
    
    public var lock = SpinLock()
    
    public var freeIndices = RingBuffer<Int>()
    public var maxIndex = 0
    
    public let enqueuedDisposals = ExpandingBuffer<_ArgumentBuffer>()
    public let chunks : UnsafeMutablePointer<Chunk>
    
    public init() {
        self.chunks = .allocate(capacity: Self.maxChunks)
    }
    
    public func allocate(flags: ResourceFlags) -> UInt64 {
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
            self.chunks[chunkIndex].heaps.advanced(by: indexInChunk).initialize(to: Heap(handle: Resource.invalidResource.handle))
            self.chunks[chunkIndex].labels.advanced(by: indexInChunk).initialize(to: nil)
            
            let generation = self.chunks[chunkIndex].generations[indexInChunk]
            
            return UInt64(truncatingIfNeeded: index) | (UInt64(generation) << Resource.generationBitsRange.lowerBound)
        }
    }
    
    public func allocate(flags: ResourceFlags, sourceArray: _ArgumentBufferArray) -> UInt64 {
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
            self.chunks[chunkIndex].heaps.advanced(by: indexInChunk).initialize(to: Heap(handle: Resource.invalidResource.handle))
            self.chunks[chunkIndex].labels.advanced(by: indexInChunk).initialize(to: nil)
            
            let generation = self.chunks[chunkIndex].generations[indexInChunk]
            
            return UInt64(truncatingIfNeeded: index) | (UInt64(generation) << Resource.generationBitsRange.lowerBound)
        }
    }
    
    var chunkCount : Int {
        if self.maxIndex == 0 { return 0 }
        return (self.maxIndex / Chunk.itemsPerChunk) + 1
    }
    
    @inlinable
    func allocateChunk(_ index: Int) {
        assert(index < Self.maxChunks)
        self.chunks.advanced(by: index).initialize(to: Chunk())
    }
    
    public func clear() {
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
    
    public func dispose(_ buffer: _ArgumentBuffer) {
        self.lock.withLock {
            self.enqueuedDisposals.append(buffer)
        }
    }
}

public final class TransientArgumentBufferArrayRegistry {
    public static let instance = TransientArgumentBufferArrayRegistry()
    
    public let capacity = 1024
    public var count = UnsafeMutablePointer<AtomicInt>.allocate(capacity: 1)
    
    public let bindings : UnsafeMutablePointer<[_ArgumentBuffer?]>
    public let labels : UnsafeMutablePointer<String?>
    
    public init() {
        self.count.initialize(to: AtomicInt(0))
        self.bindings = .allocate(capacity: capacity)
        self.labels = .allocate(capacity: capacity)
    }
    
    deinit {
        self.clear()
        self.bindings.deallocate()
        self.labels.deallocate()
    }
    
    @inlinable
    public func allocate(flags: ResourceFlags) -> UInt64 {
        let index = CAtomicsAdd(self.count, 1, .relaxed)
        assert(index < self.capacity)
        assert(index <= 0x1FFFFFFF, "Too many bits required to encode the resource's index.")
        
        self.bindings.advanced(by: index).initialize(to: [])
        self.labels.advanced(by: index).initialize(to: nil)
            
        return UInt64(truncatingIfNeeded: index) | ((FrameGraph.activeFrameGraph!.currentFrameIndex & 0xFF) << Resource.generationBitsRange.lowerBound)
    }
    
    @inlinable
    public func clear() {
        let count = CAtomicsLoad(self.count, .relaxed)
        
        self.bindings.deinitialize(count: count)
        self.labels.deinitialize(count: count)
        let oldCount = CAtomicsExchange(self.count, 0, .relaxed)
        assert(oldCount == count)
    }
}

public final class PersistentArgumentBufferArrayRegistry {
    public static let instance = PersistentArgumentBufferArrayRegistry()
    
    public struct Chunk {
        public static let itemsPerChunk = 2048
        
        public let bindings : UnsafeMutablePointer<[_ArgumentBuffer?]>
        public let heaps : UnsafeMutablePointer<Heap>
        public let generations : UnsafeMutablePointer<UInt8>
        public let labels : UnsafeMutablePointer<String?>
        
        public init() {
            self.bindings = .allocate(capacity: Chunk.itemsPerChunk)
            self.heaps = .allocate(capacity: Chunk.itemsPerChunk)
            self.generations = .allocate(capacity: Chunk.itemsPerChunk)
            self.labels = .allocate(capacity: Chunk.itemsPerChunk)
            
            self.generations.initialize(repeating: 0, count: Chunk.itemsPerChunk)
        }
        
        public func deallocate() {
            self.bindings.deallocate()
            self.heaps.deallocate()
            self.generations.deallocate()
            self.labels.deallocate()
        }
    }
    
    public static let maxChunks = 256
    
    public var lock = SpinLock()
    
    public var freeIndices = RingBuffer<Int>()
    public var maxIndex = 0
    
    public let enqueuedDisposals = ExpandingBuffer<_ArgumentBufferArray>()
    public let chunks : UnsafeMutablePointer<Chunk>
    
    public init() {
        self.chunks = .allocate(capacity: Self.maxChunks)
    }
    
    public func allocate(flags: ResourceFlags) -> UInt64 {
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
            self.chunks[chunkIndex].heaps.advanced(by: indexInChunk).initialize(to: Heap(handle: Resource.invalidResource.handle))
            self.chunks[chunkIndex].labels.advanced(by: indexInChunk).initialize(to: nil)
            
            let generation = self.chunks[chunkIndex].generations[indexInChunk]
            
            return UInt64(truncatingIfNeeded: index) | (UInt64(generation) << Resource.generationBitsRange.lowerBound)
        }
    }
    
    var chunkCount : Int {
        if self.maxIndex == 0 { return 0 }
        return (self.maxIndex / Chunk.itemsPerChunk) + 1
    }
    
    @inlinable
    func allocateChunk(_ index: Int) {
        assert(index < Self.maxChunks)
        self.chunks.advanced(by: index).initialize(to: Chunk())
    }
    
    public func clear() {
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
    
    public func dispose(_ buffer: _ArgumentBufferArray) {
        self.lock.withLock {
            self.enqueuedDisposals.append(buffer)
        }
    }
}


public final class HeapRegistry {
    
    public static let instance = HeapRegistry()
    
    public struct Chunk {
        public static let itemsPerChunk = 4096
        
        public let descriptors : UnsafeMutablePointer<HeapDescriptor>
        public let generations : UnsafeMutablePointer<UInt8>
        public let labels : UnsafeMutablePointer<String?>
        
        public init() {
            self.descriptors = .allocate(capacity: Chunk.itemsPerChunk)
            self.generations = .allocate(capacity: Chunk.itemsPerChunk)
            self.labels = .allocate(capacity: Chunk.itemsPerChunk)
            
            self.generations.initialize(repeating: 0, count: Chunk.itemsPerChunk)
        }
        
        public func deallocate() {
            self.descriptors.deallocate()
            self.generations.deallocate()
            self.labels.deallocate()
        }
    }
    
    public static let maxChunks = 128
    
    public var lock = SpinLock()
    
    public var freeIndices = RingBuffer<Int>()
    public var maxIndex = 0
    public let enqueuedDisposals = ExpandingBuffer<Heap>()
    public let chunks : UnsafeMutablePointer<Chunk>
    
    public init() {
        self.chunks = .allocate(capacity: Self.maxChunks)
    }
    
    @inlinable
    public func allocate(descriptor: HeapDescriptor) -> UInt64 {
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
    
    var chunkCount : Int {
        if self.maxIndex == 0 { return 0 }
        return (self.maxIndex / Chunk.itemsPerChunk) + 1
    }
    
    @inlinable
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
    
    public func clear() {
        assert(!self.lock.isLocked)
        
        for heap in self.enqueuedDisposals {
            self.disposeImmediately(heap: heap)
        }
        
        self.enqueuedDisposals.removeAll()
    }
    
    public func dispose(_ heap: Heap, atEndOfFrame: Bool = true) {
        self.lock.withLock {
            if atEndOfFrame {
                self.enqueuedDisposals.append(heap)
            } else {
                self.disposeImmediately(heap: heap)
            }
        }
    }
}
