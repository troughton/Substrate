//
//  CachedValue.swift
//  InterdimensionalLlama
//
//  Created by Thomas Roughton on 25/02/17.
//
//

public final class CachedValue<T> {
    private let constructor : () -> T
    private var _value : T? = nil
    
    public init(constructor: @escaping () -> T) {
        self.constructor = constructor
    }
    
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
    
    public func reset() {
        _value = nil
    }
}
