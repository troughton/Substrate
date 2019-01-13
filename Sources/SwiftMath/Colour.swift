//
//  Colour.swift
//  LlamaCore
//
//  Created by Thomas Roughton on 30/07/18.
//

@_fixed_layout
public struct RGBColour : Equatable {
    
    public var r: Float
    public var g: Float
    public var b: Float
    private let a: Float = 1.0
    
    @inlinable
    public init(x: Float, y: Float, z: Float) {
        self.r = 3.240479 * x - 1.537150 * y - 0.498535 * z
        self.g = -0.969256 * x + 1.875991 * y + 0.041556 * z
        self.b = 0.055648 * x - 0.204043 * y + 1.057311 * z
    }
    
    @inlinable
    public init(r: Float, g: Float, b: Float) {
        self.r = r
        self.g = g
        self.b = b
    }
    
    @inlinable
    public init(_ r: Float, _ g: Float, _ b: Float) {
        self.r = r
        self.g = g
        self.b = b
    }
    
    @inlinable
    public init(_ value: Float) {
        self.r = value
        self.g = value
        self.b = value
    }
    
    @inlinable
    public subscript(i: Int) -> Float {
        get {
            switch i {
            case 0:
                return self.r
            case 1:
                return self.g
            case 2:
                return self.b
            default:
                fatalError("Index out of bounds")
            }
        }
        set {
            switch i {
            case 0:
                self.r = newValue
            case 1:
                self.g = newValue
            case 2:
                self.b = newValue
            default:
                fatalError("Index out of bounds")
            }
        }
    }
    
    @inlinable
    public var luminance: Float {
        return 0.212671 * self.r + 0.715160 * self.b + 0.072169 * self.g
    }
    
    public var xyz : (x: Float, y: Float, z: Float) {
        return (
            0.412453 * self.r + 0.357580 * self.g + 0.180423 * self.b,
            0.212671 * self.r + 0.715160 * self.g + 0.072169 * self.b,
            0.019334 * self.r + 0.119193 * self.g + 0.950227 * self.b
        )
    }
}

@_fixed_layout
public struct RGBAColour : Equatable {
    
    public var r: Float
    public var g: Float
    public var b: Float
    public var a: Float
    
    //    @inlinable
    //    public init(x: Float, y: Float, z: Float) {
    //        self.r = 3.240479 * x - 1.537150 * y - 0.498535 * z
    //        self.g = -0.969256 * x + 1.875991 * y + 0.041556 * z
    //        self.b = 0.055648 * x - 0.204043 * y + 1.057311 * z
    //    }
    
    @inlinable
    public init(packed: UInt32) {
        let a = (packed >> 24) & 0xFF
        let b = (packed >> 16) & 0xFF
        let g = (packed >> 8) & 0xFF
        let r = packed & 0xFF
        
        self.init(Float(r) / 255.0, Float(g) / 255.0, Float(b) / 255.0, Float(a) / 255.0)
    }
    
