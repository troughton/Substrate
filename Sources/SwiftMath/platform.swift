// Copyright 2016 Stuart Carnie.
// License: https://github.com/SwiftGFX/SwiftMath#license-bsd-2-clause
//

#if os(Linux)

import Glibc
    
@usableFromInline
internal func __sincosf(_ a: Float, _ sina: inout Float, _ cosa: inout Float) {
    sina = sin(a)
    cosa = cos(a)
}

#elseif os(macOS) || os(iOS)
    
import Foundation

#elseif os(Windows)

import Foundation

@usableFromInline
internal func __sincosf(_ a: Float, _ sina: inout Float, _ cosa: inout Float) {
    sina = sin(a)
    cosa = cos(a)
}

#endif

@inlinable
public func sincos(_ a: Angle, _ sina: inout Float, _ cosa: inout Float)  {
    __sincosf(a.radians, &sina, &cosa)
}

@inlinable
public func sincos(_ a: Angle) -> (sin: Float, cos: Float) {
    var s: Float = 0.0
    var c: Float = 0.0
    sincos(a, &s, &c)
    
    return (sin: s, cos: c)
}

@inlinable
public func sin(_ a: Angle) -> Float {
	return sin(a.radians)
}

@inlinable
public func cos(_ a: Angle) -> Float {
	return cos(a.radians)
}

@inlinable
public func tan(_ a: Angle) -> Float {
    return tan(a.radians)
}
