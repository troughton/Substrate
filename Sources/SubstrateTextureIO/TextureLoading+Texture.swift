//
//  TextureLoading+Texture.swift
//  
//
//  Created by Thomas Roughton on 27/08/20.
//

import Foundation
import Substrate
import stb_image
import SubstrateImage

public enum MipGenerationMode {
    /// Generate mipmaps on the CPU using the specified wrap mode and filter
    case cpu(wrapMode: ImageEdgeWrapMode, filter: ImageResizeFilter)
    /// Generate mipmaps using the default GPU mipmap generation method
    case gpuDefault
    /// Skip generating mipmaps, leaving levels below the top-most level uninitialised.
    case skip
}

public protocol TextureCopyable {
    func copyData(to texture: Texture, mipGenerationMode: MipGenerationMode) throws
    var preferredPixelFormat: PixelFormat { get }
}

extension StorageMode {
    public static var preferredForLoadedImage: StorageMode {
        return RenderBackend.hasUnifiedMemory ? .managed : .private
    }
}

public enum TextureCopyError: Error {
    case notTextureCopyable(AnyImage)
}

extension AnyImage {
    public func copyData(to texture: Texture, mipGenerationMode: MipGenerationMode) throws {
        guard let data = self as? TextureCopyable else {
            throw TextureCopyError.notTextureCopyable(self)
        }
        try data.copyData(to: texture, mipGenerationMode: mipGenerationMode)
    }
    
    public var preferredPixelFormat: PixelFormat {
        return (self as? TextureCopyable)?.preferredPixelFormat ?? .invalid
    }
}

extension Image: TextureCopyable {
    public var preferredPixelFormat: PixelFormat {
        let colorSpace = self.colorSpace
        
        switch T.self {
        case is UInt8.Type:
            switch self.channelCount {
            case 1:
                if !RenderBackend.supportsPixelFormat(.r8Unorm_sRGB) { return .r8Unorm }
                return colorSpace == .sRGB ? .r8Unorm_sRGB : .r8Unorm
            case 2:
                if !RenderBackend.supportsPixelFormat(.rg8Unorm_sRGB) { return .rg8Unorm }
                return colorSpace == .sRGB ? .rg8Unorm_sRGB : .rg8Unorm
            case 4:
                return colorSpace == .sRGB ? .rgba8Unorm_sRGB : .rgba8Unorm
            default:
                return .invalid
            }
        case is Int8.Type:
            switch self.channelCount {
            case 1:
                return .r8Snorm
            case 2:
                return .rg8Snorm
            case 4:
                return .rgba8Snorm
            default:
                return .invalid
            }
        case is UInt16.Type:
            switch self.channelCount {
            case 1:
                return .r16Unorm
            case 2:
                return .rg16Unorm
            case 4:
                return .rgba16Unorm
            default:
                return .invalid
            }
        case is Float.Type:
            switch self.channelCount {
            case 1:
                return .r32Float
            case 2:
                return .rg32Float
            case 4:
                return .rgba32Float
            default:
                return .invalid
            }
        default:
            return .invalid
        }
    }
}

public struct TextureLoadingOptions: OptionSet, Hashable {
    public let rawValue: UInt32
    
    @inlinable
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
    
    /// When the render backend supports RGBA sRGB formats but not e.g. r8Unorm_sRGB, whether to automatically
    /// expand to a four-channel sRGB texture.
    public static let autoExpandSRGBToRGBA = TextureLoadingOptions(rawValue: 1 << 0)
    
    /// Whether to automatically convert the image's color space to match the chosen pixel format's color space.
    public static let autoConvertColorSpace = TextureLoadingOptions(rawValue: 1 << 1)
    
