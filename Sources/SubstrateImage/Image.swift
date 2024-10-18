//
//  ImageConversion.swift
//  SubstrateImageIO
//
//

#if canImport(Darwin)
@preconcurrency import Darwin
#endif
import Foundation
import RealModule
import stb_image_resize
@_exported import SubstrateMath

//@available(*, deprecated, renamed: "ImageColorSpace")
public typealias TextureColorSpace = ImageColorSpace

//@available(*, deprecated, renamed: "ImageColorSpace")
public typealias TextureColourSpace = ImageColorSpace

//@available(*, deprecated, renamed: "Image")
public typealias TextureData = Image

//@available(*, deprecated, renamed: "AnyImage")
public typealias AnyTextureData = AnyImage

//@available(*, deprecated, renamed: "ImageAlphaMode")
public typealias TextureAlphaMode = ImageAlphaMode

//@available(*, deprecated, renamed: "ImageEdgeWrapMode")
public typealias TextureEdgeWrapMode = ImageEdgeWrapMode

//@available(*, deprecated, renamed: "ImageResizeFilter")
public typealias TextureResizeFilter = ImageResizeFilter

@inlinable
func clamp<T: Comparable>(_ val: T, min minValue: T, max maxValue: T) -> T {
    return Swift.min(Swift.max(val, minValue), maxValue)
}

public enum ImageLoadingError : Error {
    case invalidFile(URL, message: String? = nil)
    case invalidData(message: String? = nil)
    case unsupportedComponentFormat(Any.Type)
    case pngDecodingError(String)
    case exrParseError(String)
    case unsupportedMultipartEXR(URL)
    case unsupportedMultipartEXRData
    case privateImageRequiresRenderGraph
    case incorrectBitDepth(found: Int, expected: Int)
    case invalidImageDataFormat(URL, Any.Type)
}

public enum ImageColorSpace: Hashable, Sendable {
    /// The texture values use no defined color space.
    case undefined
    /// The IEC 61966-2-1:1999 color space.
    case sRGB
    /// The IEC 61966-2-1:1999 sRGB color space using a linear gamma.
    case linearSRGB
    /// The IEC 61966-2-1:1999 sRGB color space using a user-specified gamma.
    case gammaSRGB(Float)
    case cieRGB(colorSpace: CIEXYZ1931ColorSpace<Float>)

    @inlinable
    public var withLinearGamma: ImageColorSpace {
        switch self {
        case .undefined:
            return self
        case .sRGB, .gammaSRGB, .linearSRGB:
            return .linearSRGB
        case .cieRGB(var colorSpace):
            colorSpace.eotf = .linear
            return .cieRGB(colorSpace: colorSpace)
        }
    }
    
    @inlinable
    public func fromLinearGamma(_ color: Float) -> Float {
        switch self {
        case .undefined:
            return color
        case .sRGB:
            return color <= 0.0031308 ? (12.92 * color) : (1.055 * pow(color, 1.0 / 2.4) - 0.055)
        case .linearSRGB:
            return color
        case .gammaSRGB(let gamma):
            return pow(color, 1.0 / gamma)
        case .cieRGB(let cie):
            return cie.eotf.linearToEncoded(color)
        }
    }

    @inlinable
    public func toLinearGamma(_ color: Float) -> Float {
        switch self {
        case .undefined:
            return color
        case .sRGB:
            return color <= 0.04045 ? (color / 12.92) : Float.pow((color + 0.055) / 1.055, 2.4)
        case .linearSRGB:
            return color
        case .gammaSRGB(let gamma):
            return Float.pow(color, gamma)
        case .cieRGB(let cie):
            return cie.eotf.encodedToLinear(color)
        }
    }
    
    @inlinable
    public var usesSRGBPrimaries: Bool {
        switch self {
        case .undefined:
            return false
        case .sRGB, .linearSRGB, .gammaSRGB:
            return true
        case .cieRGB(let cie):
            return cie.primaries == .sRGB
        }
    }
    
    @inlinable
    public var cieSpace: CIEXYZ1931ColorSpace<Float>? {
        switch self {
        case .undefined:
            return nil
        case .sRGB:
            return .sRGB
        case .linearSRGB:
            return .linearSRGB
        case .gammaSRGB(let gamma):
            var space = CIEXYZ1931ColorSpace<Float>.sRGB
            space.eotf = .power(gamma)
            return space
        case .cieRGB(let colorSpace):
            return colorSpace
        }
    }
    
    @inlinable
    public static func convert(_ value: Float, from: ImageColorSpace, to: ImageColorSpace) -> Float {
        if from == to { return value }
        
        let inLinearSRGB = from.toLinearGamma(value)
        return to.fromLinearGamma(inLinearSRGB)
    }
    
    @inlinable
    public static func convert(_ value: RGBColor<Float>, from: ImageColorSpace, to: ImageColorSpace) -> RGBColor<Float> {
        if from == to { return value }
        
        guard let fromSpace = from.cieSpace, let toSpace = to.cieSpace else { return value }
        return CIEXYZ1931ColorSpace.convert(value, from: fromSpace, to: toSpace)
    }
    
    @inlinable
    func flatteningCIE() -> ImageColorSpace {
        if case .cieRGB(let colorSpace) = self, colorSpace.primaries == .sRGB, colorSpace.referenceWhite == .d65 {
            switch colorSpace.eotf {
            case .linear:
                return .linearSRGB
            case .sRGB, .rec709:
                return .sRGB
            case .power(let power):
                return .gammaSRGB(power)
            default:
                break
            }
        }
        return self
    }
    
    @inlinable
    public static func ==(lhs: ImageColorSpace, rhs: ImageColorSpace) -> Bool {
        switch (lhs.flatteningCIE(), rhs.flatteningCIE()) {
        case (.undefined, .undefined): return true
        case (.sRGB, .sRGB): return true
        case (.linearSRGB, .linearSRGB): return true
        case (.gammaSRGB(let powerA), .gammaSRGB(let powerB)): return powerA == powerB
        case (.cieRGB(let cieA), .cieRGB(let cieB)): return cieA == cieB
        default: return false
        }
    }
}

extension ImageColorSpace: Codable {
    public enum CodingKeys: CodingKey {
        case gamma
        case cieRGB
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let gamma = try container.decodeIfPresent(Float.self, forKey: .gamma) {
            if !gamma.isFinite || gamma < 0 {
                self = .undefined
            } else if gamma == 0 {
                self = .sRGB // sRGB is encoded as gamma of 0.0
            } else if gamma == 1.0 {
                self = .linearSRGB
            } else {
                self = .gammaSRGB(gamma)
            }
        } else {
            let cieRGB = try container.decode(CIEXYZ1931ColorSpace<Float>.self, forKey: .cieRGB)
            self = .cieRGB(colorSpace: cieRGB)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self.flatteningCIE() {
        case .undefined:
            try container.encode(-1.0 as Float, forKey: .gamma)
        case .sRGB:
            try container.encode(0.0 as Float, forKey: .gamma)
        case .linearSRGB:
            try container.encode(1.0 as Float, forKey: .gamma)
        case .gammaSRGB(let gamma):
            try container.encode(gamma, forKey: .gamma)
        case .cieRGB(let colorSpace):
            try container.encode(colorSpace, forKey: .cieRGB)
        }
    }
}

public typealias ImageColourSpace = ImageColorSpace

public enum ImageAlphaMode: String, Codable, Hashable, Sendable {
    case none
    case premultiplied
    case postmultiplied
    
    case inferred
}

public enum ImageEdgeWrapMode: Hashable, Sendable {
    case zero
    case wrap
    case reflect
    case clamp
    
    @inlinable
    var stbirMode : stbir_edge {
        switch self {
        case .zero:
            return STBIR_EDGE_ZERO
        case .wrap:
            return STBIR_EDGE_WRAP
        case .reflect:
            return STBIR_EDGE_REFLECT
        case .clamp:
            return STBIR_EDGE_CLAMP
        }
    }
}

public enum ImageResizeFilter: Sendable {
    /// Mitchell for downscaling, and Catmull-Rom for upscaling
    case `default`
    /// A trapezoid with 1-pixel wide ramps, producing the same result as a box box for integer scale ratios
    case box
    /// On upsampling, produces same results as bilinear texture filtering
    case triangle
    /// The cubic b-spline (aka Mitchell-Netrevalli with B=1,C=0), gaussian-esque
    case cubicSpline
    /// An interpolating cubic spline
    case catmullRom
    /// Mitchell-Netrevalli filter with B=1/3, C=1/3
    case mitchell
    
    @inlinable
    var stbirFilter : stbir_filter {
        switch self {
        case .default:
            return STBIR_FILTER_DEFAULT
        case .box:
            return STBIR_FILTER_BOX
        case .triangle:
            return STBIR_FILTER_TRIANGLE
        case .cubicSpline:
            return STBIR_FILTER_CUBICBSPLINE
        case .catmullRom:
            return STBIR_FILTER_CATMULLROM
        case .mitchell:
            return STBIR_FILTER_MITCHELL
        }
    }
}

public enum ImageAllocator {
    case system
    case malloc
    case temporaryBuffer
#if canImport(Darwin)
    case vm_allocate
#endif
    case custom(context: AnyObject? = nil, deallocateFunc: (_ allocation: UnsafeMutableRawBufferPointer, _ context: AnyObject?) -> Void)
    
    @_disfavoredOverload
    @inlinable
    public static func custom(context: AnyObject? = nil, deallocateFunc: @escaping (_ allocation: UnsafeMutableRawPointer, _ context: AnyObject?) -> Void) -> ImageAllocator {
        return .custom(context: context) { allocation, context in
            guard let baseAddress = allocation.baseAddress else { return }
            deallocateFunc(baseAddress, context)
        }
    }
    
    @inlinable
    public static func allocateMemoryDefault(byteCount: Int, alignment: Int, zeroed: Bool) -> (UnsafeMutableRawBufferPointer, ImageAllocator) {
#if canImport(Darwin)
        let pageSize = Int(getpagesize())
        if byteCount >= pageSize {
            // Use vm_allocate; this also enables direct uploads into GPU memory where applicable.
            let byteCount = (byteCount + pageSize - 1) & ~(pageSize - 1) // Round up to a multiple of pageSize
            var data = vm_address_t()
            let error = Darwin.vm_allocate(mach_task_self_, &data, vm_size_t(byteCount), VM_FLAGS_ANYWHERE)
            if error == KERN_SUCCESS {
                return (UnsafeMutableRawBufferPointer(start: UnsafeMutableRawPointer(bitPattern: data), count: byteCount), .vm_allocate)
            }
        }
#endif
        let memory = UnsafeMutableRawBufferPointer.allocate(byteCount: byteCount, alignment: alignment)
        if zeroed {
            memory.initializeMemory(as: UInt8.self, repeating: 0)
        }
        return (memory, .system)
    }
    
    @_spi(SubstrateTextureIO)
    public func deallocate(data: UnsafeMutableRawBufferPointer) {
        switch self {
        case .system:
            data.deallocate()
        case .malloc:
            free(data.baseAddress)
        case .temporaryBuffer:
            break
        #if canImport(Darwin)
        case .vm_allocate:
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: data.baseAddress), vm_size_t(data.count))
        #endif
        case .custom(let context, let deallocateFunc):
            deallocateFunc(data, context)
        }
    }
}

@usableFromInline
final class ImageStorage<T> {
    public let data : UnsafeMutableBufferPointer<T>
    @usableFromInline let allocator: ImageAllocator
    
