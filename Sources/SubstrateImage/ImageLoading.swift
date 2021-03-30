//
//  ImageLoader.swift
//  SubstrateImageIO
//
//  Created by Thomas Roughton on 1/04/17.
//
//

import Foundation
import stb_image
import tinyexr
import LodePNG

//@available(*, deprecated, renamed: "ImageFileInfo")
public typealias TextureFileInfo = ImageFileInfo

public struct ImageFileInfo: Hashable, Codable {
    public let width : Int
    public let height : Int
    public let channelCount : Int
    
    public let bitDepth: Int
    public let isSigned: Bool
    public let isFloatingPoint: Bool
    
    public let colorSpace: ImageColorSpace
    public let alphaMode: ImageAlphaMode
    
    init(width: Int, height: Int, channelCount: Int,
         bitDepth: Int,
         isSigned: Bool,
         isFloatingPoint: Bool,
         colorSpace: ImageColorSpace,
         alphaMode: ImageAlphaMode) {
        self.width = width
        self.height = height
        self.channelCount = channelCount
        self.bitDepth = bitDepth
        self.isSigned = isSigned
        self.isFloatingPoint = isFloatingPoint
        self.colorSpace = colorSpace
        self.alphaMode = alphaMode
    }
    
    public init(url: URL) throws {
        guard let format = ImageFileFormat(extension: url.pathExtension) else {
            throw ImageLoadingError.invalidFile(url)
        }
        do {
            try self.init(format: format, data: try Data(contentsOf: url, options: .mappedIfSafe))
        } catch {
            if case ImageLoadingError.invalidData = error {
                throw ImageLoadingError.invalidFile(url)
            }
            throw error
        }
    }
    
    public init(data: Data) throws {
        if let info = try? ImageFileInfo(format: .png, data: data) {
            self = info
        } else if let info = try? ImageFileInfo(format: .exr, data: data) {
            self = info
        } else {
            try self.init(format: nil, data: data)
        }
    }
    
