//
//  Queue.swift
//
//
//  Created by Thomas Roughton on 26/10/19.
//

import SubstrateUtilities
import Atomics
import Dispatch
import Foundation
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#elseif os(Linux)
import Glibc
#elseif os(Windows)
import CRT
#endif

public final class QueueRegistry {
    public static let shared = QueueRegistry()
    
    public static let maxQueues = UInt8.bitWidth
    
    public static let bufferedSubmissionCount = 32
    
    public let lastSubmittedCommands : UnsafeMutablePointer<UInt64.AtomicRepresentation>
    public let lastCompletedCommands : UnsafeMutablePointer<UInt64.AtomicRepresentation>
    let commandSubmissionTimes : UnsafeMutablePointer<UInt64.AtomicRepresentation>
    let commandCompletionTimes : UnsafeMutablePointer<UInt64.AtomicRepresentation>
    let commandGPUStartTimes : UnsafeMutablePointer<UInt64.AtomicRepresentation>
    let commandGPUEndTimes : UnsafeMutablePointer<UInt64.AtomicRepresentation>
    let commandWaiters: UnsafeMutablePointer<[UnsafeContinuation<Void, Never>]>
    let queueLocks: UnsafeMutablePointer<UInt32.AtomicRepresentation>
    
    var allocatedQueues : UInt8 = 0
    var lock = SpinLock()
    
    public init() {
        self.lastSubmittedCommands = .allocate(capacity: Self.maxQueues)
        self.lastSubmittedCommands.initialize(repeating: .init(0), count: Self.maxQueues)
        
        self.lastCompletedCommands = .allocate(capacity: Self.maxQueues)
        self.lastCompletedCommands.initialize(repeating: .init(0), count: Self.maxQueues)
        
        self.commandSubmissionTimes = .allocate(capacity: Self.maxQueues * Self.bufferedSubmissionCount)
        self.commandSubmissionTimes.initialize(repeating: .init(0), count: Self.maxQueues * Self.bufferedSubmissionCount)
        
        self.commandCompletionTimes = .allocate(capacity: Self.maxQueues * Self.bufferedSubmissionCount)
        self.commandCompletionTimes.initialize(repeating: .init(0), count: Self.maxQueues * Self.bufferedSubmissionCount)
        
        self.commandGPUStartTimes = .allocate(capacity: Self.maxQueues * Self.bufferedSubmissionCount)
        self.commandGPUStartTimes.initialize(repeating: .init(0), count: Self.maxQueues * Self.bufferedSubmissionCount)
        
        self.commandGPUEndTimes = .allocate(capacity: Self.maxQueues * Self.bufferedSubmissionCount)
        self.commandGPUEndTimes.initialize(repeating: .init(0), count: Self.maxQueues * Self.bufferedSubmissionCount)
        
        self.commandWaiters = .allocate(capacity: Self.maxQueues * Self.bufferedSubmissionCount)
        self.commandWaiters.initialize(repeating: [], count: Self.maxQueues * Self.bufferedSubmissionCount)
        
        self.queueLocks = .allocate(capacity: Self.maxQueues)
        for i in 0..<Self.maxQueues {
            _ = SpinLock(at: self.queueLocks.advanced(by: i))
        }
    }
    
    deinit {
        self.lastSubmittedCommands.deallocate()
        self.lastCompletedCommands.deallocate()
        self.commandSubmissionTimes.deallocate()
        self.commandCompletionTimes.deallocate()
        
        self.commandGPUStartTimes.deallocate()
        self.commandGPUEndTimes.deallocate()
        
        self.commandWaiters.deinitialize(count: Self.maxQueues * Self.bufferedSubmissionCount)
        self.commandWaiters.deallocate()
        
        self.queueLocks.deallocate()
    }
    
    public static var allQueues : IteratorSequence<QueueIterator> {
        get {
            return IteratorSequence(QueueIterator())
        }
    }
    
