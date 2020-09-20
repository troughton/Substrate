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
    
    case type2DMultisampleArray
    
    case typeTextureBuffer
}

public struct TextureUsage : OptionSet, Hashable {
    public let rawValue : UInt
    
    @inlinable
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

public struct BufferUsage : OptionSet, Hashable {
    public let rawValue : UInt
    
    @inlinable
    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }
    
    public static let unknown : BufferUsage = []
    
    public static let shaderRead = BufferUsage(rawValue: 1)
    
    public static let shaderWrite = BufferUsage(rawValue: 2)
    
    public static let blitSource = BufferUsage(rawValue: 4)
    
    public static let blitDestination = BufferUsage(rawValue: 8)
    
    public static let indexBuffer = BufferUsage(rawValue: 16)
    
    public static let vertexBuffer = BufferUsage(rawValue: 32)
    
    public static let indirectBuffer = BufferUsage(rawValue: 64)
    
    public static let textureView = BufferUsage(rawValue: 128)
}

public struct TextureDescriptor: Hashable {
    
    public init() {
        
    }

    public init(type: TextureType, format: PixelFormat, width: Int, height: Int = 1, depth: Int = 1, mipmapped: Bool, storageMode: StorageMode = .private, usage: TextureUsage = []) {
        self.init()
        
        self.pixelFormat = format
        self.textureType = type
        self.width = width
        self.height = type == .typeCube ? width : height
        self.depth = depth
        self.mipmapLevelCount = mipmapped ? 1 + Int(floor(log2(Double(max(width, height))))) : 1
        self.storageMode = storageMode
        self.usageHint = usage
    }
    
    @available(*, deprecated, message: "Use TextureDescriptor(type:) instead.")
    public init(texture2DWithFormat pixelFormat: PixelFormat, width: Int, height: Int, mipmapped: Bool, storageMode: StorageMode = .private, usageHint: TextureUsage = []) {
        var descriptor = TextureDescriptor()
        descriptor.pixelFormat = pixelFormat
        descriptor.textureType = .type2D
        descriptor.width = width
        descriptor.height = height
        descriptor.mipmapLevelCount = mipmapped ? 1 + Int(floor(log2(Double(max(width, height))))) : 1
        descriptor.storageMode = storageMode
        descriptor.usageHint = usageHint
        self = descriptor
    }
    
    @available(*, deprecated, message: "Use TextureDescriptor(type:) instead.")
    public init(textureCubeWithFormat pixelFormat: PixelFormat, size: Int, mipmapped: Bool, storageMode: StorageMode = .private, usageHint: TextureUsage = []) {
        var descriptor = TextureDescriptor()
        descriptor.pixelFormat = pixelFormat
        descriptor.textureType = .typeCube
        descriptor.width = size
        descriptor.height = size
        descriptor.mipmapLevelCount = mipmapped ? 1 + Int(floor(log2(Double(size)))) : 1
        descriptor.storageMode = storageMode
        descriptor.usageHint = usageHint
        self = descriptor
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
    
    public func size(mipLevel: Int) -> Size {
        var size = self.size
        size.width >>= mipLevel
        size.height >>= mipLevel
        size.depth >>= mipLevel
        size.width = max(size.width, 1)
        size.height = max(size.height, 1)
        size.depth = max(size.depth, 1)
        return size
    }
}

extension TextureDescriptor {
    func arraySlice(for slice: Int) -> Int {
        var arraySlice = slice
        
        if self.textureType == .typeCube || self.textureType == .typeCubeArray {
            arraySlice /= 6
        }
        arraySlice /= self.depth
        
        assert(arraySlice < self.arrayLength)
        return arraySlice
    }
}

public struct BufferDescriptor: Hashable {
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

public enum HeapType {
    case automaticPlacement
    case sparseTexture
}

public struct HeapDescriptor {
    public var size : Int
    public var type : HeapType
    public var storageMode : StorageMode
    public var cacheMode : CPUCacheMode
    
    public init(size: Int, type: HeapType = .automaticPlacement, storageMode: StorageMode = .managed, cacheMode: CPUCacheMode = .defaultCache) {
        self.size = size
        self.type = type
        self.storageMode = storageMode
        self.cacheMode = cacheMode
    }
}
