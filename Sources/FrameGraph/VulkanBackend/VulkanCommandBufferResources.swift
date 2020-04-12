//
//  CommandBufferResources.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 10/01/18.
//

#if canImport(Vulkan)
import Vulkan
import FrameGraphCExtras
import FrameGraphUtilities

// Represents all resources that are associated with a particular command buffer
// and should be freed once the command buffer has finished execution.
public final class CommandBufferResources {
    let device : VulkanDevice
    let commandBuffer : VkCommandBuffer
    let commandPool : VulkanFrameCommandPool
    let queueFamilyIndex : Int

    var renderPass : VulkanRenderPass? = nil
    
    var buffers = [VulkanBuffer]()
    var bufferView = [VulkanBufferView]()
    var images = [VulkanImage]()
    var imageViews = [VulkanImageView]()
    var renderPasses = [VulkanRenderPass]()
    var framebuffers = [VulkanFramebuffer]()
    var descriptorSets = [VkDescriptorSet?]()
    var argumentBuffers = [VulkanArgumentBuffer]()
    
    var waitSemaphores = [ResourceSemaphore]()
    var signalSemaphores = [ResourceSemaphore]()
    
    init(device: VulkanDevice, commandBuffer: VkCommandBuffer, commandPool: VulkanFrameCommandPool, queueFamilyIndex: Int) {
        self.device = device
        self.commandBuffer = commandBuffer
        self.commandPool = commandPool
        self.queueFamilyIndex = queueFamilyIndex
        
        var beginInfo = VkCommandBufferBeginInfo()
        beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO
        beginInfo.flags = VkCommandBufferUsageFlags(VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT)
        vkBeginCommandBuffer(self.commandBuffer, &beginInfo)
    }

    var descriptorPool : VulkanDescriptorPool {
        return self.commandPool.descriptorPool
    }
    
    deinit {
        for semaphore in self.waitSemaphores {
            device.semaphorePool.depositSemaphore(semaphore.vkSemaphore)
        }
        
        // VulkanBuffers are reference counted
        // VulkanBufferViews are reference counted
        // VulkanImages are reference counted
        // VulkanImageViews are reference counted
        // VulkanRenderPasses are reference counted
        // VulkanFramebuffers are reference counted
        // VulkanArgumentBuffers are reference counted
        
        self.commandPool.reset(commandBuffer: self.commandBuffer, queueFamilyIndex: self.queueFamilyIndex, usedDescriptorSets: &descriptorSets)
    }
}


#endif // canImport(Vulkan)
