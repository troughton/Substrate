#if canImport(Vulkan)
import Vulkan
import FrameGraphCExtras

// Must be kept in sync with VkReflectionContext

extension ShaderResourceType {
    /// A single struct of read-only data with the 'constant' storage class.
    static var uniformBuffer : ShaderResourceType { return ShaderResourceType(ShaderResourceTypeUniformBuffer) }
    /// A tightly packed array of read-only data with the 'constant' storage class.
    static var uniformTexelBuffer : ShaderResourceType { return ShaderResourceType(ShaderResourceTypeUniformTexelBuffer) }
    /// A single struct of atomic read-write data with the 'device' storage class.
    static var storageBuffer : ShaderResourceType { return ShaderResourceType(ShaderResourceTypeStorageBuffer) }
    /// A tightly packed array of atomic read-write data with the 'device' storage class.
    static var storageTexelBuffer : ShaderResourceType { return ShaderResourceType(ShaderResourceTypeStorageTexelBuffer) }
    /// An image view that can be used for unfiltered pixel-local load operations.
    static var subpassInput : ShaderResourceType { return ShaderResourceType(ShaderResourceTypeSubpassInput) }
    /// An image that can be loaded from, stored to, and used for atomic operations.
    static var storageImage : ShaderResourceType { return ShaderResourceType(ShaderResourceTypeStorageImage) }
    /// An image that can be read or sampled from with a sampler
    static var sampledImage : ShaderResourceType { return ShaderResourceType(ShaderResourceTypeSampledImage) }
    /// A variant of uniform buffers that's fast-pathed for updates (e.g. setBytes).
    static var pushConstantBuffer : ShaderResourceType { return ShaderResourceType(ShaderResourceTypePushConstantBuffer) }
    /// A sampler that can be used with multiple sampled images.
    static var sampler : ShaderResourceType { return ShaderResourceType(ShaderResourceTypeSampler) }
}

extension AccessQualifier {
    static var none : AccessQualifier { return AccessQualifier(AccessQualifierNone) }  
    static var readOnly : AccessQualifier { return AccessQualifier(AccessQualifierReadOnly) }  
    static var readWrite : AccessQualifier { return AccessQualifier(AccessQualifierReadWrite) }  
    static var writeOnly : AccessQualifier { return AccessQualifier(AccessQualifierWriteOnly) }  
}

#endif
