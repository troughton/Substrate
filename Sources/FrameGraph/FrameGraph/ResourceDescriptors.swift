
//
//  Texture.h
//  Metal

import Foundation

/*!
 @enum TextureType
 @abstract TextureType describes the dimensionality of each image, and if multiple images are arranged into an array or cube.
 */
public enum TextureType : UInt {
    
    case type1D
    
    case type1DArray
    
    case type2D
    
    case type2DArray
    
    case type2DMultisample
    
    case typeCube
    
    case typeCubeArray
    
    case type3D
}

/*!
 @enum TextureUsage
 @abstract TextureUsage declares how the texture will be used over its lifetime (bitwise OR for multiple uses).
 @discussion This information may be used by the driver to make optimization decisions.
 */
public struct TextureUsage : OptionSet {
    public let rawValue : UInt
    
    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }
    
    
    public static let unknown: TextureUsage = TextureUsage(rawValue: 0)
    
    public static let shaderRead: TextureUsage = TextureUsage(rawValue: 1)
    
    public static let shaderWrite: TextureUsage = TextureUsage(rawValue: 2)
    
    public static let renderTarget: TextureUsage = TextureUsage(rawValue: 4)
    
    public static let pixelFormatView: TextureUsage = TextureUsage(rawValue: 0x0010)
    
    public static let blitSource: TextureUsage = TextureUsage(rawValue: 32)
    
    public static let blitDestination: TextureUsage = TextureUsage(rawValue: 64)
}

/*!
 @enum BufferUsage
 @abstract BufferUsage declares how the texture will be used over its lifetime (bitwise OR for multiple uses).
 @discussion This information may be used by the driver to make optimization decisions.
 */
public struct BufferUsage : OptionSet {
    public let rawValue : UInt
    
    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }
    
    public static let unknown = BufferUsage(rawValue: 0)
    
    public static let shaderRead = BufferUsage(rawValue: 1)
    
    public static let shaderWrite = BufferUsage(rawValue: 2)
    
    public static let blitSource = BufferUsage(rawValue: 4)
    
    public static let blitDestination = BufferUsage(rawValue: 8)
    
    public static let indexBuffer = BufferUsage(rawValue: 16)
    
    public static let vertexBuffer = BufferUsage(rawValue: 32)
    
    public static let indirectBuffer = BufferUsage(rawValue: 64)
}

public struct TextureDescriptor {
    
    public init() {
        
    }
    
    /*!
     @method texture2DDescriptorWithPixelFormat:width:height:mipmapped:
     @abstract Create a TextureDescriptor for a common 2D texture.
     */
    public static func texture2DDescriptor(pixelFormat: PixelFormat, width: Int, height: Int, mipmapped: Bool) -> TextureDescriptor {
        var descriptor = TextureDescriptor()
        descriptor.pixelFormat = pixelFormat
        descriptor.textureType = .type2D
        descriptor.width = width
        descriptor.height = height
        descriptor.mipmapLevelCount = mipmapped ? 1 + Int(floor(log2(Double(max(width, height))))) : 1
        return descriptor
    }
    
    
    /*!
     @method textureCubeDescriptorWithPixelFormat:size:mipmapped:
     @abstract Create a TextureDescriptor for a common Cube texture.
     */
    public static func textureCubeDescriptor(pixelFormat: PixelFormat, size: Int, mipmapped: Bool) -> TextureDescriptor {
        var descriptor = TextureDescriptor()
        descriptor.pixelFormat = pixelFormat
        descriptor.textureType = .typeCube
        descriptor.width = size
        descriptor.height = size
        descriptor.mipmapLevelCount = mipmapped ? 1 + Int(floor(log2(Double(size)))) : 1
        return descriptor
    }
    
    
    /*!
     @property type
     @abstract The overall type of the texture to be created. The default value is TextureType2D.
     */
    public var textureType: TextureType = .type2D
    
    
    /*!
     @property pixelFormat
     @abstract The pixel format to use when allocating this texture. This is also the pixel format that will be used to when the caller writes or reads pixels from this texture. The default value is PixelFormatRGBA8Unorm.
     */
    public var pixelFormat: PixelFormat = .rgba8Unorm
    
    
    /*!
     @property width
     @abstract The width of the texture to create. The default value is 1.
     */
    public var width: Int = 1
    
    
    /*!
     @property height
     @abstract The height of the texture to create. The default value is 1.
     @discussion height If allocating a 1D texture, height must be 1.
     */
    public var height: Int = 1
    
    
    /*!
     @property depth
     @abstract The depth of the texture to create. The default value is 1.
     @discussion depth When allocating any texture types other than 3D, depth must be 1.
     */
    public var depth: Int = 1
    
    
    /*!
     @property mipmapLevelCount
     @abstract The number of mipmap levels to allocate. The default value is 1.
     @discussion When creating Buffer and Multisample textures, mipmapLevelCount must be 1.
     */
    public var mipmapLevelCount: Int = 1
    
    
    /*!
     @property sampleCount
     @abstract The number of samples in the texture to create. The default value is 1.
     @discussion When creating Buffer and Array textures, sampleCount must be 1. Implementations may round sample counts up to the next supported value.
     */
    public var sampleCount: Int = 1
    
    
    /*!
     @property arrayLength
     @abstract The number of array elements to allocate. The default value is 1.
     @discussion When allocating any non-Array texture type, arrayLength has to be 1. Otherwise it must be set to something greater than 1 and less than 2048.
     */
    public var arrayLength: Int = 1
    
    public var storageMode: StorageMode = .private
    
    public var cacheMode: CPUCacheMode = .defaultCache
    
    /// This usage hint is only needed for persistent resources.
    public var usageHint: TextureUsage = .unknown

    public var size : Size {
        get {
            return Size(width: self.width, height: self.height, depth: self.depth)
        }
        set {
            self.width = newValue.width
            self.height = newValue.height
            self.depth = newValue.depth
        }
    }
}

public struct BufferDescriptor {
    public var length : Int = 0
    public var storageMode : StorageMode
    public var cacheMode : CPUCacheMode
    
    /// This usage hint is only needed for persistent resources.
    public var usageHint: BufferUsage
    
    public init(length: Int, storageMode: StorageMode = .managed, cacheMode: CPUCacheMode = .defaultCache, usage: BufferUsage = .unknown) {
        self.length = length
        self.storageMode = storageMode
        self.cacheMode = cacheMode
        self.usageHint = usage
    }
}
