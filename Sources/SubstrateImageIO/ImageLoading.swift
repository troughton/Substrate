//
//  ImageLoader.swift
//  SubstrateImageIO
//
//  Created by Thomas Roughton on 1/04/17.
//
//

import Foundation
@_spi(SubstrateTextureIO) import SubstrateImage
import CWuffs
import WuffsAux
import stb_image
import tinyexr
import LodePNG

#if canImport(CoreGraphics)
import CoreGraphics
import ImageIO
#endif

//@available(*, deprecated, renamed: "ImageFileInfo")
public typealias TextureFileInfo = ImageFileInfo


extension Data {
    // Checks adapted from stb_image
    
    fileprivate var isPNG: Bool {
        return self.starts(with: [137,80,78,71,13,10,26,10] as [UInt8])
    }
    
    fileprivate var isBMP: Bool {
        if !self.starts(with: [66, 77]) {
            return false
        }
        guard let b0 = self.dropFirst(14).first, let b1 = self.dropFirst(15).first, let b2 = self.dropFirst(16).first, let b3 = self.dropFirst(17).first else {
            return false
        }
        let sz = UInt32(b0) | (UInt32(b1) << 8) | (UInt32(b2) << 16) | (UInt32(b3) << 24)
        return sz == 12 || sz == 40 || sz == 56 || sz == 108 || sz == 124
    }
    
    fileprivate var isGIF: Bool {
        if !self.starts(with: [71, 73, 70, 56] as [UInt8]) { // 'G', 'I', 'F', '8'
            return false
        }
        let sz = self.dropFirst(4).first
        if sz != 57 && sz != 55 {
            return false
        }
        if self.dropFirst(5).first != 97 {
            return false
        }
        return true
    }
    
    fileprivate var isPSD: Bool {
        return self.count >= 4 && self.prefix(4).withUnsafeBytes {
            return $0.baseAddress?.load(as: UInt32.self).byteSwapped == 0x38425053
        }
    }
    
    fileprivate var isPic: Bool {
        return self.starts(with: [0x53, 0x80, 0xF6, 0x34]) &&
        self.dropFirst(88).starts(with: [80, 73, 67, 84])
    }
}

extension ImageFileFormat {
    public init?(typeOf data: Data) {
        // TODO: add tests for more types.
        if data.isPNG {
            self = .png
        } else if data.isBMP {
            self = .bmp
        } else if data.isGIF {
            self = .gif
        } else if data.isPSD {
            self = .psd
        }
        return nil
    }
}

fileprivate func inspectPNGChunkByName(state: inout LodePNGState, data: UnsafePointer<UInt8>, end: UnsafePointer<UInt8>, type: String) throws {
    guard let p = lodepng_chunk_find_const(data, end, type) else {
        return
    }
    if lodepng_inspect_chunk(&state, data.distance(to: p), data, data.distance(to: end)) != 0 {
        throw ImageLoadingError.invalidData(message: "No chunk with name \(type)")
    }
}

extension ImageAlphaMode {
    func inferFromFileFormat(format: ImageFileFormat?, channelCount: Int) -> ImageAlphaMode {
        if channelCount != 2 && channelCount != 4 {
            return .none
        }
        if case .inferred = self, let format = format {
            switch format {
            case .png:
                return .postmultiplied
            case .exr:
                return .premultiplied
            case .bmp:
                return .premultiplied
            case .jpg, .hdr:
                return .premultiplied // No transparency
            default:
                break
            }
        }
        
        return self
    }
}

