//
//  CachedValue.swift
//  Substrate
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


public final class CachedAsync<T> {
    public var constructor : (() async -> T)! = nil
    @usableFromInline var _value : T? = nil
    
    @inlinable
    public init() {
    }
    
    @inlinable
    public func getValue() async -> T {
        if let value = _value {
            return value
        } else {
            let result = await constructor()
            _value = result
            return result
        }
    }
    
    @inlinable
    public func reset() {
        _value = nil
    }
}