    @inlinable
    init(elementCount: Int, zeroed: Bool) {
        let (memory, allocator) = ImageAllocator.allocateMemoryDefault(byteCount: elementCount * MemoryLayout<T>.stride, alignment: MemoryLayout<T>.alignment, zeroed: zeroed)
        self.data = memory.bindMemory(to: T.self)
        self.allocator = allocator
    }
    
    @inlinable
    init(data: UnsafeMutableBufferPointer<T>, allocator: ImageAllocator) {
        self.data = data
        self.allocator = allocator
    }
    
    @inlinable
    init(copying: UnsafeMutableBufferPointer<T>) {
        let (memory, allocator) = ImageAllocator.allocateMemoryDefault(byteCount: copying.count * MemoryLayout<T>.stride, alignment: MemoryLayout<T>.alignment, zeroed: false)
        self.data = memory.bindMemory(to: T.self)
        _ = self.data.initialize(from: copying)
        self.allocator = allocator
    }
    
    @inlinable
    subscript(x: Int, y: Int, channel channel: Int, width width: Int, height height: Int, channelCount channelCount: Int) -> T {
        @inline(__always) get {
            return self.data[y &* width &* channelCount + x &* channelCount &+ channel]
        }
        @inline(__always) set {
            self.data[y &* width &* channelCount &+ x * channelCount &+ channel] = newValue
        }
    }
    
    deinit {
        self.allocator.deallocate(data: UnsafeMutableRawBufferPointer(self.data))
    }
}

public protocol AnyImage: Codable {
    var fileInfo: ImageFileInfo { get }
    var data: Data { get }
    
    var width : Int { get }
    var height : Int { get }
    var channelCount : Int { get }
    
    var colorSpace : ImageColorSpace { get }
    var alphaMode: ImageAlphaMode { get }
    
    mutating func reinterpretColor(as colorSpace: ImageColorSpace)
    mutating func reinterpretAlphaMode(as alphaMode: ImageAlphaMode)
}

public struct Image<ComponentType> : AnyImage {
    public typealias T = ComponentType
    
    public let width : Int
    public let height : Int
    public let channelCount : Int
    
    public internal(set) var colorSpace : ImageColorSpace
    public internal(set) var alphaMode: ImageAlphaMode
    
    @usableFromInline var storage: ImageStorage<T>
    
    @available(*, deprecated, renamed: "colorSpace")
    public internal(set) var colourSpace: ImageColorSpace {
        get {
            return self.colorSpace
        }
        set {
            self.colorSpace = newValue
        }
    }
    
    public init(width: Int, height: Int, channelCount: Int, colorSpace: ImageColorSpace = .undefined, alphaMode: ImageAlphaMode = .none) {
        precondition(_isPOD(T.self))
        precondition(width >= 1 && height >= 1 && channelCount >= 1)
        precondition(alphaMode != .inferred, "Inferred alpha modes are only valid given existing data.")
        
        self.init(width: width, height: height, channelCount: channelCount, colorSpace: colorSpace, alphaModeAllowInferred: alphaMode, zeroStorage: true)
    }
    
    @available(*, deprecated, renamed: "init(width:height:channelCount:colorSpace:alphaMode:)")
    public init(width: Int, height: Int, channels: Int, colorSpace: ImageColorSpace = .undefined, alphaMode: ImageAlphaMode = .none) {
        self.init(width: width, height: height, channelCount: channels, colorSpace: colorSpace, alphaMode: alphaMode)
    }
    
    @usableFromInline
    init(width: Int, height: Int, channelCount: Int, colorSpace: ImageColorSpace, alphaModeAllowInferred alphaMode: ImageAlphaMode, zeroStorage: Bool) {
        precondition(_isPOD(T.self))
        precondition(width >= 1 && height >= 1 && channelCount >= 1)
        precondition(alphaMode != .inferred, "Inferred alpha modes are only valid given existing data.")
        
        self.width = width
        self.height = height
        self.channelCount = channelCount
        
        self.storage = .init(elementCount: width * height * channelCount, zeroed: zeroStorage)
        
        self.colorSpace = colorSpace
        self.alphaMode = alphaMode
    }
    
    @available(*, deprecated, renamed: "init(width:height:channelCount:colorSpace:alphaMode:)")
    public init(width: Int, height: Int, channels: Int, colorSpace: ImageColorSpace, premultipliedAlpha: Bool) {
        self.init(width: width, height: height, channels: channels, colorSpace: colorSpace, alphaMode: premultipliedAlpha ? .premultiplied : .postmultiplied)
    }
    
    @available(*, deprecated, renamed: "init(width:height:channelCount:colorSpace:alphaMode:)")
    public init(width: Int, height: Int, channels: Int, colourSpace: ImageColorSpace, premultipliedAlpha: Bool = false) {
        self.init(width: width, height: height, channels: channels, colorSpace: colourSpace, alphaMode: premultipliedAlpha ? .premultiplied : .postmultiplied)
    }

    public init(width: Int, height: Int, channelCount: Int, colorSpace: ImageColorSpace = .undefined, alphaMode: ImageAlphaMode = .none, data: UnsafeMutableBufferPointer<T>, allocator: ImageAllocator) {
        precondition(width >= 1 && height >= 1 && channelCount >= 1)
        precondition(alphaMode != .inferred, "Cannot infer the alpha mode when T is not Comparable.")
        precondition(data.count >= width * height * channelCount)
        
        self.width = width
        self.height = height
        self.channelCount = channelCount
        
        self.storage = .init(data: data, allocator: allocator)
        
        self.colorSpace = colorSpace
        self.alphaMode = alphaMode
    }
    
    @available(*, deprecated, renamed: "init(width:height:channelCount:colorSpace:alphaMode:data:allocator:)")
    public init(width: Int, height: Int, channels: Int, colorSpace: ImageColorSpace = .undefined, alphaMode: ImageAlphaMode = .none, data: UnsafeMutablePointer<T>, allocator: ImageAllocator) {
        self.init(width: width, height: height, channelCount: channels, colorSpace: colorSpace, alphaMode: alphaMode, data: UnsafeMutableBufferPointer<T>(start: data, count: width * height * channels), allocator: allocator)
    }
    
    @available(*, deprecated, renamed: "init(width:height:channels:colorSpace:alphaMode:data:allocator:)")
    public init(width: Int, height: Int, channels: Int, colorSpace: ImageColorSpace = .undefined, alphaMode: ImageAlphaMode = .none, data: UnsafeMutablePointer<T>, deallocateFunc: @escaping (UnsafeMutablePointer<T>) -> Void) {
        self.init(width: width, height: height, channels: channels, colorSpace: colorSpace, alphaMode: alphaMode, data: data, allocator: .custom(deallocateFunc: { rawPointer, _ in
            deallocateFunc(rawPointer.assumingMemoryBound(to: T.self))
        }))
    }
    
    @available(*, deprecated, renamed: "init(width:height:channels:colorSpace:alphaMode:data:allocator:)")
    public init(width: Int, height: Int, channels: Int, data: UnsafeMutablePointer<T>, colorSpace: ImageColorSpace = .undefined, alphaMode: ImageAlphaMode = .none, deallocateFunc: @escaping (UnsafeMutablePointer<T>) -> Void) {
        self.init(width: width, height: height, channels: channels, colorSpace: colorSpace, alphaMode: alphaMode, data: data, allocator: .custom(deallocateFunc: { rawPointer, _ in
            deallocateFunc(rawPointer.assumingMemoryBound(to: T.self))
        }))
    }
        
    @available(*, deprecated, renamed: "init(width:height:channels:colorSpace:alphaMode:data:allocator:)")
    public init(width: Int, height: Int, channels: Int, data: UnsafeMutablePointer<T>, colorSpace: ImageColorSpace, premultipliedAlpha: Bool, deallocateFunc: @escaping (UnsafeMutablePointer<T>) -> Void) {
        self.init(width: width, height: height, channels: channels, colorSpace: colorSpace, alphaMode: premultipliedAlpha ? .premultiplied : .postmultiplied, data: data, allocator: .custom(deallocateFunc: { rawPointer, _ in
            deallocateFunc(rawPointer.assumingMemoryBound(to: T.self))
        }))
    }
    
    @available(*, deprecated, renamed: "init(width:height:channels:colorSpace:alphaMode:data:allocator:)")
    public init(width: Int, height: Int, channels: Int, data: UnsafeMutablePointer<T>, colourSpace: ImageColorSpace, premultipliedAlpha: Bool = false, deallocateFunc: @escaping (UnsafeMutablePointer<T>) -> Void) {
        self.init(width: width, height: height, channels: channels, colorSpace: colourSpace, alphaMode: premultipliedAlpha ? .premultiplied : .postmultiplied, data: data, allocator: .custom(deallocateFunc: { rawPointer, _ in
            deallocateFunc(rawPointer.assumingMemoryBound(to: T.self))
        }))
    }
    
    @inlinable
    public init(_ other: Image<ComponentType>) {
        self = other
    }
    
    @inlinable
    public init?<Other>(_ other: Image<Other>) {
        if let image = other as? Image<ComponentType> {
            self = image
        } else if let image = other as? Image<Float> {
            if ComponentType.self == UInt8.self {
                self = Image<UInt8>(image) as! Image<ComponentType>
            } else if ComponentType.self == Int8.self {
                self = Image<Int8>(image) as! Image<ComponentType>
            } else if ComponentType.self == UInt16.self {
                self = Image<UInt16>(image) as! Image<ComponentType>
            } else if ComponentType.self == Int16.self {
                self = Image<Int16>(image) as! Image<ComponentType>
            } else {
                return nil
            }
        } else if let image = other as? Image<UInt8> {
            if ComponentType.self == UInt16.self {
                self = Image<UInt16>(image) as! Image<ComponentType>
            } else if ComponentType.self == Int8.self {
                self = Image<Int8>(image) as! Image<ComponentType>
            } else if ComponentType.self == UInt16.self {
                self = Image<UInt16>(image) as! Image<ComponentType>
            } else if ComponentType.self == Int16.self {
                self = Image<Int16>(image) as! Image<ComponentType>
            } else if ComponentType.self == Float.self {
                self = Image<Float>(image) as! Image<ComponentType>
            } else {
                return nil
            }
        } else if let image = other as? Image<Int8> {
            if ComponentType.self == Int16.self {
                self = Image<Int16>(image) as! Image<ComponentType>
            } else if ComponentType.self == Float.self {
                self = Image<Float>(image) as! Image<ComponentType>
            } else {
                return nil
            }
        } else if let image = other as? Image<UInt16> {
            if ComponentType.self == Float.self {
                self = Image<Float>(image) as! Image<ComponentType>
            } else {
                return nil
            }
        } else if let image = other as? Image<Int16> {
            if ComponentType.self == Float.self {
                self = Image<Float>(image) as! Image<ComponentType>
            } else {
                return nil
            }
        } else {
            return nil
        }
    }
    
    @inlinable
    mutating func ensureUniqueness() {
        if !isKnownUniquelyReferenced(&self.storage) {
            self.storage = .init(copying: self.truncatedStorageData)
        }
    }
    
    @inlinable
    public var allocator: ImageAllocator {
        return self.storage.allocator
    }
    
    public var componentsPerRow: Int {
        return self.width * self.channelCount
    }
    
    @inlinable
    public var allocatedSize: Int {
        return self.storage.data.count * MemoryLayout<ComponentType>.stride
    }
    
    @inlinable
    public var elementCount: Int {
        return self.height * self.componentsPerRow
    }
    
    @usableFromInline
    var truncatedStorageData: UnsafeMutableBufferPointer<ComponentType> {
        // ImageStorage may be over-allocated, so this returns only the portion that contains valid pixels.
        return UnsafeMutableBufferPointer(start: self.storage.data.baseAddress, count: self.elementCount)
    }
    
