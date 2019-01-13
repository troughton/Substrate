//
//  ResourceRegistries.swift
//  RenderAPI
//
//  Created by Thomas Roughton on 24/07/18.
//

import Utilities
import Dispatch
import Foundation
import Atomics

public protocol BufferRegistry {
    static var instance : Self { get }
    
    var descriptors : UnsafeMutablePointer<BufferDescriptor> { get }
}

// TODO: make persistent resources thread-safe (all accesses must be on a single queue).

@_fixed_layout
public final class TransientBufferRegistry : BufferRegistry {
    public static let instance = TransientBufferRegistry()
    
    public let capacity = 16384
    public var count = AtomicInt()
    
    public var descriptors : UnsafeMutablePointer<BufferDescriptor>
    public var deferredSliceActions : UnsafeMutablePointer<[DeferredBufferSlice]>
    public var usages : UnsafeMutablePointer<ResourceUsagesList>
    public var labels : UnsafeMutablePointer<String?>
    
    public init() {
        self.descriptors = UnsafeMutablePointer.allocate(capacity: self.capacity)
        self.deferredSliceActions = UnsafeMutablePointer.allocate(capacity: self.capacity)
        self.usages = UnsafeMutablePointer.allocate(capacity: self.capacity)
        self.labels = UnsafeMutablePointer.allocate(capacity: self.capacity)
        self.count.initialize(0)
    }
    
    @inlinable
    public func allocate(descriptor: BufferDescriptor, flags: ResourceFlags) -> UInt64 {
        
        let index = self.count.increment()
        self.ensureCapacity(index + 1)
        
        self.descriptors.advanced(by: index).initialize(to: descriptor)
        self.deferredSliceActions.advanced(by: index).initialize(to: [])
        self.usages.advanced(by: index).initialize(to: ResourceUsagesList())
        self.labels.advanced(by: index).initialize(to: nil)
        
        assert(index <= 0x1FFFFFFF, "Too many bits required to encode the resource's index.")
        
        return UInt64(truncatingIfNeeded: index) | ((FrameGraph.currentFrameIndex & 0b111) << 29)
    }
    
    @inlinable
    public func ensureCapacity(_ capacity: Int) {
        assert(capacity <= self.capacity)
    }
    
    @inlinable
    public func clear() {
        let count = self.count.swap(0, order: .relaxed)
        self.descriptors.deinitialize(count: count)
        self.deferredSliceActions.deinitialize(count: count)
        self.usages.deinitialize(count: count)
        self.labels.deinitialize(count: count)
    }
}

@_fixed_layout
public final class PersistentBufferRegistry : BufferRegistry {
    
    public static let instance = PersistentBufferRegistry()
    
    public let queue = DispatchQueue(label: "Persistent Buffer Registry Queue")
    
    public let allocator : ResizingAllocator
    public var freeIndices = RingBuffer<Int>()
    public var maxIndex = 0
    public let enqueuedDisposals = ExpandingBuffer<Buffer>()
    
    public var stateFlags : UnsafeMutablePointer<ResourceStateFlags>
    
    /// The frame that must be completed on the GPU before the CPU can read from this memory.
    public var readWaitFrames : UnsafeMutablePointer<UInt64>
    /// The frame that must be completed on the GPU before the CPU can write to this memory.
    public var writeWaitFrames : UnsafeMutablePointer<UInt64>
    
    public var descriptors : UnsafeMutablePointer<BufferDescriptor>
    public var usages : UnsafeMutablePointer<ResourceUsagesList>
    
    public var labels : UnsafeMutablePointer<String?>
    
    public init() {
        self.allocator = ResizingAllocator(allocator: .system)
        (self.stateFlags, self.readWaitFrames, self.writeWaitFrames, self.descriptors, self.usages, self.labels) = allocator.reallocate(capacity: 16)
    }
    
    @inlinable
    public func allocate(descriptor: BufferDescriptor, flags: ResourceFlags) -> UInt64 {
        return self.queue.sync {
            let index : Int
            if let reusedIndex = self.freeIndices.popFirst() {
                index = reusedIndex
            } else {
                index = self.maxIndex
                self.ensureCapacity(self.maxIndex + 1)
                self.maxIndex += 1
            }
            
            self.stateFlags.advanced(by: index).initialize(to: [])
            self.readWaitFrames.advanced(by: index).initialize(to: 0)
            self.writeWaitFrames.advanced(by: index).initialize(to: 0)
            self.descriptors.advanced(by: index).initialize(to: descriptor)
            self.usages.advanced(by: index).initialize(to: ResourceUsagesList())
            self.labels.advanced(by: index).initialize(to: nil)
            
            return UInt64(truncatingIfNeeded: index)
        }
    }
    
