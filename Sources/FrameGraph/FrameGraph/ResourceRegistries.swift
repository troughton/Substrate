//
//  ResourceRegistries.swift
//  RenderAPI
//
//  Created by Thomas Roughton on 24/07/18.
//

import Utilities
import Dispatch
import Foundation

public protocol BufferRegistry {
    static var instance : Self { get }
    
    var descriptors : UnsafeMutablePointer<BufferDescriptor> { get }
}

// TODO: make persistent resources thread-safe (all accesses must be on a single queue).

@_fixed_layout
public struct TransientBufferRegistry : BufferRegistry {
    public static var instance = TransientBufferRegistry()
    
    public let allocator : ResizingAllocator
    public internal(set) var count = 0
    
    public internal(set) var descriptors : UnsafeMutablePointer<BufferDescriptor>
    public internal(set) var deferredSliceActions : UnsafeMutablePointer<[DeferredBufferSlice]>
    public internal(set) var usages : UnsafeMutablePointer<ResourceUsagesList>
    
    public init() {
        self.allocator = ResizingAllocator(allocator: .system)
        (self.descriptors, self.deferredSliceActions, self.usages) = allocator.reallocate(capacity: 16)
    }
    
    @inlinable
    public mutating func allocate(descriptor: BufferDescriptor, flags: ResourceFlags) -> UInt64 {
        self.ensureCapacity(self.count + 1)
        
        self.descriptors.advanced(by: self.count).initialize(to: descriptor)
        self.deferredSliceActions.advanced(by: self.count).initialize(to: [])
        self.usages.advanced(by: self.count).initialize(to: ResourceUsagesList())
        
        let index = self.count

        self.count += 1
        
        return UInt64(truncatingIfNeeded: index)
    }
    
    @inlinable
    public mutating func ensureCapacity(_ capacity: Int) {
        if self.allocator.capacity < capacity {
            (self.descriptors, self.deferredSliceActions, self.usages) = allocator.reallocate(capacity: 2 * capacity)
        }
    }
    
    @inlinable
    public mutating func clear() {
        self.descriptors.deinitialize(count: self.count)
        self.deferredSliceActions.deinitialize(count: self.count)
        self.usages.deinitialize(count: self.count)
        self.count = 0
    }
}

@_fixed_layout
public struct PersistentBufferRegistry : BufferRegistry {
    
    public static var instance = PersistentBufferRegistry()
    
    public let allocator : ResizingAllocator
    public internal(set) var freeIndices = RingBuffer<Int>()
    public internal(set) var maxIndex = 0
    public let enqueuedDisposals = ExpandingBuffer<Buffer>()
    
    public internal(set) var stateFlags : UnsafeMutablePointer<ResourceStateFlags>
    
    /// The frame that must be completed on the GPU before the CPU can read from this memory.
    public internal(set) var readWaitFrames : UnsafeMutablePointer<UInt64>
    /// The frame that must be completed on the GPU before the CPU can write to this memory.
    public internal(set) var writeWaitFrames : UnsafeMutablePointer<UInt64>
    
    public internal(set) var descriptors : UnsafeMutablePointer<BufferDescriptor>
    public internal(set) var usages : UnsafeMutablePointer<ResourceUsagesList>
    
    public init() {
        self.allocator = ResizingAllocator(allocator: .system)
        (self.stateFlags, self.readWaitFrames, self.writeWaitFrames, self.descriptors, self.usages) = allocator.reallocate(capacity: 16)
    }
    
    @inlinable
    public mutating func allocate(descriptor: BufferDescriptor, flags: ResourceFlags) -> UInt64 {
        
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
        
        return UInt64(truncatingIfNeeded: index)
    }
    
    @inlinable
    public mutating func ensureCapacity(_ capacity: Int) {
        if self.allocator.capacity < capacity {
            (self.stateFlags, self.readWaitFrames, self.writeWaitFrames, self.descriptors, self.usages) = allocator.reallocate(capacity: 2 * capacity)
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
            
            self.freeIndices.append(index)
        }
        self.enqueuedDisposals.removeAll()
        
        self.usages.assign(repeating: ResourceUsagesList(), count: self.maxIndex)
    }
    
    public func dispose(_ buffer: Buffer) {
        self.enqueuedDisposals.append(buffer)
    }
}

public protocol TextureRegistry {
    static var instance : Self { get }
    
    var descriptors : UnsafeMutablePointer<TextureDescriptor> { get }
}