    public init(format: ImageFileFormat?, data: Data) throws {
        switch format {
        case .exr:
            var header = EXRHeader()
            InitEXRHeader(&header)
            
            var error: UnsafePointer<CChar>? = nil
            
            defer {
                FreeEXRHeader(&header)
                error.map { FreeEXRErrorMessage($0) }
            }
            
            try data.withUnsafeBytes { data in
                let memory = data.bindMemory(to: UInt8.self)
                
                var version = EXRVersion()
                var result = ParseEXRVersionFromMemory(&version, memory.baseAddress, memory.count)
                if result != TINYEXR_SUCCESS {
                    throw ImageLoadingError.exrParseError("Unable to parse EXR version")
                }
                
                result = ParseEXRHeaderFromMemory(&header, &version, memory.baseAddress, memory.count, &error)
                if result != TINYEXR_SUCCESS {
                    throw ImageLoadingError.exrParseError(String(cString: error!))
                }
            }
            
            self.width = Int(header.data_window.2 - header.data_window.0 + 1)
            self.height = Int(header.data_window.3 - header.data_window.1 + 1)
            
            let channelCount = Int(header.num_channels)
            self.channelCount = channelCount
            
            self.colorSpace = .linearSRGB
            self.isFloatingPoint = true
            self.isSigned = true
            self.bitDepth = 32
            self.alphaMode = channelCount == 2 || channelCount == 4 ? .premultiplied : .none
            
        case .png:
            var state = LodePNGState()
            lodepng_state_init(&state)
            defer { lodepng_state_cleanup(&state) }
            
            var width: UInt32 = 0
            var height: UInt32 = 0
            
            let result = data.withUnsafeBytes { lodepng_inspect(&width, &height, &state, $0.baseAddress?.assumingMemoryBound(to: UInt8.self), $0.count) }
            if result != 0 {
                throw ImageLoadingError.invalidData
            }
            
            self.width = Int(width)
            self.height = Int(height)
            switch state.info_png.color.colortype {
            case LCT_GREY:
                self.channelCount = 1
                self.alphaMode = .none
            case LCT_GREY_ALPHA:
                self.channelCount = 2
                self.alphaMode = .postmultiplied
            case LCT_RGB:
                self.channelCount = 3
                self.alphaMode = .none
            case LCT_RGBA, LCT_PALETTE:
                self.channelCount = 4
                self.alphaMode = .postmultiplied
            default:
                throw ImageLoadingError.invalidData
            }
            self.bitDepth = Int(state.info_png.color.bitdepth)
            self.isSigned = false
            self.isFloatingPoint = false
            
            if state.info_png.srgb_defined != 0 {
                self.colorSpace = .sRGB
            } else if state.info_png.gama_defined != 0 {
                if state.info_png.gama_gamma == 100_000 {
                    self.colorSpace = .linearSRGB
                } else {
                    self.colorSpace = .gammaSRGB(Float(state.info_png.gama_gamma) / 100_000.0)
                }
            } else {
                self.colorSpace = .undefined
            }
        case nil:
            if let format = try? Self.init(format: .exr, data: data) {
                self = format
                return
            } else {
                fallthrough
            }
            
        default:
            var width : Int32 = 0
            var height : Int32 = 0
            var componentsPerPixel : Int32 = 0
            guard data.withUnsafeBytes({ stbi_info_from_memory($0.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32($0.count), &width, &height, &componentsPerPixel) }) != 0 else {
                throw ImageLoadingError.invalidData
            }
            
            self.width = Int(width)
            self.height = Int(height)
            self.channelCount = Int(componentsPerPixel)
            
            let isHDR = data.withUnsafeBytes { stbi_is_hdr_from_memory($0.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32($0.count)) } != 0
            let is16Bit = data.withUnsafeBytes { stbi_is_16_bit_from_memory($0.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32($0.count)) } != 0
            
            if isHDR {
                self.bitDepth = 32
                self.isFloatingPoint = true
            } else {
                self.bitDepth = is16Bit ? 16 : 8
                self.isFloatingPoint = false
            }
            
            self.isSigned = false
            self.colorSpace = isHDR ? .linearSRGB : .undefined
            self.alphaMode = componentsPerPixel == 2 || componentsPerPixel == 4 ? .inferred : .none
        }
        
    }
}


extension Image where ComponentType == UInt8 {
    public init(fileAt url: URL, colorSpace: ImageColorSpace = .undefined, alphaMode: ImageAlphaMode = .inferred) throws {
        let fileInfo = try ImageFileInfo(url: url)
        let colorSpace = colorSpace != .undefined ? colorSpace : fileInfo.colorSpace
        
        let channels = fileInfo.channelCount == 3 ? 4 : fileInfo.channelCount
        
        var width : Int32 = 0
        var height : Int32 = 0
        var componentsPerPixel : Int32 = 0
        guard let data = stbi_load(url.path, &width, &height, &componentsPerPixel, Int32(channels)) else {
            throw ImageLoadingError.invalidImageDataFormat(url, T.self)
        }
        
        self.init(width: Int(width), height: Int(height), channels: Int(channels), data: data, colorSpace: colorSpace, alphaMode: alphaMode.inferFromFileFormat(fileExtension: url.pathExtension, channelCount: Int(channels)), deallocateFunc: { stbi_image_free($0) })
    }
    
