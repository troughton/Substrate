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
import tinyexr

extension StorageMode {
    public static var preferredForLoadedImage: StorageMode {
        return RenderBackend.hasUnifiedMemory ? .managed : .private
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
    
    
    public init(data: Data, colorSpace: TextureColorSpace, alphaMode: TextureAlphaMode = .inferred) throws {
        self = try data.withUnsafeBytes { data in
            var width : Int32 = 0
            var height : Int32 = 0
            var componentsPerPixel : Int32 = 0
            guard stbi_info_from_memory(data.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32(data.count), &width, &height, &componentsPerPixel) != 0 else {
                throw TextureLoadingError.invalidData
            }
            
            let channels = componentsPerPixel == 3 ? 4 : componentsPerPixel
            let data = stbi_load_from_memory(data.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32(data.count), &width, &height, &componentsPerPixel, channels)!
            return TextureData(width: Int(width), height: Int(height), channels: Int(channels), data: data, colorSpace: colorSpace, alphaMode: alphaMode, deallocateFunc: { stbi_image_free($0) })
        }
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
    
    public init(data: Data, colorSpace: TextureColorSpace, alphaMode: TextureAlphaMode = .inferred) throws {
        self = try data.withUnsafeBytes { data in
            var width : Int32 = 0
            var height : Int32 = 0
            var componentsPerPixel : Int32 = 0
            guard stbi_info_from_memory(data.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32(data.count), &width, &height, &componentsPerPixel) != 0 else {
                throw TextureLoadingError.invalidData
            }
            
            let channels = componentsPerPixel == 3 ? 4 : componentsPerPixel
            let data = stbi_load_16_from_memory(data.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32(data.count), &width, &height, &componentsPerPixel, channels)!
            return TextureData(width: Int(width), height: Int(height), channels: Int(channels), data: data, colorSpace: colorSpace, alphaMode: alphaMode, deallocateFunc: { stbi_image_free($0) })
        }
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
    
    public init(data: Data, colorSpace: TextureColorSpace, alphaMode: TextureAlphaMode = .inferred) throws {
        self = try data.withUnsafeBytes { data in
            var width : Int32 = 0
            var height : Int32 = 0
            var componentsPerPixel : Int32 = 0
            guard stbi_info_from_memory(data.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32(data.count), &width, &height, &componentsPerPixel) != 0 else {
                throw TextureLoadingError.invalidData
            }
            
            let channels = componentsPerPixel == 3 ? 4 : componentsPerPixel
            
            let isHDR = stbi_is_hdr_from_memory(data.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32(data.count)) != 0
            let is16Bit = stbi_is_16_bit_from_memory(data.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32(data.count)) != 0
            
            let dataCount = Int(width * height * channels)
            
            if isHDR {
                let data = stbi_loadf_from_memory(data.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32(data.count), &width, &height, &componentsPerPixel, channels)!
                return TextureData(width: Int(width), height: Int(height), channels: Int(channels), data: data, colorSpace: colorSpace, alphaMode: alphaMode, deallocateFunc: { stbi_image_free($0) })
                
            } else if is16Bit {
                let data = stbi_load_16_from_memory(data.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32(data.count), &width, &height, &componentsPerPixel, channels)!
                defer { stbi_image_free(data) }
                
                var result = TextureData(width: Int(width), height: Int(height), channels: Int(channels), colorSpace: colorSpace, alphaModeAllowInferred: alphaMode)
                
                for i in 0..<dataCount {
                    result.storage.data[i] = unormToFloat(data[i])
                }
                
                result.inferAlphaMode()
                return result
                
            } else {
                let data = stbi_load_from_memory(data.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32(data.count), &width, &height, &componentsPerPixel, channels)!
                defer { stbi_image_free(data) }
                
                var result = TextureData(width: Int(width), height: Int(height), channels: Int(channels), colorSpace: colorSpace, alphaModeAllowInferred: alphaMode)
                
                for i in 0..<dataCount {
                    result.storage.data[i] = unormToFloat(data[i])
                }
                
                result.inferAlphaMode()
                return result
            }
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
    
    public init(exrData: Data, colorSpace: TextureColorSpace, alphaMode: TextureAlphaMode) throws {
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
        
        try exrData.withUnsafeBytes { data in
            
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
    
    init(exrAt url: URL, colorSpace: TextureColorSpace, alphaMode: TextureAlphaMode) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        try self.init(exrData: data, colorSpace: colorSpace, alphaMode: alphaMode)
    }
}
