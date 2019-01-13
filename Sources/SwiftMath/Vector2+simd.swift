// Copyright 2016 Stuart Carnie.
// License: https://github.com/SwiftGFX/SwiftMath#license-bsd-2-clause
//

#if !NOSIMD

import simd

@_fixed_layout
public struct Vector2f {
    public var d: float2 = float2()
    
    @inlinable
    public var x: Float { get { return d.x } set { d.x = newValue } }
    @inlinable
    public var y: Float { get { return d.y } set { d.y = newValue } }
    
    @inlinable
    public var r: Float { get { return d.x } set { d.x = newValue } }
    @inlinable
    public var g: Float { get { return d.y } set { d.y = newValue } }
    
    @inlinable
    public var s: Float { get { return d.x } set { d.x = newValue } }
    @inlinable
    public var t: Float { get { return d.y } set { d.y = newValue } }
    
    @inlinable
    public subscript(x: Int) -> Float {
        get {
            return d[x]
        }
        
        set {
            d[x] = newValue
        }
    }
    
    //MARK: - initializers
    
    @inlinable
    public init() {
    }
    
    @inlinable
    public init(x: Float, y: Float) {
        self.init()
        self.d = float2(x, y)
    }
    
    @inlinable
    public init(_ scalar: Float) {
        self.init()
        self.d = float2(scalar)
    }
    
    @inlinable
    public init(_ x: Float, _ y: Float) {
        self.init()
        self.d = float2(x, y)
    }
}

extension Vector2f {
    
    //MARK: - properties
    
    /// Length (two-norm or “Euclidean norm”) of x.
    @inlinable
    public var length: Float {
        return simd.length(d)
    }
    
    /// Length of x, squared. This is more efficient to compute than the length,
    /// so you should use it if you only need to compare lengths to each other.
    /// I.e. instead of writing:
    ///
    /// `if (length(x) < length(y)) { … }`
    ///
    /// use:
    ///
    /// `if (length_squared(x) < length_squared(y)) { … }`
    ///
    /// Doing it this way avoids one or two square roots, which is a fairly costly operation.
    @inlinable
    public var lengthSquared: Float {
        return simd.length_squared(d)
    }
    
    @inlinable
    public var normalized: Vector2f {
        return unsafeBitCast(simd.normalize(d), to: Vector2f.self)
    }
    
    //MARK: - operators
    
    @inlinable
    public static prefix func -(lhs: Vector2f) -> Vector2f {
        return unsafeBitCast(-lhs.d, to: Vector2f.self)
    }
    
    @inlinable
    public static func +=(lhs: inout Vector2f, rhs: Vector2f) {
        lhs.d += rhs.d
    }
    
    @inlinable
    public static func -=(lhs: inout Vector2f, rhs: Vector2f) {
        lhs.d -= rhs.d
    }
    
    @inlinable
    public static func *=(lhs: inout Vector2f, rhs: Vector2f) {
        lhs.d *= rhs.d
    }
    
    @inlinable
    public static func *=(lhs: inout Vector2f, rhs: Float) {
        lhs.d *= rhs
    }
    
    @inlinable
    public static func /=(lhs: inout Vector2f, rhs: Vector2f) {
        lhs.d /= rhs.d
    }
    
    @inlinable
    public static func /=(lhs: inout Vector2f, rhs: Float) {
        lhs.d *= (1.0 / rhs)
    }
    
    @inlinable
    public static func *(lhs: Matrix4x4f, rhs: Vector2f) -> Vector2f {
        let res = lhs.d * Vector4f(rhs).d
        return Vector2f(res.x, res.y)
    }
    
    @inlinable
    public static func *(lhs: Vector2f, rhs: Matrix4x4f) -> Vector2f {
        let res = Vector4f(lhs).d * rhs.d
        return Vector2f(res.x, res.y)
    }
}

//MARK: - functions

@inlinable
public func dot(_ a: Vector2f, _ b: Vector2f) -> Float {
    return simd.dot(a.d, b.d)
}

@inlinable
public func cross(_ a: Vector2f, _ b: Vector2f) -> Vector3f {
    return unsafeBitCast(simd.cross(a.d, b.d), to: Vector3f.self)
}

@inlinable
public func interpolate(from: Vector2f, to: Vector2f, factor: Float) -> Vector2f {
    return unsafeBitCast(simd.mix(from.d, to.d, t: factor), to: Vector2f.self)
}

extension Vector2f {
    @inlinable
    public static func +(lhs: Vector2f, rhs: Vector2f) -> Vector2f {
        return unsafeBitCast(lhs.d + rhs.d, to: Vector2f.self)
    }
    
    @inlinable
    public static func -(lhs: Vector2f, rhs: Vector2f) -> Vector2f {
        return unsafeBitCast(lhs.d - rhs.d, to: Vector2f.self)
    }
    
    @inlinable
    public static func *(lhs: Vector2f, rhs: Vector2f) -> Vector2f {
        return unsafeBitCast(lhs.d * rhs.d, to: Vector2f.self)
    }
    
    @inlinable
    public static func *(lhs: Vector2f, rhs: Float) -> Vector2f {
        return unsafeBitCast(lhs.d * rhs, to: Vector2f.self)
    }
    
    @inlinable
    public static func *(lhs: Float, rhs: Vector2f) -> Vector2f {
        return unsafeBitCast(lhs * rhs.d, to: Vector2f.self)
    }
    
    @inlinable
    public static func +(lhs: Vector2f, rhs: Float) -> Vector2f {
        return unsafeBitCast(lhs.d + Vector2f(rhs).d, to: Vector2f.self)
    }
    
    @inlinable
    public static func +(lhs: Float, rhs: Vector2f) -> Vector2f {
        return unsafeBitCast(Vector2f(lhs).d + rhs.d, to: Vector2f.self)
    }
    
    @inlinable
    public static func /(lhs: Vector2f, rhs: Vector2f) -> Vector2f {
        return unsafeBitCast(lhs.d / rhs.d, to: Vector2f.self)
    }
    
    @inlinable
    public static func /(lhs: Vector2f, rhs: Float) -> Vector2f {
        return unsafeBitCast(lhs.d * (1.0 / rhs), to: Vector2f.self)
    }
}

extension Vector2f: Equatable {
    @inlinable
    public static func ==(lhs: Vector2f, rhs: Vector2f) -> Bool {
        return
            lhs.d.x == rhs.d.x &&
                lhs.d.y == rhs.d.y
    }
}

#endif