    public func allocate() -> UInt8 {
        return Self.shared.lock.withLock {
            for i in 0..<self.allocatedQueues.bitWidth {
                if self.allocatedQueues & (1 << i) == 0 {
                    self.allocatedQueues |= (1 << i)
                    
                    UInt64.AtomicRepresentation.atomicStore(0, at: self.lastSubmittedCommands.advanced(by: i), ordering: .relaxed)
                    UInt64.AtomicRepresentation.atomicStore(0, at: self.lastCompletedCommands.advanced(by: i), ordering: .relaxed)
                    
                    return UInt8(i)
                }
            }
            
            fatalError("Only \(Self.maxQueues) queues may exist at any time.")
        }
    }
    
    public func dispose(_ queue: Queue) {
        Self.shared.lock.withLock {
            precondition(self.allocatedQueues & (1 << Int(queue.index)) != 0, "Queue being disposed is not allocated.")
            for i in 0..<Self.bufferedSubmissionCount {
                precondition(self.commandWaiters[Int(queue.index) * Self.bufferedSubmissionCount + i].isEmpty)
            }
            self.allocatedQueues &= ~(1 << Int(queue.index))
        }
    }
    
    public struct QueueIterator : IteratorProtocol {
        let allocatedQueues: UInt8
        var nextIndex = 0
        
        init() {
            self.allocatedQueues = QueueRegistry.shared.lock.withLock { QueueRegistry.shared.allocatedQueues }
            self.nextIndex = (0..<QueueRegistry.maxQueues)
                .first(where: { allocatedQueues & (1 << $0) != 0 }) ?? QueueRegistry.maxQueues
        }
        
        public mutating func next() -> Queue? {
            if self.nextIndex < QueueRegistry.maxQueues {
                let queue = Queue(index: UInt8(self.nextIndex))
                self.nextIndex = (0..<QueueRegistry.maxQueues)
                    .dropFirst(self.nextIndex + 1)
                    .first(where: { allocatedQueues & (1 << $0) != 0 }) ?? QueueRegistry.maxQueues
                return queue
            }
            return nil
        }
    }
    
    public static var lastSubmittedCommands: QueueCommandIndices {
        var commands = QueueCommandIndices(repeating: 0)
        for i in 0..<Self.maxQueues {
            commands[i] = UInt64.AtomicRepresentation.atomicLoad(at: self.shared.lastSubmittedCommands.advanced(by: i), ordering: .relaxed)
        }
        return commands
    }
    
    public static var lastCompletedCommands: QueueCommandIndices {
        var commands = QueueCommandIndices(repeating: 0)
        for i in 0..<Self.maxQueues {
            commands[i] = UInt64.AtomicRepresentation.atomicLoad(at: self.shared.lastCompletedCommands.advanced(by: i), ordering: .relaxed)
        }
        return commands
    }
}

public struct Queue : Equatable, Sendable {
    public let index : UInt8
    
    fileprivate init(index: UInt8) {
        self.index = index
    }
    
    init() {
        self.index = QueueRegistry.shared.allocate()
    }
    
    func dispose() {
        QueueRegistry.shared.dispose(self)
    }
    
    var lock: SpinLock {
        return SpinLock(initializedLockAt: QueueRegistry.shared.queueLocks.advanced(by: Int(self.index)))
    }
    
    func submitCommand(commandIndex: UInt64) {
        if commandIndex > QueueRegistry.bufferedSubmissionCount {
            let previousCommand = commandIndex - UInt64(QueueRegistry.bufferedSubmissionCount)
            while self.lastCompletedCommand < previousCommand {
                #if os(Windows)
                Sleep(0)
                #else
                sched_yield()
                #endif
            }
        }
        
        self.lock.withLock { // lock to avoid invalidating the previous command's buffered data before we're done processing it.
            UInt64.AtomicRepresentation.atomicStore(commandIndex, at: QueueRegistry.shared.lastSubmittedCommands.advanced(by: Int(self.index)), ordering: .relaxed)
            
            let indexInQueuesArray = self.indexInQueuesArrays(for: commandIndex)!
            UInt64.AtomicRepresentation.atomicStore(DispatchTime.now().uptimeNanoseconds, at: QueueRegistry.shared.commandSubmissionTimes.advanced(by: indexInQueuesArray), ordering: .relaxed)
        }
    }
    
