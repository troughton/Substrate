//
//  OptionSets.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 8/01/18.
//

#if canImport(Vulkan)
import Vulkan
@_implementationOnly import SubstrateCExtras

extension VkDebugReportFlagBitsEXT : OptionSet {
    var flags: VkDebugReportFlagsEXT {
        return VkDebugReportFlagsEXT(self.rawValue)
    }
 }

extension VkFormatFeatureFlagBits : OptionSet { 
    var flags: VkFormatFeatureFlags {
        return VkFormatFeatureFlags(self.rawValue)
    }
}

extension VkImageCreateFlagBits : OptionSet {
    var flags: VkImageCreateFlags {
        return VkImageCreateFlags(self.rawValue)
    }

    public static var sparseBinding : VkImageCreateFlagBits {
        return VK_IMAGE_CREATE_SPARSE_BINDING_BIT
    }
    
    public static var sparseResidency : VkImageCreateFlagBits {
        return VK_IMAGE_CREATE_SPARSE_RESIDENCY_BIT
    }
    
    public static var sparseAliased : VkImageCreateFlagBits {
        return VK_IMAGE_CREATE_SPARSE_ALIASED_BIT
    }
    
    public static var mutableFormat : VkImageCreateFlagBits {
        return VK_IMAGE_CREATE_MUTABLE_FORMAT_BIT
    }
    
    public static var cubeCompatible : VkImageCreateFlagBits {
        return VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT
    }
}

extension VkImageUsageFlagBits : OptionSet {
    
    public static var transferSource : VkImageUsageFlagBits {
        return VK_IMAGE_USAGE_TRANSFER_SRC_BIT
    }
    
    public static var transferDestination : VkImageUsageFlagBits {
        return VK_IMAGE_USAGE_TRANSFER_DST_BIT
    }
    
    public static var sampled : VkImageUsageFlagBits {
        return VK_IMAGE_USAGE_SAMPLED_BIT
    }
    
    public static var storage : VkImageUsageFlagBits {
        return VK_IMAGE_USAGE_STORAGE_BIT
    }
    
    public static var colorAttachment : VkImageUsageFlagBits {
        return VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT
    }
    
    public static var depthStencilAttachment : VkImageUsageFlagBits {
        return VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT
    }
    
    public static var transientAttachment : VkImageUsageFlagBits {
        return VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT
    }
    
    public static var inputAttachment : VkImageUsageFlagBits {
        return VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT
    }
}

extension VkImageViewCreateFlagBits : OptionSet {
    var flags: VkImageViewCreateFlags {
        return VkImageViewCreateFlags(self.rawValue)
    }
}

extension VkBufferUsageFlagBits : OptionSet {
    var flags: VkBufferUsageFlags {
        return VkBufferUsageFlags(self.rawValue)
    }
    
    public static var transferSource : VkBufferUsageFlagBits {
        return VK_BUFFER_USAGE_TRANSFER_SRC_BIT
    }
    
    public static var transferDestination : VkBufferUsageFlagBits {
        return VK_BUFFER_USAGE_TRANSFER_DST_BIT
    }
    
    public static var uniformTexelBuffer : VkBufferUsageFlagBits {
        return VK_BUFFER_USAGE_UNIFORM_TEXEL_BUFFER_BIT
    }
    
    public static var storageTexelBuffer : VkBufferUsageFlagBits {
        return VK_BUFFER_USAGE_STORAGE_TEXEL_BUFFER_BIT
    }
    
    public static var uniformBuffer : VkBufferUsageFlagBits {
        return VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT
    }
    
    public static var storageBuffer : VkBufferUsageFlagBits {
        return VK_BUFFER_USAGE_STORAGE_BUFFER_BIT
    }
    
    public static var indexBuffer : VkBufferUsageFlagBits {
        return VK_BUFFER_USAGE_INDEX_BUFFER_BIT
    }
    
    public static var vertexBuffer : VkBufferUsageFlagBits {
        return VK_BUFFER_USAGE_VERTEX_BUFFER_BIT
    }
    
    public static var indirectBuffer : VkBufferUsageFlagBits {
        return VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT
    }
}

extension VkAccessFlagBits : OptionSet {
    var flags: VkAccessFlags {
        return VkAccessFlags(self.rawValue)
    }
}


extension VkDescriptorBindingFlagBits : OptionSet {
    var flags: VkDescriptorBindingFlags {
        return VkDescriptorBindingFlags(self.rawValue)
    }
}

extension VkDependencyFlagBits: OptionSet {
    var flags: VkDependencyFlags {
        return VkDependencyFlags(self.rawValue)
    }
}

extension VkImageAspectFlagBits: OptionSet {
    var flags: VkImageAspectFlags {
        return VkImageAspectFlags(self.rawValue)
    }
}

extension VkPipelineStageFlagBits : OptionSet {
    var flags: VkPipelineStageFlags {
        return VkPipelineStageFlags(self.rawValue)
    }
}

extension VkSampleCountFlagBits : OptionSet {
    var flags: VkSampleCountFlags {
        return VkSampleCountFlags(self.rawValue)
    }
}

extension VkCommandPoolCreateFlagBits : OptionSet {
    var flags: VkCommandPoolCreateFlags {
        return VkCommandPoolCreateFlags(self.rawValue)
    }
}

extension VkQueueFlagBits : OptionSet {
    var flags: VkQueueFlags {
        return VkQueueFlags(self.rawValue)
    }
}

extension VkMemoryPropertyFlagBits : OptionSet {
    var flags: VkMemoryPropertyFlags {
        return VkMemoryPropertyFlags(self.rawValue)
    }
}

extension VmaAllocationCreateFlagBits : OptionSet {
    var flags: VmaAllocationCreateFlags {
        return VmaAllocationCreateFlags(self.rawValue)
    }
}

#endif // canImport(Vulkan)
