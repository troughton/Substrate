//
//  TextureLoader.swift
//  FrameGraphTextureLoading
//
//  Created by Thomas Roughton on 1/04/17.
//
//

import Foundation
import SwiftFrameGraph
import stb_image

#if os(macOS)
import Metal
#endif

extension StorageMode {
    public static var preferredForLoadedImage: StorageMode {
        #if (os(iOS) || os(tvOS) || os(watchOS)) && !targetEnvironment(macCatalyst)
        // Shared is preferred on iOS since then the file can be loaded directly into GPU accessible memory without an intermediate buffer.
        return .shared
        #elseif os(macOS)
        if #available(OSX 10.15, *) {
            let renderDevice = RenderBackend.renderDevice as! MTLDevice
            return renderDevice.hasUnifiedMemory ? .managed : .private
        } else {
            return .private
        }
        #else
        // For GPUs with dedicated memory, only keeping a copy on the GPU is preferable.
        return .private
        #endif
    }
}

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
    
    public init(fileAt url: URL, mipmapped: Bool, colourSpace: TextureColourSpace, premultipliedAlpha: Bool = false, storageMode: StorageMode = .preferredForLoadedImage, usage: TextureUsage = .shaderRead) throws {
        let pixelFormat: PixelFormat
        let usage = usage.union(storageMode == .private ? TextureUsage.blitDestination : [])
        
        if url.pathExtension.lowercased() == "exr" {
            let textureData = try TextureData<Float>(exrAt: url, colourSpace: colourSpace)
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
            
            var width : Int32 = 0
            var height : Int32 = 0
            var componentsPerPixel : Int32 = 0
            guard stbi_info(url.path, &width, &height, &componentsPerPixel) != 0 else {
                throw TextureLoadingError.invalidFile(url)
            }
            
            let channels = componentsPerPixel == 3 ? 4 : componentsPerPixel
            
            let isHDR = stbi_is_hdr(url.path) != 0
            let is16Bit = stbi_is_16_bit(url.path) != 0
            
            if isHDR {
                let data = stbi_loadf(url.path, &width, &height, &componentsPerPixel, channels)!
                let textureData = TextureData<Float>(width: Int(width), height: Int(height), channels: Int(channels), data: data, colourSpace: colourSpace, premultipliedAlpha: premultipliedAlpha, deallocateFunc: { stbi_image_free($0) })
                
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
                let data = stbi_load_16(url.path, &width, &height, &componentsPerPixel, channels)!
                let textureData = TextureData<UInt16>(width: Int(width), height: Int(height), channels: Int(channels), data: data, colourSpace: colourSpace, premultipliedAlpha: premultipliedAlpha, deallocateFunc: { stbi_image_free($0) })
                
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
                let data = stbi_load(url.path, &width, &height, &componentsPerPixel, channels)!
                var textureData = TextureData<UInt8>(width: Int(width), height: Int(height), channels: Int(channels), data: data, colourSpace: colourSpace, premultipliedAlpha: premultipliedAlpha, deallocateFunc: { stbi_image_free($0) })
                
                if (colourSpace == .sRGB && textureData.channelCount < 4) || textureData.channelCount == 3 {
                    var needsChannelExpansion = true
                    #if os(iOS) || os(tvOS) || os(watchOS)
                    if textureData.channelCount == 1 || textureData.channelCount == 2 {
                        needsChannelExpansion = false
                    }
                    #endif
                    if needsChannelExpansion {
                        let sourceData = textureData
                        textureData = TextureData<UInt8>(width: sourceData.width, height: sourceData.height, channels: 4, colourSpace: sourceData.colourSpace, premultipliedAlpha: sourceData.premultipliedAlpha)
                        
                        sourceData.forEachPixel { (x, y, channel, val) in
                            if sourceData.channelCount == 1 {
                                textureData[x, y] = SIMD4(val, val, val, .max)
                            } else if channel == 1 {
                                textureData[x, y, channel: 3] = val
                            } else {
                                for i in 0..<3 {
                                    textureData[x, y, channel: i] = val
                                }
                            }
                        }
                    }
                }
                
                switch textureData.channelCount {
                case 1:
                    pixelFormat = colourSpace == .sRGB ? .r8Unorm_sRGB : .r8Unorm
                case 2:
                    pixelFormat = colourSpace == .sRGB ? .rg8Unorm_sRGB : .rg8Unorm
                case 4:
                    pixelFormat = colourSpace == .sRGB ? .rgba8Unorm_sRGB : .rgba8Unorm
                default:
                    throw TextureLoadingError.invalidChannelCount(url, textureData.channelCount)
                }
                
                let descriptor = TextureDescriptor(type: .type2D, format: pixelFormat, width: textureData.width, height: textureData.height, mipmapped: mipmapped, storageMode: storageMode, usage: usage)
                self = Texture(descriptor: descriptor, flags: .persistent)
                
                try self.copyData(from: textureData, mipmapped: mipmapped)
            }
        }
    }
}
