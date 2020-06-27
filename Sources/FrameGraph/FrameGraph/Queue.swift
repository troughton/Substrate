//
//  Queue.swift
//  
//
//  Created by Thomas Roughton on 26/10/19.
//

import FrameGraphUtilities
import CAtomics

public struct QueueCapabilities : OptionSet {
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    public static let render = QueueCapabilities(rawValue: 1 << 0)
    public static let compute = QueueCapabilities(rawValue: 1 << 1)
    public static let blit = QueueCapabilities(rawValue: 1 << 2)
    public static let present = QueueCapabilities(rawValue: 1 << 3)
    
    public static var all : QueueCapabilities = [.render, .compute, .blit, .present]
}

public final class QueueRegistry {
    public static let instance = QueueRegistry()
    
    public static let maxQueues = UInt8.bitWidth
    
    public let queueCapabilities : UnsafeMutablePointer<QueueCapabilities>
    public let lastSubmittedCommands : UnsafeMutablePointer<AtomicUInt64>
    public let lastCompletedCommands : UnsafeMutablePointer<AtomicUInt64>
    
    var allocatedQueues : UInt8 = 0
    var lock = SpinLock()
    
    public init() {
        self.queueCapabilities = .allocate(capacity: Self.maxQueues)
        self.lastSubmittedCommands = .allocate(capacity: Self.maxQueues)
        self.lastCompletedCommands = .allocate(capacity: Self.maxQueues)
    }
    
    deinit {
        self.lastSubmittedCommands.deallocate()
        self.lastCompletedCommands.deallocate()
    }
    
    public static var allQueues : IteratorSequence<QueueIterator> {
        return IteratorSequence(QueueIterator())
    }
    
    public func allocate(capabilities: QueueCapabilities) -> UInt8 {
        return self.lock.withLock {
            for i in 0..<self.allocatedQueues.bitWidth {
                if self.allocatedQueues & (1 << i) == 0 {
                    self.allocatedQueues |= (1 << i)
                    
                    CAtomicsStore(self.lastSubmittedCommands.advanced(by: i), 0, .relaxed)
                    CAtomicsStore(self.lastCompletedCommands.advanced(by: i), 0, .relaxed)
                    
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
    
    init(capabilities: QueueCapabilities) {
        self.index = QueueRegistry.instance.allocate(capabilities: capabilities)
    }
    
    func dispose() {
        QueueRegistry.instance.dispose(self)
    }
    
    public var capabilities: QueueCapabilities {
        return QueueRegistry.instance.queueCapabilities[Int(self.index)]
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
    
    public internal(set) var lastCompletedCommand : UInt64 {
        get {
            return CAtomicsLoad(QueueRegistry.instance.lastCompletedCommands.advanced(by: Int(self.index)), .relaxed)
        }
        nonmutating set {
            assert(self.lastSubmittedCommand >= newValue)
            assert(self.lastCompletedCommand < newValue)
            CAtomicsStore(QueueRegistry.instance.lastCompletedCommands.advanced(by: Int(self.index)), newValue, .relaxed)
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