extension ImageFileInfo {
    public init(url: URL) throws {
        guard let format = ImageFileFormat(fileExtension: url.pathExtension) else {
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
        guard let format = format else {
            if let format = try? Self.init(format: .exr, data: data) {
                // Try OpenEXR
                self = format
                return
            } else if let format = try? Self.init(format: .png, data: data) {
                // Try LodePNG
                self = format
                return
            } else if let format = try? Self.init(format: .jpg, data: data) {
                // Try STBImage
                self = format
                return
            } else {
#if canImport(CoreGraphics)
                // NOTE: 'public.image' is checked in ImageFileInfo.requiresCGImageDecode
                if let format = try? Self.init(format: .genericImage, data: data) {
                    // Try CoreGraphics
                    self = format
                    return
                }
#endif
                throw ImageLoadingError.invalidData(message: "No valid format found.")
            }
        }
        
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
            
            let format = ImageFileFormat.exr
            let width = Int(header.data_window.max_x - header.data_window.min_x + 1)
            let height = Int(header.data_window.max_y - header.data_window.min_y + 1)
            
            let channelCount = Int(header.num_channels)
            
            let colorSpace = ImageColorSpace.linearSRGB
            let isFloatingPoint = true
            let isSigned = true
            let bitDepth = 32
            let alphaMode: ImageAlphaMode = channelCount == 2 || channelCount == 4 ? .premultiplied : .none
             
            let physicalSize: SIMD2<Double>? = nil
            
            self.init(format: format, width: width, height: height, channelCount: channelCount, bitDepth: bitDepth, isSigned: isSigned, isFloatingPoint: isFloatingPoint, colorSpace: colorSpace, alphaMode: alphaMode, physicalSize: physicalSize)
            
        case .png:
            var state = LodePNGState()
            lodepng_state_init(&state)
            defer { lodepng_state_cleanup(&state) }
            
            var width: UInt32 = 0
            var height: UInt32 = 0
            
            
            try data.withUnsafeBytes { data in
                guard let baseAddress = data.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    throw ImageLoadingError.invalidData(message: "Data is empty")
                }
                if lodepng_inspect(&width, &height, &state, baseAddress, data.count) != 0 {
                    throw ImageLoadingError.invalidData(message: "PNG header inspection failed")
                }
                
                // end before first IDAT chunk: do not parse more than first part of file for all this.
                let end = lodepng_chunk_find_const(baseAddress, baseAddress.advanced(by: data.count), "IDAT") ?? baseAddress.advanced(by: data.count) // no IDAT, invalid PNG but extract info anyway
                try? inspectPNGChunkByName(state: &state, data: baseAddress, end: end, type: "PLTE")
                try? inspectPNGChunkByName(state: &state, data: baseAddress, end: end, type: "cHRM")
                try? inspectPNGChunkByName(state: &state, data: baseAddress, end: end, type: "gAMA")
                try? inspectPNGChunkByName(state: &state, data: baseAddress, end: end, type: "sRGB")
                try? inspectPNGChunkByName(state: &state, data: baseAddress, end: end, type: "sBIT")
//                try? inspectPNGChunkByName(state: &state, data: baseAddress, end: end, type: "bKGD")
//                try? inspectPNGChunkByName(state: &state, data: baseAddress, end: end, type: "hIST")
                try? inspectPNGChunkByName(state: &state, data: baseAddress, end: end, type: "pHYs")
                try? inspectPNGChunkByName(state: &state, data: baseAddress, end: end, type: "iCCP")
            }
            
             let format = ImageFileFormat.png
             let channelCount = withUnsafePointer(to: state.info_png.color) {
                if lodepng_is_palette_type($0) != 0 {
                    return lodepng_has_palette_alpha($0) != 0 ? 4 : 3
                } else {
                    return Int(lodepng_get_channels($0))
                }
            }
            
            let alphaMode: ImageAlphaMode = withUnsafePointer(to: state.info_png.color, { lodepng_can_have_alpha($0) != 0 }) ? .postmultiplied : .none
            let bitDepth = Int(state.info_png.color.bitdepth)
            let isSigned = false
            let isFloatingPoint = false
            
            let colorSpace: ImageColorSpace
            if state.info_png.srgb_defined != 0 {
                colorSpace = .sRGB
            } else if state.info_png.gama_defined != 0 {
                if state.info_png.gama_gamma == 100_000 {
                    colorSpace = .linearSRGB
                } else {
                    colorSpace = .gammaSRGB(Float(state.info_png.gama_gamma) / 100_000.0)
                }
            } else {
                colorSpace = .undefined
            }
            
            let physicalSize: SIMD2<Double>?
            if state.info_png.phys_defined != 0 {
                physicalSize = SIMD2(1.0 / Double(state.info_png.phys_x), 1.0 / Double(state.info_png.phys_y))
            } else {
                physicalSize = nil
            }
            
            self.init(format: format, width: Int(width), height: Int(height), channelCount: channelCount, bitDepth: bitDepth, isSigned: isSigned, isFloatingPoint: isFloatingPoint, colorSpace: colorSpace, alphaMode: alphaMode, physicalSize: physicalSize)
            
        case .jpg, .tga, .bmp, .psd, .gif, .hdr:
            var width : Int32 = 0
            var height : Int32 = 0
            var componentsPerPixel : Int32 = 0
            guard data.withUnsafeBytes({ stbi_info_from_memory($0.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32($0.count), &width, &height, &componentsPerPixel) }) != 0 else {
                throw ImageLoadingError.invalidData(message: stbi_failure_reason().flatMap { String(cString: $0) })
            }
            
            let format = ImageFileFormat(typeOf: data)
            let channelCount = Int(componentsPerPixel)
            
            let isHDR = data.withUnsafeBytes { stbi_is_hdr_from_memory($0.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32($0.count)) } != 0
            let is16Bit = data.withUnsafeBytes { stbi_is_16_bit_from_memory($0.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32($0.count)) } != 0
            
            let bitDepth: Int
            let isFloatingPoint: Bool
            if isHDR {
                bitDepth = 32
                isFloatingPoint = true
            } else {
                bitDepth = is16Bit ? 16 : 8
                isFloatingPoint = false
            }
            
            let isSigned = false
            let colorSpace: ImageColorSpace = isHDR ? .linearSRGB : .undefined
            let alphaMode: ImageAlphaMode = componentsPerPixel == 2 || componentsPerPixel == 4 ? .inferred : .none
            
            let physicalSize: SIMD2<Double>? = nil // TODO: read physical sizes from PSDs
            
            self.init(format: format, width: Int(width), height: Int(height), channelCount: channelCount, bitDepth: bitDepth, isSigned: isSigned, isFloatingPoint: isFloatingPoint, colorSpace: colorSpace, alphaMode: alphaMode, physicalSize: physicalSize)
            
        default:
            #if canImport(CoreGraphics)
            let options = [kCGImageSourceShouldAllowFloat: true] as CFDictionary
            let cgImageSource = CGImageSourceCreateIncremental(options)
            var dataPrefixCount = 2048 // Start with a 2KB chunk. We only want to load the header.
            
            loadLoop: repeat {
                if Task.isCancelled { throw CancellationError() }
                
                let complete = dataPrefixCount >= data.count
                CGImageSourceUpdateData(cgImageSource, data.prefix(dataPrefixCount) as CFData, complete)
                let status = CGImageSourceGetStatus(cgImageSource)
                
                print("Status is \(status); properties are \(CGImageSourceCopyPropertiesAtIndex(cgImageSource, 0, options) as NSDictionary?)")
                
                switch status {
                case .statusUnknownType,
                        .statusReadingHeader:
                    dataPrefixCount *= 2
                case .statusInvalidData,
                        .statusUnexpectedEOF:
                    throw ImageLoadingError.invalidData(message: "Invalid data or unexpected end of file")
                case .statusIncomplete:
                    if let _ = CGImageSourceCopyPropertiesAtIndex(cgImageSource, 0, options) {
                        break loadLoop
                    } else {
                        dataPrefixCount *= 2
                    }
                case .statusComplete:
                    break loadLoop
                default:
                    throw ImageLoadingError.invalidData(message: "Unknown error in CGImageSource decoding")
                }
            } while true
            
            guard let properties = CGImageSourceCopyPropertiesAtIndex(cgImageSource, 0, options) as NSDictionary? else {
                throw ImageLoadingError.invalidData(message: "Unknown error in CGImageSource decoding")
            }
            
            let format = format
            guard let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  let bitDepth = properties[kCGImagePropertyDepth] as? Int,
                  let colorModel = properties[kCGImagePropertyColorModel] else {
                throw ImageLoadingError.invalidData(message: "Unknown error in CGImageSource decoding")
            }
            let hasAlpha = (properties[kCGImagePropertyHasAlpha] as! Bool?) ?? false
            let channelCount: Int
            switch colorModel as! CFString {
            case kCGImagePropertyColorModelLab, kCGImagePropertyColorModelRGB:
                channelCount = hasAlpha ? 4 : 3
            case kCGImagePropertyColorModelCMYK:
                channelCount = 4
            case kCGImagePropertyColorModelGray:
                channelCount = hasAlpha ? 1 : 2
            default:
                throw ImageLoadingError.invalidData(message: "Unknown color model in CGImageSource decoding")
            }
            let isFloatingPoint = (properties[kCGImagePropertyIsFloat] as! Bool?) ?? false
            let isSigned = isFloatingPoint
            
            var colorSpace: ImageColorSpace = .undefined
            if let colorSpaceName = properties[kCGImagePropertyNamedColorSpace] as! CFString? {
                if colorSpaceName == CGColorSpace.genericGrayGamma2_2 || colorSpaceName == CGColorSpace.sRGB {
                    colorSpace = .sRGB
                } else if colorSpaceName == CGColorSpace.linearGray || colorSpaceName == CGColorSpace.linearSRGB {
                    colorSpace = .linearSRGB
                }
            }
            if colorSpace == .undefined {
                if let gamma = (properties[kCGImagePropertyPNGDictionary] as? NSDictionary)?[kCGImagePropertyPNGGamma] as? Double {
                    colorSpace = .gammaSRGB(Float(1.0 / gamma))
                } else if let gamma = (properties[kCGImagePropertyExifDictionary] as? NSDictionary)?[kCGImagePropertyExifGamma] as? Double {
                    colorSpace = .gammaSRGB(Float(1.0 / gamma))
                }
            }
            
            var alphaMode: ImageAlphaMode = .none
            if hasAlpha {
                alphaMode = .inferred
                print("The image dictionary is \(properties)")
            }
            
            let physicalSize: SIMD2<Double>? = nil // TODO: read physical sizes from PSDs
            
            self.init(format: format, width: width, height: height, channelCount: channelCount, bitDepth: bitDepth, isSigned: isSigned, isFloatingPoint: isFloatingPoint, colorSpace: colorSpace, alphaMode: alphaMode, physicalSize: physicalSize)
            
            #else
            throw ImageLoadingError.invalidData(message: nil)
            #endif
        }
    }
}

