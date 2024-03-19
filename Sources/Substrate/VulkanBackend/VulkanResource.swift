//
//  VulkanResource.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 15/01/18.
//

#if canImport(Vulkan)
import Vulkan
@_implementationOnly import SubstrateCExtras

struct ResourceSemaphore {
    let vkSemaphore : VkSemaphore
    let stages : VkPipelineStageFlagBits
}

enum VulkanSharingMode : Equatable {
    case exclusive
    case concurrent(queueFamilyIndices: [UInt32])
    
    public init(usage: VkBufferUsageFlagBits, device: VulkanDevice) {
        var queueFlags : VkQueueFlagBits = []
        if !usage.intersection([.uniformBuffer, .uniformTexelBuffer, .storageBuffer, .storageTexelBuffer, .indirectBuffer]).isEmpty {
            queueFlags.formUnion([VK_QUEUE_GRAPHICS_BIT, VK_QUEUE_COMPUTE_BIT])
        }
        if !usage.intersection([.vertexBuffer, .indexBuffer]).isEmpty {
            queueFlags.formUnion(VK_QUEUE_GRAPHICS_BIT)
        }
        if !usage.intersection([.transferSource, .transferDestination]).isEmpty {
            queueFlags.formUnion(VK_QUEUE_TRANSFER_BIT)
        }
        self.init(queueFlags: queueFlags, device: device)
    }
    
    public init(usage: VkImageUsageFlagBits, device: VulkanDevice) {
        var queueFlags : VkQueueFlagBits = []
        if !usage.intersection([.sampled, .storage]).isEmpty {
            queueFlags.formUnion([VK_QUEUE_GRAPHICS_BIT, VK_QUEUE_COMPUTE_BIT])
        }
        if !usage.intersection([.colorAttachment, .depthStencilAttachment, .inputAttachment, .transientAttachment]).isEmpty {
            queueFlags.formUnion(VK_QUEUE_GRAPHICS_BIT)
        }
        if !usage.intersection([.transferSource, .transferDestination]).isEmpty {
            queueFlags.formUnion(VK_QUEUE_TRANSFER_BIT)
        }
        self.init(queueFlags: queueFlags, device: device)
    }
    
    public init(queueFlags: VkQueueFlagBits, device: VulkanDevice) {
        self = .concurrent(queueFamilyIndices: device.queueFamilyIndices(matchingAnyOf: queueFlags)) // FIXME: figure out how to manage queue sharing.
    }
}

#endif // canImport(Vulkan)
