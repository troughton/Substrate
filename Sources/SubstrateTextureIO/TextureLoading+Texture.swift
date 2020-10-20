//
//  TextureLoading+Texture.swift
//  
//
//  Created by Thomas Roughton on 27/08/20.
//

import Foundation
import Substrate
import stb_image

public enum MipGenerationMode {
    /// Generate mipmaps on the CPU using the specified wrap mode and filter
    case cpu(wrapMode: TextureEdgeWrapMode, filter: TextureResizeFilter)
    /// Generate mipmaps using the default GPU mipmap generation method
    case gpuDefault
    /// Skip generating mipmaps, leaving levels below the top-most level uninitialised.
    case skip
}

extension TextureData {
    public var pixelFormat: PixelFormat {
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

public struct TextureLoadingOptions: OptionSet {
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

extension Texture {
    
    public func copyData<T>(from textureData: TextureData<T>, mipGenerationMode: MipGenerationMode = .gpuDefault) throws {
        if textureData.colorSpace == .sRGB, !self.descriptor.pixelFormat.isSRGB {
            print("Warning: the source texture data is in the sRGB color space but the texture's pixel format is linear RGB.")
        }
        
        guard textureData.pixelFormat.channelCount == self.descriptor.pixelFormat.channelCount, textureData.pixelFormat.bytesPerPixel == self.descriptor.pixelFormat.bytesPerPixel else {
            throw TextureLoadingError.mismatchingPixelFormat(expected: textureData.pixelFormat, actual: self.descriptor.pixelFormat)
        }
        guard self.descriptor.width == textureData.width, self.descriptor.height == textureData.height else {
            throw TextureLoadingError.mismatchingDimensions(expected: Size(width: textureData.width, height: textureData.height), actual: self.descriptor.size)
        }
        
        if self.descriptor.mipmapLevelCount > 1, case .cpu(let wrapMode, let filter) = mipGenerationMode {
            let mips = textureData.generateMipChain(wrapMode: wrapMode, filter: filter, compressedBlockSize: 1, mipmapCount: self.descriptor.mipmapLevelCount)
                           
            for (i, data) in mips.enumerated().prefix(self.descriptor.mipmapLevelCount) {
                let storage = data.storage
                GPUResourceUploader.replaceTextureRegion(Region(x: 0, y: 0, width: data.width, height: data.height), mipmapLevel: i, in: self, withBytes: storage.data.baseAddress!, bytesPerRow: data.width * data.channelCount * MemoryLayout<T>.size, onUploadCompleted: { [storage] _, _ in
                    _ = storage
                })
            }
        } else {
            let storage = textureData.storage
            GPUResourceUploader.replaceTextureRegion(Region(x: 0, y: 0, width: textureData.width, height: textureData.height), mipmapLevel: 0, in: self, withBytes: storage.data.baseAddress!, bytesPerRow: textureData.width * textureData.channelCount * MemoryLayout<T>.size, onUploadCompleted: { [storage] _, _ in
                _ = storage
            })
            if self.descriptor.mipmapLevelCount > 1, case .gpuDefault = mipGenerationMode {
                if textureData.channelCount == 4, textureData.alphaMode != .premultiplied {
                    if _isDebugAssertConfiguration() {
                        print("Warning: generating mipmaps using the GPU's default mipmap generation for texture \(self.label ?? "Texture(handle: \(self.handle))") which expects premultiplied alpha, but the texture has an alpha mode of \(textureData.alphaMode). Fringing may be visible")
                    }
                }
                GPUResourceUploader.generateMipmaps(for: self)
            }
        }
    }
    
    public init(fileAt url: URL, colorSpace: TextureColorSpace = .undefined, sourceAlphaMode: TextureAlphaMode = .inferred, gpuAlphaMode: TextureAlphaMode = .none, mipmapped: Bool, mipGenerationMode: MipGenerationMode = .gpuDefault, storageMode: StorageMode = .preferredForLoadedImage, usage: TextureUsage = .shaderRead, options: TextureLoadingOptions = .default) throws {
        let usage = usage.union(storageMode == .private ? TextureUsage.blitDestination : [])
        
        self = Texture._createPersistentTextureWithoutDescriptor(flags: .persistent)
        try self.fillInternal(fromFileAt: url, colorSpace: colorSpace, sourceAlphaMode: sourceAlphaMode, gpuAlphaMode: gpuAlphaMode, mipmapped: mipmapped, mipGenerationMode: mipGenerationMode, storageMode: storageMode, usage: usage, options: options, isPartiallyInitialised: true)
    }
    
    @available(*, deprecated, renamed: "init(fileAt:mipmapped:colorSpace:alphaMode:storageMode:usage:)")
    public init(fileAt url: URL, mipmapped: Bool, colorSpace: TextureColorSpace, premultipliedAlpha: Bool, storageMode: StorageMode = .preferredForLoadedImage, usage: TextureUsage = .shaderRead) throws {
        try self.init(fileAt: url, colorSpace: colorSpace, sourceAlphaMode: premultipliedAlpha ? .premultiplied : .postmultiplied, mipmapped: mipmapped, storageMode: storageMode, usage: usage)
    }
    
    @available(*, deprecated, renamed: "init(fileAt:mipmapped:colorSpace:alphaMode:storageMode:usage:)")
    public init(fileAt url: URL, mipmapped: Bool, colourSpace: TextureColorSpace, premultipliedAlpha: Bool, storageMode: StorageMode = .preferredForLoadedImage, usage: TextureUsage = .shaderRead) throws {
        try self.init(fileAt: url, colorSpace: colourSpace, sourceAlphaMode: premultipliedAlpha ? .premultiplied : .postmultiplied, mipmapped: mipmapped, storageMode: storageMode, usage: usage)
    }

    private func fillInternal(fromFileAt url: URL, colorSpace: TextureColorSpace, sourceAlphaMode: TextureAlphaMode, gpuAlphaMode: TextureAlphaMode, mipmapped: Bool, mipGenerationMode: MipGenerationMode, storageMode: StorageMode, usage: TextureUsage, options: TextureLoadingOptions, isPartiallyInitialised: Bool) throws {
        precondition(storageMode != .private || usage.contains(.blitDestination))
        
        if url.pathExtension.lowercased() == "exr" {
            var textureData = try TextureData<Float>(exrAt: url)
            if colorSpace != .undefined {
                textureData.reinterpretColor(as: colorSpace)
            } else if options.contains(.mapUndefinedColorSpaceToSRGB), textureData.colorSpace == .undefined {
                textureData.reinterpretColor(as: .sRGB)
            }
            
            let pixelFormat = textureData.pixelFormat
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
            
            switch gpuAlphaMode {
            case .premultiplied:
                textureData.convertToPremultipliedAlpha()
            case .postmultiplied:
                textureData.convertToPostmultipliedAlpha()
            default:
                break
            }
            
            if isPartiallyInitialised {
                let descriptor = TextureDescriptor(type: .type2D, format: pixelFormat, width: textureData.width, height: textureData.height, mipmapped: mipmapped, storageMode: storageMode, usage: usage)
                self._initialisePersistentTexture(descriptor: descriptor, heap: nil)
            }
            
            try self.copyData(from: textureData, mipGenerationMode: mipGenerationMode)
            
        } else {
            let fileInfo = try TextureFileInfo(url: url)
            
            let hasAlphaChannel = fileInfo.channelCount == 2 || fileInfo.channelCount == 4
            let is16Bit = fileInfo.bitDepth == 16
            let isHDR = fileInfo.isFloatingPoint
            
            if isHDR {
                var textureData = try TextureData<Float>(fileAt: url, colorSpace: colorSpace, alphaMode: sourceAlphaMode)
                if options.contains(.mapUndefinedColorSpaceToSRGB), textureData.colorSpace == .undefined {
                    textureData.reinterpretColor(as: .sRGB)
                }
                
                let pixelFormat = textureData.pixelFormat
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
                
                if hasAlphaChannel {
                    switch gpuAlphaMode {
                    case .premultiplied:
                        textureData.convertToPremultipliedAlpha()
                    case .postmultiplied:
                        textureData.convertToPostmultipliedAlpha()
                    default:
                        break
                    }
                }
                
                if isPartiallyInitialised {
                    let descriptor = TextureDescriptor(type: .type2D, format: pixelFormat, width: textureData.width, height: textureData.height, mipmapped: mipmapped, storageMode: storageMode, usage: usage)
                    self._initialisePersistentTexture(descriptor: descriptor, heap: nil)
                }
                
                try self.copyData(from: textureData, mipGenerationMode: mipGenerationMode)
                
            } else if is16Bit {
                var textureData = try TextureData<UInt16>(fileAt: url, colorSpace: colorSpace, alphaMode: sourceAlphaMode)
                if options.contains(.mapUndefinedColorSpaceToSRGB), textureData.colorSpace == .undefined {
                    textureData.reinterpretColor(as: .sRGB)
                }
                
                let pixelFormat = textureData.pixelFormat
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
                
                if hasAlphaChannel {
                    switch gpuAlphaMode {
                    case .premultiplied:
                        textureData.convertToPremultipliedAlpha()
                    case .postmultiplied:
                        textureData.convertToPostmultipliedAlpha()
                    default:
                        break
                    }
                }
                
                if isPartiallyInitialised {
                    let descriptor = TextureDescriptor(type: .type2D, format: pixelFormat, width: textureData.width, height: textureData.height, mipmapped: mipmapped, storageMode: storageMode, usage: usage)
                    self._initialisePersistentTexture(descriptor: descriptor, heap: nil)
                }
                
                try self.copyData(from: textureData, mipGenerationMode: mipGenerationMode)
            } else {
                var textureData = try TextureData<UInt8>(fileAt: url, colorSpace: colorSpace, alphaMode: sourceAlphaMode)
                if options.contains(.mapUndefinedColorSpaceToSRGB), textureData.colorSpace == .undefined {
                    textureData.reinterpretColor(as: .sRGB)
                }
                
                if hasAlphaChannel {
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
                        textureData = TextureData<UInt8>(width: sourceData.width, height: sourceData.height, channels: 4, colorSpace: sourceData.colorSpace, alphaMode: sourceData.alphaMode)
                        
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
                
                let pixelFormat = textureData.pixelFormat
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
                
                if isPartiallyInitialised {
                    let descriptor = TextureDescriptor(type: .type2D, format: pixelFormat, width: textureData.width, height: textureData.height, mipmapped: mipmapped, storageMode: storageMode, usage: usage)
                    self._initialisePersistentTexture(descriptor: descriptor, heap: nil)
                }
                
                try self.copyData(from: textureData, mipGenerationMode: mipGenerationMode)
            }
        }
        if self.label == nil {
            self.label = url.lastPathComponent
        }
    }
    
    public func fill(fromFileAt url: URL, colorSpace: TextureColorSpace = .undefined, sourceAlphaMode: TextureAlphaMode = .inferred, gpuAlphaMode: TextureAlphaMode = .none, mipGenerationMode: MipGenerationMode = .gpuDefault, options: TextureLoadingOptions = .default) throws {
        try self.fillInternal(fromFileAt: url, colorSpace: colorSpace, sourceAlphaMode: sourceAlphaMode, gpuAlphaMode: gpuAlphaMode, mipmapped: self.descriptor.mipmapLevelCount > 1, mipGenerationMode: mipGenerationMode, storageMode: self.descriptor.storageMode, usage: self.descriptor.usageHint, options: options, isPartiallyInitialised: false)
    }
}
