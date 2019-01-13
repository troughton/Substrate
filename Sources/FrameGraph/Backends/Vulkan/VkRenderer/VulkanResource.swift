//
//  VulkanResource.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 15/01/18.
//

import SwiftFrameGraph
import CVkRenderer

struct ResourceSemaphore {
    let vkSemaphore : VkSemaphore
    let stages : VkPipelineStageFlagBits
}

enum VulkanSharingMode : Equatable {
    case exclusive
    case concurrent(QueueFamilies)
    
    public init(usage: VkBufferUsageFlagBits, queueIndices: QueueFamilyIndices) {
        var queueFamilies : QueueFamilies = []
        if usage.contains(.indexBuffer) {
            queueFamilies.formUnion(.graphics)
        }
        if !usage.intersection([.uniformBuffer, .uniformTexelBuffer, .storageBuffer, .storageTexelBuffer, .indirectBuffer]).isEmpty {
            queueFamilies.formUnion([.graphics, .compute])
        }
        if !usage.intersection([.vertexBuffer, .indexBuffer]).isEmpty {
            queueFamilies.formUnion([.graphics])
        }
        if !usage.intersection([.transferSource, .transferDestination]).isEmpty {
            queueFamilies.formUnion(.copy)
        }
        self.init(queueFamilies: queueFamilies, indices: queueIndices)
    }
    
    public init(usage: VkImageUsageFlagBits, queueIndices: QueueFamilyIndices) {
        var queueFamilies : QueueFamilies = []
        if !usage.intersection([.sampled, .storage]).isEmpty {
            queueFamilies.formUnion([.graphics, .compute])
        }
        if !usage.intersection([.colorAttachment, .depthStencilAttachment, .inputAttachment, .transientAttachment]).isEmpty {
            queueFamilies.formUnion([.graphics])
        }
        if !usage.intersection([.transferSource, .transferDestination]).isEmpty {
            queueFamilies.formUnion(.copy)
        }
        self.init(queueFamilies: queueFamilies, indices: queueIndices)
    }
    
    public init(queueFamilies: QueueFamilies, indices: QueueFamilyIndices) {
        self = queueFamilies.isSingleQueue(indices: indices) ? .exclusive : .concurrent(queueFamilies)
    }
}
