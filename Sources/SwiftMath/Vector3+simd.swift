// Copyright 2016 Stuart Carnie.
// License: https://github.com/SwiftGFX/SwiftMath#license-bsd-2-clause
//

#if !NOSIMD
import simd

@_fixed_layout
public struct Vector3f {
    public var d: float3 = float3()
    
    @inlinable
    public init() {
    }
    
    @inlinable
    public var x: Float { get { return d.x } set { d.x = newValue } }
    @inlinable
    public var y: Float { get { return d.y } set { d.y = newValue } }
    @inlinable
    public var z: Float { get { return d.z } set { d.z = newValue } }
    
    @inlinable
    public var r: Float { get { return d.x } set { d.x = newValue } }
    @inlinable
    public var g: Float { get { return d.y } set { d.y = newValue } }
    @inlinable
    public var b: Float { get { return d.z } set { d.z = newValue } }
    
    @inlinable
    public var s: Float { get { return d.x } set { d.x = newValue } }
    @inlinable
    public var t: Float { get { return d.y } set { d.y = newValue } }
    @inlinable
    public var p: Float { get { return d.z } set { d.z = newValue } }
    
    @inlinable
    public subscript(x: Int) -> Float {
        get {
            return d[x]
        }
        
        set {
            d[x] = newValue
        }
    }
}

extension Vector3f {
    
    //MARK: - initializers
    
    @inlinable
    public init(_ scalar: Float) {
        self.init()
        self.d = float3(scalar)
    }
    
    @inlinable
    public init(_ x: Float, _ y: Float, _ z: Float) {
        self.init()
        self.d = float3(x, y, z)
    }
    
    @inlinable
    public init(x: Float, y: Float, z: Float) {
        self.init()
        self.d = float3(x, y, z)
    }
    
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
    public var normalized: Vector3f {
        return unsafeBitCast(simd.normalize(self.d), to: Vector3f.self)
    }
    
    @inlinable
    public var componentSum : Float {
        return simd.reduce_add(d)
    }
    
    //MARK: - operators
    
    
    @inlinable
    public static prefix func -(lhs: Vector3f) -> Vector3f {
        return unsafeBitCast(-lhs.d, to: Vector3f.self)
    }
    
    @inlinable
    public static func +=(lhs: inout Vector3f, rhs: Vector3f) {
        lhs.d += rhs.d
    }
    
    @inlinable
    public static func -=(lhs: inout Vector3f, rhs: Vector3f) {
        lhs.d -= rhs.d
    }
    
    @inlinable
    public static func *=(lhs: inout Vector3f, rhs: Vector3f) {
        lhs.d *= rhs.d
    }
    
    @inlinable
    public static func *=(lhs: inout Vector3f, rhs: Float) {
        lhs.d *= rhs
    }
    
    @inlinable
    public static func /=(lhs: inout Vector3f, rhs: Vector3f) {
        lhs.d /= rhs.d
    }
    
    @inlinable
    public static func /=(lhs: inout Vector3f, rhs: Float) {
        lhs.d *= (1.0 / rhs)
    }
    
    @inlinable
    public static func *(lhs: Matrix3x3f, rhs: Vector3f) -> Vector3f {
        return unsafeBitCast(lhs.d * rhs.d, to: Vector3f.self)
    }
    
    @inlinable
    public static func *(lhs: Vector3f, rhs: Matrix3x3f) -> Vector3f {
        return unsafeBitCast(lhs.d * rhs.d, to: Vector3f.self)
    }
    
    @inlinable
    public static func ==(lhs: Vector3f, rhs: Vector3f) -> Bool {
        return lhs.x == rhs.x && lhs.y == rhs.y && lhs.z == rhs.z
    }
}

//MARK: - functions

@inlinable
public func dot(_ x: Vector3f, _ y: Vector3f) -> Float {
    return simd.dot(x.d, y.d)
}

@inlinable
public func cross(_ x: Vector3f, _ y: Vector3f) -> Vector3f {
    return unsafeBitCast(simd.cross(x.d, y.d), to: Vector3f.self)
}

@inlinable
public func interpolate(from: Vector3f, to: Vector3f, factor: Float) -> Vector3f {
    return unsafeBitCast(simd.mix(from.d, to.d, t: factor), to: Vector3f.self)
}

extension Vector3f {
    @inlinable
    public static func +(lhs: Vector3f, rhs: Vector3f) -> Vector3f {
        return unsafeBitCast(lhs.d + rhs.d, to: Vector3f.self)
    }
    
    @inlinable
    public static func -(lhs: Vector3f, rhs: Vector3f) -> Vector3f {
        return unsafeBitCast(lhs.d - rhs.d, to: Vector3f.self)
    }
    
    @inlinable
    public static func *(lhs: Vector3f, rhs: Vector3f) -> Vector3f {
        return unsafeBitCast(lhs.d * rhs.d, to: Vector3f.self)
    }
    
    @inlinable
    public static func *(lhs: Vector3f, rhs: Float) -> Vector3f {
        return unsafeBitCast(lhs.d * rhs, to: Vector3f.self)
    }
    
    @inlinable
    public static func *(lhs: Float, rhs: Vector3f) -> Vector3f {
        return unsafeBitCast(lhs * rhs.d, to: Vector3f.self)
    }
    
    @inlinable
    public static func +(lhs: Vector3f, rhs: Float) -> Vector3f {
        return unsafeBitCast(lhs.d + Vector3f(rhs).d, to: Vector3f.self)
    }
    
    @inlinable
    public static func +(lhs: Float, rhs: Vector3f) -> Vector3f {
        return unsafeBitCast(Vector3f(lhs).d + rhs.d, to: Vector3f.self)
    }
    
    @inlinable
    public static func *(lhs: Int, rhs: Vector3f) -> Vector3f {
        return unsafeBitCast(Vector3f(Float(lhs)).d * rhs.d, to: Vector3f.self)
    }
    
    @inlinable
    public static func /(lhs: Vector3f, rhs: Vector3f) -> Vector3f {
        return unsafeBitCast(lhs.d / rhs.d, to: Vector3f.self)
    }
    
    @inlinable
    public static func /(lhs: Vector3f, rhs: Float) -> Vector3f {
        return unsafeBitCast(lhs.d * (1.0 / rhs), to: Vector3f.self)
    }
}

#endif