@_fixed_layout
public struct TransientTextureRegistry : TextureRegistry {
    public static var instance = TransientTextureRegistry()
    
    public let allocator : ResizingAllocator
    public internal(set) var count = 0
    
    public internal(set) var descriptors : UnsafeMutablePointer<TextureDescriptor>
    public internal(set) var usages : UnsafeMutablePointer<ResourceUsagesList>
    
    public init() {
        self.allocator = ResizingAllocator(allocator: .system)
        (self.descriptors, self.usages) = allocator.reallocate(capacity: 16)
    }
    
    @inlinable
    public mutating func allocate(descriptor: TextureDescriptor, flags: ResourceFlags) -> UInt64 {
        self.ensureCapacity(self.count + 1)
        
        
        let index = self.count
        
        self.descriptors.advanced(by: index).initialize(to: descriptor)
        self.usages.advanced(by: index).initialize(to: ResourceUsagesList())
        
        self.count += 1
        
        return UInt64(truncatingIfNeeded: index)
    }
    
    @inlinable
    public mutating func ensureCapacity(_ capacity: Int) {
        if self.allocator.capacity < capacity {
            (self.descriptors, self.usages) = allocator.reallocate(capacity: 2 * capacity)
        }
    }
    
    @inlinable
    public mutating func clear() {
        self.descriptors.deinitialize(count: self.count)
        self.usages.deinitialize(count: self.count)
        self.count = 0
    }
}

@_fixed_layout
public struct PersistentTextureRegistry : TextureRegistry {
    public static var instance = PersistentTextureRegistry()
    
    public let allocator : ResizingAllocator
    public internal(set) var freeIndices = RingBuffer<Int>()
    public internal(set) var maxIndex = 0
    public let enqueuedDisposals = ExpandingBuffer<Texture>()
    
    public internal(set) var stateFlags : UnsafeMutablePointer<ResourceStateFlags>
    
    /// The frame that must be completed on the GPU before the CPU can read from this memory.
    public internal(set) var readWaitFrames : UnsafeMutablePointer<UInt64>
    /// The frame that must be completed on the GPU before the CPU can write to this memory.
    public internal(set) var writeWaitFrames : UnsafeMutablePointer<UInt64>
    
    public internal(set) var descriptors : UnsafeMutablePointer<TextureDescriptor>
    public internal(set) var usages : UnsafeMutablePointer<ResourceUsagesList>
    
    public init() {
        self.allocator = ResizingAllocator(allocator: .system)
        (self.stateFlags, self.readWaitFrames, self.writeWaitFrames, self.descriptors, self.usages) = allocator.reallocate(capacity: 16)
    }
    
    @inlinable
    public mutating func allocate(descriptor: TextureDescriptor, flags: ResourceFlags) -> UInt64 {
        
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
        
        return UInt64(truncatingIfNeeded: index)
    }
    
    @inlinable
    public mutating func ensureCapacity(_ capacity: Int) {
        if self.allocator.capacity < capacity {
            (self.stateFlags, self.readWaitFrames, self.writeWaitFrames, self.descriptors, self.usages) = allocator.reallocate(capacity: 2 * capacity)
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
            
            self.freeIndices.append(index)
        }
        self.enqueuedDisposals.removeAll()
        self.usages.assign(repeating: ResourceUsagesList(), count: self.maxIndex)
    }
    
    public func dispose(_ texture: Texture) {
        self.enqueuedDisposals.append(texture)
    }
}

@_fixed_layout
public struct TransientArgumentBufferRegistry {
    public static var instance = TransientArgumentBufferRegistry()
    
    public let allocator : ResizingAllocator
    public let inlineDataAllocator : ExpandingBuffer<UInt8>
    public internal(set) var count = 0
    
    public internal(set) var data : UnsafeMutablePointer<_ArgumentBufferData>
    
    public init() {
        self.allocator = ResizingAllocator(allocator: .system)
        self.inlineDataAllocator = ExpandingBuffer()
        self.data = allocator.reallocate(capacity: 16)
    }
    
    @inlinable
    public mutating func allocate(flags: ResourceFlags) -> UInt64 {
        self.ensureCapacity(self.count + 1)
        
        let index = self.count
        
        self.data.advanced(by: index).initialize(to: _ArgumentBufferData())
        
        self.count += 1
        
        return UInt64(truncatingIfNeeded: index)
    }
    