    /// If this option is set, the texture will be converted on load such that blending the loaded texture in linear space will have the same
    /// effect as blending the source texture in gamma space.
    /// For example, when loading an sRGB texture with a color value of 0.0 and an alpha value of 0.5, blending the texture onto a white background will result in an image with a value of 0.5 in sRGB space rather than a value of 0.5 in linear space.
    public static let assumeSourceImageUsesGammaSpaceBlending = TextureLoadingOptions(rawValue: 1 << 2)
    
    /// When loading a texture with an undefined color space, treat that texture's contents as being sRGB.
    public static let mapUndefinedColorSpaceToSRGB = TextureLoadingOptions(rawValue: 1 << 3)
    
    public static let `default`: TextureLoadingOptions = [.autoConvertColorSpace, .autoExpandSRGBToRGBA]
}

public enum TextureLoadingError : Error {
    case noSupportedPixelFormat
    case mismatchingPixelFormat(expected: PixelFormat, actual: PixelFormat)
    case mismatchingDimensions(expected: Size, actual: Size)
}

extension Image {
    public func copyData(to texture: Texture, mipGenerationMode: MipGenerationMode = .gpuDefault) throws {
        if self.colorSpace == .sRGB, !texture.descriptor.pixelFormat.isSRGB {
            print("Warning: the source texture data is in the sRGB color space but the texture's pixel format is linear RGB.")
        }
        
        guard self.preferredPixelFormat.channelCount == texture.descriptor.pixelFormat.channelCount, self.preferredPixelFormat.bytesPerPixel == texture.descriptor.pixelFormat.bytesPerPixel else {
            throw TextureLoadingError.mismatchingPixelFormat(expected: self.preferredPixelFormat, actual: texture.descriptor.pixelFormat)
        }
        guard texture.descriptor.width == self.width, texture.descriptor.height == self.height else {
            throw TextureLoadingError.mismatchingDimensions(expected: Size(width: self.width, height: self.height), actual: texture.descriptor.size)
        }
        
        if texture.descriptor.mipmapLevelCount > 1, case .cpu(let wrapMode, let filter) = mipGenerationMode {
            let mips = self.generateMipChain(wrapMode: wrapMode, filter: filter, compressedBlockSize: 1, mipmapCount: texture.descriptor.mipmapLevelCount)
                           
            for (i, data) in mips.enumerated().prefix(texture.descriptor.mipmapLevelCount) {
                data.withUnsafeBufferPointer { buffer in
                    _ = GPUResourceUploader.replaceTextureRegion(Region(x: 0, y: 0, width: data.width, height: data.height), mipmapLevel: i, in: texture, withBytes: buffer.baseAddress!, bytesPerRow: data.width * data.channelCount * MemoryLayout<T>.size)
                }
            }
        } else {
            self.withUnsafeBufferPointer { buffer in
                _ = GPUResourceUploader.replaceTextureRegion(Region(x: 0, y: 0, width: self.width, height: self.height), mipmapLevel: 0, in: texture, withBytes: buffer.baseAddress!, bytesPerRow: self.width * self.channelCount * MemoryLayout<T>.size)
            }
            if texture.descriptor.mipmapLevelCount > 1, case .gpuDefault = mipGenerationMode {
                if self.channelCount == 4, self.alphaMode != .premultiplied {
                    if _isDebugAssertConfiguration() {
                        print("Warning: generating mipmaps using the GPU's default mipmap generation for texture \(texture.label ?? "Texture(handle: \(texture.handle))") which expects premultiplied alpha, but the texture has an alpha mode of \(self.alphaMode). Fringing may be visible")
                    }
                }
                GPUResourceUploader.generateMipmaps(for: texture)
            }
        }
    }
}

