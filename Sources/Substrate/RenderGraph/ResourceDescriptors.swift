import Foundation

public enum TextureType : UInt, Sendable {
    
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

public struct TextureUsage : OptionSet, Hashable, Sendable {
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

public struct BufferUsage : OptionSet, Hashable, Sendable {
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

public struct TextureDescriptor: Hashable, Sendable {
    
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

public struct BufferDescriptor: Hashable, Sendable {
    /// The minimum length, in bytes, of the buffer's allocation.
    public var length : Int
    /// The storage mode for the buffer, representing the pool of memory from which the buffer should be allocated.
    public var storageMode : StorageMode
    /// The CPU cache mode for the created buffer, if it is CPU-visible. Write-combined buffers _may_ have better write performance from the CPU but will have considerable overhead when being read by the CPU.
    public var cacheMode : CPUCacheMode
    
    /// The ways in which the created buffer will be used by the GPU. Only required for persistent or history buffers; transient buffers will infer their usage.
    public var usageHint: BufferUsage
    
    /// Creates a new `BufferDescriptor`.
    ///
    /// - Parameter length: The minimum length, in bytes, of the buffer's allocation.
    /// - Parameter storageMode: The storage mode for the buffer, representing the pool of memory from which the buffer should be allocated.
    /// - Parameter cacheMode: The CPU cache mode for the created buffer, if it is CPU-visible. Write-combined buffers _may_ have better write performance from the CPU but will have considerable overhead when being read by the CPU.
    /// - Parameter usage: The ways in which the created buffer will be used by the GPU. Only required for persistent or history buffers; transient buffers will infer their usage.
    public init(length: Int, storageMode: StorageMode = .managed, cacheMode: CPUCacheMode = .defaultCache, usage: BufferUsage = .unknown) {
        self.length = length
        self.storageMode = storageMode
        self.cacheMode = cacheMode
        self.usageHint = usage
    }
}

public enum HeapType: Sendable {
    case automaticPlacement
    case sparseTexture
}

public struct HeapDescriptor: Sendable {
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

public struct AccelerationStructureFlags: OptionSet, Sendable {
    public let rawValue: Int
    
    @inlinable
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    public static var refittable: AccelerationStructureFlags { .init(rawValue: 1 << 0) }
    public static var preferFastBuild: AccelerationStructureFlags { .init(rawValue: 1 << 1) }
}

public struct AccelerationStructureDescriptor: Equatable, Sendable {
    public struct TriangleGeometryDescriptor: Equatable, Sendable {
        public var triangleCount: Int
        
        public var indexBuffer: Buffer?
        public var indexBufferOffset: Int
        public var indexType: IndexType
        
        public var vertexBuffer: Buffer
        public var vertexBufferOffset: Int
        public var vertexStride: Int
        
        public init(triangleCount: Int,
                    vertexBuffer: Buffer, vertexBufferOffset: Int = 0, vertexStride: Int = 12,
                    indexBuffer: Buffer, indexBufferOffset: Int = 0, indexType: IndexType) {
            self.triangleCount = triangleCount
            
            self.vertexBuffer = vertexBuffer
            self.vertexBufferOffset = vertexBufferOffset
            self.vertexStride = vertexStride
            
            self.indexBuffer = indexBuffer
            self.indexBufferOffset = indexBufferOffset
            self.indexType = indexType
        }
        
        public init(triangleCount: Int,
                    vertexBuffer: Buffer, vertexBufferOffset: Int = 0, vertexStride: Int = 12) {
            self.triangleCount = triangleCount
            
            self.vertexBuffer = vertexBuffer
            self.vertexBufferOffset = vertexBufferOffset
            self.vertexStride = vertexStride
            
            self.indexBuffer = nil
            self.indexBufferOffset = 0
            self.indexType = .uint16
        }
    }

    public struct BoundingBoxGeometryDescriptor: Equatable, Sendable {
        public var boundingBoxCount: Int
        
        public var boundingBoxBuffer: Buffer
        public var boundingBoxBufferOffset: Int
        public var boundingBoxStride: Int
        
        
        public init(boundingBoxCount: Int,
                    boundingBoxBuffer: Buffer, boundingBoxBufferOffset: Int = 0, boundingBoxStride: Int = 24) {
            self.boundingBoxCount = boundingBoxCount
            
            self.boundingBoxBuffer = boundingBoxBuffer
            self.boundingBoxBufferOffset = boundingBoxBufferOffset
            self.boundingBoxStride = boundingBoxStride
        }
    }
    
    public enum GeometryType: Equatable, Sendable {
        case triangle(TriangleGeometryDescriptor)
        case boundingBox(BoundingBoxGeometryDescriptor)
    }
    
    public struct GeometryDescriptor: Equatable, Sendable {
        public var geometry: GeometryType
        
        public var intersectionFunctionTableOffset: Int
        public var isOpaque: Bool
        public var canInvokeIntersectionFunctionsMultipleTimesPerIntersection: Bool
        
        public init(geometry: GeometryType, intersectionFunctionTableOffset: Int = 0, isOpaque: Bool = true, canInvokeIntersectionFunctionsMultipleTimesPerIntersection: Bool = true) {
            self.geometry = geometry
            self.intersectionFunctionTableOffset = intersectionFunctionTableOffset
            self.isOpaque = isOpaque
            self.canInvokeIntersectionFunctionsMultipleTimesPerIntersection = canInvokeIntersectionFunctionsMultipleTimesPerIntersection
        }
    }
    
    public struct InstanceStructureDescriptor: Equatable, Sendable {
        public var primitiveStructures: [AccelerationStructure]
        
        public var instanceCount: Int
        public var instanceDescriptorBuffer: Buffer
        public var instanceDescriptorBufferOffset: Int
        public var instanceDescriptorStride: Int
        
        public init(primitiveStructures: [AccelerationStructure],
                    instanceCount: Int, instanceDescriptorBuffer: Buffer, instanceDescriptorBufferOffset: Int = 0, instanceDescriptorStride: Int = 64) {
            self.primitiveStructures = primitiveStructures
            self.instanceCount = instanceCount
            self.instanceDescriptorBuffer = instanceDescriptorBuffer
            self.instanceDescriptorBufferOffset = instanceDescriptorBufferOffset
            self.instanceDescriptorStride = instanceDescriptorStride
        }
    }
    
    public enum StructureType: Equatable, Sendable {
        case bottomLevelPrimitive([GeometryDescriptor])
        case topLevelInstance(InstanceStructureDescriptor)
    }
    
    public var type: StructureType
    public var flags: AccelerationStructureFlags
    
    @available(macOS 11.0, iOS 14.0, *)
    public init(type: StructureType, flags: AccelerationStructureFlags = []) {
        self.type = type
        self.flags = flags
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public var sizes: AccelerationStructureSizes {
        return RenderBackend.accelerationStructureSizes(for: self)
    }
}

public struct AccelerationStructureSizes: Equatable, Sendable {
    public var accelerationStructureSize: Int
    
    /// The amount of scratch memory, in bytes, needed to build the acceleration structure.
    public var buildScratchBufferSize: Int
    
    /// The amount of scratch memory, in bytes, needed to refit the acceleration structure.
    public var refitScratchBufferSize: Int
}