    public init(data: Data, colorSpace: ImageColorSpace = .undefined, alphaMode: ImageAlphaMode = .inferred) throws {
        let fileInfo = try ImageFileInfo(format: nil, data: data)
        let colorSpace = colorSpace != .undefined ? colorSpace : fileInfo.colorSpace
        
        self = try data.withUnsafeBytes { data in
            var width : Int32 = 0
            var height : Int32 = 0
            var componentsPerPixel : Int32 = 0
            guard stbi_info_from_memory(data.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32(data.count), &width, &height, &componentsPerPixel) != 0 else {
                throw ImageLoadingError.invalidData
            }
            
            let channels = componentsPerPixel == 3 ? 4 : componentsPerPixel
            let data = stbi_load_from_memory(data.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32(data.count), &width, &height, &componentsPerPixel, channels)!
            
            return Image(width: Int(width), height: Int(height), channels: Int(channels), data: data, colorSpace: colorSpace, alphaMode: alphaMode, deallocateFunc: { stbi_image_free($0) })
        }
    }
}

extension Image where ComponentType == Int8 {
    public init(fileAt url: URL) throws {
        let fileInfo = try ImageFileInfo(url: url)
        
        let channels = fileInfo.channelCount == 3 ? 4 : fileInfo.channelCount
        
        var width : Int32 = 0
        var height : Int32 = 0
        var componentsPerPixel : Int32 = 0
        guard let data = stbi_load(url.path, &width, &height, &componentsPerPixel, Int32(channels)) else {
            throw ImageLoadingError.invalidImageDataFormat(url, T.self)
        }
        
        self.init(width: Int(width), height: Int(height), channels: Int(channels), data: UnsafeMutableRawPointer(data).bindMemory(to: Int8.self, capacity: Int(width) * Int(height) * Int(channels)), colorSpace: .undefined, alphaMode: .none, deallocateFunc: { stbi_image_free($0) })
    }
    
    public init(data: Data, colorSpace: ImageColorSpace = .undefined, alphaMode: ImageAlphaMode = .inferred) throws {
        let fileInfo = try ImageFileInfo(format: nil, data: data)
        let colorSpace = colorSpace != .undefined ? colorSpace : fileInfo.colorSpace
        
        self = try data.withUnsafeBytes { data in
            var width : Int32 = 0
            var height : Int32 = 0
            var componentsPerPixel : Int32 = 0
            guard stbi_info_from_memory(data.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32(data.count), &width, &height, &componentsPerPixel) != 0 else {
                throw ImageLoadingError.invalidData
            }
            
            let channels = componentsPerPixel == 3 ? 4 : componentsPerPixel
            let data = stbi_load_from_memory(data.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32(data.count), &width, &height, &componentsPerPixel, channels)!
            
            return Image(width: Int(width), height: Int(height), channels: Int(channels), data: UnsafeMutableRawPointer(data).bindMemory(to: Int8.self, capacity: Int(width) * Int(height) * Int(channels)), colorSpace: colorSpace, alphaMode: alphaMode, deallocateFunc: { stbi_image_free($0) })
        }
    }
}

extension Image where ComponentType == UInt16 {
    public init(fileAt url: URL, colorSpace: ImageColorSpace = .undefined, alphaMode: ImageAlphaMode = .inferred) throws {
        let fileInfo = try ImageFileInfo(url: url)
        let colorSpace = colorSpace != .undefined ? colorSpace : fileInfo.colorSpace
        
        let channels = fileInfo.channelCount == 3 ? 4 : fileInfo.channelCount
        
        var width : Int32 = 0
        var height : Int32 = 0
        var componentsPerPixel : Int32 = 0
        
        guard let data = stbi_load_16(url.path, &width, &height, &componentsPerPixel, Int32(channels)) else {
            throw ImageLoadingError.invalidImageDataFormat(url, T.self)
        }
        
        self.init(width: Int(width), height: Int(height), channels: Int(channels), data: data, colorSpace: colorSpace, alphaMode: alphaMode.inferFromFileFormat(fileExtension: url.pathExtension, channelCount: Int(channels)), deallocateFunc: { stbi_image_free($0) })
    }
    