struct WuffsImageDecodeCallbacks: DecodeImageCallbacks {
    let loadingDelegate: ImageLoadingDelegate
    var bitDepth: Int
    var channelCount: Int
    
    func selectPixelFormat(imageConfig: wuffs_base__image_config) -> wuffs_base__pixel_format {
        var result: UInt32
        switch (self.channelCount, self.bitDepth) {
        case (1, 8):
            result = UInt32(WUFFS_BASE__PIXEL_FORMAT__Y)
        case (1, 16):
            result = UInt32(WUFFS_BASE__PIXEL_FORMAT__Y_16LE)
        case (1, 32):
            result = 0x2000000D
        case (2, 8):
            result = UInt32(WUFFS_BASE__PIXEL_FORMAT__YA_NONPREMUL)
        case (2, 16):
            result = 0x2100000B
        case (2, 32):
            result = 0x2100000D
        case (3, 8):
            result = UInt32(WUFFS_BASE__PIXEL_FORMAT__RGB)
        case (3, 16):
            result = 0xA0000BBB
        case (3, 32):
            result = 0xA0000DDD
        case (4, 8):
            result = UInt32(WUFFS_BASE__PIXEL_FORMAT__RGBA_NONPREMUL)
        case (4, 16):
            result = UInt32(WUFFS_BASE__PIXEL_FORMAT__RGBA_NONPREMUL_4X16LE)
        case (4, 32):
            result = 0xA100DDDD
        default:
            result = UInt32(WUFFS_BASE__PIXEL_FORMAT__INVALID)
        }
        
        if (result & 0x0F > 0x8) &&
            (result & 0xF0000000) != (imageConfig.pixcfg.pixelFormat.repr & 0xF0000000) {
            // Wuffs can't currently swizzle RGBA and BGRA for 16-bit formats.
            // We handle it ourselves instead, so ask for BGRA from Wuffs
            result &= ~0xF0000000
            result |= imageConfig.pixcfg.pixelFormat.repr & 0xF0000000
        }
        
        return wuffs_base__make_pixel_format(result)
    }
    
    final class AllocationContext {
        let buffer: UnsafeMutableRawBufferPointer
        let allocator: ImageAllocator
        
        init(buffer: UnsafeMutableRawBufferPointer, allocator: ImageAllocator) {
            self.buffer = buffer
            self.allocator = allocator
        }
    }
    
    func allocatePixelBuffer(imageConfig image_config: wuffs_base__image_config, allowUninitializedMemory: Bool) throws -> PixelBuffer {
        return try PixelBuffer(imageConfig: image_config,
                               allocatingWith: { byteCount in
            let (memory, allocator) = try self.loadingDelegate.allocateMemory(byteCount: byteCount, alignment: 16, zeroed: !allowUninitializedMemory)
            return (memory, AllocationContext(buffer: memory, allocator: allocator))
        }, deallocatingWith: { allocation, userInfo in
            let context = userInfo as! AllocationContext
            precondition(context.buffer.baseAddress == allocation.baseAddress)
            return context.allocator.deallocate(data: context.buffer)
        })
    }
}

extension ImageFileInfo {
    fileprivate var decodableByWuffs: Bool {
        guard self.format == .png else { return false } // We only use Wuffs for PNG decoding for now.
        if self.channelCount == 2 { return false } // Wuffs doesn't handle greyscale-alpha yet.
        if self.channelCount < 3 && self.bitDepth < 8 { return false } // Wuffs doesn't support greyscale palette images.
        return true
    }
    
#if canImport(CoreGraphics)
    fileprivate var requiresCGImageDecode: Bool {
        guard let format = self.format else { return false }
        if format == .genericImage {
            // public.image is used for images where CoreGraphics
            // was used to load them but we don't know the exact format.
            return true
        }
        if ImageFileFormat.nativeFormats.contains(format) { return false }

        return (CGImageSourceCopyTypeIdentifiers() as! [String]).contains(where: { $0 == format.typeIdentifier })
    }
#endif
}

