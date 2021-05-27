//
//  ImageConversion.swift
//  SubstrateImageIO
//
//

import Foundation
import stb_image_resize

//@available(*, deprecated, renamed: "ImageColorSpace")
public typealias TextureColorSpace = ImageColorSpace

//@available(*, deprecated, renamed: "ImageColorSpace")
public typealias TextureColourSpace = ImageColorSpace

//@available(*, deprecated, renamed: "Image")
public typealias TextureData = Image

//@available(*, deprecated, renamed: "AnyImage")
public typealias AnyTextureData = AnyImage

//@available(*, deprecated, renamed: "ImageAlphaMode")
public typealias TextureAlphaMode = ImageAlphaMode

//@available(*, deprecated, renamed: "ImageEdgeWrapMode")
public typealias TextureEdgeWrapMode = ImageEdgeWrapMode

//@available(*, deprecated, renamed: "ImageResizeFilter")
public typealias TextureResizeFilter = ImageResizeFilter

@inlinable
func clamp<T: Comparable>(_ val: T, min minValue: T, max maxValue: T) -> T {
    return min(max(val, minValue), maxValue)
}

// Reference: https://docs.microsoft.com/en-us/windows/win32/direct3d10/d3d10-graphics-programming-guide-resources-data-conversion
@inlinable
public func floatToSnorm<I: BinaryInteger & FixedWidthInteger & SignedInteger>(_ c: Float, type: I.Type) -> I {
    if c != c { // Check for NaN – this check is faster than c.isNaN
        return 0
    }
    let c = clamp(c, min: -1.0, max: 1.0)
    
    let scale: Float
    if I.self == Int8.self {
        scale = Float(Int8.max)
    } else if I.self == Int16.self {
        scale = Float(Int16.max)
    } else {
        scale = Float(I.max)
    }
    let rescaled = c * scale
    //    let rounded = rescaled.rounded(.toNearestOrAwayFromZero)
    let rounded = rescaled + (rescaled > 0 ? 0.5 : -0.5) // We follow this by a floor through conversion to int, so we can round by adding 0.5
    if I.self == Int8.self {
        return Int8(rounded) as! I
    } else if I.self == Int16.self {
        return Int16(rounded) as! I
    } else {
        return I(rounded)
    }
}

@inlinable
public func floatToUnorm<I: BinaryInteger & FixedWidthInteger & UnsignedInteger>(_ c: Float, type: I.Type) -> I {
    if c != c { // Check for NaN – this check is faster than c.isNaN
        return 0
    }
    let c = min(1.0, max(c, 0.0))
    let scale: Float
    if I.self == UInt8.self {
        scale = Float(UInt8.max)
    } else if I.self == UInt16.self {
        scale = Float(UInt16.max)
    } else {
        scale = Float(I.max)
    }
    let rescaled = c * scale
    //    let rounded = rescaled.rounded(.toNearestOrAwayFromZero)
    let rounded = rescaled + 0.5 // We follow this by a floor through conversion to int, so we can round by adding 0.5
    if I.self == UInt8.self {
        return UInt8(rounded) as! I
    } else if I.self == UInt16.self {
        return UInt16(rounded) as! I
    } else {
        return I(rounded)
    }
}

@inlinable
public func snormToFloat<I: BinaryInteger & FixedWidthInteger & SignedInteger>(_ c: I) -> Float {
    if c == I.min {
        return -1.0
    }
    if let c = c as? Int8 {
        return Float(c) / Float(Int8.max)
    } else if let c = c as? Int16 {
        return Float(c) / Float(Int16.max)
    } else {
        return Float(c) / Float(I.max)
    }
}

@inlinable
public func unormToFloat<I: BinaryInteger & FixedWidthInteger & UnsignedInteger>(_ c: I) -> Float {
    if let c = c as? UInt8 {
        return Float(c) / Float(UInt8.max)
    } else if let c = c as? UInt16 {
        return Float(c) / Float(UInt16.max)
    } else {
        return Float(c) / Float(I.max)
    }
}

public enum ImageLoadingError : Error {
    case invalidFile(URL)
    case invalidData
    case pngDecodingError(String)
    case exrParseError(String)
    case unsupportedMultipartEXR(URL)
    case unsupportedMultipartEXRData
    case privateImageRequiresRenderGraph
    case invalidImageDataFormat(URL, Any.Type)
}

public enum ImageColorSpace: Hashable {
    /// The texture values use no defined color space.
    case undefined
    /// The IEC 61966-2-1:1999 color space.
    case sRGB
    /// The IEC 61966-2-1:1999 sRGB color space using a linear gamma.
    case linearSRGB
    /// The IEC 61966-2-1:1999 sRGB color space using a user-specified gamma.
    case gammaSRGB(Float)

    @inlinable
    public func fromLinearSRGB(_ color: Float) -> Float {
        switch self {
        case .undefined:
            return color
        case .sRGB:
            return color <= 0.0031308 ? (12.92 * color) : (1.055 * pow(color, 1.0 / 2.4) - 0.055)
        case .linearSRGB:
            return color
        case .gammaSRGB(let gamma):
            return pow(color, gamma)
        }
    }

