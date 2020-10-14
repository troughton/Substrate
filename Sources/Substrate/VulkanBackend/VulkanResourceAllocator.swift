//
//  ResourceAllocator.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 6/01/18.
//

#if canImport(Vulkan)
import Vulkan
import SubstrateCExtras

protocol VulkanResourceAllocator {
    func cycleFrames()
}

protocol VulkanImageAllocator : VulkanResourceAllocator {
    func collectImage(descriptor: VulkanImageDescriptor) -> (VkImageReference, [FenceDependency], ContextWaitEvent)
    func depositImage(_ image: VkImageReference, events: [FenceDependency], waitSemaphore: ContextWaitEvent)
}

protocol VulkanBufferAllocator : VulkanResourceAllocator {
    func collectBuffer(descriptor: VulkanBufferDescriptor) -> (VkBufferReference, [FenceDependency], ContextWaitEvent)
    func depositBuffer(_ buffer: VkBufferReference, events: [FenceDependency], waitSemaphore: ContextWaitEvent)
}


#endif // canImport(Vulkan)
