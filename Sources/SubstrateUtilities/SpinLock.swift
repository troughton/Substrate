//
//  SpinLock.swift
//  LlamaCore
//
//  Created by Thomas Roughton on 8/05/19.
//

import Atomics
import Foundation

public enum SpinLockState : UInt32 {
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
        UInt32.AtomicRepresentation.atomicStore(SpinLockState.free.rawValue, at: self.value, ordering: .relaxed)
    }
    
    @inlinable
    public init(at location: UnsafeMutablePointer<UInt32.AtomicRepresentation>) {
        self.value = location
        UInt32.AtomicRepresentation.atomicStore(SpinLockState.free.rawValue, at: self.value, ordering: .relaxed)
    }
    
    @inlinable
    public func `deinit`() {
        self.value.deallocate()
    }
    
    @inlinable
    public var isLocked : Bool {
        get {
            return UInt32.AtomicRepresentation.atomicLoad(at: self.value, ordering: .relaxed) == SpinLockState.taken.rawValue
        }
    }
    
    @inlinable
    public func lock() {
        while UInt32.AtomicRepresentation.atomicLoad(at: self.value, ordering: .relaxed) == SpinLockState.taken.rawValue ||
                UInt32.AtomicRepresentation.atomicExchange(SpinLockState.taken.rawValue, at: self.value, ordering: .acquiring) == SpinLockState.taken.rawValue {
            yieldCPU()
        }
    }
    
    @inlinable
    public func unlock() {
        _ = UInt32.AtomicRepresentation.atomicExchange(SpinLockState.free.rawValue, at: self.value, ordering: .releasing)
    }
    
    @inlinable
    public func withLock<T>(_ perform: () throws -> T) rethrows -> T {
        self.lock()
        defer { self.unlock() }
        let result = try perform()
        return result
    }
}


public actor AsyncSpinLock {
    @usableFromInline var currentTask: Task<Void, Never>?
    
    @inlinable
    public init() {
        
    }
    
    @inlinable
    public func withLock<T>(@_inheritActorContext @_implicitSelfCapture _ perform: @Sendable @escaping () async -> T) async -> T {
        while let currentTask = self.currentTask {
            _ = await currentTask.value
        }
        let newTask = Task { await perform() }
        self.currentTask = Task { _ = await newTask.value }
        let result = await newTask.value
        self.currentTask = nil
        return result
    }
    
    @inlinable
    public func withLock<T>(@_inheritActorContext @_implicitSelfCapture _ perform: @Sendable @escaping () async throws -> T) async throws -> T {
        while let currentTask = self.currentTask {
            _ = await currentTask.value
        }
        let newTask = Task { try await perform() }
        self.currentTask = Task { _ = try? await newTask.value }
        defer { self.currentTask = nil }
        let result = try await newTask.value
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
