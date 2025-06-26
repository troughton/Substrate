//
//  RenderBlackboard.swift
//  Substrate
//
//  Created by Thomas Roughton on 2/04/17.
//
//

import Foundation

@globalActor
public actor RenderBlackboard {
    public static let shared = RenderBlackboard()
    
    @RenderBlackboard static var mappings = [ObjectIdentifier : any Sendable]()
    
    public init() {
        
    }
    
    @RenderBlackboard
    public static func add<T: Sendable>(_ obj: T) {
        self.mappings[ObjectIdentifier(T.self)] = obj
    }
    
    @RenderBlackboard
    public static func remove<T: Sendable>(_ obj: T) {
        self.mappings[ObjectIdentifier(T.self)] = nil
    }
    
    @RenderBlackboard
    public static func remove<T: Sendable>(type: T.Type) {
        self.mappings[ObjectIdentifier(type)] = nil
    }
    
    @RenderBlackboard
    public static func get<T: Sendable>(_ type: T.Type) -> T {
        guard let item = self.mappings[ObjectIdentifier(type)] else {
            fatalError("No item in blackboard of type \(type).")
        }
        return item as! T
    }
    
    @RenderBlackboard
    public static func tryGet<T: Sendable>(_ type: T.Type) -> T? {
        return self.mappings[ObjectIdentifier(type)] as! T?
    }
    
    @RenderBlackboard
    public static func has<T: Sendable>(_ type: T.Type) -> Bool {
        return self.mappings[ObjectIdentifier(type)] != nil
    }
    
    @RenderBlackboard
    public static func clear() {
        self.mappings.removeAll(keepingCapacity: true)
    }
}

