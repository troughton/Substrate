//
//  SpinLock.swift
//  LlamaCore
//
//  Created by Thomas Roughton on 8/05/19.
//

import SwiftAtomics
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
/// Necessary for fibers since fibers can move between threads.
@_alignment(16)
public struct SpinLock {
    @usableFromInline var value : AtomicUInt32 = AtomicUInt32(LockState.free.rawValue)

    @inlinable
    public init() {
        
    }
    
    @inlinable
    public var isLocked : Bool {
        mutating get {
            return self.value.load() == LockState.taken.rawValue
        }
    }
    
    @inlinable
    public mutating func lock() {
        while self.value.load() == LockState.taken.rawValue ||
            self.value.swap(LockState.taken.rawValue) == LockState.taken.rawValue {
            yieldCPU()
        }
    }
    
    @inlinable
    public mutating func unlock() {
        _ = self.value.swap(LockState.free.rawValue)
    }
    
    @inlinable
    public mutating func withLock<T>(_ perform: () throws -> T) rethrows -> T {
        self.lock()
        let result = try perform()
        self.unlock()
        return result
    }
}

@_alignment(16)
public struct Semaphore {
    @usableFromInline var value : AtomicInt32
    
    @inlinable
    public init(value: Int32) {
        self.value = AtomicInt32(value)
    }
    
    @inlinable
    public mutating func signal() {
        self.value.increment()
    }
    
    @inlinable
    public mutating func signal(count: Int) {
        self.value.add(Int32(count))
    }
    
    @inlinable
    public mutating func wait() {
        // If the value was greater than 0, we can proceed immediately.
        while self.value.decrement() <= 0 {
            // Otherwise, reset and try again.
            self.value.increment()
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
