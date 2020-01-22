//
//  ResourceAllocator.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 6/01/18.
//

#if canImport(Vulkan)
import Vulkan
import FrameGraphCExtras

protocol VulkanResourceAllocator {
    func cycleFrames()
}

protocol VulkanImageAllocator : VulkanResourceAllocator {
    func collectImage(descriptor: VulkanImageDescriptor) -> (VkImageReference, [VulkanEventHandle], VulkanContextWaitSemaphore)
    func depositImage(_ image: VkImageReference, events: [VulkanEventHandle], waitSemaphore: VulkanContextWaitSemaphore)
}

protocol VulkanBufferAllocator : VulkanResourceAllocator {
    func collectBuffer(descriptor: VulkanBufferDescriptor) -> (VkBufferReference, [VulkanEventHandle], VulkanContextWaitSemaphore)
    func depositBuffer(_ buffer: VkBufferReference, events: [VulkanEventHandle], waitSemaphore: VulkanContextWaitSemaphore)
}


#endif // canImport(Vulkan)
