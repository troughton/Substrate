import Foundation
import stb_image_write
import tinyexr
import LodePNG

#if canImport(zlib)
import zlib
#endif

@available(*, deprecated, renamed: "ImageFileFormat")
public typealias TextureFileFormat = ImageFileFormat

public enum ImageFileFormat: String, CaseIterable, Hashable {
    case png
    case bmp
    case tga
    case hdr
    case jpg
    case exr
    
    public init?(extension: String) {
        switch `extension`.lowercased() {
        case "png":
            self = .png
        case "bmp":
            self = .bmp
        case "tga":
            self = .tga
        case "hdr":
            self = .hdr
        case "jpeg", "jpg":
            self = .jpg
        case "exr":
            self = .exr
        default:
            return nil
        }
    }
    
    public var isLinearHDR : Bool {
        switch self {
        case .hdr, .exr:
            return true
        default:
            return false
        }
    }
    
    public var fileExtension : String {
        return self.rawValue
    }
}

public enum TextureSaveError: Error {
    case unknownFormat(String)
    case errorWritingFile(String)
    case invalidChannelCount(Int)
    case unexpectedDataFormat(found: Any.Type, required: [Any.Type])
}

public struct PNGCompressionSettings {
    public enum LZBlockType: UInt32 {
        case uncompressed = 0
        case type1 = 1
        case type2 = 2
        case type3 = 3
    }
    
    public enum WindowSize: UInt32 {
        case size1 = 1
        case size2 = 2
        case size4 = 4
        case size8 = 8
        case size16 = 16
        case size32 = 32
        case size64 = 64
        case size128 = 128
        case size256 = 256
        case size512 = 512
        case size1024 = 1024
        case size2048 = 2048
        case size4096 = 4096
        case size8192 = 8192
        case size16384 = 16384
        case size32768 = 32768
    }
    
    public enum FilterType {
        /// Every filter at zero.
        case zero
        /// Use the filter that gives the minimum sum, as described in the official PNG filter heuristic.
        case minimumSum
        /// Use the filter type that gives smallest Shannon entropy for this scanline. Depending on the image, this is better or worse than minimumSum.
        case entropy
        /// Brute-force-search PNG filters by compressing each filter for each scanline.
        /// Experimental, very slow, and only rarely gives better compression than minimumSum.
        case bruteForce
    }
    
    public var filterType: FilterType = .minimumSum
    
    public var useLZ77 = true
    /// The LZ block type to use for compression.
    public var blockType: LZBlockType = .type2
    /// The compression window size. A higher window size compresses more but is slower
    public var windowSize: WindowSize = .size2048
    /// The minimum LZ77 match length. 3 is normally best, but 6 can be better for some PNGs
    public var minimumMatchLength = 3
    /// Stop searching if a match of at least this length is found. Set to 258 for best compression.
    public var targetMatchLength = 128
    /// Use lazy matching. Slightly slower but better compression.
    public var useLazyMatching = true
    /// The compression level from 0 to 10 to use with zlib, if available. Overrides other zlib-related settings in this struct.
    public var zlibCompressionLevel: Int32?
    
    public init() {
    }
    
    public static var uncompressed: PNGCompressionSettings {
        var settings = PNGCompressionSettings()
        settings.filterType = .zero
        settings.useLZ77 = false
        settings.blockType = .uncompressed
        #if canImport(zlib)
        settings.zlibCompressionLevel = Z_NO_COMPRESSION
        #endif
        return settings
    }

    public static var fast: PNGCompressionSettings {
        var settings = PNGCompressionSettings()
        settings.filterType = .zero
        settings.windowSize = .size16
        settings.minimumMatchLength = 0
        settings.targetMatchLength = 16
        settings.useLazyMatching = false
        #if canImport(zlib)
        settings.zlibCompressionLevel = Z_BEST_SPEED
        #endif
        return settings
    }
    
    public static var `default`: PNGCompressionSettings {
        var settings = PNGCompressionSettings()
        #if canImport(zlib)
        settings.zlibCompressionLevel = Z_DEFAULT_COMPRESSION
        #endif
        return settings
    }
    
    public static var maxCompression: PNGCompressionSettings {
        var settings = PNGCompressionSettings()
        settings.blockType = .type2
        settings.windowSize = .size32768
        settings.targetMatchLength = 256
        #if canImport(zlib)
        settings.zlibCompressionLevel = Z_BEST_COMPRESSION
        #endif
        return settings
    }
}

fileprivate extension LodePNGColorType {
    init(channelCount: Int) throws {
        switch channelCount {
        case 1:
            self = LCT_GREY
        case 2:
            self = LCT_GREY_ALPHA
        case 3:
            self = LCT_RGB
        case 4:
            self = LCT_RGBA
        default:
            throw TextureSaveError.invalidChannelCount(channelCount)
        }
    }
}

