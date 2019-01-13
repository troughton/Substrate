//
//  Vector4f+nosimd.swift
//  SwiftMath
//
//  Created by Andrey Volodin on 07.10.16.
//
//
#if NOSIMD
    
import Foundation
    
public struct Vector4f {
    public var x: Float = 0.0
    public var y: Float = 0.0
    public var z: Float = 0.0
    public var w: Float = 0.0

    public init() {}

    @inlinable
    public init(x: Float, y: Float, z: Float, w: Float) {
        self.init()
        
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }
}
    
extension Vector4f {
    //MARK: - initializers
    
    @inlinable
    public init(_ scalar: Float) {
        self.init()
        self.x = scalar
        self.y = scalar
        self.z = scalar
        self.w = scalar
    }
    
    @inlinable
    public init(_ x: Float, _ y: Float, _ z: Float, _ w: Float) {
        self.init()
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }
        
    @inlinable
    public init(_ v: Vector2f) {
        self.init(v.x, v.y, 0.0, 1.0)
    }
    
    @inlinable
    public init(_ v: Vector3f) {
        self.init(v.x, v.y, v.z, 1.0)
    }
    
    @inlinable
    public init(x: Int, y: Int, z: Int, w: Int) {
        self.init(x: Float(x), y: Float(y), z: Float(z), w: Float(w))
    }
    
    @inlinable
    public init(_ x: Int, _ y: Int, _ z: Int, _ w: Int) {
        self.init(x: Float(x), y: Float(y), z: Float(z), w: Float(w))
    }
    
    @inlinable
    public init(_ xyz: Vector3f, _ w: Float) {
        self = Vector4f(xyz.x, xyz.y, xyz.z, w)
    }
    
    @inlinable
    public init(_ xy: Vector2f, _ zw: Vector2f) {
        self = Vector4f(xy.x, xy.y, zw.x, zw.y)
    }
    
    @inlinable
    public var r: Float { get { return x } set { x = newValue } }
    @inlinable
    public var g: Float { get { return y } set { y = newValue } }
    @inlinable
    public var b: Float { get { return z } set { z = newValue } }
    @inlinable
    public var a: Float { get { return w } set { w = newValue } }
    
    @inlinable
    public var s: Float { get { return x } set { x = newValue } }
    @inlinable
    public var t: Float { get { return y } set { y = newValue } }
    @inlinable
    public var p: Float { get { return z } set { z = newValue } }
    @inlinable
    public var q: Float { get { return w } set { w = newValue } }
    

    @inlinable
    public subscript(x: Int) -> Float {
        get {
            if x == 0 { return self.x }
            if x == 1 { return self.y }
            if x == 2 { return self.z }
            if x == 3 { return self.w }
            fatalError("Index outside of bounds")
        }
        
        set {
            if x == 0 { self.x = newValue; return }
            if x == 1 { self.y = newValue; return }
            if x == 2 { self.z = newValue; return }
            if x == 3 { self.w = newValue; return }
            fatalError("Index outside of bounds")
        }
    }

}

extension Vector4f: Equatable {

    @inlinable
    public var lengthSquared: Float {
        return x * x + y * y + z * z + w * w
    }

    @inlinable
    public var length: Float {
        return sqrtf(lengthSquared)
    }


    @inlinable
    public var normalized: Vector4f {
        let lengthSquared = self.lengthSquared
        if lengthSquared ~= 0 || lengthSquared ~= 1 {
            return self
        }
        return self / sqrtf(lengthSquared)
    }

    @inlinable
    public static prefix func -(v: Vector4f) -> Vector4f {
        return Vector4f(-v.x, -v.y, -v.z, -v.w)
    }

    @inlinable
    public static func +=(lhs: inout Vector4f, rhs: Vector4f) {
        lhs.x += rhs.x
        lhs.y += rhs.y
        lhs.z += rhs.z
        lhs.w += rhs.w
    }