    @inlinable
    public func toLinearSRGB(_ color: Float) -> Float {
        switch self {
        case .undefined:
            return color
        case .sRGB:
            return color <= 0.04045 ? (color / 12.92) : pow((color + 0.055) / 1.055, 2.4)
        case .linearSRGB:
            return color
        case .gammaSRGB(let gamma):
            return pow(color, 1.0 / gamma)
        }
    }
    
    @inlinable
    public static func convert(_ value: Float, from: ImageColorSpace, to: ImageColorSpace) -> Float {
        if from == to { return value }
        
        let inLinearSRGB = from.toLinearSRGB(value)
        return to.fromLinearSRGB(inLinearSRGB)
    }
}

extension ImageColorSpace: Codable {
    public enum CodingKeys: CodingKey {
        case gamma
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let gamma = try container.decode(Float.self, forKey: .gamma)
        if !gamma.isFinite || gamma < 0 {
            self = .undefined
        } else if gamma == 0 {
            self = .sRGB // sRGB is encoded as gamma of 0.0
        } else if gamma == 1.0 {
            self = .linearSRGB
        } else {
            self = .gammaSRGB(gamma)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .undefined:
            try container.encode(-1.0 as Float, forKey: .gamma)
        case .sRGB:
            try container.encode(0.0 as Float, forKey: .gamma)
        case .linearSRGB:
            try container.encode(1.0 as Float, forKey: .gamma)
        case .gammaSRGB(let gamma):
            try container.encode(gamma, forKey: .gamma)
        }
    }
}

public typealias ImageColourSpace = ImageColorSpace

public enum ImageAlphaMode: String, Codable {
    case none
    case premultiplied
    case postmultiplied
    
    case inferred
    
    func inferFromFileFormat(fileExtension: String, channelCount: Int) -> ImageAlphaMode {
        if channelCount != 2 && channelCount != 4 {
            return .none
        }
        if case .inferred = self, let format = ImageFileFormat(extension: fileExtension) {
            switch format {
            case .png:
                return .postmultiplied
            case .exr:
                return .premultiplied
            case .bmp:
                return .premultiplied
            case .jpg, .hdr:
                return .premultiplied // No transparency
            default:
                break
            }
        }
        
        return self
    }
}

public enum ImageEdgeWrapMode {
    case zero
    case wrap
    case reflect
    case clamp
    
    @inlinable
    var stbirMode : stbir_edge {
        switch self {
        case .zero:
            return STBIR_EDGE_ZERO
        case .wrap:
            return STBIR_EDGE_WRAP
        case .reflect:
            return STBIR_EDGE_REFLECT
        case .clamp:
            return STBIR_EDGE_CLAMP
        }
    }
}

public enum ImageResizeFilter {
    /// Mitchell for downscaling, and Catmull-Rom for upscaling
    case `default`
    /// A trapezoid with 1-pixel wide ramps, producing the same result as a box box for integer scale ratios
    case box
    /// On upsampling, produces same results as bilinear texture filtering
    case triangle
    /// The cubic b-spline (aka Mitchell-Netrevalli with B=1,C=0), gaussian-esque
    case cubicSpline
    /// An interpolating cubic spline
    case catmullRom
    /// Mitchell-Netrevalli filter with B=1/3, C=1/3
    case mitchell
    
    @inlinable
    var stbirFilter : stbir_filter {
        switch self {
        case .default:
            return STBIR_FILTER_DEFAULT
        case .box:
            return STBIR_FILTER_BOX
        case .triangle:
            return STBIR_FILTER_TRIANGLE
        case .cubicSpline:
            return STBIR_FILTER_CUBICBSPLINE
        case .catmullRom:
            return STBIR_FILTER_CATMULLROM
        case .mitchell:
            return STBIR_FILTER_MITCHELL
        }
    }
}

@usableFromInline
final class ImageStorage<T> {
    public let data : UnsafeMutableBufferPointer<T>
    @usableFromInline let deallocateFunc : ((UnsafeMutablePointer<T>) -> Void)?
    
    @inlinable
    init(elementCount: Int) {
        let memory = UnsafeMutableRawBufferPointer.allocate(byteCount: elementCount * MemoryLayout<T>.stride, alignment: MemoryLayout<T>.alignment)
        memory.initializeMemory(as: UInt8.self, repeating: 0)
        self.data = memory.bindMemory(to: T.self)
        self.deallocateFunc = nil
    }
    
    @inlinable
    init(data: UnsafeMutableBufferPointer<T>, deallocateFunc: ((UnsafeMutablePointer<T>) -> Void)?) {
        self.data = data
        self.deallocateFunc = deallocateFunc
    }
    
    @inlinable
    init(copying: UnsafeMutableBufferPointer<T>) {
        self.data = .allocate(capacity: copying.count)
        _ = self.data.initialize(from: copying)
        self.deallocateFunc = nil
    }
    
    deinit {
        if let deallocateFunc = self.deallocateFunc {
            deallocateFunc(self.data.baseAddress!)
        } else {
            self.data.deallocate()
        }
    }
}

public protocol AnyImage: Codable {
    var fileInfo: ImageFileInfo { get }
    var data: Data { get }
    
    var width : Int { get }
    var height : Int { get }
    var channelCount : Int { get }
    
    var colorSpace : ImageColorSpace { get }
    var alphaMode: ImageAlphaMode { get }
    
