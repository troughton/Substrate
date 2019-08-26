//
//  CachedValue.swift
//  SwiftFrameGraph
//
//  Created by Thomas Roughton on 25/02/17.
//
//

@propertyWrapper
public struct Cached<T> {
    public var constructor : (() -> T)! = nil
    @usableFromInline var _value : T? = nil
    
    @inlinable
    public init() {
    }
    
    @inlinable
    public var wrappedValue : T {
        mutating get {
            if let value = _value {
                return value
            } else {
                let result = constructor()
                _value = result
                return result
            }
        }
        set {
            _value = newValue
        }
    }
    
    @inlinable
    public mutating func reset() {
        _value = nil
    }
}
