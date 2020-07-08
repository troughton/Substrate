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

public enum TextureColourSpace : String, Codable, Hashable {
    case sRGB
    case linearSRGB

    @inlinable
    public func fromLinearSRGB(_ colour: Float) -> Float {
        switch self {
        case .sRGB:
            return colour <= 0.0031308 ? (12.92 * colour) : (1.055 * pow(colour, 1.0 / 2.4) - 0.055)
        case .linearSRGB:
            return colour
        }
    }

    @inlinable
    public func toLinearSRGB(_ colour: Float) -> Float {
        switch self {
        case .sRGB:
            return colour <= 0.04045 ? (colour / 12.92) : pow((colour + 0.055) / 1.055, 2.4)
        case .linearSRGB:
            return colour
        }
    }
    
    @inlinable
    public static func convert(_ value: Float, from: TextureColourSpace, to: TextureColourSpace) -> Float {
        if from == to { return value }
        
        let inLinearSRGB = from.toLinearSRGB(value)
        return to.fromLinearSRGB(inLinearSRGB)
    }
}

public enum TextureEdgeWrapMode {
    case zero
    case wrap
    case reflect
    case clamp
    
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

@usableFromInline
final class TextureDataStorage<T> {
    @usableFromInline let data : UnsafeMutableBufferPointer<T>
    @usableFromInline let deallocateFunc : ((UnsafeMutablePointer<T>) -> Void)?
    