extension Image where ComponentType: BinaryInteger {
    init(wuffsFileAt url: URL, fileInfo: ImageFileInfo, colorSpace: ImageColorSpace, alphaMode: ImageAlphaMode, loadingDelegate: ImageLoadingDelegate) throws {
        let channelCount = loadingDelegate.channelCount(for: fileInfo)
        
        // Use Wuffs for PNG decoding.
        guard let file = fopen(url.path, "rb") else {
            throw ImageLoadingError.invalidFile(url)
        }
        defer { fclose(file) }
        let pixelBuffer = try WuffsAux.decodeImage(callbacks: WuffsImageDecodeCallbacks(loadingDelegate: loadingDelegate, bitDepth: MemoryLayout<ComponentType>.stride * 8, channelCount: channelCount), input: FileInput(file: file))
        let (data, userContext) = pixelBuffer.moveAllocation()
        let deallocateFunc = pixelBuffer.deallocateFunc
        
        let allocator: ImageAllocator
        if let context = userContext as? WuffsImageDecodeCallbacks.AllocationContext {
            allocator = context.allocator
        } else {
            allocator = .custom(context: userContext,
                                deallocateFunc: deallocateFunc)
        }
        
        self.init(width: Int(pixelBuffer.buffer.pixcfg.width),
                  height: Int(pixelBuffer.buffer.pixcfg.height),
                  channelCount: Int(channelCount),
                  data: data!.bindMemory(to: ComponentType.self),
                  colorSpace: colorSpace,
                  alphaMode: alphaMode,
                  allocator: allocator)
        
        if pixelBuffer.buffer.pixcfg.pixelFormat.repr & 0xF0000000 == 0x80000000 {
            // It's BGRA when we want RGBA
            self.swapRAndB()
        }
    }
    
    init(wuffsData data: Data, fileInfo: ImageFileInfo, colorSpace: ImageColorSpace, alphaMode: ImageAlphaMode, loadingDelegate: ImageLoadingDelegate) throws {
        let channelCount = loadingDelegate.channelCount(for: fileInfo)
        let pixelBuffer = try data.withUnsafeBytes { buffer -> PixelBuffer in
            let memoryInput = MemoryInput(buffer: buffer)
            return try WuffsAux.decodeImage(callbacks: WuffsImageDecodeCallbacks(loadingDelegate: loadingDelegate, bitDepth: MemoryLayout<ComponentType>.stride * 8, channelCount: channelCount), input: memoryInput)
        }
        let (data, userContext) = pixelBuffer.moveAllocation()
        let deallocateFunc = pixelBuffer.deallocateFunc
        
        let allocator: ImageAllocator
        if let context = userContext as? WuffsImageDecodeCallbacks.AllocationContext {
            allocator = context.allocator
        } else {
            allocator = .custom(context: userContext,
                                deallocateFunc: deallocateFunc)
        }
        
        self.init(width: Int(pixelBuffer.buffer.pixcfg.width),
                  height: Int(pixelBuffer.buffer.pixcfg.height),
                  channelCount: Int(channelCount),
                  data: data!.bindMemory(to: ComponentType.self),
                  colorSpace: colorSpace,
                  alphaMode: alphaMode,
                  allocator: allocator)
        
        if pixelBuffer.buffer.pixcfg.pixelFormat.repr & 0xF0000000 == 0x80000000 {
            // It's BGRA when we want RGBA
            self.swapRAndB()
        }
    }
        
    mutating func swapRAndB() {
        let channelCount = self.channelCount
        guard channelCount >= 3 else { return }
        self.withUnsafeMutableBufferPointer { buffer in
            for base in stride(from: 0, to: buffer.count, by: channelCount) {
                buffer.swapAt(base + 0, base + 2)
            }
        }
    }
}

final class STBLoadingDelegate {
    let loadingDelegate: ImageLoadingDelegate
    var overrides: stbi_allocator_overrides = .init()
    var expectedSize: Int = .max
    var allocations: [(allocation: UnsafeMutableRawBufferPointer, allocator: ImageAllocator)] = []
    
    init(loadingDelegate: ImageLoadingDelegate, expectedSize: Int) {
        self.loadingDelegate = loadingDelegate
        self.expectedSize = expectedSize
    }
    
    func allocate(size: Int) -> UnsafeMutableRawPointer? {
        guard size > 0 else { return nil }
        guard size == self.expectedSize || size &- 1 == self.expectedSize, // STB requests a one-byte overallocation.
              let (buffer, allocator) = try? self.loadingDelegate.allocateMemory(byteCount: size, alignment: 16, zeroed: false) else {
                  let allocation = UnsafeMutableRawBufferPointer.allocate(byteCount: size, alignment: 16)
                  self.allocations.append((allocation, .system))
                  return allocation.baseAddress
        }
        if case .custom = allocator {
            self.expectedSize = .max // Only allow one allocation of the expected size per image. We do this because multiple allocations for the same image backed by GPUResourceUploader allocations might fail/deadlock since the GPUResourceUploader has exhausted all of its available upload buffer memory.
        }
        self.allocations.append((buffer, allocator))
        return buffer.baseAddress
    }
    
    func allocator(for allocation: UnsafeMutableRawPointer) -> ImageAllocator {
        return self.allocations.first(where: { $0.allocation.baseAddress == allocation })?.allocator ?? .system
    }
    
    func allocatedSize(for allocation: UnsafeMutableRawPointer) -> Int {
        return self.allocations.first(where: { $0.allocation.baseAddress == allocation })?.allocation.count ?? 0
    }
    
    func deallocate(allocation: UnsafeMutableRawPointer?) {
        guard let theAllocation = allocation,
        let allocationIndex = self.allocations.firstIndex(where: { $0.allocation.baseAddress == theAllocation }) else {
            allocation?.deallocate()
            return
        }
        let (buffer, allocator) = self.allocations.remove(at: allocationIndex)
        allocator.deallocate(data: buffer)
    }
    
    func reallocate(allocation: UnsafeMutableRawPointer?, size: Int) -> UnsafeMutableRawPointer? {
        if let allocationIndex = self.allocations.firstIndex(where: { $0.allocation.baseAddress == allocation }), self.allocations[allocationIndex].allocation.count >= size {
            return allocation
        }
        self.deallocate(allocation: allocation)
        return self.allocate(size: size)
    }
}

fileprivate func setupStbImageAllocatorContext(_ wrapper: STBLoadingDelegate) {
    let existingOverrides = stbi_set_allocator_overrides(stbi_allocator_overrides(stbi_alloc_override: { size in
        let context = Unmanaged<STBLoadingDelegate>.fromOpaque(stbi_get_allocator_context()!).takeUnretainedValue()
        return context.allocate(size: size)
    }, stbi_realloc_override: { currentAddress, oldLength, newLength in
        let context = Unmanaged<STBLoadingDelegate>.fromOpaque(stbi_get_allocator_context()!).takeUnretainedValue()
        return context.reallocate(allocation: currentAddress, size: newLength)
    }, stbi_free_override: { memory in
        let context = Unmanaged<STBLoadingDelegate>.fromOpaque(stbi_get_allocator_context()!).takeUnretainedValue()
        context.deallocate(allocation: memory)
    }, allocator_context: Unmanaged.passRetained(wrapper).toOpaque()))
    wrapper.overrides = existingOverrides
}

