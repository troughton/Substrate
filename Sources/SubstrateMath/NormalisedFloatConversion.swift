import RealModule

// Reference: https://docs.microsoft.com/en-us/windows/win32/direct3d10/d3d10-graphics-programming-guide-resources-data-conversion
@_specialize(kind: full, where F == Float, I == Int8)
@_specialize(kind: full, where F == Float, I == Int16)
@inlinable
public func floatToSnorm<F: BinaryFloatingPoint, I: BinaryInteger & FixedWidthInteger & SignedInteger>(_ c: F, type: I.Type = I.self) -> I {
    if c != c { // Check for NaN – this check is faster than c.isNaN
        return 0
    }
    let c = clamp(c, min: -1.0, max: 1.0)
    
    let scale: F = F(I.max)
    let rescaled = c * scale
    let rounded = rescaled.rounded(.toNearestOrAwayFromZero)
    return I(rounded)
}

@_specialize(kind: full, where F == Float, I == Int8)
@_specialize(kind: full, where F == Float, I == Int16)
@inlinable
public func floatToSnorm<F: BinaryFloatingPoint, I: BinaryInteger & FixedWidthInteger & SignedInteger>(_ c: SIMD2<F>, type: I.Type = I.self) -> SIMD2<I> {
    if any(c .!= c) { // Check for NaN – this check is faster than c.isNaN
        return .zero
    }
    let c = c.clamped(lowerBound: SIMD2(repeating: -1.0), upperBound: SIMD2(repeating: 1.0))
    
    let scale: F = F(I.max)
    let rescaled = c * scale
    return SIMD2<I>(rescaled, rounding: .toNearestOrAwayFromZero)
}

@_specialize(kind: full, where F == Float, I == Int8)
@_specialize(kind: full, where F == Float, I == Int16)
@inlinable
public func floatToSnorm<F: BinaryFloatingPoint, I: BinaryInteger & FixedWidthInteger & SignedInteger>(_ c: SIMD3<F>, type: I.Type = I.self) -> SIMD3<I> {
    if any(c .!= c) { // Check for NaN – this check is faster than c.isNaN
        return .zero
    }
    let c = c.clamped(lowerBound: SIMD3(repeating: -1.0), upperBound: SIMD3(repeating: 1.0))
    
    let scale: F = F(I.max)
    let rescaled = c * scale
    return SIMD3<I>(rescaled, rounding: .toNearestOrAwayFromZero)
}

@_specialize(kind: full, where F == Float, I == Int8)
@_specialize(kind: full, where F == Float, I == Int16)
@inlinable
public func floatToSnorm<F: BinaryFloatingPoint, I: BinaryInteger & FixedWidthInteger & SignedInteger>(_ c: SIMD4<F>, type: I.Type = I.self) -> SIMD4<I> {
    if any(c .!= c) { // Check for NaN – this check is faster than c.isNaN
        return .zero
    }
    let c = c.clamped(lowerBound: SIMD4(repeating: -1.0), upperBound: SIMD4(repeating: 1.0))
    
    let scale: F = F(I.max)
    let rescaled = c * scale
    return SIMD4<I>(rescaled, rounding: .toNearestOrAwayFromZero)
}

@_specialize(kind: full, where F == Float, I == UInt8)
@_specialize(kind: full, where F == Float, I == UInt16)
@inlinable
public func floatToUnorm<F: BinaryFloatingPoint, I: BinaryInteger & FixedWidthInteger & UnsignedInteger>(_ c: F, type: I.Type = I.self) -> I {
    if c != c { // Check for NaN – this check is faster than c.isNaN
        return 0
    }
    let c = Swift.min(1.0, Swift.max(c, 0.0))
    let scale: F = F(I.max)
    let rescaled = c * scale
    let rounded = rescaled.rounded(.toNearestOrAwayFromZero)
    return I(rounded)
}

@_specialize(kind: full, where F == Float, I == UInt8)
@_specialize(kind: full, where F == Float, I == UInt16)
@inlinable
public func floatToUnorm<F: BinaryFloatingPoint, I: BinaryInteger & FixedWidthInteger & UnsignedInteger>(_ c: SIMD2<F>, type: I.Type = I.self) -> SIMD2<I> {
    if any(c .!= c) { // Check for NaN – this check is faster than c.isNaN
        return .zero
    }
    let c = c.clamped(lowerBound: .zero, upperBound: .one)
    let scale: F = F(I.max)
    let rescaled = c * scale
    return SIMD2<I>(rescaled, rounding: .toNearestOrAwayFromZero)
}

