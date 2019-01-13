// Copyright 2016 Stuart Carnie.
// License: https://github.com/SwiftGFX/SwiftMath#license-bsd-2-clause
//

public typealias vec3 = Vector3f

extension Vector3f : Vector { }

extension Vector3f {
    //MARK: - initializers
    
    @inlinable
    public init(_ v: Vector4f) {
        self.init(v.x, v.y, v.z)
    }
    
    @inlinable
    public init(_ v: Vector2f) {
        self.init(v.x, v.y, 0.0)
    }
    
    @inlinable
    public init(_ xy: Vector2f, _ z: Float) {
        self.init(xy.x, xy.y, z)
    }
    
    @inlinable
    public init(x: Int, y: Int, z: Int) {
        self.init(x: Float(x), y: Float(y), z: Float(z))
    }
    
    @inlinable
    public init(_ x: Int, _ y: Int, _ z: Int) {
        self.init(x: Float(x), y: Float(y), z: Float(z))
    }
}

@inlinable
public func floor(_ v: Vector3f) -> Vector3f {
#if NOSIMD
    return Vector3f(v.x.rounded(.down), v.y.rounded(.down), v.z.rounded(.down))
#else
    var result = Vector3f()
    result.d = floor(v.d)
    return result
#endif
}

@inlinable
public func abs(_ v: Vector3f) -> Vector3f {
    #if NOSIMD
    return Vector3f(abs(v.x), abs(v.y), abs(v.z))
    #else
    var result = Vector3f()
    result.d = abs(v.d)
    return result
    #endif
}

@inlinable
public func ceil(_ v: Vector3f) -> Vector3f {
#if NOSIMD
    return Vector3f(v.x.rounded(.up), v.y.rounded(.up), v.z.rounded(.up))
#else
    var result = Vector3f()
    result.d = ceil(v.d)
    return result
#endif
}

@inlinable
public func min(_ a: Vector3f, _ b: Vector3f) -> Vector3f {
#if NOSIMD
    return Vector3f(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z))
#else
    var result = Vector3f()
    result.d = min(a.d, b.d)
    return result
#endif
}

@inlinable
public func max(_ a: Vector3f, _ b: Vector3f) -> Vector3f {
    #if NOSIMD
    return Vector3f(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z))
    #else
    var result = Vector3f()
    result.d = max(a.d, b.d)
    return result
    #endif
}

@inlinable
public func clamp(_ x: Vector3f, min minVec: Vector3f, max maxVec: Vector3f) -> Vector3f {
    return min(max(minVec, x), maxVec)
}

extension Vector3f {
    @inlinable
    public var isZero: Bool {
        return x == 0.0 && y == 0.0 && z == 0.0
    }
    
    public static let zero = Vector3f()
}

extension Vector3f: CustomStringConvertible {
    public var description: String {
        return "Vector3f(x: \(x), y: \(y), z: \(z))"
    }
}

extension Vector3f : CustomDebugStringConvertible {
    public var debugDescription : String {
        return self.description
    }
}


extension Vector3f {
    public var orthonormalBasis : (tangent: Vector3f, bitangent: Vector3f) {
        let n = self
        let sign : Float = n.z.sign == .plus ? 1.0 : -1.0
        let a = -1.0 / (sign + n.z);
        let b = n.x * n.y * a
        let b1 = Vector3f(1.0 + sign * n.x * n.x * a, sign * b, -sign * n.x)
        let b2 = Vector3f(b, sign + n.y * n.y * a, -n.y)
        return (b1, b2)
    }
}

