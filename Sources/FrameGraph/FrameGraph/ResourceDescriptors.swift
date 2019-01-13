import Foundation

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

    public static func texture2DDescriptor(pixelFormat: PixelFormat, width: Int, height: Int, mipmapped: Bool, usageHint: TextureUsage = []) -> TextureDescriptor {
        var descriptor = TextureDescriptor()
        descriptor.pixelFormat = pixelFormat
        descriptor.textureType = .type2D
        descriptor.width = width
        descriptor.height = height
        descriptor.mipmapLevelCount = mipmapped ? 1 + Int(floor(log2(Double(max(width, height))))) : 1
        descriptor.usageHint = usageHint
        return descriptor
    }
    
    public static func textureCubeDescriptor(pixelFormat: PixelFormat, size: Int, mipmapped: Bool) -> TextureDescriptor {
        var descriptor = TextureDescriptor()
        descriptor.pixelFormat = pixelFormat
        descriptor.textureType = .typeCube
        descriptor.width = size
        descriptor.height = size
        descriptor.mipmapLevelCount = mipmapped ? 1 + Int(floor(log2(Double(size)))) : 1
        return descriptor
    }
    
    public var textureType: TextureType = .type2D
    
    public var pixelFormat: PixelFormat = .rgba8Unorm
    
    public var width: Int = 1
    
    public var height: Int = 1
    
    public var depth: Int = 1
    
    public var mipmapLevelCount: Int = 1
    
    public var sampleCount: Int = 1
    
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
