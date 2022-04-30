//
//  File.swift
//  
//
//  Created by Thomas Roughton on 30/04/22.
//

import Foundation

public final class TaskStream {
    let taskHandle: Task<Void, Never>
    let taskStreamContinuation: AsyncStream<@Sendable () async -> Void>.Continuation
    
    public init(priority: TaskPriority = .medium) {
        var taskStreamContinuation: AsyncStream<@Sendable () async -> Void>.Continuation? = nil
        let taskStream = AsyncStream<@Sendable () async -> Void> { continuation in
            taskStreamContinuation = continuation
        }
        self.taskStreamContinuation = taskStreamContinuation!
        
        self.taskHandle = Task.detached(priority: priority) {
            for await task in taskStream {
                await task()
            }
        }
    }
    
    deinit {
        self.taskHandle.cancel()
    }
    
    public func enqueueAndWait<T>(@_inheritActorContext @_implicitSelfCapture _ perform: @escaping @Sendable () async -> T) async -> T {
        let taskStreamContinuation = self.taskStreamContinuation
        return await withUnsafeContinuation { continuation in
            taskStreamContinuation.yield {
                continuation.resume(returning: await perform())
            }
        }
    }
    
    public func enqueueAndWait<T>(@_inheritActorContext @_implicitSelfCapture _ perform: @escaping @Sendable () async throws -> T) async throws -> T {
        let taskStreamContinuation = self.taskStreamContinuation
        return try await withUnsafeThrowingContinuation { continuation in
            taskStreamContinuation.yield {
                do {
                    continuation.resume(returning: try await perform())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    public func enqueue(@_inheritActorContext @_implicitSelfCapture _ perform: @escaping @Sendable () async -> Void) {
        self.taskStreamContinuation.yield(perform)
    }
}