    mutating func reinterpretColor(as colorSpace: ImageColorSpace)
    mutating func reinterpretAlphaMode(as alphaMode: ImageAlphaMode)
}

public struct Image<ComponentType> : AnyImage {
    public typealias T = ComponentType
    
    public let width : Int
    public let height : Int
    public let channelCount : Int
    
    public internal(set) var colorSpace : ImageColorSpace
    public internal(set) var alphaMode: ImageAlphaMode
    
    @usableFromInline var storage: ImageStorage<T>
    
    @available(*, deprecated, renamed: "colorSpace")
    public internal(set) var colourSpace: ImageColorSpace {
        get {
            return self.colorSpace
        }
        set {
            self.colorSpace = newValue
        }
    }
    
    public init(width: Int, height: Int, channels: Int, colorSpace: ImageColorSpace = .undefined, alphaMode: ImageAlphaMode = .none) {
        precondition(_isPOD(T.self))
        precondition(width >= 1 && height >= 1 && channels >= 1)
        precondition(alphaMode != .inferred, "Inferred alpha modes are only valid given existing data.")
        
        self.init(width: width, height: height, channels: channels, colorSpace: colorSpace, alphaModeAllowInferred: alphaMode)
    }
    
    init(width: Int, height: Int, channels: Int, colorSpace: ImageColorSpace, alphaModeAllowInferred alphaMode: ImageAlphaMode) {
        precondition(_isPOD(T.self))
        precondition(width >= 1 && height >= 1 && channels >= 1)
        precondition(alphaMode != .inferred, "Inferred alpha modes are only valid given existing data.")
        
        self.width = width
        self.height = height
        self.channelCount = channels
        
        self.storage = .init(elementCount: width * height * channelCount)
        
        self.colorSpace = colorSpace
        self.alphaMode = alphaMode
    }
    
    @available(*, deprecated, renamed: "init(width:height:channels:colorSpace:alphaMode:)")
    public init(width: Int, height: Int, channels: Int, colorSpace: ImageColorSpace, premultipliedAlpha: Bool) {
        self.init(width: width, height: height, channels: channels, colorSpace: colorSpace, alphaMode: premultipliedAlpha ? .premultiplied : .postmultiplied)
    }
    
    @available(*, deprecated, renamed: "init(width:height:channels:colorSpace:alphaMode:)")
    public init(width: Int, height: Int, channels: Int, colourSpace: ImageColorSpace, premultipliedAlpha: Bool = false) {
        self.init(width: width, height: height, channels: channels, colorSpace: colourSpace, alphaMode: premultipliedAlpha ? .premultiplied : .postmultiplied)
    }
    
    public init(width: Int, height: Int, channels: Int, colorSpace: ImageColorSpace = .undefined, alphaMode: ImageAlphaMode = .none, data: UnsafeMutablePointer<T>, deallocateFunc: @escaping (UnsafeMutablePointer<T>) -> Void) {
        precondition(width >= 1 && height >= 1 && channels >= 1)
        precondition(alphaMode != .inferred, "Cannot infer the alpha mode when T is not Comparable.")
        
        self.width = width
        self.height = height
        self.channelCount = channels
        
        self.storage = .init(data: UnsafeMutableBufferPointer<T>(start: data, count: self.width * self.height * self.channelCount), deallocateFunc: deallocateFunc)
        
        self.colorSpace = colorSpace
        self.alphaMode = alphaMode
    }
    
    @available(*, deprecated, renamed: "init(width:height:channels:colorSpace:alphaMode:data:deallocateFunc:)")
    public init(width: Int, height: Int, channels: Int, data: UnsafeMutablePointer<T>, colorSpace: ImageColorSpace = .undefined, alphaMode: ImageAlphaMode = .none, deallocateFunc: @escaping (UnsafeMutablePointer<T>) -> Void) {
        self.init(width: width, height: height, channels: channels, colorSpace: colorSpace, alphaMode: alphaMode, data: data, deallocateFunc: deallocateFunc)
    }
        
    @available(*, deprecated, renamed: "init(width:height:channels:colorSpace:alphaMode:data:deallocateFunc:)")
    public init(width: Int, height: Int, channels: Int, data: UnsafeMutablePointer<T>, colorSpace: ImageColorSpace, premultipliedAlpha: Bool, deallocateFunc: @escaping (UnsafeMutablePointer<T>) -> Void) {
        self.init(width: width, height: height, channels: channels, colorSpace: colorSpace, alphaMode: premultipliedAlpha ? .premultiplied : .postmultiplied, data: data, deallocateFunc: deallocateFunc)
    }
    
    @available(*, deprecated, renamed: "init(width:height:channels:colorSpace:alphaMode:data:deallocateFunc:)")
    public init(width: Int, height: Int, channels: Int, data: UnsafeMutablePointer<T>, colourSpace: ImageColorSpace, premultipliedAlpha: Bool = false, deallocateFunc: @escaping (UnsafeMutablePointer<T>) -> Void) {
        self.init(width: width, height: height, channels: channels, colorSpace: colourSpace, alphaMode: premultipliedAlpha ? .premultiplied : .postmultiplied, data: data, deallocateFunc: deallocateFunc)
    }
    
