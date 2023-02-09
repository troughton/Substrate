//
//  ImageLoader.swift
//  SubstrateImageIO
//
//  Created by Thomas Roughton on 1/04/17.
//
//

import Foundation
import CWuffs
import WuffsAux
import stb_image
import tinyexr
import LodePNG

#if canImport(AppKit)
import AppKit
import CoreGraphics
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

public struct ImageFileInfo: Hashable, Codable {
    public let format: ImageFileFormat?
    public let width : Int
    public let height : Int
    public let channelCount : Int
    
    public let bitDepth: Int
    public let isSigned: Bool
    public let isFloatingPoint: Bool
    
    public let colorSpace: ImageColorSpace
    public let alphaMode: ImageAlphaMode
    
    public init(width: Int, height: Int, channelCount: Int,
         bitDepth: Int,
         isSigned: Bool,
         isFloatingPoint: Bool,
         colorSpace: ImageColorSpace,
         alphaMode: ImageAlphaMode) {
        self.format = nil
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
#if canImport(AppKit)
                // NOTE: 'public.image' is checked in ImageFileInfo.requiresNSBitmapImageRepDecode
                if let format = try? Self.init(format: .genericImage, data: data) {
                    // Try NSBitmapImageRep
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
            
            self.format = .exr
            self.width = Int(header.data_window.max_x - header.data_window.min_x + 1)
            self.height = Int(header.data_window.max_y - header.data_window.min_y + 1)
            
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
//                try? inspectPNGChunkByName(state: &state, data: baseAddress, end: end, type: "pHYs")
                try? inspectPNGChunkByName(state: &state, data: baseAddress, end: end, type: "iCCP")
            }
            
            self.format = .png
            self.width = Int(width)
            self.height = Int(height)
            self.channelCount = withUnsafePointer(to: state.info_png.color) {
                if lodepng_is_palette_type($0) != 0 {
                    return lodepng_has_palette_alpha($0) != 0 ? 4 : 3
                } else {
                    return Int(lodepng_get_channels($0))
                }
            }
            
            self.alphaMode = withUnsafePointer(to: state.info_png.color, { lodepng_can_have_alpha($0) != 0 }) ? .postmultiplied : .none
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
            
        case .jpg, .tga, .bmp, .psd, .gif, .hdr:
            var width : Int32 = 0
            var height : Int32 = 0
            var componentsPerPixel : Int32 = 0
            guard data.withUnsafeBytes({ stbi_info_from_memory($0.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32($0.count), &width, &height, &componentsPerPixel) }) != 0 else {
                throw ImageLoadingError.invalidData(message: stbi_failure_reason().flatMap { String(cString: $0) })
            }
            
            self.format = ImageFileFormat(typeOf: data)
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
            
        default:
            #if canImport(AppKit)
            let bitmapImageRep = NSBitmapImageRep(forIncrementalLoad: ())
            var dataPrefixCount = 2048 // Start with a 2KB chunk. We only want to load the header.
            
            var loadingComplete = false
            loadLoop: repeat {
                if Task.isCancelled { throw CancellationError() }
                
                let status = bitmapImageRep.incrementalLoad(from: data.prefix(dataPrefixCount), complete: dataPrefixCount >= data.count)
                switch status {
                case NSBitmapImageRep.LoadStatus.unknownType.rawValue,
                    NSBitmapImageRep.LoadStatus.readingHeader.rawValue:
                    dataPrefixCount += 2048
                case NSBitmapImageRep.LoadStatus.invalidData.rawValue,
                    NSBitmapImageRep.LoadStatus.unexpectedEOF.rawValue:
                    throw ImageLoadingError.invalidData(message: "Invalid data or unexpected end of file")
                case NSBitmapImageRep.LoadStatus.willNeedAllData.rawValue:
                    dataPrefixCount = data.count
                case NSBitmapImageRep.LoadStatus.completed.rawValue,
                    _ where status > 0:
                    loadingComplete = status == NSBitmapImageRep.LoadStatus.completed.rawValue
                    break loadLoop
                default:
                    throw ImageLoadingError.invalidData(message: "Unknown error in NSBitmapImageRep decoding")
                }
            } while true
            
            if !loadingComplete {
                bitmapImageRep.incrementalLoad(from: data.prefix(dataPrefixCount), complete: true)
            }
            
            self.format = format
            self.width = bitmapImageRep.pixelsWide
            self.height = bitmapImageRep.pixelsHigh
            self.channelCount = bitmapImageRep.samplesPerPixel
            self.bitDepth = bitmapImageRep.bitsPerPixel / bitmapImageRep.samplesPerPixel
            self.isSigned = false
            self.isFloatingPoint = bitmapImageRep.bitmapFormat.contains(.floatingPointSamples)
            
            if let colorSpace = bitmapImageRep.colorSpace.cgColorSpace {
                if colorSpace.name == CGColorSpace.genericGrayGamma2_2 || colorSpace.name == CGColorSpace.sRGB {
                    self.colorSpace = .sRGB
                } else if colorSpace.name == CGColorSpace.linearGray || colorSpace.name == CGColorSpace.linearSRGB {
                    self.colorSpace = .linearSRGB
                } else if let gamma = bitmapImageRep.value(forProperty: .gamma) as? Double {
                    self.colorSpace = .gammaSRGB(Float(1.0 / gamma))
                } else {
                    self.colorSpace = .undefined
                }
            } else {
                self.colorSpace = .undefined
            }
            
            switch bitmapImageRep.samplesPerPixel {
            case 1, 3:
                self.alphaMode = .none
            case 2, 4:
                self.alphaMode = bitmapImageRep.bitmapFormat.contains(.alphaNonpremultiplied) ? .postmultiplied : .premultiplied
            default:
                self.alphaMode = .inferred
            }
            
            #else
            throw ImageLoadingError.invalidData
            #endif
        }
    }
}

