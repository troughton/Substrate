//
//  ReaderWriterLock.swift
//  Utilities
//
//  Created by Thomas Roughton on 17/05/19.
//

import SwiftAtomics
import Foundation

/// An implementation of a spin-lock using test-and-swap
/// Necessary for fibers since fibers can move between threads.
@_alignment(16)
public struct ReaderWriterLock {
    // either the number of readers or .max for writer-lock.
    @usableFromInline var value : AtomicUInt32 = AtomicUInt32(LockState.free.rawValue)
    
    @inlinable
    public init() {
        
    }
    
    @inlinable
    public mutating func acquireWriteAccess() {
        while true {
            var previousReaders = self.value.load(order: .relaxed)
            if previousReaders == 0 {
                if self.value.loadCAS(current: &previousReaders, future: .max, type: .weak, orderSwap: .relaxed, orderLoad: .relaxed) {
                    return
                }
            }
            yieldCPU()
        }
    }
    
    @inlinable
    public mutating func acquireReadAccess() {
        while true {
            var previousReaders = self.value.load(order: .relaxed)
            
            if previousReaders != .max {
                let newReaders = previousReaders &+ 1
                if self.value.loadCAS(current: &previousReaders, future: newReaders, type: .weak, orderSwap: .relaxed, orderLoad: .relaxed) {
                    return
                }
            }
            yieldCPU()
        }
    }
    
    @inlinable
    public mutating func transformReadToWriteAccess() {
        var previousReaders = self.value.load(order: .relaxed)
        if previousReaders == 1 {
            if self.value.loadCAS(current: &previousReaders, future: .max, type: .weak, orderSwap: .relaxed, orderLoad: .relaxed) {
                return
            }
        }

        self.releaseReadAccess()
        self.acquireWriteAccess()
    }
    
    @inlinable
    public mutating func releaseReadAccess() {
        while true {
            var previousReaders = self.value.load(order: .relaxed)
            if previousReaders != .max /* && previousReaders > 0 */ {
                let newReaders = previousReaders &- 1
                if self.value.loadCAS(current: &previousReaders, future: newReaders, type: .weak, orderSwap: .relaxed, orderLoad: .relaxed) {
                    return
                }
            }
            yieldCPU()
        }
    }
    
    @inlinable
    public mutating func releaseWriteAccess() {
        while true {
            var previousReaders = self.value.load(order: .relaxed)
            if previousReaders == .max {
                if self.value.loadCAS(current: &previousReaders, future: 0, type: .weak, orderSwap: .relaxed, orderLoad: .relaxed) {
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
