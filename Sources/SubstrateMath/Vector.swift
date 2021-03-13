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

@inlinable
public func dot<V : SIMD>(_ a: V, _ b: V) -> V.Scalar where V.Scalar : FloatingPoint {
    var total = V.Scalar(0)
    for i in a.indices {
        total += a[i] * b[i]
    }
    return total
}

@inlinable
public func componentSum<V : SIMD>(_ v: V) -> V.Scalar where V.Scalar : FloatingPoint {
    var total = V.Scalar(0)
    for i in v.indices {
        total += v[i]
    }
    return total
}

@inlinable
public func dot<V : SIMD>(_ a: V, _ b: V) -> V.Scalar where V.Scalar : BinaryInteger {
    var total = V.Scalar(0)
    for i in a.indices {
        total += a[i] * b[i]
    }
    return total
}

@inlinable
public func componentSum<V : SIMD>(_ v: V) -> V.Scalar where V.Scalar : BinaryInteger {
    var total = V.Scalar(0)
    for i in v.indices {
        total += v[i]
    }
    return total
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
