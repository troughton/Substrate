// Copyright 2016 Stuart Carnie.
// License: https://github.com/SwiftGFX/SwiftMath#license-bsd-2-clause
//

import RealModule

/// A floating point value that represents an angle
public struct Angle<Scalar: BinaryFloatingPoint & Real> : Hashable {
	
    /// The value of the angle in degrees
    @inlinable
    public var degrees: Scalar {
        get {
            return radians * 180.0 / .pi
        }
        set {
            radians = newValue * .pi / 180.0
        }
    }
	
    /// The value of the angle in radians
    public var radians: Scalar

	/// Creates an instance using the value in radians.
    @inlinable
    public init(radians val: Scalar) {
        radians = val
    }
    
    /// Creates an instance using the value in radians.
    /// The angle is reinterpreted to the range -pi...pi.
    @inlinable
    public init(truncatingRadians val: Scalar) {
        radians = val.remainder(dividingBy: 2.0 * .pi)
    }
    
    @available(*, deprecated, renamed: "init(radians:)")
    @inlinable
    public init(radiansInUnboundedRange val: Scalar) {
        radians = val
    }
	
	/// Creates an instance using the value in degrees
    @inlinable
    public init(degrees val: Scalar) {
        self.init(radians: val / 180.0 * .pi)
    }
    
    /// Creates an instance using the value in degrees
    @inlinable
    public init(truncatingDegrees val: Scalar) {
        self.init(truncatingRadians: val / 180.0 * .pi)
    }
    
    @available(*, deprecated, renamed: "init(degrees:)")
    /// Creates an instance using the value in degrees
    @inlinable
    public init(degreesInUnboundedRange val: Scalar) {
        self.init(degrees: val / 180.0 * .pi)
    }
    
    @inlinable
    public init<Other>(_ angle: Angle<Other>) {
        self.init(radians: Scalar(angle.radians))
    }
    
    // MARK: Constants
    @inlinable public static var zero  : Angle { return  Angle(radians: 0) }
    @inlinable public static var pi_6  : Angle { return  Angle(degrees: 30) }
    @inlinable public static var pi_4  : Angle { return  Angle(degrees: 45) }
    @inlinable public static var pi_3  : Angle { return  Angle(degrees: 60) }
    @inlinable public static var pi_2  : Angle { return  Angle(radians: Scalar.pi * 0.5) }
    @inlinable public static var pi2_3 : Angle { return  Angle(degrees: 120) }
    @inlinable public static var pi    : Angle { return  Angle(radians: Scalar.pi) }
    @inlinable public static var pi3_2 : Angle { return  Angle(degrees: 270) }
    @inlinable public static var pi2   : Angle { return  Angle(radians: Scalar.pi * 2) }
}

extension Angle : Decodable where Scalar : Decodable {}
extension Angle : Encodable where Scalar : Encodable {}
extension Angle: @unchecked Sendable where Scalar: Sendable {}

extension Angle {
    @inlinable
    public static func sin(_ a: Angle<Scalar>) -> Scalar {
        return Scalar.sin(a.radians)
    }

    @inlinable
    public static func cos(_ a: Angle<Scalar>) -> Scalar {
        return Scalar.cos(a.radians)
    }
    
    @inlinable
    public static func tan(_ a: Angle<Scalar>) -> Scalar {
        return Scalar.tan(a.radians)
    }

    @inlinable
    public static func sincos(_ a: Angle<Scalar>) -> (sin: Scalar, cos: Scalar) {
        let s: Scalar = Scalar.sin(a.radians)
        let c: Scalar = Scalar.cos(a.radians)
        
        return (sin: s, cos: c)
    }
}

extension Angle: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        return "\(degrees)°"
    }
    
    public var debugDescription: String {
        return "\(degrees)°"
    }
}

extension Angle {
    // MARK: - operators
    
    // MARK: multiplication (scaling)
  
    @inlinable
    public static func *=(lhs: inout Angle, rhs: Scalar) {
        lhs = Angle(radians: lhs.radians * rhs)
    }
    
    @inlinable
    public static func *(lhs: Angle, rhs: Scalar) -> Angle {
        return Angle(radians: lhs.radians * rhs)
    }
    
    @inlinable
    public static func *(lhs: Scalar, rhs: Angle) -> Angle {
        return Angle(radians: rhs.radians * lhs)
    }
    
    // MARK: division (scaling)
    
    @inlinable
    public static func /=(lhs: inout Angle, rhs: Scalar) {
        lhs = Angle(radians: lhs.radians / rhs)
    }
    
    @inlinable
    public static func /(lhs: Angle, rhs: Scalar) -> Angle {
        return Angle(radians: lhs.radians / rhs)
    }
    
    // MARK: addition
    
    @inlinable
    public static func +=(lhs: inout Angle, rhs: Angle) {
        lhs = Angle(radians: (lhs.radians + rhs.radians))
    }
    
    @inlinable
    public static func +(lhs: Angle, rhs: Angle) -> Angle {
        var result = lhs
        result += rhs
        return result
    }
    
    // MARK: subtraction
    
    @inlinable
    public static func -=(lhs: inout Angle, rhs: Angle) {
        lhs = Angle(radians: lhs.radians - rhs.radians)
    }
    
    @inlinable
    public static func -(lhs: Angle, rhs: Angle) -> Angle {
        var result = lhs
        result -= rhs
        return result
    }
    
    // MARK: Modulus
    
    @inlinable
    public static func %(lhs: Angle, rhs: Angle) -> Angle {
        return Angle(radians: lhs.radians.truncatingRemainder(dividingBy: rhs.radians))
    }
    
    // MARK: Unary
    
    @inlinable
    public static prefix func -(lhs: Angle) -> Angle {
        return Angle(radians: -lhs.radians)
    }
}

// MARK: - Equatable

extension Angle: Equatable {
    @inlinable
    public static func ==(lhs: Angle, rhs: Angle) -> Bool {
        return lhs.radians == rhs.radians
    }
}

// MARK: - Degrees

/// Degree operator, unicode symbol U+00B0 DEGREE SIGN
postfix operator °

/// The degree operator constructs an `Angle` from the specified floating point value in degrees
///
/// - remark: 
/// * Degree operator is the unicode symbol U+00B0 DEGREE SIGN
/// * macOS shortcut is ⌘+⇧+8
public postfix func °<Scalar>(lhs: Scalar) -> Angle<Scalar> {
    return Angle(degrees: lhs)
}

// MARK: - Convenience functions

/// Constructs an `Angle` from the specified floating point value in degrees
public func deg<Scalar>(_ a: Scalar) -> Angle<Scalar> {
    return Angle(degrees: a)
}

/// Constructs an `Angle` from the specified floating point value in radians
public func rad<Scalar>(_ a: Scalar) -> Angle<Scalar> {
    return Angle(radians: a)
}