extension Texture {
    public init(fileAt url: URL, colorSpace: ImageColorSpace = .undefined, sourceAlphaMode: ImageAlphaMode = .inferred, gpuAlphaMode: ImageAlphaMode = .none, mipmapped: Bool, mipGenerationMode: MipGenerationMode = .gpuDefault, storageMode: StorageMode = .preferredForLoadedImage, usage: TextureUsage = .shaderRead, options: TextureLoadingOptions = .default) throws {
        let usage = usage.union(storageMode == .private ? TextureUsage.blitDestination : [])
        
        self = Texture._createPersistentTextureWithoutDescriptor(flags: .persistent)
        try self.fillInternal(fromFileAt: url, colorSpace: colorSpace, sourceAlphaMode: sourceAlphaMode, gpuAlphaMode: gpuAlphaMode, mipmapped: mipmapped, mipGenerationMode: mipGenerationMode, storageMode: storageMode, usage: usage, options: options, isPartiallyInitialised: true)
    }
    
    public init(decodingImageData imageData: Data, colorSpace: ImageColorSpace = .undefined, sourceAlphaMode: ImageAlphaMode = .inferred, gpuAlphaMode: ImageAlphaMode = .none, mipmapped: Bool, mipGenerationMode: MipGenerationMode = .gpuDefault, storageMode: StorageMode = .preferredForLoadedImage, usage: TextureUsage = .shaderRead, options: TextureLoadingOptions = .default) throws {
        let usage = usage.union(storageMode == .private ? TextureUsage.blitDestination : [])
        
        self = Texture._createPersistentTextureWithoutDescriptor(flags: .persistent)
        try self.fillInternal(imageData: imageData, colorSpace: colorSpace, sourceAlphaMode: sourceAlphaMode, gpuAlphaMode: gpuAlphaMode, mipmapped: mipmapped, mipGenerationMode: mipGenerationMode, storageMode: storageMode, usage: usage, options: options, isPartiallyInitialised: true)
    }
    
    @available(*, deprecated, renamed: "init(fileAt:mipmapped:colorSpace:alphaMode:storageMode:usage:)")
    public init(fileAt url: URL, mipmapped: Bool, colorSpace: ImageColorSpace, premultipliedAlpha: Bool, storageMode: StorageMode = .preferredForLoadedImage, usage: TextureUsage = .shaderRead) throws {
        try self.init(fileAt: url, colorSpace: colorSpace, sourceAlphaMode: premultipliedAlpha ? .premultiplied : .postmultiplied, mipmapped: mipmapped, storageMode: storageMode, usage: usage)
    }
    
    @available(*, deprecated, renamed: "init(fileAt:mipmapped:colorSpace:alphaMode:storageMode:usage:)")
    public init(fileAt url: URL, mipmapped: Bool, colourSpace: ImageColorSpace, premultipliedAlpha: Bool, storageMode: StorageMode = .preferredForLoadedImage, usage: TextureUsage = .shaderRead) throws {
        try self.init(fileAt: url, colorSpace: colourSpace, sourceAlphaMode: premultipliedAlpha ? .premultiplied : .postmultiplied, mipmapped: mipmapped, storageMode: storageMode, usage: usage)
    }
    
    public func copyData(from textureData: AnyImage, mipGenerationMode: MipGenerationMode = .gpuDefault) throws {
        return try textureData.copyData(to: self, mipGenerationMode: mipGenerationMode)
    }
    
