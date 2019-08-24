//
//  CachedValue.swift
//  SwiftFrameGraph
//
//  Created by Thomas Roughton on 25/02/17.
//
//

public final class CachedValue<T> {
    @usableFromInline let constructor : () -> T
    @usableFromInline var _value : T? = nil
    
    @inlinable
    public init(constructor: @escaping () -> T) {
        self.constructor = constructor
    }
    
    @inlinable
    public var value : T {
        get {
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
    public func reset() {
        _value = nil
    }
}