    public init(data: Data, colorSpace: ImageColorSpace = .undefined, alphaMode: ImageAlphaMode = .inferred) throws {
        let fileInfo = try ImageFileInfo(data: data)
        let colorSpace = colorSpace != .undefined ? colorSpace : fileInfo.colorSpace
        
        let channels = fileInfo.channelCount == 3 ? 4 : Int32(fileInfo.channelCount)
        
        self = data.withUnsafeBytes { data in
            var width : Int32 = 0
            var height : Int32 = 0
            var componentsPerPixel : Int32 = 0
            let data = stbi_load_16_from_memory(data.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32(data.count), &width, &height, &componentsPerPixel, channels)!
            
            return Image(width: Int(width), height: Int(height), channels: Int(channels), data: data, colorSpace: colorSpace, alphaMode: alphaMode, deallocateFunc: { stbi_image_free($0) })
        }
    }
    
    @available(*, deprecated, renamed: "init(fileAt:colorSpace:alphaMode:)")
    public init(fileAt url: URL, colorSpace: ImageColorSpace, premultipliedAlpha: Bool) throws {
        try self.init(fileAt: url, colorSpace: colorSpace, alphaMode: premultipliedAlpha ? .premultiplied : .postmultiplied)
    }
    
    @available(*, deprecated, renamed: "init(fileAt:colorSpace:alphaMode:)")
    public init(fileAt url: URL, colourSpace: ImageColorSpace, premultipliedAlpha: Bool) throws {
        try self.init(fileAt: url, colorSpace: colourSpace, alphaMode: premultipliedAlpha ? .premultiplied : .postmultiplied)
    }
}


extension Image where ComponentType == Float {
    
    public init(fileAt url: URL, colorSpace: ImageColorSpace = .undefined, alphaMode: ImageAlphaMode = .inferred) throws {
        if url.pathExtension.lowercased() == "exr" {
            try self.init(exrAt: url)
            return
        }
        
        let fileInfo = try ImageFileInfo(url: url)
        let colorSpace = colorSpace != .undefined ? colorSpace : fileInfo.colorSpace
        
        let channels = fileInfo.channelCount == 3 ? 4 : fileInfo.channelCount
        
        let dataCount = fileInfo.width * fileInfo.height * channels
        
        var width : Int32 = 0
        var height : Int32 = 0
        var componentsPerPixel : Int32 = 0
        
        if fileInfo.isFloatingPoint {
            let data = stbi_loadf(url.path, &width, &height, &componentsPerPixel, Int32(channels))!
            self.init(width: Int(width), height: Int(height), channels: Int(channels), data: data, colorSpace: colorSpace, alphaMode: alphaMode.inferFromFileFormat(fileExtension: url.pathExtension, channelCount: Int(channels)), deallocateFunc: { stbi_image_free($0) })
            
        } else if fileInfo.bitDepth == 16 {
            let data = stbi_load_16(url.path, &width, &height, &componentsPerPixel, Int32(channels))!
            defer { stbi_image_free(data) }
            
            self.init(width: Int(width), height: Int(height), channels: Int(channels), colorSpace: colorSpace, alphaModeAllowInferred: alphaMode.inferFromFileFormat(fileExtension: url.pathExtension, channelCount: Int(channels)))
            
            for i in 0..<dataCount {
                self.storage.data[i] = unormToFloat(data[i])
            }
            
            self.inferAlphaMode()
            
        } else {
            let data = stbi_load(url.path, &width, &height, &componentsPerPixel, Int32(channels))!
            defer { stbi_image_free(data) }
            
            self.init(width: Int(width), height: Int(height), channels: Int(channels), colorSpace: colorSpace, alphaModeAllowInferred: alphaMode.inferFromFileFormat(fileExtension: url.pathExtension, channelCount: Int(channels)))
            
            for i in 0..<dataCount {
                self.storage.data[i] = unormToFloat(data[i])
            }
            
            self.inferAlphaMode()
        }
    }
    