    @inlinable
    mutating func ensureUniqueness() {
        if !isKnownUniquelyReferenced(&self.storage) {
            self.storage = .init(copying: self.storage.data)
        }
    }
    
    public var fileInfo: ImageFileInfo {
        let isFloatingPoint: Bool
        let isSigned: Bool
        switch T.self {
        #if (os(iOS) || os(tvOS) || os(watchOS)) && !targetEnvironment(macCatalyst)
        case is Float16.Type:
            isFloatingPoint = true
            isSigned = true
        #endif
        case is Float.Type, is Double.Type:
            isFloatingPoint = true
            isSigned = true
        #if arch(x86_64)
        case is Float80.Type:
            isFloatingPoint = true
            isSigned = true
        #endif
        case is Int8.Type, is Int16.Type, is Int32.Type, is Int64.Type:
            isFloatingPoint = false
            isSigned = false
        default:
            isFloatingPoint = false
            isSigned = false
        }
        return ImageFileInfo(width: self.width, height: self.height, channelCount: self.channelCount,
                             bitDepth: MemoryLayout<ComponentType>.size * 8, isSigned: isSigned, isFloatingPoint: isFloatingPoint,
                             colorSpace: self.colorSpace, alphaMode: self.alphaMode)
    }
    
    public var data: Data {
        return Data(buffer: self.storage.data)
    }
    
    @available(*, deprecated, renamed: "alphaMode")
    @inlinable
    public var premultipliedAlpha: Bool {
        return self.alphaMode == .premultiplied
    }
    
    /// Reinterprets the texture's pixel data as belonging to the specified color space.
    public mutating func reinterpretColor(as colorSpace: ImageColorSpace) {
        self.colorSpace = colorSpace
    }
    
    /// Reinterprets the texture's alpha data as using the specified alpha mode.
    public mutating func reinterpretAlphaMode(as alphaMode: ImageAlphaMode) {
        precondition(alphaMode != .inferred, "Cannot reinterpret the alpha mode as inferred.")
        self.alphaMode = alphaMode
    }
    
    @inlinable
    func setUnchecked(x: Int, y: Int, channel: Int, value: T) {
        self.storage.data[y &* self.width &* self.channelCount + x &* self.channelCount &+ channel] = value
    }
    
    @inlinable
    public subscript(x: Int, y: Int, channel channel: Int) -> T {
        get {
            precondition(x >= 0 && y >= 0 && channel >= 0 && x < self.width && y < self.height && channel < self.channelCount)
            return self.storage.data[y &* self.width &* self.channelCount + x &* self.channelCount &+ channel]
        }
        set {
            precondition(x >= 0 && y >= 0 && channel >= 0 && x < self.width && y < self.height && channel < self.channelCount)
            self.ensureUniqueness()
            self.storage.data[y &* self.width &* self.channelCount &+ x * self.channelCount &+ channel] = newValue
        }
    }
    
    @inlinable
    public subscript(checked x: Int, y: Int, channel channel: Int) -> T? {
        guard x >= 0, y >= 0, channel >= 0,
            x < self.width, y < self.height, channel < self.channelCount else {
                return nil
        }
        return self.storage.data[y &* self.width &* self.channelCount &+ x * self.channelCount &+ channel]
    }
    
    @inlinable
    public mutating func apply(_ function: (T) -> T, channelRange: Range<Int>) {
        self.ensureUniqueness()
        for y in 0..<self.height {
            let yBase = y * self.width * self.channelCount
            for x in 0..<self.width {
                let baseIndex = yBase + x * self.channelCount
                for c in channelRange {
                    self.storage.data[baseIndex + c] = function(self.storage.data[baseIndex + c])
                }
            }
        }
    }
    
    @inlinable
    public func forEachPixel(_ function: (_ x: Int, _ y: Int, _ channel: Int, _ value: T) -> Void) {
        for y in 0..<self.height {
            let yBase = y * self.width * self.channelCount
            for x in 0..<self.width {
                let baseIndex = yBase + x * self.channelCount
                for c in 0..<self.channelCount {
                    function(x, y, c, self.storage.data[baseIndex + c])
                }
            }
        }
    }
    
    @inlinable
    public func withUnsafeBufferPointer<R>(_ perform: (UnsafeBufferPointer<T>) throws -> R) rethrows -> R {
        return try perform(UnsafeBufferPointer(self.storage.data))
    }
    
    @inlinable
    public mutating func withUnsafeMutableBufferPointer<R>(_ perform: (UnsafeMutableBufferPointer<T>) throws -> R) rethrows -> R {
        self.ensureUniqueness()
        return try perform(self.storage.data)
    }

    @inlinable
    public func cropped(originX: Int, originY: Int, width: Int, height: Int, clampOutOfBounds: Bool = false) -> Image<T> {
        precondition(clampOutOfBounds || (originX >= 0 && originY >= 0))
        precondition(clampOutOfBounds || (originX + width <= self.width && originY + height <= self.height))
        
        if width == self.width, height == self.height, originX == 0, originY == 0 {
            return self
        }
        
        let result = Image<T>(width: width, height: height, channels: self.channelCount, colorSpace: self.colorSpace, alphaMode: self.alphaMode)
        
        for y in 0..<height {
            let clampedY = clampOutOfBounds ? clamp(y + originY, min: 0, max: self.height - 1) : (y + originY)
            for x in 0..<width {
                let clampedX = clampOutOfBounds ? clamp(x + originX, min: 0, max: self.width - 1) : (x + originX)
                for c in 0..<self.channelCount {
                    result.setUnchecked(x: x, y: y, channel: c, value: self[clampedX, clampedY, channel: c])
                }
            }
        }
        
        return result
    }
    