public protocol ImageLoadingDelegate {
    func channelCount(for fileInfo: ImageFileInfo) -> Int
    func allocateMemory(byteCount: Int, alignment: Int, zeroed: Bool) async throws -> (allocation: UnsafeMutableRawBufferPointer, allocator: ImageAllocator)
}

extension ImageLoadingDelegate {
    public func channelCount(for fileInfo: ImageFileInfo) -> Int {
        return fileInfo.channelCount == 3 ? 4 : fileInfo.channelCount
    }
    
    public func allocateMemory(byteCount: Int, alignment: Int, zeroed: Bool) throws -> (allocation: UnsafeMutableRawBufferPointer, allocator: ImageAllocator) {
        return ImageAllocator.allocateMemoryDefault(byteCount: byteCount, alignment: alignment, zeroed: zeroed)
    }
}

@usableFromInline
struct DefaultImageLoadingDelegate: ImageLoadingDelegate {}

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
    
#if canImport(AppKit)
    fileprivate var requiresNSBitmapImageRepDecode: Bool {
        guard let format = self.format else { return false }
        if format == .genericImage {
            // public.image is used for images where NSBitmapImageRep
            // was used to load them but we don't know the exact format.
            return true
        }
        return !ImageFileFormat.nativeFormats.contains(format) && NSBitmapImageRep.imageTypes.contains(where: { $0 == format.typeIdentifier })
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
        
#if canImport(AppKit)
        if fileInfo.requiresNSBitmapImageRepDecode {
            guard let bitmapImage = NSBitmapImageRep(data: try Data(contentsOf: url, options: .mappedIfSafe)) else {
                throw ImageLoadingError.invalidFile(url)
            }
            self = try bitmapImage.makeImage(colorSpace: colorSpace, alphaMode: alphaMode, fileInfo: fileInfo, loadingDelegate: loadingDelegate)
            return
        }
#endif
        
        let channels = loadingDelegate.channelCount(for: fileInfo)
        
        let colorSpace = colorSpace != .undefined ? colorSpace : fileInfo.colorSpace
        let alphaMode = alphaMode != .inferred ? alphaMode : fileInfo.alphaMode.inferFromFileFormat(format: fileInfo.format, channelCount: channels)
        
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
        
#if canImport(AppKit)
        if fileInfo.requiresNSBitmapImageRepDecode {
            guard let bitmapImage = NSBitmapImageRep(data: data) else {
                throw ImageLoadingError.invalidData(message: "Unknown error in NSBitmapImageRep decoding")
            }
            self = try bitmapImage.makeImage(colorSpace: colorSpace, alphaMode: alphaMode, fileInfo: fileInfo, loadingDelegate: loadingDelegate)
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
        
#if canImport(AppKit)
        if fileInfo.requiresNSBitmapImageRepDecode {
            guard let bitmapImage = NSBitmapImageRep(data: try Data(contentsOf: url, options: .mappedIfSafe)) else {
                throw ImageLoadingError.invalidFile(url)
            }
            self = try bitmapImage.makeImage(fileInfo: fileInfo, loadingDelegate: loadingDelegate)
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
        
#if canImport(AppKit)
        if fileInfo.requiresNSBitmapImageRepDecode {
            guard let bitmapImage = NSBitmapImageRep(data: data) else {
                throw ImageLoadingError.invalidData(message: "Unknown error in NSBitmapImageRep decoding")
            }
            self = try bitmapImage.makeImage(fileInfo: fileInfo, loadingDelegate: loadingDelegate)
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
        
        if fileInfo.decodableByWuffs {
            do {
                try self.init(wuffsFileAt: url, fileInfo: fileInfo, colorSpace: colorSpace, alphaMode: alphaMode, loadingDelegate: loadingDelegate)
                return
            } catch {
                assertionFailure("Wuffs decoding failed: \(error)")
            }
        }
        
#if canImport(AppKit)
        if fileInfo.requiresNSBitmapImageRepDecode {
            guard let bitmapImage = NSBitmapImageRep(data: try Data(contentsOf: url, options: .mappedIfSafe)) else {
                throw ImageLoadingError.invalidFile(url)
            }
            self = try bitmapImage.makeImage(colorSpace: colorSpace, alphaMode: alphaMode, fileInfo: fileInfo, loadingDelegate: loadingDelegate)
            return
        }
#endif
        
        let channels = loadingDelegate.channelCount(for: fileInfo)
        let colorSpace = colorSpace != .undefined ? colorSpace : fileInfo.colorSpace
        let alphaMode = alphaMode != .inferred ? alphaMode : fileInfo.alphaMode.inferFromFileFormat(format: fileInfo.format, channelCount: channels)
        
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
        
#if canImport(AppKit)
        if fileInfo.requiresNSBitmapImageRepDecode {
            guard let bitmapImage = NSBitmapImageRep(data: data) else {
                throw ImageLoadingError.invalidData(message: "Unknown error in NSBitmapImageRep decoding")
            }
            self = try bitmapImage.makeImage(colorSpace: colorSpace, alphaMode: alphaMode, fileInfo: fileInfo, loadingDelegate: loadingDelegate)
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
        
#if canImport(AppKit)
        if fileInfo.requiresNSBitmapImageRepDecode {
            guard let bitmapImage = NSBitmapImageRep(data: try Data(contentsOf: url, options: .mappedIfSafe)) else {
                throw ImageLoadingError.invalidFile(url)
            }
            self = try bitmapImage.makeImage(colorSpace: colorSpace, alphaMode: alphaMode, fileInfo: fileInfo, loadingDelegate: loadingDelegate)
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
        
#if canImport(AppKit)
        if fileInfo.requiresNSBitmapImageRepDecode {
            guard let bitmapImage = NSBitmapImageRep(data: data) else {
                throw ImageLoadingError.invalidData(message: "Unknown error in NSBitmapImageRep decoding")
            }
            self = try bitmapImage.makeImage(colorSpace: colorSpace, alphaMode: alphaMode, fileInfo: fileInfo, loadingDelegate: loadingDelegate)
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
    }
    
    public init(exrAt url: URL, loadingDelegate: ImageLoadingDelegate? = nil) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        try self.init(exrData: data, loadingDelegate: loadingDelegate)
    }
}

#if canImport(CoreGraphics)
import CoreGraphics


extension Image {
    public var cgColorSpace: CGColorSpace {
        let isGrayscale = self.channelCount < 3
        
        let colorSpace: CGColorSpace
        switch self.colorSpace {
        case .undefined:
            colorSpace = isGrayscale ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
        case .gammaSRGB(let gamma):
            var whitePoint: [CGFloat] = [0.3127, 0.3290, 1.0]
            colorSpace = CGColorSpace(calibratedGrayWhitePoint: &whitePoint, blackPoint: nil, gamma: CGFloat(gamma)) ?? CGColorSpace(name: CGColorSpace.linearSRGB)!
        case .linearSRGB:
            colorSpace = CGColorSpace(name: isGrayscale ? CGColorSpace.linearGray : CGColorSpace.linearSRGB)!
        case .sRGB:
            colorSpace = CGColorSpace(name: isGrayscale ? CGColorSpace.genericGrayGamma2_2 : CGColorSpace.sRGB)!
        }
        return colorSpace
    }
    
    public var cgBitmapInfo: CGBitmapInfo {
        var bitmapInfo = CGBitmapInfo()
        if T.self == Float.self {
            bitmapInfo.formUnion(.floatComponents)
        } else if T.self == UInt16.self {
            bitmapInfo.formUnion(.byteOrder16Little)
        } else if T.self == UInt32.self {
            bitmapInfo.formUnion(.byteOrder32Little)
        }
        if self.channelCount == 4 || self.channelCount == 2 {
            bitmapInfo.formUnion(CGBitmapInfo(rawValue: self.alphaMode == .premultiplied ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.last.rawValue))
        } else {
            bitmapInfo.formUnion(CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue))
        }
        return bitmapInfo
    }
}

extension Image where ComponentType: SIMDScalar {
    @_specialize(kind: full, where ComponentType == UInt8)
    @_specialize(kind: full, where ComponentType == UInt16)
    @_specialize(kind: full, where ComponentType == Float)
    init(_cgImage cgImage: CGImage, fileInfo: ImageFileInfo?, loadingDelegate: ImageLoadingDelegate? = nil) throws {
        var cgImage = cgImage
        
        let cgColorSpace = cgImage.colorSpace
        let colorSpace: ImageColorSpace
        switch cgColorSpace?.name {
        case CGColorSpace.linearSRGB, CGColorSpace.linearGray, CGColorSpace.extendedLinearSRGB:
            colorSpace = .linearSRGB
        case CGColorSpace.sRGB, CGColorSpace.extendedSRGB:
            colorSpace = .sRGB
        default:
            if ComponentType.self == UInt8.self, let sRGB = cgImage.copy(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) {
                cgImage = sRGB
                colorSpace = .sRGB
            } else if let linearSRGB = cgImage.copy(colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!) {
                cgImage = linearSRGB
                colorSpace = .linearSRGB
            } else {
                colorSpace = .undefined
            }
        }
        
        guard let data = cgImage.dataProvider?.data as NSData? else {
            throw ImageLoadingError.invalidData(message: "Unable to retrieve CGImage data provider")
        }
        
        let alphaMode: ImageAlphaMode
        switch cgImage.alphaInfo {
        case .first, .last:
            alphaMode = .postmultiplied
        case .premultipliedFirst, .premultipliedLast:
            alphaMode = .premultiplied
        default:
            alphaMode = .none
        }
        
        let loadingDelegate = loadingDelegate ?? DefaultImageLoadingDelegate()
        let channelCount = fileInfo.map { loadingDelegate.channelCount(for: $0) } ?? (cgImage.bitsPerPixel / cgImage.bitsPerComponent)
        
        let (imageData, allocator) = try loadingDelegate.allocateMemory(byteCount: cgImage.width * cgImage.height * channelCount * MemoryLayout<ComponentType>.stride, alignment: MemoryLayout<SIMD4<ComponentType>>.stride, zeroed: false)
        
        self.init(width: cgImage.width, height: cgImage.height,
                  channelCount: channelCount,
                  colorSpace: colorSpace,
                  alphaMode: alphaMode,
                  data: imageData.bindMemory(to: ComponentType.self),
                  allocator: allocator)
        
        let sourceChannelCount = cgImage.bitsPerPixel / cgImage.bitsPerComponent
        let width = self.width
        let height = self.height
        
        self.withUnsafeMutableBufferPointer { contentsBuffer in
            for y in 0..<height {
                let base = data.bytes + y * cgImage.bytesPerRow
                let dest = contentsBuffer.baseAddress!.advanced(by: y * width * channelCount)
                if sourceChannelCount == channelCount {
                    for i in 0..<width * channelCount {
                        dest.advanced(by: i).initialize(to: base.load(fromByteOffset: i * MemoryLayout<ComponentType>.stride, as: ComponentType.self))
                    }
                } else {
                    for x in 0..<width {
                        for c in 0..<Swift.min(sourceChannelCount, channelCount) {
                            dest.advanced(by: x * channelCount + c).initialize(to: base.load(fromByteOffset: (x * sourceChannelCount + c) * MemoryLayout<ComponentType>.stride, as: ComponentType.self))
                        }
                        for c in Swift.min(sourceChannelCount, channelCount)..<channelCount {
                            dest.advanced(by: x * channelCount + c).withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<ComponentType>.size) { $0.initialize(repeating: 0 as UInt8, count: MemoryLayout<ComponentType>.size) }
                        }
                    }
                }
            }
            
            // Reference: https://stackoverflow.com/a/49087310
            let alphaInfo: CGImageAlphaInfo? = CGImageAlphaInfo(rawValue: cgImage.bitmapInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue)
            let alphaFirst: Bool = alphaInfo == .premultipliedFirst || alphaInfo == .first || alphaInfo == .noneSkipFirst
            let alphaLast: Bool = alphaInfo == .premultipliedLast || alphaInfo == .last || alphaInfo == .noneSkipLast
            var argbOrder: Bool = false
            if cgImage.bitsPerComponent == 8, !cgImage.bitmapInfo.intersection([.byteOrder16Little, .byteOrder32Little]).isEmpty {
                argbOrder = true
            } else if cgImage.bitsPerComponent == 16, cgImage.bitmapInfo.contains(.byteOrder32Little) {
                argbOrder = true
            } else if cgImage.bitsPerComponent == 16, !cgImage.bitmapInfo.contains(.byteOrder16Little) {
                contentsBuffer.withMemoryRebound(to: UInt16.self) { buffer in
                    for i in buffer.indices {
                        buffer[i] = buffer[i].bigEndian
                    }
                }
                
                argbOrder = false
            } else if cgImage.bitsPerComponent == 32, !cgImage.bitmapInfo.contains(.byteOrder32Little) {
                contentsBuffer.withMemoryRebound(to: UInt32.self) { buffer in
                    for i in buffer.indices {
                        buffer[i] = buffer[i].bigEndian
                    }
                }
                
                argbOrder = false
            }
            
            if channelCount == 2 {
                if alphaFirst != argbOrder {
                    for baseIndex in stride(from: 0, to: contentsBuffer.count, by: channelCount) {
                        contentsBuffer.swapAt(baseIndex + 0, baseIndex + 1) // AR to RA
                    }
                }
            } else if channelCount == 3 {
                if argbOrder {
                    for baseIndex in stride(from: 0, to: contentsBuffer.count, by: channelCount) {
                        contentsBuffer.swapAt(baseIndex + 0, baseIndex + 2) // BGR to RGB
                    }
                }
            } else if channelCount == 4 {
                let swizzle: SIMD4<Int>
                if alphaFirst && argbOrder {
                    swizzle = SIMD4(2, 1, 0, 3)
                } else if alphaFirst {
                    swizzle = SIMD4(1, 2, 3, 0)
                } else if alphaLast && argbOrder {
                    swizzle = SIMD4(3, 2, 1, 0)
                } else {
                    swizzle = SIMD4(0, 1, 2, 3)
                }
                
                if swizzle != SIMD4(0, 1, 2, 3) {
                    contentsBuffer.withMemoryRebound(to: SIMD4<ComponentType>.self) { buffer in
                        for i in buffer.indices {
                            buffer[i] = buffer[i][swizzle]
                        }
                    }
                }
            }
        }
    }
}

extension Image where ComponentType: SIMDScalar & UnsignedInteger & FixedWidthInteger {
    @_specialize(kind: full, where ComponentType == UInt8)
    @_specialize(kind: full, where ComponentType == UInt16)
    public init(cgImage: CGImage, fileInfo: ImageFileInfo? = nil, loadingDelegate: ImageLoadingDelegate? = nil) throws {
        try self.init(_cgImage: cgImage, fileInfo: fileInfo, loadingDelegate: loadingDelegate)
        
        if let fileInfo = fileInfo, fileInfo.channelCount < self.channelCount {
            let alphaChannelIndex = self.channelCount - 1
            self.apply(channelRange: alphaChannelIndex..<self.channelCount) { _ in
                ComponentType.max
            }
        }
    }
}

extension Image where ComponentType: SIMDScalar & SignedInteger & FixedWidthInteger {
    public init(cgImage: CGImage, fileInfo: ImageFileInfo? = nil, loadingDelegate: ImageLoadingDelegate? = nil) throws {
        try self.init(_cgImage: cgImage, fileInfo: fileInfo, loadingDelegate: loadingDelegate)
    }
}

extension Image where ComponentType: SIMDScalar & BinaryFloatingPoint {
    @_specialize(kind: full, where ComponentType == Float)
    public init(cgImage: CGImage, fileInfo: ImageFileInfo? = nil, loadingDelegate: ImageLoadingDelegate? = nil) throws {
        try self.init(_cgImage: cgImage, fileInfo: fileInfo, loadingDelegate: loadingDelegate)
        
        if let fileInfo = fileInfo, fileInfo.channelCount < self.channelCount {
            let alphaChannelIndex = self.channelCount - 1
            self.apply(channelRange: alphaChannelIndex..<self.channelCount) { _ in
                1.0
            }
        }
    }
}

#endif

#if canImport(AppKit)

extension Image {
    @inline(__always)
    fileprivate func converted<R>(to format: R.Type) throws -> Image<R> {
        if R.self == ComponentType.self {
            return self as! Image<R>
        }
        if ComponentType.self == Float.self {
            if R.self == UInt8.self {
                return Image<UInt8>(self as! Image<Float>) as! Image<R>
            } else if R.self == Int8.self {
                return Image<Int8>(self as! Image<Float>) as! Image<R>
            } else if R.self == UInt16.self {
                return Image<UInt16>(self as! Image<Float>) as! Image<R>
            } else if R.self == Int16.self {
                return Image<Int16>(self as! Image<Float>) as! Image<R>
            }
        } else if ComponentType.self == UInt8.self {
            if R.self == UInt16.self {
                return (self as! Image<UInt16>).map { Int16($0) } as! Image<R>
            } else if R.self == Float.self {
                return Image<Float>(self as! Image<UInt8>) as! Image<R>
            }
        } else if ComponentType.self == Int8.self {
            if R.self == Int16.self {
                return (self as! Image<Int8>).map { Int16($0) } as! Image<R>
            } else if R.self == Float.self {
                return Image<Float>(self as! Image<Int8>) as! Image<R>
            }
        } else if ComponentType.self == UInt16.self {
            if R.self == Float.self {
                return Image<Float>(self as! Image<UInt16>) as! Image<R>
            }
        } else if ComponentType.self == Int16.self {
            if R.self == Float.self {
                return Image<Float>(self as! Image<Int16>) as! Image<R>
            }
        }
        throw ImageLoadingError.unsupportedComponentFormat(R.self)
    }
}

extension NSBitmapImageRep {
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
    
    @inline(__always)
    func makeImage<T: SIMDScalar>(format: T.Type = T.self, colorSpace: ImageColorSpace = .undefined, alphaMode: ImageAlphaMode = .inferred, fileInfo: ImageFileInfo, loadingDelegate: ImageLoadingDelegate? = nil) throws -> Image<T> {
        if let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let image = try? self.makeImageFromCGImage(cgImage: cgImage, format: format, fileInfo: fileInfo, loadingDelegate: loadingDelegate) {
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
