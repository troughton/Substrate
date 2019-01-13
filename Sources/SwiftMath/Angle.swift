// Copyright 2016 Stuart Carnie.
// License: https://github.com/SwiftGFX/SwiftMath#license-bsd-2-clause
//

/// A floating point value that represents an angle
public struct Angle : Codable, Hashable {
	
    /// The value of the angle in degrees
    public var degrees: Float {
        return radians * 180.0 / Float.pi
    }
	
    /// The value of the angle in radians
    public let radians: Float

	/// Creates an instance using the value in radians
    public init(radians val: Float) {
        radians = val
    }
	
	/// Creates an instance using the value in degrees
    public init(degrees val: Float) {
        radians = val / 180.0 * Float.pi
    }
    
    // MARK: Constants
    public static let zero  = 0
    public static let pi_6  = 30°
    public static let pi_4  = 45°
    public static let pi_3  = 60°
    public static let pi_2  = Float.pi * 0.5
    public static let pi2_3 = 120°
    public static let pi    = Float.pi
    public static let pi3_2 = 270°
    public static let pi2   = Float.pi * 2
}

extension Angle: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        return "\(degrees)°"
    }
    
    public var debugDescription: String {
        return "\(degrees)°"
    }
}

extension Int {
    /// Returns the integer value as an angle in degrees
    public var degrees: Angle {
        return Angle(degrees: Float(self))
    }
}

extension Angle {
    // MARK: - operators
    
    // MARK: multiplication (scaling)
  
    @inlinable
    public static func *=(lhs: inout Angle, rhs: Float) {
        lhs = Angle(radians: lhs.radians * rhs)
    }
    
    @inlinable
    public static func *(lhs: Angle, rhs: Float) -> Angle {
        return Angle(radians: lhs.radians * rhs)
    }
    
    @inlinable
    public static func *(lhs: Float, rhs: Angle) -> Angle {
        return Angle(radians: rhs.radians * lhs)
    }
    
    // MARK: division (scaling)
    
    @inlinable
    public static func /=(lhs: inout Angle, rhs: Float) {
        lhs = Angle(radians: lhs.radians / rhs)
    }
    
    @inlinable
    public static func /(lhs: Angle, rhs: Float) -> Angle {
        return Angle(radians: lhs.radians / rhs)
    }
    
    // MARK: addition
    
    @inlinable
    public static func +=(lhs: inout Angle, rhs: Angle) {
        lhs = Angle(radians: lhs.radians + rhs.degrees)
    }
    
    @inlinable
    public static func +(lhs: Angle, rhs: Angle) -> Angle {
        return Angle(radians: lhs.radians + rhs.degrees)
    }
    
    // MARK: subtraction
    
    @inlinable
    public static func -=(lhs: inout Angle, rhs: Angle) {
        lhs = Angle(radians: lhs.radians - rhs.degrees)
    }
    
    @inlinable
    public static func -(lhs: Angle, rhs: Angle) -> Angle {
        return Angle(radians: lhs.radians - rhs.degrees)
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

// MARK: - Comparable

extension Angle: Comparable {
    @inlinable
	public static func <(lhs: Angle, rhs: Angle) -> Bool {
		return lhs.radians < rhs.radians
	}
    
    @inlinable
	public static func <=(lhs: Angle, rhs: Angle) -> Bool {
		return lhs.radians <= rhs.radians
	}
    
    @inlinable
	public static func >(lhs: Angle, rhs: Angle) -> Bool {
		return lhs.radians > rhs.radians
	}
    
    @inlinable
	public static func >=(lhs: Angle, rhs: Angle) -> Bool {
		return lhs.radians >= rhs.radians
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
public postfix func °(lhs: Float) -> Angle {
    return Angle(degrees: lhs)
}

/// Constructs an `Angle` from the specified `Int` value in degrees
public postfix func °(lhs: Int) -> Angle {
    return Angle(degrees: Float(lhs))
}

// MARK: - Convenience functions

/// Constructs an `Angle` from the specified floating point value in degrees
public func deg(_ a: Float) -> Angle {
    return Angle(degrees: a)
}

/// Constructs an `Angle` from the specified floating point value in radians
public func rad(_ a: Float) -> Angle {
    return Angle(radians: a)
}