    @inlinable
    public var alphaChannelIndex: Int? {
        switch self.alphaMode {
        case .none:
            return nil
        default:
            return self.channelCount - 1
        }
    }
    
    public var fileInfo: ImageFileInfo {
        let isFloatingPoint: Bool
        let isSigned: Bool
        switch T.self {
        #if (os(iOS) || os(tvOS) || os(watchOS)) && !targetEnvironment(macCatalyst)
        case is Float16.Type:
            isFloatingPoint = true
            isSigned = true
        #endif
        case is Float.Type, is Double.Type:
            isFloatingPoint = true
            isSigned = true
        #if arch(x86_64) && !os(Windows)
        case is Float80.Type:
            isFloatingPoint = true
            isSigned = true
        #endif
        case is Int8.Type, is Int16.Type, is Int32.Type, is Int64.Type:
            isFloatingPoint = false
            isSigned = false
        default:
            isFloatingPoint = false
            isSigned = false
        }
        return ImageFileInfo(width: self.width, height: self.height, channelCount: self.channelCount,
                             bitDepth: MemoryLayout<ComponentType>.size * 8, isSigned: isSigned, isFloatingPoint: isFloatingPoint,
                             colorSpace: self.colorSpace, alphaMode: self.alphaMode)
    }
    
    public var data: Data {
        let data = self.truncatedStorageData
        return Data(bytesNoCopy: UnsafeMutableRawPointer(data.baseAddress!), count: data.count, deallocator: .custom({ [self] _, _ in
            _ = self
        }))
    }
    
    @available(*, deprecated, renamed: "alphaMode")
    @inlinable
    public var premultipliedAlpha: Bool {
        return self.alphaMode == .premultiplied
    }
    
    /// Reinterprets the texture's pixel data as belonging to the specified color space.
    public mutating func reinterpretColor(as colorSpace: ImageColorSpace) {
        self.colorSpace = colorSpace
    }
    
    /// Reinterprets the texture's alpha data as using the specified alpha mode.
    public mutating func reinterpretAlphaMode(as alphaMode: ImageAlphaMode) {
        precondition(alphaMode != .inferred, "Cannot reinterpret the alpha mode as inferred.")
        self.alphaMode = alphaMode
    }
    
    @inlinable @inline(__always)
    func uncheckedIndex(x: Int, y: Int, channel: Int) -> Int {
        return y &* self.componentsPerRow &+ x &* self.channelCount &+ channel
    }
    
    @inlinable @inline(__always)
    func setUnchecked(x: Int, y: Int, channel: Int, value: T) {
        self.storage.data[self.uncheckedIndex(x: x, y: y, channel: channel)] = value
    }
    
    @inlinable
    public subscript(x: Int, y: Int, channel channel: Int) -> T {
        @inline(__always) get {
            precondition(x >= 0 && y >= 0 && channel >= 0 && x < self.width && y < self.height && channel < self.channelCount)
            return self.storage.data[self.uncheckedIndex(x: x, y: y, channel: channel)]
        }
        @inline(__always) set {
            precondition(x >= 0 && y >= 0 && channel >= 0 && x < self.width && y < self.height && channel < self.channelCount)
            self.ensureUniqueness()
            self.storage.data[self.uncheckedIndex(x: x, y: y, channel: channel)] = newValue
        }
    }
    
    @inlinable
    public subscript(checked x: Int, y: Int, channel channel: Int) -> T? {
        guard x >= 0, y >= 0, channel >= 0,
            x < self.width, y < self.height, channel < self.channelCount else {
                return nil
        }
        return self.storage.data[self.uncheckedIndex(x: x, y: y, channel: channel)]
    }
    
    @inlinable
    public mutating func apply(_ mapValues: (T) -> T) {
        self.apply(channelRange: 0..<self.channelCount, mapValues)
    }
    
    
    @inlinable
    public mutating func apply(_ mapValues: (_ x: Int, _ y: Int, _ channel: Int, _ value: T) -> T) {
        self.apply(channelRange: 0..<self.channelCount, mapValues)
    }
    
    @inlinable
    public mutating func apply(channelRange: Range<Int>, _ mapValues: (T) -> T) {
        precondition(channelRange.lowerBound >= 0 && channelRange.upperBound <= self.channelCount)
        self.ensureUniqueness()
        for y in 0..<self.height {
            let yBase = y * self.componentsPerRow
            for x in 0..<self.width {
                let baseIndex = yBase + x * self.channelCount
                for c in channelRange {
                    self.storage.data[baseIndex + c] = mapValues(self.storage.data[baseIndex + c])
                }
            }
        }
    }
    
    @inlinable
    public mutating func apply(channelRange: Range<Int>, _ mapValues: (_ x: Int, _ y: Int, _ channel: Int, _ value: T) -> T) {
        precondition(channelRange.lowerBound >= 0 && channelRange.upperBound <= self.channelCount)
        self.ensureUniqueness()
        for y in 0..<self.height {
            let yBase = y * self.componentsPerRow
            for x in 0..<self.width {
                let baseIndex = yBase + x * self.channelCount
                for c in channelRange {
                    self.storage.data[baseIndex + c] = mapValues(x, y, c, self.storage.data[baseIndex + c])
                }
            }
        }
    }
    
    @available(*, deprecated, renamed: "apply(channelRange:_:)")
    @inlinable
    public mutating func apply(_ function: (T) -> T, channelRange: Range<Int>) {
        self.apply(channelRange: channelRange, function)
    }
    
    @inlinable
    public func forEachPixel(_ function: (_ x: Int, _ y: Int, _ channel: Int, _ value: T) -> Void) {
        for y in 0..<self.height {
            let yBase = y * self.componentsPerRow
            for x in 0..<self.width {
                let baseIndex = yBase + x * self.channelCount
                for c in 0..<self.channelCount {
                    function(x, y, c, self.storage.data[baseIndex + c])
                }
            }
        }
    }
    
    @inlinable
    public func withUnsafeBufferPointer<R>(_ perform: (UnsafeBufferPointer<T>) throws -> R) rethrows -> R {
        return try perform(UnsafeBufferPointer(self.truncatedStorageData))
    }
    
    @inlinable
    public mutating func withUnsafeMutableBufferPointer<R>(_ perform: (UnsafeMutableBufferPointer<T>) throws -> R) rethrows -> R {
        self.ensureUniqueness()
        return try perform(self.truncatedStorageData)
    }
    
    @inlinable
    public func withUnsafeBufferPointer<R>(_ perform: (UnsafeBufferPointer<T>) async throws -> R) async rethrows -> R {
        return try await perform(UnsafeBufferPointer(self.storage.data))
    }
    
    @inlinable
    public mutating func withUnsafeMutableBufferPointer<R>(_ perform: (UnsafeMutableBufferPointer<T>) async throws -> R) async rethrows -> R {
        self.ensureUniqueness()
        return try await perform(self.storage.data)
    }
    
    @inlinable
    public func map<Other>(_ function: (ComponentType) -> Other) -> Image<Other> {
        var other = Image<Other>(width: self.width, height: self.height, channelCount: self.channelCount, colorSpace: self.colorSpace, alphaMode: self.alphaMode)
        
        other.withUnsafeMutableBufferPointer { dest in
            self.withUnsafeBufferPointer { source in
                for (i, sourceVal) in source.enumerated() {
                    dest[i] = function(sourceVal)
                }
            }
        }
        
        return other
    }
    
    @inlinable
    public func map<Other>(_ function: (_ x: Int, _ y: Int, _ channel: Int, _ value: ComponentType) -> Other) -> Image<Other> {
        var other = Image<Other>(width: self.width, height: self.height, channelCount: self.channelCount, colorSpace: self.colorSpace, alphaMode: self.alphaMode)
        
        for (x, y, channel, val) in self {
            other[x, y, channel: channel] = function(x, y, channel, val)
        }
        
        return other
    }

    @inlinable
    public func cropped(originX: Int, originY: Int, width: Int, height: Int, clampOutOfBounds: Bool = false) -> Image<T> {
        precondition(clampOutOfBounds || (originX >= 0 && originY >= 0))
        precondition(clampOutOfBounds || (originX + width <= self.width && originY + height <= self.height))
        
        if width == self.width, height == self.height, originX == 0, originY == 0 {
            return self
        }
        
        let result = Image<T>(width: width, height: height, channelCount: self.channelCount, colorSpace: self.colorSpace, alphaMode: self.alphaMode)
        
        for y in 0..<height {
            let clampedY = clampOutOfBounds ? clamp(y + originY, min: 0, max: self.height - 1) : (y + originY)
            for x in 0..<width {
                let clampedX = clampOutOfBounds ? clamp(x + originX, min: 0, max: self.width - 1) : (x + originX)
                for c in 0..<self.channelCount {
                    result.setUnchecked(x: x, y: y, channel: c, value: self[clampedX, clampedY, channel: c])
                }
            }
        }
        
        return result
    }
  
    @inlinable
    public func resized(width: Int, height: Int, horizontalWrapMode: ImageEdgeWrapMode, verticalWrapMode: ImageEdgeWrapMode, horizontalFilter: ImageResizeFilter = .default, verticalFilter: ImageResizeFilter = .default) -> Image<T> {
        if width == self.width && height == self.height {
            return self
        }
        
        var flags : Int32 = 0
        if self.alphaMode == .premultiplied {
            flags |= STBIR_FLAG_ALPHA_PREMULTIPLIED
        }
        
        let stbColorSpace : stbir_colorspace
        let processingColorSpace: ImageColorSpace
        
        switch self.colorSpace {
        case .sRGB:
            stbColorSpace = STBIR_COLORSPACE_SRGB
            processingColorSpace = .sRGB
        default:
            stbColorSpace = STBIR_COLORSPACE_LINEAR
            processingColorSpace = self.colorSpace.withLinearGamma
        }
        
        var sourceImage: Image<T>
        
        let dataType : stbir_datatype
        switch self {
        case let image as Image<Float>:
            dataType = STBIR_TYPE_FLOAT
            sourceImage = image.converted(toColorSpace: processingColorSpace) as! Image<T>
        case let image as Image<UInt8>:
            dataType = STBIR_TYPE_UINT8
            sourceImage = image.converted(toColorSpace: processingColorSpace) as! Image<T>
        case let image as Image<UInt16>:
            dataType = STBIR_TYPE_UINT16
            sourceImage = image.converted(toColorSpace: processingColorSpace) as! Image<T>
        case let image as Image<UInt32>:
            dataType = STBIR_TYPE_UINT32
            sourceImage = image.converted(toColorSpace: processingColorSpace) as! Image<T>
        default:
            fatalError("Unsupported Image type \(T.self) for mip chain generation.")
        }
        
        var result = Image<T>(width: width, height: height, channelCount: self.channelCount, colorSpace: self.colorSpace, alphaMode: self.alphaMode)
        
        let sourceWidth = self.width
        let sourceHeight = self.height
        let sourceStride = self.componentsPerRow * MemoryLayout<ComponentType>.stride
        let resultStride = result.componentsPerRow * MemoryLayout<ComponentType>.stride
        sourceImage.withUnsafeBufferPointer { storage in
            result.withUnsafeMutableBufferPointer { result in
                _ = stbir_resize(storage.baseAddress, Int32(sourceWidth), Int32(sourceHeight), Int32(sourceStride),
                                 result.baseAddress, Int32(width), Int32(height), Int32(resultStride),
                                 dataType,
                                 Int32(self.channelCount),
                                 self.channelCount == 4 ? 3 : -1,
                                 flags,
                                 horizontalWrapMode.stbirMode, verticalWrapMode.stbirMode,
                                 horizontalFilter.stbirFilter, verticalFilter.stbirFilter,
                                 stbColorSpace, nil)
            }
        }
        
        switch result {
        case let image as Image<Float>:
            return image.converted(toColorSpace: self.colorSpace) as! Image<T>
        case let image as Image<UInt8>:
            return image.converted(toColorSpace: self.colorSpace) as! Image<T>
        case let image as Image<UInt16>:
            return image.converted(toColorSpace: self.colorSpace) as! Image<T>
        case let image as Image<UInt32>:
            return image.converted(toColorSpace: self.colorSpace) as! Image<T>
        default:
            fatalError()
        }
    }
    
