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

extension Texture {
    
    fileprivate func copyData<T>(from textureData: TextureData<T>, mipmapped: Bool) throws {
        let mips = mipmapped ? textureData.generateMipChain(wrapMode: .wrap, compressedBlockSize: 1) : [textureData]
                       
        for (i, data) in mips.enumerated() {
            GPUResourceUploader.replaceTextureRegion(Region(x: 0, y: 0, width: data.width, height: data.height), mipmapLevel: i, in: self, withBytes: data.data, bytesPerRow: data.width * data.channels * MemoryLayout<T>.size, onUploadCompleted: { [data] _, _ in
                _ = data
            })
        }
    }
    
    public init(fileAt url: URL, mipmapped: Bool, colourSpace: TextureColourSpace, premultipliedAlpha: Bool = false, storageMode: StorageMode = .managed, usageHint: TextureUsage = .shaderRead) throws {
        let pixelFormat: PixelFormat
        
        if url.pathExtension.lowercased() == "exr" {
            let textureData = try TextureData<Float>(exrAt: url, colourSpace: colourSpace)
            switch textureData.channels {
            case 1:
                pixelFormat = .r32Float
            case 2:
                pixelFormat = .rg32Float
            case 4:
                pixelFormat = .rgba32Float
            default:
                throw TextureLoadingError.invalidChannelCount(url, textureData.channels)
            }
            
            let descriptor = TextureDescriptor(texture2DWithFormat: pixelFormat, width: textureData.width, height: textureData.height, mipmapped: mipmapped, storageMode: storageMode, usageHint: usageHint)
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
                
                switch textureData.channels {
                case 1:
                    pixelFormat = .r32Float
                case 2:
                    pixelFormat = .rg32Float
                case 4:
                    pixelFormat = .rgba32Float
                default:
                    throw TextureLoadingError.invalidChannelCount(url, textureData.channels)
                }
                
                let descriptor = TextureDescriptor(texture2DWithFormat: pixelFormat, width: textureData.width, height: textureData.height, mipmapped: mipmapped, storageMode: storageMode, usageHint: usageHint)
                self = Texture(descriptor: descriptor, flags: .persistent)
                
                try self.copyData(from: textureData, mipmapped: mipmapped)
                
            } else if is16Bit {
                let data = stbi_load_16(url.path, &width, &height, &componentsPerPixel, channels)!
                let textureData = TextureData<UInt16>(width: Int(width), height: Int(height), channels: Int(channels), data: data, colourSpace: colourSpace, premultipliedAlpha: premultipliedAlpha, deallocateFunc: { stbi_image_free($0) })
                
                switch textureData.channels {
                case 1:
                    pixelFormat = .r16Unorm
                case 2:
                    pixelFormat = .rg16Unorm
                case 4:
                    pixelFormat = .rgba16Unorm
                default:
                    throw TextureLoadingError.invalidChannelCount(url, textureData.channels)
                }
                
                let descriptor = TextureDescriptor(texture2DWithFormat: pixelFormat, width: textureData.width, height: textureData.height, mipmapped: mipmapped, storageMode: storageMode, usageHint: usageHint)
                self = Texture(descriptor: descriptor, flags: .persistent)
                
                try self.copyData(from: textureData, mipmapped: mipmapped)
            } else {
                let data = stbi_load(url.path, &width, &height, &componentsPerPixel, channels)!
                let textureData = TextureData<UInt8>(width: Int(width), height: Int(height), channels: Int(channels), data: data, colourSpace: colourSpace, premultipliedAlpha: premultipliedAlpha, deallocateFunc: { stbi_image_free($0) })
                
                switch textureData.channels {
                case 1:
                    pixelFormat = colourSpace == .sRGB ? .r8Unorm_sRGB : .r8Unorm
                case 2:
                    pixelFormat = colourSpace == .sRGB ? .rg8Unorm_sRGB : .rg8Unorm
                case 4:
                    pixelFormat = colourSpace == .sRGB ? .rgba8Unorm_sRGB : .rgba8Unorm
                default:
                    throw TextureLoadingError.invalidChannelCount(url, textureData.channels)
                }
                
                let descriptor = TextureDescriptor(texture2DWithFormat: pixelFormat, width: textureData.width, height: textureData.height, mipmapped: mipmapped, storageMode: storageMode, usageHint: usageHint)
                self = Texture(descriptor: descriptor, flags: .persistent)
                
                try self.copyData(from: textureData, mipmapped: mipmapped)
            }
        }
    }
}