    @inlinable
    public mutating func ensureCapacity(_ capacity: Int) {
        if self.allocator.capacity < capacity {
            self.data = allocator.reallocate(capacity: 2 * capacity)
        }
    }
    
    @inlinable
    public mutating func clear() {
        self.data.deinitialize(count: self.count)
        self.count = 0
    }
}

@_fixed_layout
public struct PersistentArgumentBufferRegistry {
    public static var instance = PersistentArgumentBufferRegistry()
    
    public let allocator : ResizingAllocator
    public internal(set) var freeIndices = RingBuffer<Int>()
    public internal(set) var maxIndex = 0
    
    public internal(set) var data : UnsafeMutablePointer<_ArgumentBufferData>
    public internal(set) var inlineDataStorage : UnsafeMutablePointer<Data>
    
    public init() {
        self.allocator = ResizingAllocator(allocator: .system)
        (self.data, self.inlineDataStorage) = allocator.reallocate(capacity: 16)
    }
    
    public mutating func allocate(flags: ResourceFlags) -> UInt64 {
        
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
        
        return UInt64(truncatingIfNeeded: index)
    }
    
    @inlinable
    public mutating func ensureCapacity(_ capacity: Int) {
        if self.allocator.capacity < capacity {
            (self.data, self.inlineDataStorage) = allocator.reallocate(capacity: 2 * capacity)
        }
    }
    
    public func dispose(_ argumentBuffer: ArgumentBuffer) {
        RenderBackend.dispose(argumentBuffer: argumentBuffer)
        
        let index = argumentBuffer.index
        
        self.data.advanced(by: index).deinitialize(count: 1)
        self.inlineDataStorage.advanced(by: index).deinitialize(count: 1)
        
        self.freeIndices.append(index)
    }
}

@_fixed_layout
public struct TransientArgumentBufferArrayRegistry {
    public static var instance = TransientArgumentBufferArrayRegistry()
    
    public let allocator : ResizingAllocator
    public internal(set) var count = 0
    
    public internal(set) var bindings : UnsafeMutablePointer<[ArgumentBuffer?]>
    
    public init() {
        self.allocator = ResizingAllocator(allocator: .system)
        self.bindings = allocator.reallocate(capacity: 16)
    }
    
    @inlinable
    public mutating func allocate(flags: ResourceFlags) -> UInt64 {
        self.ensureCapacity(self.count + 1)
        
        let index = self.count
        
        self.bindings.advanced(by: index).initialize(to: [])
        
        self.count += 1
        
        return UInt64(truncatingIfNeeded: index)
    }
    
    @inlinable
    public mutating func ensureCapacity(_ capacity: Int) {
        if self.allocator.capacity < capacity {
            self.bindings = allocator.reallocate(capacity: 2 * capacity)
        }
    }
    
    @inlinable
    public mutating func clear() {
        self.bindings.deinitialize(count: self.count)
        self.count = 0
    }
}

@_fixed_layout
public struct PersistentArgumentBufferArrayRegistry {
    public static var instance = PersistentArgumentBufferArrayRegistry()
    
    public let allocator : ResizingAllocator
    public internal(set) var freeIndices = RingBuffer<Int>()
    public internal(set) var maxIndex = 0
    
    public internal(set) var bindings : UnsafeMutablePointer<[ArgumentBuffer?]>
    
    public init() {
        self.allocator = ResizingAllocator(allocator: .system)
        (self.bindings) = allocator.reallocate(capacity: 16)
    }
    
    public mutating func allocate(flags: ResourceFlags) -> UInt64 {
        
        let index : Int
        if let reusedIndex = self.freeIndices.popFirst() {
            index = reusedIndex
        } else {
            index = self.maxIndex
            self.ensureCapacity(self.maxIndex + 1)
            self.maxIndex += 1
        }
        
        self.bindings.advanced(by: index).initialize(to: [])
        
        return UInt64(truncatingIfNeeded: index)
    }
    
    @inlinable
    public mutating func ensureCapacity(_ capacity: Int) {
        if self.allocator.capacity < capacity {
            (self.bindings) = allocator.reallocate(capacity: 2 * capacity)
        }
    }
    
    public func dispose(_ argumentBuffer: ArgumentBuffer) {
        RenderBackend.dispose(argumentBuffer: argumentBuffer)
        
        let index = argumentBuffer.index
        
        self.bindings.advanced(by: index).deinitialize(count: 1)
        
        self.freeIndices.append(index)
    }
}
