//
//  Vector2f+nosimd.swift
//  SwiftMath
//
//  Created by Andrey Volodin on 07.10.16.
//
//

#if NOSIMD
    
import Foundation 

    public struct Vector2f {
        public var x: Float = 0.0
        public var y: Float = 0.0
        
        public init() { }
        
        public init(x: Float, y: Float) {
            self.x = x
            self.y = y
        }
        
        public init(_ scalar: Float) {
            self.init(x: scalar, y: scalar)
        }
        
        public init(_ x: Float, _ y: Float) {
            self.init(x: x, y: y)
        }
    }
    
extension Vector2f: Equatable {
    
@inlinable
    public var r: Float { get { return x } set { x = newValue } }
@inlinable
    public var g: Float { get { return y } set { y = newValue } }
    
    @inlinable
    public var s: Float { get { return x } set { x = newValue } }
    @inlinable
    public var t: Float { get { return y } set { y = newValue } }
    
    @inlinable
    public subscript(x: Int) -> Float {
        get {
            if x == 0 { return self.x }
            if x == 1 { return self.y }
            fatalError("Index outside of bounds")
        }
        
        set {
            if x == 0 { self.x = newValue; return }
            if x == 1 { self.y = newValue; return }
            fatalError("Index outside of bounds")
        }
    }
    
    @inlinable
    public var lengthSquared: Float {
        return x * x + y * y
    }
    
    @inlinable
    public var length: Float {
        return sqrtf(lengthSquared)
    }
    
    
    @inlinable
    public var normalized: Vector2f {
        let lengthSquared = self.lengthSquared
        if lengthSquared ~= 0 || lengthSquared ~= 1 {
            return self
        }
        return self / sqrtf(lengthSquared)
    }
    
    @inlinable
    public static prefix func -(v: Vector2f) -> Vector2f {
        return Vector2f(-v.x, -v.y)
    }
    
    @inlinable
    public static func +=(lhs: inout Vector2f, rhs: Vector2f) {
        lhs.x += rhs.x
        lhs.y += rhs.y
    }
    
    @inlinable
    public static func -=(lhs: inout Vector2f, rhs: Vector2f) {
        lhs.x -= rhs.x
        lhs.y -= rhs.y
    }
    
    @inlinable
    public static func *=(lhs: inout Vector2f, rhs: Vector2f) {
        lhs.x *= rhs.x
        lhs.y *= rhs.y
    }
    
    @inlinable
    public static func *=(lhs: inout Vector2f, rhs: Float) {
        lhs.x *= rhs
        lhs.y *= rhs
    }
    
    @inlinable
    public static func /=(lhs: inout Vector2f, rhs: Vector2f) {
        lhs.x /= rhs.x
        lhs.y /= rhs.y
    }
    
    @inlinable
    public static func /=(lhs: inout Vector2f, rhs: Float) {
        lhs.x /= rhs
        lhs.y /= rhs
    }
    
    @inlinable
    public static func ==(lhs: Vector2f, rhs: Vector2f) -> Bool {
        return lhs.x == rhs.x && lhs.y == rhs.y
    }
    
    @inlinable
    public static func ~=(lhs: Vector2f, rhs: Vector2f) -> Bool {
        return lhs.x ~= rhs.x && lhs.y ~= rhs.y
    }
    
    @inlinable
    public static func *(lhs: Matrix4x4f, rhs: Vector2f) -> Vector2f {
        return (lhs * Vector4f(rhs)).xy
    }
    
    @inlinable
    public static func * (lhs: Vector2f, rhs: Matrix3x3f) -> Vector2f {
        return Vector2f(
            lhs.x * rhs.m11 + lhs.y * rhs.m21 + rhs.m31,
            lhs.x * rhs.m12 + lhs.y * rhs.m22 + rhs.m32
        )
    }
    
    @inlinable
    public static func * (lhs: Matrix3x3f, rhs: Vector2f) -> Vector2f {
        return rhs * lhs
    }
    
    @inlinable
    public static func *(lhs: Vector2f, rhs: Matrix4x4f) -> Vector2f {
        return (Vector4f(lhs) * rhs).xy
    }
    
}

    @inlinable
public func interpolate(from u: Vector2f, to v: Vector2f, factor t: Float) -> Vector2f {
    return u + (v - u) * t
}

    @inlinable
public func dot(_ u: Vector2f, _ v: Vector2f) -> Float {
    return u.x * v.x + u.y * v.y
}

    @inlinable
public func cross(_ u: Vector2f, _ v: Vector2f) -> Float {
    return u.x * v.y - u.y * v.x
}

extension Vector2f {
    @inlinable
    public static func +(lhs: Vector2f, rhs: Vector2f) -> Vector2f {
        var result = lhs
        result += rhs
        return result
    }

    @inlinable
    public static func +(lhs: Vector2f, rhs: Float) -> Vector2f {
        return lhs + Vector2f(rhs)
    }
    
    @inlinable
    public static func -(lhs: Vector2f, rhs: Vector2f) -> Vector2f {
        var result = lhs
        result -= rhs
        return result
    }
    
    @inlinable
    public static func *(lhs: Vector2f, rhs: Vector2f) -> Vector2f {
        var result = lhs
        result *= rhs
        return result
    }
    
    @inlinable
    public static func *(lhs: Vector2f, rhs: Float) -> Vector2f {
        var result = lhs
        result *= rhs
        return result
    }

    @inlinable
    public static func *(lhs: Float, rhs: Vector2f) -> Vector2f {
        return rhs * lhs
    }
    
    @inlinable
    public static func /(lhs: Vector2f, rhs: Vector2f) -> Vector2f {
        var result = lhs
        result /= rhs
        return result
    }
    
    @inlinable
    public static func /(lhs: Vector2f, rhs: Float) -> Vector2f {
        var result = lhs
        result /= rhs
        return result
    }
}
#endif
