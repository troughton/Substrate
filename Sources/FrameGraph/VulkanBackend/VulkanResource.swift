//
//  VulkanResource.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 15/01/18.
//

#if canImport(Vulkan)
import Vulkan
import FrameGraphCExtras

struct ResourceSemaphore {
    let vkSemaphore : VkSemaphore
    let stages : VkPipelineStageFlagBits
}

enum VulkanSharingMode : Equatable {
    case exclusive
    case concurrent(queueFamilyIndices: [UInt32])
    
    public init(usage: VkBufferUsageFlagBits, device: VulkanPhysicalDevice) {
        var queueFamilies : QueueCapabilities = []
        if !usage.intersection([.uniformBuffer, .uniformTexelBuffer, .storageBuffer, .storageTexelBuffer, .indirectBuffer]).isEmpty {
            queueFamilies.formUnion([.render, .compute])
        }
        if !usage.intersection([.vertexBuffer, .indexBuffer]).isEmpty {
            queueFamilies.formUnion(.render)
        }
        if !usage.intersection([.transferSource, .transferDestination]).isEmpty {
            queueFamilies.formUnion(.blit)
        }
        self.init(queueFamilies: queueFamilies)
    }
    
    public init(usage: VkImageUsageFlagBits, device: VulkanPhysicalDevice) {
        var queueFamilies : QueueCapabilities = []
        if !usage.intersection([.sampled, .storage]).isEmpty {
            queueFamilies.formUnion([.render, .compute])
        }
        if !usage.intersection([.colorAttachment, .depthStencilAttachment, .inputAttachment, .transientAttachment]).isEmpty {
            queueFamilies.formUnion(.render)
        }
        if !usage.intersection([.transferSource, .transferDestination]).isEmpty {
            queueFamilies.formUnion(.blit)
        }
        self.init(queueFamilies: queueFamilies)
    }
    
    public init(queueFamilies: QueueCapabilities) {
        self = .exclusive // FIXME: figure out how to manage queue sharing.
    }
}

#endif // canImport(Vulkan)
