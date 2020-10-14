//
//  SpinLock.swift
//  LlamaCore
//
//  Created by Thomas Roughton on 8/05/19.
//

import CAtomics
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
    @usableFromInline let value : UnsafeMutablePointer<AtomicUInt32>

    @inlinable
    public init() {
        self.value = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<AtomicUInt32>.size, alignment: 64).assumingMemoryBound(to: AtomicUInt32.self)
        CAtomicsStore(self.value, LockState.free.rawValue, .relaxed)
    }
    
    @inlinable
    public func `deinit`() {
        self.value.deallocate()
    }
    
    @inlinable
    public var isLocked : Bool {
        get {
            return CAtomicsLoad(self.value, .relaxed) == LockState.taken.rawValue
        }
    }
    
    @inlinable
    public func lock() {
        while CAtomicsLoad(self.value, .relaxed) == LockState.taken.rawValue ||
            CAtomicsExchange(self.value, LockState.taken.rawValue, .relaxed) == LockState.taken.rawValue {
            yieldCPU()
        }
    }
    
    @inlinable
    public func unlock() {
        _ = CAtomicsExchange(self.value, LockState.free.rawValue, .relaxed)
    }
    
    @inlinable
    public func withLock<T>(_ perform: () throws -> T) rethrows -> T {
        self.lock()
        let result = try perform()
        self.unlock()
        return result
    }
}

public struct Semaphore {
    @usableFromInline let value : UnsafeMutablePointer<AtomicInt32>
    
    @inlinable
    public init(value: Int32) {
        self.value = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<AtomicInt32>.size, alignment: 64).assumingMemoryBound(to: AtomicInt32.self)
        CAtomicsStore(self.value, value, .relaxed)
    }
    
    @inlinable
    public func `deinit`() {
        self.value.deallocate()
    }
    
    @inlinable
    public func signal() {
        CAtomicsAdd(self.value, 1, .relaxed)
    }
    
    @inlinable
    public func signal(count: Int) {
        CAtomicsAdd(self.value, Int32(count), .relaxed)
    }
    
    @inlinable
    public func wait() {
        // If the value was greater than 0, we can proceed immediately.
        while CAtomicsSubtract(self.value, 1, .relaxed) <= 0 {
            // Otherwise, reset and try again.
            CAtomicsAdd(self.value, 1, .relaxed)
            yieldCPU()
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
