//
//  Weak.swift
//  CGRAGame
//
//  Created by Thomas Roughton on 30/05/17.
//  Copyright © 2017 Team Llama. All rights reserved.
//

public struct Weak<T: AnyObject> {
    public weak var value: T?
    
    public init(_ value: T?) {
        self.value = value
    }
}

public struct UnownedReference<T : AnyObject> {
    public unowned var value: T
    
    public init(_ value: T) {
        self.value = value
    }
}

public final class Reference<T> {
    public var value: T
    
    public init(_ value: T) {
        self.value = value
    }
}


