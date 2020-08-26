//
//  TextureLoading+Texture.swift
//  
//
//  Created by Thomas Roughton on 27/08/20.
//

import Foundation
import SwiftFrameGraph
import stb_image

extension Texture {
    
    fileprivate func copyData<T>(from textureData: TextureData<T>, mipmapped: Bool) throws {
        let mips = mipmapped ? textureData.generateMipChain(wrapMode: .wrap, compressedBlockSize: 1) : [textureData]
                       
        for (i, data) in mips.enumerated() {
            let storage = data.storage
            GPUResourceUploader.replaceTextureRegion(Region(x: 0, y: 0, width: data.width, height: data.height), mipmapLevel: i, in: self, withBytes: storage.data.baseAddress!, bytesPerRow: data.width * data.channelCount * MemoryLayout<T>.size, onUploadCompleted: { [storage] _, _ in
                _ = storage
            })
        }
    }
    
    public init(fileAt url: URL, mipmapped: Bool, colorSpace: TextureColorSpace, alphaMode: TextureAlphaMode = .inferred, storageMode: StorageMode = .preferredForLoadedImage, usage: TextureUsage = .shaderRead) throws {
        let pixelFormat: PixelFormat
        let usage = usage.union(storageMode == .private ? TextureUsage.blitDestination : [])
        
        if url.pathExtension.lowercased() == "exr" {
            let textureData = try TextureData<Float>(exrAt: url, colorSpace: colorSpace, alphaMode: alphaMode)
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
            
            let descriptor = TextureDescriptor(type: .type2D, format: pixelFormat, width: textureData.width, height: textureData.height, mipmapped: mipmapped, storageMode: storageMode, usage: usage)
            self = Texture(descriptor: descriptor, flags: .persistent)
            
            try self.copyData(from: textureData, mipmapped: mipmapped)
            
        } else {
            // Use stb image directly.
            
            let isHDR = stbi_is_hdr(url.path) != 0
            let is16Bit = stbi_is_16_bit(url.path) != 0
            
            if isHDR {
                let textureData = try TextureData<Float>(fileAt: url, colorSpace: colorSpace, alphaMode: alphaMode)
                
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
                
                let descriptor = TextureDescriptor(type: .type2D, format: pixelFormat, width: textureData.width, height: textureData.height, mipmapped: mipmapped, storageMode: storageMode, usage: usage)
                self = Texture(descriptor: descriptor, flags: .persistent)
                
                try self.copyData(from: textureData, mipmapped: mipmapped)
                
            } else if is16Bit {
                let textureData = try TextureData<UInt16>(fileAt: url, colorSpace: colorSpace, alphaMode: alphaMode)
                
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
                
                let descriptor = TextureDescriptor(type: .type2D, format: pixelFormat, width: textureData.width, height: textureData.height, mipmapped: mipmapped, storageMode: storageMode, usage: usage)
                self = Texture(descriptor: descriptor, flags: .persistent)
                
                try self.copyData(from: textureData, mipmapped: mipmapped)
            } else {
                var textureData = try TextureData<UInt8>(fileAt: url, colorSpace: colorSpace, alphaMode: alphaMode)
                
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
                
                let descriptor = TextureDescriptor(type: .type2D, format: pixelFormat, width: textureData.width, height: textureData.height, mipmapped: mipmapped, storageMode: storageMode, usage: usage)
                self = Texture(descriptor: descriptor, flags: .persistent)
                
                try self.copyData(from: textureData, mipmapped: mipmapped)
            }
        }
        
        self.label = url.lastPathComponent
    }
    
    @available(*, deprecated, renamed: "init(fileAt:mipmapped:colorSpace:alphaMode:storageMode:usage:)")
    public init(fileAt url: URL, mipmapped: Bool, colorSpace: TextureColorSpace, premultipliedAlpha: Bool, storageMode: StorageMode = .preferredForLoadedImage, usage: TextureUsage = .shaderRead) throws {
        try self.init(fileAt: url, mipmapped: mipmapped, colorSpace: colorSpace, alphaMode: premultipliedAlpha ? .premultiplied : .postmultiplied, storageMode: storageMode, usage: usage)
    }
    
    @available(*, deprecated, renamed: "init(fileAt:mipmapped:colorSpace:alphaMode:storageMode:usage:)")
    public init(fileAt url: URL, mipmapped: Bool, colourSpace: TextureColorSpace, premultipliedAlpha: Bool, storageMode: StorageMode = .preferredForLoadedImage, usage: TextureUsage = .shaderRead) throws {
        try self.init(fileAt: url, mipmapped: mipmapped, colorSpace: colourSpace, alphaMode: premultipliedAlpha ? .premultiplied : .postmultiplied, storageMode: storageMode, usage: usage)
    }
}
