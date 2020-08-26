//
//  TextureConversion.swift
//  FrameGraphTextureLoading
//
//

import Foundation
import stb_image
import stb_image_resize
import SwiftFrameGraph
import tinyexr

@inlinable
func clamp<T: Comparable>(_ val: T, min minValue: T, max maxValue: T) -> T {
    return min(max(val, minValue), maxValue)
}

// Reference: https://docs.microsoft.com/en-us/windows/win32/direct3d10/d3d10-graphics-programming-guide-resources-data-conversion
@inlinable
public func floatToSnorm<I: BinaryInteger & FixedWidthInteger & SignedInteger>(_ c: Float, type: I.Type) -> I {
    if c.isNaN {
        return 0
    }
    let c = clamp(c, min: -1.0, max: 1.0)
    
    let scale = Float(I.max)
    let rescaled = c * scale
    return I(exactly: rescaled.rounded(.toNearestOrAwayFromZero))!
}

@inlinable
public func floatToUnorm<I: BinaryInteger & FixedWidthInteger & UnsignedInteger>(_ c: Float, type: I.Type) -> I {
    if c.isNaN {
        return 0
    }
    let c = clamp(c, min: 0.0, max: 1.0)
    let scale = Float(I.max)
    let rescaled = c * scale
    return I(exactly: rescaled.rounded(.toNearestOrAwayFromZero))!
}

@inlinable
public func snormToFloat<I: BinaryInteger & FixedWidthInteger & SignedInteger>(_ c: I) -> Float {
    if c == I.min {
        return -1.0
    }
    return Float(c) / Float(I.max)
}

@inlinable
public func unormToFloat<I: BinaryInteger & FixedWidthInteger & UnsignedInteger>(_ c: I) -> Float {
    return Float(c) / Float(I.max)
}

public enum TextureLoadingError : Error {
    case invalidFile(URL)
    case exrParseError(String)
    case unsupportedMultipartEXR(URL)
    case invalidChannelCount(URL, Int)
    case privateTextureRequiresFrameGraph
    case invalidTextureDataFormat(URL, Any.Type)
    case noSupportedPixelFormat
}

public enum TextureColorSpace : String, Codable, Hashable {
    case sRGB
    case linearSRGB

    @inlinable
    public func fromLinearSRGB(_ color: Float) -> Float {
        switch self {
        case .sRGB:
            return color <= 0.0031308 ? (12.92 * color) : (1.055 * pow(color, 1.0 / 2.4) - 0.055)
        case .linearSRGB:
            return color
        }
    }

    @inlinable
    public func toLinearSRGB(_ color: Float) -> Float {
        switch self {
        case .sRGB:
            return color <= 0.04045 ? (color / 12.92) : pow((color + 0.055) / 1.055, 2.4)
        case .linearSRGB:
            return color
        }
    }
    
    @inlinable
    public static func convert(_ value: Float, from: TextureColorSpace, to: TextureColorSpace) -> Float {
        if from == to { return value }
        
        let inLinearSRGB = from.toLinearSRGB(value)
        return to.fromLinearSRGB(inLinearSRGB)
    }
}

public typealias TextureColourSpace = TextureColorSpace

public enum TextureAlphaMode {
    case premultiplied
    case postmultiplied
    
    case inferred
    
