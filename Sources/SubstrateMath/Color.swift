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
        let rX: Scalar = 3.240479
        let rY: Scalar = -1.537150
        let rZ: Scalar = -0.498535
        let gX: Scalar = -0.969256
        let gY: Scalar = 1.875991
        let gZ: Scalar = 0.041556
        let bX: Scalar = 0.055648
        let bY: Scalar = -0.204043
        let bZ: Scalar = 1.057311
        let r = rX * x + rY * y + rZ * z
        let g = gX * x + gY * y + gZ * z
        let b = bX * x + bY * y + bZ * z
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
            let rWeight: Scalar = 0.212671
            let gWeight: Scalar = 0.715160
            let bWeight: Scalar = 0.072169
            return rWeight * self.r + gWeight * self.g + bWeight * self.b
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
extension RGBColor: @unchecked Sendable where Scalar: Sendable {}

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

// ALEXA Log C Curve: Usage in VFX (Harald Brendel)
// https://www.arri.com/resource/blob/31918/66f56e6abb6e5b6553929edf9aa7483e/2017-03-alexa-logc-curve-in-vfx-data.pdf
public enum ArriAlexaEl: Int, CaseIterable, Hashable, Sendable, Codable {
    case el160 = 160
    case el200 = 200
    case el250 = 250
    case el320 = 320
    case el400 = 400
    case el500 = 500
    case el640 = 640
    case el800 = 800
    case el1000 = 1000
    case el1280 = 1280
    case el1600 = 1600
    
    @inlinable
    public var sensorSignalParameters: ArriLogCParameters {
        switch self {
        case .el160:
            return .init(cut: 0.004680, a: 40.0, b: -0.076072, c: 0.269036, d: 0.381991, e: 42.062665, f: -0.071569)
        case .el200:
            return .init(cut: 0.004597, a: 50.0, b: -0.118740, c: 0.266007, d: 0.382478, e: 51.986387, f: -0.110339)
        case .el250:
            return .init(cut: 0.004518, a: 62.5, b: -0.171260, c: 0.262978, d: 0.382966, e: 64.243053, f: -0.158224)
        case .el320:
            return .init(cut: 0.004436, a: 80.0, b: -0.243808, c: 0.259627, d: 0.383508, e: 81.183335, f: -0.224409)
        case .el400:
            return .init(cut: 0.004369, a: 100.0, b: -0.325820, c: 0.256598, d: 0.383999, e: 100.295280, f: -0.299079)
        case .el500:
            return .init(cut: 0.004309, a: 125.0, b: -0.427461, c: 0.253569, d: 0.384493, e: 123.889239, f: -0.391261)
        case .el640:
            return .init(cut: 0.004249, a: 160.0, b: -0.568709, c: 0.250219, d: 0.385040, e: 156.482680, f: -0.518605)
        case .el800:
            return .init(cut: 0.004201, a: 200.0, b: -0.729169, c: 0.247190, d: 0.385537, e: 193.235573, f: -0.662201)
        case .el1000:
            return .init(cut: 0.004160, a: 250.0, b: -0.928805, c: 0.244161, d: 0.386036, e: 238.584745, f: -0.839385)
        case .el1280:
            return .init(cut: 0.004120, a: 320.0, b: -1.207168, c: 0.240810, d: 0.386590, e: 301.197380, f: -1.084020)
        case .el1600:
            return .init(cut: 0.004088, a: 400.0, b: -1.524256, c: 0.237781, d: 0.387093, e: 371.761171, f: -1.359723)
        }
    }
    