    @inlinable
    init(elementCount: Int) {
        self.data = .allocate(capacity: elementCount)
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
    
    public internal(set) var colourSpace : TextureColourSpace
    public internal(set) var premultipliedAlpha: Bool
    
    @usableFromInline var storage: TextureDataStorage<T>
    
    public init(width: Int, height: Int, channels: Int, colourSpace: TextureColourSpace, premultipliedAlpha: Bool = false) {
        precondition(width >= 1 && height >= 1 && channels >= 1)
        self.width = width
        self.height = height
        self.channelCount = channels
        
        self.storage = .init(elementCount: width * height * channelCount)
        
        self.colourSpace = colourSpace
        self.premultipliedAlpha = premultipliedAlpha
    }
    
    public init(width: Int, height: Int, channels: Int, data: UnsafeMutablePointer<T>, colourSpace: TextureColourSpace, premultipliedAlpha: Bool = false, deallocateFunc: @escaping (UnsafeMutablePointer<T>) -> Void) {
        precondition(width >= 1 && height >= 1 && channels >= 1)
        
        self.width = width
        self.height = height
        self.channelCount = channels
        
        self.storage = .init(data: UnsafeMutableBufferPointer<T>(start: data, count: self.width * self.height * self.channelCount), deallocateFunc: deallocateFunc)
        
        self.colourSpace = colourSpace
        self.premultipliedAlpha = premultipliedAlpha
    }
    
    @inlinable
    mutating func ensureUniqueness() {
        if !isKnownUniquelyReferenced(&self.storage) {
            self.storage = .init(copying: self.storage.data)
        }
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
    
    public func cropped(originX: Int, originY: Int, width: Int, height: Int, clampOutOfBounds: Bool = false) -> TextureData<T> {
        precondition(clampOutOfBounds || (originX >= 0 && originY >= 0))
        precondition(clampOutOfBounds || (originX + width <= self.width && originY + height <= self.height))
        
        if width == self.width, height == self.height, originX == 0, originY == 0 {
            return self
        }
        
        var result = TextureData<T>(width: width, height: height, channels: self.channelCount, colourSpace: self.colourSpace, premultipliedAlpha: self.premultipliedAlpha)
        
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
    
    public func resized(width: Int, height: Int, wrapMode: TextureEdgeWrapMode) -> TextureData<T> {
        if width == self.width && height == self.height {
            return self
        }
        
        let result = TextureData<T>(width: width, height: height, channels: self.channelCount, colourSpace: self.colourSpace, premultipliedAlpha: self.premultipliedAlpha)
        
        var flags : Int32 = 0
        if self.premultipliedAlpha {
            flags |= STBIR_FLAG_ALPHA_PREMULTIPLIED
        }
        
        let colourSpace : stbir_colorspace
        switch self.colourSpace {
        case .linearSRGB:
            colourSpace = STBIR_COLORSPACE_LINEAR
        case .sRGB:
            colourSpace = STBIR_COLORSPACE_SRGB
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
                     STBIR_FILTER_DEFAULT, STBIR_FILTER_DEFAULT,
                     colourSpace, nil)
        
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
        self.init(width: data.width, height: data.height, channels: data.channelCount, colourSpace: data.colourSpace, premultipliedAlpha: data.premultipliedAlpha)
        
        self.withUnsafeMutableBufferPointer { dest in
            data.withUnsafeBufferPointer { source in
                for (i, sourceVal) in source.enumerated() {
                    dest[i] = floatToUnorm(sourceVal, type: T.self)
                }
            }
        }
    }
}

extension TextureData where T: BinaryInteger & FixedWidthInteger & SignedInteger {
    @inlinable
    public init(_ data: TextureData<Float>) {
        self.init(width: data.width, height: data.height, channels: data.channelCount, colourSpace: data.colourSpace, premultipliedAlpha: data.premultipliedAlpha)
        
        self.withUnsafeMutableBufferPointer { dest in
            data.withUnsafeBufferPointer { source in
                for (i, sourceVal) in source.enumerated() {
                    dest[i] = floatToSnorm(sourceVal, type: T.self)
                }
            }
        }
    }
}

extension TextureData where T == UInt16 {
    public init(fileAt url: URL, colourSpace: TextureColourSpace, premultipliedAlpha: Bool) throws {
        var width : Int32 = 0
        var height : Int32 = 0
        var componentsPerPixel : Int32 = 0
        guard stbi_info(url.path, &width, &height, &componentsPerPixel) != 0 else {
            throw TextureLoadingError.invalidFile(url)
        }
        
        let channels = componentsPerPixel
        
        guard let data = stbi_load_16(url.path, &width, &height, &componentsPerPixel, Int32(channels)) else {
            throw TextureLoadingError.invalidTextureDataFormat(url, T.self)
        }
        
        self.init(width: Int(width), height: Int(height), channels: Int(channels), data: data, colourSpace: colourSpace, premultipliedAlpha: premultipliedAlpha, deallocateFunc: { stbi_image_free($0) })
    }
}

extension TextureData where T == Float {
    
    @inlinable
    public init<I: BinaryInteger & FixedWidthInteger & SignedInteger>(_ data: TextureData<I>) {
        self.init(width: data.width, height: data.height, channels: data.channelCount, colourSpace: data.colourSpace, premultipliedAlpha: data.premultipliedAlpha)
        
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
        self.init(width: data.width, height: data.height, channels: data.channelCount, colourSpace: data.colourSpace, premultipliedAlpha: data.premultipliedAlpha)
        
        self.withUnsafeMutableBufferPointer { dest in
            data.withUnsafeBufferPointer { source in
                for (i, sourceVal) in source.enumerated() {
                    dest[i] = unormToFloat(sourceVal)
                }
            }
        }
    }
    
    public init(fileAt url: URL, colourSpace: TextureColourSpace, premultipliedAlpha: Bool) throws {
        if url.pathExtension.lowercased() == "exr" {
            try self.init(exrAt: url, colourSpace: colourSpace)
            return
        }
        
        var width : Int32 = 0
        var height : Int32 = 0
        var componentsPerPixel : Int32 = 0
        guard stbi_info(url.path, &width, &height, &componentsPerPixel) != 0 else {
            throw TextureLoadingError.invalidFile(url)
        }
        
        let channels = componentsPerPixel
        
        let isHDR = stbi_is_hdr(url.path) != 0
        let is16Bit = stbi_is_16_bit(url.path) != 0
        
        let dataCount = Int(width * height * componentsPerPixel)
        
        if isHDR {
            let data = stbi_loadf(url.path, &width, &height, &componentsPerPixel, channels)!
            self.init(width: Int(width), height: Int(height), channels: Int(channels), data: data, colourSpace: colourSpace, premultipliedAlpha: premultipliedAlpha, deallocateFunc: { stbi_image_free($0) })
            
        } else if is16Bit {
            let data = stbi_load_16(url.path, &width, &height, &componentsPerPixel, channels)!
            defer { stbi_image_free(data) }
            
            self.init(width: Int(width), height: Int(height), channels: Int(channels), colourSpace: colourSpace, premultipliedAlpha: premultipliedAlpha)
            
            for i in 0..<dataCount {
                self.storage.data[i] = unormToFloat(data[i])
            }
            
        } else {
            let data = stbi_load(url.path, &width, &height, &componentsPerPixel, channels)!
            defer { stbi_image_free(data) }
            
            self.init(width: Int(width), height: Int(height), channels: Int(channels), colourSpace: colourSpace, premultipliedAlpha: premultipliedAlpha)
            
            for i in 0..<dataCount {
                self.storage.data[i] = unormToFloat(data[i])
            }
        }
    }
    
    init(exrAt url: URL, colourSpace: TextureColourSpace, premultipliedAlpha: Bool = false) throws {
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
        
        self.init(width: Int(image.width), height: Int(image.height), channels: image.num_channels == 3 ? 4 : Int(image.num_channels), colourSpace: colourSpace, premultipliedAlpha: premultipliedAlpha)
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
                    image.tiles![it].images.withMemoryRebound(to: UnsafePointer<Float>.self, capacity: Int(image.num_channels)) { src in
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
                }
            } else {
                image.images.withMemoryRebound(to: UnsafePointer<Float>.self, capacity: Int(image.num_channels)) { src in
                    for y in 0..<self.height {
                        for x in 0..<self.width {
                            let i = y &* self.width &+ x
                            self.storage.data[self.channelCount &* i + channelIndex] = src[c][i]
                        }
                    }
                }
                
            }
        }
    }
    
    public mutating func convert(toColourSpace: TextureColourSpace) {
        if toColourSpace == self.colourSpace {
            return
        }
        
        let sourceColourSpace = self.colourSpace
        self.apply({ TextureColourSpace.convert($0, from: sourceColourSpace, to: toColourSpace) }, channelRange: self.channelCount == 4 ? 0..<3 : 0..<self.channelCount)
        self.colourSpace = toColourSpace
    }
    
    public mutating func convertToPremultipliedAlpha() {
        guard !self.premultipliedAlpha, self.channelCount == 4 else { return }
        self.ensureUniqueness()
        
        let sourceColourSpace = self.colourSpace
        self.convert(toColourSpace: .linearSRGB)
        
        for y in 0..<self.height {
            for x in 0..<self.width {
                for c in 0..<3 {
                    self[x, y, channel: c] *= self[x, y, channel: 3]
                }
            }
        }
        
        self.convert(toColourSpace: sourceColourSpace)
        self.premultipliedAlpha = true
    }
    
    public mutating func convertToPostmultipliedAlpha() {
        guard self.premultipliedAlpha, self.channelCount == 4 else { return }
        self.ensureUniqueness()
        
        let sourceColourSpace = self.colourSpace
        self.convert(toColourSpace: .linearSRGB)
        
        for y in 0..<self.height {
            for x in 0..<self.width {
                for c in 0..<3 {
                    self[x, y, channel: c] /= self[x, y, channel: 3]
                    self[x, y, channel: c] = clamp(self[x, y, channel: c], min: 0.0, max: 1.0)
                }
            }
        }
        
        self.convert(toColourSpace: sourceColourSpace)
        
        self.premultipliedAlpha = false
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