    @inlinable
    public func ensureCapacity(_ capacity: Int) {
        if self.allocator.capacity < capacity {
            (self.stateFlags, self.readWaitFrames, self.writeWaitFrames, self.descriptors, self.usages, self.labels) = allocator.reallocate(capacity: 2 * capacity)
        }
    }
    
    public func clear() {
        for buffer in self.enqueuedDisposals {
            RenderBackend.dispose(buffer: buffer)
            
            let index = buffer.index
            
            self.stateFlags.advanced(by: index).deinitialize(count: 1)
            self.readWaitFrames.advanced(by: index).deinitialize(count: 1)
            self.writeWaitFrames.advanced(by: index).deinitialize(count: 1)
            self.descriptors.advanced(by: index).deinitialize(count: 1)
            self.labels.advanced(by: index).deinitialize(count: 1)
            
            self.freeIndices.append(index)
        }
        self.enqueuedDisposals.removeAll()
        
        self.usages.assign(repeating: ResourceUsagesList(), count: self.maxIndex)
    }
    
    public func dispose(_ buffer: Buffer) {
        self.queue.sync {
            self.enqueuedDisposals.append(buffer)
        }
    }
}

public protocol TextureRegistry {
    static var instance : Self { get }
    
    var descriptors : UnsafeMutablePointer<TextureDescriptor> { get }
}

@_fixed_layout
public final class TransientTextureRegistry : TextureRegistry {
    public static let instance = TransientTextureRegistry()
    
    public let capacity = 16384
    public var count = AtomicInt()
    
    public var descriptors : UnsafeMutablePointer<TextureDescriptor>
    public var usages : UnsafeMutablePointer<ResourceUsagesList>
    
    public var labels : UnsafeMutablePointer<String?>
    
    public init() {
        self.descriptors = UnsafeMutablePointer.allocate(capacity: self.capacity)
        self.usages = UnsafeMutablePointer.allocate(capacity: self.capacity)
        self.labels = UnsafeMutablePointer.allocate(capacity: self.capacity)
        self.count.initialize(0)
    }
    
    @inlinable
    public func allocate(descriptor: TextureDescriptor, flags: ResourceFlags) -> UInt64 {
        let index = self.count.increment()
        self.ensureCapacity(index + 1)
        assert(index <= 0x1FFFFFFF, "Too many bits required to encode the resource's index.")
        
        self.descriptors.advanced(by: index).initialize(to: descriptor)
        self.usages.advanced(by: index).initialize(to: ResourceUsagesList())
        self.labels.advanced(by: index).initialize(to: nil)
        
        return UInt64(truncatingIfNeeded: index) | ((FrameGraph.currentFrameIndex & 0b111) << 29)
    }
    
    @inlinable
    public func ensureCapacity(_ capacity: Int) {
        assert(capacity <= self.capacity)
    }
    
    @inlinable
    public func clear() {
        let count = self.count.swap(0)
        self.descriptors.deinitialize(count: count)
        self.usages.deinitialize(count: count)
        self.labels.deinitialize(count: count)
    }
}

@_fixed_layout
public final class PersistentTextureRegistry : TextureRegistry {
    public static let instance = PersistentTextureRegistry()
    public let queue = DispatchQueue(label: "Persistent Texture Registry Queue")
    
    public let allocator : ResizingAllocator
    public var freeIndices = RingBuffer<Int>()
    public var maxIndex = 0
    public let enqueuedDisposals = ExpandingBuffer<Texture>()
    
    public var stateFlags : UnsafeMutablePointer<ResourceStateFlags>
    
    /// The frame that must be completed on the GPU before the CPU can read from this memory.
    public var readWaitFrames : UnsafeMutablePointer<UInt64>
    /// The frame that must be completed on the GPU before the CPU can write to this memory.
    public var writeWaitFrames : UnsafeMutablePointer<UInt64>
    
    public var descriptors : UnsafeMutablePointer<TextureDescriptor>
    public var usages : UnsafeMutablePointer<ResourceUsagesList>
    
    public var labels : UnsafeMutablePointer<String?>
    
    public init() {
        self.allocator = ResizingAllocator(allocator: .system)
        (self.stateFlags, self.readWaitFrames, self.writeWaitFrames, self.descriptors, self.usages, self.labels) = allocator.reallocate(capacity: 16)
    }
    
