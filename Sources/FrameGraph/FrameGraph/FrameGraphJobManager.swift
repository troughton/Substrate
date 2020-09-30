//
//  FrameGraphJobManager.swift
//  Created by Thomas Roughton on 24/08/19.
//

import Foundation

public protocol FrameGraphJobManager : class {
    var threadIndex : Int { get }
    var threadCount : Int { get }
    
    func dispatchPassJob(_ function: @escaping () -> Void)
    func waitForAllPassJobs()
    func syncOnMainThread<T>(_ function: () throws -> T) rethrows -> T
    func asyncOnMainThread(_ function: @escaping () -> Void)
}

final class DefaultFrameGraphJobManager : FrameGraphJobManager {
    public var threadIndex : Int {
        return 0
    }
    
    public var threadCount : Int {
        return 1
    }
    
    public func dispatchPassJob(_ function: @escaping () -> Void) {
        function()
    }
    
    public func waitForAllPassJobs() {
        
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
