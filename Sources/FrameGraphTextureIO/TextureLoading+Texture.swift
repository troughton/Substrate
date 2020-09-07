//
//  TextureLoading+Texture.swift
//  
//
//  Created by Thomas Roughton on 27/08/20.
//

import Foundation
import SwiftFrameGraph
import stb_image

public enum MipGenerationMode {
    case cpu(wrapMode: TextureEdgeWrapMode, filter: TextureResizeFilter)
    case gpuDefault
}

extension Texture {
    
    fileprivate func copyData<T>(from textureData: TextureData<T>, mipmapped: Bool, mipGenerationMode: MipGenerationMode) throws {
        if mipmapped, case .cpu(let wrapMode, let filter) = mipGenerationMode {
            let mips = textureData.generateMipChain(wrapMode: wrapMode, filter: filter, compressedBlockSize: 1)
                           
            for (i, data) in mips.enumerated() {
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
            if mipmapped, case .gpuDefault = mipGenerationMode {
                if textureData.channelCount == 4, textureData.alphaMode != .premultiplied {
                    if _isDebugAssertConfiguration() {
                        print("Warning: generating mipmaps using the GPU's default mipmap generation for texture \(self.label ?? "Texture(handle: \(self.handle))") which expects premultiplied alpha, but the texture has an alpha mode of \(textureData.alphaMode). Fringing may be visible")
                    }
                }
                GPUResourceUploader.generateMipmaps(for: self)
            }
        }
    }
    
    public init(fileAt url: URL, mipmapped: Bool, colorSpace: TextureColorSpace, alphaMode: TextureAlphaMode = .inferred, gpuAlphaMode: TextureAlphaMode = .premultiplied, storageMode: StorageMode = .preferredForLoadedImage, usage: TextureUsage = .shaderRead, mipGenerationMode: MipGenerationMode = .gpuDefault) throws {
        let usage = usage.union(storageMode == .private ? TextureUsage.blitDestination : [])
        
        self = Texture._createPersistentTextureWithoutDescriptor(flags: .persistent)
        try self.fillInternal(fromFileAt: url, mipmapped: mipmapped, colorSpace: colorSpace, alphaMode: alphaMode, gpuAlphaMode: gpuAlphaMode, mipGenerationMode: mipGenerationMode, storageMode: storageMode, usage: usage, isPartiallyInitialised: true)
    }
    
    @available(*, deprecated, renamed: "init(fileAt:mipmapped:colorSpace:alphaMode:storageMode:usage:)")
    public init(fileAt url: URL, mipmapped: Bool, colorSpace: TextureColorSpace, premultipliedAlpha: Bool, storageMode: StorageMode = .preferredForLoadedImage, usage: TextureUsage = .shaderRead) throws {
        try self.init(fileAt: url, mipmapped: mipmapped, colorSpace: colorSpace, alphaMode: premultipliedAlpha ? .premultiplied : .postmultiplied, storageMode: storageMode, usage: usage)
    }
    
    @available(*, deprecated, renamed: "init(fileAt:mipmapped:colorSpace:alphaMode:storageMode:usage:)")
    public init(fileAt url: URL, mipmapped: Bool, colourSpace: TextureColorSpace, premultipliedAlpha: Bool, storageMode: StorageMode = .preferredForLoadedImage, usage: TextureUsage = .shaderRead) throws {
        try self.init(fileAt: url, mipmapped: mipmapped, colorSpace: colourSpace, alphaMode: premultipliedAlpha ? .premultiplied : .postmultiplied, storageMode: storageMode, usage: usage)
    }

    private func fillInternal(fromFileAt url: URL, mipmapped: Bool, colorSpace: TextureColorSpace, alphaMode: TextureAlphaMode, gpuAlphaMode: TextureAlphaMode, mipGenerationMode: MipGenerationMode, storageMode: StorageMode, usage: TextureUsage, isPartiallyInitialised: Bool) throws {
        precondition(storageMode != .private || usage.contains(.blitDestination))
        
        let pixelFormat: PixelFormat
        if url.pathExtension.lowercased() == "exr" {
            var textureData = try TextureData<Float>(exrAt: url, colorSpace: colorSpace, alphaMode: alphaMode)
            switch textureData.channelCount {
            case 1:
                pixelFormat = .r32Float
            case 2:
                pixelFormat = .rg32Float
            case 4:
                pixelFormat = .rgba32Float
            default:
                throw TextureLoadingError.invalidChannelCount(url, textureData.channelCount)
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
            } else {
                guard pixelFormat == self.descriptor.pixelFormat else {
                    throw TextureLoadingError.mismatchingPixelFormat(url, expected: pixelFormat, actual: self.descriptor.pixelFormat)
                }
            }
            
            try self.copyData(from: textureData, mipmapped: mipmapped, mipGenerationMode: mipGenerationMode)
            
        } else {
            // Use stb image directly.
            let isHDR = stbi_is_hdr(url.path) != 0
            let is16Bit = stbi_is_16_bit(url.path) != 0
            
            if isHDR {
                var textureData = try TextureData<Float>(fileAt: url, colorSpace: colorSpace, alphaMode: alphaMode)
                
                switch textureData.channelCount {
                case 1:
                    pixelFormat = .r32Float
                case 2:
                    pixelFormat = .rg32Float
                case 4:
                    pixelFormat = .rgba32Float
                default:
                    throw TextureLoadingError.invalidChannelCount(url, textureData.channelCount)
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
                } else {
                    guard pixelFormat == self.descriptor.pixelFormat else {
                        throw TextureLoadingError.mismatchingPixelFormat(url, expected: pixelFormat, actual: self.descriptor.pixelFormat)
                    }
                }
                
                try self.copyData(from: textureData, mipmapped: mipmapped, mipGenerationMode: mipGenerationMode)
                
            } else if is16Bit {
                var textureData = try TextureData<UInt16>(fileAt: url, colorSpace: colorSpace, alphaMode: alphaMode)
                
                switch textureData.channelCount {
                case 1:
                    pixelFormat = .r16Unorm
                case 2:
                    pixelFormat = .rg16Unorm
                case 4:
                    pixelFormat = .rgba16Unorm
                default:
                    throw TextureLoadingError.invalidChannelCount(url, textureData.channelCount)
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
                } else {
                    guard pixelFormat == self.descriptor.pixelFormat else {
                        throw TextureLoadingError.mismatchingPixelFormat(url, expected: pixelFormat, actual: self.descriptor.pixelFormat)
                    }
                }
                
                try self.copyData(from: textureData, mipmapped: mipmapped, mipGenerationMode: mipGenerationMode)
            } else {
                var textureData = try TextureData<UInt8>(fileAt: url, colorSpace: colorSpace, alphaMode: alphaMode)
                
                switch gpuAlphaMode {
                case .premultiplied:
                    textureData.convertToPremultipliedAlpha()
                case .postmultiplied:
                    textureData.convertToPostmultipliedAlpha()
                default:
                    break
                }
                
                if (colorSpace == .sRGB && textureData.channelCount < 4) || textureData.channelCount == 3 {
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
                
                switch textureData.channelCount {
                case 1:
                    pixelFormat = colorSpace == .sRGB ? .r8Unorm_sRGB : .r8Unorm
                case 2:
                    pixelFormat = colorSpace == .sRGB ? .rg8Unorm_sRGB : .rg8Unorm
                case 4:
                    pixelFormat = colorSpace == .sRGB ? .rgba8Unorm_sRGB : .rgba8Unorm
                default:
                    throw TextureLoadingError.invalidChannelCount(url, textureData.channelCount)
                }
                
                if isPartiallyInitialised {
                    let descriptor = TextureDescriptor(type: .type2D, format: pixelFormat, width: textureData.width, height: textureData.height, mipmapped: mipmapped, storageMode: storageMode, usage: usage)
                    self._initialisePersistentTexture(descriptor: descriptor, heap: nil)
                } else {
                    guard pixelFormat == self.descriptor.pixelFormat else {
                        throw TextureLoadingError.mismatchingPixelFormat(url, expected: pixelFormat, actual: self.descriptor.pixelFormat)
                    }
                }
                
                try self.copyData(from: textureData, mipmapped: mipmapped, mipGenerationMode: mipGenerationMode)
            }
        }
        if self.label == nil {
            self.label = url.lastPathComponent
        }
    }
    
    public func fill(fromFileAt url: URL, mipmapped: Bool, colorSpace: TextureColorSpace, alphaMode: TextureAlphaMode = .inferred, gpuAlphaMode: TextureAlphaMode = .premultiplied, mipGenerationMode: MipGenerationMode = .gpuDefault) throws {
        try self.fillInternal(fromFileAt: url, mipmapped: mipmapped, colorSpace: colorSpace, alphaMode: alphaMode, gpuAlphaMode: gpuAlphaMode, mipGenerationMode: mipGenerationMode, storageMode: self.descriptor.storageMode, usage: self.descriptor.usageHint, isPartiallyInitialised: false)
    }
}
