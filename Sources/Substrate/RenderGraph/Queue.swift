//
//  Queue.swift
//  
//
//  Created by Thomas Roughton on 26/10/19.
//

import SubstrateUtilities
import CAtomics
import Dispatch

public final class QueueRegistry {
    public static let instance = QueueRegistry()
    
    public static let maxQueues = UInt8.bitWidth
    
    public let lastSubmittedCommands : UnsafeMutablePointer<AtomicUInt64>
    public let lastCompletedCommands : UnsafeMutablePointer<AtomicUInt64>
    public let lastSubmissionTimes : UnsafeMutablePointer<AtomicUInt64>
    public let lastCompletionTimes : UnsafeMutablePointer<AtomicUInt64>
    
    var allocatedQueues : UInt8 = 0
    var lock = SpinLock()
    
    public init() {
        self.lastSubmittedCommands = .allocate(capacity: Self.maxQueues)
        self.lastCompletedCommands = .allocate(capacity: Self.maxQueues)
        self.lastSubmissionTimes = .allocate(capacity: Self.maxQueues)
        self.lastCompletionTimes = .allocate(capacity: Self.maxQueues)
    }
    
    deinit {
        self.lastSubmittedCommands.deallocate()
        self.lastCompletedCommands.deallocate()
        self.lastSubmissionTimes.deallocate()
        self.lastCompletionTimes.deallocate()
    }
    
    public static var allQueues : IteratorSequence<QueueIterator> {
        return IteratorSequence(QueueIterator())
    }
    
    public func allocate() -> UInt8 {
        return self.lock.withLock {
            for i in 0..<self.allocatedQueues.bitWidth {
                if self.allocatedQueues & (1 << i) == 0 {
                    self.allocatedQueues |= (1 << i)
                    
                    CAtomicsStore(self.lastSubmittedCommands.advanced(by: i), 0, .relaxed)
                    CAtomicsStore(self.lastCompletedCommands.advanced(by: i), 0, .relaxed)
                    
                    CAtomicsStore(self.lastSubmissionTimes.advanced(by: i), 0, .relaxed)
                    CAtomicsStore(self.lastCompletionTimes.advanced(by: i), 0, .relaxed)
                    
                    return UInt8(i)
                }
            }
            
            fatalError("Only \(Self.maxQueues) queues may exist at any time.")
        }
    }
    
    public func dispose(_ queue: Queue) {
        self.lock.withLock {
            assert(self.allocatedQueues & (1 << Int(queue.index)) != 0, "Queue being disposed is not allocated.")
            self.allocatedQueues &= ~(1 << Int(queue.index))
        }
    }
    
    public struct QueueIterator : IteratorProtocol {
        var nextIndex = 0
        
        init() {
            self.nextIndex = (0..<QueueRegistry.maxQueues)
                .first(where: { QueueRegistry.instance.allocatedQueues & (1 << $0) != 0 }) ?? QueueRegistry.maxQueues
        }
        
        public mutating func next() -> Queue? {
            if self.nextIndex < QueueRegistry.maxQueues {
                let queue = Queue(index: UInt8(self.nextIndex))
                self.nextIndex = (0..<QueueRegistry.maxQueues)
                    .dropFirst(self.nextIndex + 1)
                    .first(where: { QueueRegistry.instance.allocatedQueues & (1 << $0) != 0 }) ?? QueueRegistry.maxQueues
                return queue
            }
            return nil
        }
    }
}

public struct Queue : Equatable {
    let index : UInt8
    
    fileprivate init(index: UInt8) {
        self.index = index
    }
    
    init() {
        self.index = QueueRegistry.instance.allocate()
    }
    
    func dispose() {
        QueueRegistry.instance.dispose(self)
    }
    
    public internal(set) var lastSubmittedCommand : UInt64 {
        get {
            return CAtomicsLoad(QueueRegistry.instance.lastSubmittedCommands.advanced(by: Int(self.index)), .relaxed)
        }
        nonmutating set {
            assert(self.lastSubmittedCommand < newValue)
            CAtomicsStore(QueueRegistry.instance.lastSubmittedCommands.advanced(by: Int(self.index)), newValue, .relaxed)
        }
    }
    
    /// The time at which the last command was submitted.
    public internal(set) var lastSubmissionTime : DispatchTime {
        get {
            let time = CAtomicsLoad(QueueRegistry.instance.lastSubmissionTimes.advanced(by: Int(self.index)), .relaxed)
            return DispatchTime(uptimeNanoseconds: time)
        }
        nonmutating set {
            assert(self.lastSubmissionTime < newValue)
            CAtomicsStore(QueueRegistry.instance.lastSubmissionTimes.advanced(by: Int(self.index)), newValue.uptimeNanoseconds, .relaxed)
        }
    }
    
    public internal(set) var lastCompletedCommand : UInt64 {
        get {
            return CAtomicsLoad(QueueRegistry.instance.lastCompletedCommands.advanced(by: Int(self.index)), .relaxed)
        }
        nonmutating set {
            assert(self.lastCompletedCommand < newValue)
            CAtomicsStore(QueueRegistry.instance.lastCompletedCommands.advanced(by: Int(self.index)), newValue, .relaxed)
        }
    }
    
    /// The time at which the last command was completed.
    public internal(set) var lastCompletionTime : DispatchTime {
        get {
            let time = CAtomicsLoad(QueueRegistry.instance.lastCompletionTimes.advanced(by: Int(self.index)), .relaxed)
            return DispatchTime(uptimeNanoseconds: time)
        }
        nonmutating set {
            assert(self.lastCompletionTime < newValue)
            CAtomicsStore(QueueRegistry.instance.lastCompletionTimes.advanced(by: Int(self.index)), newValue.uptimeNanoseconds, .relaxed)
        }
    }
    
    func waitForCommand(_ index: UInt64) {
        while self.lastCompletedCommand < index {
            #if os(Windows)
            _sleep(0)
            #else
            sched_yield()
            #endif
        }
    }
}

public typealias QueueCommandIndices = SIMD8<UInt64>
