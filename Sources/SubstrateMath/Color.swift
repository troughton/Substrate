//
//  Color.swift
//  SwiftMath
//
//  Created by Thomas Roughton on 30/07/18.
//

import RealModule

public struct RGBColor<Scalar: BinaryFloatingPoint & Real & SIMDScalar> {
    @usableFromInline var storage: SIMD3<Scalar>
    
    @inlinable
    public var r: Scalar {
        @inline(__always) get {
            storage.x
        }
        @inline(__always) set {
            storage.x = newValue
        }
    }
    
    @inlinable
    public var g: Scalar {
        @inline(__always) get {
            storage.y
        }
        @inline(__always) set {
            storage.y = newValue
        }
    }
    
    @inlinable
    public var b: Scalar {
        @inline(__always) get {
            storage.z
        }
        @inline(__always) set {
            storage.z = newValue
        }
    }
    
    @inlinable
    public init(r: Scalar, g: Scalar, b: Scalar) {
        self.storage = SIMD3(r, g, b)
    }
    
    @inlinable
    public init(_ r: Scalar, _ g: Scalar, _ b: Scalar) {
        self.storage = SIMD3(r, g, b)
    }
    
    @inlinable
    public init(_ value: Scalar) {
        self.storage = SIMD3(repeating: value)
    }
    
    @inlinable
    public init(_ rgb: SIMD3<Scalar>) {
        self.storage = rgb
    }
    
    @inlinable
    public init(_ xyzColor: XYZColor<Scalar>) {
        let x = xyzColor.X, y = xyzColor.Y, z = xyzColor.Z
        let r = 3.240479 * x - 1.537150 * y - 0.498535 * z
        let g = -0.969256 * x + 1.875991 * y + 0.041556 * z
        let b = 0.055648 * x - 0.204043 * y + 1.057311 * z
        self.init(r, g, b)
    }
    