fileprivate extension LodePNGEncoderSettings {
    mutating func fill(from settings: PNGCompressionSettings) {
        switch settings.filterType {
        case .zero:
            self.filter_strategy = LFS_ZERO
        case .minimumSum:
            self.filter_strategy = LFS_MINSUM
        case .entropy:
            self.filter_strategy = LFS_ENTROPY
        case .bruteForce:
            self.filter_strategy = LFS_BRUTE_FORCE
        }
        self.zlibsettings.use_lz77 = settings.useLZ77 ? 1 : 0
        self.zlibsettings.btype = settings.blockType.rawValue
        self.zlibsettings.windowsize = settings.windowSize.rawValue
        self.zlibsettings.minmatch = UInt32(settings.minimumMatchLength)
        self.zlibsettings.nicematch = UInt32(settings.targetMatchLength)
        self.zlibsettings.lazymatching = settings.useLazyMatching ? 1 : 0
        
        #if canImport(zlib)
        if let zlibCompressionLevel = settings.zlibCompressionLevel {
            self.zlibsettings.custom_context = UnsafeRawPointer(bitPattern: Int(zlibCompressionLevel))
            
            self.zlibsettings.custom_zlib = { out, outsize, `in`, inSize, settings in
                let compressionLevel = Int32(Int(bitPattern: settings?.pointee.custom_context))
                let bufferSize = Int(compressBound(uLong(inSize)))
                out!.pointee = malloc(bufferSize).assumingMemoryBound(to: UInt8.self)
                outsize!.pointee = bufferSize
                
                let result = compress2(out!.pointee, unsafeBitCast(outsize, to: UnsafeMutablePointer<uLongf>?.self), `in`, uLong(inSize), compressionLevel)
                return UInt32(bitPattern: result)
            }
        }
        #endif
    }
}

fileprivate extension LodePNGInfo {
    mutating func setColorSpace(_ colorSpace: ImageColorSpace) {
        switch colorSpace {
        case .undefined:
            break
        case .linearSRGB:
            self.gama_defined = 1
            self.gama_gamma = 100_000 // Gamma exponent times 100000
        case .gammaSRGB(let gamma):
            self.gama_defined = 1
            self.gama_gamma = UInt32(100_000.0 * gamma) // Gamma exponent times 100000
        case .sRGB:
            self.srgb_defined = 1
            self.srgb_intent = 1 // relative colorimetric
        }
    }
}

extension Image {
    public typealias SaveFormat = ImageFileFormat
    
    public func write(to url: URL) throws {
        guard let saveFormat = ImageFileFormat(extension: url.pathExtension) else {
            throw TextureSaveError.unknownFormat(url.pathExtension)
        }
        
        switch saveFormat {
        case .png:
            if let texture = self as? Image<UInt8> {
                try texture.writePNG(to: url)
            } else if let texture = self as? Image<UInt16> {
                try texture.writePNG(to: url)
            } else {
                throw TextureSaveError.unexpectedDataFormat(found: T.self, required: [UInt8.self, UInt16.self])
            }
        case .hdr:
            if let texture = self as? Image<Float> {
                try texture.writeHDR(to: url)
            } else {
                throw TextureSaveError.unexpectedDataFormat(found: T.self, required: [Float.self])
            }
        case .bmp:
            if let texture = self as? Image<UInt8> {
                try texture.writeBMP(to: url)
            } else {
                throw TextureSaveError.unexpectedDataFormat(found: T.self, required: [UInt8.self])
            }
        case .tga:
            if let texture = self as? Image<UInt8> {
                try texture.writeTGA(to: url)
            } else {
                throw TextureSaveError.unexpectedDataFormat(found: T.self, required: [UInt8.self])
            }
        case .jpg:
            if let texture = self as? Image<UInt8> {
                try texture.writeJPEG(to: url)
            } else {
                throw TextureSaveError.unexpectedDataFormat(found: T.self, required: [UInt8.self])
            }
        case .exr:
            if let texture = self as? Image<Float> {
                try texture.writeEXR(to: url)
            } else {
                throw TextureSaveError.unexpectedDataFormat(found: T.self, required: [Float.self])
            }
        }
    }
}

extension Image where ComponentType == UInt8 {
    public func writeBMP(to url: URL) throws {
        let result = stbi_write_bmp(url.path, Int32(self.width), Int32(self.height), Int32(self.channelCount), self.storage.data.baseAddress)
        if result == 0 {
            throw TextureSaveError.errorWritingFile("(no error message)")
        }
    }
    
    public func writeJPEG(to url: URL, quality: Double = 0.9) throws {
        let result = stbi_write_jpg(url.path, Int32(self.width), Int32(self.height), Int32(self.channelCount), self.storage.data.baseAddress, /* quality = */ Int32((min(max(0.0, quality), 1.0) * 100.0).rounded()))
        if result == 0 {
            throw TextureSaveError.errorWritingFile("(no error message)")
        }
    }
    