    public init(data: Data, colorSpace: ImageColorSpace = .undefined, alphaMode: ImageAlphaMode = .inferred) throws {
        if let exrImage = try? Image<Float>(exrData: data) {
            self = exrImage
            return
        }
        
        let fileInfo = try ImageFileInfo(data: data)
                
        let colorSpace = colorSpace != .undefined ? colorSpace : fileInfo.colorSpace
        
        let channels = fileInfo.channelCount == 3 ? 4 : fileInfo.channelCount
        
        let isHDR = fileInfo.isFloatingPoint
        let is16Bit = fileInfo.bitDepth == 16
        
        let dataCount = fileInfo.width * fileInfo.height * channels
        
        self = data.withUnsafeBytes { data in
            var width : Int32 = 0
            var height : Int32 = 0
            var componentsPerPixel : Int32 = 0
            
            if isHDR {
                let data = stbi_loadf_from_memory(data.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32(data.count), &width, &height, &componentsPerPixel, Int32(channels))!
                return Image(width: Int(width), height: Int(height), channels: Int(channels), data: data, colorSpace: colorSpace, alphaMode: alphaMode, deallocateFunc: { stbi_image_free($0) })
                
            } else if is16Bit {
                let data = stbi_load_16_from_memory(data.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32(data.count), &width, &height, &componentsPerPixel, Int32(channels))!
                defer { stbi_image_free(data) }
                
                var result = Image(width: Int(width), height: Int(height), channels: Int(channels), colorSpace: colorSpace, alphaModeAllowInferred: alphaMode)
                
                for i in 0..<dataCount {
                    result.storage.data[i] = unormToFloat(data[i])
                }
                
                result.inferAlphaMode()
                return result
                
            } else {
                let data = stbi_load_from_memory(data.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32(data.count), &width, &height, &componentsPerPixel, Int32(channels))!
                defer { stbi_image_free(data) }
                
                var result = Image(width: Int(width), height: Int(height), channels: Int(channels), colorSpace: colorSpace, alphaModeAllowInferred: alphaMode)
                
                for i in 0..<dataCount {
                    result.storage.data[i] = unormToFloat(data[i])
                }
                
                result.inferAlphaMode()
                return result
            }
        }
    }
    
    @available(*, deprecated, renamed: "init(fileAt:colorSpace:alphaMode:)")
    public init(fileAt url: URL, colorSpace: ImageColorSpace, premultipliedAlpha: Bool) throws {
        try self.init(fileAt: url, colorSpace: colorSpace, alphaMode: premultipliedAlpha ? .premultiplied : .postmultiplied)
    }
    
    @available(*, deprecated, renamed: "init(fileAt:colorSpace:alphaMode:)")
    public init(fileAt url: URL, colourSpace: ImageColorSpace, premultipliedAlpha: Bool) throws {
        try self.init(fileAt: url, colorSpace: colourSpace, alphaMode: premultipliedAlpha ? .premultiplied : .postmultiplied)
    }
    
    public init(exrData: Data) throws {
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
                throw ImageLoadingError.exrParseError("Unable to parse EXR version")
            }
            
            result = ParseEXRHeaderFromMemory(&header, &version, memory.baseAddress, memory.count, &error)
            if result != TINYEXR_SUCCESS {
                throw ImageLoadingError.exrParseError(String(cString: error!))
            }
            
            for i in 0..<Int(header.num_channels) {
                header.requested_pixel_types[i] = TINYEXR_PIXELTYPE_FLOAT
            }
            
            result = LoadEXRImageFromMemory(&image, &header, memory.baseAddress, memory.count, &error)
            if result != TINYEXR_SUCCESS {
                throw ImageLoadingError.exrParseError(String(cString: error!))
            }
        }
        
        self.init(width: Int(image.width), height: Int(image.height), channels: image.num_channels == 3 ? 4 : Int(image.num_channels), colorSpace: .linearSRGB, alphaModeAllowInferred: .premultiplied)
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
    
    public init(exrAt url: URL) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        try self.init(exrData: data)
    }
}
