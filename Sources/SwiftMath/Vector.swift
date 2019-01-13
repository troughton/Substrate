//
//  Vector.swift
//  SwiftMath
//
//  Created by Thomas Roughton on 11/01/17.
//
//

#if !NOSIMD

@_exported import simd

#endif

import Swift

public protocol Vector : Equatable {
    static var zero : Self { get }
    
    var isZero: Bool { get }
    
    init(_ value: Float)
    
    var lengthSquared : Float { get }
    
    var length : Float { get }
    
    var normalized : Self { get }
    
    subscript(x: Int) -> Float { get set }
    
    static prefix func -(v: Self) -> Self
    
    static func +=(lhs: inout Self, rhs: Self)
    static func -=(lhs: inout Self, rhs: Self)
    static func *=(lhs: inout Self, rhs: Self)
    static func /=(lhs: inout Self, rhs: Self)
    
    static func *=(lhs: inout Self, rhs: Float)
    static func /=(lhs: inout Self, rhs: Float)
    
    static func +(lhs: Self, rhs: Self) -> Self
    static func -(lhs: Self, rhs: Self) -> Self
    static func *(lhs: Self, rhs: Self) -> Self
    static func *(lhs: Self, rhs: Float) -> Self
    static func *(lhs: Float, rhs: Self) -> Self
    static func /(lhs: Self, rhs: Self) -> Self
    static func /(lhs: Self, rhs: Float) -> Self

}
