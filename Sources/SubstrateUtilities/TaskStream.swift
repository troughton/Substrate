//
//  File.swift
//  
//
//  Created by Thomas Roughton on 30/04/22.
//

import Foundation

public final class TaskStream: @unchecked Sendable {
    @usableFromInline final class TaskHolder<R>: Sendable {
        @usableFromInline let task: @Sendable () async throws -> R
        
        @inlinable
        init(task: @escaping @Sendable () async throws -> R) {
            self.task = task
        }
    }
    
    let taskHandle: Task<Void, Never>
    @usableFromInline let taskStreamContinuation: AsyncStream<@Sendable () async -> Void>.Continuation
    
    public convenience init(priority: TaskPriority = .medium) {
        self.init(creatingTask: { stream in
            Task.detached(priority: priority, operation: {
                for await task in stream {
                    await task()
                }
            })
        })
    }
    
    public init(creatingTask: (AsyncStream<@Sendable () async -> Void>) -> Task<Void, Never>) {
        var taskStreamContinuation: AsyncStream<@Sendable () async -> Void>.Continuation? = nil
        let taskStream = AsyncStream<@Sendable () async -> Void> { continuation in
            taskStreamContinuation = continuation
        }
        self.taskStreamContinuation = taskStreamContinuation!
        
        self.taskHandle = creatingTask(taskStream)
    }
    
    deinit {
        self.taskHandle.cancel()
    }
    
    @inlinable @inline(__always)
    @_unsafeInheritExecutor
    public func enqueueAndWait<T>(@_inheritActorContext @_implicitSelfCapture _ perform: @Sendable () async -> T) async -> T {
        let taskStreamContinuation = self.taskStreamContinuation
        return await withoutActuallyEscaping(perform) { perform in
            let task = TaskHolder<T>(task: perform)
            let result: T = await withUnsafeContinuation { continuation in
                taskStreamContinuation.yield { [unowned task, continuation] in
                    let result = try! await task.task()
                    continuation.resume(returning: result)
                }
            }
            withExtendedLifetime(task) {}
            return result
        }
    }
    
    @inlinable @inline(__always)
    @_unsafeInheritExecutor
    public func enqueueAndWait<T>(@_inheritActorContext @_implicitSelfCapture _ perform: @Sendable () async throws -> T) async throws -> T {
        let taskStreamContinuation = self.taskStreamContinuation
        return try await withoutActuallyEscaping(perform) { perform in
            let task = TaskHolder<T>(task: perform)
            let result: T = try await withUnsafeThrowingContinuation { continuation in
                taskStreamContinuation.yield { [unowned task, continuation] in
                    do {
                        continuation.resume(returning: try await task.task())
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            withExtendedLifetime(task) {}
            return result
        }
    }
    
    public func enqueue(@_inheritActorContext @_implicitSelfCapture _ perform: @escaping @Sendable () async -> Void) {
        self.taskStreamContinuation.yield(perform)
    }
}