    @inlinable
    public func resized(width: Int, height: Int, wrapMode: ImageEdgeWrapMode, filter: ImageResizeFilter = .default) -> Image<T> {
        if width == self.width && height == self.height {
            return self
        }
        
        let result = Image<T>(width: width, height: height, channels: self.channelCount, colorSpace: self.colorSpace, alphaMode: self.alphaMode)
        
        var flags : Int32 = 0
        if self.alphaMode == .premultiplied {
            flags |= STBIR_FLAG_ALPHA_PREMULTIPLIED
        }
        
        let colorSpace : stbir_colorspace
        switch self.colorSpace {
        case .linearSRGB, .gammaSRGB(1.0):
            colorSpace = STBIR_COLORSPACE_LINEAR
        default:
            colorSpace = STBIR_COLORSPACE_SRGB
        }
        
        let dataType : stbir_datatype
        switch T.self {
        case is Float.Type:
            dataType = STBIR_TYPE_FLOAT
        case is UInt8.Type:
            dataType = STBIR_TYPE_UINT8
        case is UInt16.Type:
            dataType = STBIR_TYPE_UINT16
        case is UInt32.Type:
            dataType = STBIR_TYPE_UINT32
        default:
            fatalError("Unsupported Image type \(T.self) for mip chain generation.")
        }
        
        stbir_resize(self.storage.data.baseAddress, Int32(self.width), Int32(self.height), 0,
                     result.storage.data.baseAddress, Int32(width), Int32(height), 0,
                     dataType,
                     Int32(self.channelCount),
                     self.channelCount == 4 ? 3 : -1,
                     flags,
                     wrapMode.stbirMode, wrapMode.stbirMode,
                     filter.stbirFilter, filter.stbirFilter,
                     colorSpace, nil)
        
        return result
    }
    
    public func generateMipChain(wrapMode: ImageEdgeWrapMode, filter: ImageResizeFilter = .default, compressedBlockSize: Int, mipmapCount: Int? = nil) -> [Image<T>] {
        var results = [self]
        
        var width = self.width
        var height = self.height
        while width >= 2 && height >= 2 {
            if results.count == (mipmapCount ?? .max) {
                return results
            }
            
            width /= 2
            height /= 2
            if width % compressedBlockSize != 0 || height % compressedBlockSize != 0 {
                break
            }
            
            let nextMip = results.last!.resized(width: width, height: height, wrapMode: wrapMode)
            results.append(nextMip)
        }
        
        return results
    }
}

extension Image: Hashable {
    @inlinable
    public static func ==(lhs: Image, rhs: Image) -> Bool {
        if lhs.storage === rhs.storage {
            return true
        }
        if lhs.fileInfo != rhs.fileInfo {
            return false
        }
        return lhs.withUnsafeBufferPointer { lhs in
            return rhs.withUnsafeBufferPointer { rhs in
                return lhs.count == rhs.count && memcmp(lhs.baseAddress!, rhs.baseAddress!, lhs.count * MemoryLayout<ComponentType>.stride) == 0
            }
        }
    }
    
    @inlinable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.fileInfo)
    }
}

extension Image where T: Comparable {
    public init(width: Int, height: Int, channels: Int, data: UnsafeMutablePointer<T>, colorSpace: ImageColorSpace = .undefined, alphaMode: ImageAlphaMode = .none, deallocateFunc: @escaping (UnsafeMutablePointer<T>) -> Void) {
        precondition(width >= 1 && height >= 1 && channels >= 1)
        
        self.width = width
        self.height = height
        self.channelCount = channels
        
        self.storage = .init(data: UnsafeMutableBufferPointer<T>(start: data, count: self.width * self.height * self.channelCount), deallocateFunc: deallocateFunc)
        
        self.colorSpace = colorSpace
        self.alphaMode = alphaMode
        
        self.inferAlphaMode()
    }

    mutating func inferAlphaMode() {
        guard case .inferred = alphaMode else { return }
        
        if self.channelCount == 2 || self.channelCount == 4 {
            let alphaChannel = self.channelCount - 1
            for baseIndex in stride(from: 0, to: self.storage.data.count, by: self.channelCount) {
                let alphaVal = self.storage.data[baseIndex + alphaChannel]
                for c in 0..<alphaChannel {
                    if self.storage.data[baseIndex + c] > alphaVal {
                        self.alphaMode = .postmultiplied
                        return
                    }
                }
            }
            self.alphaMode = .premultiplied
        } else {
            self.alphaMode = .none
        }
    }
}

extension Image where T: SIMDScalar {
    @inlinable
    public subscript(x: Int, y: Int) -> SIMD4<T> {
        get {
            precondition(x >= 0 && y >= 0 && x < self.width && y < self.height)
            
            var result = SIMD4<T>()
            for i in 0..<min(self.channelCount, 4) {
                result[i] = self.storage.data[y * self.width * self.channelCount + x * self.channelCount + i]
            }
            return result
        }
        set {
            precondition(x >= 0 && y >= 0 && x < self.width && y < self.height)
            self.ensureUniqueness()
            
            for i in 0..<min(self.channelCount, 4) {
                self.storage.data[y * self.width * self.channelCount + x * self.channelCount + i] = newValue[i]
            }
        }
    }
}

