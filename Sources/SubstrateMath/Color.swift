//
//  Color.swift
//  SwiftMath
//
//  Created by Thomas Roughton on 30/07/18.
//

import RealModule

public struct RGBColor : Equatable, Hashable, Sendable {
    public var r: Float
    public var g: Float
    public var b: Float
    @usableFromInline let a: Float
    
    @inlinable
    public init(r: Float, g: Float, b: Float) {
        self.r = r
        self.g = g
        self.b = b
        self.a = 1.0
    }
    
    @inlinable
    public init(_ r: Float, _ g: Float, _ b: Float) {
        self.r = r
        self.g = g
        self.b = b
        self.a = 1.0
    }
    
    @inlinable
    public init(_ rgb: SIMD3<Float>) {
        self.r = rgb.x
        self.g = rgb.y
        self.b = rgb.z
        self.a = 1.0
    }
    
    @inlinable
    public init(_ value: Float) {
        self.r = value
        self.g = value
        self.b = value
        self.a = 1.0
    }
    
    @inlinable
    public init(_ xyzColor: XYZColor) {
        let x = xyzColor.X, y = xyzColor.Y, z = xyzColor.Z
        self.r = 3.240479 * x - 1.537150 * y - 0.498535 * z
        self.g = -0.969256 * x + 1.875991 * y + 0.041556 * z
        self.b = 0.055648 * x - 0.204043 * y + 1.057311 * z
        self.a = 1.0
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
                preconditionFailure("Index out of bounds")
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
                preconditionFailure("Index out of bounds")
            }
        }
    }
    
    @inlinable
    public var luminance: Float {
        get {
            return 0.212671 * self.r + 0.715160 * self.g + 0.072169 * self.b
        }
        set {
            let currentLuminance = self.luminance
            if currentLuminance == 0.0 {
                self = RGBColor(newValue)
                return
            }
            
            let ratio = max(newValue, .ulpOfOne) / currentLuminance
            self *= ratio
        }
    }
    
    public var tuple : (Float, Float, Float) {
        return (
            self.r, self.g, self.b
        )
    }
    
    @inlinable
    public var sRGBToLinear: RGBColor {
        var result = RGBColor(0.0)
        for i in 0..<3 {
            result[i] = self[i] <= 0.04045 ? (self[i] / 12.92) : Float.pow((self[i] + 0.055) / 1.055, 2.4)
        }
        return result
    }
    
    @inlinable
    public var linearToSRGB: RGBColor {
        var result = RGBColor(0.0)
        for i in 0..<3 {
            result[i] = self[i] <= 0.0031308 ? (12.92 * self[i]) : (1.055 * Float.pow(self[i], 1.0 / 2.4) - 0.055)
        }
        return result
    }
}

extension RGBColor: CustomStringConvertible {
    public var description: String {
        return "RGBColor(r: \(self.r), g: \(self.g), b: \(self.b))"
    }
}

public typealias RGBColour = RGBColor

public struct XYZColor : Equatable, Hashable, Sendable {
    public var X: Float
    public var Y: Float
    public var Z: Float
    
    @inlinable
    public init(X: Float, Y: Float, Z: Float) {
        self.X = X
        self.Y = Y
        self.Z = Z
    }
    
    @inlinable
    public init(chromacity: SIMD2<Float>, Y: Float = 1.0) {
        let scaledY = Y / chromacity.y
        self.X = scaledY * chromacity.x
        self.Y = Y
        self.Z = scaledY * (1.0 - chromacity.x - chromacity.y)
    }
    
    @inlinable
    public init(_ x: Float, _ y: Float, _ z: Float) {
        self.X = x
        self.Y = y
        self.Z = z
    }
    
    @inlinable
    public init(_ XYZ: SIMD3<Float>) {
        self.X = XYZ.x
        self.Y = XYZ.y
        self.Z = XYZ.z
    }
    
