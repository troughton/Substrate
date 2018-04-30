// NOTE: Auto-generated from Generators/ResizingAllocator.swift

import Foundation

public final class ResizingAllocator {
    @_versioned
    let allocator : AllocatorType
    public internal(set) var capacity : Int = 0
    @_versioned
    var buffer : UnsafeMutableRawPointer! = nil
    
    public init(allocator: AllocatorType = .system) {
        self.allocator = allocator
    }
    
    deinit {
        self.buffer?.deallocate()
    }
    
    @inlinable
    public func reallocate<A>(capacity: Int) -> (UnsafeMutablePointer<A>) {
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
            ABuffer.moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self), count: self.capacity)
            oldBuffer.deallocate()
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer
        )
    }
    
    
    @inlinable
    public func reallocate<A, B>(capacity: Int) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>) {
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
            ABuffer.moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self), count: self.capacity)
            BBuffer.moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self), count: self.capacity)
            oldBuffer.deallocate()
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer,
                BBuffer
        )
    }
    
    
    @inlinable
    public func reallocate<A, B, C>(capacity: Int) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>) {
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
            ABuffer.moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self), count: self.capacity)
            BBuffer.moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self), count: self.capacity)
            CBuffer.moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self), count: self.capacity)
            oldBuffer.deallocate()
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer,
                BBuffer,
                CBuffer
        )
    }
    
    
    @inlinable
    public func reallocate<A, B, C, D>(capacity: Int) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>, UnsafeMutablePointer<D>) {
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
            ABuffer.moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self), count: self.capacity)
            BBuffer.moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self), count: self.capacity)
            CBuffer.moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self), count: self.capacity)
            DBuffer.moveInitialize(from: (oldBuffer + DOffsetOld).assumingMemoryBound(to: D.self), count: self.capacity)
            oldBuffer.deallocate()
        }
        
        self.buffer = newBuffer
        self.capacity = capacity
        
        return (ABuffer,
                BBuffer,
                CBuffer,
                DBuffer
        )
    }
    
    
    @inlinable
    public func reallocate<A, B, C, D, E>(capacity: Int) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>, UnsafeMutablePointer<D>, UnsafeMutablePointer<E>) {
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
            ABuffer.moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self), count: self.capacity)
            BBuffer.moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self), count: self.capacity)
            CBuffer.moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self), count: self.capacity)
            DBuffer.moveInitialize(from: (oldBuffer + DOffsetOld).assumingMemoryBound(to: D.self), count: self.capacity)
            EBuffer.moveInitialize(from: (oldBuffer + EOffsetOld).assumingMemoryBound(to: E.self), count: self.capacity)
            oldBuffer.deallocate()
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
    
    
    @inlinable
    public func reallocate<A, B, C, D, E, F>(capacity: Int) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>, UnsafeMutablePointer<D>, UnsafeMutablePointer<E>, UnsafeMutablePointer<F>) {
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
            ABuffer.moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self), count: self.capacity)
            BBuffer.moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self), count: self.capacity)
            CBuffer.moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self), count: self.capacity)
            DBuffer.moveInitialize(from: (oldBuffer + DOffsetOld).assumingMemoryBound(to: D.self), count: self.capacity)
            EBuffer.moveInitialize(from: (oldBuffer + EOffsetOld).assumingMemoryBound(to: E.self), count: self.capacity)
            FBuffer.moveInitialize(from: (oldBuffer + FOffsetOld).assumingMemoryBound(to: F.self), count: self.capacity)
            oldBuffer.deallocate()
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
    
    
    @inlinable
    public func reallocate<A, B, C, D, E, F, G>(capacity: Int) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>, UnsafeMutablePointer<D>, UnsafeMutablePointer<E>, UnsafeMutablePointer<F>, UnsafeMutablePointer<G>) {
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
            ABuffer.moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self), count: self.capacity)
            BBuffer.moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self), count: self.capacity)
            CBuffer.moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self), count: self.capacity)
            DBuffer.moveInitialize(from: (oldBuffer + DOffsetOld).assumingMemoryBound(to: D.self), count: self.capacity)
            EBuffer.moveInitialize(from: (oldBuffer + EOffsetOld).assumingMemoryBound(to: E.self), count: self.capacity)
            FBuffer.moveInitialize(from: (oldBuffer + FOffsetOld).assumingMemoryBound(to: F.self), count: self.capacity)
            GBuffer.moveInitialize(from: (oldBuffer + GOffsetOld).assumingMemoryBound(to: G.self), count: self.capacity)
            oldBuffer.deallocate()
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
    
    
    @inlinable
    public func reallocate<A, B, C, D, E, F, G, H>(capacity: Int) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>, UnsafeMutablePointer<D>, UnsafeMutablePointer<E>, UnsafeMutablePointer<F>, UnsafeMutablePointer<G>, UnsafeMutablePointer<H>) {
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
            ABuffer.moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self), count: self.capacity)
            BBuffer.moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self), count: self.capacity)
            CBuffer.moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self), count: self.capacity)
            DBuffer.moveInitialize(from: (oldBuffer + DOffsetOld).assumingMemoryBound(to: D.self), count: self.capacity)
            EBuffer.moveInitialize(from: (oldBuffer + EOffsetOld).assumingMemoryBound(to: E.self), count: self.capacity)
            FBuffer.moveInitialize(from: (oldBuffer + FOffsetOld).assumingMemoryBound(to: F.self), count: self.capacity)
            GBuffer.moveInitialize(from: (oldBuffer + GOffsetOld).assumingMemoryBound(to: G.self), count: self.capacity)
            HBuffer.moveInitialize(from: (oldBuffer + HOffsetOld).assumingMemoryBound(to: H.self), count: self.capacity)
            oldBuffer.deallocate()
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
    
    
    @inlinable
    public func reallocate<A, B, C, D, E, F, G, H, I>(capacity: Int) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>, UnsafeMutablePointer<D>, UnsafeMutablePointer<E>, UnsafeMutablePointer<F>, UnsafeMutablePointer<G>, UnsafeMutablePointer<H>, UnsafeMutablePointer<I>) {
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
            ABuffer.moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self), count: self.capacity)
            BBuffer.moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self), count: self.capacity)
            CBuffer.moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self), count: self.capacity)
            DBuffer.moveInitialize(from: (oldBuffer + DOffsetOld).assumingMemoryBound(to: D.self), count: self.capacity)
            EBuffer.moveInitialize(from: (oldBuffer + EOffsetOld).assumingMemoryBound(to: E.self), count: self.capacity)
            FBuffer.moveInitialize(from: (oldBuffer + FOffsetOld).assumingMemoryBound(to: F.self), count: self.capacity)
            GBuffer.moveInitialize(from: (oldBuffer + GOffsetOld).assumingMemoryBound(to: G.self), count: self.capacity)
            HBuffer.moveInitialize(from: (oldBuffer + HOffsetOld).assumingMemoryBound(to: H.self), count: self.capacity)
            IBuffer.moveInitialize(from: (oldBuffer + IOffsetOld).assumingMemoryBound(to: I.self), count: self.capacity)
            oldBuffer.deallocate()
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
    
    
    @inlinable
    public func reallocate<A, B, C, D, E, F, G, H, I, J>(capacity: Int) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>, UnsafeMutablePointer<D>, UnsafeMutablePointer<E>, UnsafeMutablePointer<F>, UnsafeMutablePointer<G>, UnsafeMutablePointer<H>, UnsafeMutablePointer<I>, UnsafeMutablePointer<J>) {
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
            ABuffer.moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self), count: self.capacity)
            BBuffer.moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self), count: self.capacity)
            CBuffer.moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self), count: self.capacity)
            DBuffer.moveInitialize(from: (oldBuffer + DOffsetOld).assumingMemoryBound(to: D.self), count: self.capacity)
            EBuffer.moveInitialize(from: (oldBuffer + EOffsetOld).assumingMemoryBound(to: E.self), count: self.capacity)
            FBuffer.moveInitialize(from: (oldBuffer + FOffsetOld).assumingMemoryBound(to: F.self), count: self.capacity)
            GBuffer.moveInitialize(from: (oldBuffer + GOffsetOld).assumingMemoryBound(to: G.self), count: self.capacity)
            HBuffer.moveInitialize(from: (oldBuffer + HOffsetOld).assumingMemoryBound(to: H.self), count: self.capacity)
            IBuffer.moveInitialize(from: (oldBuffer + IOffsetOld).assumingMemoryBound(to: I.self), count: self.capacity)
            JBuffer.moveInitialize(from: (oldBuffer + JOffsetOld).assumingMemoryBound(to: J.self), count: self.capacity)
            oldBuffer.deallocate()
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
    
    
    @inlinable
    public func reallocate<A, B, C, D, E, F, G, H, I, J, K>(capacity: Int) -> (UnsafeMutablePointer<A>, UnsafeMutablePointer<B>, UnsafeMutablePointer<C>, UnsafeMutablePointer<D>, UnsafeMutablePointer<E>, UnsafeMutablePointer<F>, UnsafeMutablePointer<G>, UnsafeMutablePointer<H>, UnsafeMutablePointer<I>, UnsafeMutablePointer<J>, UnsafeMutablePointer<K>) {
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
            ABuffer.moveInitialize(from: (oldBuffer + AOffsetOld).assumingMemoryBound(to: A.self), count: self.capacity)
            BBuffer.moveInitialize(from: (oldBuffer + BOffsetOld).assumingMemoryBound(to: B.self), count: self.capacity)
            CBuffer.moveInitialize(from: (oldBuffer + COffsetOld).assumingMemoryBound(to: C.self), count: self.capacity)
            DBuffer.moveInitialize(from: (oldBuffer + DOffsetOld).assumingMemoryBound(to: D.self), count: self.capacity)
            EBuffer.moveInitialize(from: (oldBuffer + EOffsetOld).assumingMemoryBound(to: E.self), count: self.capacity)
            FBuffer.moveInitialize(from: (oldBuffer + FOffsetOld).assumingMemoryBound(to: F.self), count: self.capacity)
            GBuffer.moveInitialize(from: (oldBuffer + GOffsetOld).assumingMemoryBound(to: G.self), count: self.capacity)
            HBuffer.moveInitialize(from: (oldBuffer + HOffsetOld).assumingMemoryBound(to: H.self), count: self.capacity)
            IBuffer.moveInitialize(from: (oldBuffer + IOffsetOld).assumingMemoryBound(to: I.self), count: self.capacity)
            JBuffer.moveInitialize(from: (oldBuffer + JOffsetOld).assumingMemoryBound(to: J.self), count: self.capacity)
            KBuffer.moveInitialize(from: (oldBuffer + KOffsetOld).assumingMemoryBound(to: K.self), count: self.capacity)
            oldBuffer.deallocate()
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
}