    @inlinable
    public init(r: Float, g: Float, b: Float, a: Float = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
    
    @inlinable
    public init(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
    
    @inlinable
    public init(_ value: Float, a: Float = 1.0) {
        self.r = value
        self.g = value
        self.b = value
        self.a = a
    }
    
    @inlinable
    public init(_ rgb: RGBColour, _ a: Float = 1.0) {
        self.r = rgb.r
        self.g = rgb.g
        self.b = rgb.b
        self.a = a
    }
    
    @inlinable
    public subscript(i: Int) -> Float {
        get {
            switch i {
            case 0:
                return self.r
            case 1:
                return self.g
            case 2:
                return self.b
            case 3:
                return self.a
            default:
                fatalError("Index out of bounds")
            }
        }
        set {
            switch i {
            case 0:
                self.r = newValue
            case 1:
                self.g = newValue
            case 2:
                self.b = newValue
            case 3:
                self.a = newValue
            default:
                fatalError("Index out of bounds")
            }
        }
    }
    
    @inlinable
    public var luminance: Float {
        return 0.212671 * self.r + 0.715160 * self.b + 0.072169 * self.g
    }
    
    @inlinable
    public var xyz : (x: Float, y: Float, z: Float) {
        return (
            0.412453 * self.r + 0.357580 * self.g + 0.180423 * self.b,
            0.212671 * self.r + 0.715160 * self.g + 0.072169 * self.b,
            0.019334 * self.r + 0.119193 * self.g + 0.950227 * self.b
        )
    }
    
    @inlinable
    public var rgb : RGBColour {
        get {
            return RGBColour(r: self.r, g: self.g, b: self.b)
        }
        set {
            self.r = newValue.r
            self.g = newValue.g
            self.b = newValue.b
        }
    }
    
    @inlinable
    public var packed : UInt32 {
        let w0 = clamp(self.r, min: 0, max: 1) * Float(UInt8.max)
        let w1 = clamp(self.g, min: 0, max: 1) * Float(UInt8.max)
        let w2 = clamp(self.b, min: 0, max: 1) * Float(UInt8.max)
        let w3 = clamp(self.a, min: 0, max: 1) * Float(UInt8.max)
        
        return (UInt32(w3) << 24) | (UInt32(w2) << 16) | (UInt32(w1) << 8) | UInt32(w0)
    }
}

extension RGBColour {
    @inlinable
    public static func +=(lhs: inout RGBColour, rhs: RGBColour) {
        lhs.r += rhs.r
        lhs.g += rhs.g
        lhs.b += rhs.b
    }
    
    @inlinable
    public static func +(lhs: RGBColour, rhs: RGBColour) -> RGBColour {
        var result = lhs
        result += rhs
        return result
    }
    
    @inlinable
    public static func -=(lhs: inout RGBColour, rhs: RGBColour) {
        lhs.r -= rhs.r
        lhs.g -= rhs.g
        lhs.b -= rhs.b
    }
    
    @inlinable
    public static func -(lhs: RGBColour, rhs: RGBColour) -> RGBColour {
        var result = lhs
        result -= rhs
        return result
    }
    
    @inlinable
    public static func *=(lhs: inout RGBColour, rhs: RGBColour) {
        lhs.r *= rhs.r
        lhs.g *= rhs.g
        lhs.b *= rhs.b
    }
    
    @inlinable
    public static func *(lhs: RGBColour, rhs: RGBColour) -> RGBColour {
        var result = lhs
        result *= rhs
        return result
    }
    
    @inlinable
    public static func *=(lhs: inout RGBColour, rhs: Float) {
        lhs.r *= rhs
        lhs.g *= rhs
        lhs.b *= rhs
    }
    
    @inlinable
    public static func *(lhs: RGBColour, rhs: Float) -> RGBColour {
        var result = lhs
        result *= rhs
        return result
    }
    
    @inlinable
    public static func *(lhs: Float, rhs: RGBColour) -> RGBColour {
        var result = rhs
        result *= lhs
        return result
    }
    
    @inlinable
    public static func /=(lhs: inout RGBColour, rhs: RGBColour) {
        lhs.r /= rhs.r
        lhs.g /= rhs.g
        lhs.b /= rhs.b
    }
    
    @inlinable
    public static func /(lhs: RGBColour, rhs: RGBColour) -> RGBColour {
        var result = lhs
        result /= rhs
        return result
    }
    
    @inlinable
    public static func ==(lhs: RGBColour, rhs: RGBColour) -> Bool {
        return lhs.r == rhs.r && lhs.g == rhs.g && lhs.b == rhs.b
    }
}

extension RGBAColour {
    @inlinable
    public static func +=(lhs: inout RGBAColour, rhs: RGBAColour) {
        lhs.r += rhs.r
        lhs.g += rhs.g
        lhs.b += rhs.b
        lhs.a += rhs.a
    }
    
    @inlinable
    public static func +(lhs: RGBAColour, rhs: RGBAColour) -> RGBAColour {
        var result = lhs
        result += rhs
        return result
    }
    
    @inlinable
    public static func -=(lhs: inout RGBAColour, rhs: RGBAColour) {
        lhs.r -= rhs.r
        lhs.g -= rhs.g
        lhs.b -= rhs.b
        lhs.a -= rhs.a
    }
    
    @inlinable
    public static func -(lhs: RGBAColour, rhs: RGBAColour) -> RGBAColour {
        var result = lhs
        result -= rhs
        return result
    }
    
    @inlinable
    public static func *=(lhs: inout RGBAColour, rhs: RGBAColour) {
        lhs.r *= rhs.r
        lhs.g *= rhs.g
        lhs.b *= rhs.b
        lhs.a *= rhs.a
    }
    
    @inlinable
    public static func *(lhs: RGBAColour, rhs: RGBAColour) -> RGBAColour {
        var result = lhs
        result *= rhs
        return result
    }
    
    @inlinable
    public static func *=(lhs: inout RGBAColour, rhs: Float) {
        lhs.r *= rhs
        lhs.g *= rhs
        lhs.b *= rhs
        lhs.a *= rhs
    }
    
    @inlinable
    public static func *(lhs: RGBAColour, rhs: Float) -> RGBAColour {
        var result = lhs
        result *= rhs
        return result
    }
    
    @inlinable
    public static func /=(lhs: inout RGBAColour, rhs: RGBAColour) {
        lhs.r /= rhs.r
        lhs.g /= rhs.g
        lhs.b /= rhs.b
        lhs.a /= rhs.a
    }
    
    @inlinable
    public static func /(lhs: RGBAColour, rhs: RGBAColour) -> RGBAColour {
        var result = lhs
        result /= rhs
        return result
    }
    
    @inlinable
    public static func ==(lhs: RGBAColour, rhs: RGBAColour) -> Bool {
        return lhs.r == rhs.r && lhs.g == rhs.g && lhs.b == rhs.b && lhs.a == rhs.a
    }
}

@inlinable
public func interpolate(from u: RGBColour, to v: RGBColour, factor t: Float) -> RGBColour {
    return u + (v - u) * t
}

@inlinable
public func interpolate(from u: RGBAColour, to v: RGBAColour, factor t: Float) -> RGBAColour {
    return u + (v - u) * t
}

@inlinable
public func min(_ a: RGBColour, _ b: RGBColour) -> RGBColour {
    return RGBColour(min(a.r, b.r), min(a.g, b.g), min(a.b, b.b))
}

@inlinable
public func max(_ a: RGBColour, _ b: RGBColour) -> RGBColour {
    return RGBColour(max(a.r, b.r), max(a.g, b.g), max(a.b, b.b))
}

@inlinable
public func clamp(_ x: RGBColour, min minVec: RGBColour, max maxVec: RGBColour) -> RGBColour {
    return min(max(minVec, x), maxVec)
}

// MARK: - Codable Conformance

extension RGBColour : Codable {
    @inlinable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.r)
        try container.encode(self.g)
        try container.encode(self.b)
    }
    
    @inlinable
    public init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        let r = try values.decode(Float.self)
        let g = try values.decode(Float.self)
        let b = try values.decode(Float.self)
        
        self.init(r: r, g: g, b: b)
    }
}


extension RGBAColour : Codable {
    @inlinable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.r)
        try container.encode(self.g)
        try container.encode(self.b)
        try container.encode(self.a)
    }
    
    @inlinable
    public init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        let r = try values.decode(Float.self)
        let g = try values.decode(Float.self)
        let b = try values.decode(Float.self)
        let a = try values.decode(Float.self)
        
        self.init(r: r, g: g, b: b, a: a)
    }
}