    @inlinable
    public subscript(i: Int) -> Scalar {
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
    public var luminance: Scalar {
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
    
    public var tuple : (Scalar, Scalar, Scalar) {
        return (
            self.r, self.g, self.b
        )
    }
    
    @inlinable
    public func decoded(using transferFunction: ColorTransferFunction<Scalar>) -> RGBColor {
        var result = RGBColor(0.0)
        for i in 0..<3 {
            result[i] = transferFunction.encodedToLinear(self[i])
        }
        return result
    }
    
    @inlinable
    public func encoded(using transferFunction: ColorTransferFunction<Scalar>) -> RGBColor {
        var result = RGBColor(0.0)
        for i in 0..<3 {
            result[i] = transferFunction.linearToEncoded(self[i])
        }
        return result
    }
    
    @inlinable
    public func converted(from inputColorSpace: CIEXYZ1931ColorSpace<Scalar>, to outputColorSpace: CIEXYZ1931ColorSpace<Scalar>) -> RGBColor<Scalar> {
        return CIEXYZ1931ColorSpace.convert(self, from: inputColorSpace, to: outputColorSpace)
    }
    
    @available(*, deprecated, renamed: "decoded(using:)")
    @inlinable
    public var sRGBToLinear: RGBColor {
        return self.decoded(using: .sRGB)
    }
    
    @available(*, deprecated, renamed: "encoded(using:)")
    @inlinable
    public var linearToSRGB: RGBColor {
        return self.encoded(using: .sRGB)
    }
}

extension RGBColor: Equatable where Scalar: Equatable {}
extension RGBColor: Hashable where Scalar: Hashable {}
extension RGBColor: Sendable where Scalar: Sendable {}

extension RGBColor: CustomStringConvertible {
    public var description: String {
        return "RGBColor(r: \(self.r), g: \(self.g), b: \(self.b))"
    }
}

public typealias RGBColour = RGBColor

public struct XYZColor<Scalar: BinaryFloatingPoint & Real> {
    public var X: Scalar
    public var Y: Scalar
    public var Z: Scalar
    
    @inlinable
    public init(X: Scalar, Y: Scalar, Z: Scalar) {
        self.X = X
        self.Y = Y
        self.Z = Z
    }
    
    @inlinable
    public init(_ x: Scalar, _ y: Scalar, _ z: Scalar) {
        self.X = x
        self.Y = y
        self.Z = z
    }
    
    @inlinable
    public subscript(i: Int) -> Scalar {
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
    public var luminance: Scalar {
        return self.Y
    }
    
    @inlinable
    public var tuple : (Scalar, Scalar, Scalar) {
        return (
            self.X, self.Y, self.Z
        )
    }
}

extension XYZColor: Equatable where Scalar: Equatable {}
extension XYZColor: Hashable where Scalar: Hashable {}
extension XYZColor: Sendable where Scalar: Sendable {}

extension XYZColor where Scalar: SIMDScalar {
    @inlinable
    public init(_ XYZ: SIMD3<Scalar>) {
        self.X = XYZ.x
        self.Y = XYZ.y
        self.Z = XYZ.z
    }
    
    @inlinable
    public init(chromacity: SIMD2<Scalar>, Y: Scalar = 1.0) {
        let scaledY = Y / chromacity.y
        self.X = scaledY * chromacity.x
        self.Y = Y
        self.Z = scaledY * (1.0 - chromacity.x - chromacity.y)
    }
    
    @inlinable
    public init(_ rgbColor: RGBColor<Scalar>, colorSpace: CIEXYZ1931ColorSpace<Scalar>) {
        let matrix = colorSpace.rgbToXYZMatrix
        let XYZ = matrix * SIMD3(rgbColor)
        
        self.X = XYZ.x
        self.Y = XYZ.y
        self.Z = XYZ.z
    }
    
    @inlinable
    public var xyChromacity: SIMD2<Scalar> {
        let sum = self.X + self.Y + self.Z
        return SIMD2(self.X / sum, self.Y / sum)
    }
}

public enum ColorTransferFunction<Scalar: BinaryFloatingPoint & Real> {
    case linear
    case power(Scalar)
    case acesCC
    case acesCCT
    case sRGB
    case rec709
    case sonySLog3
    case pq
    case hlg
    
    public static var rec2020: ColorTransferFunction { return .rec709 }
    
    /// This is the OETF (opto-electronic transfer function) that converts linear light into an encoded signal.
    public func linearToEncoded(_ x: Scalar) -> Scalar {
        switch self {
        case .linear:
            return x
        case .power(let power):
            return Scalar.pow(x, 1.0 / power)
        case .acesCC:
            if x <= 0 {
                return (-16.0 + 9.72) / 17.52
            } else if x < Scalar.exp2(-15.0) {
                return (Scalar.log2(Scalar.exp2(-16.0) + 0.5 * x) + 9.72) / 17.52
            } else {
                return (Scalar.log2(x) + 9.72) / 17.52
            }
        case .acesCCT:
            if x <= 0.0078125 {
                return 10.5402337416545 * x + 0.0729055341958355
            } else {
                return (Scalar.log2(x) + 9.72) / 17.52
            }
        case .sRGB:
            if x <= 0.0031308 {
                return 12.92 * x
            } else {
                return 1.055 * Scalar.pow(x, 1.0 / 2.4) - 0.055
            }
        case .rec709:
            let alpha: Scalar = 1.09929682680944
            let beta: Scalar = 0.018053968510807
            if x < beta {
                return 4.5 * x
            } else {
                return alpha * Scalar.pow(x, 0.45) - (alpha - 1.0)
            }
        case .sonySLog3:
            if x >= 0.01125000 {
                return (420.0 + Scalar.log10((x + 0.01) / (0.18 + 0.01)) * 261.5) / 1023.0
            } else {
                let scale: Scalar = (171.2102946929 - 95.0)/0.01125000
                return (x * scale + 95.0) / 1023.0
            }
        case .pq:
            let m1: Scalar = 1305.0 / 8192.0
            let m2: Scalar = 2523.0 / 32.0
            let c1: Scalar = 107.0 / 128.0
            let c2: Scalar = 2413.0 / 128.0
            let c3: Scalar = 2392.0 / 128.0
            
            let Y = x / 10_000.0
            let Ym1 = Scalar.pow(Y, m1)
            let numerator = c1 + c2 * Ym1
            let denominator = 1.0 + c3 * Ym1
            return Scalar.pow(numerator / denominator, m2)
        case .hlg:
            let E = x
            let a: Scalar = 0.17883277
            let b: Scalar = 0.28466892
            let c: Scalar = 0.55991073
            
            if E < 1.0 / 12.0 {
                return Scalar.sqrt(3.0 * E)
            } else {
                return a * Scalar.log(12.0 * E - b) + c
            }
        }
    }
    
    /// This is the EOTF (electro-optical transfer function) that converts an encoded signal into linear light.
    public func encodedToLinear(_ x: Scalar) -> Scalar {
        switch self {
        case .linear:
            return x
        case .power(let power):
            return Scalar.pow(x, power)
        case .acesCC:
            if x <= -0.301369863014 {
                return 2.0 * (Scalar.exp2(x * 17.52 - 9.72) - Scalar.exp2(-16.0))
            } else if x < 1.46799631204 {
                return Scalar.exp2(x * 17.52 - 9.72)
            } else {
                return 65504.0
            }
        case .acesCCT:
            if x <= 0.155251141552511 {
                return (x - 0.0729055341958355) / 10.5402337416545
            } else if x < 1.46799631204 {
                return Scalar.exp2(x * 17.52 - 9.72)
            } else {
                return 65504.0
            }
        case .sRGB:
            if x <= 0.04045 {
                return x / 12.92
            } else {
                return Scalar.pow((x + 0.055) / 1.055, 2.4)
            }
        case .rec709:
            let alpha: Scalar = 1.09929682680944
            let beta: Scalar = 0.018053968510807
            if x < 4.5 * beta {
                return x / 4.5
            } else {
                return Scalar.pow((x + (alpha - 1.0)) / alpha, 1.0 / 0.45)
            }
        case .sonySLog3:
            if x >= 171.2102946929 / 1023.0 {
                return (Scalar.exp10((x * 1023.0 - 420.0) / 261.5)) * (0.18 + 0.01) - 0.01
            } else {
                let scale: Scalar = 0.01125000 / (171.2102946929 - 95.0)
                return (x * 1023.0 - 95.0) * scale
            }
        case .pq:
            let m1: Scalar = 1305.0 / 8192.0
            let m2: Scalar = 2523.0 / 32.0
            let c1: Scalar = 107.0 / 128.0
            let c2: Scalar = 2413.0 / 128.0
            let c3: Scalar = 2392.0 / 128.0
            
            let inverse = self.linearToEncoded(x)
            let numerator = max(Scalar.pow(inverse, 1.0 / m2) - c1, 0.0)
            let denominator = c2 - c3 * Scalar.pow(inverse, 1.0 / m2)
            
            return 10_000.0 * Scalar.pow(numerator / denominator, 1.0 / m1)
        case .hlg:
            // NOTE: this ignores any display-specific settings and simply remaps using the inverse of the OETF.
            let a: Scalar = 0.17883277
            let b: Scalar = 0.28466892
            let c: Scalar = 0.55991073
            
            if x < 0.5 {
                return x * x / 3.0
            } else {
                // x = a * Scalar.log(12.0 * E - b) + c
                // (x - c) / a = log(12.0 * E - b)
                // exp((x - c) / a) + b = 12.0 * E
                return Scalar.exp((x - c) / a + b) / 12.0
            }
            
        }
    }
}

public struct CIEXYZ1931ColorSpace<Scalar: BinaryFloatingPoint & Real & SIMDScalar> {
    public struct ReferenceWhite: Hashable {
        public var chromacity: SIMD2<Scalar>
        
        @inlinable
        public init(chromacity: SIMD2<Scalar>) {
            self.chromacity = chromacity
        }
        
        @inlinable
        public static var aces: ReferenceWhite {
            return ReferenceWhite(chromacity: SIMD2(0.32168, 0.33767))
        }
        
        @inlinable
        public static var dci: ReferenceWhite {
            return ReferenceWhite(chromacity: SIMD2(0.314, 0.351))
        }
        
        @inlinable
        public static var d65: ReferenceWhite {
            return ReferenceWhite(chromacity: SIMD2(0.31271, 0.32902))
        }
        
        public var value: XYZColor<Scalar> {
            return XYZColor(chromacity: self.chromacity)
        }
    }
    
    public struct Primaries {
        public var red: SIMD2<Scalar>
        public var green: SIMD2<Scalar>
        public var blue: SIMD2<Scalar>
        
        @inlinable
        public init(red: SIMD2<Scalar>, green: SIMD2<Scalar>, blue: SIMD2<Scalar>) {
            self.red = red
            self.green = green
            self.blue = blue
        }
        
        @inlinable
        public static var sRGB: Primaries {
            return Primaries(
                red:   SIMD2(0.64000,  0.33000),
                green: SIMD2(0.30000,  0.60000),
                blue:  SIMD2(0.15000,  0.06000))
        }
        
        @inlinable
        public static var p3: Primaries {
            return Primaries(
                red:   SIMD2(0.68000,  0.32000),
                green: SIMD2(0.26500,  0.69000),
                blue:  SIMD2(0.15000,  0.06000))
        }
        
        @inlinable
        public static var acesAP0: Primaries {
            return Primaries(
                red:   SIMD2(0.73470,  0.26530),
                green: SIMD2(0.00000,  1.00000),
                blue:  SIMD2(0.00010, -0.07700))
        }
        
        
        @inlinable
        public static var acesAP1: Primaries {
            return Primaries(
                red:   SIMD2(0.71300,  0.29300),
                green: SIMD2(0.16500,  0.83000),
                blue:  SIMD2(0.12800,  0.04400))
        }
        
        @inlinable
        public static var rec2020: Primaries {
            return Primaries(
                red:   SIMD2(0.70800,  0.29200),
                green: SIMD2(0.17000,  0.79700),
                blue:  SIMD2(0.13100,  0.04600))
        }
        
        @inlinable
        public static var sonySGamut3: Primaries {
            return Primaries(
                red:   SIMD2(0.73000,  0.28000),
                green: SIMD2(0.14000,  0.85500),
                blue:  SIMD2(0.10000, -0.05000))
        }
        
        @inlinable
        public static var sonySGamut3Cine: Primaries {
            return Primaries(
                red:   SIMD2(0.76600,  0.27500),
                green: SIMD2(0.22500,  0.80000),
                blue:  SIMD2(0.08900, -0.08700))
        }
    }
    
    public struct ConversionContext {
        public var matrix: Matrix3x3<Scalar>?
        public var inputColorTransferFunction: ColorTransferFunction<Scalar>
        public var outputColorTransferFunction: ColorTransferFunction<Scalar>
        
        public static func converting(from inputColorSpace: CIEXYZ1931ColorSpace, to outputColorSpace: CIEXYZ1931ColorSpace) -> ConversionContext {
            if inputColorSpace == outputColorSpace {
                return .init(matrix: nil, inputColorTransferFunction: .linear, outputColorTransferFunction: .linear)
            }
            
            var matrix = inputColorSpace.rgbToXYZMatrix
            if inputColorSpace.referenceWhite != outputColorSpace.referenceWhite {
                matrix = CIEXYZ1931ColorSpace.chromaticAdaptationMatrix(from: XYZColor(chromacity: SIMD2(inputColorSpace.referenceWhite.chromacity)), to: XYZColor(chromacity: SIMD2(outputColorSpace.referenceWhite.chromacity))) * matrix
            }
            matrix = outputColorSpace.xyzToRGBMatrix * matrix
            return ConversionContext(matrix: matrix, inputColorTransferFunction: inputColorSpace.eotf, outputColorTransferFunction: outputColorSpace.eotf)
        }
        
        public func convert(_ input: RGBColor<Scalar>) -> RGBColor<Scalar> {
            var linear = SIMD3(input)
            if self.inputColorTransferFunction != .linear {
                for i in 0..<linear.scalarCount {
                    linear[i] = self.inputColorTransferFunction.encodedToLinear(input[i])
                }
            }
            
            if let matrix = self.matrix {
                linear = matrix * linear
            }
            
            var gamma = linear
            if self.outputColorTransferFunction != .linear {
                for i in 0..<gamma.scalarCount {
                    gamma[i] = self.outputColorTransferFunction.linearToEncoded(linear[i])
                }
            }
            return RGBColor(gamma)
        }
    }
    
    public var primaries: Primaries
    public var referenceWhite: ReferenceWhite
    public var eotf: ColorTransferFunction<Scalar>
    
    public init(primaries: Primaries, eotf: ColorTransferFunction<Scalar>, referenceWhite: ReferenceWhite) {
        self.primaries = primaries
        self.eotf = eotf
        self.referenceWhite = referenceWhite
    }
    
    public static var rec709: CIEXYZ1931ColorSpace {
        return .init(primaries: .sRGB,
                     eotf: .rec709,
                     referenceWhite: .d65)
    }
    
    public static var sRGB: CIEXYZ1931ColorSpace {
        return .init(primaries: .sRGB,
                     eotf: .sRGB,
                     referenceWhite: .d65)
    }
    
    public static var linearSRGB: CIEXYZ1931ColorSpace {
        return .init(primaries: .sRGB,
                     eotf: .linear,
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
                     eotf: .rec2020,
                     referenceWhite: .d65)
    }
    
    public static var aces: CIEXYZ1931ColorSpace {
        return .init(primaries: .acesAP0,
                     eotf: .linear,
                     referenceWhite: .aces)
    }
    
    public static var acesCC: CIEXYZ1931ColorSpace {
        return .init(primaries: .acesAP1,
                     eotf: .acesCC,
                     referenceWhite: .aces)
    }
    
    public static var acesCCT: CIEXYZ1931ColorSpace {
        return .init(primaries: .acesAP1,
                     eotf: .acesCCT,
                     referenceWhite: .aces)
    }
    
    public static var acesCG: CIEXYZ1931ColorSpace {
        return .init(primaries: .acesAP1,
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
    
    // Reference: http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    public var rgbToXYZMatrix: Matrix3x3<Scalar> {
        let x = SIMD4(self.primaries.red.x, self.primaries.green.x, self.primaries.blue.x, self.referenceWhite.chromacity.x)
        let y = SIMD4(self.primaries.red.y, self.primaries.green.y, self.primaries.blue.y, self.referenceWhite.chromacity.y)
        
        let X = x / y;
        let Y = SIMD4<Scalar>(repeating: 1.0)
        let Z = (1.0 - x - y) / y
        
        let whitePointTransformMatrix = Matrix3x3(X.xyz, Y.xyz, Z.xyz).transpose
        
        let S = whitePointTransformMatrix.inverse * SIMD3(X.w, Y.w, Z.w)
        
        return Matrix3x3(S.x * whitePointTransformMatrix[0],
                         S.y * whitePointTransformMatrix[1],
                         S.z * whitePointTransformMatrix[2])
    }
    
    public var xyzToRGBMatrix: Matrix3x3<Scalar> {
        self.rgbToXYZMatrix.inverse
    }
    
    public static func chromaticAdaptationMatrix(from: XYZColor<Scalar>, to: XYZColor<Scalar>) -> Matrix3x3<Scalar> {
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
    
    public static func conversionContext(convertingFrom inputColorSpace: CIEXYZ1931ColorSpace, to outputColorSpace: CIEXYZ1931ColorSpace) -> ConversionContext {
        return .converting(from: inputColorSpace, to: outputColorSpace)
    }
    
    public static func convert(_ value: RGBColor<Scalar>, from inputColorSpace: CIEXYZ1931ColorSpace, to outputColorSpace: CIEXYZ1931ColorSpace) -> RGBColor<Scalar> {
        return ConversionContext.converting(from: inputColorSpace, to: outputColorSpace).convert(value)
    }
}

extension CIEXYZ1931ColorSpace.Primaries: Equatable where Scalar: Equatable {}
extension CIEXYZ1931ColorSpace.Primaries: Hashable where Scalar: Hashable {}
extension CIEXYZ1931ColorSpace.Primaries: Sendable where Scalar: Sendable {}

extension ColorTransferFunction: Equatable where Scalar: Equatable {}
extension ColorTransferFunction: Hashable where Scalar: Hashable {}
extension ColorTransferFunction: Sendable where Scalar: Sendable {}

extension CIEXYZ1931ColorSpace: Equatable where Scalar: Equatable {}
extension CIEXYZ1931ColorSpace: Hashable where Scalar: Hashable {}
extension CIEXYZ1931ColorSpace: Sendable where Scalar: Sendable {}

extension CIEXYZ1931ColorSpace.ConversionContext: Sendable where Scalar: Sendable {}

/// Reference: https://bottosson.github.io/posts/oklab/
public struct OklabColor<Scalar: BinaryFloatingPoint & Real> {
    public var L: Scalar
    public var a: Scalar
    public var b: Scalar
    
    @inlinable
    public init(L: Scalar, a: Scalar, b: Scalar) {
        self.L = L
        self.a = a
        self.b = b
    }
    
    @inlinable
    public init(_ L: Scalar, _ a: Scalar, _ b: Scalar) {
        self.L = L
        self.a = a
        self.b = b
    }
    
    @inlinable
    public var luminance: Scalar {
        return self.L
    }
    
    public var tuple : (Scalar, Scalar, Scalar) {
        return (
            self.L, self.a, self.b
        )
    }
}

extension OklabColor: Equatable where Scalar: Equatable {}
extension OklabColor: Hashable where Scalar: Hashable {}
extension OklabColor: Sendable where Scalar: Sendable {}

extension OklabColor where Scalar: SIMDScalar {
    public init(fromLinearSRGB c: RGBColor<Scalar>)  {
        let l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b
        let m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b
        let s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b

        let l_ = Scalar.pow(l, 1.0 / 3.0)
        let m_ = Scalar.pow(m, 1.0 / 3.0)
        let s_ = Scalar.pow(s, 1.0 / 3.0)

        let L: Scalar = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
        let a: Scalar = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
        let b: Scalar = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
        self.init(L: L, a: a, b: b)
    }
    
    @inlinable
    public init(_ Lab: SIMD3<Scalar>) {
        self.L = Lab.x
        self.a = Lab.y
        self.b = Lab.z
    }
    
    @inlinable
    @_specialize(where Scalar == Float)
    public init(_ xyzColor: XYZColor<Scalar>) {
        let m1 = Matrix3x3<Scalar>(SIMD3(0.8189330101, 0.3618667424, -0.1288597137),
                                  SIMD3(0.0329845436, 0.9293118715, 0.0361456387),
                                  SIMD3(0.0482003018, 0.2643662691, 0.6338517070)).transpose
        
        let m2 = Matrix3x3<Scalar>(SIMD3(0.2104542553, 0.7936177850, -0.0040720468),
                                  SIMD3(1.9779984951, -2.4285922050, 0.4505937099),
                                  SIMD3(0.0259040371, 0.7827717662, -0.8086757660)).transpose
        
        let lms = m1 * SIMD3(xyzColor.X, xyzColor.Y, xyzColor.Z)
        let lms_ = SIMD3(Scalar.pow(lms.x, 1.0 / 3.0), Scalar.pow(lms.y, 1.0 / 3.0), Scalar.pow(lms.z, 1.0 / 3.0))
        let Lab = m2 * lms_
        self.init(Lab)
    }
    
    public init(_ rgbColor: RGBColor<Scalar>, sourceColorSpace: CIEXYZ1931ColorSpace<Scalar>) {
        if sourceColorSpace.eotf == .linear, sourceColorSpace.primaries == .sRGB, sourceColorSpace.referenceWhite == .d65 {
            self.init(fromLinearSRGB: rgbColor)
        } else {
            let matrix = sourceColorSpace.rgbToXYZMatrix
            var xyzColor = matrix * SIMD3(rgbColor)
            
            if sourceColorSpace.referenceWhite != .d65 {
                xyzColor = CIEXYZ1931ColorSpace.chromaticAdaptationMatrix(from: sourceColorSpace.referenceWhite, to: .d65) * xyzColor
            }
            
            self.init(XYZColor(xyzColor))
        }
    }
}

extension RGBColor {
    public init(linearSRGBFrom c: OklabColor<Scalar>) {
        let l_ = c.L + 0.3963377774 * c.a + 0.2158037573 * c.b
        let m_ = c.L - 0.1055613458 * c.a - 0.0638541728 * c.b
        let s_ = c.L - 0.0894841775 * c.a - 1.2914855480 * c.b
        
        let l = l_ * l_ * l_
        let m = m_ * m_ * m_
        let s = s_ * s_ * s_
        
        let r: Scalar = +4.0767245293 * l - 3.3072168827 * m + 0.2307590544 * s
        let g: Scalar = -1.2681437731 * l + 2.6093323231 * m - 0.3411344290 * s
        let b: Scalar = -0.0041119885 * l - 0.7034763098 * m + 1.7068625689 * s
        self.init(
            r: r,
            g: g,
            b: b
        )
    }
}

extension RGBAColor {
    public init(linearSRGBFrom c: OklabColor<Scalar>, alpha: Scalar) {
        self.init(RGBColor(linearSRGBFrom: c), alpha)
    }
}

extension XYZColor where Scalar == Float {
    /// Returns a CIE 1931 XYZ color with a D65 white point.
    public init(_ labColor: OklabColor<Scalar>) {
        let m1 = Matrix3x3<Scalar>(SIMD3(0.8189330101, 0.3618667424, -0.1288597137),
                                  SIMD3(0.0329845436, 0.9293118715, 0.0361456387),
                                  SIMD3(0.0482003018, 0.2643662691, 0.6338517070)).transpose
        
        let m2 = Matrix3x3<Scalar>(SIMD3(0.2104542553, 0.7936177850, -0.0040720468),
                                  SIMD3(1.9779984951, -2.4285922050, 0.4505937099),
                                  SIMD3(0.0259040371, 0.7827717662, -0.8086757660)).transpose
        
        let lms_ = m2.inverse * SIMD3(labColor.L, labColor.a, labColor.b)
        let lms = lms_ * lms_ * lms_
        let XYZ = m1.inverse * lms
        self.init(XYZ)
    }
}

public struct RGBAColor<Scalar: BinaryFloatingPoint & Real & SIMDScalar> {
    public var r: Scalar
    public var g: Scalar
    public var b: Scalar
    public var a: Scalar
    
    @inlinable
    public init(r: Scalar, g: Scalar, b: Scalar, a: Scalar = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
    
    @inlinable
    public init(_ r: Scalar, _ g: Scalar, _ b: Scalar, _ a: Scalar) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
    
    @inlinable
    public init(_ value: Scalar) {
        self.r = value
        self.g = value
        self.b = value
        self.a = value
    }
    
    @inlinable
    public init(value: Scalar, a: Scalar) {
        self.r = value
        self.g = value
        self.b = value
        self.a = a
    }
    
    @inlinable
    public init(_ rgb: RGBColor<Scalar>, _ a: Scalar = 1.0) {
        self.r = rgb.r
        self.g = rgb.g
        self.b = rgb.b
        self.a = a
    }
    
    @inlinable
    public subscript(i: Int) -> Scalar {
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
    public var luminance: Scalar {
        return 0.212671 * self.r + 0.715160 * self.g + 0.072169 * self.b
    }
    
    @inlinable
    public var rgb : RGBColor<Scalar> {
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
    public init(rgb: SIMD3<Scalar>, a: Scalar = 1.0) {
        self.r = rgb.x
        self.g = rgb.y
        self.b = rgb.z
        self.a = a
    }
    
    @inlinable
    public init(_ rgba: SIMD4<Scalar>) {
        self.r = rgba.x
        self.g = rgba.y
        self.b = rgba.z
        self.a = rgba.w
    }
}

extension RGBAColor: Equatable where Scalar: Equatable {}
extension RGBAColor: Hashable where Scalar: Hashable {}
extension RGBAColor: Sendable where Scalar: Sendable {}

public typealias RGBAColour = RGBAColor

extension RGBAColor where Scalar == Float {
    @inlinable
    public init(packed: UInt32) {
        let a = (packed >> UInt32(24)) & UInt32(0xFF)
        let b = (packed >> UInt32(16)) & UInt32(0xFF)
        let g = (packed >> UInt32(8))  & UInt32(0xFF)
        let r = packed & UInt32(0xFF)
        
        self.init(Float(r) / 255.0, Float(g) / 255.0, Float(b) / 255.0, Float(a) / 255.0)
    }
    
    @inlinable
    public var packed : UInt32 {
        let w0 = clamp(self.r, min: 0, max: 1) * Float(UInt8.max) + 0.5
        let w1 = clamp(self.g, min: 0, max: 1) * Float(UInt8.max) + 0.5
        let w2 = clamp(self.b, min: 0, max: 1) * Float(UInt8.max) + 0.5
        let w3 = clamp(self.a, min: 0, max: 1) * Float(UInt8.max) + 0.5
        
        return (UInt32(w3) << 24) | (UInt32(w2) << 16) | (UInt32(w1) << 8) | UInt32(w0)
    }
}

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
    public static func *=(lhs: inout OklabColor, rhs: Scalar) {
        lhs.L *= rhs
        lhs.a *= rhs
        lhs.b *= rhs
    }
    
    @inlinable
    public static func *(lhs: OklabColor, rhs: Scalar) -> OklabColor {
        var result = lhs
        result *= rhs
        return result
    }
    
    @inlinable
    public static func *(lhs: Scalar, rhs: OklabColor) -> OklabColor {
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
    public static func /(lhs: Scalar, rhs: OklabColor) -> OklabColor {
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
    public static func *=(lhs: inout RGBColor, rhs: Scalar) {
        lhs.r *= rhs
        lhs.g *= rhs
        lhs.b *= rhs
    }
    
    @inlinable
    public static func *(lhs: RGBColor, rhs: Scalar) -> RGBColor {
        var result = lhs
        result *= rhs
        return result
    }
    
    @inlinable
    public static func *(lhs: Scalar, rhs: RGBColor) -> RGBColor {
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
    public static func /(lhs: Scalar, rhs: RGBColor) -> RGBColor {
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
    public static func *=(lhs: inout RGBAColor, rhs: Scalar) {
        lhs.r *= rhs
        lhs.g *= rhs
        lhs.b *= rhs
        lhs.a *= rhs
    }
    
    @inlinable
    public static func *(lhs: RGBAColor, rhs: Scalar) -> RGBAColor {
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
    public static func /(lhs: Scalar, rhs: RGBAColor) -> RGBAColor {
        return RGBAColor(lhs / rhs.r, lhs / rhs.g, lhs / rhs.b, lhs / rhs.a)
    }
    
    @inlinable
    public static func ==(lhs: RGBAColor, rhs: RGBAColor) -> Bool {
        return lhs.r == rhs.r && lhs.g == rhs.g && lhs.b == rhs.b && lhs.a == rhs.a
    }
}

extension SIMD3 where Scalar: Real & BinaryFloatingPoint {
    @inlinable
    public init(_ colour: RGBColor<Scalar>) {
        self.init(colour.r, colour.g, colour.b)
    }
}

extension SIMD3 where Scalar: Real & BinaryFloatingPoint {
    @inlinable
    public init(_ colour: OklabColor<Scalar>) {
        self.init(colour.L, colour.a, colour.b)
    }
}

extension SIMD3 where Scalar: Real & BinaryFloatingPoint {
    @inlinable
    public init(_ colour: XYZColor<Scalar>) {
        self.init(colour.X, colour.Y, colour.Z)
    }
}

extension SIMD4 where Scalar: Real & BinaryFloatingPoint {
    @inlinable
    public init(_ colour: RGBAColor<Scalar>) {
        self.init(colour.r, colour.g, colour.b, colour.a)
    }
}

@inlinable
public func interpolate<Scalar>(from u: RGBColor<Scalar>, to v: RGBColor<Scalar>, factor t: Scalar) -> RGBColor<Scalar> {
    return u + (v - u) * t
}

@inlinable
public func interpolateOklabSpace<Scalar>(from u: RGBColor<Scalar>, to v: RGBColor<Scalar>, factor t: Scalar) -> RGBColor<Scalar> {
    return RGBColor(linearSRGBFrom: interpolate(from: OklabColor(fromLinearSRGB: u), to: OklabColor(fromLinearSRGB: v), factor: t))
}

@inlinable
public func interpolate<Scalar>(from u: OklabColor<Scalar>, to v: OklabColor<Scalar>, factor t: Scalar) -> OklabColor<Scalar> {
    return u + (v - u) * t
}

@inlinable
public func interpolate<Scalar>(from u: RGBAColor<Scalar>, to v: RGBAColor<Scalar>, factor t: Scalar) -> RGBAColor<Scalar> {
    return u + (v - u) * t
}

@inlinable
public func min<Scalar>(_ a: RGBColor<Scalar>, _ b: RGBColor<Scalar>) -> RGBColor<Scalar> {
    return RGBColor(min(a.r, b.r), min(a.g, b.g), min(a.b, b.b))
}

@inlinable
public func max<Scalar>(_ a: RGBColor<Scalar>, _ b: RGBColor<Scalar>) -> RGBColor<Scalar> {
    return RGBColor(max(a.r, b.r), max(a.g, b.g), max(a.b, b.b))
}

@inlinable
public func clamp<Scalar>(_ x: RGBColor<Scalar>, min minVec: RGBColor<Scalar>, max maxVec: RGBColor<Scalar>) -> RGBColor<Scalar> {
    return min(max(minVec, x), maxVec)
}

@inlinable
public func min<Scalar>(_ a: RGBAColor<Scalar>, _ b: RGBAColor<Scalar>) -> RGBAColor<Scalar> {
    return RGBAColor(min(a.r, b.r), min(a.g, b.g), min(a.b, b.b), min(a.a, b.a))
}

@inlinable
public func max<Scalar>(_ a: RGBAColor<Scalar>, _ b: RGBAColor<Scalar>) -> RGBAColor<Scalar> {
    return RGBAColor(max(a.r, b.r), max(a.g, b.g), max(a.b, b.b), max(a.a, b.a))
}

@inlinable
public func clamp<Scalar>(_ x: RGBAColor<Scalar>, min minVec: RGBAColor<Scalar>, max maxVec: RGBAColor<Scalar>) -> RGBAColor<Scalar> {
    return min(max(minVec, x), maxVec)
}

@inlinable
public func min<Scalar>(_ a: OklabColor<Scalar>, _ b: OklabColor<Scalar>) -> OklabColor<Scalar> {
    return OklabColor(min(a.L, b.L), min(a.a, b.a), min(a.b, b.b))
}

@inlinable
public func max<Scalar>(_ a: OklabColor<Scalar>, _ b: OklabColor<Scalar>) -> OklabColor<Scalar> {
    return OklabColor(max(a.L, b.L), max(a.a, b.a), max(a.b, b.b))
}

@inlinable
public func clamp<Scalar>(_ x: OklabColor<Scalar>, min minVec: OklabColor<Scalar>, max maxVec: OklabColor<Scalar>) -> OklabColor<Scalar> {
    return min(max(minVec, x), maxVec)
}

@inlinable
public func min<Scalar>(_ a: XYZColor<Scalar>, _ b: XYZColor<Scalar>) -> XYZColor<Scalar> {
    return XYZColor(min(a.X, b.X), min(a.Y, b.Y), min(a.Z, b.Z))
}

@inlinable
public func max<Scalar>(_ a: XYZColor<Scalar>, _ b: XYZColor<Scalar>) -> XYZColor<Scalar> {
    return XYZColor(max(a.X, b.X), max(a.Y, b.Y), max(a.Z, b.Z))
}

@inlinable
public func clamp<Scalar>(_ x: XYZColor<Scalar>, min minVec: XYZColor<Scalar>, max maxVec: XYZColor<Scalar>) -> XYZColor<Scalar> {
    return min(max(minVec, x), maxVec)
}

// MARK: - Codable Conformance

extension RGBColor: Encodable where Scalar: Encodable {
    @inlinable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.r)
        try container.encode(self.g)
        try container.encode(self.b)
    }
}
    
extension RGBColor: Decodable where Scalar: Decodable {
    @inlinable
    public init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        let r = try values.decode(Scalar.self)
        let g = try values.decode(Scalar.self)
        let b = try values.decode(Scalar.self)
        
        self.init(r: r, g: g, b: b)
    }
}

extension XYZColor: Encodable where Scalar: Encodable {
    @inlinable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.X)
        try container.encode(self.Y)
        try container.encode(self.Z)
    }
}

extension XYZColor: Decodable where Scalar: Decodable {
    @inlinable
    public init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        let x = try values.decode(Scalar.self)
        let y = try values.decode(Scalar.self)
        let z = try values.decode(Scalar.self)
        
        self.init(X: x, Y: y, Z: z)
    }
}

extension OklabColor: Encodable where Scalar: Encodable {
    @inlinable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.L)
        try container.encode(self.a)
        try container.encode(self.b)
    }
}
    
extension OklabColor: Decodable where Scalar: Decodable {
    @inlinable
    public init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        let L = try values.decode(Scalar.self)
        let a = try values.decode(Scalar.self)
        let b = try values.decode(Scalar.self)
        
        self.init(L: L, a: a, b: b)
    }
}

extension RGBAColor: Encodable where Scalar: Encodable {
    @inlinable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.r)
        try container.encode(self.g)
        try container.encode(self.b)
        try container.encode(self.a)
    }
}
    
extension RGBAColor: Decodable where Scalar: Decodable {
    @inlinable
    public init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        let r = try values.decode(Scalar.self)
        let g = try values.decode(Scalar.self)
        let b = try values.decode(Scalar.self)
        let a = try values.decode(Scalar.self)
        
        self.init(r: r, g: g, b: b, a: a)
    }
}