extension Image where ComponentType == UInt8 {
    private func _applyUnchecked(_ function: (UInt8) -> UInt8, channelRange: Range<Int>) {
        for y in 0..<self.height {
            let yBase = y * self.width * self.channelCount
            for x in 0..<self.width {
                let baseIndex = yBase + x * self.channelCount
                for c in channelRange {
                    self.storage.data[baseIndex + c] = function(self.storage.data[baseIndex + c])
                }
            }
        }
    }
    
    private func _convertSRGBToLinear() {
        self._applyUnchecked({ ColorSpaceLUTs.sRGBToLinear($0) }, channelRange: self.alphaMode != .none ? (0..<self.channelCount - 1) : 0..<self.channelCount)
    }
    
    private func _convertLinearToSRGB() {
        self._applyUnchecked({ ColorSpaceLUTs.linearToSRGB($0) }, channelRange: self.alphaMode != .none ? (0..<self.channelCount - 1) : 0..<self.channelCount)
    }
    
    private func _convertWithAlpha(using lut: UnsafeBufferPointer<UInt8>) {
        let buffer = self.storage.data
        if self.channelCount == 4 {
            let simdBuffer = UnsafeMutableRawBufferPointer(buffer).bindMemory(to: SIMD4<UInt8>.self)
            for i in 0..<simdBuffer.count {
                let sourcePixels = simdBuffer[i]
                let alpha = sourcePixels.w
                let alphaLut = lut.baseAddress.unsafelyUnwrapped.advanced(by: Int(alpha) &* 256)
                
                simdBuffer[i] = SIMD4(
                    alphaLut[Int(sourcePixels.x)],
                    alphaLut[Int(sourcePixels.y)],
                    alphaLut[Int(sourcePixels.z)],
                    alpha
                )
            }
            _ = UnsafeMutableRawBufferPointer(simdBuffer).bindMemory(to: UInt8.self)
        } else {
            let alphaChannel = self.channelCount - 1
            for pixelBase in stride(from: 0, to: buffer.count, by: self.channelCount) {
                let alpha = buffer[pixelBase + alphaChannel]
                for c in 0..<alphaChannel {
                    let lutIndex = Int(alpha) &* 256 &+ Int(buffer[pixelBase + c])
                    buffer[pixelBase + c] = lut[lutIndex]
                }
            }
        }
    }
    
    private func _convertSRGBPostmultipliedToPremultiplied() {
        ColorSpaceLUTs.sRGBPostmultToPremultAlphaLUT.withUnsafeBufferPointer {
            self._convertWithAlpha(using: $0)
        }
    }
    
    private func _convertLinearPostmultipliedToPremultiplied() {
        ColorSpaceLUTs.postmultToPremultAlphaLUT.withUnsafeBufferPointer {
            self._convertWithAlpha(using: $0)
        }
    }
    
    private func _convertSRGBPremultipliedToPostmultiplied() {
        ColorSpaceLUTs.sRGBPremultToPostmultAlphaLUT.withUnsafeBufferPointer {
            self._convertWithAlpha(using: $0)
        }
    }
    
    private func _convertLinearPremultipliedToPostmultiplied() {
        ColorSpaceLUTs.postmultToPremultAlphaLUT.withUnsafeBufferPointer {
            self._convertWithAlpha(using: $0)
        }
    }
}

extension Image where T: BinaryInteger & FixedWidthInteger & UnsignedInteger {
    @inlinable
    public init(_ data: Image<Float>) {
        self.init(width: data.width, height: data.height, channels: data.channelCount, colorSpace: data.colorSpace, alphaMode: data.alphaMode)
        
        self.withUnsafeMutableBufferPointer { dest in
            data.withUnsafeBufferPointer { source in
                for (i, sourceVal) in source.enumerated() {
                    dest[i] = floatToUnorm(sourceVal, type: T.self)
                }
            }
        }
    }
    
    @_specialize(kind: full, where ComponentType == UInt8)
    @_specialize(kind: full, where ComponentType == UInt16)
    @_specialize(kind: full, where ComponentType == UInt32)
    public mutating func convert(toColorSpace: ImageColorSpace) {
        if toColorSpace == self.colorSpace || self.colorSpace == .undefined {
            return
        }
        defer { self.colorSpace = toColorSpace }
        
        if T.self == UInt8.self {
            self.ensureUniqueness()
            if self.colorSpace == .sRGB, toColorSpace == .linearSRGB {
                (self as! Image<UInt8>)._convertSRGBToLinear()
                return
            } else if self.colorSpace == .linearSRGB, toColorSpace == .sRGB {
                (self as! Image<UInt8>)._convertLinearToSRGB()
                return
            }
        }
        
        let sourceColorSpace = self.colorSpace
        self.apply({ floatToUnorm(ImageColorSpace.convert(unormToFloat($0), from: sourceColorSpace, to: toColorSpace), type: T.self) }, channelRange: self.alphaMode != .none ? (0..<self.channelCount - 1) : 0..<self.channelCount)
    }
    