    public init(_ rgbColor: RGBColor) {
        self.X = 0.412453 * rgbColor.r + 0.357580 * rgbColor.g + 0.180423 * rgbColor.b
        self.Y = 0.212671 * rgbColor.r + 0.715160 * rgbColor.g + 0.072169 * rgbColor.b
        self.Z = 0.019334 * rgbColor.r + 0.119193 * rgbColor.g + 0.950227 * rgbColor.b
    }
    
    @inlinable
    public subscript(i: Int) -> Float {
        get {
            switch i {
            case 0:
                return self.X
            case 1:
                return self.Y
            case 2:
                return self.Z
            default:
                preconditionFailure("Index out of bounds")
            }
        }
        set {
            switch i {
            case 0:
                self.X = newValue
            case 1:
                self.Y = newValue
            case 2:
                self.Z = newValue
            default:
                preconditionFailure("Index out of bounds")
            }
        }
    }
    
    @inlinable
    public var luminance: Float {
        return RGBColor(self).luminance
    }
    
    public var tuple : (Float, Float, Float) {
        return (
            self.X, self.Y, self.Z
        )
    }
    
    public var xyChromacity: SIMD2<Float> {
        let sum = self.X + self.Y + self.Z
        return SIMD2(self.X / sum, self.Y / sum)
    }
}

extension XYZColor {
    @available(*, deprecated, renamed: "X")
    public var x: Float {
        get {
            return self.X
        }
        set {
            self.X = newValue
        }
    }
    
    @available(*, deprecated, renamed: "Y")
    public var y: Float {
        get {
            return self.Y
        }
        set {
            self.Y = newValue
        }
    }
    
    @available(*, deprecated, renamed: "Z")
    public var z: Float {
        get {
            return self.Z
        }
        set {
            self.Z = newValue
        }
    }
}

public struct CIEXYZ1931ColorSpace<Scalar: BinaryFloatingPoint & Real & SIMDScalar> {
    public enum ReferenceWhite {
        case aces
        case dci
        case d65
        
        public var value: XYZColor {
            switch self {
            case .aces:
                return XYZColor(chromacity: SIMD2(0.32168, 0.33767))
            case .dci:
                return XYZColor(chromacity: SIMD2(0.3127, 0.3290))
            case .d65:
                return XYZColor(0.31271, 0.32902, 0.35827)
            }
        }
    }
    
    public struct Primaries {
        public var red: SIMD2<Scalar>
        public var green: SIMD2<Scalar>
        public var blue: SIMD2<Scalar>
        public var white: SIMD2<Scalar>
        
        public init(red: SIMD2<Scalar>, green: SIMD2<Scalar>, blue: SIMD2<Scalar>, white: SIMD2<Scalar>) {
            self.red = red
            self.green = green
            self.blue = blue
            self.white = white
        }
        
        // Reference: http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
        public var rgbToXYZMatrix: Matrix3x3<Scalar> {
            let x = SIMD4(self.red.x, self.green.x, self.blue.x, self.white.x)
            let y = SIMD4(self.red.y, self.green.y, self.blue.y, self.white.y)
            
            let X = x / y;
            let Y = SIMD4<Scalar>(repeating: 1.0)
            let Z = (1.0 - x - y) / y
            
            let whitePointTransformMatrix = Matrix3x3(X.xyz, Y.xyz, Z.xyz).transpose
            
            let S = whitePointTransformMatrix.inverse * SIMD3(X.w, Y.w, Z.w)
            
            return Matrix3x3(S.x * whitePointTransformMatrix[0],
                             S.y * whitePointTransformMatrix[1],
                             S.z * whitePointTransformMatrix[2])
        }
        
        
        public static var sRGB: Primaries {
            return Primaries(
                red:   SIMD2(0.64000,  0.33000),
                green: SIMD2(0.30000,  0.60000),
                blue:  SIMD2(0.15000,  0.06000),
                white: SIMD2(0.31270,  0.32900)) // D65
        }
        
        public static var p3: Primaries {
            return Primaries(
                red:   SIMD2(0.68000,  0.32000),
                green: SIMD2(0.26500,  0.69000),
                blue:  SIMD2(0.15000,  0.06000),
                white: SIMD2(0.31400,  0.35100)) // DCI
        }
        
