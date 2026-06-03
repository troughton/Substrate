//
//  File.swift
//  
//
//  Created by Thomas Roughton on 30/04/22.
//

import Foundation

public final class TaskStream: @unchecked Sendable {
    // Based on https://forums.swift.org/t/task-gates-for-the-standard-library/85052
    @usableFromInline actor PendingTaskQueue { // Ring buffer
        @usableFromInline
        typealias Element = UnsafeContinuation<Void, Never>
        
        var pendingContinuations: UnsafeMutablePointer<Element>?
        var capacity: Int
        var lowerBound: Int
        var count: Int
        
        @usableFromInline var hasActiveTask = false
        
        init() {
            self.pendingContinuations = nil
            self.capacity = 0
            self.lowerBound = 0
            self.count = 0
        }
        
        func reserveCapacity(_ capacity: Int) {
            if self.capacity < capacity {
                let newCapacity = max((self.capacity * 3) / 2, capacity)
                let newBuffer = UnsafeMutablePointer<Element>.allocate(capacity: newCapacity)
                
                if let oldBuffer = self.pendingContinuations {
                    let tailCount = min(self.capacity - self.lowerBound, self.count)
                    newBuffer.moveInitialize(from: oldBuffer.advanced(by: self.lowerBound), count: tailCount)
                    if tailCount < self.count {
                        newBuffer.advanced(by: tailCount).moveInitialize(from: oldBuffer, count: self.count - tailCount)
                    }
                }
                
                self.pendingContinuations = newBuffer
                self.lowerBound = 0
                self.capacity = newCapacity
            }
        }
        
        @usableFromInline
        func append(_ element: consuming Element) {
            self.reserveCapacity(self.count + 1)
            self.pendingContinuations?.advanced(by: (self.lowerBound + self.count) % self.capacity).initialize(to: element)
            self.count += 1
        }
        
        @usableFromInline
        func popFirst() -> Element? {
            if self.count == 0 {
                return nil
            }
            
            let element = self.pendingContinuations?.advanced(by: self.lowerBound).move()
            self.lowerBound = (self.lowerBound + 1) % self.capacity
            self.count -= 1
            return element
        }
        
        @inlinable
        public func acquire() async {
            if !self.hasActiveTask {
                self.hasActiveTask = true
            } else {
                await withUnsafeContinuation { continuation in
                    self.append(continuation)
                }
            }
        }
        
        @inlinable
        public func release() {
            if let continuation = self.popFirst() {
                continuation.resume()
            } else {
                self.hasActiveTask = false
            }
        }
    }
    
    @usableFromInline let pendingTaskQueue = PendingTaskQueue()
    
    @available(*, deprecated, renamed: "init()", message: "TaskStream no longer takes a priority")
    public init(priority: TaskPriority) {}
    
    public init() {}
    
    @inlinable @inline(__always)
    public nonisolated(nonsending) func enqueueAndWait<T>(@_implicitSelfCapture _ perform: nonisolated(nonsending) () async -> T) async -> T {
        await self.pendingTaskQueue.acquire()
        let result = await perform()
        await self.pendingTaskQueue.release()
        return result
    }
    
    @inlinable @inline(__always)
    public nonisolated(nonsending) func enqueueAndWait<T>(@_implicitSelfCapture _ perform: nonisolated(nonsending) () async throws -> T) async throws -> T {
        await self.pendingTaskQueue.acquire()
        do {
            let result = try await perform()
            await self.pendingTaskQueue.release()
            return result
        } catch {
            await self.pendingTaskQueue.release()
            throw error
        }
    }
    
    public func enqueue(_ perform: @escaping @Sendable () async -> Void) {
        Task.detached {
            await self.pendingTaskQueue.acquire()
            await perform()
            await self.pendingTaskQueue.release()
        }
    }
}