    @_specialize(kind: full, where ComponentType == UInt8)
    @_specialize(kind: full, where ComponentType == UInt16)
    @_specialize(kind: full, where ComponentType == UInt32)
    public mutating func convertToPremultipliedAlpha() {
        guard case .postmultiplied = self.alphaMode else { return }
        self.ensureUniqueness()
        
        defer { self.alphaMode = .premultiplied }
        
        if T.self == UInt8.self {
            if self.colorSpace == .sRGB {
                (self as! Image<UInt8>)._convertSRGBPostmultipliedToPremultiplied()
                return
            } else if self.colorSpace == .linearSRGB || self.colorSpace == .undefined {
                (self as! Image<UInt8>)._convertLinearPostmultipliedToPremultiplied()
                return
            }
        }
        
        let sourceColorSpace = self.colorSpace
        
        let alphaChannel = self.channelCount - 1
        for y in 0..<self.height {
            for x in 0..<self.width {
                let alpha = unormToFloat(self[x, y, channel: alphaChannel])
                for c in 0..<alphaChannel {
                    let floatVal = unormToFloat(self[x, y, channel: c])
                    let linearVal = ImageColorSpace.convert(floatVal, from: sourceColorSpace, to: .linearSRGB) * alpha
                    self.setUnchecked(x: x, y: y, channel: c, value: floatToUnorm(ImageColorSpace.convert(linearVal, from: .linearSRGB, to: sourceColorSpace), type: T.self))
                }
            }
        }
    }
    
    @_specialize(kind: full, where ComponentType == UInt8)
    @_specialize(kind: full, where ComponentType == UInt16)
    @_specialize(kind: full, where ComponentType == UInt32)
    public mutating func convertToPostmultipliedAlpha() {
        guard case .premultiplied = self.alphaMode else { return }
        self.ensureUniqueness()
        defer { self.alphaMode = .postmultiplied }
        
        if T.self == UInt8.self {
            if self.colorSpace == .sRGB {
                (self as! Image<UInt8>)._convertSRGBPremultipliedToPostmultiplied()
                return
            } else if self.colorSpace == .linearSRGB || self.colorSpace == .undefined {
                (self as! Image<UInt8>)._convertLinearPremultipliedToPostmultiplied()
                return
            }
        }
        
        let sourceColorSpace = self.colorSpace
        let alphaChannel = self.channelCount - 1
        
        for y in 0..<self.height {
            for x in 0..<self.width {
                let alpha = unormToFloat(self[x, y, channel: alphaChannel])
                for c in 0..<alphaChannel {
                    let floatVal = unormToFloat(self[x, y, channel: c])
                    let linearVal = clamp(ImageColorSpace.convert(floatVal, from: sourceColorSpace, to: .linearSRGB) / alpha, min: 0.0, max: 1.0)
                    self.setUnchecked(x: x, y: y, channel: c, value: floatToUnorm(ImageColorSpace.convert(linearVal, from: .linearSRGB, to: sourceColorSpace), type: T.self))
                }
            }
        }
    }
}

extension Image {
    @available(*, deprecated, renamed: "withImageReinterpreted(as:perform:)")
    @inlinable
    public func withTextureReinterpreted<U, Result>(as type: U.Type, perform: (Image<U>) throws -> Result) rethrows -> Result {
        return try self.withImageReinterpreted(as: type, perform: perform)
    }
    
    @inlinable
    public func withImageReinterpreted<U, Result>(as: U.Type, perform: (Image<U>) throws -> Result) rethrows -> Result {
        precondition(MemoryLayout<U>.stride == MemoryLayout<T>.stride, "\(U.self) is not layout compatible with \(T.self)")
        let storage = self.storage
        return try self.withUnsafeBufferPointer { buffer in
            return try buffer.withMemoryRebound(to: U.self) { reboundBuffer in
                let data = Image<U>(width: self.width, height: self.height, channels: self.channelCount, colorSpace: self.colorSpace, alphaMode: self.alphaMode, data: UnsafeMutablePointer(mutating: reboundBuffer.baseAddress!), deallocateFunc: { [storage] _ in _ = storage })
                return try perform(data)
            }
        }
    }
    
    @available(*, deprecated, renamed: "withMutableImageReinterpreted(as:perform:)")
    @inlinable
    public mutating func withMutableTextureReinterpreted<U, Result>(as type: U.Type, perform: (inout Image<U>) throws -> Result) rethrows -> Result {
        return try self.withMutableImageReinterpreted(as: type, perform: perform)
    }
    
    
    @inlinable
    public mutating func withMutableImageReinterpreted<U, Result>(as: U.Type, perform: (inout Image<U>) throws -> Result) rethrows -> Result {
        precondition(MemoryLayout<U>.stride == MemoryLayout<T>.stride, "\(U.self) is not layout compatible with \(T.self)")
        let width = self.width
        let height = self.height
        let channels = self.channelCount
        let colorSpace = self.colorSpace
        let alphaMode = self.alphaMode
        let storage = self.storage
        return try self.withUnsafeMutableBufferPointer { buffer in
            return try buffer.withMemoryRebound(to: U.self) { reboundBuffer in
                var data = Image<U>(width: width, height: height, channels: channels, colorSpace: colorSpace, alphaMode: alphaMode, data: reboundBuffer.baseAddress!, deallocateFunc: { [storage] _ in _ = storage })
                return try perform(&data)
            }
        }
    }
}