fileprivate func tearDownStbImageAllocatorContext(overrides: stbi_allocator_overrides) {
    let setOverrides = stbi_set_allocator_overrides(overrides)
    Unmanaged<STBLoadingDelegate>.fromOpaque(setOverrides.allocator_context!).release()
}

extension Image where ComponentType == UInt8 {
    public init(fileAt url: URL, colorSpace: ImageColorSpace = .undefined, alphaMode: ImageAlphaMode = .inferred, loadingDelegate: ImageLoadingDelegate? = nil) throws {
        let fileInfo = try ImageFileInfo(url: url)
        let loadingDelegate = loadingDelegate ?? DefaultImageLoadingDelegate()
        
        let channels = loadingDelegate.channelCount(for: fileInfo)
        
        let colorSpace = colorSpace != .undefined ? colorSpace : fileInfo.colorSpace
        let alphaMode = alphaMode != .inferred ? alphaMode : fileInfo.alphaMode.inferFromFileFormat(format: fileInfo.format, channelCount: channels)
        
        if fileInfo.decodableByWuffs {
            do {
                try self.init(wuffsFileAt: url, fileInfo: fileInfo, colorSpace: colorSpace, alphaMode: alphaMode, loadingDelegate: loadingDelegate)
                return
            } catch {
                if _isDebugAssertConfiguration() {
                    print("Wuffs decoding failed for file at \(url): \(error)")
                }
            }
        }
        
#if canImport(CoreGraphics)
        if fileInfo.requiresCGImageDecode {
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw ImageLoadingError.invalidFile(url)
            }
            self = try makeImageFromCGImage(cgImage: image, fileInfo: fileInfo, loadingDelegate: loadingDelegate)
            return
        }
#endif
        
        let delegateWrapper = STBLoadingDelegate(loadingDelegate: loadingDelegate, expectedSize: MemoryLayout<ComponentType>.stride * fileInfo.width * fileInfo.height * channels)
        setupStbImageAllocatorContext(delegateWrapper)
        defer { tearDownStbImageAllocatorContext(overrides: delegateWrapper.overrides) }
        
        var width : Int32 = 0
        var height : Int32 = 0
        var componentsPerPixel : Int32 = 0
        guard let data = stbi_load(url.path, &width, &height, &componentsPerPixel, Int32(channels)) else {
            throw ImageLoadingError.invalidFile(url, message: stbi_failure_reason().flatMap { String(cString: $0) })
        }
        
        self.init(width: Int(width), height: Int(height), channelCount: Int(channels),
                  data: .init(start: data, count: delegateWrapper.allocatedSize(for: data)),
                  colorSpace: colorSpace,
                  alphaMode: alphaMode,
                  allocator: delegateWrapper.allocator(for: data))
    }
    
    public init(data: Data, colorSpace: ImageColorSpace = .undefined, alphaMode: ImageAlphaMode = .inferred, loadingDelegate: ImageLoadingDelegate? = nil) throws {
        let fileInfo = try ImageFileInfo(format: nil, data: data)
        let colorSpace = colorSpace != .undefined ? colorSpace : fileInfo.colorSpace
        let alphaMode = alphaMode != .inferred ? alphaMode : fileInfo.alphaMode
        
        let loadingDelegate = loadingDelegate ?? DefaultImageLoadingDelegate()

        if fileInfo.decodableByWuffs {
            do {
                try self.init(wuffsData: data, fileInfo: fileInfo, colorSpace: colorSpace, alphaMode: alphaMode, loadingDelegate: loadingDelegate)
                return
            } catch {
                if _isDebugAssertConfiguration() {
                    print("Wuffs decoding failed for data: \(error)")
                }
            }
        }
        
#if canImport(CoreGraphics)
        if fileInfo.requiresCGImageDecode {
            guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw ImageLoadingError.invalidData(message: "Unknown error decoding CGImageSource.")
            }
            self = try makeImageFromCGImage(cgImage: image, fileInfo: fileInfo, loadingDelegate: loadingDelegate)
            return
        }
#endif
        
        let channels = loadingDelegate.channelCount(for: fileInfo)
        
        let delegateWrapper = STBLoadingDelegate(loadingDelegate: loadingDelegate, expectedSize: MemoryLayout<ComponentType>.stride * fileInfo.width * fileInfo.height * channels)
        setupStbImageAllocatorContext(delegateWrapper)
        defer { tearDownStbImageAllocatorContext(overrides: delegateWrapper.overrides) }
        
        self = try data.withUnsafeBytes { data in
            var width : Int32 = 0
            var height : Int32 = 0
            var componentsPerPixel : Int32 = 0
            guard let data = stbi_load_from_memory(data.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32(data.count), &width, &height, &componentsPerPixel, Int32(channels)) else {
                throw ImageLoadingError.invalidData(message: stbi_failure_reason().flatMap { String(cString: $0) })
            }
            
            return Image(width: Int(width),
                         height: Int(height),
                         channelCount: Int(channels),
                         data: .init(start: data, count: delegateWrapper.allocatedSize(for: data)),
                         colorSpace: colorSpace,
                         alphaMode: alphaMode,
                         allocator: delegateWrapper.allocator(for: data))
        }
    }
}

extension Image where ComponentType == Int8 {
    public init(fileAt url: URL, loadingDelegate: ImageLoadingDelegate? = nil) throws {
        let fileInfo = try ImageFileInfo(url: url)
        let loadingDelegate = loadingDelegate ?? DefaultImageLoadingDelegate()
        
        if fileInfo.decodableByWuffs {
            do {
                try self.init(wuffsFileAt: url, fileInfo: fileInfo, colorSpace: .undefined, alphaMode: .none, loadingDelegate: loadingDelegate)
                return
            } catch {
                assertionFailure("Wuffs decoding failed: \(error)")
            }
        }
        
#if canImport(CoreGraphics)
        if fileInfo.requiresCGImageDecode {
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw ImageLoadingError.invalidFile(url)
            }
            self = try makeImageFromCGImage(cgImage: image, fileInfo: fileInfo, loadingDelegate: loadingDelegate)
            return
        }
#endif
        
