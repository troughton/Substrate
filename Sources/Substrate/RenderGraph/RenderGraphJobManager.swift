//
//  RenderGraphJobManager.swift
//  Created by Thomas Roughton on 24/08/19.
//

import Foundation
import SubstrateUtilities

public protocol RenderGraphJobManager : AnyObject {
    var threadIndex : Int { get }
    var threadCount : Int { get }
    
    func dispatchPassJob(_ function: @escaping () -> Void)
    func waitForAllPassJobs()
    func syncOnMainThread<T>(_ function: () throws -> T) rethrows -> T
    func asyncOnMainThread(_ function: @escaping () -> Void)
}

final class DefaultRenderGraphJobManager : RenderGraphJobManager {
    static let queueIndexKey = DispatchSpecificKey<Int>()
    
    public let threadCount : Int
    var queues: [DispatchQueue]!
    let taskAvailableSemaphore: DispatchSemaphore
    var taskQueue = [() -> Void]()
    let taskQueueLock = SpinLock()
    let taskGroup = DispatchGroup()
    
    deinit {
        self.taskQueueLock.deinit()
    }
    
    public var threadIndex : Int {
        return DispatchQueue.getSpecific(key: Self.queueIndexKey) ?? 0
    }
    
    public func dispatchPassJob(_ function: @escaping () -> Void) {
        taskGroup.enter()
        
        self.taskQueueLock.lock()
        self.taskQueue.append {
            function()
            self.taskGroup.leave()
        }
        self.taskQueueLock.unlock()
        self.taskAvailableSemaphore.signal()
    }
    
    public func waitForAllPassJobs() {
        self.taskGroup.wait()
    }
    
    public init() {
        dispatchPrecondition(condition: .onQueue(.main))
        let processorCount = ProcessInfo.processInfo.processorCount
        
        DispatchQueue.main.setSpecific(key: Self.queueIndexKey, value: 0)
        
        self.taskAvailableSemaphore = DispatchSemaphore(value: 0)
        
        let queueCount = min(max(processorCount - 1, 1), 8)
        self.threadCount = queueCount + 1
        
        let queues = (1...max(processorCount - 1, 1)).map { i -> DispatchQueue in
            let queue = DispatchQueue(label: "RenderGraph Job Queue \(i)", qos: .userInteractive, autoreleaseFrequency: .workItem, target: nil)
            queue.setSpecific(key: Self.queueIndexKey, value: i)
            
            queue.async { [weak self] in
                while let self = self {
                    self.taskAvailableSemaphore.wait()
                    self.taskQueueLock.lock()
                    let task = self.taskQueue.removeLast()
                    self.taskQueueLock.unlock()
                    task()
                }
            }
            
            return queue
        }
        
        self.queues = queues
    }
    
    @inlinable
    public func syncOnMainThread<T>(_ function: () throws -> T) rethrows -> T {
        if !Thread.isMainThread {
            return try DispatchQueue.main.sync { try function() }
        } else {
            return try function()
        }
    }
    
    @inlinable
    public func asyncOnMainThread(_ function: @escaping () -> Void) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { function() }
        } else {
            function()
        }
    }
}