    @inlinable
    public func allocate(descriptor: TextureDescriptor, flags: ResourceFlags) -> UInt64 {
        
        return self.queue.sync {
            let index : Int
            if let reusedIndex = self.freeIndices.popFirst() {
                index = reusedIndex
            } else {
                index = self.maxIndex
                self.ensureCapacity(self.maxIndex + 1)
                self.maxIndex += 1
            }
            
            self.stateFlags.advanced(by: index).initialize(to: [])
            self.readWaitFrames.advanced(by: index).initialize(to: 0)
            self.writeWaitFrames.advanced(by: index).initialize(to: 0)
            self.descriptors.advanced(by: index).initialize(to: descriptor)
            self.usages.advanced(by: index).initialize(to: ResourceUsagesList())
            self.labels.advanced(by: index).initialize(to: nil)
            
            return UInt64(truncatingIfNeeded: index)
        }
    }
    
    @inlinable
    public func ensureCapacity(_ capacity: Int) {
        if self.allocator.capacity < capacity {
            (self.stateFlags, self.readWaitFrames, self.writeWaitFrames, self.descriptors, self.usages, self.labels) = allocator.reallocate(capacity: 2 * capacity)
        }
    }
    
    public func clear() {
        for texture in self.enqueuedDisposals {
            RenderBackend.dispose(texture: texture)
            
            let index = texture.index
            
            self.stateFlags.advanced(by: index).deinitialize(count: 1)
            self.readWaitFrames.advanced(by: index).deinitialize(count: 1)
            self.writeWaitFrames.advanced(by: index).deinitialize(count: 1)
            self.descriptors.advanced(by: index).deinitialize(count: 1)
            self.labels.advanced(by: index).deinitialize(count: 1)
            
            self.freeIndices.append(index)
        }
        self.enqueuedDisposals.removeAll()
        self.usages.assign(repeating: ResourceUsagesList(), count: self.maxIndex)
    }
    
    public func dispose(_ texture: Texture) {
        self.queue.sync {
            self.enqueuedDisposals.append(texture)
        }
    }
}

@_fixed_layout
public final class TransientArgumentBufferRegistry {
    public static let instance = TransientArgumentBufferRegistry()
    
    public let queue = DispatchQueue(label: "Transient Argument Buffer Registry Queue")
    
    public let allocator : ResizingAllocator
    public let inlineDataAllocator : ExpandingBuffer<UInt8>
    public var count = 0
    
    public var data : UnsafeMutablePointer<_ArgumentBufferData>
    
    public var labels : UnsafeMutablePointer<String?>
    
    public init() {
        self.allocator = ResizingAllocator(allocator: .system)
        self.inlineDataAllocator = ExpandingBuffer()
        (self.data, self.labels) = allocator.reallocate(capacity: 16)
    }
    
    @inlinable
    public func allocate(flags: ResourceFlags) -> UInt64 {
        return self.queue.sync {
            self.ensureCapacity(self.count + 1)
            
            let index = self.count
            assert(index <= 0x1FFFFFFF, "Too many bits required to encode the resource's index.")
            
            self.data.advanced(by: index).initialize(to: _ArgumentBufferData())
            self.labels.advanced(by: index).initialize(to: nil)
            self.count += 1
            
            return UInt64(truncatingIfNeeded: index) | ((FrameGraph.currentFrameIndex & 0b111) << 29)
        }
    }
    
    @inlinable
    public func ensureCapacity(_ capacity: Int) {
        if self.allocator.capacity < capacity {
            (self.data, self.labels) = allocator.reallocate(capacity: 2 * capacity)
        }
    }
    
    @inlinable
    public func clear() {
        self.data.deinitialize(count: self.count)
        self.labels.deinitialize(count: self.count)
        self.count = 0
    }
}

@_fixed_layout
public final class PersistentArgumentBufferRegistry {
    public static let instance = PersistentArgumentBufferRegistry()
    public let queue = DispatchQueue(label: "Persistent Argument Buffer Registry Queue")
    
    public let allocator : ResizingAllocator
    public var freeIndices = RingBuffer<Int>()
    public var maxIndex = 0
    
    public var data : UnsafeMutablePointer<_ArgumentBufferData>
    public var inlineDataStorage : UnsafeMutablePointer<Data>
    
    public var labels : UnsafeMutablePointer<String?>
    
    public init() {
        self.allocator = ResizingAllocator(allocator: .system)
        (self.data, self.inlineDataStorage, self.labels) = allocator.reallocate(capacity: 16)
    }
    