    @inlinable
    public func resized(width: Int, height: Int, wrapMode: ImageEdgeWrapMode, filter: ImageResizeFilter = .default) -> Image<T> {
        return self.resized(width: width, height: height, horizontalWrapMode: wrapMode, verticalWrapMode: wrapMode, horizontalFilter: filter, verticalFilter: filter)
    }
    
    @inlinable
    public func transposed() -> Image<ComponentType> {
        // TODO: implement more efficiently; see e.g. https://fgiesen.wordpress.com/2013/07/09/simd-transposes-1/
        
        var result = Image<ComponentType>(width: self.height, height: self.width, channelCount: self.channelCount, colorSpace: self.colorSpace, alphaModeAllowInferred: self.alphaMode, zeroStorage: false)
        
        let pixelStride = self.channelCount
        let rowStride = self.componentsPerRow
        let width = result.width
        let height = result.height
        result.withUnsafeMutableBufferPointer { result in
            let result = result.baseAddress.unsafelyUnwrapped
            self.withUnsafeBufferPointer { source in
                let source = source.baseAddress.unsafelyUnwrapped
                for y in 0..<height {
                    let destinationRow = result.advanced(by: y * rowStride)
                    for x in 0..<width {
                        destinationRow.advanced(by: x * pixelStride).initialize(from: source.advanced(by: (x * rowStride + y) * pixelStride), count: pixelStride)
                    }
                }
            }
        }
        
        return result
    }
    
    public func generateMipChain(wrapMode: ImageEdgeWrapMode, filter: ImageResizeFilter = .default, compressedBlockSize: Int, mipmapCount: Int? = nil) -> [Image<T>] {
        var results = [self]
        
        var width = self.width
        var height = self.height
        while width >= 2 && height >= 2 {
            if results.count == (mipmapCount ?? .max) {
                return results
            }
            
            width /= 2
            height /= 2
            if width % compressedBlockSize != 0 || height % compressedBlockSize != 0 {
                break
            }
            
            let nextMip = results.last!.resized(width: width, height: height, wrapMode: wrapMode)
            results.append(nextMip)
        }
        
        return results
    }
}

extension Image: Hashable {
    @inlinable
    public static func ==(lhs: Image, rhs: Image) -> Bool {
        if lhs.storage === rhs.storage {
            return true
        }
        if lhs.fileInfo != rhs.fileInfo {
            return false
        }
        return lhs.withUnsafeBufferPointer { lhs in
            return rhs.withUnsafeBufferPointer { rhs in
                return lhs.count == rhs.count && memcmp(lhs.baseAddress!, rhs.baseAddress!, lhs.count * MemoryLayout<ComponentType>.stride) == 0
            }
        }
    }
    
    @inlinable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.fileInfo)
    }
}

extension Image where ComponentType: Comparable {
    public init(width: Int, height: Int, channelCount: Int, data: UnsafeMutableBufferPointer<T>, colorSpace: ImageColorSpace = .undefined, alphaMode: ImageAlphaMode = .none, allocator: ImageAllocator) {
        precondition(width >= 1 && height >= 1 && channelCount >= 1)
        precondition(data.count >= width * height * channelCount)
        
        self.width = width
        self.height = height
        self.channelCount = channelCount
        
        self.storage = .init(data: data, allocator: allocator)
        
        self.colorSpace = colorSpace
        self.alphaMode = alphaMode
        
        self.inferAlphaMode()
    }
    
    @available(*, deprecated, renamed: "init(width:height:channelCount:data:colorSpace:alphaMode:allocator:)")
    public init(width: Int, height: Int, channels: Int, data: UnsafeMutablePointer<T>, colorSpace: ImageColorSpace = .undefined, alphaMode: ImageAlphaMode = .none, allocator: ImageAllocator) {
        self.init(width: width, height: height, channelCount: channels, data: UnsafeMutableBufferPointer<T>(start: data, count: width * height * channels), colorSpace: colorSpace, alphaMode: alphaMode, allocator: allocator)
    }

    mutating func inferAlphaMode() {
        guard case .inferred = alphaMode else { return }
        
        if self.channelCount == 2 || self.channelCount == 4 {
            let alphaChannel = self.channelCount - 1
            for baseIndex in stride(from: 0, to: self.elementCount, by: self.channelCount) {
                let alphaVal = self.storage.data[baseIndex + alphaChannel]
                for c in 0..<alphaChannel {
                    if self.storage.data[baseIndex + c] > alphaVal {
                        self.alphaMode = .postmultiplied
                        return
                    }
                }
            }
            self.alphaMode = .premultiplied
        } else {
            self.alphaMode = .none
        }
    }
}

extension Image where ComponentType: SIMDScalar {
    @inlinable
    public subscript(x: Int, y: Int) -> SIMD4<ComponentType> {
        @inline(__always) get {
            precondition(x >= 0 && y >= 0 && x < self.width && y < self.height)
            precondition(self.width * self.height * self.channelCount < Int.max)
            
            let storage = self.storage.data.baseAddress.unsafelyUnwrapped
            
            var result = SIMD4<ComponentType>()
            if self.channelCount != 4, let alphaChannelIndex = self.alphaChannelIndex {
                for i in 0..<Swift.min(alphaChannelIndex, 3) {
                    result[i] = storage[y &* self.componentsPerRow &+ x &* self.channelCount &+ i]
                }
                result[3] = storage[y &* self.componentsPerRow &+ x &* self.channelCount &+ alphaChannelIndex]
            } else {
                for i in 0..<Swift.min(self.channelCount, 4) {
                    result[i] = storage[y &* self.componentsPerRow &+ x &* self.channelCount &+ i]
                }
            }
            return result
        }
        @inline(__always) set {
            precondition(x >= 0 && y >= 0 && x < self.width && y < self.height)
            precondition(self.width * self.height * self.channelCount < Int.max)
            
            self.ensureUniqueness()
            
            let storage = self.storage.data.baseAddress.unsafelyUnwrapped
            
            if self.channelCount != 4, let alphaChannelIndex = self.alphaChannelIndex {
                for i in 0..<Swift.min(alphaChannelIndex, 3) {
                    storage[y &* self.componentsPerRow &+ x &* self.channelCount &+ i] = newValue[i]
                }
                storage[y &* self.width &* self.channelCount &+ x &* self.channelCount &+ alphaChannelIndex] = newValue.w
            } else {
                for i in 0..<Swift.min(self.channelCount, 4) {
                    storage[y &* self.componentsPerRow &+ x &* self.channelCount &+ i] = newValue[i]
                }
            }
        }
    }
    
    public struct PixelView: Collection {
        @usableFromInline var image: Image
        
        public typealias Index = Image.Index
        
        @inlinable
        init(image: Image) {
            self.image = image
        }
        
        @inlinable
        public subscript(position: Index) -> (x: Int, y: Int, value: SIMD4<ComponentType>) {
            @inline(__always) get {
                let channelCount = self.image.channelCount
                let alphaChannelIndex = self.image.alphaChannelIndex
                
                let pixelIndex = position.offset / channelCount
                let (y, x) = pixelIndex.quotientAndRemainder(dividingBy: self.image.width)
                
                return self.image.withUnsafeBufferPointer { imageBuffer in
                    var result = SIMD4<T>()
                    if channelCount != 4, let alphaChannelIndex = alphaChannelIndex {
                        for i in 0..<Swift.min(alphaChannelIndex, 3) {
                            result[i] = imageBuffer[position.offset &+ i]
                        }
                        result[3] = imageBuffer[position.offset &+ alphaChannelIndex]
                    } else {
                        for i in 0..<Swift.min(channelCount, 4) {
                            result[i] = imageBuffer[position.offset &+ i]
                        }
                    }
                    return (x, y, result)
                }
            }
            @inline(__always) set {
                let channelCount = self.image.channelCount
                let alphaChannelIndex = self.image.alphaChannelIndex
                
                let pixelIndex = position.offset / channelCount
                let (y, x) = pixelIndex.quotientAndRemainder(dividingBy: self.image.width)
                precondition(newValue.x == x && newValue.y == y)
                
                self.image.withUnsafeMutableBufferPointer { imageBuffer in
                    if channelCount != 4, let alphaChannelIndex = alphaChannelIndex {
                        for i in 0..<Swift.min(alphaChannelIndex, 3) {
                            imageBuffer[position.offset &+ i] = newValue.value[i]
                        }
                        imageBuffer[position.offset &+ alphaChannelIndex] = newValue.value.w
                    } else {
                        for i in 0..<Swift.min(channelCount, 4) {
                            imageBuffer[position.offset &+ i] = newValue.value[i]
                        }
                    }
                }
            }
        }
        
        @inlinable
        public subscript(x: Int, y: Int) -> SIMD4<ComponentType> {
            @inline(__always) get {
                return self.image[x, y]
            }
            @inline(__always) set {
                self.image[x, y] = newValue
            }
        }
        
        @inlinable
        public var count: Int {
            return self.image.width * self.image.height
        }
        
        @inlinable
        public var startIndex: Index {
            return .init(offset: 0)
        }
        
        @inlinable
        public var endIndex: Index {
            return .init(offset: self.image.width * self.image.height * self.image.channelCount)
        }
        
        @inlinable
        public func index(after i: Index) -> Index {
            return .init(offset: i.offset + self.image.channelCount)
        }
    }
    
    @inlinable
    public var pixels: PixelView {
        get {
            return PixelView(image: self)
        }
        set {
            self = newValue.image
        }
        _modify {
            var pixelView = PixelView(image: self)
            self.storage = .init(data: .init(start: nil, count: 0), allocator: .temporaryBuffer)
            yield &pixelView
            self = pixelView.image
        }
    }
    
    @inlinable
    public func mapPixels<Other: SIMDScalar>(_ function: (_ x: Int, _ y: Int, _ pixel: SIMD4<ComponentType>) -> SIMD4<Other>) -> Image<Other> {
        var other = Image<Other>(width: self.width, height: self.height, channelCount: self.channelCount, colorSpace: self.colorSpace, alphaMode: self.alphaMode)
         
        for (x, y, val) in self.pixels {
            other[x, y] = function(x, y, val)
        }
        
        return other
    }
}

extension Image: Collection {
    public struct Index: Equatable, Comparable {
        @usableFromInline var offset: Int
        
        @inlinable
        init(x: Int, y: Int, image: Image) {
            precondition((0..<image.width).contains(x) && (0..<image.height).contains(y))
            self.offset = image.componentsPerRow * y + image.channelCount * x
        }
        
        @inlinable
        init(x: Int, y: Int, channel: Int, image: Image) {
            precondition((0..<image.width).contains(x) && (0..<image.height).contains(y) && (0..<image.channelCount).contains(channel))
            self.offset = image.componentsPerRow * y + image.channelCount * x
        }
        
        @inlinable
        init(offset: Int) {
            self.offset = offset
        }
        
        @inlinable
        public static func ==(lhs: Index, rhs: Index) -> Bool {
            return lhs.offset == rhs.offset
        }
        