    @inlinable
    public var exposureValueParameters: ArriLogCParameters {
        switch self {
        case .el160:
            return .init(cut: 0.005561, a: 5.555556, b: 0.080216, c: 0.269036, d: 0.381991, e: 5.842037, f: 0.092778)
        case .el200:
            return .init(cut: 0.006208, a: 5.555556, b: 0.076621, c: 0.266007, d: 0.382478, e: 5.776265, f: 0.092782)
        case .el250:
            return .init(cut: 0.006871, a: 5.555556, b: 0.072941, c: 0.262978, d: 0.382966, e: 5.710494, f: 0.092786)
        case .el320:
            return .init(cut: 0.007622, a: 5.555556, b: 0.068768, c: 0.259627, d: 0.383508, e: 5.637732, f: 0.092791)
        case .el400:
            return .init(cut: 0.008318, a: 5.555556, b: 0.064901, c: 0.256598, d: 0.383999, e: 5.571960, f: 0.092795)
        case .el500:
            return .init(cut: 0.009031, a: 5.555556, b: 0.060939, c: 0.253569, d: 0.384493, e: 5.506188, f: 0.092800)
        case .el640:
            return .init(cut: 0.009840, a: 5.555556, b: 0.056443, c: 0.250219, d: 0.385040, e: 5.433426, f: 0.092805)
        case .el800:
            return .init(cut: 0.010591, a: 5.555556, b: 0.052272, c: 0.247190, d: 0.385537, e: 5.367655, f: 0.092809)
        case .el1000:
            return .init(cut: 0.011361, a: 5.555556, b: 0.047996, c: 0.244161, d: 0.386036, e: 5.301883, f: 0.092814)
        case .el1280:
            return .init(cut: 0.012235, a: 5.555556, b: 0.043137, c: 0.240810, d: 0.386590, e: 5.229121, f: 0.092819)
        case .el1600:
            return .init(cut: 0.013047, a: 5.555556, b: 0.038625, c: 0.237781, d: 0.387093, e: 5.163350, f: 0.092824)
        }
    }
}

public struct ArriLogCParameters: Hashable, Sendable {
    public let cut: Double
    public let a: Double
    public let b: Double
    public let c: Double
    public let d: Double
    public let e: Double
    public let f: Double
    
    @inlinable
    public init(cut: Double, a: Double, b: Double, c: Double, d: Double, e: Double, f: Double) {
        self.cut = cut
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.e = e
        self.f = f
    }
}

public enum ColorTransferFunction<Scalar: BinaryFloatingPoint & Real> {
    case linear
    case power(Scalar)
    case acesCC
    case acesCCT
    case sRGB
    case rec709
    case arriLogC(ArriLogCParameters)
    case arriLogC4
    case sonySLog3
    case proPhoto
    case pq
    case hlg
    
    @inlinable
    public var representativeGamma: Scalar? {
        switch self {
        case .linear: return 1.0
        case .power(let power): return power
        case .sRGB: return 2.2
        case .rec709: return 2.4
        case .proPhoto: return 1.8
        default: return nil
        }
    }
    
    /// This is the OETF (opto-electronic transfer function) that converts linear light into an encoded signal.
    @inlinable
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
        case .arriLogC(let params):
            let cut = Scalar(params.cut)
            let a = Scalar(params.a)
            let b = Scalar(params.b)
            let c = Scalar(params.c)
            let d = Scalar(params.d)
            let e = Scalar(params.e)
            let f = Scalar(params.f)
            return (x > cut) ? c * Scalar.log10(a * x + b) + d : e * x + f
        case .arriLogC4:
            let a: Scalar = 262128.0 / 117.45 // (2^18 - 16) / 117.45
            let b: Scalar = (1023.0 - 95.0) / 1023.0
            let c: Scalar = 95.0 / 1023.0
            let s: Scalar = 0.1135972086105891 //  7.0 * Scalar.log(2.0) * Scalar.exp2(7.0 - 14.0 * c / b) / (a * b)
            let t: Scalar = -0.018056996119911309 // (Scalar.exp2(14.0 * -c / b + 6.0) - 64.0) / a
            
