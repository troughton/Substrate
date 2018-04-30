//
//  ResourceAllocator.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 6/01/18.
//

import CVkRenderer

 protocol ResourceAllocator {
    func collectImage(descriptor: VulkanImageDescriptor) -> VulkanImage
    func depositImage(_ image: VulkanImage)
    
    func collectBuffer(descriptor: VulkanBufferDescriptor) -> VulkanBuffer
    func depositBuffer(_ buffer: VulkanBuffer)
    
    func cycleFrames()
}