    func inferFromFileFormat(fileExtension: String) -> TextureAlphaMode {
        if case .inferred = self, let format = TextureSaveFormat(rawValue: fileExtension.lowercased()) {
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

public enum TextureEdgeWrapMode {
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

public enum TextureResizeFilter {
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
final class TextureDataStorage<T> {
    @usableFromInline let data : UnsafeMutableBufferPointer<T>
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

public struct TextureData<T> {
    public let width : Int
    public let height : Int
    public let channelCount : Int
    
    public internal(set) var colorSpace : TextureColorSpace
    public internal(set) var alphaMode: TextureAlphaMode
    
    @usableFromInline var storage: TextureDataStorage<T>
    
    @available(*, deprecated, renamed: "colorSpace")
    public var colourSpace: TextureColorSpace {
        get {
            return self.colorSpace
        }
        set {
            self.colorSpace = newValue
        }
    }
    
    public init(width: Int, height: Int, channels: Int, colorSpace: TextureColorSpace, alphaMode: TextureAlphaMode = .premultiplied) {
        precondition(_isPOD(T.self))
        precondition(width >= 1 && height >= 1 && channels >= 1)
        precondition(alphaMode != .inferred, "Inferred alpha modes are only valid given existing data.")
        
        self.init(width: width, height: height, channels: channels, colorSpace: colorSpace, alphaModeAllowInferred: alphaMode)
    }
    
    init(width: Int, height: Int, channels: Int, colorSpace: TextureColorSpace, alphaModeAllowInferred alphaMode: TextureAlphaMode) {
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
    public init(width: Int, height: Int, channels: Int, colorSpace: TextureColorSpace, premultipliedAlpha: Bool) {
        self.init(width: width, height: height, channels: channels, colorSpace: colorSpace, alphaMode: premultipliedAlpha ? .premultiplied : .postmultiplied)
    }
    
    @available(*, deprecated, renamed: "init(width:height:channels:colorSpace:alphaMode:)")
    public init(width: Int, height: Int, channels: Int, colourSpace: TextureColorSpace, premultipliedAlpha: Bool = false) {
        self.init(width: width, height: height, channels: channels, colorSpace: colourSpace, alphaMode: premultipliedAlpha ? .premultiplied : .postmultiplied)
    }
    
    public init(width: Int, height: Int, channels: Int, data: UnsafeMutablePointer<T>, colorSpace: TextureColorSpace, alphaMode: TextureAlphaMode = .premultiplied, deallocateFunc: @escaping (UnsafeMutablePointer<T>) -> Void) {
        precondition(width >= 1 && height >= 1 && channels >= 1)
        precondition(alphaMode != .inferred, "Cannot infer the alpha mode when T is not Comparable.")
        
        self.width = width
        self.height = height
        self.channelCount = channels
        
        self.storage = .init(data: UnsafeMutableBufferPointer<T>(start: data, count: self.width * self.height * self.channelCount), deallocateFunc: deallocateFunc)
        
        self.colorSpace = colorSpace
        self.alphaMode = alphaMode
    }

    @available(*, deprecated, renamed: "init(width:height:channels:data:colorSpace:alphaMode:deallocateFunc:)")
    public init(width: Int, height: Int, channels: Int, data: UnsafeMutablePointer<T>, colorSpace: TextureColorSpace, premultipliedAlpha: Bool, deallocateFunc: @escaping (UnsafeMutablePointer<T>) -> Void) {
        self.init(width: width, height: height, channels: channels, data: data, colorSpace: colorSpace, alphaMode: premultipliedAlpha ? .premultiplied : .postmultiplied, deallocateFunc: deallocateFunc)
    }
    
    @available(*, deprecated, renamed: "init(width:height:channels:data:colorSpace:alphaMode:deallocateFunc:)")
    public init(width: Int, height: Int, channels: Int, data: UnsafeMutablePointer<T>, colourSpace: TextureColorSpace, premultipliedAlpha: Bool = false, deallocateFunc: @escaping (UnsafeMutablePointer<T>) -> Void) {
        self.init(width: width, height: height, channels: channels, data: data, colorSpace: colourSpace, alphaMode: premultipliedAlpha ? .premultiplied : .postmultiplied, deallocateFunc: deallocateFunc)
    }
    
    @inlinable
    mutating func ensureUniqueness() {
        if !isKnownUniquelyReferenced(&self.storage) {
            self.storage = .init(copying: self.storage.data)
        }
    }
    
    @available(*, deprecated, renamed: "alphaMode")
    @inlinable
    public var premultipliedAlpha: Bool {
        return self.alphaMode == .premultiplied
    }
    
    @inlinable
    public subscript(x: Int, y: Int, channel channel: Int) -> T {
        get {
            precondition(x >= 0 && y >= 0 && channel >= 0 && x < self.width && y < self.height && channel < self.channelCount)
            return self.storage.data[y * self.width * self.channelCount + x * self.channelCount + channel]
        }
        set {
            precondition(x >= 0 && y >= 0 && channel >= 0 && x < self.width && y < self.height && channel < self.channelCount)
            self.ensureUniqueness()
            self.storage.data[y * self.width * self.channelCount + x * self.channelCount + channel] = newValue
        }
    }
    
    @inlinable
    public subscript(checked x: Int, y: Int, channel channel: Int) -> T? {
        guard x >= 0, y >= 0, channel >= 0,
            x < self.width, y < self.height, channel < self.channelCount else {
                return nil
        }
        return self.storage.data[y * self.width * self.channelCount + x * self.channelCount + channel]
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
    public func cropped(originX: Int, originY: Int, width: Int, height: Int, clampOutOfBounds: Bool = false) -> TextureData<T> {
        precondition(clampOutOfBounds || (originX >= 0 && originY >= 0))
        precondition(clampOutOfBounds || (originX + width <= self.width && originY + height <= self.height))
        
        if width == self.width, height == self.height, originX == 0, originY == 0 {
            return self
        }
        
        var result = TextureData<T>(width: width, height: height, channels: self.channelCount, colorSpace: self.colorSpace, alphaMode: self.alphaMode)
        
        for y in 0..<height {
            let clampedY = clampOutOfBounds ? clamp(y + originY, min: 0, max: self.height - 1) : (y + originY)
            for x in 0..<width {
                let clampedX = clampOutOfBounds ? clamp(x + originX, min: 0, max: self.width - 1) : (x + originX)
                for c in 0..<self.channelCount {
                    result[x, y, channel: c] = self[clampedX, clampedY, channel: c]
                }
            }
        }
        
        return result
    }
    
    @inlinable
    public func resized(width: Int, height: Int, wrapMode: TextureEdgeWrapMode, filter: TextureResizeFilter = .default) -> TextureData<T> {
        if width == self.width && height == self.height {
            return self
        }
        
        let result = TextureData<T>(width: width, height: height, channels: self.channelCount, colorSpace: self.colorSpace, alphaMode: self.alphaMode)
        
        var flags : Int32 = 0
        if self.alphaMode == .premultiplied {
            flags |= STBIR_FLAG_ALPHA_PREMULTIPLIED
        }
        
        let colorSpace : stbir_colorspace
        switch self.colorSpace {
        case .linearSRGB:
            colorSpace = STBIR_COLORSPACE_LINEAR
        case .sRGB:
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
            fatalError("Unsupported TextureData type \(T.self) for mip chain generation.")
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
    
    public func generateMipChain(wrapMode: TextureEdgeWrapMode, compressedBlockSize: Int) -> [TextureData<T>] {
        var results = [self]
        
        var width = self.width
        var height = self.height
        while width >= 2 && height >= 2 {
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

extension TextureData where T: Comparable {
    public init(width: Int, height: Int, channels: Int, data: UnsafeMutablePointer<T>, colorSpace: TextureColorSpace, alphaMode: TextureAlphaMode = .premultiplied, deallocateFunc: @escaping (UnsafeMutablePointer<T>) -> Void) {
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
            self.alphaMode = .premultiplied
        }
    }
}

extension TextureData where T: SIMDScalar {
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

extension TextureData where T: BinaryInteger & FixedWidthInteger & UnsignedInteger {
    @inlinable
    public init(_ data: TextureData<Float>) {
        self.init(width: data.width, height: data.height, channels: data.channelCount, colorSpace: data.colorSpace, alphaMode: data.alphaMode)
        
        self.withUnsafeMutableBufferPointer { dest in
            data.withUnsafeBufferPointer { source in
                for (i, sourceVal) in source.enumerated() {
                    dest[i] = floatToUnorm(sourceVal, type: T.self)
                }
            }
        }
    }
    
    public mutating func convert(toColorSpace: TextureColorSpace) {
        if toColorSpace == self.colorSpace {
            return
        }
        
        let sourceColorSpace = self.colorSpace
        self.apply({ floatToUnorm(TextureColorSpace.convert(unormToFloat($0), from: sourceColorSpace, to: toColorSpace), type: T.self) }, channelRange: self.channelCount == 4 ? 0..<3 : 0..<self.channelCount)
        self.colorSpace = toColorSpace
    }
    
    public mutating func convertToPremultipliedAlpha() {
        guard case .postmultiplied = self.alphaMode, self.channelCount == 4 else { return }
        self.ensureUniqueness()
        
        let sourceColorSpace = self.colorSpace
        
        for y in 0..<self.height {
            for x in 0..<self.width {
                let alpha = unormToFloat(self[x, y, channel: 3])
                for c in 0..<3 {
                    let floatVal = unormToFloat(self[x, y, channel: c])
                    let linearVal = TextureColourSpace.convert(floatVal, from: sourceColorSpace, to: .linearSRGB) * alpha
                    self[x, y, channel: c] = floatToUnorm(TextureColourSpace.convert(linearVal, from: .linearSRGB, to: sourceColorSpace), type: T.self)
                }
            }
        }
        
        self.alphaMode = .premultiplied
    }
    
    public mutating func convertToPostmultipliedAlpha() {
        guard case .premultiplied = self.alphaMode, self.channelCount == 4 else { return }
        self.ensureUniqueness()
        
        let sourceColorSpace = self.colorSpace
        
        for y in 0..<self.height {
            for x in 0..<self.width {
                let alpha = unormToFloat(self[x, y, channel: 3])
                for c in 0..<3 {
                    let floatVal = unormToFloat(self[x, y, channel: c])
                    let linearVal = clamp(TextureColourSpace.convert(floatVal, from: sourceColorSpace, to: .linearSRGB) / alpha, min: 0.0, max: 1.0)
                    self[x, y, channel: c] = floatToUnorm(TextureColourSpace.convert(linearVal, from: .linearSRGB, to: sourceColorSpace), type: T.self)
                }
            }
        }
        
        self.alphaMode = .postmultiplied
    }
}

extension TextureData where T: BinaryInteger & FixedWidthInteger & SignedInteger {
    @inlinable
    public init(_ data: TextureData<Float>) {
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

extension TextureData where T == UInt8 {
    public init(fileAt url: URL, colorSpace: TextureColorSpace, alphaMode: TextureAlphaMode) throws {
        var width : Int32 = 0
        var height : Int32 = 0
        var componentsPerPixel : Int32 = 0
        guard stbi_info(url.path, &width, &height, &componentsPerPixel) != 0 else {
            throw TextureLoadingError.invalidFile(url)
        }
        
        let channels = componentsPerPixel == 3 ? 4 : componentsPerPixel
        
        guard let data = stbi_load(url.path, &width, &height, &componentsPerPixel, Int32(channels)) else {
            throw TextureLoadingError.invalidTextureDataFormat(url, T.self)
        }
        
        self.init(width: Int(width), height: Int(height), channels: Int(channels), data: data, colorSpace: colorSpace, alphaMode: alphaMode.inferFromFileFormat(fileExtension: url.pathExtension), deallocateFunc: { stbi_image_free($0) })
    }
}

extension TextureData where T == UInt16 {
    public init(fileAt url: URL, colorSpace: TextureColorSpace, alphaMode: TextureAlphaMode = .inferred) throws {
        var width : Int32 = 0
        var height : Int32 = 0
        var componentsPerPixel : Int32 = 0
        guard stbi_info(url.path, &width, &height, &componentsPerPixel) != 0 else {
            throw TextureLoadingError.invalidFile(url)
        }
        
        let channels = componentsPerPixel == 3 ? 4 : componentsPerPixel
        
        guard let data = stbi_load_16(url.path, &width, &height, &componentsPerPixel, Int32(channels)) else {
            throw TextureLoadingError.invalidTextureDataFormat(url, T.self)
        }
        
        self.init(width: Int(width), height: Int(height), channels: Int(channels), data: data, colorSpace: colorSpace, alphaMode: alphaMode.inferFromFileFormat(fileExtension: url.pathExtension), deallocateFunc: { stbi_image_free($0) })
    }
    
    @available(*, deprecated, renamed: "init(fileAt:colorSpace:alphaMode:)")
    public init(fileAt url: URL, colorSpace: TextureColorSpace, premultipliedAlpha: Bool) throws {
        try self.init(fileAt: url, colorSpace: colorSpace, premultipliedAlpha: premultipliedAlpha)
    }
    
    @available(*, deprecated, renamed: "init(fileAt:colorSpace:alphaMode:)")
    public init(fileAt url: URL, colourSpace: TextureColorSpace, premultipliedAlpha: Bool) throws {
        try self.init(fileAt: url, colorSpace: colourSpace, premultipliedAlpha: premultipliedAlpha)
    }
}

extension TextureData where T == Float {
    
    @inlinable
    public init<I: BinaryInteger & FixedWidthInteger & SignedInteger>(_ data: TextureData<I>) {
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
    public init<I: BinaryInteger & FixedWidthInteger & UnsignedInteger>(_ data: TextureData<I>) {
        self.init(width: data.width, height: data.height, channels: data.channelCount, colorSpace: data.colorSpace, alphaMode: data.alphaMode)
        
        self.withUnsafeMutableBufferPointer { dest in
            data.withUnsafeBufferPointer { source in
                for (i, sourceVal) in source.enumerated() {
                    dest[i] = unormToFloat(sourceVal)
                }
            }
        }
    }
    
    public init(fileAt url: URL, colorSpace: TextureColorSpace, alphaMode: TextureAlphaMode = .inferred) throws {
        if url.pathExtension.lowercased() == "exr" {
            try self.init(exrAt: url, colorSpace: colorSpace, alphaMode: alphaMode)
            return
        }
        
        var width : Int32 = 0
        var height : Int32 = 0
        var componentsPerPixel : Int32 = 0
        guard stbi_info(url.path, &width, &height, &componentsPerPixel) != 0 else {
            throw TextureLoadingError.invalidFile(url)
        }
        
        let channels = componentsPerPixel == 3 ? 4 : componentsPerPixel
        
        let isHDR = stbi_is_hdr(url.path) != 0
        let is16Bit = stbi_is_16_bit(url.path) != 0
        
        let dataCount = Int(width * height * channels)
        
        if isHDR {
            let data = stbi_loadf(url.path, &width, &height, &componentsPerPixel, channels)!
            self.init(width: Int(width), height: Int(height), channels: Int(channels), data: data, colorSpace: colorSpace, alphaMode: alphaMode.inferFromFileFormat(fileExtension: url.pathExtension), deallocateFunc: { stbi_image_free($0) })
            
        } else if is16Bit {
            let data = stbi_load_16(url.path, &width, &height, &componentsPerPixel, channels)!
            defer { stbi_image_free(data) }
            
            self.init(width: Int(width), height: Int(height), channels: Int(channels), colorSpace: colorSpace, alphaModeAllowInferred: alphaMode.inferFromFileFormat(fileExtension: url.pathExtension))
            
            for i in 0..<dataCount {
                self.storage.data[i] = unormToFloat(data[i])
            }
            
            self.inferAlphaMode()
            
        } else {
            let data = stbi_load(url.path, &width, &height, &componentsPerPixel, channels)!
            defer { stbi_image_free(data) }
            
            self.init(width: Int(width), height: Int(height), channels: Int(channels), colorSpace: colorSpace, alphaModeAllowInferred: alphaMode.inferFromFileFormat(fileExtension: url.pathExtension))
            
            for i in 0..<dataCount {
                self.storage.data[i] = unormToFloat(data[i])
            }
            
            self.inferAlphaMode()
        }
    }
    
    
    @available(*, deprecated, renamed: "init(fileAt:colorSpace:alphaMode:)")
    public init(fileAt url: URL, colorSpace: TextureColorSpace, premultipliedAlpha: Bool) throws {
        try self.init(fileAt: url, colorSpace: colorSpace, alphaMode: premultipliedAlpha ? .premultiplied : .postmultiplied)
    }
    
    @available(*, deprecated, renamed: "init(fileAt:colorSpace:alphaMode:)")
    public init(fileAt url: URL, colourSpace: TextureColorSpace, premultipliedAlpha: Bool) throws {
        try self.init(fileAt: url, colorSpace: colourSpace, alphaMode: premultipliedAlpha ? .premultiplied : .postmultiplied)
    }
    
    init(exrAt url: URL, colorSpace: TextureColorSpace, alphaMode: TextureAlphaMode) throws {
        var header = EXRHeader()
        InitEXRHeader(&header)
        var image = EXRImage()
        InitEXRImage(&image)
        
        var error: UnsafePointer<CChar>? = nil
        
        defer {
            FreeEXRImage(&image)
            FreeEXRHeader(&header)
            error.map { FreeEXRErrorMessage($0) }
        }
        
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        try data.withUnsafeBytes { data in
            
            let memory = data.bindMemory(to: UInt8.self)
            
            var version = EXRVersion()
            var result = ParseEXRVersionFromMemory(&version, memory.baseAddress, memory.count)
            if result != TINYEXR_SUCCESS {
                throw TextureLoadingError.exrParseError("Unable to parse EXR version")
            }
            
            result = ParseEXRHeaderFromMemory(&header, &version, memory.baseAddress, memory.count, &error)
            if result != TINYEXR_SUCCESS {
                throw TextureLoadingError.exrParseError(String(cString: error!))
            }
            
            for i in 0..<Int(header.num_channels) {
                header.requested_pixel_types[i] = TINYEXR_PIXELTYPE_FLOAT
            }
            
            result = LoadEXRImageFromMemory(&image, &header, memory.baseAddress, memory.count, &error)
            if result != TINYEXR_SUCCESS {
                throw TextureLoadingError.exrParseError(String(cString: error!))
            }
        }
        
        self.init(width: Int(image.width), height: Int(image.height), channels: image.num_channels == 3 ? 4 : Int(image.num_channels), colorSpace: colorSpace, alphaModeAllowInferred: alphaMode.inferFromFileFormat(fileExtension: "exr"))
        self.storage.data.initialize(repeating: 0.0)
        
        
        for c in 0..<Int(image.num_channels) {
            let channelIndex : Int
            switch (UInt8(bitPattern: header.channels[c].name.0), header.channels[c].name.1) {
            case (UInt8(ascii: "R"), 0):
                channelIndex = 0
            case (UInt8(ascii: "G"), 0):
                channelIndex = 1
            case (UInt8(ascii: "B"), 0):
                channelIndex = 2
            case (UInt8(ascii: "A"), 0):
                channelIndex = 3
            default:
                channelIndex = c
            }
            
            if header.tiled != 0 {
                for it in 0..<Int(image.num_tiles) {
                    let src = UnsafeRawPointer(image.tiles![it].images)!.bindMemory(to: UnsafePointer<Float>.self, capacity: Int(image.num_channels))
                    for j in 0..<header.tile_size_y {
                        for i in 0..<header.tile_size_x {
                            let ii =
                                image.tiles![it].offset_x * header.tile_size_x + i
                            let jj =
                                image.tiles![it].offset_y * header.tile_size_y + j
                            let idx = Int(ii + jj * image.width)
                            
                            // out of region check.
                            if ii >= image.width || jj >= image.height {
                                continue;
                            }
                            let srcIdx = Int(i + j * header.tile_size_x)
                            
                            self.storage.data[self.channelCount * idx + channelIndex] = src[c][srcIdx]
                        }
                    }
                }
            } else {
                let src = UnsafeRawPointer(image.images)!.bindMemory(to: UnsafePointer<Float>.self, capacity: Int(image.num_channels))
                for y in 0..<self.height {
                    for x in 0..<self.width {
                        let i = y &* self.width &+ x
                        self.storage.data[self.channelCount &* i + channelIndex] = src[c][i]
                    }
                }
                
            }
        }
        
        self.inferAlphaMode()
    }
    
    public mutating func convert(toColorSpace: TextureColorSpace) {
        if toColorSpace == self.colorSpace {
            return
        }
        
        let sourceColorSpace = self.colorSpace
        self.apply({ TextureColorSpace.convert($0, from: sourceColorSpace, to: toColorSpace) }, channelRange: self.channelCount == 4 ? 0..<3 : 0..<self.channelCount)
        self.colorSpace = toColorSpace
    }
    
    @available(*, deprecated, renamed: "convert(toColorSpace:)")
    public mutating func convert(toColourSpace: TextureColorSpace) {
        self.convert(toColorSpace: toColourSpace)
    }
    
    public mutating func convertToPremultipliedAlpha() {
        guard case .postmultiplied = self.alphaMode, self.channelCount == 4 else { return }
        self.ensureUniqueness()
        
        let sourceColorSpace = self.colorSpace
        self.convert(toColorSpace: .linearSRGB)
        
        for y in 0..<self.height {
            for x in 0..<self.width {
                for c in 0..<3 {
                    self[x, y, channel: c] *= self[x, y, channel: 3]
                }
            }
        }
        
        self.convert(toColorSpace: sourceColorSpace)
        self.alphaMode = .premultiplied
    }
    
    public mutating func convertToPostmultipliedAlpha() {
        guard case .premultiplied = self.alphaMode, self.channelCount == 4 else { return }
        self.ensureUniqueness()
        
        let sourceColorSpace = self.colorSpace
        self.convert(toColorSpace: .linearSRGB)
        
        for y in 0..<self.height {
            for x in 0..<self.width {
                for c in 0..<3 {
                    self[x, y, channel: c] /= self[x, y, channel: 3]
                    self[x, y, channel: c] = clamp(self[x, y, channel: c], min: 0.0, max: 1.0)
                }
            }
        }
        
        self.convert(toColorSpace: sourceColorSpace)
        
        self.alphaMode = .postmultiplied
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