    func didCompleteCommand(_ commandIndex: UInt64, completionTime: DispatchTime) {
        self.lock.withLock {
            let indexInQueuesArray = self.indexInQueuesArrays(for: commandIndex)!
            UInt64.AtomicRepresentation.atomicStore(commandIndex, at: QueueRegistry.shared.lastCompletedCommands.advanced(by: Int(self.index)), ordering: .relaxed)
            UInt64.AtomicRepresentation.atomicStore(completionTime.uptimeNanoseconds, at: QueueRegistry.shared.commandCompletionTimes.advanced(by: indexInQueuesArray), ordering: .relaxed)
            
            for waiter in QueueRegistry.shared.commandWaiters[indexInQueuesArray] {
                waiter.resume()
            }
            
            QueueRegistry.shared.commandWaiters[indexInQueuesArray].removeAll()
        }
    }
    
    public var lastSubmittedCommand : UInt64 {
        get {
            return UInt64.AtomicRepresentation.atomicLoad(at: QueueRegistry.shared.lastSubmittedCommands.advanced(by: Int(self.index)), ordering: .relaxed)
        }
    }
    
    func hasBufferedData(for commandIndex: UInt64) -> Bool {
        let lastSubmittedCommand = self.lastSubmittedCommand
        
        if commandIndex > lastSubmittedCommand { return false }
        if lastSubmittedCommand < QueueRegistry.bufferedSubmissionCount { return true }
        
        let lastBufferedCommand = lastSubmittedCommand + 1 - UInt64(QueueRegistry.bufferedSubmissionCount)
        return (lastBufferedCommand...lastSubmittedCommand).contains(commandIndex)
    }
    
    func indexInQueuesArrays(for commandIndex: UInt64) -> Int? {
        guard self.hasBufferedData(for: commandIndex) else { return nil }
        
        let indexInBuffer = commandIndex % UInt64(QueueRegistry.bufferedSubmissionCount)
        return Int(self.index) * QueueRegistry.bufferedSubmissionCount + Int(indexInBuffer)
    }
    
    public func submissionTime(for commandIndex: UInt64) -> DispatchTime? {
        guard let indexInQueuesArray = self.indexInQueuesArrays(for: commandIndex) else { return nil }
        
        let time = UInt64.AtomicRepresentation.atomicLoad(at: QueueRegistry.shared.commandSubmissionTimes.advanced(by: indexInQueuesArray), ordering: .relaxed)
        
        guard self.hasBufferedData(for: commandIndex) else { return nil }
        
        return DispatchTime(uptimeNanoseconds: time)
    }
    
    public func completionTime(for commandIndex: UInt64) -> DispatchTime? {
        guard let indexInQueuesArray = self.indexInQueuesArrays(for: commandIndex) else { return nil }
        
        let time = UInt64.AtomicRepresentation.atomicLoad(at: QueueRegistry.shared.commandCompletionTimes.advanced(by: indexInQueuesArray), ordering: .relaxed)
        
        guard self.hasBufferedData(for: commandIndex) else { return nil } // Make sure the data we retrieved was valid
        
        return DispatchTime(uptimeNanoseconds: time)
    }
    
    /// The host time at which the specified command buffer began executing on the GPU, in seconds.
    public func gpuStartTime(for commandIndex: UInt64) -> DispatchTime? {
        guard let indexInQueuesArray = self.indexInQueuesArrays(for: commandIndex) else { return nil }
        
        let time = UInt64.AtomicRepresentation.atomicLoad(at: QueueRegistry.shared.commandGPUStartTimes.advanced(by: indexInQueuesArray), ordering: .relaxed)
        
        guard self.hasBufferedData(for: commandIndex) else { return nil }
        
        return DispatchTime(uptimeNanoseconds: time)
    }
    
    func setGPUStartTime(_ time: DispatchTime, for commandIndex: UInt64) {
        let indexInQueuesArray = self.indexInQueuesArrays(for: commandIndex)!
        
        UInt64.AtomicRepresentation.atomicStore(time.uptimeNanoseconds, at: QueueRegistry.shared.commandGPUStartTimes.advanced(by: indexInQueuesArray), ordering: .relaxed)
    }
    
