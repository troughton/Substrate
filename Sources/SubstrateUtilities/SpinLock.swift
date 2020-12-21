//
//  SpinLock.swift
//  LlamaCore
//
//  Created by Thomas Roughton on 8/05/19.
//

import Atomics
import Foundation

@usableFromInline
enum LockState : UInt32 {
    case free
    case taken
}

#if canImport(SX)
import SX.Atomic
@_transparent
@inlinable
func yieldCPU() {
    sx_yield_cpu()
}
#else
@_transparent
@inlinable
func yieldCPU() {
}
#endif

/// An implementation of a spin-lock using test-and-swap
public struct SpinLock {
    @usableFromInline let value : UnsafeMutablePointer<UInt32.AtomicRepresentation>

    @inlinable
    public init() {
        self.value = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<UInt32.AtomicRepresentation>.size, alignment: 64).assumingMemoryBound(to: UInt32.AtomicRepresentation.self)
        UInt32.AtomicRepresentation.atomicStore(LockState.free.rawValue, at: self.value, ordering: .relaxed)
    }
    
    @inlinable
    public func `deinit`() {
        self.value.deallocate()
    }
    
    @inlinable
    public var isLocked : Bool {
        get {
            return UInt32.AtomicRepresentation.atomicLoad(at: self.value, ordering: .relaxed) == LockState.taken.rawValue
        }
    }
    
    @inlinable
    public func lock() {
        while UInt32.AtomicRepresentation.atomicLoad(at: self.value, ordering: .relaxed) == LockState.taken.rawValue ||
                UInt32.AtomicRepresentation.atomicExchange(LockState.taken.rawValue, at: self.value, ordering: .acquiring) == LockState.taken.rawValue {
            yieldCPU()
        }
    }
    
    @inlinable
    public func unlock() {
        _ = UInt32.AtomicRepresentation.atomicExchange(LockState.free.rawValue, at: self.value, ordering: .releasing)
    }
    
    @inlinable
    public func withLock<T>(_ perform: () throws -> T) rethrows -> T {
        self.lock()
        let result = try perform()
        self.unlock()
        return result
    }
}

public struct AsyncSpinLock {
    @usableFromInline let value : UnsafeMutablePointer<UInt32.AtomicRepresentation>

    @inlinable
    public init() {
        self.value = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<UInt32.AtomicRepresentation>.size, alignment: 64).assumingMemoryBound(to: UInt32.AtomicRepresentation.self)
        UInt32.AtomicRepresentation.atomicStore(LockState.free.rawValue, at: self.value, ordering: .relaxed)
    }
    
    @inlinable
    public func `deinit`() {
        self.value.deallocate()
    }
    
    @inlinable
    public var isLocked : Bool {
        get {
            return UInt32.AtomicRepresentation.atomicLoad(at: self.value, ordering: .relaxed) == LockState.taken.rawValue
        }
    }
    
    @inlinable
    public func lock() async {
        while UInt32.AtomicRepresentation.atomicLoad(at: self.value, ordering: .relaxed) == LockState.taken.rawValue ||
                UInt32.AtomicRepresentation.atomicExchange(LockState.taken.rawValue, at: self.value, ordering: .acquiring) == LockState.taken.rawValue {
            await Task.yield()
        }
    }
    
    @inlinable
    public func unlock() {
        _ = UInt32.AtomicRepresentation.atomicExchange(LockState.free.rawValue, at: self.value, ordering: .releasing)
    }
    
    @inlinable
    public func withLock<T>(_ perform: () async throws -> T) async rethrows -> T {
        await self.lock()
        let result = await try perform()
        self.unlock()
        return result
    }
}

public struct Semaphore {
    @usableFromInline let value : UnsafeMutablePointer<Int32.AtomicRepresentation>
    
    @inlinable
    public init(value: Int32) {
        self.value = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<Int32.AtomicRepresentation>.size, alignment: 64).assumingMemoryBound(to: Int32.AtomicRepresentation.self)
        Int32.AtomicRepresentation.atomicStore(value, at: self.value, ordering: .relaxed)
    }
    
    @inlinable
    public func `deinit`() {
        self.value.deallocate()
    }
    
    @inlinable
    public func signal() {
        Int32.AtomicRepresentation.atomicLoadThenWrappingIncrement(at: self.value, ordering: .releasing)
    }
    
    @inlinable
    public func signal(count: Int) {
        Int32.AtomicRepresentation.atomicLoadThenWrappingIncrement(by: Int32(count), at: self.value, ordering: .releasing)
    }
    
    @inlinable
    public func wait() {
        // If the value was greater than 0, we can proceed immediately.
        while Int32.AtomicRepresentation.atomicLoadThenWrappingDecrement(at: self.value, ordering: .acquiring) <= 0 {
            // Otherwise, reset and try again.
            Int32.AtomicRepresentation.atomicLoadThenWrappingIncrement(at: self.value, ordering: .relaxed)
            yieldCPU()
        }
    }
}

public struct AsyncSemaphore {
    @usableFromInline let value : UnsafeMutablePointer<Int32.AtomicRepresentation>
    
    @inlinable
    public init(value: Int32) {
        self.value = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<Int32.AtomicRepresentation>.size, alignment: 64).assumingMemoryBound(to: Int32.AtomicRepresentation.self)
        Int32.AtomicRepresentation.atomicStore(value, at: self.value, ordering: .relaxed)
    }
    
    @inlinable
    public func `deinit`() {
        self.value.deallocate()
    }
    
    @inlinable
    public func signal() {
        Int32.AtomicRepresentation.atomicLoadThenWrappingIncrement(at: self.value, ordering: .releasing)
    }
    
    @inlinable
    public func signal(count: Int) {
        Int32.AtomicRepresentation.atomicLoadThenWrappingIncrement(by: Int32(count), at: self.value, ordering: .releasing)
    }
    
    @inlinable
    public func wait() async {
        // If the value was greater than 0, we can proceed immediately.
        while Int32.AtomicRepresentation.atomicLoadThenWrappingDecrement(at: self.value, ordering: .acquiring) <= 0 {
            // Otherwise, reset and try again.
            Int32.AtomicRepresentation.atomicLoadThenWrappingIncrement(at: self.value, ordering: .relaxed)
            await Task.yield()
        }
    }
}


public struct Synchronised<T> {
    @usableFromInline var lock : SpinLock
    public var value : T
    
    @inlinable
    public init(value: T) {
        self.value = value
        self.lock = SpinLock()
    }
    
    @inlinable
    public mutating func withValue<U>(_ perform: (inout T) throws -> U) rethrows -> U {
        return try self.lock.withLock { try perform(&self.value) }
    }
}
