//
//  RenderBlackboard.swift
//  Substrate
//
//  Created by Thomas Roughton on 2/04/17.
//
//

import Foundation

public actor RenderBlackboard {
    static let blackboard = RenderBlackboard()
    private var mappings = [ObjectIdentifier : any Sendable]()
    
    public init() {
        
    }
    
    public func add<T: Sendable>(_ obj: T) {
        self.mappings[ObjectIdentifier(T.self)] = obj
    }
    
    public func remove<T: Sendable>(_ obj: T) {
        self.mappings[ObjectIdentifier(T.self)] = nil
    }
    
    public func remove<T: Sendable>(type: T.Type) {
        self.mappings[ObjectIdentifier(type)] = nil
    }
    
    public func get<T: Sendable>(_ type: T.Type) -> T {
        guard let item = self.mappings[ObjectIdentifier(type)] else {
            fatalError("No item in blackboard of type \(type).")
        }
        return item as! T
    }
    
    public func tryGet<T: Sendable>(_ type: T.Type) -> T? {
        return self.mappings[ObjectIdentifier(type)] as! T?
    }
    
    public func has<T: Sendable>(_ type: T.Type) -> Bool {
        return self.mappings[ObjectIdentifier(type)] != nil
    }
    
    public func clear() {
        self.mappings.removeAll(keepingCapacity: true)
    }
}