        public static var aces: Primaries {
            return Primaries(
                red:   SIMD2(0.73470,  0.26530),
                green: SIMD2(0.00000,  1.00000),
                blue:  SIMD2(0.00010, -0.07700),
                white: SIMD2(0.32168,  0.33767)) // ~D60
        }
        
        public static var rec2020: Primaries {
            return Primaries(
                red:   SIMD2(0.70800,  0.29200),
                green: SIMD2(0.17000,  0.79700),
                blue:  SIMD2(0.13100,  0.04600),
                white: SIMD2(0.31270,  0.3290)) // ~D60
        }
        
        public static var sonySGamut3: Primaries {
            return Primaries(
                red:   SIMD2(0.73000,  0.28000),
                green: SIMD2(0.14000,  0.85500),
                blue:  SIMD2(0.10000, -0.05000),
                white: SIMD2(0.31270,  0.32900)) // D65
        }
        
        public static var sonySGamut3Cine: Primaries {
            return Primaries(
                red:   SIMD2(0.76600,  0.27500),
                green: SIMD2(0.22500,  0.80000),
                blue:  SIMD2(0.08900, -0.08700),
                white: SIMD2(0.31270,  0.32900)) // D65
        }
    }
    
    public enum EOTF {
        case linear
        case power(Scalar)
        case sRGB
        case sonySLog3
        
        public func linearToGamma(_ x: Scalar) -> Scalar {
            switch self {
            case .linear:
                return x
            case .power(let power):
                return Scalar.pow(x, 1.0 / power)
            case .sRGB:
                if x <= 0.0031308 {
                    return 12.92 * x
                } else {
                    return 1.055 * Scalar.pow(x, 1.0 / 2.4) - 0.055
                }
            case .sonySLog3:
                if x >= 0.01125000 {
                    return (420.0 + Scalar.log10((x + 0.01) / (0.18 + 0.01)) * 261.5) / 1023.0
                } else {
                    return (x * (171.2102946929 - 95.0)/0.01125000 + 95.0) / 1023.0
                }
            }
        }
        
        public func gammaToLinear(_ x: Scalar) -> Scalar {
            switch self {
            case .linear:
                return x
            case .power(let power):
                return Scalar.pow(x, power)
            case .sRGB:
                if x <= 0.04045 {
                    return x / 12.92
                } else {
                    return Scalar.pow((x + 0.055) / 1.055, 2.4)
                }
            case .sonySLog3:
                if x >= 171.2102946929 / 1023.0 {
                    return (Scalar.exp10((x * 1023.0 - 420.0) / 261.5)) * (0.18 + 0.01) - 0.01
                } else {
                    return (x * 1023.0 - 95.0) * 0.01125000 / (171.2102946929 - 95.0)
                }
            }
        }
    }
    
    public var primaries: Primaries
    public var eotf: EOTF
    public var referenceWhite: ReferenceWhite
    
    public static var sRGB: CIEXYZ1931ColorSpace {
        return .init(primaries: .sRGB,
                     eotf: .sRGB,
                     referenceWhite: .d65)
    }
    
    public static var dciP3: CIEXYZ1931ColorSpace {
        return .init(primaries: .p3,
                     eotf: .power(2.6),
                     referenceWhite: .dci)
    }
    
    public static var displayP3: CIEXYZ1931ColorSpace {
        return .init(primaries: .p3,
                     eotf: .sRGB,
                     referenceWhite: .d65)
    }
    
    public static var rec2020: CIEXYZ1931ColorSpace {
        return .init(primaries: .rec2020,
                     eotf: .sRGB,
                     referenceWhite: .d65)
    }
    
    public static var aces: CIEXYZ1931ColorSpace {
        return .init(primaries: .aces,
                     eotf: .linear,
                     referenceWhite: .aces)
    }
    
    public static var sonySGamut3: CIEXYZ1931ColorSpace {
        return .init(primaries: .sonySGamut3,
                     eotf: .sonySLog3,
                     referenceWhite: .d65)
    }
    