@_specialize(kind: full, where F == Float, I == UInt8)
@_specialize(kind: full, where F == Float, I == UInt16)
@inlinable
public func floatToUnorm<F: BinaryFloatingPoint, I: BinaryInteger & FixedWidthInteger & UnsignedInteger>(_ c: SIMD3<F>, type: I.Type = I.self) -> SIMD3<I> {
    if any(c .!= c) { // Check for NaN – this check is faster than c.isNaN
        return .zero
    }
    let c = c.clamped(lowerBound: .zero, upperBound: .one)
    let scale: F = F(I.max)
    let rescaled = c * scale
    return SIMD3<I>(rescaled, rounding: .toNearestOrAwayFromZero)
}

@_specialize(kind: full, where F == Float, I == UInt8)
@_specialize(kind: full, where F == Float, I == UInt16)
@inlinable
public func floatToUnorm<F: BinaryFloatingPoint, I: BinaryInteger & FixedWidthInteger & UnsignedInteger>(_ c: SIMD4<F>, type: I.Type = I.self) -> SIMD4<I> {
    if any(c .!= c) { // Check for NaN – this check is faster than c.isNaN
        return .zero
    }
    let c = c.clamped(lowerBound: .zero, upperBound: .one)
    let scale: F = F(I.max)
    let rescaled = c * scale
    return SIMD4<I>(rescaled, rounding: .toNearestOrAwayFromZero)
}

@_specialize(kind: full, where I == Int8)
@_specialize(kind: full, where I == Int16)
@inlinable
public func snormToFloat<I: BinaryInteger & FixedWidthInteger & SignedInteger>(_ c: I) -> Float {
    if c == I.min {
        return -1.0
    }
    return Float(c) / Float(I.max)
}

@_specialize(kind: full, where I == Int8)
@_specialize(kind: full, where I == Int16)
@inlinable
public func snormToFloat<I: BinaryInteger & FixedWidthInteger & SignedInteger>(_ c: SIMD2<I>) -> SIMD2<Float> {
    let c = c.replacing(with: SIMD2(repeating: -I.max), where: c .== SIMD2(repeating: I.min))
    return (SIMD2<Float>(c) / Float(I.max))
}

@_specialize(kind: full, where I == Int8)
@_specialize(kind: full, where I == Int16)
@inlinable
public func snormToFloat<I: BinaryInteger & FixedWidthInteger & SignedInteger>(_ c: SIMD3<I>) -> SIMD3<Float> {
    let c = c.replacing(with: SIMD3(repeating: -I.max), where: c .== SIMD3(repeating: I.min))
    return SIMD3<Float>(c) / Float(I.max)
}

@_specialize(kind: full, where I == Int8)
@_specialize(kind: full, where I == Int16)
@inlinable
public func snormToFloat<I: BinaryInteger & FixedWidthInteger & SignedInteger>(_ c: SIMD4<I>) -> SIMD4<Float> {
    let c = c.replacing(with: SIMD4(repeating: -I.max), where: c .== SIMD4(repeating: I.min))
    return SIMD4<Float>(c) / Float(I.max)
}

@_specialize(kind: full, where I == UInt8)
@_specialize(kind: full, where I == UInt16)
@inlinable
public func unormToFloat<I: BinaryInteger & FixedWidthInteger & UnsignedInteger>(_ c: I) -> Float {
    return Float(c) / Float(I.max)
}

@_specialize(kind: full, where I == UInt8)
@_specialize(kind: full, where I == UInt16)
@inlinable
public func unormToFloat<I: BinaryInteger & FixedWidthInteger & UnsignedInteger>(_ c: SIMD2<I>) -> SIMD2<Float> {
    return SIMD2<Float>(c) / Float(I.max)
}

@_specialize(kind: full, where I == UInt8)
@_specialize(kind: full, where I == UInt16)
@inlinable
public func unormToFloat<I: BinaryInteger & FixedWidthInteger & UnsignedInteger>(_ c: SIMD3<I>) -> SIMD3<Float> {
    return SIMD3<Float>(c) / Float(I.max)
}

@_specialize(kind: full, where I == UInt8)
@_specialize(kind: full, where I == UInt16)
@inlinable
public func unormToFloat<I: BinaryInteger & FixedWidthInteger & UnsignedInteger>(_ c: SIMD4<I>) -> SIMD4<Float> {
    return SIMD4<Float>(c) / Float(I.max)
}