        let channels = loadingDelegate.channelCount(for: fileInfo)
        let delegateWrapper = STBLoadingDelegate(loadingDelegate: loadingDelegate, expectedSize: MemoryLayout<ComponentType>.stride * fileInfo.width * fileInfo.height * channels)
        setupStbImageAllocatorContext(delegateWrapper)
        defer { tearDownStbImageAllocatorContext(overrides: delegateWrapper.overrides) }
        
        var width : Int32 = 0
        var height : Int32 = 0
        var componentsPerPixel : Int32 = 0
        guard let data = stbi_load(url.path, &width, &height, &componentsPerPixel, Int32(channels)) else {
            throw ImageLoadingError.invalidFile(url, message: stbi_failure_reason().flatMap { String(cString: $0) })
        }
        
        self.init(width: Int(width),
                  height: Int(height),
                  channelCount: channels,
                  data: UnsafeMutableRawBufferPointer(start: UnsafeMutableRawPointer(data), count: delegateWrapper.allocatedSize(for: data)).bindMemory(to: Int8.self),
                  colorSpace: .undefined,
                  alphaMode: .none,
                  allocator: delegateWrapper.allocator(for: data))
    }
    
    public init(data: Data, loadingDelegate: ImageLoadingDelegate? = nil) throws {
        let fileInfo = try ImageFileInfo(format: nil, data: data)
        let loadingDelegate = loadingDelegate ?? DefaultImageLoadingDelegate()
        
        if fileInfo.decodableByWuffs {
            do {
                try self.init(wuffsData: data, fileInfo: fileInfo, colorSpace: .undefined, alphaMode: .none, loadingDelegate: loadingDelegate)
                return
            } catch {
                assertionFailure("Wuffs decoding failed: \(error)")
            }
        }
        
#if canImport(CoreGraphics)
        if fileInfo.requiresCGImageDecode {
            guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw ImageLoadingError.invalidData(message: "Unknown error in CGImage decoding.")
            }
            self = try makeImageFromCGImage(cgImage: image, fileInfo: fileInfo, loadingDelegate: loadingDelegate)
            return
        }
#endif
        
        let channels = loadingDelegate.channelCount(for: fileInfo)
        let delegateWrapper = STBLoadingDelegate(loadingDelegate: loadingDelegate, expectedSize: MemoryLayout<ComponentType>.stride * fileInfo.width * fileInfo.height * channels)
        setupStbImageAllocatorContext(delegateWrapper)
        defer { tearDownStbImageAllocatorContext(overrides: delegateWrapper.overrides) }
        
        self = try data.withUnsafeBytes { data in
            var width : Int32 = 0
            var height : Int32 = 0
            var componentsPerPixel : Int32 = 0
            guard let data = stbi_load_from_memory(data.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32(data.count), &width, &height, &componentsPerPixel, Int32(channels)) else {
                throw ImageLoadingError.invalidData(message: stbi_failure_reason().flatMap { String(cString: $0) })
            }
            
            return Image(width: Int(width),
                         height: Int(height),
                         channelCount: Int(channels),
                         data: UnsafeMutableRawBufferPointer(start: UnsafeMutableRawPointer(data), count: delegateWrapper.allocatedSize(for: data)).bindMemory(to: Int8.self),
                         colorSpace: .undefined,
                         alphaMode: .none,
                         allocator: delegateWrapper.allocator(for: data))
        }
    }
}

extension Image where ComponentType == UInt16 {
    public init(fileAt url: URL, colorSpace: ImageColorSpace = .undefined, alphaMode: ImageAlphaMode = .inferred, loadingDelegate: ImageLoadingDelegate? = nil) throws {
        let fileInfo = try ImageFileInfo(url: url)
        let loadingDelegate = loadingDelegate ?? DefaultImageLoadingDelegate()
        
        let channels = loadingDelegate.channelCount(for: fileInfo)
        let colorSpace = colorSpace != .undefined ? colorSpace : fileInfo.colorSpace
        let alphaMode = alphaMode != .inferred ? alphaMode : fileInfo.alphaMode.inferFromFileFormat(format: fileInfo.format, channelCount: channels)
        
        if fileInfo.decodableByWuffs {
            do {
                try self.init(wuffsFileAt: url, fileInfo: fileInfo, colorSpace: colorSpace, alphaMode: alphaMode, loadingDelegate: loadingDelegate)
                return
            } catch {
                assertionFailure("Wuffs decoding failed: \(error)")
            }
        }
        
#if canImport(CoreGraphics)
        if fileInfo.requiresCGImageDecode {
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw ImageLoadingError.invalidFile(url)
            }
            self = try makeImageFromCGImage(cgImage: image, fileInfo: fileInfo, loadingDelegate: loadingDelegate)
            return
        }
#endif
        
        let delegateWrapper = STBLoadingDelegate(loadingDelegate: loadingDelegate, expectedSize: MemoryLayout<ComponentType>.stride * fileInfo.width * fileInfo.height * channels)
        setupStbImageAllocatorContext(delegateWrapper)
        defer { tearDownStbImageAllocatorContext(overrides: delegateWrapper.overrides) }
        
        var width : Int32 = 0
        var height : Int32 = 0
        var componentsPerPixel : Int32 = 0
        
        guard let data = stbi_load_16(url.path, &width, &height, &componentsPerPixel, Int32(channels)) else {
            throw ImageLoadingError.invalidFile(url, message: stbi_failure_reason().flatMap { String(cString: $0) })
        }
        
        self.init(width: Int(width),
                  height: Int(height),
                  channelCount: channels,
                  data: .init(start: data, count: delegateWrapper.allocatedSize(for: data) / MemoryLayout<UInt16>.stride),
                  colorSpace: colorSpace,
                  alphaMode: alphaMode,
                  allocator: delegateWrapper.allocator(for: data))
    }
    
    public init(data: Data, colorSpace: ImageColorSpace = .undefined, alphaMode: ImageAlphaMode = .inferred, loadingDelegate: ImageLoadingDelegate? = nil) throws {
        let fileInfo = try ImageFileInfo(data: data)
        let loadingDelegate = loadingDelegate ?? DefaultImageLoadingDelegate()
        let colorSpace = colorSpace != .undefined ? colorSpace : fileInfo.colorSpace
        let alphaMode = alphaMode != .inferred ? alphaMode : fileInfo.alphaMode
        
        if fileInfo.decodableByWuffs {
            do {
                try self.init(wuffsData: data, fileInfo: fileInfo, colorSpace: colorSpace, alphaMode: alphaMode, loadingDelegate: loadingDelegate)
                return
            } catch {
                assertionFailure("Wuffs decoding failed: \(error)")
            }
        }
        
#if canImport(CoreGraphics)
        if fileInfo.requiresCGImageDecode {
            guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw ImageLoadingError.invalidData(message: "Unknown error decoding CGImageSource.")
            }
            self = try makeImageFromCGImage(cgImage: image, fileInfo: fileInfo, loadingDelegate: loadingDelegate)
            return
        }