    public static var sonySGamut3Cine: CIEXYZ1931ColorSpace {
        return .init(primaries: .sonySGamut3Cine,
                     eotf: .sonySLog3,
                     referenceWhite: .d65)
    }
    
    public var rgbToXYZMatrix: Matrix3x3<Scalar> {
        return self.primaries.rgbToXYZMatrix
    }
    
    public var xyzToRGBMatrix: Matrix3x3<Scalar> {
        self.rgbToXYZMatrix.inverse
    }
    
    public static func chromaticAdaptationMatrix(from: XYZColor, to: XYZColor) -> Matrix3x3<Scalar> {
        // http://www.brucelindbloom.com/index.html?Eqn_ChromAdapt.html
        
        let Ma = Matrix3x3<Scalar>(SIMD3(0.8951000,  0.2664000, -0.1614000),
                           SIMD3(-0.7502000,  1.7135000,  0.0367000),
                           SIMD3(0.0389000, -0.0685000,  1.0296000)).transpose
        let MaInv = Matrix3x3<Scalar>(SIMD3( 0.9869929, -0.1470543, 0.1599627),
                              SIMD3( 0.4323053,  0.5183603, 0.0492912),
                              SIMD3(-0.0085287,  0.0400428, 0.9684867)).transpose
        
        let coeffSource = Ma * SIMD3<Scalar>(SIMD3(from))
        let coeffDest = Ma * SIMD3<Scalar>(SIMD3(to))
        
        return MaInv * Matrix3x3(diagonal: coeffDest / coeffSource) * Ma
    }
    
    public static func chromaticAdaptationMatrix(from: ReferenceWhite, to: ReferenceWhite) -> Matrix3x3<Scalar> {
        return self.chromaticAdaptationMatrix(from: from.value, to: to.value)
    }
}


/// Reference: https://bottosson.github.io/posts/oklab/
public struct OklabColor : Equatable, Hashable, Sendable {
    public var L: Float
    public var a: Float
    public var b: Float
    
    @inlinable
    public init(L: Float, a: Float, b: Float) {
        self.L = L
        self.a = a
        self.b = b
    }
    
    @inlinable
    public init(_ L: Float, _ a: Float, _ b: Float) {
        self.L = L
        self.a = a
        self.b = b
    }
    
    @inlinable
    public init(_ Lab: SIMD3<Float>) {
        self.L = Lab.x
        self.a = Lab.y
        self.b = Lab.z
    }
    
    public init(_ xyzColor: XYZColor) {
        let m1 = Matrix3x3<Float>(SIMD3(0.8189330101, 0.3618667424, -0.1288597137),
                                  SIMD3(0.0329845436, 0.9293118715, 0.0361456387),
                                  SIMD3(0.0482003018, 0.2643662691, 0.6338517070)).transpose
        
        let m2 = Matrix3x3<Float>(SIMD3(0.2104542553, 0.7936177850, -0.0040720468),
                                  SIMD3(1.9779984951, -2.4285922050, 0.4505937099),
                                  SIMD3(0.0259040371, 0.7827717662, -0.8086757660)).transpose
        
        let lms = m1 * SIMD3(xyzColor.X, xyzColor.Y, xyzColor.Z)
        let lms_ = SIMD3(Float.pow(lms.x, 1.0 / 3.0), Float.pow(lms.y, 1.0 / 3.0), Float.pow(lms.z, 1.0 / 3.0))
        let Lab = m2 * lms_
        self.init(Lab)
    }
    
    public init(fromLinearSRGB c: RGBColor) {
        let l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b
        let m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b
        let s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b

        let l_ = Float.pow(l, 1.0 / 3.0)
        let m_ = Float.pow(m, 1.0 / 3.0)
        let s_ = Float.pow(s, 1.0 / 3.0)

        self.init(
            L: 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            a: 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            b: 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
        )
    }
    
    @inlinable
    public var luminance: Float {
        return self.L
    }
    
    public var tuple : (Float, Float, Float) {
        return (
            self.L, self.a, self.b
        )
    }
}