    public func pngData(compressionSettings: PNGCompressionSettings = .default) throws -> Data {
        var texture = self
        texture.convertToPostmultipliedAlpha()
        
        var lodePNGState = LodePNGState()
        lodepng_state_init(&lodePNGState)
        defer { lodepng_state_cleanup(&lodePNGState) }
        
        lodePNGState.info_raw.colortype = try LodePNGColorType(channelCount: texture.channelCount)
        lodePNGState.info_raw.bitdepth = UInt32(MemoryLayout<T>.size * 8)
        lodePNGState.info_png.color.colortype = lodePNGState.info_raw.colortype
        lodePNGState.info_png.color.bitdepth = lodePNGState.info_raw.bitdepth
        lodePNGState.info_png.setColorSpace(texture.colorSpace)
        lodePNGState.encoder.fill(from: compressionSettings)
        
        var outBuffer: UnsafeMutablePointer<UInt8>! = nil
        var outSize: Int = 0
        
        let errorCode = texture.withUnsafeBufferPointer { lodepng_encode(&outBuffer, &outSize, $0.baseAddress, UInt32(texture.width), UInt32(texture.height), &lodePNGState) }
        
        if errorCode != 0 {
            let error = lodepng_error_text(errorCode)
            throw TextureSaveError.errorWritingFile(error.map { String(cString: $0) } ?? "(no error message)")
        }
        
        return Data(bytesNoCopy: UnsafeMutableRawPointer(outBuffer), count: outSize, deallocator: .free)
    }
    
    public func writePNG(to url: URL, compressionSettings: PNGCompressionSettings = .default) throws {
        try self.pngData(compressionSettings: compressionSettings).write(to: url)
    }
    
    public func writeTGA(to url: URL) throws {
        let result = stbi_write_tga(url.path, Int32(self.width), Int32(self.height), Int32(self.channelCount), self.storage.data.baseAddress)
        if result == 0 {
            throw TextureSaveError.errorWritingFile("(no error message)")
        }
    }
}

extension Image where ComponentType == UInt16 {
    public func pngData(compressionSettings: PNGCompressionSettings = .default) throws -> Data {
        var texture = self
        texture.convertToPostmultipliedAlpha()
        
        texture.withUnsafeMutableBufferPointer { buffer in
            for i in buffer.indices {
                buffer[i] = buffer[i].bigEndian
            }
        }
        
        var lodePNGState = LodePNGState()
        lodepng_state_init(&lodePNGState)
        defer { lodepng_state_cleanup(&lodePNGState) }
        
        lodePNGState.info_raw.colortype = try LodePNGColorType(channelCount: self.channelCount)
        lodePNGState.info_raw.bitdepth = UInt32(MemoryLayout<T>.size * 8)
        lodePNGState.info_png.color.colortype = lodePNGState.info_raw.colortype
        lodePNGState.info_png.color.bitdepth = lodePNGState.info_raw.bitdepth
        lodePNGState.info_png.setColorSpace(texture.colorSpace)
        lodePNGState.encoder.fill(from: compressionSettings)
        
        var outBuffer: UnsafeMutablePointer<UInt8>! = nil
        var outSize: Int = 0
        
        let errorCode = texture.withUnsafeBufferPointer { pixelData -> UInt32 in
            let pixelBytes = UnsafeRawBufferPointer(pixelData)
            let uint8Bytes = pixelBytes.bindMemory(to: UInt8.self)
            defer { pixelBytes.bindMemory(to: T.self) }
            
            return lodepng_encode(&outBuffer, &outSize, uint8Bytes.baseAddress, UInt32(self.width), UInt32(self.height), &lodePNGState)
        }
        
        if errorCode != 0 {
            let error = lodepng_error_text(errorCode)
            throw TextureSaveError.errorWritingFile(error.map { String(cString: $0) } ?? "(no error message)")
        }
        
        return Data(bytesNoCopy: UnsafeMutableRawPointer(outBuffer), count: outSize, deallocator: .free)
    }
    
    public func writePNG(to url: URL, compressionSettings: PNGCompressionSettings = .default) throws {
        try self.pngData(compressionSettings: compressionSettings).write(to: url)
    }
}


extension Image where ComponentType == Float {
    
    public func writeHDR(to url: URL) throws {
        let result = stbi_write_hdr(url.path, Int32(self.width), Int32(self.height), Int32(self.channelCount), self.storage.data.baseAddress)
        if result == 0 {
            throw TextureSaveError.errorWritingFile("(no error message)")
        }
    }
    
    public func writeEXR(to url: URL) throws {
        var texture = self
        texture.convert(toColorSpace: .linearSRGB)
        texture.convertToPremultipliedAlpha()
        
        var error : UnsafePointer<Int8>? = nil
        let exrResult = SaveEXR(texture.storage.data.baseAddress, Int32(texture.width), Int32(texture.height), Int32(texture.channelCount), 0, url.path, &error)
        if exrResult < 0 {
            throw TextureSaveError.errorWritingFile(error.map { String(cString: $0) } ?? "(no error message)")
        }
    }
}