    public func allocate(flags: ResourceFlags) -> UInt64 {
        return self.queue.sync {
            let index : Int
            if let reusedIndex = self.freeIndices.popFirst() {
                index = reusedIndex
            } else {
                index = self.maxIndex
                self.ensureCapacity(self.maxIndex + 1)
                self.maxIndex += 1
            }
            
            self.data.advanced(by: index).initialize(to: _ArgumentBufferData())
            self.inlineDataStorage.advanced(by: index).initialize(to: Data())
            self.labels.advanced(by: index).initialize(to: nil)
            
            return UInt64(truncatingIfNeeded: index)
        }
    }
    
    @inlinable
    public func ensureCapacity(_ capacity: Int) {
        if self.allocator.capacity < capacity {
            (self.data, self.inlineDataStorage, self.labels) = allocator.reallocate(capacity: 2 * capacity)
        }
    }
    
    public func dispose(_ argumentBuffer: ArgumentBuffer) {
        self.queue.sync {
            RenderBackend.dispose(argumentBuffer: argumentBuffer)
            
            let index = argumentBuffer.index
            
            self.data.advanced(by: index).deinitialize(count: 1)
            self.inlineDataStorage.advanced(by: index).deinitialize(count: 1)
            self.labels.advanced(by: index).deinitialize(count: 1)
            
            self.freeIndices.append(index)
        }
    }
}

@_fixed_layout
public final class TransientArgumentBufferArrayRegistry {
    public static let instance = TransientArgumentBufferArrayRegistry()
    public let queue = DispatchQueue(label: "Persistent Argument Buffer Registry Queue")
    
    public let allocator : ResizingAllocator
    public var count = 0
    
    public var bindings : UnsafeMutablePointer<[ArgumentBuffer?]>
    
    public var labels : UnsafeMutablePointer<String?>
    
    public init() {
        self.allocator = ResizingAllocator(allocator: .system)
        (self.bindings, self.labels) = allocator.reallocate(capacity: 16)
    }
    
    @inlinable
    public func allocate(flags: ResourceFlags) -> UInt64 {
        return self.queue.sync {
            self.ensureCapacity(self.count + 1)
            
            let index = self.count
            assert(index <= 0x1FFFFFFF, "Too many bits required to encode the resource's index.")
            
            self.bindings.advanced(by: index).initialize(to: [])
            self.labels.advanced(by: index).initialize(to: nil)
            self.count += 1
            
            return UInt64(truncatingIfNeeded: index) | ((FrameGraph.currentFrameIndex & 0b111) << 29)
        }
    }
    
    @inlinable
    public func ensureCapacity(_ capacity: Int) {
        if self.allocator.capacity < capacity {
            (self.bindings, self.labels) = allocator.reallocate(capacity: 2 * capacity)
        }
    }
    
    @inlinable
    public func clear() {
        self.bindings.deinitialize(count: self.count)
        self.labels.deinitialize(count: self.count)
        self.count = 0
    }
}

@_fixed_layout
public final class PersistentArgumentBufferArrayRegistry {
    public static let instance = PersistentArgumentBufferArrayRegistry()
    public let queue = DispatchQueue(label: "Persistent Argument Buffer Registry Queue")
    
    public let allocator : ResizingAllocator
    public var freeIndices = RingBuffer<Int>()
    public var maxIndex = 0
    
    public var bindings : UnsafeMutablePointer<[ArgumentBuffer?]>
    
    public var labels : UnsafeMutablePointer<String?>
    
    public init() {
        self.allocator = ResizingAllocator(allocator: .system)
        (self.bindings, self.labels) = allocator.reallocate(capacity: 16)
    }
    
    public func allocate(flags: ResourceFlags) -> UInt64 {
        return self.queue.sync {
            let index : Int
            if let reusedIndex = self.freeIndices.popFirst() {
                index = reusedIndex
            } else {
                index = self.maxIndex
                self.ensureCapacity(self.maxIndex + 1)
                self.maxIndex += 1
            }
            
            self.bindings.advanced(by: index).initialize(to: [])
            self.labels.advanced(by: index).initialize(to: nil)
            
            return UInt64(truncatingIfNeeded: index)
        }
    }
    
    @inlinable
    public func ensureCapacity(_ capacity: Int) {
        if self.allocator.capacity < capacity {
            (self.bindings, self.labels) = allocator.reallocate(capacity: 2 * capacity)
        }
    }
    
    public func dispose(_ argumentBufferArray: ArgumentBufferArray) {
        self.queue.sync {
            print("Warning: disposal of non-transient ArgumentBufferArrays isn't implemented in RenderBackend.")
//            RenderBackend.dispose(argumentBuffer: argumentBuffer)
            
            let index = argumentBufferArray.index
            
            self.bindings.advanced(by: index).deinitialize(count: 1)
            self.labels.advanced(by: index).deinitialize(count: 1)
            
            self.freeIndices.append(index)
        }
    }
}
