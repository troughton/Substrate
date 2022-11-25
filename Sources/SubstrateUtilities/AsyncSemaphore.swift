//
//  File.swift
//  
//
//  Created by Thomas Roughton on 25/11/22.
//

import Foundation
import Atomics

protocol _AsyncSemaphoreInit {
    init(other: Self)
}

extension _AsyncSemaphoreInit {
    init(other: Self) {
        self = other
    }
}


public struct _AsyncSemaphoreHeader {
    @usableFromInline let pendingContinuations: RingBuffer<UnsafeContinuation<Void, Never>>
    @usableFromInline var availableCapacity: Int
}

public final class AsyncSemaphore: ManagedBuffer<_AsyncSemaphoreHeader, UInt32.AtomicRepresentation> {
    
    public func signal() {
        self.withLock {
            self.withUnsafeMutablePointerToHeader { header in
                if let waiting = header.pointee.pendingContinuations.popFirst() {
                    assert(header.pointee.availableCapacity == 0)
                    waiting.resume()
                } else {
                    header.pointee.availableCapacity += 1
                }
            }
        }
    }
    
    @_unsafeInheritExecutor
    @inlinable @inline(__always)
    public func wait() async {
        await withUnsafeContinuation { continuation in
            self.withLock {
                self.withUnsafeMutablePointerToHeader { header in
                    if header.pointee.availableCapacity > 0 {
                        header.pointee.availableCapacity -= 1
                        continuation.resume()
                    } else {
                        header.pointee.pendingContinuations.append(continuation)
                    }
                }
            }
        }
    }
    
    @inlinable func withLock(_ perform: () -> Void) {
        self.withUnsafeMutablePointerToElements { elements in
            let lock = SpinLock(initializedLockAt: elements)
            lock.withLock(perform)
        }
    }
}

extension AsyncSemaphore: _AsyncSemaphoreInit {
    public convenience init(count: Int) {
        self.init(other: Self.create(minimumCapacity: 1, makingHeaderWith: { _ in _AsyncSemaphoreHeader(pendingContinuations: .init(), availableCapacity: count) }) as! Self)
        self.withUnsafeMutablePointerToElements {
            _ = SpinLock(at: $0)
        }
    }
}