#endif
        
        let channels = loadingDelegate.channelCount(for: fileInfo)
        let delegateWrapper = STBLoadingDelegate(loadingDelegate: loadingDelegate, expectedSize: MemoryLayout<ComponentType>.stride * fileInfo.width * fileInfo.height * channels)
        setupStbImageAllocatorContext(delegateWrapper)
        defer { tearDownStbImageAllocatorContext(overrides: delegateWrapper.overrides) }
        
        self = try data.withUnsafeBytes { data in
            var width : Int32 = 0
            var height : Int32 = 0
            var componentsPerPixel : Int32 = 0
            guard let data = stbi_load_16_from_memory(data.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32(data.count), &width, &height, &componentsPerPixel, Int32(channels)) else {
                throw ImageLoadingError.invalidData(message: stbi_failure_reason().flatMap { String(cString: $0) })
            }
            
            return Image(width: Int(width),
                         height: Int(height),
                         channelCount: Int(channels),
                         data: .init(start: data, count: delegateWrapper.allocatedSize(for: data) / MemoryLayout<UInt16>.stride),
                         colorSpace: colorSpace,
                         alphaMode: alphaMode,
                         allocator: delegateWrapper.allocator(for: data))
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
    
    public init(fileAt url: URL, colorSpace: ImageColorSpace = .undefined, alphaMode: ImageAlphaMode = .inferred, loadingDelegate: ImageLoadingDelegate? = nil) throws {
        if url.pathExtension.lowercased() == "exr" {
            try self.init(exrAt: url)
            return
        }
        
        let fileInfo = try ImageFileInfo(url: url)
        
#if canImport(CoreGraphics)
        if fileInfo.requiresCGImageDecode {
            let options = [kCGImageSourceShouldAllowFloat: true] as CFDictionary
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, options), let image = CGImageSourceCreateImageAtIndex(imageSource, 0, options) else {
                throw ImageLoadingError.invalidFile(url)
            }
            self = try makeImageFromCGImage(cgImage: image, fileInfo: fileInfo, loadingDelegate: loadingDelegate)
            return
        }
#endif
        
        if fileInfo.isFloatingPoint {
            let loadingDelegate = loadingDelegate ?? DefaultImageLoadingDelegate()
            let channels = loadingDelegate.channelCount(for: fileInfo)
            let colorSpace = colorSpace != .undefined ? colorSpace : fileInfo.colorSpace
            let alphaMode = alphaMode != .inferred ? alphaMode : fileInfo.alphaMode.inferFromFileFormat(format: fileInfo.format, channelCount: channels)
            
            var width : Int32 = 0
            var height : Int32 = 0
            var componentsPerPixel : Int32 = 0
            
            let delegateWrapper = STBLoadingDelegate(loadingDelegate: loadingDelegate, expectedSize: MemoryLayout<ComponentType>.stride * fileInfo.width * fileInfo.height * channels)
            setupStbImageAllocatorContext(delegateWrapper)
            defer { tearDownStbImageAllocatorContext(overrides: delegateWrapper.overrides) }
            
            guard let data = stbi_loadf(url.path, &width, &height, &componentsPerPixel, Int32(channels)) else {
                throw ImageLoadingError.invalidData(message: stbi_failure_reason().flatMap { String(cString: $0) })
            }
            self.init(width: Int(width),
                      height: Int(height),
                      channelCount: Int(channels),
                      data: .init(start: data, count: delegateWrapper.allocatedSize(for: data) / MemoryLayout<Float>.stride),
                      colorSpace: colorSpace,
                      alphaMode: alphaMode.inferFromFileFormat(format: fileInfo.format, channelCount: Int(channels)),
                      allocator: delegateWrapper.allocator(for: data))
            
        } else if fileInfo.bitDepth == 16 {
            let image = try Image<UInt16>(fileAt: url, colorSpace: colorSpace, alphaMode: alphaMode)
            self.init(image)
        } else {
            let image = try Image<UInt8>(fileAt: url, colorSpace: colorSpace, alphaMode: alphaMode)
            self.init(image)
        }
    }
    
    public init(data: Data, colorSpace: ImageColorSpace = .undefined, alphaMode: ImageAlphaMode = .inferred, loadingDelegate: ImageLoadingDelegate? = nil) throws {
        if let exrImage = try? Image<Float>(exrData: data) {
            self = exrImage
            return
        }
        
        let fileInfo = try ImageFileInfo(data: data)
        
        let colorSpace = colorSpace != .undefined ? colorSpace : fileInfo.colorSpace
        let alphaMode = alphaMode != .inferred ? alphaMode : fileInfo.alphaMode
        
#if canImport(CoreGraphics)
        if fileInfo.requiresCGImageDecode {
            let options = [kCGImageSourceShouldAllowFloat: true] as CFDictionary
            guard let imageSource = CGImageSourceCreateWithData(data as CFData, options), let image = CGImageSourceCreateImageAtIndex(imageSource, 0, options) else {
                throw ImageLoadingError.invalidData(message: "Unknown error in CGImage decoding")
            }
            self = try makeImageFromCGImage(cgImage: image, fileInfo: fileInfo, loadingDelegate: loadingDelegate)
            return
        }
#endif
        
        let isHDR = fileInfo.isFloatingPoint
        let is16Bit = fileInfo.bitDepth == 16
        
        if isHDR {
            let loadingDelegate = loadingDelegate ?? DefaultImageLoadingDelegate()
            let channels = loadingDelegate.channelCount(for: fileInfo)
            
            self = try data.withUnsafeBytes { data in
                var width : Int32 = 0
                var height : Int32 = 0
                var componentsPerPixel : Int32 = 0
                
                let delegateWrapper = STBLoadingDelegate(loadingDelegate: loadingDelegate, expectedSize: MemoryLayout<ComponentType>.stride * fileInfo.width * fileInfo.height * channels)
                setupStbImageAllocatorContext(delegateWrapper)
                defer { tearDownStbImageAllocatorContext(overrides: delegateWrapper.overrides) }
                
                guard let data = stbi_loadf_from_memory(data.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32(data.count), &width, &height, &componentsPerPixel, Int32(channels)) else {
                    throw ImageLoadingError.invalidData(message: stbi_failure_reason().flatMap { String(cString: $0) })
                }
                return Image(width: Int(width),
                             height: Int(height),
                             channelCount: Int(channels),
                             data: .init(start: data, count: delegateWrapper.allocatedSize(for: data) / MemoryLayout<UInt16>.stride),
                             colorSpace: colorSpace,
                             alphaMode: alphaMode,
                             allocator: delegateWrapper.allocator(for: data))
            }
            
        } else if is16Bit {
            let image = try Image<UInt16>(data: data, colorSpace: colorSpace, alphaMode: alphaMode, loadingDelegate: loadingDelegate)
            self.init(image)
            
        } else {
            let image = try Image<UInt8>(data: data, colorSpace: colorSpace, alphaMode: alphaMode)
            self.init(image)
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
    
    public init(exrData: Data, loadingDelegate: ImageLoadingDelegate? = nil) throws {
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
        
        let fileInfo = try ImageFileInfo(format: .exr, data: exrData)
        
        let loadingDelegate = loadingDelegate ?? DefaultImageLoadingDelegate()
        let channels = loadingDelegate.channelCount(for: fileInfo)
        
        let (data, allocator) = try loadingDelegate.allocateMemory(byteCount: Int(image.width) * Int(image.height) * Int(channels) * MemoryLayout<Float>.stride, alignment: MemoryLayout<SIMD4<Float>>.stride, zeroed: false)
        
        self.init(width: Int(image.width), height: Int(image.height), channelCount: Int(channels), colorSpace: .linearSRGB, alphaMode: (channels == 2 || channels == 4) ? .premultiplied : .none, data: data.bindMemory(to: Float.self), allocator: allocator)
        
        if channels == 4 && image.num_channels == 3 {
            for y in 0..<self.height {
                for x in 0..<self.width {
                    self[x, y, channel: 3] = 1.0
                }
            }
        }
        
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
            let width = self.width
            let height = self.height
            let rowStride = self.componentsPerRow
            let channelCount = self.channelCount
            
            self.withUnsafeMutableBufferPointer { data in
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
                                
                                data[channelCount * idx + channelIndex] = src[c][srcIdx]
                            }
                        }
                    }
                } else {
                    let src = UnsafeRawPointer(image.images)!.bindMemory(to: UnsafePointer<Float>.self, capacity: Int(image.num_channels))
                    for y in 0..<height {
                        let rowBase = y &* rowStride
                        for x in 0..<width {
                            let i = y &* width &+ x
                            data[rowBase &+ x &* channelCount + channelIndex] = src[c][i]
                        }
                    }
                }
            }
        }
    }
    
    public init(exrAt url: URL, loadingDelegate: ImageLoadingDelegate? = nil) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        try self.init(exrData: data, loadingDelegate: loadingDelegate)
    }
}