extension RGBColor {
    public init(linearSRGBFrom c: OklabColor) {
        let l_ = c.L + 0.3963377774 * c.a + 0.2158037573 * c.b
        let m_ = c.L - 0.1055613458 * c.a - 0.0638541728 * c.b
        let s_ = c.L - 0.0894841775 * c.a - 1.2914855480 * c.b
        
        let l = l_ * l_ * l_
        let m = m_ * m_ * m_
        let s = s_ * s_ * s_
        
        self.init(
            r: +4.0767245293 * l - 3.3072168827 * m + 0.2307590544 * s,
            g: -1.2681437731 * l + 2.6093323231 * m - 0.3411344290 * s,
            b: -0.0041119885 * l - 0.7034763098 * m + 1.7068625689 * s
        )
    }
}

extension RGBAColor {
    public init(linearSRGBFrom c: OklabColor, alpha: Float) {
        self.init(RGBColor(linearSRGBFrom: c), alpha)
    }
}

extension XYZColor {
    public init(_ labColor: OklabColor) {
        let m1 = Matrix3x3<Float>(SIMD3(0.8189330101, 0.3618667424, -0.1288597137),
                                  SIMD3(0.0329845436, 0.9293118715, 0.0361456387),
                                  SIMD3(0.0482003018, 0.2643662691, 0.6338517070)).transpose
        
        let m2 = Matrix3x3<Float>(SIMD3(0.2104542553, 0.7936177850, -0.0040720468),
                                  SIMD3(1.9779984951, -2.4285922050, 0.4505937099),
                                  SIMD3(0.0259040371, 0.7827717662, -0.8086757660)).transpose
        
        let lms_ = m2.inverse * SIMD3(labColor.L, labColor.a, labColor.b)
        let lms = lms_ * lms_ * lms_
        let XYZ = m1.inverse * lms
        self.init(XYZ)
    }
}

public struct RGBAColor : Equatable, Hashable, Sendable {
    
    public var r: Float
    public var g: Float
    public var b: Float
    public var a: Float
    
