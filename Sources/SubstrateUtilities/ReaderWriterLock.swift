//
//  ReaderWriterLock.swift
//  Utilities
//
//  Created by Thomas Roughton on 17/05/19.
//

import Atomics
import Foundation

/// An implementation of a spin-lock using test-and-swap
/// Necessary for fibers since fibers can move between threads.
public struct ReaderWriterLock {
    // either the number of readers or .max for writer-lock.
    @usableFromInline let value : UnsafeMutablePointer<UInt32.AtomicRepresentation>
    
    @inlinable
    public init() {
        self.value = UnsafeMutablePointer.allocate(capacity: 1)
        UInt32.AtomicRepresentation.atomicStore(SpinLockState.free.rawValue, at: self.value, ordering: .relaxed)
    }
    
    @inlinable
    public func `deinit`() {
        self.value.deallocate()
    }
    
    @inlinable
    public func acquireWriteAccess() {
        while true {
            if UInt32.AtomicRepresentation.atomicLoad(at: self.value, ordering: .relaxed) == 0 {
                if UInt32.AtomicRepresentation.atomicWeakCompareExchange(expected: 0, desired: .max, at: self.value, successOrdering: .acquiring, failureOrdering: .relaxed).exchanged {
                    return
                }
            }
            yieldCPU()
        }
    }
    
    @inlinable
    public func acquireReadAccess() {
        while true {
            let previousReaders = UInt32.AtomicRepresentation.atomicLoad(at: self.value, ordering: .relaxed)
            
            if previousReaders != .max {
                let newReaders = previousReaders &+ 1
                if UInt32.AtomicRepresentation.atomicWeakCompareExchange(expected: previousReaders, desired: newReaders, at: self.value, successOrdering: .acquiring, failureOrdering: .relaxed).exchanged {
                    return
                }
            }
            yieldCPU()
        }
    }
    
    @inlinable
    public func transformReadToWriteAccess() {
        let previousReaders = UInt32.AtomicRepresentation.atomicLoad(at: self.value, ordering: .relaxed)
        if previousReaders == 1 {
            if UInt32.AtomicRepresentation.atomicWeakCompareExchange(expected: previousReaders, desired: .max, at: self.value, successOrdering: .relaxed, failureOrdering: .relaxed).exchanged {
                return
            }
        }

        self.releaseReadAccess()
        self.acquireWriteAccess()
    }
    
    @inlinable
    public func releaseReadAccess() {
        while true {
            let previousReaders = UInt32.AtomicRepresentation.atomicLoad(at: self.value, ordering: .relaxed)
            if previousReaders != .max /* && previousReaders > 0 */ {
                let newReaders = previousReaders &- 1
                if UInt32.AtomicRepresentation.atomicWeakCompareExchange(expected: previousReaders, desired: newReaders, at: self.value, successOrdering: .relaxed, failureOrdering: .relaxed).exchanged {
                    return
                }
            }
            yieldCPU()
        }
    }
    
    @inlinable
    public func releaseWriteAccess() {
        while true {
            let previousReaders = UInt32.AtomicRepresentation.atomicLoad(at: self.value, ordering: .relaxed)
            if previousReaders == .max {
                if UInt32.AtomicRepresentation.atomicWeakCompareExchange(expected: previousReaders, desired: 0, at: self.value, successOrdering: .releasing, failureOrdering: .relaxed).exchanged {
                    return
                }
            }
            
            yieldCPU()
        }
    }
    
    @inlinable
    public func withReadLock<T>(_ perform: () throws -> T) rethrows -> T {
        self.acquireReadAccess()
        let result = try perform()
        self.releaseReadAccess()
        return result
    }
    
    @inlinable
    public func withWriteLock<T>(_ perform: () throws -> T) rethrows -> T {
        self.acquireWriteAccess()
        let result = try perform()
        self.releaseWriteAccess()
        return result
    }
}