extension Image where T: BinaryInteger & FixedWidthInteger & SignedInteger {
    @inlinable
    public init(_ data: Image<Float>) {
        self.init(width: data.width, height: data.height, channels: data.channelCount, colorSpace: data.colorSpace, alphaMode: data.alphaMode)
        
        self.withUnsafeMutableBufferPointer { dest in
            data.withUnsafeBufferPointer { source in
                for (i, sourceVal) in source.enumerated() {
                    dest[i] = floatToSnorm(sourceVal, type: T.self)
                }
            }
        }
    }
}

extension Image where ComponentType == Float {
    
    @inlinable
    public init<I: BinaryInteger & FixedWidthInteger & SignedInteger>(_ data: Image<I>) {
        self.init(width: data.width, height: data.height, channels: data.channelCount, colorSpace: data.colorSpace, alphaMode: data.alphaMode)
        
        self.withUnsafeMutableBufferPointer { dest in
            data.withUnsafeBufferPointer { source in
                for (i, sourceVal) in source.enumerated() {
                    dest[i] = snormToFloat(sourceVal)
                }
            }
        }
    }
    
    @inlinable
    public init<I: BinaryInteger & FixedWidthInteger & UnsignedInteger>(_ data: Image<I>) {
        self.init(width: data.width, height: data.height, channels: data.channelCount, colorSpace: data.colorSpace, alphaMode: data.alphaMode)
        
        self.withUnsafeMutableBufferPointer { dest in
            data.withUnsafeBufferPointer { source in
                for (i, sourceVal) in source.enumerated() {
                    dest[i] = unormToFloat(sourceVal)
                }
            }
        }
    }
    
    public mutating func convert(toColorSpace: ImageColorSpace) {
        if toColorSpace == self.colorSpace || self.colorSpace == .undefined {
            return
        }
        
        let sourceColorSpace = self.colorSpace
        self.apply({ ImageColorSpace.convert($0, from: sourceColorSpace, to: toColorSpace) }, channelRange: self.channelCount == 4 ? 0..<3 : 0..<self.channelCount)
        self.colorSpace = toColorSpace
    }
    
    @available(*, deprecated, renamed: "convert(toColorSpace:)")
    public mutating func convert(toColourSpace: ImageColorSpace) {
        self.convert(toColorSpace: toColourSpace)
    }
    
    public mutating func convertToPremultipliedAlpha() {
        guard case .postmultiplied = self.alphaMode else { return }
        defer { self.alphaMode = .premultiplied }
        
        self.ensureUniqueness()
        
        let sourceColorSpace = self.colorSpace
        self.convert(toColorSpace: .linearSRGB)
        
        let alphaChannel = self.channelCount - 1
        for y in 0..<self.height {
            for x in 0..<self.width {
                for c in 0..<alphaChannel {
                    self.setUnchecked(x: x, y: y, channel: c, value: self[x, y, channel: c] * self[x, y, channel: alphaChannel])
                }
            }
        }
        
        self.convert(toColorSpace: sourceColorSpace)
    }
    
    public mutating func convertToPostmultipliedAlpha() {
        guard case .premultiplied = self.alphaMode else { return }
        
        defer { self.alphaMode = .postmultiplied }
        
        self.ensureUniqueness()
        
        let sourceColorSpace = self.colorSpace
        self.convert(toColorSpace: .linearSRGB)
        
        let alphaChannel = self.channelCount - 1
        for y in 0..<self.height {
            for x in 0..<self.width {
                let alpha = max(self[x, y, channel: alphaChannel], .leastNormalMagnitude)
                for c in 0..<alphaChannel {
                    let newValue = self[x, y, channel: c] / alpha
                    self.setUnchecked(x: x, y: y, channel: c, value: clamp(newValue, min: 0.0, max: 1.0))
                }
            }
        }
        
        self.convert(toColorSpace: sourceColorSpace)
        
    }
    
    public var averageValue : SIMD4<Float> {
        let scale = 1.0 / Float(self.width * self.height)
        var average = SIMD4<Float>(repeating: 0)
        for y in 0..<self.height {
            let yBase = y * self.width * self.channelCount
            for x in 0..<self.width {
                let baseIndex = yBase + x * self.channelCount
                for c in 0..<self.channelCount {
                    //                    assert(self.data[baseIndex + c].isFinite, "Pixel \(x), \(y), channel \(c) is not finite: value is \(self.data[baseIndex + c])")
                    average[c] += self.storage.data[baseIndex + c] * scale
                }
            }
        }
        return average
    }
}


extension Image where T: BinaryFloatingPoint {
    @inlinable
    public init<Other: BinaryFloatingPoint>(_ data: Image<Other>) {
        self.init(width: data.width, height: data.height, channels: data.channelCount, colorSpace: data.colorSpace, alphaMode: data.alphaMode)
        
        self.withUnsafeMutableBufferPointer { dest in
            data.withUnsafeBufferPointer { source in
                for (i, sourceVal) in source.enumerated() {
                    dest[i] = T(sourceVal)
                }
            }
        }
    }
}
