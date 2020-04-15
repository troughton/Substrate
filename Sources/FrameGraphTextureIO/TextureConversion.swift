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
    case noSupportedPixelFormat
}

public enum TextureColourSpace : String, Codable, Hashable {
    case sRGB
    case linearSRGB

    @inlinable
    public func fromLinearSRGB(_ colour: Float) -> Float {
        switch self {
        case .sRGB:
            return colour <= 0.04045 ? (colour / 12.92) : pow((colour + 0.055) / 1.055, 2.4)
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

public final class TextureData<T> {
    public let width : Int
    public let height : Int
    public let channels : Int
    public var colourSpace : TextureColourSpace
    public var premultipliedAlpha: Bool
    
    public let data : UnsafeMutablePointer<T>
    let deallocateFunc : ((UnsafeMutablePointer<T>) -> Void)?
    
    public init(width: Int, height: Int, channels: Int, colourSpace: TextureColourSpace, premultipliedAlpha: Bool = false) {
        self.width = width
        self.height = height
        self.channels = channels
        
        self.data = .allocate(capacity: width * height * channels)
        
        self.colourSpace = colourSpace
        self.premultipliedAlpha = premultipliedAlpha
        self.deallocateFunc = nil
    }
    
    public init(width: Int, height: Int, channels: Int, data: UnsafeMutablePointer<T>, colourSpace: TextureColourSpace, premultipliedAlpha: Bool = false, deallocateFunc: @escaping (UnsafeMutablePointer<T>) -> Void) {
        self.width = width
        self.height = height
        self.channels = channels
        
        self.data = data
        
        self.colourSpace = colourSpace
        self.premultipliedAlpha = premultipliedAlpha
        self.deallocateFunc = deallocateFunc
    }
    
    public init(_ texture: TextureData<T>) {
        self.width = texture.width
        self.height = texture.height
        self.channels = texture.channels
        
        self.data = .allocate(capacity: texture.width * texture.height * texture.channels)
        self.data.initialize(from: texture.data, count: texture.width * texture.height * texture.channels)
        
        self.colourSpace = texture.colourSpace
        self.premultipliedAlpha = texture.premultipliedAlpha
        self.deallocateFunc = nil
    }
    
    deinit {
        if let deallocateFunc = self.deallocateFunc {
            deallocateFunc(self.data)
        } else {
            self.data.deallocate()
        }
    }
    
    @inlinable
    public subscript(x: Int, y: Int, channel channel: Int) -> T {
        get {
            precondition(x >= 0 && y >= 0 && channel >= 0 && x < self.width && y < self.height && channel < self.channels)
            return self.data[y * self.width * self.channels + x * self.channels + channel]
        }
        set {
            precondition(x >= 0 && y >= 0 && channel >= 0 && x < self.width && y < self.height && channel < self.channels)
            self.data[y * self.width * self.channels + x * self.channels + channel] = newValue
        }
    }
    
    @inlinable
    public subscript(checked x: Int, y: Int, channel channel: Int) -> T? {
        guard x >= 0, y >= 0, channel >= 0,
            x < self.width, y < self.height, channel < self.channels else {
                return nil
        }
        return self.data[y * self.width * self.channels + x * self.channels + channel]
    }
    
    @inlinable
    public func apply(_ function: (T) -> T, channelRange: Range<Int>) {
        for y in 0..<self.height {
            let yBase = y * self.width * self.channels
            for x in 0..<self.width {
                let baseIndex = yBase + x * self.channels
                for c in channelRange {
                    self.data[baseIndex + c] = function(self.data[baseIndex + c])
                }
            }
        }
    }
    
    @inlinable
    public func forEachPixel(_ function: (_ x: Int, _ y: Int, _ channel: Int, _ value: T) -> Void) {
        for y in 0..<self.height {
            let yBase = y * self.width * self.channels
            for x in 0..<self.width {
                let baseIndex = yBase + x * self.channels
                for c in 0..<self.channels {
                    function(x, y, c, self.data[baseIndex + c])
                }
            }
        }
    }
    
    public func resize(width: Int, height: Int, wrapMode: TextureEdgeWrapMode) -> TextureData<T> {
        if width == self.width && height == self.height {
            return self
        }
        
        let result = TextureData<T>(width: width, height: height, channels: self.channels, colourSpace: self.colourSpace, premultipliedAlpha: premultipliedAlpha)
        
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
        
        stbir_resize(self.data, Int32(self.width), Int32(self.height), 0,
                     result.data, Int32(width), Int32(height), 0,
                     dataType,
                     Int32(self.channels),
                     self.channels == 4 ? 3 : -1,
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
            
            let nextMip = results.last!.resize(width: width, height: height, wrapMode: wrapMode)
            results.append(nextMip)
        }
        
        return results
    }
}

extension TextureData where T == UInt8 {
    public convenience init(_ texture: TextureData<Float>) {
        self.init(width: texture.width, height: texture.height, channels: texture.channels, colourSpace: texture.colourSpace, premultipliedAlpha: texture.premultipliedAlpha)
        
        for i in 0..<(self.width * self.height * self.channels) {
            self.data[i] = floatToUnorm(texture.data[i], type: UInt8.self)
        }
    }
}

extension TextureData where T == Float {
    public convenience init(fileAt url: URL, colourSpace: TextureColourSpace, premultipliedAlpha: Bool) throws {
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
                self.data[i] = unormToFloat(data[i])
            }
            
        } else {
            let data = stbi_load(url.path, &width, &height, &componentsPerPixel, channels)!
            defer { stbi_image_free(data) }
            
            self.init(width: Int(width), height: Int(height), channels: Int(channels), colourSpace: colourSpace, premultipliedAlpha: premultipliedAlpha)
            
            for i in 0..<dataCount {
                self.data[i] = unormToFloat(data[i])
            }
        }
    }
    
    convenience init(exrAt url: URL, colourSpace: TextureColourSpace, premultipliedAlpha: Bool = false) throws {
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
        self.data.initialize(repeating: 0.0, count: self.width * self.height * self.channels)
        
        
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
                                
                                self.data[self.channels * idx + channelIndex] = src[c][srcIdx]
                            }
                        }
                    }
                }
            } else {
                image.images.withMemoryRebound(to: UnsafePointer<Float>.self, capacity: Int(image.num_channels)) { src in
                    for y in 0..<self.height {
                        for x in 0..<self.width {
                            let i = y &* self.width &+ x
                            self.data[self.channels &* i + channelIndex] = src[c][i]
                        }
                    }
                }
                
            }
        }
    }
    
    public func convert(toColourSpace: TextureColourSpace) {
        self.apply({ TextureColourSpace.convert($0, from: self.colourSpace, to: toColourSpace) }, channelRange: self.channels == 4 ? 0..<3 : 0..<self.channels)
        self.colourSpace = toColourSpace
    }
    
    public var averageValue : SIMD4<Float> {
        let scale = 1.0 / Float(self.width * self.height)
        var average = SIMD4<Float>(repeating: 0)
        for y in 0..<self.height {
            let yBase = y * self.width * self.channels
            for x in 0..<self.width {
                let baseIndex = yBase + x * self.channels
                for c in 0..<self.channels {
                    //                    assert(self.data[baseIndex + c].isFinite, "Pixel \(x), \(y), channel \(c) is not finite: value is \(self.data[baseIndex + c])")
                    average[c] += self.data[baseIndex + c] * scale
                }
            }
        }
        return average
    }
}
