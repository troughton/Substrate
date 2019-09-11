//
//  ReaderWriterLock.swift
//  Utilities
//
//  Created by Thomas Roughton on 17/05/19.
//

import CAtomics
import Foundation

/// An implementation of a spin-lock using test-and-swap
/// Necessary for fibers since fibers can move between threads.
public struct ReaderWriterLock {
    // either the number of readers or .max for writer-lock.
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
    public mutating func acquireWriteAccess() {
        while true {
            var previousReaders = CAtomicsLoad(self.value, .relaxed)
            if previousReaders == 0 {
                if CAtomicsCompareAndExchange(self.value, &previousReaders, .max, .weak, .relaxed, .relaxed) {
                    return
                }
            }
            yieldCPU()
        }
    }
    
    @inlinable
    public mutating func acquireReadAccess() {
        while true {
            var previousReaders = CAtomicsLoad(self.value, .relaxed)
            
            if previousReaders != .max {
                let newReaders = previousReaders &+ 1
                if CAtomicsCompareAndExchange(self.value, &previousReaders, newReaders, .weak, .relaxed, .relaxed) {
                    return
                }
            }
            yieldCPU()
        }
    }
    
    @inlinable
    public mutating func transformReadToWriteAccess() {
        var previousReaders = CAtomicsLoad(self.value, .relaxed)
        if previousReaders == 1 {
            if CAtomicsCompareAndExchange(self.value, &previousReaders, .max, .weak, .relaxed, .relaxed) {
                return
            }
        }

        self.releaseReadAccess()
        self.acquireWriteAccess()
    }
    
    @inlinable
    public mutating func releaseReadAccess() {
        while true {
            var previousReaders = CAtomicsLoad(self.value, .relaxed)
            if previousReaders != .max /* && previousReaders > 0 */ {
                let newReaders = previousReaders &- 1
                if CAtomicsCompareAndExchange(self.value, &previousReaders, newReaders, .weak, .relaxed, .relaxed) {
                    return
                }
            }
            yieldCPU()
        }
    }
    
    @inlinable
    public mutating func releaseWriteAccess() {
        while true {
            var previousReaders = CAtomicsLoad(self.value, .relaxed)
            if previousReaders == .max {
                if CAtomicsCompareAndExchange(self.value, &previousReaders, 0, .weak, .relaxed, .relaxed) {
                    return
                }
            }
            
            yieldCPU()
        }
    }
    
    @inlinable
    public mutating func withReadLock<T>(_ perform: () throws -> T) rethrows -> T {
        self.acquireReadAccess()
        let result = try perform()
        self.releaseReadAccess()
        return result
    }
    
    @inlinable
    public mutating func withWriteLock<T>(_ perform: () throws -> T) rethrows -> T {
        self.acquireWriteAccess()
        let result = try perform()
        self.releaseWriteAccess()
        return result
    }
}
