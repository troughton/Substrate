#if canImport(Vulkan)
import Vulkan
import FrameGraphCExtras
import SPIRV_Cross

// Must be kept in sync with VkReflectionContext

extension spvc_resource_type {
    /// A single struct of read-only data with the 'constant' storage class.
    static var uniformBuffer : spvc_resource_type { return SPVC_RESOURCE_TYPE_UNIFORM_BUFFER }
    /// A single struct of atomic read-write data with the 'device' storage class.
    static var storageBuffer : spvc_resource_type { return SPVC_RESOURCE_TYPE_STORAGE_BUFFER }
    /// An image view that can be used for unfiltered pixel-local load operations.
    static var subpassInput : spvc_resource_type { return SPVC_RESOURCE_TYPE_SUBPASS_INPUT }
    /// An image that can be loaded from, stored to, and used for atomic operations.
    static var storageImage : spvc_resource_type { return SPVC_RESOURCE_TYPE_STORAGE_IMAGE }
    /// An image that can be read or sampled from with a sampler
    static var sampledImage : spvc_resource_type { return SPVC_RESOURCE_TYPE_SAMPLED_IMAGE }
    /// An image that can be read or sampled from with a sampler
    static var separateImage : spvc_resource_type { return SPVC_RESOURCE_TYPE_SEPARATE_IMAGE }
    /// A variant of uniform buffers that's fast-pathed for updates (e.g. setBytes).
    static var pushConstantBuffer : spvc_resource_type { return SPVC_RESOURCE_TYPE_PUSH_CONSTANT }
    /// A sampler that can be used with multiple sampled images.
    static var sampler : spvc_resource_type { return SPVC_RESOURCE_TYPE_SEPARATE_SAMPLERS }
}

#endif