            let log2: Scalar = Scalar.log2(a * x + Scalar(64.0))
            let log2Part: Scalar = (log2 - 6.0) / 14.0
            return x >= t ? log2Part * b + c : (x - t) / s
        case .sonySLog3:
            if x >= 0.01125000 {
                let log10Part: Scalar = Scalar.log10((x + 0.01) / (0.18 + 0.01))
                return (420.0 + log10Part * 261.5) / 1023.0
            } else {
                let scale: Scalar = (171.2102946929 - 95.0)/0.01125000
                return (x * scale + 95.0) / 1023.0
            }
        case .proPhoto:
            if x < 0.0 {
                return 0.0
            } else if x < 1.0 / 512.0 {
                return 16.0 * x
            } else if x < 1.0 {
                return Scalar.pow(x, 1.0 / 1.8)
            } else {
                return 1.0
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
    @inlinable
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
        case .arriLogC(let params):
            let cut = Scalar(params.cut)
            let a: Scalar = Scalar(params.a)
            let b: Scalar = Scalar(params.b)
            let c: Scalar = Scalar(params.c)
            let d: Scalar = Scalar(params.d)
            let e: Scalar = Scalar(params.e)
            let f: Scalar = Scalar(params.f)
            let eCutF = e * cut + f
            
            let exp10 = Scalar.exp10((x - d) / c)
            return (x > eCutF) ? (exp10 - b) / a : (x - f) / e
        case .arriLogC4:
            let a: Scalar = 262128.0 / 117.45 // (2^18 - 16) / 117.45
            let b: Scalar = (1023.0 - 95.0) / 1023.0
            let c: Scalar = 95.0 / 1023.0
            let s: Scalar = 0.1135972086105891 //  7.0 * Scalar.log(2.0) * Scalar.exp2(7.0 - 14.0 * c / b) / (a * b)
            let t: Scalar = -0.018056996119911309 // (Scalar.exp2(14.0 * -c / b + 6.0) - 64.0) / a
            
            let xcb: Scalar = (x - c) / b
            let exp2 = Scalar.exp2(14.0 * xcb + 6.0)
            let exp2A: Scalar = (exp2 - 64.0) / a
            return x >= 0.0 ? exp2A : x * s + t
        case .sonySLog3:
            if x >= 171.2102946929 / 1023.0 {
                let exp10Part: Scalar = Scalar.exp10((x * 1023.0 - 420.0) / 261.5)
                return exp10Part * (0.18 + 0.01) - 0.01
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
            
            let xGamma = Scalar.pow(x, 1.0 / m2)
            let numerator = max(xGamma - c1, 0.0)
            let denominator = c2 - c3 * xGamma
            
            return 10_000.0 * Scalar.pow(numerator / denominator, 1.0 / m1)
        case .proPhoto:
            if x < 0.0 {
                return 0.0
            } else if x < 16.0 / 512.0 {
                return x / 16.0
            } else if x < 1.0 {
                return Scalar.pow(x, 1.8)
            } else {
                return 1.0
            }
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
                return (Scalar.exp((x - c) / a) + b) / 12.0
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
        public static var d50: ReferenceWhite {
            return ReferenceWhite(chromacity: SIMD2(0.345704, 0.358540))
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
        public static var rec709: Primaries {
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
        public static var adobeRGB: Primaries {
            return Primaries(
                red:   SIMD2(0.64000,  0.33000),
                green: SIMD2(0.21000,  0.71000),
                blue:  SIMD2(0.15000,  0.06000))
        }
        
        @inlinable
        public static var rec2020: Primaries {
            return Primaries(
                red:   SIMD2(0.70800,  0.29200),
                green: SIMD2(0.17000,  0.79700),
                blue:  SIMD2(0.13100,  0.04600))
        }
        
        @inlinable
        public static var arriWideGamutRGB: Primaries {
            return Primaries(
                red:   SIMD2(0.6840,  0.3130),
                green: SIMD2(0.2210,  0.8480),
                blue:  SIMD2(0.0861, -0.1020))
        }
        
        @inlinable
        public static var arriWideGamut4: Primaries {
            return Primaries(
                red:   SIMD2(0.7347,  0.2653),
                green: SIMD2(0.1424,  0.8576),
                blue:  SIMD2(0.0991, -0.0308))
        }
        
        @inlinable
        public static var proPhoto: Primaries {
            return Primaries(
                red:   SIMD2(0.734699, 0.265301),
                green: SIMD2(0.159597, 0.840403),
                blue:  SIMD2(0.036598, 0.000105))
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
        
        @inlinable
        init(matrix: Matrix3x3<Scalar>? = nil, inputColorTransferFunction: ColorTransferFunction<Scalar>, outputColorTransferFunction: ColorTransferFunction<Scalar>) {
            self.matrix = matrix != .identity ? matrix : nil
            self.inputColorTransferFunction = inputColorTransferFunction
            self.outputColorTransferFunction = outputColorTransferFunction
        }
        
        @inlinable
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
        
        @inlinable
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
    
    @inlinable
    public init(primaries: Primaries, eotf: ColorTransferFunction<Scalar>, referenceWhite: ReferenceWhite) {
        self.primaries = primaries
        self.eotf = eotf
        self.referenceWhite = referenceWhite
    }
    
    // BT.1886 defines a gamma 2.4 EOTF. Rec.709 has its own OETF but that's only used for encoding directly to Rec.709 from a camera sensor.
    @inlinable
    public static func rec709(eotf: ColorTransferFunction<Scalar> = .power(2.4)) -> CIEXYZ1931ColorSpace {
        return .init(primaries: .sRGB,
                     eotf: eotf,
                     referenceWhite: .d65)
    }
    
    @inlinable
    public static var sRGB: CIEXYZ1931ColorSpace {
        return .init(primaries: .sRGB,
                     eotf: .sRGB,
                     referenceWhite: .d65)
    }
    
    @inlinable
    public static var linearSRGB: CIEXYZ1931ColorSpace {
        return .init(primaries: .sRGB,
                     eotf: .linear,
                     referenceWhite: .d65)
    }
    
    @inlinable
    public static var dciP3: CIEXYZ1931ColorSpace {
        return .init(primaries: .p3,
                     eotf: .power(2.6),
                     referenceWhite: .dci)
    }
    
    @inlinable
    public static var displayP3: CIEXYZ1931ColorSpace {
        return .init(primaries: .p3,
                     eotf: .sRGB,
                     referenceWhite: .d65)
    }
    
    // BT.1886 defines a gamma 2.4 EOTF.
    @inlinable
    public static func rec2020(eotf: ColorTransferFunction<Scalar> = .power(2.4)) -> CIEXYZ1931ColorSpace {
        return .init(primaries: .rec2020,
                     eotf: eotf,
                     referenceWhite: .d65)
    }
    
    @inlinable
    public static var aces: CIEXYZ1931ColorSpace {
        return .init(primaries: .acesAP0,
                     eotf: .linear,
                     referenceWhite: .aces)
    }
    
    @inlinable
    public static var acesCC: CIEXYZ1931ColorSpace {
        return .init(primaries: .acesAP1,
                     eotf: .acesCC,
                     referenceWhite: .aces)
    }
    
    @inlinable
    public static var acesCCT: CIEXYZ1931ColorSpace {
        return .init(primaries: .acesAP1,
                     eotf: .acesCCT,
                     referenceWhite: .aces)
    }
    
    @inlinable
    public static var acesCG: CIEXYZ1931ColorSpace {
        return .init(primaries: .acesAP1,
                     eotf: .linear,
                     referenceWhite: .aces)
    }
    
    @inlinable
    public static var adobeRGB: CIEXYZ1931ColorSpace {
        return .init(primaries: .adobeRGB,
                     eotf: .power(563.0 / 256.0),
                     referenceWhite: .d65)
    }
    
    @inlinable
    public static func arriLogC(el: ArriAlexaEl = .el800, usingSensorValues: Bool = false) -> CIEXYZ1931ColorSpace {
        return .init(primaries: .arriWideGamutRGB,
                     eotf: .arriLogC(usingSensorValues ? el.sensorSignalParameters : el.exposureValueParameters),
                     referenceWhite: .d65)
    }
    
    @inlinable
    public static var arriLogC4: CIEXYZ1931ColorSpace {
        return .init(primaries: .arriWideGamut4,
                     eotf: .arriLogC4,
                     referenceWhite: .d65)
    }
    
    @inlinable
    public static var proPhoto: CIEXYZ1931ColorSpace {
        return .init(primaries: .proPhoto,
                     eotf: .proPhoto,
                     referenceWhite: .d50)
    }
    
    @inlinable
    public static var sonySGamut3: CIEXYZ1931ColorSpace {
        return .init(primaries: .sonySGamut3,
                     eotf: .sonySLog3,
                     referenceWhite: .d65)
    }
    
    @inlinable
    public static var sonySGamut3Cine: CIEXYZ1931ColorSpace {
        return .init(primaries: .sonySGamut3Cine,
                     eotf: .sonySLog3,
                     referenceWhite: .d65)
    }
    
    // Reference: http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    @inlinable
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
    
    @inlinable
    public var xyzToRGBMatrix: Matrix3x3<Scalar> {
        self.rgbToXYZMatrix.inverse
    }
    
    @inlinable
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
    
    @inlinable
    public static func chromaticAdaptationMatrix(from: ReferenceWhite, to: ReferenceWhite) -> Matrix3x3<Scalar> {
        return self.chromaticAdaptationMatrix(from: from.value, to: to.value)
    }
    
    @inlinable
    public static func conversionContext(convertingFrom inputColorSpace: CIEXYZ1931ColorSpace, to outputColorSpace: CIEXYZ1931ColorSpace) -> ConversionContext {
        return .converting(from: inputColorSpace, to: outputColorSpace)
    }
    
    @inlinable
    public static func convert(_ value: RGBColor<Scalar>, from inputColorSpace: CIEXYZ1931ColorSpace, to outputColorSpace: CIEXYZ1931ColorSpace) -> RGBColor<Scalar> {
        return ConversionContext.converting(from: inputColorSpace, to: outputColorSpace).convert(value)
    }
}

extension CIEXYZ1931ColorSpace {
    /// Decoding for macOS system profiles.
    public init?(iccProfileName: String) {
        switch iccProfileName {
        case "ACES CG Linear (Academy Color Encoding System AP1)":
            self = .acesCG
        case "Display P3":
            self = .displayP3
        case "Generic Grey Gamma 2.2 Profile":
            self = .init(primaries: .sRGB, eotf: .power(2.2), referenceWhite: .d65)
        case "Rec. ITU-R BT.2020-1":
            self = .rec2020(eotf: .rec709)
        case "Rec. ITU-R BT.709-5":
            self = .rec709(eotf: .rec709)
        case "ROMM RGB: ISO 22028-2:2013":
            self = .proPhoto
        case "SMPTE RP 431-2-2007 DCI (P3)":
            self = .dciP3
        case "sRGB IEC61966-2.1":
            self = .sRGB
        default:
            return nil
        }
    }
}

extension CIEXYZ1931ColorSpace.Primaries: Equatable where Scalar: Equatable {}
extension CIEXYZ1931ColorSpace.Primaries: Hashable where Scalar: Hashable {}
extension CIEXYZ1931ColorSpace.Primaries: @unchecked Sendable where Scalar: Sendable {}

extension ColorTransferFunction: Equatable where Scalar: Equatable {}
extension ColorTransferFunction: Hashable where Scalar: Hashable {}
extension ColorTransferFunction: @unchecked Sendable where Scalar: Sendable {}

extension CIEXYZ1931ColorSpace: Equatable where Scalar: Equatable {}
extension CIEXYZ1931ColorSpace: Hashable where Scalar: Hashable {}
extension CIEXYZ1931ColorSpace: @unchecked Sendable where Scalar: Sendable {}

extension CIEXYZ1931ColorSpace.ConversionContext: @unchecked Sendable where Scalar: Sendable {}

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
        let lR: Scalar = 0.4122214708
        let lG: Scalar = 0.5363325363
        let lB: Scalar = 0.0514459929
        let mR: Scalar = 0.2119034982
        let mG: Scalar = 0.6806995451
        let mB: Scalar = 0.1073969566
        let sR: Scalar = 0.0883024619
        let sG: Scalar = 0.2817188376
        let sB: Scalar = 0.6299787005
        
        let l = lR * c.r + lG * c.g + lB * c.b
        let m = mR * c.r + mG * c.g + mB * c.b
        let s = sR * c.r + sG * c.g + sB * c.b

        let l_ = Scalar.pow(l, 1.0 / 3.0)
        let m_ = Scalar.pow(m, 1.0 / 3.0)
        let s_ = Scalar.pow(s, 1.0 / 3.0)

        let Ll: Scalar = 0.2104542553
        let Lm: Scalar = 0.7936177850
        let Ls: Scalar = -0.0040720468
        let al: Scalar = 1.9779984951
        let am: Scalar = -2.4285922050
        let `as`: Scalar = 0.4505937099
        let bl: Scalar = 0.0259040371
        let bm: Scalar = 0.7827717662
        let bs: Scalar = -0.8086757660
        
        let L: Scalar = Ll * l_ + Lm * m_ + Ls * s_
        let a: Scalar = al * l_ + am * m_ + `as` * s_
        let b: Scalar = bl * l_ + bm * m_ + bs * s_
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
        let la: Scalar =  0.3963377774
        let lb: Scalar =  0.2158037573
        let ma: Scalar = -0.1055613458
        let mb: Scalar = -0.0638541728
        let sa: Scalar = -0.0894841775
        let sb: Scalar = -1.2914855480
        let l_ = c.L + la * c.a + lb * c.b
        let m_ = c.L + ma * c.a + mb * c.b
        let s_ = c.L + sa * c.a + sb * c.b
        
        let l = l_ * l_ * l_
        let m = m_ * m_ * m_
        let s = s_ * s_ * s_
        
        let rl: Scalar = +4.0767245293
        let rm: Scalar = -3.3072168827
        let rs: Scalar = +0.2307590544
        let gl: Scalar = -1.2681437731
        let gm: Scalar = +2.6093323231
        let gs: Scalar = -0.3411344290
        let bl: Scalar = -0.0041119885
        let bm: Scalar = -0.7034763098
        let bs: Scalar = +1.7068625689
        let r: Scalar = rl * l + rm * m + rs * s
        let g: Scalar = gl * l + gm * m + gs * s
        let b: Scalar = bl * l + bm * m + bs * s
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
        let rWeight: Scalar = 0.212671
        let gWeight: Scalar = 0.715160
        let bWeight: Scalar = 0.072169
        return rWeight * self.r + gWeight * self.g + bWeight * self.b
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
extension RGBAColor: @unchecked Sendable where Scalar: Sendable {}

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


extension ArriLogCParameters: Codable {}
extension CIEXYZ1931ColorSpace.Primaries: Encodable where Scalar: Encodable {}
extension CIEXYZ1931ColorSpace.Primaries: Decodable where Scalar: Decodable {}
extension CIEXYZ1931ColorSpace.ReferenceWhite: Encodable where Scalar: Encodable {}
extension CIEXYZ1931ColorSpace.ReferenceWhite: Decodable where Scalar: Decodable {}
extension ColorTransferFunction: Encodable where Scalar: Encodable {}
extension ColorTransferFunction: Decodable where Scalar: Decodable {}
extension CIEXYZ1931ColorSpace: Encodable where Scalar: Encodable {}
extension CIEXYZ1931ColorSpace: Decodable where Scalar: Decodable {}