    @inlinable
    public init(packed: UInt32) {
        let a = (packed >> UInt32(24)) & UInt32(0xFF)
        let b = (packed >> UInt32(16)) & UInt32(0xFF)
        let g = (packed >> UInt32(8))  & UInt32(0xFF)
        let r = packed & UInt32(0xFF)
        
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
    public init(rgb: SIMD3<Float>, a: Float = 1.0) {
        self.r = rgb.x
        self.g = rgb.y
        self.b = rgb.z
        self.a = a
    }
    
    @inlinable
    public init(_ rgba: SIMD4<Float>) {
        self.r = rgba.x
        self.g = rgba.y
        self.b = rgba.z
        self.a = rgba.w
    }
    
    @inlinable
    public init(_ r: Float, _ g: Float, _ b: Float, _ a: Float) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
    
    @inlinable
    public init(_ value: Float) {
        self.r = value
        self.g = value
        self.b = value
        self.a = value
    }
    
    @inlinable
    public init(value: Float, a: Float) {
        self.r = value
        self.g = value
        self.b = value
        self.a = a
    }
    
    @inlinable
    public init(_ rgb: RGBColor, _ a: Float = 1.0) {
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
                preconditionFailure("Index out of bounds")
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
                preconditionFailure("Index out of bounds")
            }
        }
    }
    
    @inlinable
    public var luminance: Float {
        return 0.212671 * self.r + 0.715160 * self.g + 0.072169 * self.b
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
    public var rgb : RGBColor {
        get {
            return RGBColor(r: self.r, g: self.g, b: self.b)
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

public typealias RGBAColour = RGBAColor

extension OklabColor {
    @inlinable
    public static func +=(lhs: inout OklabColor, rhs: OklabColor) {
        lhs.L += rhs.L
        lhs.a += rhs.a
        lhs.b += rhs.b
    }
    
    @inlinable
    public static func +(lhs: OklabColor, rhs: OklabColor) -> OklabColor {
        var result = lhs
        result += rhs
        return result
    }
    
    @inlinable
    public static func -=(lhs: inout OklabColor, rhs: OklabColor) {
        lhs.L -= rhs.L
        lhs.a -= rhs.a
        lhs.b -= rhs.b
    }
    
    @inlinable
    public static func -(lhs: OklabColor, rhs: OklabColor) -> OklabColor {
        var result = lhs
        result -= rhs
        return result
    }
    
    @inlinable
    public static func *=(lhs: inout OklabColor, rhs: OklabColor) {
        lhs.L *= rhs.L
        lhs.a *= rhs.a
        lhs.b *= rhs.b
    }
    
    @inlinable
    public static func *(lhs: OklabColor, rhs: OklabColor) -> OklabColor {
        var result = lhs
        result *= rhs
        return result
    }
    
    @inlinable
    public static func *=(lhs: inout OklabColor, rhs: Float) {
        lhs.L *= rhs
        lhs.a *= rhs
        lhs.b *= rhs
    }
    
    @inlinable
    public static func *(lhs: OklabColor, rhs: Float) -> OklabColor {
        var result = lhs
        result *= rhs
        return result
    }
    
    @inlinable
    public static func *(lhs: Float, rhs: OklabColor) -> OklabColor {
        var result = rhs
        result *= lhs
        return result
    }
    
    @inlinable
    public static func /=(lhs: inout OklabColor, rhs: OklabColor) {
        lhs.L /= rhs.L
        lhs.a /= rhs.a
        lhs.b /= rhs.b
    }
    
    @inlinable
    public static func /(lhs: OklabColor, rhs: OklabColor) -> OklabColor {
        var result = lhs
        result /= rhs
        return result
    }
    
    @inlinable
    public static func /(lhs: Float, rhs: OklabColor) -> OklabColor {
        return OklabColor(lhs / rhs.L, lhs / rhs.a, lhs / rhs.b)
    }
}

extension RGBColor {
    @inlinable
    public static prefix func -(lhs: RGBColor) -> RGBColor {
        var result = lhs
        result.r = -result.r
        result.g = -result.g
        result.b = -result.b
        return result
    }
    
    @inlinable
    public static func +=(lhs: inout RGBColor, rhs: RGBColor) {
        lhs.r += rhs.r
        lhs.g += rhs.g
        lhs.b += rhs.b
    }
    
    @inlinable
    public static func +(lhs: RGBColor, rhs: RGBColor) -> RGBColor {
        var result = lhs
        result += rhs
        return result
    }
    
    @inlinable
    public static func -=(lhs: inout RGBColor, rhs: RGBColor) {
        lhs.r -= rhs.r
        lhs.g -= rhs.g
        lhs.b -= rhs.b
    }
    
    @inlinable
    public static func -(lhs: RGBColor, rhs: RGBColor) -> RGBColor {
        var result = lhs
        result -= rhs
        return result
    }
    
    @inlinable
    public static func *=(lhs: inout RGBColor, rhs: RGBColor) {
        lhs.r *= rhs.r
        lhs.g *= rhs.g
        lhs.b *= rhs.b
    }
    
    @inlinable
    public static func *(lhs: RGBColor, rhs: RGBColor) -> RGBColor {
        var result = lhs
        result *= rhs
        return result
    }
    
    @inlinable
    public static func *=(lhs: inout RGBColor, rhs: Float) {
        lhs.r *= rhs
        lhs.g *= rhs
        lhs.b *= rhs
    }
    
    @inlinable
    public static func *(lhs: RGBColor, rhs: Float) -> RGBColor {
        var result = lhs
        result *= rhs
        return result
    }
    
    @inlinable
    public static func *(lhs: Float, rhs: RGBColor) -> RGBColor {
        var result = rhs
        result *= lhs
        return result
    }
    
    @inlinable
    public static func /=(lhs: inout RGBColor, rhs: RGBColor) {
        lhs.r /= rhs.r
        lhs.g /= rhs.g
        lhs.b /= rhs.b
    }
    
    @inlinable
    public static func /(lhs: RGBColor, rhs: RGBColor) -> RGBColor {
        var result = lhs
        result /= rhs
        return result
    }
    
    @inlinable
    public static func /(lhs: Float, rhs: RGBColor) -> RGBColor {
        return RGBColor(lhs / rhs.r, lhs / rhs.g, lhs / rhs.b)
    }
    
    @inlinable
    public static func ==(lhs: RGBColor, rhs: RGBColor) -> Bool {
        return lhs.r == rhs.r && lhs.g == rhs.g && lhs.b == rhs.b
    }
}

extension RGBAColor {
    @inlinable
    public static prefix func -(lhs: RGBAColor) -> RGBAColor {
        var result = lhs
        result.r = -result.r
        result.g = -result.g
        result.b = -result.b
        result.a = -result.a
        return result
    }
    
    @inlinable
    public static func +=(lhs: inout RGBAColor, rhs: RGBAColor) {
        lhs.r += rhs.r
        lhs.g += rhs.g
        lhs.b += rhs.b
        lhs.a += rhs.a
    }
    
    @inlinable
    public static func +(lhs: RGBAColor, rhs: RGBAColor) -> RGBAColor {
        var result = lhs
        result += rhs
        return result
    }
    
    @inlinable
    public static func -=(lhs: inout RGBAColor, rhs: RGBAColor) {
        lhs.r -= rhs.r
        lhs.g -= rhs.g
        lhs.b -= rhs.b
        lhs.a -= rhs.a
    }
    
    @inlinable
    public static func -(lhs: RGBAColor, rhs: RGBAColor) -> RGBAColor {
        var result = lhs
        result -= rhs
        return result
    }
    
    @inlinable
    public static func *=(lhs: inout RGBAColor, rhs: RGBAColor) {
        lhs.r *= rhs.r
        lhs.g *= rhs.g
        lhs.b *= rhs.b
        lhs.a *= rhs.a
    }
    
    @inlinable
    public static func *(lhs: RGBAColor, rhs: RGBAColor) -> RGBAColor {
        var result = lhs
        result *= rhs
        return result
    }
    
    @inlinable
    public static func *=(lhs: inout RGBAColor, rhs: Float) {
        lhs.r *= rhs
        lhs.g *= rhs
        lhs.b *= rhs
        lhs.a *= rhs
    }
    
    @inlinable
    public static func *(lhs: RGBAColor, rhs: Float) -> RGBAColor {
        var result = lhs
        result *= rhs
        return result
    }
    
    @inlinable
    public static func /=(lhs: inout RGBAColor, rhs: RGBAColor) {
        lhs.r /= rhs.r
        lhs.g /= rhs.g
        lhs.b /= rhs.b
        lhs.a /= rhs.a
    }
    
    @inlinable
    public static func /(lhs: RGBAColor, rhs: RGBAColor) -> RGBAColor {
        var result = lhs
        result /= rhs
        return result
    }
    
    @inlinable
    public static func /(lhs: Float, rhs: RGBAColor) -> RGBAColor {
        return RGBAColor(lhs / rhs.r, lhs / rhs.g, lhs / rhs.b, lhs / rhs.a)
    }
    
    @inlinable
    public static func ==(lhs: RGBAColor, rhs: RGBAColor) -> Bool {
        return lhs.r == rhs.r && lhs.g == rhs.g && lhs.b == rhs.b && lhs.a == rhs.a
    }
}

extension SIMD3 where Scalar == Float {
    @inlinable
    public init(_ colour: RGBColor) {
        self.init(colour.r, colour.g, colour.b)
    }
}

extension SIMD3 where Scalar == Float {
    @inlinable
    public init(_ colour: OklabColor) {
        self.init(colour.L, colour.a, colour.b)
    }
}

extension SIMD3 where Scalar == Float {
    @inlinable
    public init(_ colour: XYZColor) {
        self.init(colour.X, colour.Y, colour.Z)
    }
}

extension SIMD4 where Scalar == Float {
    @inlinable
    public init(_ colour: RGBAColor) {
        self.init(colour.r, colour.g, colour.b, colour.a)
    }
}

@inlinable
public func interpolate(from u: RGBColor, to v: RGBColor, factor t: Float) -> RGBColor {
    return u + (v - u) * t
}

@inlinable
public func interpolateOklabSpace(from u: RGBColor, to v: RGBColor, factor t: Float) -> RGBColor {
    return RGBColor(linearSRGBFrom: interpolate(from: OklabColor(fromLinearSRGB: u), to: OklabColor(fromLinearSRGB: v), factor: t))
}

@inlinable
public func interpolate(from u: OklabColor, to v: OklabColor, factor t: Float) -> OklabColor {
    return u + (v - u) * t
}

@inlinable
public func interpolate(from u: RGBAColor, to v: RGBAColor, factor t: Float) -> RGBAColor {
    return u + (v - u) * t
}

@inlinable
public func min(_ a: RGBColor, _ b: RGBColor) -> RGBColor {
    return RGBColor(min(a.r, b.r), min(a.g, b.g), min(a.b, b.b))
}

@inlinable
public func max(_ a: RGBColor, _ b: RGBColor) -> RGBColor {
    return RGBColor(max(a.r, b.r), max(a.g, b.g), max(a.b, b.b))
}

@inlinable
public func clamp(_ x: RGBColor, min minVec: RGBColor, max maxVec: RGBColor) -> RGBColor {
    return min(max(minVec, x), maxVec)
}

@inlinable
public func min(_ a: RGBAColor, _ b: RGBAColor) -> RGBAColor {
    return RGBAColor(min(a.r, b.r), min(a.g, b.g), min(a.b, b.b), min(a.a, b.a))
}

@inlinable
public func max(_ a: RGBAColor, _ b: RGBAColor) -> RGBAColor {
    return RGBAColor(max(a.r, b.r), max(a.g, b.g), max(a.b, b.b), max(a.a, b.a))
}

@inlinable
public func clamp(_ x: RGBAColor, min minVec: RGBAColor, max maxVec: RGBAColor) -> RGBAColor {
    return min(max(minVec, x), maxVec)
}

@inlinable
public func min(_ a: OklabColor, _ b: OklabColor) -> OklabColor {
    return OklabColor(min(a.L, b.L), min(a.a, b.a), min(a.b, b.b))
}

@inlinable
public func max(_ a: OklabColor, _ b: OklabColor) -> OklabColor {
    return OklabColor(max(a.L, b.L), max(a.a, b.a), max(a.b, b.b))
}

@inlinable
public func clamp(_ x: OklabColor, min minVec: OklabColor, max maxVec: OklabColor) -> OklabColor {
    return min(max(minVec, x), maxVec)
}

@inlinable
public func min(_ a: XYZColor, _ b: XYZColor) -> XYZColor {
    return XYZColor(min(a.X, b.X), min(a.Y, b.Y), min(a.Z, b.Z))
}

@inlinable
public func max(_ a: XYZColor, _ b: XYZColor) -> XYZColor {
    return XYZColor(max(a.X, b.X), max(a.Y, b.Y), max(a.Z, b.Z))
}

@inlinable
public func clamp(_ x: XYZColor, min minVec: XYZColor, max maxVec: XYZColor) -> XYZColor {
    return min(max(minVec, x), maxVec)
}

// MARK: - Codable Conformance

extension RGBColor : Codable {
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


extension XYZColor : Codable {
    @inlinable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.X)
        try container.encode(self.Y)
        try container.encode(self.Z)
    }
    
    @inlinable
    public init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        let x = try values.decode(Float.self)
        let y = try values.decode(Float.self)
        let z = try values.decode(Float.self)
        
        self.init(X: x, Y: y, Z: z)
    }
}

extension OklabColor : Codable {
    @inlinable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.L)
        try container.encode(self.a)
        try container.encode(self.b)
    }
    
    @inlinable
    public init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        let L = try values.decode(Float.self)
        let a = try values.decode(Float.self)
        let b = try values.decode(Float.self)
        
        self.init(L: L, a: a, b: b)
    }
}

extension RGBAColor : Codable {
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
