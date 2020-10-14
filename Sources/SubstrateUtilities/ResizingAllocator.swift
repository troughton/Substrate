// NOTE: Auto-generated from Generators/ResizingAllocator.swift

import Foundation

public final class ResizingAllocator {
    public let allocator : AllocatorType
    public var capacity : Int = 0
    @usableFromInline
    var buffer : UnsafeMutableRawPointer! = nil
    
    public init(allocator: AllocatorType = .system) {
        self.allocator = allocator
    }
    
    deinit {
        if let buffer = self.buffer {
            Allocator.deallocate(buffer, allocator: self.allocator)
        }
    }
    
    @inlinable @inline(__always)
    public func reallocate<A>(capacity: Int, initializedCount: Int) -> (UnsafeMutablePointer<A>) {
        assert(capacity >= self.capacity)
        
        let alignment = MemoryLayout<A>.alignment
        
        var oldSize = 0
        var size = 0
        size = size.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffset = size
        size += capacity * MemoryLayout<A>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<A>.stride
        
        let newBuffer = Allocator.allocate(byteCount: size, alignment: alignment, allocator: self.allocator)
        
        let ABuffer = (newBuffer + AOffset).bindMemory(to: A.self, capacity: capacity)
        
        if let oldBuffer = self.buffer {
            ABuffer.moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self), count: initializedCount)
            Allocator.deallocate(oldBuffer, allocator: self.allocator)
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer
        )
    }
    
    @inlinable @inline(__always)
    public func reallocate<A>(capacity: Int, isElementInitialized: (Int) -> Bool) -> (UnsafeMutablePointer<A>) {
        assert(capacity >= self.capacity)
        
        let alignment = MemoryLayout<A>.alignment
        
        var oldSize = 0
        var size = 0
        size = size.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffset = size
        size += capacity * MemoryLayout<A>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<A>.stride
        
        let newBuffer = Allocator.allocate(byteCount: size, alignment: alignment, allocator: self.allocator)
        
        let ABuffer = (newBuffer + AOffset).bindMemory(to: A.self, capacity: capacity)
        
        if let oldBuffer = self.buffer {
            for i in 0..<self.capacity where isElementInitialized(i) {
                ABuffer.advanced(by: i).moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self).advanced(by: i), count: 1)
            }
            
            Allocator.deallocate(oldBuffer, allocator: self.allocator)
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer
        )
    }
    
    @inlinable @inline(__always)
    public func reallocate<A, B>(capacity: Int, initializedCount: Int) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>) {
        assert(capacity >= self.capacity)
        
        var alignment = MemoryLayout<A>.alignment
        alignment = max(alignment, MemoryLayout<B>.alignment)
        var oldSize = 0
        var size = 0
        size = size.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffset = size
        size += capacity * MemoryLayout<A>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<A>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffset = size
        size += capacity * MemoryLayout<B>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<B>.stride
        
        let newBuffer = Allocator.allocate(byteCount: size, alignment: alignment, allocator: self.allocator)
        
        let ABuffer = (newBuffer + AOffset).bindMemory(to: A.self, capacity: capacity)
        let BBuffer = (newBuffer + BOffset).bindMemory(to: B.self, capacity: capacity)
        
        if let oldBuffer = self.buffer {
            ABuffer.moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self), count: initializedCount)
            BBuffer.moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self), count: initializedCount)
            Allocator.deallocate(oldBuffer, allocator: self.allocator)
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer,
                BBuffer
        )
    }
    
    @inlinable @inline(__always)
    public func reallocate<A, B>(capacity: Int, isElementInitialized: (Int) -> Bool) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>) {
        assert(capacity >= self.capacity)
        
        var alignment = MemoryLayout<A>.alignment
        alignment = max(alignment, MemoryLayout<B>.alignment)
        var oldSize = 0
        var size = 0
        size = size.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffset = size
        size += capacity * MemoryLayout<A>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<A>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffset = size
        size += capacity * MemoryLayout<B>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<B>.stride
        
        let newBuffer = Allocator.allocate(byteCount: size, alignment: alignment, allocator: self.allocator)
        
        let ABuffer = (newBuffer + AOffset).bindMemory(to: A.self, capacity: capacity)
        let BBuffer = (newBuffer + BOffset).bindMemory(to: B.self, capacity: capacity)
        
        if let oldBuffer = self.buffer {
            for i in 0..<self.capacity where isElementInitialized(i) {
                ABuffer.advanced(by: i).moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self).advanced(by: i), count: 1)
                BBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self).advanced(by: i), count: 1)
            }
            
            Allocator.deallocate(oldBuffer, allocator: self.allocator)
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer,
                BBuffer
        )
    }
    
    @inlinable @inline(__always)
    public func reallocate<A, B, C>(capacity: Int, initializedCount: Int) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>) {
        assert(capacity >= self.capacity)
        
        var alignment = MemoryLayout<A>.alignment
        alignment = max(alignment, MemoryLayout<B>.alignment)
        alignment = max(alignment, MemoryLayout<C>.alignment)
        var oldSize = 0
        var size = 0
        size = size.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffset = size
        size += capacity * MemoryLayout<A>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<A>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffset = size
        size += capacity * MemoryLayout<B>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<B>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffset = size
        size += capacity * MemoryLayout<C>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<C>.stride
        
        let newBuffer = Allocator.allocate(byteCount: size, alignment: alignment, allocator: self.allocator)
        
        let ABuffer = (newBuffer + AOffset).bindMemory(to: A.self, capacity: capacity)
        let BBuffer = (newBuffer + BOffset).bindMemory(to: B.self, capacity: capacity)
        let CBuffer = (newBuffer + COffset).bindMemory(to: C.self, capacity: capacity)
        
        if let oldBuffer = self.buffer {
            ABuffer.moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self), count: initializedCount)
            BBuffer.moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self), count: initializedCount)
            CBuffer.moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self), count: initializedCount)
            Allocator.deallocate(oldBuffer, allocator: self.allocator)
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer,
                BBuffer,
                CBuffer
        )
    }
    
    @inlinable @inline(__always)
    public func reallocate<A, B, C>(capacity: Int, isElementInitialized: (Int) -> Bool) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>) {
        assert(capacity >= self.capacity)
        
        var alignment = MemoryLayout<A>.alignment
        alignment = max(alignment, MemoryLayout<B>.alignment)
        alignment = max(alignment, MemoryLayout<C>.alignment)
        var oldSize = 0
        var size = 0
        size = size.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffset = size
        size += capacity * MemoryLayout<A>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<A>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffset = size
        size += capacity * MemoryLayout<B>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<B>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffset = size
        size += capacity * MemoryLayout<C>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<C>.stride
        
        let newBuffer = Allocator.allocate(byteCount: size, alignment: alignment, allocator: self.allocator)
        
        let ABuffer = (newBuffer + AOffset).bindMemory(to: A.self, capacity: capacity)
        let BBuffer = (newBuffer + BOffset).bindMemory(to: B.self, capacity: capacity)
        let CBuffer = (newBuffer + COffset).bindMemory(to: C.self, capacity: capacity)
        
        if let oldBuffer = self.buffer {
            for i in 0..<self.capacity where isElementInitialized(i) {
                ABuffer.advanced(by: i).moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self).advanced(by: i), count: 1)
                BBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self).advanced(by: i), count: 1)
                CBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self).advanced(by: i), count: 1)
            }
            
            Allocator.deallocate(oldBuffer, allocator: self.allocator)
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer,
                BBuffer,
                CBuffer
        )
    }
    
    @inlinable @inline(__always)
    public func reallocate<A, B, C, D>(capacity: Int, initializedCount: Int) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>, UnsafeMutablePointer<D>) {
        assert(capacity >= self.capacity)
        
        var alignment = MemoryLayout<A>.alignment
        alignment = max(alignment, MemoryLayout<B>.alignment)
        alignment = max(alignment, MemoryLayout<C>.alignment)
        alignment = max(alignment, MemoryLayout<D>.alignment)
        var oldSize = 0
        var size = 0
        size = size.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffset = size
        size += capacity * MemoryLayout<A>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<A>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffset = size
        size += capacity * MemoryLayout<B>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<B>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffset = size
        size += capacity * MemoryLayout<C>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<C>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffset = size
        size += capacity * MemoryLayout<D>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<D>.stride
        
        let newBuffer = Allocator.allocate(byteCount: size, alignment: alignment, allocator: self.allocator)
        
        let ABuffer = (newBuffer + AOffset).bindMemory(to: A.self, capacity: capacity)
        let BBuffer = (newBuffer + BOffset).bindMemory(to: B.self, capacity: capacity)
        let CBuffer = (newBuffer + COffset).bindMemory(to: C.self, capacity: capacity)
        let DBuffer = (newBuffer + DOffset).bindMemory(to: D.self, capacity: capacity)
        
        if let oldBuffer = self.buffer {
            ABuffer.moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self), count: initializedCount)
            BBuffer.moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self), count: initializedCount)
            CBuffer.moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self), count: initializedCount)
            DBuffer.moveInitialize(from: (oldBuffer + DOffsetOld).assumingMemoryBound(to: D.self), count: initializedCount)
            Allocator.deallocate(oldBuffer, allocator: self.allocator)
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer,
                BBuffer,
                CBuffer,
                DBuffer
        )
    }
    
    @inlinable @inline(__always)
    public func reallocate<A, B, C, D>(capacity: Int, isElementInitialized: (Int) -> Bool) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>, UnsafeMutablePointer<D>) {
        assert(capacity >= self.capacity)
        
        var alignment = MemoryLayout<A>.alignment
        alignment = max(alignment, MemoryLayout<B>.alignment)
        alignment = max(alignment, MemoryLayout<C>.alignment)
        alignment = max(alignment, MemoryLayout<D>.alignment)
        var oldSize = 0
        var size = 0
        size = size.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffset = size
        size += capacity * MemoryLayout<A>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<A>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffset = size
        size += capacity * MemoryLayout<B>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<B>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffset = size
        size += capacity * MemoryLayout<C>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<C>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffset = size
        size += capacity * MemoryLayout<D>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<D>.stride
        
        let newBuffer = Allocator.allocate(byteCount: size, alignment: alignment, allocator: self.allocator)
        
        let ABuffer = (newBuffer + AOffset).bindMemory(to: A.self, capacity: capacity)
        let BBuffer = (newBuffer + BOffset).bindMemory(to: B.self, capacity: capacity)
        let CBuffer = (newBuffer + COffset).bindMemory(to: C.self, capacity: capacity)
        let DBuffer = (newBuffer + DOffset).bindMemory(to: D.self, capacity: capacity)
        
        if let oldBuffer = self.buffer {
            for i in 0..<self.capacity where isElementInitialized(i) {
                ABuffer.advanced(by: i).moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self).advanced(by: i), count: 1)
                BBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self).advanced(by: i), count: 1)
                CBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self).advanced(by: i), count: 1)
                DBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + DOffsetOld).assumingMemoryBound(to: D.self).advanced(by: i), count: 1)
            }
            
            Allocator.deallocate(oldBuffer, allocator: self.allocator)
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer,
                BBuffer,
                CBuffer,
                DBuffer
        )
    }
    
    @inlinable @inline(__always)
    public func reallocate<A, B, C, D, E>(capacity: Int, initializedCount: Int) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>, UnsafeMutablePointer<D>, UnsafeMutablePointer<E>) {
        assert(capacity >= self.capacity)
        
        var alignment = MemoryLayout<A>.alignment
        alignment = max(alignment, MemoryLayout<B>.alignment)
        alignment = max(alignment, MemoryLayout<C>.alignment)
        alignment = max(alignment, MemoryLayout<D>.alignment)
        alignment = max(alignment, MemoryLayout<E>.alignment)
        var oldSize = 0
        var size = 0
        size = size.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffset = size
        size += capacity * MemoryLayout<A>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<A>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffset = size
        size += capacity * MemoryLayout<B>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<B>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffset = size
        size += capacity * MemoryLayout<C>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<C>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffset = size
        size += capacity * MemoryLayout<D>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<D>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffset = size
        size += capacity * MemoryLayout<E>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<E>.stride
        
        let newBuffer = Allocator.allocate(byteCount: size, alignment: alignment, allocator: self.allocator)
        
        let ABuffer = (newBuffer + AOffset).bindMemory(to: A.self, capacity: capacity)
        let BBuffer = (newBuffer + BOffset).bindMemory(to: B.self, capacity: capacity)
        let CBuffer = (newBuffer + COffset).bindMemory(to: C.self, capacity: capacity)
        let DBuffer = (newBuffer + DOffset).bindMemory(to: D.self, capacity: capacity)
        let EBuffer = (newBuffer + EOffset).bindMemory(to: E.self, capacity: capacity)
        
        if let oldBuffer = self.buffer {
            ABuffer.moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self), count: initializedCount)
            BBuffer.moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self), count: initializedCount)
            CBuffer.moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self), count: initializedCount)
            DBuffer.moveInitialize(from: (oldBuffer + DOffsetOld).assumingMemoryBound(to: D.self), count: initializedCount)
            EBuffer.moveInitialize(from: (oldBuffer + EOffsetOld).assumingMemoryBound(to: E.self), count: initializedCount)
            Allocator.deallocate(oldBuffer, allocator: self.allocator)
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer,
                BBuffer,
                CBuffer,
                DBuffer,
                EBuffer
        )
    }
    
    @inlinable @inline(__always)
    public func reallocate<A, B, C, D, E>(capacity: Int, isElementInitialized: (Int) -> Bool) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>, UnsafeMutablePointer<D>, UnsafeMutablePointer<E>) {
        assert(capacity >= self.capacity)
        
        var alignment = MemoryLayout<A>.alignment
        alignment = max(alignment, MemoryLayout<B>.alignment)
        alignment = max(alignment, MemoryLayout<C>.alignment)
        alignment = max(alignment, MemoryLayout<D>.alignment)
        alignment = max(alignment, MemoryLayout<E>.alignment)
        var oldSize = 0
        var size = 0
        size = size.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffset = size
        size += capacity * MemoryLayout<A>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<A>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffset = size
        size += capacity * MemoryLayout<B>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<B>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffset = size
        size += capacity * MemoryLayout<C>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<C>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffset = size
        size += capacity * MemoryLayout<D>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<D>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffset = size
        size += capacity * MemoryLayout<E>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<E>.stride
        
        let newBuffer = Allocator.allocate(byteCount: size, alignment: alignment, allocator: self.allocator)
        
        let ABuffer = (newBuffer + AOffset).bindMemory(to: A.self, capacity: capacity)
        let BBuffer = (newBuffer + BOffset).bindMemory(to: B.self, capacity: capacity)
        let CBuffer = (newBuffer + COffset).bindMemory(to: C.self, capacity: capacity)
        let DBuffer = (newBuffer + DOffset).bindMemory(to: D.self, capacity: capacity)
        let EBuffer = (newBuffer + EOffset).bindMemory(to: E.self, capacity: capacity)
        
        if let oldBuffer = self.buffer {
            for i in 0..<self.capacity where isElementInitialized(i) {
                ABuffer.advanced(by: i).moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self).advanced(by: i), count: 1)
                BBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self).advanced(by: i), count: 1)
                CBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self).advanced(by: i), count: 1)
                DBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + DOffsetOld).assumingMemoryBound(to: D.self).advanced(by: i), count: 1)
                EBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + EOffsetOld).assumingMemoryBound(to: E.self).advanced(by: i), count: 1)
            }
            
            Allocator.deallocate(oldBuffer, allocator: self.allocator)
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer,
                BBuffer,
                CBuffer,
                DBuffer,
                EBuffer
        )
    }
    
    @inlinable @inline(__always)
    public func reallocate<A, B, C, D, E, F>(capacity: Int, initializedCount: Int) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>, UnsafeMutablePointer<D>, UnsafeMutablePointer<E>, UnsafeMutablePointer<F>) {
        assert(capacity >= self.capacity)
        
        var alignment = MemoryLayout<A>.alignment
        alignment = max(alignment, MemoryLayout<B>.alignment)
        alignment = max(alignment, MemoryLayout<C>.alignment)
        alignment = max(alignment, MemoryLayout<D>.alignment)
        alignment = max(alignment, MemoryLayout<E>.alignment)
        alignment = max(alignment, MemoryLayout<F>.alignment)
        var oldSize = 0
        var size = 0
        size = size.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffset = size
        size += capacity * MemoryLayout<A>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<A>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffset = size
        size += capacity * MemoryLayout<B>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<B>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffset = size
        size += capacity * MemoryLayout<C>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<C>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffset = size
        size += capacity * MemoryLayout<D>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<D>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffset = size
        size += capacity * MemoryLayout<E>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<E>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffset = size
        size += capacity * MemoryLayout<F>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<F>.stride
        
        let newBuffer = Allocator.allocate(byteCount: size, alignment: alignment, allocator: self.allocator)
        
        let ABuffer = (newBuffer + AOffset).bindMemory(to: A.self, capacity: capacity)
        let BBuffer = (newBuffer + BOffset).bindMemory(to: B.self, capacity: capacity)
        let CBuffer = (newBuffer + COffset).bindMemory(to: C.self, capacity: capacity)
        let DBuffer = (newBuffer + DOffset).bindMemory(to: D.self, capacity: capacity)
        let EBuffer = (newBuffer + EOffset).bindMemory(to: E.self, capacity: capacity)
        let FBuffer = (newBuffer + FOffset).bindMemory(to: F.self, capacity: capacity)
        
        if let oldBuffer = self.buffer {
            ABuffer.moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self), count: initializedCount)
            BBuffer.moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self), count: initializedCount)
            CBuffer.moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self), count: initializedCount)
            DBuffer.moveInitialize(from: (oldBuffer + DOffsetOld).assumingMemoryBound(to: D.self), count: initializedCount)
            EBuffer.moveInitialize(from: (oldBuffer + EOffsetOld).assumingMemoryBound(to: E.self), count: initializedCount)
            FBuffer.moveInitialize(from: (oldBuffer + FOffsetOld).assumingMemoryBound(to: F.self), count: initializedCount)
            Allocator.deallocate(oldBuffer, allocator: self.allocator)
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer,
                BBuffer,
                CBuffer,
                DBuffer,
                EBuffer,
                FBuffer
        )
    }
    
    @inlinable @inline(__always)
    public func reallocate<A, B, C, D, E, F>(capacity: Int, isElementInitialized: (Int) -> Bool) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>, UnsafeMutablePointer<D>, UnsafeMutablePointer<E>, UnsafeMutablePointer<F>) {
        assert(capacity >= self.capacity)
        
        var alignment = MemoryLayout<A>.alignment
        alignment = max(alignment, MemoryLayout<B>.alignment)
        alignment = max(alignment, MemoryLayout<C>.alignment)
        alignment = max(alignment, MemoryLayout<D>.alignment)
        alignment = max(alignment, MemoryLayout<E>.alignment)
        alignment = max(alignment, MemoryLayout<F>.alignment)
        var oldSize = 0
        var size = 0
        size = size.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffset = size
        size += capacity * MemoryLayout<A>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<A>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffset = size
        size += capacity * MemoryLayout<B>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<B>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffset = size
        size += capacity * MemoryLayout<C>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<C>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffset = size
        size += capacity * MemoryLayout<D>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<D>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffset = size
        size += capacity * MemoryLayout<E>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<E>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffset = size
        size += capacity * MemoryLayout<F>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<F>.stride
        
        let newBuffer = Allocator.allocate(byteCount: size, alignment: alignment, allocator: self.allocator)
        
        let ABuffer = (newBuffer + AOffset).bindMemory(to: A.self, capacity: capacity)
        let BBuffer = (newBuffer + BOffset).bindMemory(to: B.self, capacity: capacity)
        let CBuffer = (newBuffer + COffset).bindMemory(to: C.self, capacity: capacity)
        let DBuffer = (newBuffer + DOffset).bindMemory(to: D.self, capacity: capacity)
        let EBuffer = (newBuffer + EOffset).bindMemory(to: E.self, capacity: capacity)
        let FBuffer = (newBuffer + FOffset).bindMemory(to: F.self, capacity: capacity)
        
        if let oldBuffer = self.buffer {
            for i in 0..<self.capacity where isElementInitialized(i) {
                ABuffer.advanced(by: i).moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self).advanced(by: i), count: 1)
                BBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self).advanced(by: i), count: 1)
                CBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self).advanced(by: i), count: 1)
                DBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + DOffsetOld).assumingMemoryBound(to: D.self).advanced(by: i), count: 1)
                EBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + EOffsetOld).assumingMemoryBound(to: E.self).advanced(by: i), count: 1)
                FBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + FOffsetOld).assumingMemoryBound(to: F.self).advanced(by: i), count: 1)
            }
            
            Allocator.deallocate(oldBuffer, allocator: self.allocator)
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer,
                BBuffer,
                CBuffer,
                DBuffer,
                EBuffer,
                FBuffer
        )
    }
    
    @inlinable @inline(__always)
    public func reallocate<A, B, C, D, E, F, G>(capacity: Int, initializedCount: Int) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>, UnsafeMutablePointer<D>, UnsafeMutablePointer<E>, UnsafeMutablePointer<F>, UnsafeMutablePointer<G>) {
        assert(capacity >= self.capacity)
        
        var alignment = MemoryLayout<A>.alignment
        alignment = max(alignment, MemoryLayout<B>.alignment)
        alignment = max(alignment, MemoryLayout<C>.alignment)
        alignment = max(alignment, MemoryLayout<D>.alignment)
        alignment = max(alignment, MemoryLayout<E>.alignment)
        alignment = max(alignment, MemoryLayout<F>.alignment)
        alignment = max(alignment, MemoryLayout<G>.alignment)
        var oldSize = 0
        var size = 0
        size = size.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffset = size
        size += capacity * MemoryLayout<A>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<A>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffset = size
        size += capacity * MemoryLayout<B>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<B>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffset = size
        size += capacity * MemoryLayout<C>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<C>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffset = size
        size += capacity * MemoryLayout<D>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<D>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffset = size
        size += capacity * MemoryLayout<E>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<E>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffset = size
        size += capacity * MemoryLayout<F>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<F>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<G>.alignment)
        let GOffset = size
        size += capacity * MemoryLayout<G>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<G>.alignment)
        let GOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<G>.stride
        
        let newBuffer = Allocator.allocate(byteCount: size, alignment: alignment, allocator: self.allocator)
        
        let ABuffer = (newBuffer + AOffset).bindMemory(to: A.self, capacity: capacity)
        let BBuffer = (newBuffer + BOffset).bindMemory(to: B.self, capacity: capacity)
        let CBuffer = (newBuffer + COffset).bindMemory(to: C.self, capacity: capacity)
        let DBuffer = (newBuffer + DOffset).bindMemory(to: D.self, capacity: capacity)
        let EBuffer = (newBuffer + EOffset).bindMemory(to: E.self, capacity: capacity)
        let FBuffer = (newBuffer + FOffset).bindMemory(to: F.self, capacity: capacity)
        let GBuffer = (newBuffer + GOffset).bindMemory(to: G.self, capacity: capacity)
        
        if let oldBuffer = self.buffer {
            ABuffer.moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self), count: initializedCount)
            BBuffer.moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self), count: initializedCount)
            CBuffer.moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self), count: initializedCount)
            DBuffer.moveInitialize(from: (oldBuffer + DOffsetOld).assumingMemoryBound(to: D.self), count: initializedCount)
            EBuffer.moveInitialize(from: (oldBuffer + EOffsetOld).assumingMemoryBound(to: E.self), count: initializedCount)
            FBuffer.moveInitialize(from: (oldBuffer + FOffsetOld).assumingMemoryBound(to: F.self), count: initializedCount)
            GBuffer.moveInitialize(from: (oldBuffer + GOffsetOld).assumingMemoryBound(to: G.self), count: initializedCount)
            Allocator.deallocate(oldBuffer, allocator: self.allocator)
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer,
                BBuffer,
                CBuffer,
                DBuffer,
                EBuffer,
                FBuffer,
                GBuffer
        )
    }
    
    @inlinable @inline(__always)
    public func reallocate<A, B, C, D, E, F, G>(capacity: Int, isElementInitialized: (Int) -> Bool) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>, UnsafeMutablePointer<D>, UnsafeMutablePointer<E>, UnsafeMutablePointer<F>, UnsafeMutablePointer<G>) {
        assert(capacity >= self.capacity)
        
        var alignment = MemoryLayout<A>.alignment
        alignment = max(alignment, MemoryLayout<B>.alignment)
        alignment = max(alignment, MemoryLayout<C>.alignment)
        alignment = max(alignment, MemoryLayout<D>.alignment)
        alignment = max(alignment, MemoryLayout<E>.alignment)
        alignment = max(alignment, MemoryLayout<F>.alignment)
        alignment = max(alignment, MemoryLayout<G>.alignment)
        var oldSize = 0
        var size = 0
        size = size.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffset = size
        size += capacity * MemoryLayout<A>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<A>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffset = size
        size += capacity * MemoryLayout<B>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<B>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffset = size
        size += capacity * MemoryLayout<C>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<C>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffset = size
        size += capacity * MemoryLayout<D>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<D>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffset = size
        size += capacity * MemoryLayout<E>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<E>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffset = size
        size += capacity * MemoryLayout<F>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<F>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<G>.alignment)
        let GOffset = size
        size += capacity * MemoryLayout<G>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<G>.alignment)
        let GOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<G>.stride
        
        let newBuffer = Allocator.allocate(byteCount: size, alignment: alignment, allocator: self.allocator)
        
        let ABuffer = (newBuffer + AOffset).bindMemory(to: A.self, capacity: capacity)
        let BBuffer = (newBuffer + BOffset).bindMemory(to: B.self, capacity: capacity)
        let CBuffer = (newBuffer + COffset).bindMemory(to: C.self, capacity: capacity)
        let DBuffer = (newBuffer + DOffset).bindMemory(to: D.self, capacity: capacity)
        let EBuffer = (newBuffer + EOffset).bindMemory(to: E.self, capacity: capacity)
        let FBuffer = (newBuffer + FOffset).bindMemory(to: F.self, capacity: capacity)
        let GBuffer = (newBuffer + GOffset).bindMemory(to: G.self, capacity: capacity)
        
        if let oldBuffer = self.buffer {
            for i in 0..<self.capacity where isElementInitialized(i) {
                ABuffer.advanced(by: i).moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self).advanced(by: i), count: 1)
                BBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self).advanced(by: i), count: 1)
                CBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self).advanced(by: i), count: 1)
                DBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + DOffsetOld).assumingMemoryBound(to: D.self).advanced(by: i), count: 1)
                EBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + EOffsetOld).assumingMemoryBound(to: E.self).advanced(by: i), count: 1)
                FBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + FOffsetOld).assumingMemoryBound(to: F.self).advanced(by: i), count: 1)
                GBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + GOffsetOld).assumingMemoryBound(to: G.self).advanced(by: i), count: 1)
            }
            
            Allocator.deallocate(oldBuffer, allocator: self.allocator)
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer,
                BBuffer,
                CBuffer,
                DBuffer,
                EBuffer,
                FBuffer,
                GBuffer
        )
    }
    
    @inlinable @inline(__always)
    public func reallocate<A, B, C, D, E, F, G, H>(capacity: Int, initializedCount: Int) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>, UnsafeMutablePointer<D>, UnsafeMutablePointer<E>, UnsafeMutablePointer<F>, UnsafeMutablePointer<G>, UnsafeMutablePointer<H>) {
        assert(capacity >= self.capacity)
        
        var alignment = MemoryLayout<A>.alignment
        alignment = max(alignment, MemoryLayout<B>.alignment)
        alignment = max(alignment, MemoryLayout<C>.alignment)
        alignment = max(alignment, MemoryLayout<D>.alignment)
        alignment = max(alignment, MemoryLayout<E>.alignment)
        alignment = max(alignment, MemoryLayout<F>.alignment)
        alignment = max(alignment, MemoryLayout<G>.alignment)
        alignment = max(alignment, MemoryLayout<H>.alignment)
        var oldSize = 0
        var size = 0
        size = size.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffset = size
        size += capacity * MemoryLayout<A>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<A>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffset = size
        size += capacity * MemoryLayout<B>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<B>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffset = size
        size += capacity * MemoryLayout<C>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<C>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffset = size
        size += capacity * MemoryLayout<D>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<D>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffset = size
        size += capacity * MemoryLayout<E>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<E>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffset = size
        size += capacity * MemoryLayout<F>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<F>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<G>.alignment)
        let GOffset = size
        size += capacity * MemoryLayout<G>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<G>.alignment)
        let GOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<G>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<H>.alignment)
        let HOffset = size
        size += capacity * MemoryLayout<H>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<H>.alignment)
        let HOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<H>.stride
        
        let newBuffer = Allocator.allocate(byteCount: size, alignment: alignment, allocator: self.allocator)
        
        let ABuffer = (newBuffer + AOffset).bindMemory(to: A.self, capacity: capacity)
        let BBuffer = (newBuffer + BOffset).bindMemory(to: B.self, capacity: capacity)
        let CBuffer = (newBuffer + COffset).bindMemory(to: C.self, capacity: capacity)
        let DBuffer = (newBuffer + DOffset).bindMemory(to: D.self, capacity: capacity)
        let EBuffer = (newBuffer + EOffset).bindMemory(to: E.self, capacity: capacity)
        let FBuffer = (newBuffer + FOffset).bindMemory(to: F.self, capacity: capacity)
        let GBuffer = (newBuffer + GOffset).bindMemory(to: G.self, capacity: capacity)
        let HBuffer = (newBuffer + HOffset).bindMemory(to: H.self, capacity: capacity)
        
        if let oldBuffer = self.buffer {
            ABuffer.moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self), count: initializedCount)
            BBuffer.moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self), count: initializedCount)
            CBuffer.moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self), count: initializedCount)
            DBuffer.moveInitialize(from: (oldBuffer + DOffsetOld).assumingMemoryBound(to: D.self), count: initializedCount)
            EBuffer.moveInitialize(from: (oldBuffer + EOffsetOld).assumingMemoryBound(to: E.self), count: initializedCount)
            FBuffer.moveInitialize(from: (oldBuffer + FOffsetOld).assumingMemoryBound(to: F.self), count: initializedCount)
            GBuffer.moveInitialize(from: (oldBuffer + GOffsetOld).assumingMemoryBound(to: G.self), count: initializedCount)
            HBuffer.moveInitialize(from: (oldBuffer + HOffsetOld).assumingMemoryBound(to: H.self), count: initializedCount)
            Allocator.deallocate(oldBuffer, allocator: self.allocator)
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer,
                BBuffer,
                CBuffer,
                DBuffer,
                EBuffer,
                FBuffer,
                GBuffer,
                HBuffer
        )
    }
    
    @inlinable @inline(__always)
    public func reallocate<A, B, C, D, E, F, G, H>(capacity: Int, isElementInitialized: (Int) -> Bool) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>, UnsafeMutablePointer<D>, UnsafeMutablePointer<E>, UnsafeMutablePointer<F>, UnsafeMutablePointer<G>, UnsafeMutablePointer<H>) {
        assert(capacity >= self.capacity)
        
        var alignment = MemoryLayout<A>.alignment
        alignment = max(alignment, MemoryLayout<B>.alignment)
        alignment = max(alignment, MemoryLayout<C>.alignment)
        alignment = max(alignment, MemoryLayout<D>.alignment)
        alignment = max(alignment, MemoryLayout<E>.alignment)
        alignment = max(alignment, MemoryLayout<F>.alignment)
        alignment = max(alignment, MemoryLayout<G>.alignment)
        alignment = max(alignment, MemoryLayout<H>.alignment)
        var oldSize = 0
        var size = 0
        size = size.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffset = size
        size += capacity * MemoryLayout<A>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<A>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffset = size
        size += capacity * MemoryLayout<B>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<B>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffset = size
        size += capacity * MemoryLayout<C>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<C>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffset = size
        size += capacity * MemoryLayout<D>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<D>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffset = size
        size += capacity * MemoryLayout<E>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<E>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffset = size
        size += capacity * MemoryLayout<F>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<F>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<G>.alignment)
        let GOffset = size
        size += capacity * MemoryLayout<G>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<G>.alignment)
        let GOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<G>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<H>.alignment)
        let HOffset = size
        size += capacity * MemoryLayout<H>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<H>.alignment)
        let HOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<H>.stride
        
        let newBuffer = Allocator.allocate(byteCount: size, alignment: alignment, allocator: self.allocator)
        
        let ABuffer = (newBuffer + AOffset).bindMemory(to: A.self, capacity: capacity)
        let BBuffer = (newBuffer + BOffset).bindMemory(to: B.self, capacity: capacity)
        let CBuffer = (newBuffer + COffset).bindMemory(to: C.self, capacity: capacity)
        let DBuffer = (newBuffer + DOffset).bindMemory(to: D.self, capacity: capacity)
        let EBuffer = (newBuffer + EOffset).bindMemory(to: E.self, capacity: capacity)
        let FBuffer = (newBuffer + FOffset).bindMemory(to: F.self, capacity: capacity)
        let GBuffer = (newBuffer + GOffset).bindMemory(to: G.self, capacity: capacity)
        let HBuffer = (newBuffer + HOffset).bindMemory(to: H.self, capacity: capacity)
        
        if let oldBuffer = self.buffer {
            for i in 0..<self.capacity where isElementInitialized(i) {
                ABuffer.advanced(by: i).moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self).advanced(by: i), count: 1)
                BBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self).advanced(by: i), count: 1)
                CBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self).advanced(by: i), count: 1)
                DBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + DOffsetOld).assumingMemoryBound(to: D.self).advanced(by: i), count: 1)
                EBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + EOffsetOld).assumingMemoryBound(to: E.self).advanced(by: i), count: 1)
                FBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + FOffsetOld).assumingMemoryBound(to: F.self).advanced(by: i), count: 1)
                GBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + GOffsetOld).assumingMemoryBound(to: G.self).advanced(by: i), count: 1)
                HBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + HOffsetOld).assumingMemoryBound(to: H.self).advanced(by: i), count: 1)
            }
            
            Allocator.deallocate(oldBuffer, allocator: self.allocator)
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer,
                BBuffer,
                CBuffer,
                DBuffer,
                EBuffer,
                FBuffer,
                GBuffer,
                HBuffer
        )
    }
    
    @inlinable @inline(__always)
    public func reallocate<A, B, C, D, E, F, G, H, I>(capacity: Int, initializedCount: Int) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>, UnsafeMutablePointer<D>, UnsafeMutablePointer<E>, UnsafeMutablePointer<F>, UnsafeMutablePointer<G>, UnsafeMutablePointer<H>, UnsafeMutablePointer<I>) {
        assert(capacity >= self.capacity)
        
        var alignment = MemoryLayout<A>.alignment
        alignment = max(alignment, MemoryLayout<B>.alignment)
        alignment = max(alignment, MemoryLayout<C>.alignment)
        alignment = max(alignment, MemoryLayout<D>.alignment)
        alignment = max(alignment, MemoryLayout<E>.alignment)
        alignment = max(alignment, MemoryLayout<F>.alignment)
        alignment = max(alignment, MemoryLayout<G>.alignment)
        alignment = max(alignment, MemoryLayout<H>.alignment)
        alignment = max(alignment, MemoryLayout<I>.alignment)
        var oldSize = 0
        var size = 0
        size = size.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffset = size
        size += capacity * MemoryLayout<A>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<A>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffset = size
        size += capacity * MemoryLayout<B>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<B>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffset = size
        size += capacity * MemoryLayout<C>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<C>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffset = size
        size += capacity * MemoryLayout<D>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<D>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffset = size
        size += capacity * MemoryLayout<E>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<E>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffset = size
        size += capacity * MemoryLayout<F>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<F>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<G>.alignment)
        let GOffset = size
        size += capacity * MemoryLayout<G>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<G>.alignment)
        let GOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<G>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<H>.alignment)
        let HOffset = size
        size += capacity * MemoryLayout<H>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<H>.alignment)
        let HOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<H>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<I>.alignment)
        let IOffset = size
        size += capacity * MemoryLayout<I>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<I>.alignment)
        let IOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<I>.stride
        
        let newBuffer = Allocator.allocate(byteCount: size, alignment: alignment, allocator: self.allocator)
        
        let ABuffer = (newBuffer + AOffset).bindMemory(to: A.self, capacity: capacity)
        let BBuffer = (newBuffer + BOffset).bindMemory(to: B.self, capacity: capacity)
        let CBuffer = (newBuffer + COffset).bindMemory(to: C.self, capacity: capacity)
        let DBuffer = (newBuffer + DOffset).bindMemory(to: D.self, capacity: capacity)
        let EBuffer = (newBuffer + EOffset).bindMemory(to: E.self, capacity: capacity)
        let FBuffer = (newBuffer + FOffset).bindMemory(to: F.self, capacity: capacity)
        let GBuffer = (newBuffer + GOffset).bindMemory(to: G.self, capacity: capacity)
        let HBuffer = (newBuffer + HOffset).bindMemory(to: H.self, capacity: capacity)
        let IBuffer = (newBuffer + IOffset).bindMemory(to: I.self, capacity: capacity)
        
        if let oldBuffer = self.buffer {
            ABuffer.moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self), count: initializedCount)
            BBuffer.moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self), count: initializedCount)
            CBuffer.moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self), count: initializedCount)
            DBuffer.moveInitialize(from: (oldBuffer + DOffsetOld).assumingMemoryBound(to: D.self), count: initializedCount)
            EBuffer.moveInitialize(from: (oldBuffer + EOffsetOld).assumingMemoryBound(to: E.self), count: initializedCount)
            FBuffer.moveInitialize(from: (oldBuffer + FOffsetOld).assumingMemoryBound(to: F.self), count: initializedCount)
            GBuffer.moveInitialize(from: (oldBuffer + GOffsetOld).assumingMemoryBound(to: G.self), count: initializedCount)
            HBuffer.moveInitialize(from: (oldBuffer + HOffsetOld).assumingMemoryBound(to: H.self), count: initializedCount)
            IBuffer.moveInitialize(from: (oldBuffer + IOffsetOld).assumingMemoryBound(to: I.self), count: initializedCount)
            Allocator.deallocate(oldBuffer, allocator: self.allocator)
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer,
                BBuffer,
                CBuffer,
                DBuffer,
                EBuffer,
                FBuffer,
                GBuffer,
                HBuffer,
                IBuffer
        )
    }
    
    @inlinable @inline(__always)
    public func reallocate<A, B, C, D, E, F, G, H, I>(capacity: Int, isElementInitialized: (Int) -> Bool) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>, UnsafeMutablePointer<D>, UnsafeMutablePointer<E>, UnsafeMutablePointer<F>, UnsafeMutablePointer<G>, UnsafeMutablePointer<H>, UnsafeMutablePointer<I>) {
        assert(capacity >= self.capacity)
        
        var alignment = MemoryLayout<A>.alignment
        alignment = max(alignment, MemoryLayout<B>.alignment)
        alignment = max(alignment, MemoryLayout<C>.alignment)
        alignment = max(alignment, MemoryLayout<D>.alignment)
        alignment = max(alignment, MemoryLayout<E>.alignment)
        alignment = max(alignment, MemoryLayout<F>.alignment)
        alignment = max(alignment, MemoryLayout<G>.alignment)
        alignment = max(alignment, MemoryLayout<H>.alignment)
        alignment = max(alignment, MemoryLayout<I>.alignment)
        var oldSize = 0
        var size = 0
        size = size.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffset = size
        size += capacity * MemoryLayout<A>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<A>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffset = size
        size += capacity * MemoryLayout<B>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<B>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffset = size
        size += capacity * MemoryLayout<C>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<C>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffset = size
        size += capacity * MemoryLayout<D>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<D>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffset = size
        size += capacity * MemoryLayout<E>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<E>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffset = size
        size += capacity * MemoryLayout<F>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<F>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<G>.alignment)
        let GOffset = size
        size += capacity * MemoryLayout<G>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<G>.alignment)
        let GOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<G>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<H>.alignment)
        let HOffset = size
        size += capacity * MemoryLayout<H>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<H>.alignment)
        let HOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<H>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<I>.alignment)
        let IOffset = size
        size += capacity * MemoryLayout<I>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<I>.alignment)
        let IOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<I>.stride
        
        let newBuffer = Allocator.allocate(byteCount: size, alignment: alignment, allocator: self.allocator)
        
        let ABuffer = (newBuffer + AOffset).bindMemory(to: A.self, capacity: capacity)
        let BBuffer = (newBuffer + BOffset).bindMemory(to: B.self, capacity: capacity)
        let CBuffer = (newBuffer + COffset).bindMemory(to: C.self, capacity: capacity)
        let DBuffer = (newBuffer + DOffset).bindMemory(to: D.self, capacity: capacity)
        let EBuffer = (newBuffer + EOffset).bindMemory(to: E.self, capacity: capacity)
        let FBuffer = (newBuffer + FOffset).bindMemory(to: F.self, capacity: capacity)
        let GBuffer = (newBuffer + GOffset).bindMemory(to: G.self, capacity: capacity)
        let HBuffer = (newBuffer + HOffset).bindMemory(to: H.self, capacity: capacity)
        let IBuffer = (newBuffer + IOffset).bindMemory(to: I.self, capacity: capacity)
        
        if let oldBuffer = self.buffer {
            for i in 0..<self.capacity where isElementInitialized(i) {
                ABuffer.advanced(by: i).moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self).advanced(by: i), count: 1)
                BBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self).advanced(by: i), count: 1)
                CBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self).advanced(by: i), count: 1)
                DBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + DOffsetOld).assumingMemoryBound(to: D.self).advanced(by: i), count: 1)
                EBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + EOffsetOld).assumingMemoryBound(to: E.self).advanced(by: i), count: 1)
                FBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + FOffsetOld).assumingMemoryBound(to: F.self).advanced(by: i), count: 1)
                GBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + GOffsetOld).assumingMemoryBound(to: G.self).advanced(by: i), count: 1)
                HBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + HOffsetOld).assumingMemoryBound(to: H.self).advanced(by: i), count: 1)
                IBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + IOffsetOld).assumingMemoryBound(to: I.self).advanced(by: i), count: 1)
            }
            
            Allocator.deallocate(oldBuffer, allocator: self.allocator)
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer,
                BBuffer,
                CBuffer,
                DBuffer,
                EBuffer,
                FBuffer,
                GBuffer,
                HBuffer,
                IBuffer
        )
    }
    
    @inlinable @inline(__always)
    public func reallocate<A, B, C, D, E, F, G, H, I, J>(capacity: Int, initializedCount: Int) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>, UnsafeMutablePointer<D>, UnsafeMutablePointer<E>, UnsafeMutablePointer<F>, UnsafeMutablePointer<G>, UnsafeMutablePointer<H>, UnsafeMutablePointer<I>, UnsafeMutablePointer<J>) {
        assert(capacity >= self.capacity)
        
        var alignment = MemoryLayout<A>.alignment
        alignment = max(alignment, MemoryLayout<B>.alignment)
        alignment = max(alignment, MemoryLayout<C>.alignment)
        alignment = max(alignment, MemoryLayout<D>.alignment)
        alignment = max(alignment, MemoryLayout<E>.alignment)
        alignment = max(alignment, MemoryLayout<F>.alignment)
        alignment = max(alignment, MemoryLayout<G>.alignment)
        alignment = max(alignment, MemoryLayout<H>.alignment)
        alignment = max(alignment, MemoryLayout<I>.alignment)
        alignment = max(alignment, MemoryLayout<J>.alignment)
        var oldSize = 0
        var size = 0
        size = size.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffset = size
        size += capacity * MemoryLayout<A>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<A>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffset = size
        size += capacity * MemoryLayout<B>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<B>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffset = size
        size += capacity * MemoryLayout<C>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<C>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffset = size
        size += capacity * MemoryLayout<D>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<D>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffset = size
        size += capacity * MemoryLayout<E>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<E>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffset = size
        size += capacity * MemoryLayout<F>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<F>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<G>.alignment)
        let GOffset = size
        size += capacity * MemoryLayout<G>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<G>.alignment)
        let GOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<G>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<H>.alignment)
        let HOffset = size
        size += capacity * MemoryLayout<H>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<H>.alignment)
        let HOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<H>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<I>.alignment)
        let IOffset = size
        size += capacity * MemoryLayout<I>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<I>.alignment)
        let IOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<I>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<J>.alignment)
        let JOffset = size
        size += capacity * MemoryLayout<J>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<J>.alignment)
        let JOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<J>.stride
        
        let newBuffer = Allocator.allocate(byteCount: size, alignment: alignment, allocator: self.allocator)
        
        let ABuffer = (newBuffer + AOffset).bindMemory(to: A.self, capacity: capacity)
        let BBuffer = (newBuffer + BOffset).bindMemory(to: B.self, capacity: capacity)
        let CBuffer = (newBuffer + COffset).bindMemory(to: C.self, capacity: capacity)
        let DBuffer = (newBuffer + DOffset).bindMemory(to: D.self, capacity: capacity)
        let EBuffer = (newBuffer + EOffset).bindMemory(to: E.self, capacity: capacity)
        let FBuffer = (newBuffer + FOffset).bindMemory(to: F.self, capacity: capacity)
        let GBuffer = (newBuffer + GOffset).bindMemory(to: G.self, capacity: capacity)
        let HBuffer = (newBuffer + HOffset).bindMemory(to: H.self, capacity: capacity)
        let IBuffer = (newBuffer + IOffset).bindMemory(to: I.self, capacity: capacity)
        let JBuffer = (newBuffer + JOffset).bindMemory(to: J.self, capacity: capacity)
        
        if let oldBuffer = self.buffer {
            ABuffer.moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self), count: initializedCount)
            BBuffer.moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self), count: initializedCount)
            CBuffer.moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self), count: initializedCount)
            DBuffer.moveInitialize(from: (oldBuffer + DOffsetOld).assumingMemoryBound(to: D.self), count: initializedCount)
            EBuffer.moveInitialize(from: (oldBuffer + EOffsetOld).assumingMemoryBound(to: E.self), count: initializedCount)
            FBuffer.moveInitialize(from: (oldBuffer + FOffsetOld).assumingMemoryBound(to: F.self), count: initializedCount)
            GBuffer.moveInitialize(from: (oldBuffer + GOffsetOld).assumingMemoryBound(to: G.self), count: initializedCount)
            HBuffer.moveInitialize(from: (oldBuffer + HOffsetOld).assumingMemoryBound(to: H.self), count: initializedCount)
            IBuffer.moveInitialize(from: (oldBuffer + IOffsetOld).assumingMemoryBound(to: I.self), count: initializedCount)
            JBuffer.moveInitialize(from: (oldBuffer + JOffsetOld).assumingMemoryBound(to: J.self), count: initializedCount)
            Allocator.deallocate(oldBuffer, allocator: self.allocator)
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer,
                BBuffer,
                CBuffer,
                DBuffer,
                EBuffer,
                FBuffer,
                GBuffer,
                HBuffer,
                IBuffer,
                JBuffer
        )
    }
    
    @inlinable @inline(__always)
    public func reallocate<A, B, C, D, E, F, G, H, I, J>(capacity: Int, isElementInitialized: (Int) -> Bool) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>, UnsafeMutablePointer<D>, UnsafeMutablePointer<E>, UnsafeMutablePointer<F>, UnsafeMutablePointer<G>, UnsafeMutablePointer<H>, UnsafeMutablePointer<I>, UnsafeMutablePointer<J>) {
        assert(capacity >= self.capacity)
        
        var alignment = MemoryLayout<A>.alignment
        alignment = max(alignment, MemoryLayout<B>.alignment)
        alignment = max(alignment, MemoryLayout<C>.alignment)
        alignment = max(alignment, MemoryLayout<D>.alignment)
        alignment = max(alignment, MemoryLayout<E>.alignment)
        alignment = max(alignment, MemoryLayout<F>.alignment)
        alignment = max(alignment, MemoryLayout<G>.alignment)
        alignment = max(alignment, MemoryLayout<H>.alignment)
        alignment = max(alignment, MemoryLayout<I>.alignment)
        alignment = max(alignment, MemoryLayout<J>.alignment)
        var oldSize = 0
        var size = 0
        size = size.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffset = size
        size += capacity * MemoryLayout<A>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<A>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffset = size
        size += capacity * MemoryLayout<B>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<B>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffset = size
        size += capacity * MemoryLayout<C>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<C>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffset = size
        size += capacity * MemoryLayout<D>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<D>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffset = size
        size += capacity * MemoryLayout<E>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<E>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffset = size
        size += capacity * MemoryLayout<F>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<F>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<G>.alignment)
        let GOffset = size
        size += capacity * MemoryLayout<G>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<G>.alignment)
        let GOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<G>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<H>.alignment)
        let HOffset = size
        size += capacity * MemoryLayout<H>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<H>.alignment)
        let HOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<H>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<I>.alignment)
        let IOffset = size
        size += capacity * MemoryLayout<I>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<I>.alignment)
        let IOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<I>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<J>.alignment)
        let JOffset = size
        size += capacity * MemoryLayout<J>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<J>.alignment)
        let JOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<J>.stride
        
        let newBuffer = Allocator.allocate(byteCount: size, alignment: alignment, allocator: self.allocator)
        
        let ABuffer = (newBuffer + AOffset).bindMemory(to: A.self, capacity: capacity)
        let BBuffer = (newBuffer + BOffset).bindMemory(to: B.self, capacity: capacity)
        let CBuffer = (newBuffer + COffset).bindMemory(to: C.self, capacity: capacity)
        let DBuffer = (newBuffer + DOffset).bindMemory(to: D.self, capacity: capacity)
        let EBuffer = (newBuffer + EOffset).bindMemory(to: E.self, capacity: capacity)
        let FBuffer = (newBuffer + FOffset).bindMemory(to: F.self, capacity: capacity)
        let GBuffer = (newBuffer + GOffset).bindMemory(to: G.self, capacity: capacity)
        let HBuffer = (newBuffer + HOffset).bindMemory(to: H.self, capacity: capacity)
        let IBuffer = (newBuffer + IOffset).bindMemory(to: I.self, capacity: capacity)
        let JBuffer = (newBuffer + JOffset).bindMemory(to: J.self, capacity: capacity)
        
        if let oldBuffer = self.buffer {
            for i in 0..<self.capacity where isElementInitialized(i) {
                ABuffer.advanced(by: i).moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self).advanced(by: i), count: 1)
                BBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self).advanced(by: i), count: 1)
                CBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self).advanced(by: i), count: 1)
                DBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + DOffsetOld).assumingMemoryBound(to: D.self).advanced(by: i), count: 1)
                EBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + EOffsetOld).assumingMemoryBound(to: E.self).advanced(by: i), count: 1)
                FBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + FOffsetOld).assumingMemoryBound(to: F.self).advanced(by: i), count: 1)
                GBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + GOffsetOld).assumingMemoryBound(to: G.self).advanced(by: i), count: 1)
                HBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + HOffsetOld).assumingMemoryBound(to: H.self).advanced(by: i), count: 1)
                IBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + IOffsetOld).assumingMemoryBound(to: I.self).advanced(by: i), count: 1)
                JBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + JOffsetOld).assumingMemoryBound(to: J.self).advanced(by: i), count: 1)
            }
            
            Allocator.deallocate(oldBuffer, allocator: self.allocator)
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer,
                BBuffer,
                CBuffer,
                DBuffer,
                EBuffer,
                FBuffer,
                GBuffer,
                HBuffer,
                IBuffer,
                JBuffer
        )
    }
    
    @inlinable @inline(__always)
    public func reallocate<A, B, C, D, E, F, G, H, I, J, K>(capacity: Int, initializedCount: Int) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>, UnsafeMutablePointer<D>, UnsafeMutablePointer<E>, UnsafeMutablePointer<F>, UnsafeMutablePointer<G>, UnsafeMutablePointer<H>, UnsafeMutablePointer<I>, UnsafeMutablePointer<J>, UnsafeMutablePointer<K>) {
        assert(capacity >= self.capacity)
        
        var alignment = MemoryLayout<A>.alignment
        alignment = max(alignment, MemoryLayout<B>.alignment)
        alignment = max(alignment, MemoryLayout<C>.alignment)
        alignment = max(alignment, MemoryLayout<D>.alignment)
        alignment = max(alignment, MemoryLayout<E>.alignment)
        alignment = max(alignment, MemoryLayout<F>.alignment)
        alignment = max(alignment, MemoryLayout<G>.alignment)
        alignment = max(alignment, MemoryLayout<H>.alignment)
        alignment = max(alignment, MemoryLayout<I>.alignment)
        alignment = max(alignment, MemoryLayout<J>.alignment)
        alignment = max(alignment, MemoryLayout<K>.alignment)
        var oldSize = 0
        var size = 0
        size = size.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffset = size
        size += capacity * MemoryLayout<A>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<A>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffset = size
        size += capacity * MemoryLayout<B>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<B>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffset = size
        size += capacity * MemoryLayout<C>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<C>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffset = size
        size += capacity * MemoryLayout<D>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<D>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffset = size
        size += capacity * MemoryLayout<E>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<E>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffset = size
        size += capacity * MemoryLayout<F>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<F>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<G>.alignment)
        let GOffset = size
        size += capacity * MemoryLayout<G>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<G>.alignment)
        let GOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<G>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<H>.alignment)
        let HOffset = size
        size += capacity * MemoryLayout<H>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<H>.alignment)
        let HOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<H>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<I>.alignment)
        let IOffset = size
        size += capacity * MemoryLayout<I>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<I>.alignment)
        let IOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<I>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<J>.alignment)
        let JOffset = size
        size += capacity * MemoryLayout<J>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<J>.alignment)
        let JOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<J>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<K>.alignment)
        let KOffset = size
        size += capacity * MemoryLayout<K>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<K>.alignment)
        let KOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<K>.stride
        
        let newBuffer = Allocator.allocate(byteCount: size, alignment: alignment, allocator: self.allocator)
        
        let ABuffer = (newBuffer + AOffset).bindMemory(to: A.self, capacity: capacity)
        let BBuffer = (newBuffer + BOffset).bindMemory(to: B.self, capacity: capacity)
        let CBuffer = (newBuffer + COffset).bindMemory(to: C.self, capacity: capacity)
        let DBuffer = (newBuffer + DOffset).bindMemory(to: D.self, capacity: capacity)
        let EBuffer = (newBuffer + EOffset).bindMemory(to: E.self, capacity: capacity)
        let FBuffer = (newBuffer + FOffset).bindMemory(to: F.self, capacity: capacity)
        let GBuffer = (newBuffer + GOffset).bindMemory(to: G.self, capacity: capacity)
        let HBuffer = (newBuffer + HOffset).bindMemory(to: H.self, capacity: capacity)
        let IBuffer = (newBuffer + IOffset).bindMemory(to: I.self, capacity: capacity)
        let JBuffer = (newBuffer + JOffset).bindMemory(to: J.self, capacity: capacity)
        let KBuffer = (newBuffer + KOffset).bindMemory(to: K.self, capacity: capacity)
        
        if let oldBuffer = self.buffer {
            ABuffer.moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self), count: initializedCount)
            BBuffer.moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self), count: initializedCount)
            CBuffer.moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self), count: initializedCount)
            DBuffer.moveInitialize(from: (oldBuffer + DOffsetOld).assumingMemoryBound(to: D.self), count: initializedCount)
            EBuffer.moveInitialize(from: (oldBuffer + EOffsetOld).assumingMemoryBound(to: E.self), count: initializedCount)
            FBuffer.moveInitialize(from: (oldBuffer + FOffsetOld).assumingMemoryBound(to: F.self), count: initializedCount)
            GBuffer.moveInitialize(from: (oldBuffer + GOffsetOld).assumingMemoryBound(to: G.self), count: initializedCount)
            HBuffer.moveInitialize(from: (oldBuffer + HOffsetOld).assumingMemoryBound(to: H.self), count: initializedCount)
            IBuffer.moveInitialize(from: (oldBuffer + IOffsetOld).assumingMemoryBound(to: I.self), count: initializedCount)
            JBuffer.moveInitialize(from: (oldBuffer + JOffsetOld).assumingMemoryBound(to: J.self), count: initializedCount)
            KBuffer.moveInitialize(from: (oldBuffer + KOffsetOld).assumingMemoryBound(to: K.self), count: initializedCount)
            Allocator.deallocate(oldBuffer, allocator: self.allocator)
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer,
                BBuffer,
                CBuffer,
                DBuffer,
                EBuffer,
                FBuffer,
                GBuffer,
                HBuffer,
                IBuffer,
                JBuffer,
                KBuffer
        )
    }
    
    @inlinable @inline(__always)
    public func reallocate<A, B, C, D, E, F, G, H, I, J, K>(capacity: Int, isElementInitialized: (Int) -> Bool) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>, UnsafeMutablePointer<D>, UnsafeMutablePointer<E>, UnsafeMutablePointer<F>, UnsafeMutablePointer<G>, UnsafeMutablePointer<H>, UnsafeMutablePointer<I>, UnsafeMutablePointer<J>, UnsafeMutablePointer<K>) {
        assert(capacity >= self.capacity)
        
        var alignment = MemoryLayout<A>.alignment
        alignment = max(alignment, MemoryLayout<B>.alignment)
        alignment = max(alignment, MemoryLayout<C>.alignment)
        alignment = max(alignment, MemoryLayout<D>.alignment)
        alignment = max(alignment, MemoryLayout<E>.alignment)
        alignment = max(alignment, MemoryLayout<F>.alignment)
        alignment = max(alignment, MemoryLayout<G>.alignment)
        alignment = max(alignment, MemoryLayout<H>.alignment)
        alignment = max(alignment, MemoryLayout<I>.alignment)
        alignment = max(alignment, MemoryLayout<J>.alignment)
        alignment = max(alignment, MemoryLayout<K>.alignment)
        var oldSize = 0
        var size = 0
        size = size.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffset = size
        size += capacity * MemoryLayout<A>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<A>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffset = size
        size += capacity * MemoryLayout<B>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<B>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffset = size
        size += capacity * MemoryLayout<C>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<C>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffset = size
        size += capacity * MemoryLayout<D>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<D>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffset = size
        size += capacity * MemoryLayout<E>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<E>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffset = size
        size += capacity * MemoryLayout<F>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<F>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<G>.alignment)
        let GOffset = size
        size += capacity * MemoryLayout<G>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<G>.alignment)
        let GOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<G>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<H>.alignment)
        let HOffset = size
        size += capacity * MemoryLayout<H>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<H>.alignment)
        let HOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<H>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<I>.alignment)
        let IOffset = size
        size += capacity * MemoryLayout<I>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<I>.alignment)
        let IOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<I>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<J>.alignment)
        let JOffset = size
        size += capacity * MemoryLayout<J>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<J>.alignment)
        let JOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<J>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<K>.alignment)
        let KOffset = size
        size += capacity * MemoryLayout<K>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<K>.alignment)
        let KOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<K>.stride
        
        let newBuffer = Allocator.allocate(byteCount: size, alignment: alignment, allocator: self.allocator)
        
        let ABuffer = (newBuffer + AOffset).bindMemory(to: A.self, capacity: capacity)
        let BBuffer = (newBuffer + BOffset).bindMemory(to: B.self, capacity: capacity)
        let CBuffer = (newBuffer + COffset).bindMemory(to: C.self, capacity: capacity)
        let DBuffer = (newBuffer + DOffset).bindMemory(to: D.self, capacity: capacity)
        let EBuffer = (newBuffer + EOffset).bindMemory(to: E.self, capacity: capacity)
        let FBuffer = (newBuffer + FOffset).bindMemory(to: F.self, capacity: capacity)
        let GBuffer = (newBuffer + GOffset).bindMemory(to: G.self, capacity: capacity)
        let HBuffer = (newBuffer + HOffset).bindMemory(to: H.self, capacity: capacity)
        let IBuffer = (newBuffer + IOffset).bindMemory(to: I.self, capacity: capacity)
        let JBuffer = (newBuffer + JOffset).bindMemory(to: J.self, capacity: capacity)
        let KBuffer = (newBuffer + KOffset).bindMemory(to: K.self, capacity: capacity)
        
        if let oldBuffer = self.buffer {
            for i in 0..<self.capacity where isElementInitialized(i) {
                ABuffer.advanced(by: i).moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self).advanced(by: i), count: 1)
                BBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self).advanced(by: i), count: 1)
                CBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self).advanced(by: i), count: 1)
                DBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + DOffsetOld).assumingMemoryBound(to: D.self).advanced(by: i), count: 1)
                EBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + EOffsetOld).assumingMemoryBound(to: E.self).advanced(by: i), count: 1)
                FBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + FOffsetOld).assumingMemoryBound(to: F.self).advanced(by: i), count: 1)
                GBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + GOffsetOld).assumingMemoryBound(to: G.self).advanced(by: i), count: 1)
                HBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + HOffsetOld).assumingMemoryBound(to: H.self).advanced(by: i), count: 1)
                IBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + IOffsetOld).assumingMemoryBound(to: I.self).advanced(by: i), count: 1)
                JBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + JOffsetOld).assumingMemoryBound(to: J.self).advanced(by: i), count: 1)
                KBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + KOffsetOld).assumingMemoryBound(to: K.self).advanced(by: i), count: 1)
            }
            
            Allocator.deallocate(oldBuffer, allocator: self.allocator)
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer,
                BBuffer,
                CBuffer,
                DBuffer,
                EBuffer,
                FBuffer,
                GBuffer,
                HBuffer,
                IBuffer,
                JBuffer,
                KBuffer
        )
    }
    
    @inlinable @inline(__always)
    public func reallocate<A, B, C, D, E, F, G, H, I, J, K, L>(capacity: Int, initializedCount: Int) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>, UnsafeMutablePointer<D>, UnsafeMutablePointer<E>, UnsafeMutablePointer<F>, UnsafeMutablePointer<G>, UnsafeMutablePointer<H>, UnsafeMutablePointer<I>, UnsafeMutablePointer<J>, UnsafeMutablePointer<K>, UnsafeMutablePointer<L>) {
        assert(capacity >= self.capacity)
        
        var alignment = MemoryLayout<A>.alignment
        alignment = max(alignment, MemoryLayout<B>.alignment)
        alignment = max(alignment, MemoryLayout<C>.alignment)
        alignment = max(alignment, MemoryLayout<D>.alignment)
        alignment = max(alignment, MemoryLayout<E>.alignment)
        alignment = max(alignment, MemoryLayout<F>.alignment)
        alignment = max(alignment, MemoryLayout<G>.alignment)
        alignment = max(alignment, MemoryLayout<H>.alignment)
        alignment = max(alignment, MemoryLayout<I>.alignment)
        alignment = max(alignment, MemoryLayout<J>.alignment)
        alignment = max(alignment, MemoryLayout<K>.alignment)
        alignment = max(alignment, MemoryLayout<L>.alignment)
        var oldSize = 0
        var size = 0
        size = size.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffset = size
        size += capacity * MemoryLayout<A>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<A>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffset = size
        size += capacity * MemoryLayout<B>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<B>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffset = size
        size += capacity * MemoryLayout<C>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<C>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffset = size
        size += capacity * MemoryLayout<D>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<D>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffset = size
        size += capacity * MemoryLayout<E>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<E>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffset = size
        size += capacity * MemoryLayout<F>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<F>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<G>.alignment)
        let GOffset = size
        size += capacity * MemoryLayout<G>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<G>.alignment)
        let GOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<G>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<H>.alignment)
        let HOffset = size
        size += capacity * MemoryLayout<H>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<H>.alignment)
        let HOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<H>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<I>.alignment)
        let IOffset = size
        size += capacity * MemoryLayout<I>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<I>.alignment)
        let IOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<I>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<J>.alignment)
        let JOffset = size
        size += capacity * MemoryLayout<J>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<J>.alignment)
        let JOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<J>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<K>.alignment)
        let KOffset = size
        size += capacity * MemoryLayout<K>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<K>.alignment)
        let KOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<K>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<L>.alignment)
        let LOffset = size
        size += capacity * MemoryLayout<L>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<L>.alignment)
        let LOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<L>.stride
        
        let newBuffer = Allocator.allocate(byteCount: size, alignment: alignment, allocator: self.allocator)
        
        let ABuffer = (newBuffer + AOffset).bindMemory(to: A.self, capacity: capacity)
        let BBuffer = (newBuffer + BOffset).bindMemory(to: B.self, capacity: capacity)
        let CBuffer = (newBuffer + COffset).bindMemory(to: C.self, capacity: capacity)
        let DBuffer = (newBuffer + DOffset).bindMemory(to: D.self, capacity: capacity)
        let EBuffer = (newBuffer + EOffset).bindMemory(to: E.self, capacity: capacity)
        let FBuffer = (newBuffer + FOffset).bindMemory(to: F.self, capacity: capacity)
        let GBuffer = (newBuffer + GOffset).bindMemory(to: G.self, capacity: capacity)
        let HBuffer = (newBuffer + HOffset).bindMemory(to: H.self, capacity: capacity)
        let IBuffer = (newBuffer + IOffset).bindMemory(to: I.self, capacity: capacity)
        let JBuffer = (newBuffer + JOffset).bindMemory(to: J.self, capacity: capacity)
        let KBuffer = (newBuffer + KOffset).bindMemory(to: K.self, capacity: capacity)
        let LBuffer = (newBuffer + LOffset).bindMemory(to: L.self, capacity: capacity)
        
        if let oldBuffer = self.buffer {
            ABuffer.moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self), count: initializedCount)
            BBuffer.moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self), count: initializedCount)
            CBuffer.moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self), count: initializedCount)
            DBuffer.moveInitialize(from: (oldBuffer + DOffsetOld).assumingMemoryBound(to: D.self), count: initializedCount)
            EBuffer.moveInitialize(from: (oldBuffer + EOffsetOld).assumingMemoryBound(to: E.self), count: initializedCount)
            FBuffer.moveInitialize(from: (oldBuffer + FOffsetOld).assumingMemoryBound(to: F.self), count: initializedCount)
            GBuffer.moveInitialize(from: (oldBuffer + GOffsetOld).assumingMemoryBound(to: G.self), count: initializedCount)
            HBuffer.moveInitialize(from: (oldBuffer + HOffsetOld).assumingMemoryBound(to: H.self), count: initializedCount)
            IBuffer.moveInitialize(from: (oldBuffer + IOffsetOld).assumingMemoryBound(to: I.self), count: initializedCount)
            JBuffer.moveInitialize(from: (oldBuffer + JOffsetOld).assumingMemoryBound(to: J.self), count: initializedCount)
            KBuffer.moveInitialize(from: (oldBuffer + KOffsetOld).assumingMemoryBound(to: K.self), count: initializedCount)
            LBuffer.moveInitialize(from: (oldBuffer + LOffsetOld).assumingMemoryBound(to: L.self), count: initializedCount)
            Allocator.deallocate(oldBuffer, allocator: self.allocator)
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer,
                BBuffer,
                CBuffer,
                DBuffer,
                EBuffer,
                FBuffer,
                GBuffer,
                HBuffer,
                IBuffer,
                JBuffer,
                KBuffer,
                LBuffer
        )
    }
    
    @inlinable @inline(__always)
    public func reallocate<A, B, C, D, E, F, G, H, I, J, K, L>(capacity: Int, isElementInitialized: (Int) -> Bool) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>, UnsafeMutablePointer<D>, UnsafeMutablePointer<E>, UnsafeMutablePointer<F>, UnsafeMutablePointer<G>, UnsafeMutablePointer<H>, UnsafeMutablePointer<I>, UnsafeMutablePointer<J>, UnsafeMutablePointer<K>, UnsafeMutablePointer<L>) {
        assert(capacity >= self.capacity)
        
        var alignment = MemoryLayout<A>.alignment
        alignment = max(alignment, MemoryLayout<B>.alignment)
        alignment = max(alignment, MemoryLayout<C>.alignment)
        alignment = max(alignment, MemoryLayout<D>.alignment)
        alignment = max(alignment, MemoryLayout<E>.alignment)
        alignment = max(alignment, MemoryLayout<F>.alignment)
        alignment = max(alignment, MemoryLayout<G>.alignment)
        alignment = max(alignment, MemoryLayout<H>.alignment)
        alignment = max(alignment, MemoryLayout<I>.alignment)
        alignment = max(alignment, MemoryLayout<J>.alignment)
        alignment = max(alignment, MemoryLayout<K>.alignment)
        alignment = max(alignment, MemoryLayout<L>.alignment)
        var oldSize = 0
        var size = 0
        size = size.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffset = size
        size += capacity * MemoryLayout<A>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<A>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffset = size
        size += capacity * MemoryLayout<B>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<B>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffset = size
        size += capacity * MemoryLayout<C>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<C>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffset = size
        size += capacity * MemoryLayout<D>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<D>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffset = size
        size += capacity * MemoryLayout<E>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<E>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffset = size
        size += capacity * MemoryLayout<F>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<F>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<G>.alignment)
        let GOffset = size
        size += capacity * MemoryLayout<G>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<G>.alignment)
        let GOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<G>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<H>.alignment)
        let HOffset = size
        size += capacity * MemoryLayout<H>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<H>.alignment)
        let HOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<H>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<I>.alignment)
        let IOffset = size
        size += capacity * MemoryLayout<I>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<I>.alignment)
        let IOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<I>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<J>.alignment)
        let JOffset = size
        size += capacity * MemoryLayout<J>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<J>.alignment)
        let JOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<J>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<K>.alignment)
        let KOffset = size
        size += capacity * MemoryLayout<K>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<K>.alignment)
        let KOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<K>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<L>.alignment)
        let LOffset = size
        size += capacity * MemoryLayout<L>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<L>.alignment)
        let LOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<L>.stride
        
        let newBuffer = Allocator.allocate(byteCount: size, alignment: alignment, allocator: self.allocator)
        
        let ABuffer = (newBuffer + AOffset).bindMemory(to: A.self, capacity: capacity)
        let BBuffer = (newBuffer + BOffset).bindMemory(to: B.self, capacity: capacity)
        let CBuffer = (newBuffer + COffset).bindMemory(to: C.self, capacity: capacity)
        let DBuffer = (newBuffer + DOffset).bindMemory(to: D.self, capacity: capacity)
        let EBuffer = (newBuffer + EOffset).bindMemory(to: E.self, capacity: capacity)
        let FBuffer = (newBuffer + FOffset).bindMemory(to: F.self, capacity: capacity)
        let GBuffer = (newBuffer + GOffset).bindMemory(to: G.self, capacity: capacity)
        let HBuffer = (newBuffer + HOffset).bindMemory(to: H.self, capacity: capacity)
        let IBuffer = (newBuffer + IOffset).bindMemory(to: I.self, capacity: capacity)
        let JBuffer = (newBuffer + JOffset).bindMemory(to: J.self, capacity: capacity)
        let KBuffer = (newBuffer + KOffset).bindMemory(to: K.self, capacity: capacity)
        let LBuffer = (newBuffer + LOffset).bindMemory(to: L.self, capacity: capacity)
        
        if let oldBuffer = self.buffer {
            for i in 0..<self.capacity where isElementInitialized(i) {
                ABuffer.advanced(by: i).moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self).advanced(by: i), count: 1)
                BBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self).advanced(by: i), count: 1)
                CBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self).advanced(by: i), count: 1)
                DBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + DOffsetOld).assumingMemoryBound(to: D.self).advanced(by: i), count: 1)
                EBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + EOffsetOld).assumingMemoryBound(to: E.self).advanced(by: i), count: 1)
                FBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + FOffsetOld).assumingMemoryBound(to: F.self).advanced(by: i), count: 1)
                GBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + GOffsetOld).assumingMemoryBound(to: G.self).advanced(by: i), count: 1)
                HBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + HOffsetOld).assumingMemoryBound(to: H.self).advanced(by: i), count: 1)
                IBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + IOffsetOld).assumingMemoryBound(to: I.self).advanced(by: i), count: 1)
                JBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + JOffsetOld).assumingMemoryBound(to: J.self).advanced(by: i), count: 1)
                KBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + KOffsetOld).assumingMemoryBound(to: K.self).advanced(by: i), count: 1)
                LBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + LOffsetOld).assumingMemoryBound(to: L.self).advanced(by: i), count: 1)}
            
            Allocator.deallocate(oldBuffer, allocator: self.allocator)
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer,
                BBuffer,
                CBuffer,
                DBuffer,
                EBuffer,
                FBuffer,
                GBuffer,
                HBuffer,
                IBuffer,
                JBuffer,
                KBuffer,
                LBuffer
        )
    }
    
    @inlinable @inline(__always)
    public func reallocate<A, B, C, D, E, F, G, H, I, J, K, L, M>(capacity: Int, initializedCount: Int) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>, UnsafeMutablePointer<D>, UnsafeMutablePointer<E>, UnsafeMutablePointer<F>, UnsafeMutablePointer<G>, UnsafeMutablePointer<H>, UnsafeMutablePointer<I>, UnsafeMutablePointer<J>, UnsafeMutablePointer<K>, UnsafeMutablePointer<L>, UnsafeMutablePointer<M>) {
        assert(capacity >= self.capacity)
        
        var alignment = MemoryLayout<A>.alignment
        alignment = max(alignment, MemoryLayout<B>.alignment)
        alignment = max(alignment, MemoryLayout<C>.alignment)
        alignment = max(alignment, MemoryLayout<D>.alignment)
        alignment = max(alignment, MemoryLayout<E>.alignment)
        alignment = max(alignment, MemoryLayout<F>.alignment)
        alignment = max(alignment, MemoryLayout<G>.alignment)
        alignment = max(alignment, MemoryLayout<H>.alignment)
        alignment = max(alignment, MemoryLayout<I>.alignment)
        alignment = max(alignment, MemoryLayout<J>.alignment)
        alignment = max(alignment, MemoryLayout<K>.alignment)
        alignment = max(alignment, MemoryLayout<L>.alignment)
        alignment = max(alignment, MemoryLayout<M>.alignment)
        var oldSize = 0
        var size = 0
        size = size.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffset = size
        size += capacity * MemoryLayout<A>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<A>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffset = size
        size += capacity * MemoryLayout<B>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<B>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffset = size
        size += capacity * MemoryLayout<C>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<C>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffset = size
        size += capacity * MemoryLayout<D>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<D>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffset = size
        size += capacity * MemoryLayout<E>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<E>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffset = size
        size += capacity * MemoryLayout<F>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<F>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<G>.alignment)
        let GOffset = size
        size += capacity * MemoryLayout<G>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<G>.alignment)
        let GOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<G>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<H>.alignment)
        let HOffset = size
        size += capacity * MemoryLayout<H>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<H>.alignment)
        let HOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<H>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<I>.alignment)
        let IOffset = size
        size += capacity * MemoryLayout<I>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<I>.alignment)
        let IOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<I>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<J>.alignment)
        let JOffset = size
        size += capacity * MemoryLayout<J>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<J>.alignment)
        let JOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<J>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<K>.alignment)
        let KOffset = size
        size += capacity * MemoryLayout<K>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<K>.alignment)
        let KOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<K>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<L>.alignment)
        let LOffset = size
        size += capacity * MemoryLayout<L>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<L>.alignment)
        let LOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<L>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<M>.alignment)
        let MOffset = size
        size += capacity * MemoryLayout<M>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<M>.alignment)
        let MOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<M>.stride
        
        let newBuffer = Allocator.allocate(byteCount: size, alignment: alignment, allocator: self.allocator)
        
        let ABuffer = (newBuffer + AOffset).bindMemory(to: A.self, capacity: capacity)
        let BBuffer = (newBuffer + BOffset).bindMemory(to: B.self, capacity: capacity)
        let CBuffer = (newBuffer + COffset).bindMemory(to: C.self, capacity: capacity)
        let DBuffer = (newBuffer + DOffset).bindMemory(to: D.self, capacity: capacity)
        let EBuffer = (newBuffer + EOffset).bindMemory(to: E.self, capacity: capacity)
        let FBuffer = (newBuffer + FOffset).bindMemory(to: F.self, capacity: capacity)
        let GBuffer = (newBuffer + GOffset).bindMemory(to: G.self, capacity: capacity)
        let HBuffer = (newBuffer + HOffset).bindMemory(to: H.self, capacity: capacity)
        let IBuffer = (newBuffer + IOffset).bindMemory(to: I.self, capacity: capacity)
        let JBuffer = (newBuffer + JOffset).bindMemory(to: J.self, capacity: capacity)
        let KBuffer = (newBuffer + KOffset).bindMemory(to: K.self, capacity: capacity)
        let LBuffer = (newBuffer + LOffset).bindMemory(to: L.self, capacity: capacity)
        let MBuffer = (newBuffer + MOffset).bindMemory(to: M.self, capacity: capacity)
        
        if let oldBuffer = self.buffer {
            ABuffer.moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self), count: initializedCount)
            BBuffer.moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self), count: initializedCount)
            CBuffer.moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self), count: initializedCount)
            DBuffer.moveInitialize(from: (oldBuffer + DOffsetOld).assumingMemoryBound(to: D.self), count: initializedCount)
            EBuffer.moveInitialize(from: (oldBuffer + EOffsetOld).assumingMemoryBound(to: E.self), count: initializedCount)
            FBuffer.moveInitialize(from: (oldBuffer + FOffsetOld).assumingMemoryBound(to: F.self), count: initializedCount)
            GBuffer.moveInitialize(from: (oldBuffer + GOffsetOld).assumingMemoryBound(to: G.self), count: initializedCount)
            HBuffer.moveInitialize(from: (oldBuffer + HOffsetOld).assumingMemoryBound(to: H.self), count: initializedCount)
            IBuffer.moveInitialize(from: (oldBuffer + IOffsetOld).assumingMemoryBound(to: I.self), count: initializedCount)
            JBuffer.moveInitialize(from: (oldBuffer + JOffsetOld).assumingMemoryBound(to: J.self), count: initializedCount)
            KBuffer.moveInitialize(from: (oldBuffer + KOffsetOld).assumingMemoryBound(to: K.self), count: initializedCount)
            LBuffer.moveInitialize(from: (oldBuffer + LOffsetOld).assumingMemoryBound(to: L.self), count: initializedCount)
            MBuffer.moveInitialize(from: (oldBuffer + MOffsetOld).assumingMemoryBound(to: M.self), count: initializedCount)
            Allocator.deallocate(oldBuffer, allocator: self.allocator)
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer,
                BBuffer,
                CBuffer,
                DBuffer,
                EBuffer,
                FBuffer,
                GBuffer,
                HBuffer,
                IBuffer,
                JBuffer,
                KBuffer,
                LBuffer,
                MBuffer
        )
    }
    
    @inlinable @inline(__always)
    public func reallocate<A, B, C, D, E, F, G, H, I, J, K, L, M>(capacity: Int, isElementInitialized: (Int) -> Bool) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>, UnsafeMutablePointer<D>, UnsafeMutablePointer<E>, UnsafeMutablePointer<F>, UnsafeMutablePointer<G>, UnsafeMutablePointer<H>, UnsafeMutablePointer<I>, UnsafeMutablePointer<J>, UnsafeMutablePointer<K>, UnsafeMutablePointer<L>, UnsafeMutablePointer<M>) {
        assert(capacity >= self.capacity)
        
        var alignment = MemoryLayout<A>.alignment
        alignment = max(alignment, MemoryLayout<B>.alignment)
        alignment = max(alignment, MemoryLayout<C>.alignment)
        alignment = max(alignment, MemoryLayout<D>.alignment)
        alignment = max(alignment, MemoryLayout<E>.alignment)
        alignment = max(alignment, MemoryLayout<F>.alignment)
        alignment = max(alignment, MemoryLayout<G>.alignment)
        alignment = max(alignment, MemoryLayout<H>.alignment)
        alignment = max(alignment, MemoryLayout<I>.alignment)
        alignment = max(alignment, MemoryLayout<J>.alignment)
        alignment = max(alignment, MemoryLayout<K>.alignment)
        alignment = max(alignment, MemoryLayout<L>.alignment)
        alignment = max(alignment, MemoryLayout<M>.alignment)
        var oldSize = 0
        var size = 0
        size = size.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffset = size
        size += capacity * MemoryLayout<A>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<A>.alignment)
        let AOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<A>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffset = size
        size += capacity * MemoryLayout<B>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<B>.alignment)
        let BOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<B>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffset = size
        size += capacity * MemoryLayout<C>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<C>.alignment)
        let COffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<C>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffset = size
        size += capacity * MemoryLayout<D>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<D>.alignment)
        let DOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<D>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffset = size
        size += capacity * MemoryLayout<E>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<E>.alignment)
        let EOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<E>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffset = size
        size += capacity * MemoryLayout<F>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<F>.alignment)
        let FOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<F>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<G>.alignment)
        let GOffset = size
        size += capacity * MemoryLayout<G>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<G>.alignment)
        let GOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<G>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<H>.alignment)
        let HOffset = size
        size += capacity * MemoryLayout<H>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<H>.alignment)
        let HOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<H>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<I>.alignment)
        let IOffset = size
        size += capacity * MemoryLayout<I>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<I>.alignment)
        let IOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<I>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<J>.alignment)
        let JOffset = size
        size += capacity * MemoryLayout<J>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<J>.alignment)
        let JOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<J>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<K>.alignment)
        let KOffset = size
        size += capacity * MemoryLayout<K>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<K>.alignment)
        let KOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<K>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<L>.alignment)
        let LOffset = size
        size += capacity * MemoryLayout<L>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<L>.alignment)
        let LOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<L>.stride
        
        
        size = size.roundedUpToMultiple(of: MemoryLayout<M>.alignment)
        let MOffset = size
        size += capacity * MemoryLayout<M>.stride
        
        oldSize = oldSize.roundedUpToMultiple(of: MemoryLayout<M>.alignment)
        let MOffsetOld = oldSize
        oldSize += self.capacity * MemoryLayout<M>.stride
        
        let newBuffer = Allocator.allocate(byteCount: size, alignment: alignment, allocator: self.allocator)
        
        let ABuffer = (newBuffer + AOffset).bindMemory(to: A.self, capacity: capacity)
        let BBuffer = (newBuffer + BOffset).bindMemory(to: B.self, capacity: capacity)
        let CBuffer = (newBuffer + COffset).bindMemory(to: C.self, capacity: capacity)
        let DBuffer = (newBuffer + DOffset).bindMemory(to: D.self, capacity: capacity)
        let EBuffer = (newBuffer + EOffset).bindMemory(to: E.self, capacity: capacity)
        let FBuffer = (newBuffer + FOffset).bindMemory(to: F.self, capacity: capacity)
        let GBuffer = (newBuffer + GOffset).bindMemory(to: G.self, capacity: capacity)
        let HBuffer = (newBuffer + HOffset).bindMemory(to: H.self, capacity: capacity)
        let IBuffer = (newBuffer + IOffset).bindMemory(to: I.self, capacity: capacity)
        let JBuffer = (newBuffer + JOffset).bindMemory(to: J.self, capacity: capacity)
        let KBuffer = (newBuffer + KOffset).bindMemory(to: K.self, capacity: capacity)
        let LBuffer = (newBuffer + LOffset).bindMemory(to: L.self, capacity: capacity)
        let MBuffer = (newBuffer + MOffset).bindMemory(to: M.self, capacity: capacity)
        
        if let oldBuffer = self.buffer {
            for i in 0..<self.capacity where isElementInitialized(i) {
                ABuffer.advanced(by: i).moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self).advanced(by: i), count: 1)
                BBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self).advanced(by: i), count: 1)
                CBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self).advanced(by: i), count: 1)
                DBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + DOffsetOld).assumingMemoryBound(to: D.self).advanced(by: i), count: 1)
                EBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + EOffsetOld).assumingMemoryBound(to: E.self).advanced(by: i), count: 1)
                FBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + FOffsetOld).assumingMemoryBound(to: F.self).advanced(by: i), count: 1)
                GBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + GOffsetOld).assumingMemoryBound(to: G.self).advanced(by: i), count: 1)
                HBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + HOffsetOld).assumingMemoryBound(to: H.self).advanced(by: i), count: 1)
                IBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + IOffsetOld).assumingMemoryBound(to: I.self).advanced(by: i), count: 1)
                JBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + JOffsetOld).assumingMemoryBound(to: J.self).advanced(by: i), count: 1)
                KBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + KOffsetOld).assumingMemoryBound(to: K.self).advanced(by: i), count: 1)
                LBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + LOffsetOld).assumingMemoryBound(to: L.self).advanced(by: i), count: 1)
                MBuffer.advanced(by: i).moveInitialize(from: (oldBuffer + MOffsetOld).assumingMemoryBound(to: M.self).advanced(by: i), count: 1)}
            
            Allocator.deallocate(oldBuffer, allocator: self.allocator)
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer,
                BBuffer,
                CBuffer,
                DBuffer,
                EBuffer,
                FBuffer,
                GBuffer,
                HBuffer,
                IBuffer,
                JBuffer,
                KBuffer,
                LBuffer,
                MBuffer
        )
    }
    
}