    @inlinable
    public static func -=(lhs: inout Vector4f, rhs: Vector4f) {
        lhs.x -= rhs.x
        lhs.y -= rhs.y
        lhs.z -= rhs.z
        lhs.w -= rhs.w
    }

    @inlinable
    public static func *=(lhs: inout Vector4f, rhs: Vector4f) {
        lhs.x *= rhs.x
        lhs.y *= rhs.y
        lhs.z *= rhs.z
        lhs.w *= rhs.w
    }

    @inlinable
    public static func *=(lhs: inout Vector4f, rhs: Float) {
        lhs.x *= rhs
        lhs.y *= rhs
        lhs.z *= rhs
        lhs.w *= rhs
    }

    @inlinable
    public static func /=(lhs: inout Vector4f, rhs: Vector4f) {
        lhs.x /= rhs.x
        lhs.y /= rhs.y
        lhs.z /= rhs.z
        lhs.w /= rhs.w
    }

    @inlinable
    public static func /=(lhs: inout Vector4f, rhs: Float) {
        lhs.x /= rhs
        lhs.y /= rhs
        lhs.z /= rhs
        lhs.w /= rhs
    }

    @inlinable
    public static func *(lhs: Vector4f, rhs: Matrix4x4f) -> Vector4f {
        return Vector4f(
            lhs.x * rhs.m11 + lhs.y * rhs.m21 + lhs.z * rhs.m31 + lhs.w * rhs.m41,
            lhs.x * rhs.m12 + lhs.y * rhs.m22 + lhs.z * rhs.m32 + lhs.w * rhs.m42,
            lhs.x * rhs.m13 + lhs.y * rhs.m23 + lhs.z * rhs.m33 + lhs.w * rhs.m43,
            lhs.x * rhs.m14 + lhs.y * rhs.m24 + lhs.z * rhs.m34 + lhs.w * rhs.m44
        )
    }

    @inlinable
    public static func *(lhs: Matrix4x4f, rhs: Vector4f) -> Vector4f {
        return rhs * lhs
    }

    @inlinable
    public static func ==(lhs: Vector4f, rhs: Vector4f) -> Bool {
        return lhs.x == rhs.x && lhs.y == rhs.y && lhs.z == rhs.z && lhs.w == rhs.w
    }

    @inlinable
    public static func ~=(lhs: Vector4f, rhs: Vector4f) -> Bool {
        return lhs.x ~= rhs.x && lhs.y ~= rhs.y && lhs.z ~= rhs.z && lhs.w ~= rhs.w
    }
}

@inlinable
public func interpolate(from u: Vector4f, to v: Vector4f, factor t: Float) -> Vector4f {
    return u + (v - u) * t
}

@inlinable
public func dot(_ u: Vector4f, _ v: Vector4f) -> Float {
    return u.x * v.x + u.y * v.y + u.z * v.z + u.w * v.w
}

extension Vector4f {
    @inlinable
    public static func +(lhs: Vector4f, rhs: Vector4f) -> Vector4f {
        var result = lhs
        result += rhs
        return result
    }
    
    @inlinable
    public static func -(lhs: Vector4f, rhs: Vector4f) -> Vector4f {
        var result = lhs
        result -= rhs
        return result
    }
    
    @inlinable
    public static func *(lhs: Vector4f, rhs: Vector4f) -> Vector4f {
        var result = lhs
        result *= rhs
        return result
    }
    
    @inlinable
    public static func *(lhs: Vector4f, rhs: Float) -> Vector4f {
        var result = lhs
        result *= rhs
        return result
    }
    
    @inlinable
    public static func *(lhs: Float, rhs: Vector4f) -> Vector4f {
        return rhs * lhs
    }
    
    @inlinable
    public static func /(lhs: Vector4f, rhs: Vector4f) -> Vector4f {
        var result = lhs
        result /= rhs
        return result
    }
    
    @inlinable
    public static func /(lhs: Vector4f, rhs: Float) -> Vector4f {       
        var result = lhs
        result /= rhs
        return result
    }
}

#endif
