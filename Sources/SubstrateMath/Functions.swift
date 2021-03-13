// Copyright 2016 Stuart Carnie.
// License: https://github.com/SwiftGFX/SwiftMath#license-bsd-2-clause
//

/// Returns x, such that min ≤ x ≤ max
///
/// - parameter x:   value to be clamped
/// - parameter min: minimum
/// - parameter max: maximum
@inlinable
public func clamp<T:Comparable>(_ x: T, min _min: T, max _max: T) -> T {
    return min(max(x, _min), _max)
}

/// Returns x, such that min ≤ x ≤ max
///
/// - parameter x:   value to be clamped
/// - parameter min: minimum
/// - parameter max: maximum
@inlinable
public func clamp(_ x: Float, min _min: Float, max _max: Float) -> Float {
    // Assumptions: min and max will not be NaN.
    // Comparisons with NaN return false.
    var clamped = x > _min ? x : _min
    clamped = x > _max ? _max : clamped
    
    return clamped
}

/// Returns x, such that min ≤ x ≤ max
///
/// - parameter x:   value to be clamped
/// - parameter min: minimum
/// - parameter max: maximum
@inlinable
public func clamp(_ x: Double, min _min: Double, max _max: Double) -> Double {
    // Assumptions: min and max will not be NaN.
    // Comparisons with NaN return false.
    var clamped = x > _min ? x : _min
    clamped = x > _max ? _max : clamped
    
    return clamped
}

@inlinable
public func clamp<S: SIMD>(_ x: S, min _min: S, max _max: S) -> S where S.Scalar: FloatingPoint {
    return pointwiseMin(pointwiseMax(x, _min), _max)
}

/// Returns x, where 0.0 ≤ x ≤ 1.0
@inlinable
public func saturate(_ x: Float) -> Float {
    return clamp(x, min: 0.0, max: 1.0)
}

/// Returns x, where 0.0 ≤ x ≤ 1.0
@inlinable
public func saturate<T:BinaryFloatingPoint>(_ x: T) -> T {
    return clamp(x, min: 0.0, max: 1.0)
}

@inlinable
public func saturate<S: SIMD>(_ x: S) -> S where S.Scalar: FloatingPoint {
    return clamp(x, min: S.zero, max: S.one)
}

@inlinable
public func saturate(_ c: RGBColor) -> RGBColor {
    return RGBColor(saturate(c.r), saturate(c.g), saturate(c.b))
}

@inlinable
public func saturate(_ c: RGBAColor) -> RGBAColor {
    return RGBAColor(saturate(c.r), saturate(c.g), saturate(c.b), saturate(c.a))
}

/// Performs a linear interpolation between a and b by the interpolant t
///
/// - parameter a: start value
/// - parameter b: end value
/// - parameter t: interpolant
///
/// - returns: a value interpolated from a to b
@inlinable
public func interpolate<T:BinaryFloatingPoint>(from a: T, to b: T, factor t: T) -> T {
    return a + ((b - a) as T) * t
}

/// Maps a value from a start range to an end range
///
/// - parameter value: the value to map, within the range startMin...startMax.
/// - parameter startMin: the minimum value to map from
/// - parameter startMax: the maximum value to map from
/// - parameter endMin: the minimum value to map to
/// - parameter endMax: the maximum value to map to
///
/// - returns: a value within the range endMin...endMax
@inlinable
public func map<T: FloatingPoint>(_ value: T, start startMin: T, _ startMax: T, end endMin: T, _ endMax: T) -> T{
    let startRange : T = startMax - startMin
    let endRange : T = endMax - endMin
    return ((value - startMin) / startRange) * endRange + endMin
}


@inlinable
public func smoothstep<T: FloatingPoint>(_ x: T, from: T, to: T) -> T {
    // Scale, bias and saturate x to 0..1 range
    var x : T = ((x - from) as T) / ((to - from) as T)
    x = clamp(x, min: 0 as T, max: 1 as T)
    // Evaluate polynomial
    var result : T = x * x
    result *= ((3 as T) - (2 as T) * x)
    return result
}