    private static func loadSourceImage(_ image: Image<UInt8>, colorSpace: ImageColorSpace, gpuAlphaMode: ImageAlphaMode, options: TextureLoadingOptions) throws -> Image<UInt8> {
        var textureData = image
        
        if options.contains(.mapUndefinedColorSpaceToSRGB), textureData.colorSpace == .undefined {
            textureData.reinterpretColor(as: .sRGB)
        }
        
        if textureData.alphaMode != .none {
            if options.contains(.assumeSourceImageUsesGammaSpaceBlending), textureData.colorSpace == .sRGB {
                textureData.convertToPostmultipliedAlpha()
                textureData.convertPostmultSRGBBlendedSRGBToPremultLinearBlendedSRGB()
            }
            
            switch gpuAlphaMode {
            case .premultiplied:
                textureData.convertToPremultipliedAlpha()
            case .postmultiplied:
                textureData.convertToPostmultipliedAlpha()
            default:
                break
            }
        }
        
        if (options.contains(.autoExpandSRGBToRGBA) && textureData.colorSpace == .sRGB && textureData.channelCount < 4) || textureData.channelCount == 3 {
            var needsChannelExpansion = true
            if (textureData.channelCount == 1 && RenderBackend.supportsPixelFormat(.r8Unorm_sRGB)) ||
                (textureData.channelCount == 2 && RenderBackend.supportsPixelFormat(.rg8Unorm_sRGB)) {
                needsChannelExpansion = false
            }
            if needsChannelExpansion {
                let sourceData = textureData
                textureData = Image<UInt8>(width: sourceData.width, height: sourceData.height, channels: 4, colorSpace: sourceData.colorSpace, alphaMode: sourceData.alphaMode)
                
                if sourceData.channelCount == 1 {
                    sourceData.forEachPixel { (x, y, channel, val) in
                        textureData[x, y] = SIMD4(val, val, val, .max)
                    }
                } else if sourceData.channelCount == 2 {
                    sourceData.forEachPixel { (x, y, channel, val) in
                        if channel == 0 {
                            textureData[x, y] = SIMD4(val, val, val, .max)
                        } else {
                            textureData[x, y, channel: 3] = val
                        }
                    }
                } else {
                    precondition(sourceData.channelCount == 3)
                    sourceData.forEachPixel { (x, y, channel, val) in
                        textureData[x, y, channel: channel] = val
                        textureData[x, y, channel: 3] = .max
                    }
                }
            }
        }
        
        let pixelFormat = textureData.preferredPixelFormat
        guard pixelFormat != .invalid else {
            throw TextureLoadingError.noSupportedPixelFormat
        }
        
        if options.contains(.autoConvertColorSpace) {
            if pixelFormat.isSRGB, textureData.colorSpace != .sRGB {
                textureData.convert(toColorSpace: .sRGB)
            } else if !pixelFormat.isSRGB {
                textureData.convert(toColorSpace: .linearSRGB)
            }
        }
        
        return textureData
    }
    
    private static func loadSourceImage(_ image: Image<UInt16>, colorSpace: ImageColorSpace, gpuAlphaMode: ImageAlphaMode, options: TextureLoadingOptions) throws -> Image<UInt16> {
        var textureData = image
        if options.contains(.mapUndefinedColorSpaceToSRGB), textureData.colorSpace == .undefined {
            textureData.reinterpretColor(as: .sRGB)
        }
        
        let pixelFormat = textureData.preferredPixelFormat
        guard pixelFormat != .invalid else {
            throw TextureLoadingError.noSupportedPixelFormat
        }
        
        if textureData.alphaMode != .none {
            switch gpuAlphaMode {
            case .premultiplied:
                textureData.convertToPremultipliedAlpha()
            case .postmultiplied:
                textureData.convertToPostmultipliedAlpha()
            default:
                break
            }
        }
        
        if options.contains(.autoConvertColorSpace) {
            if pixelFormat.isSRGB, textureData.colorSpace != .sRGB {
                textureData.convert(toColorSpace: .sRGB)
            } else if !pixelFormat.isSRGB {
                textureData.convert(toColorSpace: .linearSRGB)
            }
        }
        
        return textureData
    }
    
