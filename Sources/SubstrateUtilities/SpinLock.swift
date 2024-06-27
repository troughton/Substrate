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
public struct SpinLock: @unchecked Sendable {
    public typealias Storage = UInt32.AtomicRepresentation
    @usableFromInline let value : UnsafeMutablePointer<Storage>
    
    @inlinable
    public init() {
        self.value = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<Storage>.size, alignment: 64).assumingMemoryBound(to: UInt32.AtomicRepresentation.self)
        Storage.atomicStore(SpinLockState.free.rawValue, at: self.value, ordering: .relaxed)
    }
    
    @inlinable
    public init(at location: UnsafeMutablePointer<Storage>) {
        self.value = location
        Storage.atomicStore(SpinLockState.free.rawValue, at: self.value, ordering: .relaxed)
    }
    
    @inlinable
    public init(initializedLockAt location: UnsafeMutablePointer<UInt32.AtomicRepresentation>) {
        self.value = location
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
    public func tryLock() -> Bool {
        if UInt32.AtomicRepresentation.atomicLoad(at: self.value, ordering: .relaxed) == SpinLockState.taken.rawValue ||
                UInt32.AtomicRepresentation.atomicExchange(SpinLockState.taken.rawValue, at: self.value, ordering: .acquiring) == SpinLockState.taken.rawValue {
            return false
        }
        return true
    }
    
    @_unsafeInheritExecutor
    @inlinable
    public func lock() async {
        while UInt32.AtomicRepresentation.atomicLoad(at: self.value, ordering: .relaxed) == SpinLockState.taken.rawValue ||
                UInt32.AtomicRepresentation.atomicExchange(SpinLockState.taken.rawValue, at: self.value, ordering: .acquiring) == SpinLockState.taken.rawValue {
            await Task.yield()
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

@usableFromInline protocol AnyTask {
    func wait() async
}

extension Task: AnyTask {
    @inlinable func wait() async {
        _ = try? await self.value
    }
}

public final class AsyncSpinLock: @unchecked Sendable {
    @usableFromInline let lock = SpinLock()
    @usableFromInline var currentTask: AnyTask?
    
    @inlinable
    public init() {
        
    }
    
    deinit {
        self.lock.deinit()
    }
    
    @inlinable @_unsafeInheritExecutor
    public func withLock<T>(@_inheritActorContext @_implicitSelfCapture _ perform: @Sendable () async -> T) async -> T {
        await self.lock.lock()
        while let currentTask = self.currentTask {
            self.lock.unlock()
            _ = await currentTask.wait()
            await self.lock.lock()
        }
        return await withoutActuallyEscaping(perform) { perform in
            let newTask = Task {
                let result = await perform()
                await self.lock.lock()
                self.currentTask = nil
                self.lock.unlock()
                return result
            }
            self.currentTask = newTask
            self.lock.unlock()
            return await newTask.value
        }
    }
    
    @inlinable @_unsafeInheritExecutor
    public func withLock<T>(@_inheritActorContext @_implicitSelfCapture _ perform: @Sendable () async throws -> T) async throws -> T {
        await self.lock.lock()
        while let currentTask = self.currentTask {
            self.lock.unlock()
            _ = await currentTask.wait()
            await self.lock.lock()
        }
        return try await withoutActuallyEscaping(perform) { perform in
            let newTask = Task {
                let result = try await perform()
                await self.lock.lock()
                self.currentTask = nil
                self.lock.unlock()
                return result
            }
            self.currentTask = newTask
            self.lock.unlock()
            return try await newTask.value
        }
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
