//
//  Bool4.swift
//  SwiftMath
//
//  Created by Thomas Roughton on 6/05/18.
//

// Use floats internally to keep results in vector registers.

@_fixed_layout
public struct bool4 {
    public var x : Float
    public var y : Float
    public var z : Float
    public var w : Float
    
    @inlinable
    public init() {
        self.x = 0.0
        self.y = 0.0
        self.z = 0.0
        self.w = 0.0
    }
    
    @inlinable
    public init(x: Bool, y: Bool, z: Bool, w: Bool) {
        self.x = x ? 1.0 : 0.0
        self.y = y ? 1.0 : 0.0
        self.z = z ? 1.0 : 0.0
        self.w = w ? 1.0 : 0.0
    }
    
    @inlinable
    public init(_ x: Bool, _ y: Bool, _ z: Bool, _ w: Bool) {
        self.x = x ? 1.0 : 0.0
        self.y = y ? 1.0 : 0.0
        self.z = z ? 1.0 : 0.0
        self.w = w ? 1.0 : 0.0
    }
    
    @inlinable
    public init(_ val: Bool) {
        let value : Float = val ? 1.0 : 0.0
        self.x = value
        self.y = value
        self.z = value
        self.w = value
    }
}

extension bool4 : ExpressibleByBooleanLiteral {
    @inlinable
    public init(booleanLiteral value: Bool) {
        self.init(value)
    }
}

infix operator ||=

@inlinable
public func ||=(lhs: inout bool4, rhs: bool4) {
    lhs.x += rhs.x
    lhs.y += rhs.y
    lhs.z += rhs.z
    lhs.w += rhs.w
}

infix operator &&=

@inlinable
public func &&=(lhs: inout bool4, rhs: bool4) {
    lhs.x = lhs.x * rhs.x
    lhs.y = lhs.y * rhs.y
    lhs.z = lhs.z * rhs.z
    lhs.w = lhs.w * rhs.w
}


@inlinable
public func ||(lhs: bool4, rhs: bool4) -> bool4 {
    var result = lhs
    result ||= rhs
    return result
}

@inlinable
public func &&(lhs: bool4, rhs: bool4) -> bool4 {
    var result = lhs
    result &&= rhs
    return result
}

@inlinable
public prefix func !(val: bool4) -> bool4 {
    return bool4(val.x == 0.0, val.y == 0.0, val.z == 0.0, val.w == 0.0)
}

@inlinable
public func any(_ val: bool4) -> Bool {
    return val.x + val.y + val.z + val.w != 0.0
}

@inlinable
public func all(_ val: bool4) -> Bool {
    return (val.x * val.y * val.z * val.w) != 0.0
}

@inlinable
public func <(lhs: Vector4f, rhs: Vector4f) -> bool4 {
    return bool4(lhs.x < rhs.x, lhs.y < rhs.y, lhs.z < rhs.z, lhs.w < rhs.w)
}

@inlinable
public func <=(lhs: Vector4f, rhs: Vector4f) -> bool4 {
    return bool4(lhs.x <= rhs.x, lhs.y <= rhs.y, lhs.z <= rhs.z, lhs.w <= rhs.w)
}

@inlinable
public func >(lhs: Vector4f, rhs: Vector4f) -> bool4 {
    return !(lhs <= rhs)
}

@inlinable
public func >=(lhs: Vector4f, rhs: Vector4f) -> bool4 {
    return !(lhs < rhs)
}