    private static func loadSourceImage(_ image: Image<Float>, colorSpace: ImageColorSpace, gpuAlphaMode: ImageAlphaMode, options: TextureLoadingOptions) throws -> Image<Float> {
        var textureData = image
        if colorSpace != .undefined {
            textureData.reinterpretColor(as: colorSpace)
        } else if options.contains(.mapUndefinedColorSpaceToSRGB), textureData.colorSpace == .undefined {
            textureData.reinterpretColor(as: .sRGB)
        }
        
        let pixelFormat = textureData.preferredPixelFormat
        guard pixelFormat != .invalid else {
            throw TextureLoadingError.noSupportedPixelFormat
        }
        
        if options.contains(.autoConvertColorSpace) {
            if pixelFormat.isSRGB, textureData.colorSpace != .sRGB {
                textureData.convert(toColorSpace: .sRGB)
            } else if !pixelFormat.isSRGB {
                textureData.convert(toColorSpace: .linearSRGB)
            }
        }
        
        if textureData.alphaMode != .none {
            switch gpuAlphaMode {
            case .premultiplied:
                textureData.convertToPremultipliedAlpha()
            case .postmultiplied:
                textureData.convertToPostmultipliedAlpha()
            default:
                break
            }
        }
        
        return textureData
    }
    
    public static func loadSourceImage(fromFileAt url: URL, colorSpace: ImageColorSpace, sourceAlphaMode: ImageAlphaMode, gpuAlphaMode: ImageAlphaMode, options: TextureLoadingOptions) throws -> AnyImage {
        if url.pathExtension.lowercased() == "exr" {
            let textureData = try Image<Float>(exrAt: url)
            return try self.loadSourceImage(textureData, colorSpace: colorSpace, gpuAlphaMode: gpuAlphaMode, options: options)
        }
        
        let fileInfo = try ImageFileInfo(url: url)
        
        let is16Bit = fileInfo.bitDepth == 16
        let isHDR = fileInfo.isFloatingPoint
        
        if isHDR {
            let textureData = try Image<Float>(fileAt: url, colorSpace: colorSpace, alphaMode: sourceAlphaMode)
            return try self.loadSourceImage(textureData, colorSpace: colorSpace, gpuAlphaMode: gpuAlphaMode, options: options)
            
        } else if is16Bit {
            let textureData = try Image<UInt16>(fileAt: url, colorSpace: colorSpace, alphaMode: sourceAlphaMode)
            return try self.loadSourceImage(textureData, colorSpace: colorSpace, gpuAlphaMode: gpuAlphaMode, options: options)
            
        } else {
            let textureData = try Image<UInt8>(fileAt: url, colorSpace: colorSpace, alphaMode: sourceAlphaMode)
            return try self.loadSourceImage(textureData, colorSpace: colorSpace, gpuAlphaMode: gpuAlphaMode, options: options)
        }
    }
    
    public static func loadSourceImage(decodingImageData imageData: Data, colorSpace: ImageColorSpace, sourceAlphaMode: ImageAlphaMode, gpuAlphaMode: ImageAlphaMode, options: TextureLoadingOptions) throws -> AnyImage {
        if let _ = try? ImageFileInfo(format: .exr, data: imageData) {
            let textureData = try Image<Float>(exrData: imageData)
            return try self.loadSourceImage(textureData, colorSpace: colorSpace, gpuAlphaMode: gpuAlphaMode, options: options)
        }
        
        let fileInfo = try ImageFileInfo(data: imageData)
        
        let is16Bit = fileInfo.bitDepth == 16
        let isHDR = fileInfo.isFloatingPoint
        
        if isHDR {
            let textureData = try Image<Float>(data: imageData, colorSpace: colorSpace, alphaMode: sourceAlphaMode)
            return try self.loadSourceImage(textureData, colorSpace: colorSpace, gpuAlphaMode: gpuAlphaMode, options: options)
            
        } else if is16Bit {
            let textureData = try Image<UInt16>(data: imageData, colorSpace: colorSpace, alphaMode: sourceAlphaMode)
            return try self.loadSourceImage(textureData, colorSpace: colorSpace, gpuAlphaMode: gpuAlphaMode, options: options)
            
        } else {
            let textureData = try Image<UInt8>(data: imageData, colorSpace: colorSpace, alphaMode: sourceAlphaMode)
            return try self.loadSourceImage(textureData, colorSpace: colorSpace, gpuAlphaMode: gpuAlphaMode, options: options)
        }
    }

