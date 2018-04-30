import visualc
import ucrt

@_transparent
public func sin(_ x: Float) -> Float {
    return sinf(x)
}

@_transparent
public func cos(_ x: Float) -> Float {
    return cosf(x)
}

@_transparent
public func tan(_ x: Float) -> Float {
    return tanf(x)
}

@_transparent
public func asin(_ x: Float) -> Float {
    return asinf(x)
}

@_transparent
public func acos(_ x: Float) -> Float {
    return acosf(x)
}

@_transparent
public func atan(_ x: Float) -> Float {
    return atanf(x)
}

@_transparent
public func atan2(_ x: Float, _ y: Float) -> Float {
    return atan2f(x, y)
}

@_transparent
public func round(_ x: Float) -> Float {
    return roundf(x)
}

@_transparent
public func fabs(_ x: Float) -> Float {
    return fabsf(x)
}

@_transparent
public func pow(_ a: Float, _ b: Float) -> Float {
    return powf(a, b)
}

@_transparent
public func sqrt(_ x: Float) -> Float {
    return sqrtf(x)
}

@_transparent
public func exp(_ x: Float) -> Float {
    return expf(x)
}

@_transparent
public func log(_ x: Float) -> Float {
    return logf(x)
}

@_transparent
public func log2(_ x: Float) -> Float {
    return log2f(x)
}

@_transparent
public func floor(_ x: Float) -> Float {
    return floorf(x)
}

@_transparent
public func ceil(_ x: Float) -> Float {
    return ceilf(x)
}

@_transparent
public func modf(_ x: Double) -> (Double, Double) {
    var ipart : Double = 0
    let fpart = modf(x, &ipart)
    return (ipart, fpart)
}

@_transparent
public func modf(_ x: Float) -> (Float, Float) {
    var ipart : Float = 0
    let fpart = modff(x, &ipart)
    return (ipart, fpart)
}

@_transparent
public func fmod(_ a: Float, _ b: Float) -> Float {
    return fmodf(a, b)
}

@_transparent
public func hypot(_ lhs: Float, _ rhs: Float) -> Float {
    return hypotf(lhs, rhs)
}