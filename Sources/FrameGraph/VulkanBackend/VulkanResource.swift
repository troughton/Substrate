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
    
    public init(usage: VkBufferUsageFlagBits, device: VulkanDevice) {
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
        self.init(capabilities: queueFamilies, device: device)
    }
    
    public init(usage: VkImageUsageFlagBits, device: VulkanDevice) {
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
        self.init(capabilities: queueFamilies, device: device)
    }
    
    public init(capabilities: QueueCapabilities, device: VulkanDevice) {
        self = .concurrent(queueFamilyIndices: device.queueFamilyIndices(capabilities: capabilities)) // FIXME: figure out how to manage queue sharing.
    }
}

#endif // canImport(Vulkan)