    private func fillInternal(fromFileAt url: URL, colorSpace: ImageColorSpace, sourceAlphaMode: ImageAlphaMode, gpuAlphaMode: ImageAlphaMode, mipmapped: Bool, mipGenerationMode: MipGenerationMode, storageMode: StorageMode, usage: TextureUsage, options: TextureLoadingOptions, isPartiallyInitialised: Bool) throws {
        precondition(storageMode != .private || usage.contains(.blitDestination))
        
        let textureData = try Texture.loadSourceImage(fromFileAt: url, colorSpace: colorSpace, sourceAlphaMode: sourceAlphaMode, gpuAlphaMode: gpuAlphaMode, options: options)
        
        if isPartiallyInitialised {
            let descriptor = TextureDescriptor(type: .type2D, format: textureData.preferredPixelFormat, width: textureData.width, height: textureData.height, mipmapped: mipmapped, storageMode: storageMode, usage: usage)
            self._initialisePersistentTexture(descriptor: descriptor, heap: nil)
        }
        
        try textureData.copyData(to: self, mipGenerationMode: mipGenerationMode)
        
        if self.label == nil {
            self.label = url.lastPathComponent
        }
    }
    
    private func fillInternal(imageData: Data, colorSpace: ImageColorSpace, sourceAlphaMode: ImageAlphaMode, gpuAlphaMode: ImageAlphaMode, mipmapped: Bool, mipGenerationMode: MipGenerationMode, storageMode: StorageMode, usage: TextureUsage, options: TextureLoadingOptions, isPartiallyInitialised: Bool) throws {
        precondition(storageMode != .private || usage.contains(.blitDestination))
        
        let textureData = try Texture.loadSourceImage(decodingImageData: imageData, colorSpace: colorSpace, sourceAlphaMode: sourceAlphaMode, gpuAlphaMode: gpuAlphaMode, options: options)
        
        if isPartiallyInitialised {
            let descriptor = TextureDescriptor(type: .type2D, format: textureData.preferredPixelFormat, width: textureData.width, height: textureData.height, mipmapped: mipmapped, storageMode: storageMode, usage: usage)
            self._initialisePersistentTexture(descriptor: descriptor, heap: nil)
        }
        
        try textureData.copyData(to: self, mipGenerationMode: mipGenerationMode)
    }
    
    public func fill(fromFileAt url: URL, colorSpace: ImageColorSpace = .undefined, sourceAlphaMode: ImageAlphaMode = .inferred, gpuAlphaMode: ImageAlphaMode = .none, mipGenerationMode: MipGenerationMode = .gpuDefault, options: TextureLoadingOptions = .default) throws {
        try self.fillInternal(fromFileAt: url, colorSpace: colorSpace, sourceAlphaMode: sourceAlphaMode, gpuAlphaMode: gpuAlphaMode, mipmapped: self.descriptor.mipmapLevelCount > 1, mipGenerationMode: mipGenerationMode, storageMode: self.descriptor.storageMode, usage: self.descriptor.usageHint, options: options, isPartiallyInitialised: false)
    }
    
    public func fill(decodingImageData imageData: Data, colorSpace: ImageColorSpace = .undefined, sourceAlphaMode: ImageAlphaMode = .inferred, gpuAlphaMode: ImageAlphaMode = .none, mipGenerationMode: MipGenerationMode = .gpuDefault, options: TextureLoadingOptions = .default) throws {
        try self.fillInternal(imageData: imageData, colorSpace: colorSpace, sourceAlphaMode: sourceAlphaMode, gpuAlphaMode: gpuAlphaMode, mipmapped: self.descriptor.mipmapLevelCount > 1, mipGenerationMode: mipGenerationMode, storageMode: self.descriptor.storageMode, usage: self.descriptor.usageHint, options: options, isPartiallyInitialised: false)
    }
}
