//
//  FrameGraphJobManager.swift
//  Created by Thomas Roughton on 24/08/19.
//

import Foundation

public protocol FrameGraphJobManager : class {
    var threadIndex : Int { get }
    var threadCount : Int { get }
    
    func dispatchSyncFrameGraph(_ function: @escaping () -> Void)
    
    func dispatchPassJob(_ function: @escaping () -> Void)
    func waitForAllPassJobs()
    func syncOnMainThread(_ function: @escaping () -> Void)
}

final class DefaultFrameGraphJobManager : FrameGraphJobManager {
    public var threadIndex : Int {
        return 0
    }
    
    public var threadCount : Int {
        return 1
    }
    
    public func dispatchSyncFrameGraph(_ function: @escaping () -> Void) {
        function()
    }
    
    public func dispatchPassJob(_ function: @escaping () -> Void) {
        function()
    }
    
    public func waitForAllPassJobs() {
        
    }
    
    public func syncOnMainThread(_ function: @escaping () -> Void) {
        return function()
    }
}