    /// The host time at which the specified command buffer completed on the GPU, in seconds.
    public func gpuEndTime(for commandIndex: UInt64) -> DispatchTime? {
        guard let indexInQueuesArray = self.indexInQueuesArrays(for: commandIndex) else { return nil }
        
        let time = UInt64.AtomicRepresentation.atomicLoad(at: QueueRegistry.shared.commandGPUEndTimes.advanced(by: indexInQueuesArray), ordering: .relaxed)
        
        guard self.hasBufferedData(for: commandIndex) else { return nil } // Make sure the data we retrieved was valid
        
        return DispatchTime(uptimeNanoseconds: time)
    }
    
    func setGPUEndTime(_ time: DispatchTime, for commandIndex: UInt64) {
        let indexInQueuesArray = self.indexInQueuesArrays(for: commandIndex)!
        
        UInt64.AtomicRepresentation.atomicStore(time.uptimeNanoseconds, at: QueueRegistry.shared.commandGPUEndTimes.advanced(by: indexInQueuesArray), ordering: .relaxed)
    }
    
    /// The time the specified command took to execute on the GPU, in seconds.
    public func gpuDuration(for commandIndex: UInt64) -> RenderDuration? {
        guard let indexInQueuesArray = self.indexInQueuesArrays(for: commandIndex) else { return nil }
        
        let startTime = UInt64.AtomicRepresentation.atomicLoad(at: QueueRegistry.shared.commandGPUStartTimes.advanced(by: indexInQueuesArray), ordering: .relaxed)
        let endTime = UInt64.AtomicRepresentation.atomicLoad(at: QueueRegistry.shared.commandGPUEndTimes.advanced(by: indexInQueuesArray), ordering: .relaxed)
        
        guard self.hasBufferedData(for: commandIndex) else { return nil } // Make sure the data we retrieved was valid
        
        return RenderDuration(nanoseconds: max(endTime, startTime) - startTime)
    }
    
    public var lastCompletedCommand : UInt64 {
        return UInt64.AtomicRepresentation.atomicLoad(at: QueueRegistry.shared.lastCompletedCommands.advanced(by: Int(self.index)), ordering: .relaxed)
    }
    
    /// The time at which the last command was submitted.
    public var lastSubmissionTime : DispatchTime {
        return self.submissionTime(for: self.lastSubmittedCommand) ?? .init(uptimeNanoseconds: 0)
    }
    
    /// The time at which the last command was completed.
    public var lastCompletionTime : DispatchTime {
        return self.completionTime(for: self.lastSubmittedCommand) ?? .now()
    }
    
    @available(*, deprecated, renamed: "waitForCommandCompletion")
    public func waitForCommand(_ index: UInt64) async {
        await self.waitForCommandCompletion(index)
    }
    
    public func waitForCommandSubmission(_ index: UInt64) async {
        while self.lastSubmittedCommand < index {
            await Task.yield()
        }
    }
    
    public func waitForCommandCompletion(_ index: UInt64) async {
        if self.lastCompletedCommand >= index { return }
        
        await self.lock.lock()
        while self.lastCompletedCommand < index {
            // First, make sure that the slot in the buffer belongs to us
            // by making sure the command has been submitted.
            guard let indexInQueuesArray = self.indexInQueuesArrays(for: index) else {
                self.lock.unlock()
                await self.waitForCommandSubmission(index)
                await self.lock.lock()
                continue
            }
            
            // Now, we're holding the lock, so add our continuation to the pending list for this command.
            await withUnsafeContinuation({ continuation in
                QueueRegistry.shared.commandWaiters[indexInQueuesArray].append(continuation)
                self.lock.unlock()
            })
            
            return // The lock was unlocked after we added the continuation.
        }
        
        self.lock.unlock()
    }
    
    public static var invalid: Queue {
        return .init(index: .max)
    }
}

public typealias QueueCommandIndices = SIMD8<UInt64>