        @inlinable
        public static func <(lhs: Index, rhs: Index) -> Bool {
            return lhs.offset < rhs.offset
        }
    }
        
    @inlinable
    public subscript(position: Index) -> (x: Int, y: Int, channel: Int, value: ComponentType) {
        @inline(__always) get {
            let channelCount = self.channelCount
            
            let (pixelIndex, channelIndex) = position.offset.quotientAndRemainder(dividingBy: channelCount)
            let (y, x) = pixelIndex.quotientAndRemainder(dividingBy: self.componentsPerRow)
            
            return self.withUnsafeBufferPointer { imageBuffer in
                return (x, y, channelIndex, imageBuffer[position.offset])
            }
        }
    }
        
    @inlinable
    public var count: Int {
        return self.width * self.height * self.channelCount
    }
    
    @inlinable
    public var startIndex: Index {
        return .init(offset: 0)
    }
    
    @inlinable
    public var endIndex: Index {
        return .init(offset: self.height * self.componentsPerRow)
    }
    
    @inlinable
    public func index(after i: Index) -> Index {
        return .init(offset: i.offset + 1) // FIXME: componentsPerRow/row stride
    }
}

extension Image where ComponentType == UInt8 {
    private func _applyUnchecked(_ function: (UInt8) -> UInt8, channelRange: Range<Int>) {
        for y in 0..<self.height {
            let yBase = y * self.componentsPerRow
            for x in 0..<self.width {
                let baseIndex = yBase + x * self.channelCount
                for c in channelRange {
                    self.storage.data[baseIndex + c] = function(self.storage.data[baseIndex + c])
                }
            }
        }
    }
    
    private func _convertSRGBToLinear() {
        self._applyUnchecked({ ColorSpaceLUTs.sRGBToLinear($0) }, channelRange: self.alphaMode != .none ? (0..<self.channelCount - 1) : 0..<self.channelCount)
    }
    
    private func _convertLinearToSRGB() {
        self._applyUnchecked({ ColorSpaceLUTs.linearToSRGB($0) }, channelRange: self.alphaMode != .none ? (0..<self.channelCount - 1) : 0..<self.channelCount)
    }
    
    private func _convertWithAlpha(using lut: UnsafeBufferPointer<UInt8>) {
        let buffer = UnsafeMutableBufferPointer(rebasing: self.storage.data.prefix(self.elementCount))
        if self.channelCount == 4 {
            let simdBuffer = UnsafeMutableRawBufferPointer(buffer).bindMemory(to: SIMD4<UInt8>.self) // FIXME: componentsPerRow/row stride
            for i in 0..<simdBuffer.count {
                let sourcePixels = simdBuffer[i]
                let alpha = sourcePixels.w
                let alphaLut = lut.baseAddress.unsafelyUnwrapped.advanced(by: Int(alpha) &* 256)
                
                simdBuffer[i] = SIMD4(
                    alphaLut[Int(sourcePixels.x)],
                    alphaLut[Int(sourcePixels.y)],
                    alphaLut[Int(sourcePixels.z)],
                    alpha
                )
            }
            _ = UnsafeMutableRawBufferPointer(simdBuffer).bindMemory(to: UInt8.self)
        } else {
            let alphaChannel = self.channelCount - 1
            for pixelBase in stride(from: 0, to: buffer.count, by: self.channelCount) {
                let alpha = buffer[pixelBase + alphaChannel]
                for c in 0..<alphaChannel {
                    let lutIndex = Int(alpha) &* 256 &+ Int(buffer[pixelBase + c])
                    buffer[pixelBase + c] = lut[lutIndex]
                }
            }
        }
    }
    
    private func _convertSRGBPostmultipliedToPremultiplied() {
        ColorSpaceLUTs.sRGBPostmultToPremultAlphaLUT.withUnsafeBufferPointer {
            self._convertWithAlpha(using: $0)
        }
    }
    
    private func _convertLinearPostmultipliedToPremultiplied() {
        ColorSpaceLUTs.postmultToPremultAlphaLUT.withUnsafeBufferPointer {
            self._convertWithAlpha(using: $0)
        }
    }
    
    private func _convertSRGBPremultipliedToPostmultiplied() {
        ColorSpaceLUTs.sRGBPremultToPostmultAlphaLUT.withUnsafeBufferPointer {
            self._convertWithAlpha(using: $0)
        }
    }
    
    private func _convertLinearPremultipliedToPostmultiplied() {
        ColorSpaceLUTs.postmultToPremultAlphaLUT.withUnsafeBufferPointer {
            self._convertWithAlpha(using: $0)
        }
    }
}

extension Image where ComponentType: BinaryInteger & FixedWidthInteger & UnsignedInteger {
    @inlinable
    public init(_ data: Image<Float>) {
        self.init(width: data.width, height: data.height, channelCount: data.channelCount, colorSpace: data.colorSpace, alphaMode: data.alphaMode)
        
        self.withUnsafeMutableBufferPointer { dest in
            data.withUnsafeBufferPointer { source in
                for (i, sourceVal) in source.enumerated() {
                    dest[i] = floatToUnorm(sourceVal, type: T.self) // FIXME: componentsPerRow/row stride
                }
            }
        }
    }
    
    @_specialize(kind: full, where ComponentType == UInt8)
    @_specialize(kind: full, where ComponentType == UInt16)
    public mutating func convertToPremultipliedAlpha() {
        guard case .postmultiplied = self.alphaMode else { return }
        self.ensureUniqueness()
        
        defer { self.alphaMode = .premultiplied }
        
        if T.self == UInt8.self {
            if self.colorSpace == .sRGB {
                (self as! Image<UInt8>)._convertSRGBPostmultipliedToPremultiplied()
                return
            } else if self.colorSpace == .linearSRGB || self.colorSpace == .undefined {
                (self as! Image<UInt8>)._convertLinearPostmultipliedToPremultiplied()
                return
            }
        }
        
        let sourceColorSpace = self.colorSpace
        
        let alphaChannel = self.channelCount - 1
        for y in 0..<self.height {
            for x in 0..<self.width {
                let alpha = unormToFloat(self[x, y, channel: alphaChannel])
                for c in 0..<alphaChannel {
                    let floatVal = unormToFloat(self[x, y, channel: c])
                    let linearVal = ImageColorSpace.convert(floatVal, from: sourceColorSpace, to: .linearSRGB) * alpha
                    self.setUnchecked(x: x, y: y, channel: c, value: floatToUnorm(ImageColorSpace.convert(linearVal, from: .linearSRGB, to: sourceColorSpace), type: T.self))
                }
            }
        }
    }
    
    @_specialize(kind: full, where ComponentType == UInt8)
    @_specialize(kind: full, where ComponentType == UInt16)
    @_specialize(kind: full, where ComponentType == UInt32)
    public mutating func convertToPostmultipliedAlpha() {
        guard case .premultiplied = self.alphaMode else { return }
        self.ensureUniqueness()
        defer { self.alphaMode = .postmultiplied }
        
        if T.self == UInt8.self {
            if self.colorSpace == .sRGB {
                (self as! Image<UInt8>)._convertSRGBPremultipliedToPostmultiplied()
                return
            } else if self.colorSpace == .linearSRGB || self.colorSpace == .undefined {
                (self as! Image<UInt8>)._convertLinearPremultipliedToPostmultiplied()
                return
            }
        }
        
        let sourceColorSpace = self.colorSpace
        let alphaChannel = self.channelCount - 1
        
        for y in 0..<self.height {
            for x in 0..<self.width {
                let alpha = unormToFloat(self[x, y, channel: alphaChannel])
                for c in 0..<alphaChannel {
                    let floatVal = unormToFloat(self[x, y, channel: c])
                    let linearVal = clamp(ImageColorSpace.convert(floatVal, from: sourceColorSpace, to: .linearSRGB) / alpha, min: 0.0, max: 1.0)
                    self.setUnchecked(x: x, y: y, channel: c, value: floatToUnorm(ImageColorSpace.convert(linearVal, from: .linearSRGB, to: sourceColorSpace), type: T.self))
                }
            }
        }
    }
}

extension Image where ComponentType: BinaryInteger & FixedWidthInteger & UnsignedInteger & SIMDScalar {
    
    @inlinable
    public func converted(toColorSpace: ImageColorSpace) -> Self {
        var result = self
        result.convert(toColorSpace: toColorSpace)
        return result
    }
    
    @_specialize(kind: full, where ComponentType == UInt8)
    @_specialize(kind: full, where ComponentType == UInt16)
    public mutating func convert(toColorSpace: ImageColorSpace) {
        if toColorSpace == self.colorSpace || self.colorSpace == .undefined {
            return
        }
        defer { self.colorSpace = toColorSpace }
        
        if toColorSpace == .undefined { return }
        
        if T.self == UInt8.self {
            self.ensureUniqueness()
            if self.colorSpace == .sRGB, toColorSpace == .linearSRGB {
                (self as! Image<UInt8>)._convertSRGBToLinear()
                return
            } else if self.colorSpace == .linearSRGB, toColorSpace == .sRGB {
                (self as! Image<UInt8>)._convertLinearToSRGB()
                return
            }
        }
        
        let sourceColorSpace = self.colorSpace
        let channelRange = self.alphaMode != .none ? (0..<self.channelCount - 1) : 0..<self.channelCount
        
        if channelRange.count < 3 || (sourceColorSpace.usesSRGBPrimaries && toColorSpace.usesSRGBPrimaries) {
            // Gamma correction only.
            self.apply(channelRange: channelRange) { floatToUnorm(ImageColorSpace.convert(unormToFloat($0), from: sourceColorSpace, to: toColorSpace), type: T.self) }
        } else if let fromCIE = sourceColorSpace.cieSpace, let toCIE = toColorSpace.cieSpace {
            let conversionContext = CIEXYZ1931ColorSpace.conversionContext(convertingFrom: fromCIE, to: toCIE)
            let channelCount = self.channelCount
            
            if channelCount == 3 {
                self.withUnsafeMutableBufferPointer { contents in
                    for offset in stride(from: 0, to: contents.count, by: channelCount) {
                        let source = SIMD3<ComponentType>(contents[offset + 0], contents[offset + 1], contents[offset + 2])
                        let asFloat = unormToFloat(source)
                        let converted = SIMD3<Float>(conversionContext.convert(RGBColor(asFloat)))
                        let encoded = floatToUnorm(converted, type: ComponentType.self)
                        contents[offset + 0] = encoded.x
                        contents[offset + 1] = encoded.y
                        contents[offset + 2] = encoded.z
                    }
                }
            } else {
                self.withUnsafeMutableBufferPointer { contents in
                    contents.withMemoryRebound(to: SIMD4<ComponentType>.self) { contents in
                        for i in contents.indices {
                            let source = contents[i]
                            let asFloat = unormToFloat(source)
                            let converted = SIMD3<Float>(conversionContext.convert(RGBColor(asFloat.xyz)))
                            let encoded = SIMD4<ComponentType>(floatToUnorm(converted, type: ComponentType.self), source.w)
                            contents[i] = encoded
                        }
                    }
                }
            }
        }
    }
}

public protocol _ImageNormalizedComponent {
    associatedtype _ImageUnnormalizedType: BinaryFloatingPoint & SIMDScalar
    init(_imageNormalizingFloat: _ImageUnnormalizedType)
    func _imageNormalizedComponentToFloat() -> _ImageUnnormalizedType
}

extension UInt8: _ImageNormalizedComponent {
    public typealias _ImageUnnormalizedType = Float
    
    @inlinable
    public init(_imageNormalizingFloat float: Float) {
        self = floatToUnorm(float, type: UInt8.self)
    }
    
