//
//  RenderBlackboard.swift
//  Substrate
//
//  Created by Thomas Roughton on 2/04/17.
//
//

import Foundation

public final class RenderBlackboard {
    
    private static var mappings = [ObjectIdentifier : Any]()
    
    public init() {
        
    }
    
    public static func add<T>(_ obj: T) {
        self.mappings[ObjectIdentifier(T.self)] = obj
    }
    
    public static func remove<T>(_ obj: T) {
        self.mappings[ObjectIdentifier(T.self)] = nil
    }
    
    public static func remove<T>(type: T.Type) {
        self.mappings[ObjectIdentifier(type)] = nil
    }
    
    public static func get<T>(_ type: T.Type) -> T {
        guard let item = self.mappings[ObjectIdentifier(type)] else {
            fatalError("No item in blackboard of type \(type).")
        }
        return item as! T
    }
    
    public static func tryGet<T>(_ type: T.Type) -> T? {
        return self.mappings[ObjectIdentifier(type)] as! T?
    }
    
    public static func has<T>(_ type: T.Type) -> Bool {
        return self.mappings[ObjectIdentifier(type)] != nil
    }
    
    public static func clear() {
        self.mappings.removeAll(keepingCapacity: true)
    }
}

