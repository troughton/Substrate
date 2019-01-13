// Copyright 2016 Stuart Carnie.
// License: https://github.com/SwiftGFX/SwiftMath#license-bsd-2-clause
//

#if !NOSIMD
import simd

@_fixed_layout
public struct Vector4f {
    public var d: float4 = float4()
    
    @inlinable
    public var x: Float { get { return d.x } set { d.x = newValue } }
    @inlinable
    public var y: Float { get { return d.y } set { d.y = newValue } }
    @inlinable
    public var z: Float { get { return d.z } set { d.z = newValue } }
    @inlinable
    public var w: Float { get { return d.w } set { d.w = newValue } }
    
    @inlinable
    public var r: Float { get { return d.x } set { d.x = newValue } }
    @inlinable
    public var g: Float { get { return d.y } set { d.y = newValue } }
    @inlinable
    public var b: Float { get { return d.z } set { d.z = newValue } }
    @inlinable
    public var a: Float { get { return d.w } set { d.w = newValue } }
    
    @inlinable
    public var s: Float { get { return d.x } set { d.x = newValue } }
    @inlinable
    public var t: Float { get { return d.y } set { d.y = newValue } }
    @inlinable
    public var p: Float { get { return d.z } set { d.z = newValue } }
    @inlinable
    public var q: Float { get { return d.w } set { d.w = newValue } }
    
    @inlinable
    public subscript(x: Int) -> Float {
        get {
            return d[x]
        }
        
        set {
            d[x] = newValue
        }
    }
    
    // MARK: - initializers
    
    @inlinable
    public init() {
    }
    
    @inlinable
    public init(_ scalar: Float) {
        self.d = float4(scalar)
    }
    
    @inlinable
    public init(float4 scalar4: float4) {
        self.d = scalar4
    }
    
    @inlinable
    public init(_ x: Float, _ y: Float, _ z: Float, _ w: Float) {
        self.d = float4(x, y, z, w)
    }
    
    @inlinable
    public init(x: Float, y: Float, z: Float, w: Float) {
        self.d = float4(x, y, z, w)
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
    
}

extension Vector4f {
    
    // MARK: - properties
    
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
    public var normalized: Vector4f {
        return unsafeBitCast(simd.normalize(self.d), to: Vector4f.self)
    }
    
    // MARK: - operators
    
    @inlinable
    public static prefix func -(lhs: Vector4f) -> Vector4f {
        return unsafeBitCast(-lhs.d, to: Vector4f.self)
    }
    
    @inlinable
    public static func +=(lhs: inout Vector4f, rhs: Vector4f) {
        lhs.d += rhs.d
    }
    
    @inlinable
    public static func -=(lhs: inout Vector4f, rhs: Vector4f) {
        lhs.d -= rhs.d
    }
    
    @inlinable
    public static func *=(lhs: inout Vector4f, rhs: Vector4f) {
        lhs.d *= rhs.d
    }
    
    @inlinable
    public static func *=(lhs: inout Vector4f, rhs: Float) {
        lhs.d *= rhs
    }
    
    @inlinable
    public static func /=(lhs: inout Vector4f, rhs: Vector4f) {
        lhs.d /= rhs.d
    }
    
    @inlinable
    public static func /=(lhs: inout Vector4f, rhs: Float) {
        lhs.d *= (1.0 / rhs)
    }
    
    @inlinable
    public static func *(lhs: Matrix4x4f, rhs: Vector4f) -> Vector4f {
        return unsafeBitCast(lhs.d * rhs.d, to: Vector4f.self)
    }
    
    @inlinable
    public static func *(lhs: Vector4f, rhs: Matrix4x4f) -> Vector4f {
        return unsafeBitCast(lhs.d * rhs.d, to: Vector4f.self)
    }
    
    @inlinable
    public static func ==(lhs: Vector4f, rhs: Vector4f) -> Bool {
        return lhs.x == rhs.x && lhs.y == rhs.y && lhs.z == rhs.z && lhs.w == rhs.w
    }
}

// MARK: - functions

@inlinable
public func dot(_ x: Vector4f, _ y: Vector4f) -> Float {
    return simd.dot(x.d, y.d)
}

/// Linear interpolation to the target vector
///
/// - note:
///     * when factor is 0, returns self
///     * when factor is 1, returns `to`
///
/// - parameter to:     target vector
/// - parameter factor: factor
///
/// - returns: interpolated vector
@inlinable
public func interpolate(from: Vector4f, to: Vector4f, factor: Float) -> Vector4f {
    return unsafeBitCast(simd.mix(from.d, to.d, t: factor), to: Vector4f.self)
}

extension Vector4f {
    @inlinable
    public static func +(lhs: Vector4f, rhs: Vector4f) -> Vector4f {
        return unsafeBitCast(lhs.d + rhs.d, to: Vector4f.self)
    }
    
    @inlinable
    public static func -(lhs: Vector4f, rhs: Vector4f) -> Vector4f {
        return unsafeBitCast(lhs.d - rhs.d, to: Vector4f.self)
    }
    
    @inlinable
    public static func *(lhs: Vector4f, rhs: Vector4f) -> Vector4f {
        return unsafeBitCast(lhs.d * rhs.d, to: Vector4f.self)
    }
    
    @inlinable
    public static func *(lhs: Vector4f, rhs: Float) -> Vector4f {
        return unsafeBitCast(lhs.d * rhs, to: Vector4f.self)
    }
    
    @inlinable
    public static func *(lhs: Float, rhs: Vector4f) -> Vector4f {
        return unsafeBitCast(lhs * rhs.d, to: Vector4f.self)
    }
    
    @inlinable
    public static func /(lhs: Vector4f, rhs: Vector4f) -> Vector4f {
        return unsafeBitCast(lhs.d / rhs.d, to: Vector4f.self)
    }
    
    @inlinable
    public static func /(lhs: Vector4f, rhs: Float) -> Vector4f {
        return unsafeBitCast(lhs.d * (1.0 / rhs), to: Vector4f.self)
    }
}

#endif