    @inlinable
    public func _imageNormalizedComponentToFloat() -> Float {
        return unormToFloat(self)
    }
}

extension UInt16: _ImageNormalizedComponent {
    public typealias _ImageUnnormalizedType = Float
    
    @inlinable
    public init(_imageNormalizingFloat float: Float) {
        self = floatToUnorm(float, type: UInt16.self)
    }
    
    @inlinable
    public func _imageNormalizedComponentToFloat() -> Float {
        return unormToFloat(self)
    }
}

extension Float: _ImageNormalizedComponent {
    public typealias _ImageUnnormalizedType = Float
    
    @inlinable
    public init(_imageNormalizingFloat float: Float) {
        self = float
    }
    
    @inlinable
    public func _imageNormalizedComponentToFloat() -> Float {
        return self
    }
}

extension Double: _ImageNormalizedComponent {
    public typealias _ImageUnnormalizedType = Double
    
    @inlinable
    public init(_imageNormalizingFloat float: Double) {
        self = float
    }
    
    @inlinable
    public func _imageNormalizedComponentToFloat() -> Double {
        return self
    }
}

public enum ImageSamplingFilter {
    case bilinear
    case bicubic
}

extension Image where ComponentType: _ImageNormalizedComponent & SIMDScalar {
    @inlinable
    public subscript(floatVectorAt x: Int, _ y: Int) -> SIMD4<ComponentType._ImageUnnormalizedType> {
        @inline(__always) get {
            let value = self[x, y]
            return SIMD4(value.x._imageNormalizedComponentToFloat(),
                         value.y._imageNormalizedComponentToFloat(),
                         value.z._imageNormalizedComponentToFloat(),
                         value.w._imageNormalizedComponentToFloat())
        }
        @inline(__always) set {
            self[x, y] = SIMD4(ComponentType(_imageNormalizingFloat: newValue.x),
                               ComponentType(_imageNormalizingFloat: newValue.y),
                               ComponentType(_imageNormalizingFloat: newValue.z),
                               ComponentType(_imageNormalizingFloat: newValue.w))
        }
    }
    
    @inlinable
    public func computeWrappedCoordinate(x: Int, y: Int, wrapMode: ImageEdgeWrapMode = .wrap) -> SIMD2<Int>? {
        var coord = SIMD2<Int>(x, y)
        
        let size = SIMD2(self.width, self.height)
        let maxCoord = size &- 1
        
        switch wrapMode {
        case .zero:
            break
        case .wrap:
            coord = coord % size
            coord.replace(with: coord &+ size, where: coord .< .zero)
        case .reflect:
            coord = coord % (2 &* size)
            coord.replace(with: coord &+ (2 &* size), where: coord .< .zero)
            coord.replace(with: 2 &* size &- coord, where: coord .> maxCoord)
        case .clamp:
            coord = pointwiseMax(pointwiseMin(coord, maxCoord), .zero)
        }
        
        if wrapMode == .zero, any(coord .< SIMD2<Int>.zero .| coord .> maxCoord) { return nil }
        return coord
    }
    
    @inlinable
    func computeWrappedCoordinate(coord: Int, size: Int, wrapMode: ImageEdgeWrapMode = .wrap) -> Int? {
        var coord = coord
        let maxCoord = size &- 1
        
        switch wrapMode {
        case .zero:
            break
        case .wrap:
            coord = coord % size
            if coord < 0 { coord &+= size }
        case .reflect:
            coord = coord % (2 &* size)
            if coord < 0 { coord &+= 2 &* size }
            if coord > maxCoord { coord = 2 &* size &- coord }
        case .clamp:
            coord = Swift.max(Swift.min(coord, maxCoord), 0)
        }
        
        if wrapMode == .zero, coord < 0 || coord > maxCoord { return nil }
        return coord
    }
    
    @inlinable
    func applyWrapMode(_ wrapMode: ImageEdgeWrapMode, floorCoord: SIMD2<Int>, ceilCoord: SIMD2<Int>, size: SIMD2<Int>) -> (floorCoord: SIMD2<Int>, ceilCoord: SIMD2<Int>) {
        var floorCoord = floorCoord
        var ceilCoord = ceilCoord
        switch wrapMode {
        case .zero:
            break
        case .wrap:
            floorCoord = floorCoord % size
            ceilCoord = ceilCoord % size
            floorCoord.replace(with: floorCoord &+ size, where: floorCoord .< .zero)
            ceilCoord.replace(with: ceilCoord &+ size, where: ceilCoord .< .zero)
        case .reflect:
            floorCoord = floorCoord % (2 &* size)
            ceilCoord = ceilCoord % (2 &* size)
            
            floorCoord.replace(with: floorCoord &+ (2 &* size), where: floorCoord .< .zero)
            ceilCoord.replace(with: ceilCoord &+ (2 &* size), where: ceilCoord .< .zero)
            
            floorCoord.replace(with: 2 &* size &- floorCoord, where: floorCoord .>= size)
            ceilCoord.replace(with: 2 &* size &- ceilCoord, where: ceilCoord .>= size)
            
        case .clamp:
            floorCoord = pointwiseMax(pointwiseMin(floorCoord, size &- .one), .zero)
            ceilCoord = pointwiseMax(pointwiseMin(ceilCoord, size &- .one), .zero)
        }
        
        return (floorCoord, ceilCoord)
    }
    
    @_specialize(kind: partial, where T == Float)
    @inlinable @inline(__always)
    func sampleBilinear<T: BinaryFloatingPoint, Result>(pixelCoordinate: SIMD2<T>, horizontalWrapMode: ImageEdgeWrapMode, verticalWrapMode: ImageEdgeWrapMode, readPixel: (_ x: Int, _ y: Int, _ horizontalWrapMode: ImageEdgeWrapMode, _ verticalWrapMode: ImageEdgeWrapMode) -> Result, multiply: (Result, ComponentType._ImageUnnormalizedType) -> Result, add: (Result, Result) -> Result) -> Result {
        let pixelCoordinate = pixelCoordinate - SIMD2(repeating: T(0.5)) // remove half-texel offset.
        let unwrappedFloorCoordT = pixelCoordinate.rounded(.down)
        let unwrappedFloorCoord = SIMD2<Int>(Int(unwrappedFloorCoordT.x), Int(unwrappedFloorCoordT.y)) // manually converting each element produces better assembly.
        let unwrappedCeilCoord = unwrappedFloorCoord &+ .one
        let lerpX = ComponentType._ImageUnnormalizedType(pixelCoordinate.x - unwrappedFloorCoordT.x)
        let lerpY = ComponentType._ImageUnnormalizedType(pixelCoordinate.y - unwrappedFloorCoordT.y)
        
        let size = SIMD2(self.width, self.height)
        
        var (floorCoord, ceilCoord) = applyWrapMode(horizontalWrapMode, floorCoord: unwrappedFloorCoord, ceilCoord: unwrappedCeilCoord, size: size)
        
        if horizontalWrapMode != verticalWrapMode {
            let (vFloorCoord, vCeilCoord) = applyWrapMode(verticalWrapMode, floorCoord: unwrappedFloorCoord, ceilCoord: unwrappedCeilCoord, size: size)
            floorCoord.y = vFloorCoord.y
            ceilCoord.y = vCeilCoord.y
        }
        
        let a = readPixel(floorCoord.x, floorCoord.y, horizontalWrapMode, verticalWrapMode)
        let b = readPixel(ceilCoord.x, floorCoord.y, horizontalWrapMode, verticalWrapMode)
        let c = readPixel(floorCoord.x, ceilCoord.y, horizontalWrapMode, verticalWrapMode)
        let d = readPixel(ceilCoord.x, ceilCoord.y, horizontalWrapMode, verticalWrapMode)
        
        let top = add(multiply(a, 1.0 - lerpX), multiply(b, lerpX))
        let bottom = add(multiply(c, 1.0 - lerpX), multiply(d, lerpX))
        return add(multiply(top, 1.0 - lerpY), multiply(bottom, lerpY))
    }
    
    // Source: https://pastebin.com/raw/YLLSBRFq, from comments of http://vec3.ca/bicubic-filtering-in-fewer-taps/
    @_specialize(kind: partial, where T == Float)
    @inlinable @inline(__always)
    func sampleBicubic<T: BinaryFloatingPoint, Result>(pixelCoordinate: SIMD2<T>, horizontalWrapMode: ImageEdgeWrapMode, verticalWrapMode: ImageEdgeWrapMode, readPixel: (_ x: Int, _ y: Int, _ horizontalWrapMode: ImageEdgeWrapMode, _ verticalWrapMode: ImageEdgeWrapMode) -> Result, multiply: (Result, ComponentType._ImageUnnormalizedType) -> Result, add: (Result, Result) -> Result) -> Result {

        let texelCenter = pixelCoordinate.rounded(.down) + SIMD2(repeating: 0.5)
        let fracOffset    = pixelCoordinate - texelCenter
        let fracOffset_x2 = fracOffset * fracOffset
        let fracOffset_x3 = fracOffset * fracOffset_x2
        
        //--------------------------------------------------------------------------------------
        // Calculate the filter weights (B-Spline Weighting Function)
        
        let weight0 = fracOffset_x2 - 0.5 * (fracOffset_x3 + fracOffset)
        let weight1 = 1.5 * fracOffset_x3 - 2.5 * fracOffset_x2 + SIMD2.one
        let weight3 = 0.5 * (fracOffset_x3 - fracOffset_x2)
        let weight2 = 1.0 - weight0 - weight1 - weight3
        
        //--------------------------------------------------------------------------------------
        // Calculate the texture coordinates
        
        let scalingFactor0 = weight0 + weight1
        let scalingFactor1 = weight2 + weight3
        
        let f0 = (weight1 / scalingFactor0).replacing(with: .zero, where: scalingFactor0 .== .zero)
        let f1 = (weight3 / scalingFactor1).replacing(with: .zero, where: scalingFactor1 .== .zero)
        
        let texCoord0 = texelCenter - SIMD2.one + f0
        let texCoord1 = texelCenter + SIMD2.one + f1
        
        //--------------------------------------------------------------------------------------
        // Sample the texture
        
        let xy = self.sampleBilinear(pixelCoordinate: texCoord0, horizontalWrapMode: horizontalWrapMode, verticalWrapMode: verticalWrapMode, readPixel: readPixel, multiply: multiply, add: add)
        let Xy = self.sampleBilinear(pixelCoordinate: SIMD2(texCoord1.x, texCoord0.y), horizontalWrapMode: horizontalWrapMode, verticalWrapMode: verticalWrapMode, readPixel: readPixel, multiply: multiply, add: add)
        let xY = self.sampleBilinear(pixelCoordinate: SIMD2(texCoord0.x, texCoord1.y), horizontalWrapMode: horizontalWrapMode, verticalWrapMode: verticalWrapMode, readPixel: readPixel, multiply: multiply, add: add)
        let XY = self.sampleBilinear(pixelCoordinate: SIMD2(texCoord1.x, texCoord1.y), horizontalWrapMode: horizontalWrapMode, verticalWrapMode: verticalWrapMode, readPixel: readPixel, multiply: multiply, add: add)
        
        return add(
            add(multiply(xy, ComponentType._ImageUnnormalizedType(scalingFactor0.x * scalingFactor0.y)),
                multiply(Xy, ComponentType._ImageUnnormalizedType(scalingFactor1.x * scalingFactor0.y))),
            add(multiply(xY, ComponentType._ImageUnnormalizedType(scalingFactor0.x * scalingFactor1.y)),
                multiply(XY, ComponentType._ImageUnnormalizedType(scalingFactor1.x * scalingFactor1.y)))
        )
    }
    