#if canImport(CoreGraphics)

extension Image {
    @inline(__always)
    fileprivate func converted<R>(to format: R.Type) throws -> Image<R> {
        guard let result = Image<R>(self) else {
            throw ImageLoadingError.unsupportedComponentFormat(R.self)
        }
        return result
    }
}

@inline(__always)
fileprivate func makeImageFromCGImage<T: SIMDScalar>(cgImage: CGImage, format: T.Type = T.self, fileInfo: ImageFileInfo, loadingDelegate: ImageLoadingDelegate? = nil) throws -> Image<T> {
    let bitmapInfo = cgImage.bitmapInfo
    if bitmapInfo.contains(.floatComponents) {
        return try Image<Float>(cgImage: cgImage, fileInfo: fileInfo, loadingDelegate: loadingDelegate).converted(to: format)
    } else if cgImage.bitsPerComponent == 16 {
        return try Image<UInt16>(cgImage: cgImage, fileInfo: fileInfo, loadingDelegate: loadingDelegate).converted(to: format)
    } else if cgImage.bitsPerComponent == 32 {
        return try Image<UInt32>(cgImage: cgImage, fileInfo: fileInfo, loadingDelegate: loadingDelegate).converted(to: format)
    } else if cgImage.bitsPerComponent == 8 {
        return try Image<UInt8>(cgImage: cgImage, fileInfo: fileInfo, loadingDelegate: loadingDelegate).converted(to: format)
    } else {
        throw ImageLoadingError.invalidData(message: "Unsupported bits per component \(cgImage.bitsPerComponent)")
    }
}

#if canImport(AppKit)
import AppKit

extension NSBitmapImageRep {
    @inline(__always)
    func makeImage<T: SIMDScalar>(format: T.Type = T.self, colorSpace: ImageColorSpace = .undefined, alphaMode: ImageAlphaMode = .inferred, fileInfo: ImageFileInfo, loadingDelegate: ImageLoadingDelegate? = nil) throws -> Image<T> {
        if let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let image = try? makeImageFromCGImage(cgImage: cgImage, format: format, fileInfo: fileInfo, loadingDelegate: loadingDelegate) {
           return image
        }
        
        // Fallback: go through PNG
        let pngData = self.representation(using: .png, properties: [:])!
        if T.self == UInt8.self {
            return try Image<UInt8>(data: pngData, colorSpace: colorSpace, alphaMode: alphaMode, loadingDelegate: loadingDelegate) as! Image<T>
        } else if T.self == Int8.self {
            return try Image<Int8>(data: pngData, loadingDelegate: loadingDelegate) as! Image<T>
        } else if T.self == UInt16.self {
            return try Image<UInt16>(data: pngData, colorSpace: colorSpace, alphaMode: alphaMode, loadingDelegate: loadingDelegate) as! Image<T>
        } else if T.self == Float.self {
            return try Image<Float>(data: pngData, colorSpace: colorSpace, alphaMode: alphaMode, loadingDelegate: loadingDelegate) as! Image<T>
        } else {
            throw ImageLoadingError.unsupportedComponentFormat(format)
        }
    }
}

#endif
#endif
