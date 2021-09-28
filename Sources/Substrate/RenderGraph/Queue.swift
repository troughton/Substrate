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

final class CommandWaitTask {
    var command: UInt64
    var task: Task<Void, Never>
    var next: CommandWaitTask?
    
    init(command: UInt64, task: Task<Void, Never>) {
        self.command = command
        self.task = task
    }
}

public final class QueueRegistry {
    public static let shared = QueueRegistry()
    
    public static let maxQueues = UInt8.bitWidth
    
    public let lastSubmittedCommands : UnsafeMutablePointer<UInt64.AtomicRepresentation>
    public let lastCompletedCommands : UnsafeMutablePointer<UInt64.AtomicRepresentation>
    public let lastSubmissionTimes : UnsafeMutablePointer<UInt64.AtomicRepresentation>
    public let lastCompletionTimes : UnsafeMutablePointer<UInt64.AtomicRepresentation>
    let commandWaitTasks : UnsafeMutablePointer<CommandWaitTask?>
    
    var allocatedQueues : UInt8 = 0
    var lock = SpinLock()
    
    public init() {
        self.lastSubmittedCommands = .allocate(capacity: Self.maxQueues)
        self.lastSubmittedCommands.initialize(repeating: .init(0), count: Self.maxQueues)
        self.lastCompletedCommands = .allocate(capacity: Self.maxQueues)
        self.lastCompletedCommands.initialize(repeating: .init(0), count: Self.maxQueues)
        self.lastSubmissionTimes = .allocate(capacity: Self.maxQueues)
        self.lastCompletionTimes = .allocate(capacity: Self.maxQueues)
        self.commandWaitTasks = .allocate(capacity: Self.maxQueues)
    }
    
    deinit {
        self.lastSubmittedCommands.deallocate()
        self.lastCompletedCommands.deallocate()
        self.lastSubmissionTimes.deallocate()
        self.lastCompletionTimes.deallocate()
        self.commandWaitTasks.deallocate()
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
                    
                    UInt64.AtomicRepresentation.atomicStore(0, at: self.lastSubmissionTimes.advanced(by: i), ordering: .relaxed)
                    UInt64.AtomicRepresentation.atomicStore(0, at: self.lastCompletionTimes.advanced(by: i), ordering: .relaxed)
                    self.commandWaitTasks.advanced(by: i).initialize(to: nil)
                    
                    return UInt8(i)
                }
            }
            
            fatalError("Only \(Self.maxQueues) queues may exist at any time.")
        }
    }
    
    public func dispose(_ queue: Queue) {
        Self.shared.lock.withLock {
            assert(self.allocatedQueues & (1 << Int(queue.index)) != 0, "Queue being disposed is not allocated.")
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
            commands[i] = UInt64.AtomicRepresentation.atomicLoad(at: self.shared.lastSubmittedCommands, ordering: .relaxed)
        }
        return commands
    }
    
    public static var lastCompletedCommands: QueueCommandIndices {
        var commands = QueueCommandIndices(repeating: 0)
        for i in 0..<Self.maxQueues {
            commands[i] = UInt64.AtomicRepresentation.atomicLoad(at: self.shared.lastCompletedCommands, ordering: .relaxed)
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
    
    func submitCommand(commandIndex: UInt64, completionTask: Task<Void, Never>) {
        UInt64.AtomicRepresentation.atomicStore(commandIndex, at: QueueRegistry.shared.lastSubmittedCommands.advanced(by: Int(self.index)), ordering: .relaxed)
        UInt64.AtomicRepresentation.atomicStore(DispatchTime.now().uptimeNanoseconds, at: QueueRegistry.shared.lastSubmissionTimes.advanced(by: Int(self.index)), ordering: .relaxed)
        
        QueueRegistry.shared.lock.withLock {
            var commandWaitTask = QueueRegistry.shared.commandWaitTasks[Int(self.index)]
            while let next = commandWaitTask?.next {
                commandWaitTask = next
            }
            
            let newTask = CommandWaitTask(command: commandIndex, task: completionTask)
            if let commandWaitTask = commandWaitTask {
                commandWaitTask.next = newTask
            } else {
                QueueRegistry.shared.commandWaitTasks[Int(self.index)] = newTask
            }
        }
    }
    
    func didCompleteCommand(_ commandIndex: UInt64) async {
        UInt64.AtomicRepresentation.atomicStore(commandIndex, at: QueueRegistry.shared.lastCompletedCommands.advanced(by: Int(self.index)), ordering: .relaxed)
        UInt64.AtomicRepresentation.atomicStore(DispatchTime.now().uptimeNanoseconds, at: QueueRegistry.shared.lastCompletionTimes.advanced(by: Int(self.index)), ordering: .relaxed)
        
        repeat {
            guard let nextTask = QueueRegistry.shared.lock.withLock({ QueueRegistry.shared.commandWaitTasks[Int(self.index)] }) else {
                // We got to didCompleteCommand before we managed to call submitCommand.
                // Give ourselves a change to call submitCommand.
                await Task.yield()
                continue
            }
            if nextTask.command < commandIndex {
                await nextTask.task.get()
                continue
            }
            QueueRegistry.shared.lock.withLock {
                QueueRegistry.shared.commandWaitTasks[Int(self.index)] = nextTask.next
            }
            break
        } while true
    }
    
    public var lastSubmittedCommand : UInt64 {
        get {
            return UInt64.AtomicRepresentation.atomicLoad(at: QueueRegistry.shared.lastSubmittedCommands.advanced(by: Int(self.index)), ordering: .relaxed)
        }
    }
    
    /// The time at which the last command was submitted.
    public var lastSubmissionTime : DispatchTime {
        let time = UInt64.AtomicRepresentation.atomicLoad(at: QueueRegistry.shared.lastSubmissionTimes.advanced(by: Int(self.index)), ordering: .relaxed)
        return DispatchTime(uptimeNanoseconds: time)
    }
    
    public var lastCompletedCommand : UInt64 {
        return UInt64.AtomicRepresentation.atomicLoad(at: QueueRegistry.shared.lastCompletedCommands.advanced(by: Int(self.index)), ordering: .relaxed)
    }
    
    /// The time at which the last command was completed.
    public internal(set) var lastCompletionTime : DispatchTime {
        get {
            let time = UInt64.AtomicRepresentation.atomicLoad(at: QueueRegistry.shared.lastCompletionTimes.advanced(by: Int(self.index)), ordering: .relaxed)
            return DispatchTime(uptimeNanoseconds: time)
        }
        nonmutating set {
            assert(self.lastCompletionTime < newValue)
            UInt64.AtomicRepresentation.atomicStore(newValue.uptimeNanoseconds, at: QueueRegistry.shared.lastCompletionTimes.advanced(by: Int(self.index)), ordering: .relaxed)
        }
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
        while self.lastCompletedCommand < index {
            if let commandWaitTask = QueueRegistry.shared.lock.withLock({ QueueRegistry.shared.commandWaitTasks[Int(self.index)] })?.task {
                await commandWaitTask.get()
            } else {
                await Task.yield()
            }
        }
    }
}

public typealias QueueCommandIndices = SIMD8<UInt64>