    @_specialize(kind: partial, where T == Float)
    @inlinable @inline(__always)
    func sample<T: BinaryFloatingPoint, Result>(pixelCoordinate: SIMD2<T>, filter: ImageSamplingFilter,  horizontalWrapMode: ImageEdgeWrapMode, verticalWrapMode: ImageEdgeWrapMode, readPixel: (_ x: Int, _ y: Int, _ horizontalWrapMode: ImageEdgeWrapMode, _ verticalWrapMode: ImageEdgeWrapMode) -> Result, multiply: (Result, ComponentType._ImageUnnormalizedType) -> Result, add: (Result, Result) -> Result) -> Result {
        switch filter {
        case .bilinear:
            return self.sampleBilinear(pixelCoordinate: pixelCoordinate, horizontalWrapMode: horizontalWrapMode, verticalWrapMode: verticalWrapMode, readPixel: readPixel, multiply: multiply, add: add)
        case .bicubic:
            return self.sampleBicubic(pixelCoordinate: pixelCoordinate, horizontalWrapMode: horizontalWrapMode, verticalWrapMode: verticalWrapMode, readPixel: readPixel, multiply: multiply, add: add)
        }
    }
    
    @_specialize(kind: partial, where T == Float)
    @inlinable
    public func sample<T: BinaryFloatingPoint>(pixelCoordinate: SIMD2<T>, channel: Int, filter: ImageSamplingFilter = .bilinear, horizontalWrapMode: ImageEdgeWrapMode = .wrap, verticalWrapMode: ImageEdgeWrapMode = .wrap) -> ComponentType._ImageUnnormalizedType {
        return self.sample(pixelCoordinate: pixelCoordinate, filter: filter, horizontalWrapMode: horizontalWrapMode, verticalWrapMode: verticalWrapMode, readPixel: { x, y, horizontalWrapMode, verticalWrapMode in
            if horizontalWrapMode == .zero, x < 0 || x >= self.width { return .zero }
            if verticalWrapMode == .zero, y < 0 || y >= self.height { return .zero }
            return self[x, y, channel: channel]._imageNormalizedComponentToFloat()
        }, multiply: *, add: +)
    }
    
    @_specialize(kind: partial, where T == Float)
    @inlinable
    public func sample<T: BinaryFloatingPoint>(pixelCoordinate: SIMD2<T>, filter: ImageSamplingFilter = .bilinear, horizontalWrapMode: ImageEdgeWrapMode = .wrap, verticalWrapMode: ImageEdgeWrapMode = .wrap) -> SIMD4<ComponentType._ImageUnnormalizedType> {
        return self.sample(pixelCoordinate: pixelCoordinate, filter: filter, horizontalWrapMode: horizontalWrapMode, verticalWrapMode: verticalWrapMode, readPixel: { x, y, horizontalWrapMode, verticalWrapMode in
            if horizontalWrapMode == .zero, x < 0 || x >= self.width { return .zero }
            if verticalWrapMode == .zero, y < 0 || y >= self.height { return .zero }
            return self[floatVectorAt: x, y]
        }, multiply: *, add: +)
    }
    
    @inlinable
    public func sample<T: BinaryFloatingPoint>(pixelCoordinate: SIMD2<T>, channel: Int, filter: ImageSamplingFilter = .bilinear, wrapMode: ImageEdgeWrapMode = .wrap) -> ComponentType._ImageUnnormalizedType {
        return self.sample(pixelCoordinate: pixelCoordinate, channel: channel, filter: filter, horizontalWrapMode: wrapMode, verticalWrapMode: wrapMode)
    }
    
    @inlinable
    public func sample<T: BinaryFloatingPoint>(pixelCoordinate: SIMD2<T>, filter: ImageSamplingFilter = .bilinear, wrapMode: ImageEdgeWrapMode = .wrap) -> SIMD4<ComponentType._ImageUnnormalizedType> {
        return self.sample(pixelCoordinate: pixelCoordinate, filter: filter, horizontalWrapMode: wrapMode, verticalWrapMode: wrapMode)
    }
    
    @inlinable
    public func sample<T: BinaryFloatingPoint>(coordinate: SIMD2<T>, channel: Int, filter: ImageSamplingFilter = .bilinear, horizontalWrapMode: ImageEdgeWrapMode = .wrap, verticalWrapMode: ImageEdgeWrapMode = .wrap) -> ComponentType._ImageUnnormalizedType {
        return self.sample(pixelCoordinate: coordinate * SIMD2(T(self.width), T(self.height)), channel: channel, filter: filter, horizontalWrapMode: horizontalWrapMode, verticalWrapMode: verticalWrapMode)
    }
    
    @inlinable
    public func sample<T: BinaryFloatingPoint>(coordinate: SIMD2<T>, channel: Int, filter: ImageSamplingFilter = .bilinear, wrapMode: ImageEdgeWrapMode = .wrap) -> ComponentType._ImageUnnormalizedType {
        return self.sample(pixelCoordinate: coordinate * SIMD2(T(self.width), T(self.height)), channel: channel, filter: filter, horizontalWrapMode: wrapMode, verticalWrapMode: wrapMode)
    }
    
    @inlinable
    public func sample<T: BinaryFloatingPoint>(coordinate: SIMD2<T>, filter: ImageSamplingFilter = .bilinear, horizontalWrapMode: ImageEdgeWrapMode = .wrap, verticalWrapMode: ImageEdgeWrapMode = .wrap) -> SIMD4<ComponentType._ImageUnnormalizedType> {
        return self.sample(pixelCoordinate: coordinate * SIMD2(T(self.width), T(self.height)), filter: filter, horizontalWrapMode: horizontalWrapMode, verticalWrapMode: verticalWrapMode)
    }
    
    @inlinable
    public func sample<T: BinaryFloatingPoint>(coordinate: SIMD2<T>, filter: ImageSamplingFilter = .bilinear, wrapMode: ImageEdgeWrapMode = .wrap) -> SIMD4<ComponentType._ImageUnnormalizedType> {
        return self.sample(pixelCoordinate: coordinate * SIMD2(T(self.width), T(self.height)), filter: filter, wrapMode: wrapMode)
    }
    
    @inlinable
    public mutating func applyLevels(inputRangeStart: SIMD4<ComponentType._ImageUnnormalizedType> = .zero,
                                     inputRangeEnd: SIMD4<ComponentType._ImageUnnormalizedType> = .one,
                                     gamma: SIMD4<ComponentType._ImageUnnormalizedType> = .one,
                                     outputRangeStart: SIMD4<ComponentType._ImageUnnormalizedType> = .zero,
                                     outputRangeEnd: SIMD4<ComponentType._ImageUnnormalizedType> = .one) where ComponentType._ImageUnnormalizedType: Real {
        let inputRangeScale = SIMD4.one / (inputRangeEnd - inputRangeStart)
        let inputRangeOffset = -inputRangeStart / (inputRangeEnd - inputRangeStart)
        
        let outputRangeScale = outputRangeEnd - outputRangeStart
        let outputRangeOffset = outputRangeStart
    
        if gamma == .one {
            // ((x * inputScale) + inputOffset) * outputScale + outputOffset
            // (x * inputScale * outputScale + inputOffset * outputScale + outputOffset
            let scale = inputRangeScale * outputRangeScale
            let offset = inputRangeOffset * outputRangeScale + outputRangeOffset
            
            if scale == .one, offset == .zero {
                return
            }
            
            for y in 0..<self.height {
                for x in 0..<self.width {
                    self[floatVectorAt: x, y] = self[floatVectorAt: x, y] * scale + offset
                }
            }
        } else {
            let invGamma = SIMD4<ComponentType._ImageUnnormalizedType>.one / gamma
            
            for y in 0..<self.height {
                for x in 0..<self.width {
                    var scaled = self[floatVectorAt: x, y] * inputRangeScale + inputRangeOffset
                    for i in 0..<4 {
                        scaled[i] = ComponentType._ImageUnnormalizedType.pow(scaled[i], invGamma[i])
                    }
                    self[floatVectorAt: x, y] = scaled * outputRangeScale + outputRangeOffset
                }
            }
        }
    }
}

extension Image where ComponentType: _ImageNormalizedComponent, ComponentType._ImageUnnormalizedType: Real {
    @inlinable
    public mutating func applyLevels(inputRangeStart: ComponentType._ImageUnnormalizedType = 0.0,
                                     inputRangeEnd: ComponentType._ImageUnnormalizedType = 1.0,
                                     gamma: ComponentType._ImageUnnormalizedType = 1.0,
                                     outputRangeStart: ComponentType._ImageUnnormalizedType = 0.0,
                                     outputRangeEnd: ComponentType._ImageUnnormalizedType = 1.0) {
        self.applyLevels(inputRangeStart: inputRangeStart, inputRangeEnd: inputRangeEnd, gamma: gamma, outputRangeStart: outputRangeStart, outputRangeEnd: outputRangeEnd, channelRange: 0..<self.channelCount)
    }
    
    @inlinable
    public mutating func applyLevels(inputRangeStart: ComponentType._ImageUnnormalizedType = 0.0,
                                     inputRangeEnd: ComponentType._ImageUnnormalizedType = 1.0,
                                     gamma: ComponentType._ImageUnnormalizedType = 1.0,
                                     outputRangeStart: ComponentType._ImageUnnormalizedType = 0.0,
                                     outputRangeEnd: ComponentType._ImageUnnormalizedType = 1.0,
                                     channelRange: Range<Int>) {
        let inputRangeScale = 1.0 / (inputRangeEnd - inputRangeStart)
        let inputRangeOffset = -inputRangeStart / (inputRangeEnd - inputRangeStart)
        
        let outputRangeScale = outputRangeEnd - outputRangeStart
        let outputRangeOffset = outputRangeStart
    
        if gamma == 1.0 {
            // ((x * inputScale) + inputOffset) * outputScale + outputOffset
            // (x * inputScale * outputScale + inputOffset * outputScale + outputOffset
            let scale = inputRangeScale * outputRangeScale
            let offset = inputRangeOffset * outputRangeScale + outputRangeOffset
            
            if scale == 1.0, offset == 0.0 {
                return
            }
            
            self.apply(channelRange: channelRange) { val in
                .init(_imageNormalizingFloat: val._imageNormalizedComponentToFloat() * scale + offset)
            }
        } else {
            let invGamma = 1.0 / gamma
            
            self.apply(channelRange: channelRange) { val in
                var scaled = val._imageNormalizedComponentToFloat() * inputRangeScale + inputRangeOffset
                scaled = ComponentType._ImageUnnormalizedType.pow(scaled, invGamma)
                return .init(_imageNormalizingFloat: scaled * outputRangeScale + outputRangeOffset)
            }
        }
    }
}

extension Image where ComponentType: Comparable {
    @inlinable
    public func range(forChannel channel: Int) -> ClosedRange<ComponentType> {
        var minVal = self[0, 0, channel: channel]
        var maxVal = minVal
        
        for y in 0..<self.height {
            for x in 0..<self.width {
                let value = self[x, y, channel: channel]
                minVal = Swift.min(minVal, value)
                maxVal = Swift.max(maxVal, value)
            }
        }
        return minVal...maxVal
    }
}

extension Image where ComponentType: _ImageNormalizedComponent {
    @inlinable
    public func meanAndVariance(forChannel channel: Int) -> (mean: ComponentType._ImageUnnormalizedType, variance: ComponentType._ImageUnnormalizedType, sampleVariance: ComponentType._ImageUnnormalizedType) {
        // https://en.wikipedia.org/wiki/Algorithms_for_calculating_variance
        var count = 0.0 as ComponentType._ImageUnnormalizedType
        var mean = 0.0 as ComponentType._ImageUnnormalizedType
        var mean2 = 0.0 as ComponentType._ImageUnnormalizedType
        
        for y in 0..<self.height {
            for x in 0..<self.width {
                let value = self[x, y, channel: channel]._imageNormalizedComponentToFloat()
                count += 1.0
                let delta = value - mean
                mean += delta / count
                let delta2 = value - mean
                mean2 += delta * delta2
            }
        }
        
        return (mean, mean / count, mean / (count - 1))
    }
}

