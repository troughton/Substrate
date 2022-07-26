//
//  Vector.swift
//  SwiftMath
//
//  Created by Thomas Roughton on 11/01/17.
//
//

import Swift

public typealias Vector2f = SIMD2<Float>
public typealias Vector3f = SIMD3<Float>
public typealias Vector4f = SIMD4<Float>

@inlinable @inline(__always)
public func dot<V : SIMD>(_ a: V, _ b: V) -> V.Scalar where V.Scalar : FloatingPoint {
    var result = V.Scalar.zero
    for i in 0..<V.scalarCount {
        result += a[i] * b[i]
    }
    return result
}

@inlinable @inline(__always)
public func dot<V : SIMD>(_ a: V, _ b: V) -> V.Scalar where V.Scalar : FixedWidthInteger {
    var result = V.Scalar.zero
    for i in 0..<V.scalarCount {
        result &+= a[i] &* b[i]
    }
    return result
}

extension SIMD where Scalar : FloatingPoint {
    @inlinable
    public var lengthSquared : Scalar {
        return dot(self, self)
    }
    
    @inlinable
    public var length : Scalar {
        return self.lengthSquared.squareRoot()
    }
    
    @inlinable
    public var normalized : Self {
        return normalize(self)
    }
}

@inlinable
public func normalize<V : SIMD>(_ v: V) -> V where V.Scalar : FloatingPoint {
    return v / V(repeating: v.length)
}

@inlinable
public func cross<S>(_ u: SIMD2<S>, _ v: SIMD2<S>) -> S where S : Numeric {
    var result = u.x * v.y
    result -= u.y * v.x
    return result
}

@inlinable
public func cross<S>(_ u: SIMD3<S>, _ v: SIMD3<S>) -> SIMD3<S> where S : Numeric {
    var x : S = u.y * v.z
    x -= u.z * v.y
    var y : S = u.z * v.x
    y -= u.x * v.z
    var z : S = u.x * v.y
    z -= u.y * v.x
    return SIMD3<S>(x, y, z)
}

@inlinable
public func reflect<S>(incident: SIMD3<S>, normal: SIMD3<S>) -> SIMD3<S> where S: BinaryFloatingPoint {
    return incident - SIMD3<S>(repeating: 2.0) * dot(incident, normal) * normal
}

@inlinable
public func refract<S>(incident I: SIMD3<S>, normal N: SIMD3<S>, eta: S) -> SIMD3<S> where S : BinaryFloatingPoint {
    let k = 1.0 - eta * eta * (1.0 - dot(N, I) * dot(N, I))
    if k < 0.0 {
        return .zero
    } else {
        return eta * I - (eta * dot(N, I) + k.squareRoot()) * N
    }
}

@inlinable
public func interpolate<V : SIMD>(from: V, to: V, factor: V.Scalar) -> V where V.Scalar : FloatingPoint {
    return from + (to - from) * V(repeating: factor)
}

@inlinable
public func floor<V : SIMD>(_ v: V) -> V where V.Scalar : FloatingPoint {
    var result = v
    for i in v.indices {
        result[i] = result[i].rounded(.down)
    }
    return result
}

@inlinable
public func ceil<V : SIMD>(_ v: V) -> V where V.Scalar : FloatingPoint {
    var result = v
    for i in v.indices {
        result[i] = result[i].rounded(.up)
    }
    return result
}

@inlinable
public func abs<V : SIMD>(_ v: V) -> V where V.Scalar : Comparable & SignedNumeric {
    var result = v
    for i in v.indices {
        result[i] = abs(result[i])
    }
    return result
}

@inlinable
public func clamp<V : SIMD>(_ x: V, min minVec: V, max maxVec: V) -> V where V.Scalar : Comparable {
    return x.clamped(lowerBound: minVec, upperBound: maxVec)
}

extension SIMD2 {
    @inlinable
    public func map<U>(_ applying: (Scalar) -> U) -> SIMD2<U> {
        var result = SIMD2<U>()
        for i in 0..<self.scalarCount {
            result[i] = applying(self[i])
        }
        return result
    }
}

extension SIMD3 {
    @inlinable
    public func map<U>(_ applying: (Scalar) -> U) -> SIMD3<U> {
        var result = SIMD3<U>()
        for i in 0..<self.scalarCount {
            result[i] = applying(self[i])
        }
        return result
    }
}

extension SIMD4 {
    @inlinable
    public func map<U>(_ applying: (Scalar) -> U) -> SIMD4<U> {
        var result = SIMD4<U>()
        for i in 0..<self.scalarCount {
            result[i] = applying(self[i])
        }
        return result
    }
}

extension SIMD8 {
    @inlinable
    public func map<U>(_ applying: (Scalar) -> U) -> SIMD8<U> {
        var result = SIMD8<U>()
        for i in 0..<self.scalarCount {
            result[i] = applying(self[i])
        }
        return result
    }
}

extension SIMD16 {
    @inlinable
    public func map<U>(_ applying: (Scalar) -> U) -> SIMD16<U> {
        var result = SIMD16<U>()
        for i in 0..<self.scalarCount {
            result[i] = applying(self[i])
        }
        return result
    }
}

extension SIMD32 {
    @inlinable
    public func map<U>(_ applying: (Scalar) -> U) -> SIMD32<U> {
        var result = SIMD32<U>()
        for i in 0..<self.scalarCount {
            result[i] = applying(self[i])
        }
        return result
    }
}

extension SIMD64 {
    @inlinable
    public func map<U>(_ applying: (Scalar) -> U) -> SIMD64<U> {
        var result = SIMD64<U>()
        for i in 0..<self.scalarCount {
            result[i] = applying(self[i])
        }
        return result
    }
}
