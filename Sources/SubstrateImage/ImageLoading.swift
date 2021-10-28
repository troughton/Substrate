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
    
    init(width: Int, height: Int, channelCount: Int,
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
            
            let result = data.withUnsafeBytes { lodepng_inspect(&width, &height, &state, $0.baseAddress?.assumingMemoryBound(to: UInt8.self), $0.count) }
            if result != 0 {
                throw ImageLoadingError.invalidData
            }
            
            self.format = .png
            self.width = Int(width)
            self.height = Int(height)
            self.channelCount = withUnsafePointer(to: state.info_png.color) { Int(lodepng_get_channels($0)) }
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
        case nil:
            if let format = try? Self.init(format: .exr, data: data) {
                self = format
                return
            } else if let format = try? Self.init(format: .png, data: data) {
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
                assertionFailure("Wuffs decoding failed: \(error)")
            }
        }
        
        let channels = loadingDelegate.channelCount(for: fileInfo)
        
        let colorSpace = colorSpace != .undefined ? colorSpace : fileInfo.colorSpace
        let alphaMode = alphaMode != .inferred ? alphaMode : fileInfo.alphaMode.inferFromFileFormat(fileExtension: url.pathExtension, channelCount: channels)
        
        let delegateWrapper = STBLoadingDelegate(loadingDelegate: loadingDelegate, expectedSize: MemoryLayout<ComponentType>.stride * fileInfo.width * fileInfo.height * channels)
        setupStbImageAllocatorContext(delegateWrapper)
        defer { tearDownStbImageAllocatorContext(overrides: delegateWrapper.overrides) }
        
        var width : Int32 = 0
        var height : Int32 = 0
        var componentsPerPixel : Int32 = 0
        guard let data = stbi_load(url.path, &width, &height, &componentsPerPixel, Int32(channels)) else {
            throw ImageLoadingError.invalidImageDataFormat(url, T.self)
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
                assertionFailure("Wuffs decoding failed: \(error)")
            }
        }
        
        let channels = loadingDelegate.channelCount(for: fileInfo)
        
        let delegateWrapper = STBLoadingDelegate(loadingDelegate: loadingDelegate, expectedSize: MemoryLayout<ComponentType>.stride * fileInfo.width * fileInfo.height * channels)
        setupStbImageAllocatorContext(delegateWrapper)
        defer { tearDownStbImageAllocatorContext(overrides: delegateWrapper.overrides) }
        
        self = try data.withUnsafeBytes { data in
            var width : Int32 = 0
            var height : Int32 = 0
            var componentsPerPixel : Int32 = 0
            guard let data = stbi_load_from_memory(data.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32(data.count), &width, &height, &componentsPerPixel, Int32(channels)) else {
                throw ImageLoadingError.invalidData
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
        
        let channels = loadingDelegate.channelCount(for: fileInfo)
        let delegateWrapper = STBLoadingDelegate(loadingDelegate: loadingDelegate, expectedSize: MemoryLayout<ComponentType>.stride * fileInfo.width * fileInfo.height * channels)
        setupStbImageAllocatorContext(delegateWrapper)
        defer { tearDownStbImageAllocatorContext(overrides: delegateWrapper.overrides) }
        
        var width : Int32 = 0
        var height : Int32 = 0
        var componentsPerPixel : Int32 = 0
        guard let data = stbi_load(url.path, &width, &height, &componentsPerPixel, Int32(channels)) else {
            throw ImageLoadingError.invalidImageDataFormat(url, T.self)
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
        
        let channels = loadingDelegate.channelCount(for: fileInfo)
        let delegateWrapper = STBLoadingDelegate(loadingDelegate: loadingDelegate, expectedSize: MemoryLayout<ComponentType>.stride * fileInfo.width * fileInfo.height * channels)
        setupStbImageAllocatorContext(delegateWrapper)
        defer { tearDownStbImageAllocatorContext(overrides: delegateWrapper.overrides) }
        
        self = try data.withUnsafeBytes { data in
            var width : Int32 = 0
            var height : Int32 = 0
            var componentsPerPixel : Int32 = 0
            guard let data = stbi_load_from_memory(data.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32(data.count), &width, &height, &componentsPerPixel, Int32(channels)) else {
                throw ImageLoadingError.invalidData
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
        
        let channels = loadingDelegate.channelCount(for: fileInfo)
        let colorSpace = colorSpace != .undefined ? colorSpace : fileInfo.colorSpace
        let alphaMode = alphaMode != .inferred ? alphaMode : fileInfo.alphaMode.inferFromFileFormat(fileExtension: url.pathExtension, channelCount: channels)
        
        let delegateWrapper = STBLoadingDelegate(loadingDelegate: loadingDelegate, expectedSize: MemoryLayout<ComponentType>.stride * fileInfo.width * fileInfo.height * channels)
        setupStbImageAllocatorContext(delegateWrapper)
        defer { tearDownStbImageAllocatorContext(overrides: delegateWrapper.overrides) }
        
        var width : Int32 = 0
        var height : Int32 = 0
        var componentsPerPixel : Int32 = 0
        
        guard let data = stbi_load_16(url.path, &width, &height, &componentsPerPixel, Int32(channels)) else {
            throw ImageLoadingError.invalidImageDataFormat(url, T.self)
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
        
        let channels = loadingDelegate.channelCount(for: fileInfo)
        let delegateWrapper = STBLoadingDelegate(loadingDelegate: loadingDelegate, expectedSize: MemoryLayout<ComponentType>.stride * fileInfo.width * fileInfo.height * channels)
        setupStbImageAllocatorContext(delegateWrapper)
        defer { tearDownStbImageAllocatorContext(overrides: delegateWrapper.overrides) }
        
        self = try data.withUnsafeBytes { data in
            var width : Int32 = 0
            var height : Int32 = 0
            var componentsPerPixel : Int32 = 0
            guard let data = stbi_load_16_from_memory(data.baseAddress?.assumingMemoryBound(to: stbi_uc.self), Int32(data.count), &width, &height, &componentsPerPixel, Int32(channels)) else {
                throw ImageLoadingError.invalidData
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
        
        if fileInfo.isFloatingPoint {
            let loadingDelegate = loadingDelegate ?? DefaultImageLoadingDelegate()
            let channels = loadingDelegate.channelCount(for: fileInfo)
            let colorSpace = colorSpace != .undefined ? colorSpace : fileInfo.colorSpace
            let alphaMode = alphaMode != .inferred ? alphaMode : fileInfo.alphaMode.inferFromFileFormat(fileExtension: url.pathExtension, channelCount: channels)
            
            var width : Int32 = 0
            var height : Int32 = 0
            var componentsPerPixel : Int32 = 0
            
            let delegateWrapper = STBLoadingDelegate(loadingDelegate: loadingDelegate, expectedSize: MemoryLayout<ComponentType>.stride * fileInfo.width * fileInfo.height * channels)
            setupStbImageAllocatorContext(delegateWrapper)
            defer { tearDownStbImageAllocatorContext(overrides: delegateWrapper.overrides) }
            
            guard let data = stbi_loadf(url.path, &width, &height, &componentsPerPixel, Int32(channels)) else {
                throw ImageLoadingError.invalidData
            }
            self.init(width: Int(width),
                      height: Int(height),
                      channelCount: Int(channels),
                      data: .init(start: data, count: delegateWrapper.allocatedSize(for: data) / MemoryLayout<Float>.stride),
                      colorSpace: colorSpace,
                      alphaMode: alphaMode.inferFromFileFormat(fileExtension: url.pathExtension, channelCount: Int(channels)),
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
                    throw ImageLoadingError.invalidData
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
