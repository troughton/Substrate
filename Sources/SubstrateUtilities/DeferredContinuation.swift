//
//  File.swift
//  
//
//  Created by Thomas Roughton on 7/01/22.
//

import Foundation
import Atomics

protocol _DeferredContinuationInit {
    init(other: Self)
}

extension _DeferredContinuationInit {
    init(other: Self) {
        self = other
    }
}

public final class DeferredContinuation: ManagedBuffer<Void, UnsafeRawPointer.AtomicOptionalRepresentation>, @unchecked Sendable {
    
    var continuationPtr: UnsafeRawPointer? {
        get {
            return self.withUnsafeMutablePointerToElements {
                return UnsafeRawPointer.AtomicOptionalRepresentation.atomicLoad(at: $0, ordering: .relaxed)
            }
        }
    }
    
    func setContinuationResumed() -> UnsafeContinuation<Void, Never>? {
        let oldValue = self.withUnsafeMutablePointerToElements {
            UnsafeRawPointer.AtomicOptionalRepresentation.atomicExchange(UnsafeRawPointer(bitPattern: UInt.max), at: $0, ordering: .relaxed)
        }
        
        if let oldValue = oldValue, UInt(bitPattern: oldValue) != .max {
            return unsafeBitCast(oldValue, to: UnsafeContinuation<Void, Never>.self)
        }
        
        return nil
    }
    
    public func resume() {
        guard let continuation = self.setContinuationResumed() else {
            return
        }
        continuation.resume()
    }
    
    public func wait() async {
        return await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
            let (exchanged, original) = self.withUnsafeMutablePointerToElements { pointer in
                 UnsafeRawPointer.AtomicOptionalRepresentation.atomicCompareExchange(expected: nil, desired: unsafeBitCast(continuation, to: UnsafeRawPointer?.self), at: pointer, ordering: .relaxed)
            }
            if exchanged {
                return
            } else if UInt(bitPattern: original) == .max {
                continuation.resume()
            } else {
                preconditionFailure("Multiple callers waiting on the same continuation simultaneously is not permitted")
            }
        }
    }
}

extension DeferredContinuation: _DeferredContinuationInit {
    public convenience init() {
        self.init(other: Self.create(minimumCapacity: 1, makingHeaderWith: { _ in }) as! Self)
        self.withUnsafeMutablePointerToElements {
            UnsafeRawPointer.AtomicOptionalRepresentation.atomicStore(nil, at: $0, ordering: .relaxed)
        }
    }
}