extension Image where ComponentType: _ImageNormalizedComponent & SIMDScalar {
    @inlinable
    public var averageValue: SIMD4<ComponentType._ImageUnnormalizedType> {
        return self.meanAndVariance().mean
    }
    
    @inlinable
    public func meanAndVariance() -> (mean: SIMD4<ComponentType._ImageUnnormalizedType>, variance: SIMD4<ComponentType._ImageUnnormalizedType>, sampleVariance: SIMD4<ComponentType._ImageUnnormalizedType>) {
        // https://en.wikipedia.org/wiki/Algorithms_for_calculating_variance
        var count = 0.0 as ComponentType._ImageUnnormalizedType
        var mean = SIMD4<ComponentType._ImageUnnormalizedType>.zero
        var mean2 = SIMD4<ComponentType._ImageUnnormalizedType>.zero
        
        for y in 0..<self.height {
            for x in 0..<self.width {
                let value = self[floatVectorAt: x, y]
                count += 1.0
                let delta = value - mean
                mean += delta / count
                let delta2 = value - mean
                mean2 += delta * delta2
            }
        }
        
        return (mean, mean / count, mean / (count - 1))
    }
    
    
    @inlinable
    public func meanAndVariance(weightsImage: Image<ComponentType>) -> (mean: SIMD4<ComponentType._ImageUnnormalizedType>, variance: SIMD4<ComponentType._ImageUnnormalizedType>, sampleVariance: SIMD4<ComponentType._ImageUnnormalizedType>) {
        // https://en.wikipedia.org/wiki/Algorithms_for_calculating_variance
        var count = SIMD4<ComponentType._ImageUnnormalizedType>.zero
        var mean = SIMD4<ComponentType._ImageUnnormalizedType>.zero
        var mean2 = SIMD4<ComponentType._ImageUnnormalizedType>.zero
        
        for y in 0..<self.height {
            for x in 0..<self.width {
                let value = self[floatVectorAt: x, y]
                var weight = weightsImage[floatVectorAt: x, y]
                if weightsImage.channelCount == 1 {
                    weight = SIMD4(repeating: weight.x)
                }
                
                count += weight
                
                let delta = value - mean
                mean += delta * (weight / count.replacing(with: .ulpOfOne, where: weight .== .zero))
                let delta2 = value - mean
                mean2 += weight * delta * delta2
            }
        }
        
        return (mean, mean / count, mean / (count - SIMD4<ComponentType._ImageUnnormalizedType>.one))
    }
}

extension Image {
    @available(*, deprecated, renamed: "withImageReinterpreted(as:perform:)")
    @inlinable
    public func withTextureReinterpreted<U, Result>(as type: U.Type, perform: (Image<U>) throws -> Result) rethrows -> Result {
        return try self.withImageReinterpreted(as: type, perform: perform)
    }
    
    @inlinable
    public func withImageReinterpreted<U, Result>(as: U.Type, perform: (Image<U>) throws -> Result) rethrows -> Result {
        precondition(MemoryLayout<U>.stride == MemoryLayout<T>.stride, "\(U.self) is not layout compatible with \(T.self)")
        let storage = self.storage
        let allocator: ImageAllocator = .custom(context: storage, deallocateFunc: { _, _ in })
        return try self.withUnsafeBufferPointer { buffer in
            return try buffer.withMemoryRebound(to: U.self) { reboundBuffer in
                let data = Image<U>(width: self.width, height: self.height, channelCount: self.channelCount, colorSpace: self.colorSpace, alphaMode: self.alphaMode, data: UnsafeMutableBufferPointer(mutating: reboundBuffer), allocator: allocator)
                return try perform(data)
            }
        }
    }
    
    @available(*, deprecated, renamed: "withMutableImageReinterpreted(as:perform:)")
    @inlinable
    public mutating func withMutableTextureReinterpreted<U, Result>(as type: U.Type, perform: (inout Image<U>) throws -> Result) rethrows -> Result {
        return try self.withMutableImageReinterpreted(as: type, perform: perform)
    }
    
    
    @inlinable
    public mutating func withMutableImageReinterpreted<U, Result>(as: U.Type, perform: (inout Image<U>) throws -> Result) rethrows -> Result {
        precondition(MemoryLayout<U>.stride == MemoryLayout<T>.stride, "\(U.self) is not layout compatible with \(T.self)")
        let width = self.width
        let height = self.height
        let channels = self.channelCount
        let colorSpace = self.colorSpace
        let alphaMode = self.alphaMode
        let storage = self.storage
        let allocator: ImageAllocator = .custom(context: storage, deallocateFunc: { _, _ in })
        return try self.withUnsafeMutableBufferPointer { buffer in
            return try buffer.withMemoryRebound(to: U.self) { reboundBuffer in
                var data = Image<U>(width: width, height: height, channelCount: channels, colorSpace: colorSpace, alphaMode: alphaMode, data: reboundBuffer, allocator: allocator)
                return try perform(&data)
            }
        }
    }
}

extension Image where ComponentType: BinaryInteger & FixedWidthInteger & SignedInteger {
    @inlinable
    public init(_ data: Image<Float>) {
        self.init(width: data.width, height: data.height, channelCount: data.channelCount, colorSpace: data.colorSpace, alphaMode: data.alphaMode)
        
        self.withUnsafeMutableBufferPointer { dest in
            data.withUnsafeBufferPointer { source in
                for (i, sourceVal) in source.enumerated() {
                    dest[i] = floatToSnorm(sourceVal, type: T.self)
                }
            }
        }
    }
}

extension Image where ComponentType == Float {
    
    @inlinable
    public init<I: BinaryInteger & FixedWidthInteger & SignedInteger>(_ data: Image<I>) {
        self.init(width: data.width, height: data.height, channelCount: data.channelCount, colorSpace: data.colorSpace, alphaMode: data.alphaMode)
        
        self.withUnsafeMutableBufferPointer { dest in
            data.withUnsafeBufferPointer { source in
                for (i, sourceVal) in source.enumerated() {
                    dest[i] = snormToFloat(sourceVal) // FIXME: componentsPerRow/row stride
                }
            }
        }
    }
    
    @inlinable
    public init<I: BinaryInteger & FixedWidthInteger & UnsignedInteger>(_ data: Image<I>) {
        self.init(width: data.width, height: data.height, channelCount: data.channelCount, colorSpace: data.colorSpace, alphaMode: data.alphaMode)
        
        self.withUnsafeMutableBufferPointer { dest in
            data.withUnsafeBufferPointer { source in
                for (i, sourceVal) in source.enumerated() {
                    dest[i] = unormToFloat(sourceVal) // FIXME: componentsPerRow/row stride
                }
            }
        }
    }
    
    public func converted(toColorSpace: ImageColorSpace) -> Self {
        var result = self
        result.convert(toColorSpace: toColorSpace)
        return result
    }
    
    public mutating func convert(toColorSpace: ImageColorSpace) {
        if toColorSpace == self.colorSpace || self.colorSpace == .undefined {
            return
        }
        defer { self.colorSpace = toColorSpace }
        
        if toColorSpace == .undefined { return }
        
        let sourceColorSpace = self.colorSpace
        let channelRange = self.alphaMode != .none ? (0..<self.channelCount - 1) : 0..<self.channelCount
        
        if channelRange.count < 3 || (sourceColorSpace.usesSRGBPrimaries && toColorSpace.usesSRGBPrimaries) {
            // Gamma correction only.
            self.apply(channelRange: channelRange) { ImageColorSpace.convert($0, from: sourceColorSpace, to: toColorSpace) }
        } else if let fromCIE = sourceColorSpace.cieSpace, let toCIE = toColorSpace.cieSpace {
            let conversionContext = CIEXYZ1931ColorSpace.conversionContext(convertingFrom: fromCIE, to: toCIE)
            let channelCount = self.channelCount
            
            if channelCount == 3 {
                self.withUnsafeMutableBufferPointer { contents in
                    for offset in stride(from: 0, to: contents.count, by: channelCount) {
                        let source = SIMD3<ComponentType>(contents[offset + 0], contents[offset + 1], contents[offset + 2])
                        let converted = SIMD3<Float>(conversionContext.convert(RGBColor(source)))
                        contents[offset + 0] = converted.x
                        contents[offset + 1] = converted.y
                        contents[offset + 2] = converted.z
                    }
                }
            } else {
                self.withUnsafeMutableBufferPointer { contents in
                    contents.withMemoryRebound(to: SIMD4<ComponentType>.self) { contents in
                        for i in contents.indices {
                            let source = contents[i]
                            let converted = SIMD3<Float>(conversionContext.convert(RGBColor(source.xyz)))
                            let encoded = SIMD4<Float>(converted, source.w)
                            contents[i] = encoded
                        }
                    }
                }
            }
        }
    }
    
    @available(*, deprecated, renamed: "convert(toColorSpace:)")
    public mutating func convert(toColourSpace: ImageColorSpace) {
        self.convert(toColorSpace: toColourSpace)
    }
    
    public mutating func convertToPremultipliedAlpha() {
        guard case .postmultiplied = self.alphaMode else { return }
        defer { self.alphaMode = .premultiplied }
        
        self.ensureUniqueness()
        
        let sourceColorSpace = self.colorSpace
        self.convert(toColorSpace: .linearSRGB)
        
        let alphaChannel = self.channelCount - 1
        for y in 0..<self.height {
            for x in 0..<self.width {
                for c in 0..<alphaChannel {
                    self.setUnchecked(x: x, y: y, channel: c, value: self[x, y, channel: c] * self[x, y, channel: alphaChannel])
                }
            }
        }
        
        self.convert(toColorSpace: sourceColorSpace)
    }
    
    public mutating func convertToPostmultipliedAlpha() {
        guard case .premultiplied = self.alphaMode else { return }
        
        defer { self.alphaMode = .postmultiplied }
        
        self.ensureUniqueness()
        
        let sourceColorSpace = self.colorSpace
        self.convert(toColorSpace: .linearSRGB)
        
        let alphaChannel = self.channelCount - 1
        for y in 0..<self.height {
            for x in 0..<self.width {
                let alpha = Swift.max(self[x, y, channel: alphaChannel], .leastNormalMagnitude)
                for c in 0..<alphaChannel {
                    let newValue = self[x, y, channel: c] / alpha
                    self.setUnchecked(x: x, y: y, channel: c, value: clamp(newValue, min: 0.0, max: 1.0))
                }
            }
        }
        
        self.convert(toColorSpace: sourceColorSpace)
    }
}

extension Image where ComponentType: BinaryFloatingPoint {
    @inlinable
    public init<Other: BinaryFloatingPoint>(_ data: Image<Other>) {
        self.init(width: data.width, height: data.height, channelCount: data.channelCount, colorSpace: data.colorSpace, alphaMode: data.alphaMode)
        
        self.withUnsafeMutableBufferPointer { dest in
            data.withUnsafeBufferPointer { source in
                for (i, sourceVal) in source.enumerated() {
                    dest[i] = T(sourceVal)  // FIXME: componentsPerRow/row stride
                }
            }
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

@_spi(SubstrateTextureIO) public struct DefaultImageLoadingDelegate: ImageLoadingDelegate {
    public init() {}
}
