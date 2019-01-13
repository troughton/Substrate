//
//  Vector3f+nosimd.swift
//  SwiftMath
//
//  Created by Andrey Volodin on 07.10.16.
//
//

#if NOSIMD
    
import Foundation
    
public struct Vector3f {
    public var x: Float = 0.0
    public var y: Float = 0.0
    public var z: Float = 0.0
    private let w : Float = 0.0
    
    public init() {}
    
    @inlinable
    public init(_ x: Float, _ y: Float, _ z: Float) {
        self.init()
        self.x = x
        self.y = y
        self.z = z
    }
    
    @inlinable
    public init(_ scalar: Float) {
        self.init(scalar, scalar, scalar)
    }
    
    @inlinable
    public init(x: Float, y: Float, z: Float) {
        self.init(x, y, z)
    }
}
    
extension Vector3f {
    @inlinable
    public var r: Float { get { return x } set { x = newValue } }
    @inlinable
    public var g: Float { get { return y } set { y = newValue } }
    @inlinable
    public var b: Float { get { return z } set { z = newValue } }
    
    @inlinable
    public var s: Float { get { return x } set { x = newValue } }
    @inlinable
    public var t: Float { get { return y } set { y = newValue } }
    @inlinable
    public var p: Float { get { return z } set { z = newValue } }
    
    public subscript(x: Int) -> Float {
        get {
            if x == 0 { return self.x }
            if x == 1 { return self.y }
            if x == 2 { return self.z }
            fatalError("Index outside of bounds")
        }
        
        set {
            if x == 0 { self.x = newValue; return }
            if x == 1 { self.y = newValue; return }
            if x == 2 { self.z = newValue; return }
            fatalError("Index outside of bounds")
        }
    }

}

extension Vector3f: Equatable {

    @inlinable
    public var lengthSquared: Float {
        return x * x + y * y + z * z
    }
    
    @inlinable
    public var length: Float {
        return sqrtf(lengthSquared)
    }
    
    @inlinable
    public var normalized: Vector3f {
        let lengthSquared = self.lengthSquared
        if lengthSquared ~= 0 || lengthSquared ~= 1 {
            return self
        }
        return self / sqrtf(lengthSquared)
    }
    
    @inlinable
    public var componentSum : Float {
        return self.x + self.y + self.z
    }
    
    @inlinable
    public static prefix func -(v: Vector3f) -> Vector3f {
        return Vector3f(-v.x, -v.y, -v.z)
    }
    
    @inlinable
    public static func +=(lhs: inout Vector3f, rhs: Vector3f) {
        lhs.x += rhs.x
        lhs.y += rhs.y
        lhs.z += rhs.z
    }
    
    @inlinable
    public static func -=(lhs: inout Vector3f, rhs: Vector3f) {
        lhs.x -= rhs.x
        lhs.y -= rhs.y
        lhs.z -= rhs.z
    }
    
    @inlinable
    public static func *=(lhs: inout Vector3f, rhs: Vector3f) {
        lhs.x *= rhs.x
        lhs.y *= rhs.y
        lhs.z *= rhs.z
    }
    
    @inlinable
    public static func *=(lhs: inout Vector3f, rhs: Float) {
        lhs.x *= rhs
        lhs.y *= rhs
        lhs.z *= rhs
    }
    
    @inlinable
    public static func /=(lhs: inout Vector3f, rhs: Vector3f) {
        lhs.x /= rhs.x
        lhs.y /= rhs.y
        lhs.z /= rhs.z
    }
    
    @inlinable
    public static func /=(lhs: inout Vector3f, rhs: Float) {
        lhs.x /= rhs
        lhs.y /= rhs
        lhs.z /= rhs
    }
    
    @inlinable
    public static func +(lhs: Vector3f, rhs: Float) -> Vector3f {
        return lhs + Vector3f(rhs)
    }
    
    @inlinable
    public static func +(lhs: Float, rhs: Vector3f) -> Vector3f {
        return Vector3f(lhs) + rhs
    }
    
    @inlinable
    public static func *(lhs: Vector3f, rhs: Float) -> Vector3f {
        return lhs * Vector3f(rhs)
    }
    
    @inlinable
    public static func *(lhs: Float, rhs: Vector3f) -> Vector3f {
        return Vector3f(lhs) * rhs
    }
    
    @inlinable
    public static func *(lhs: Int, rhs: Vector3f) -> Vector3f {
        return Vector3f(Float(lhs)) * rhs
    }
    
    @inlinable
    public static func ==(lhs: Vector3f, rhs: Vector3f) -> Bool {
        return lhs.x == rhs.x && lhs.y == rhs.y && lhs.z == rhs.z
    }
    
    @inlinable
    public static func ~=(lhs: Vector3f, rhs: Vector3f) -> Bool {
        return lhs.x ~= rhs.x && lhs.y ~= rhs.y && lhs.z ~= rhs.z
    }
    
    @inlinable
    public static func *(lhs: Vector3f, rhs: Matrix3x3f) -> Vector3f {
        return Vector3f(
            lhs.x * rhs.m11 + lhs.y * rhs.m21 + lhs.z * rhs.m31,
            lhs.x * rhs.m12 + lhs.y * rhs.m22 + lhs.z * rhs.m32,
            lhs.x * rhs.m13 + lhs.y * rhs.m23 + lhs.z * rhs.m33
        )
    }
    
    @inlinable
    public static func *(lhs: Matrix3x3f, rhs: Vector3f) -> Vector3f {
        return rhs * lhs
    }
}
    
    @inlinable
    public func dot(_ u: Vector3f, _ v: Vector3f) -> Float {
        return u.x * v.x + u.y * v.y + u.z * v.z
    }
    
    @inlinable
    public func cross(_ u: Vector3f, _ v: Vector3f) -> Vector3f {
        return Vector3f(u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x)
    }
    
    @inlinable
    public func interpolate(from u: Vector3f, to v: Vector3f, factor t: Float) -> Vector3f {
        return u + (v - u) * t
    }

extension Vector3f {
    @inlinable
    public static func +(lhs: Vector3f, rhs: Vector3f) -> Vector3f {
        var result = lhs
        result += rhs
        return result
    }
    
    @inlinable
    public static func -(lhs: Vector3f, rhs: Vector3f) -> Vector3f {
        var result = lhs
        result -= rhs
        return result
    }
    
    @inlinable
    public static func *(lhs: Vector3f, rhs: Vector3f) -> Vector3f {
        var result = lhs
        result *= rhs
        return result
    }
    
    @inlinable
    public static func /(lhs: Vector3f, rhs: Vector3f) -> Vector3f {
        var result = lhs
        result /= rhs
        return result
    }
    
    @inlinable
    public static func /(lhs: Vector3f, rhs: Float) -> Vector3f {
        var result = lhs
        result /= rhs
        return result
    }
}
    
#endif
