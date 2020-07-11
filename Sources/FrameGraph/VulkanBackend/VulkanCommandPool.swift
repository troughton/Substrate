//
//  VulkanCommandPool.swift
//  VkRenderer
//
//  Created by Joseph Bennett on 15/01/18.
//

#if canImport(Vulkan)
import Vulkan
import FrameGraphCExtras
import FrameGraphUtilities
import Dispatch

/// Wraps a Vulkan queue.
public final class VulkanDeviceQueue {
    let commandBufferManagementQueue = DispatchQueue(label: "Vulkan Command Buffer Management")

    public let device: VulkanDevice
    public let vkQueue : VkQueue
    public let familyIndex: Int
    public let queueIndex: Int
    
    let commandPool: VkCommandPool
    
    private var commandBuffers : [VkCommandBuffer] = []
    
    init(device: VulkanDevice, familyIndex: Int, queueIndex: Int) {
        self.device = device
        self.familyIndex = familyIndex
        self.queueIndex = queueIndex
        
        var queue : VkQueue? = nil
        vkGetDeviceQueue(device.vkDevice, UInt32(familyIndex), UInt32(queueIndex), &queue)
        self.vkQueue = queue!
        
        var commandPoolCreateInfo = VkCommandPoolCreateInfo()
        commandPoolCreateInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO
        commandPoolCreateInfo.flags = VkCommandPoolCreateFlags(VK_COMMAND_POOL_CREATE_TRANSIENT_BIT)
        commandPoolCreateInfo.queueFamilyIndex = UInt32(familyIndex)
        
        var commandPool: VkCommandPool? = nil
        guard vkCreateCommandPool(device.vkDevice, &commandPoolCreateInfo, nil, &commandPool) == VK_SUCCESS else {
            fatalError("Failed to create command pool for queue family index \(familyIndex)")
        }
        self.commandPool = commandPool!
    }

    deinit {
        vkDestroyCommandPool(self.device.vkDevice, self.commandPool, nil)
    }
    
    public func allocateCommandBuffer() -> VkCommandBuffer {
        if let commandBuffer = self.commandBufferManagementQueue.sync(execute: { self.commandBuffers.popLast() }) {
            vkResetCommandBuffer(commandBuffer, 0)
            return commandBuffer
        }

        var commandBufferAllocateInfo = VkCommandBufferAllocateInfo()
        commandBufferAllocateInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO
        commandBufferAllocateInfo.commandPool = self.commandPool
        commandBufferAllocateInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY
        commandBufferAllocateInfo.commandBufferCount = 1
        
        var commandBuffer : VkCommandBuffer? = nil
        vkAllocateCommandBuffers(self.device.vkDevice, &commandBufferAllocateInfo, &commandBuffer).check()

        return commandBuffer!
    }

    public func depositCommandBuffer(_ commandBuffer: VkCommandBuffer) {
        // TODO: periodically reset all resources to the pool to avoid fragmentation/over-allocation using vkResetCommandPool
        self.commandBufferManagementQueue.sync {
            self.commandBuffers.append(commandBuffer)
        }
    }
}

/// Wraps the FrameGraph abstraction of a queue, which may map to multiple Vulkan queues.
final class VulkanQueue {
    let device : VulkanDevice
    
    let renderQueue: VulkanDeviceQueue?
    let computeQueue: VulkanDeviceQueue?
    let blitQueue: VulkanDeviceQueue?
    let presentationQueue: VulkanDeviceQueue?
    
    init(device: VulkanDevice, capabilities: QueueCapabilities) {
        self.device = device
        
        assert(!capabilities.isEmpty)
        if capabilities.contains(.render) {
            self.renderQueue = device.deviceQueue(capabilities: capabilities, requiredCapability: .render)
        } else {
            self.renderQueue = nil
        }
        if capabilities.contains(.compute) {
            self.computeQueue = device.deviceQueue(capabilities: capabilities, requiredCapability: .compute)
        } else {
            self.computeQueue = nil
        }
        if capabilities.contains(.blit) {
            self.blitQueue = device.deviceQueue(capabilities: capabilities, requiredCapability: .blit)
        } else {
            self.blitQueue = nil
        }
        if capabilities.contains(.present) {
            self.presentationQueue = device.deviceQueue(capabilities: capabilities, requiredCapability: .present)
        } else {
            self.presentationQueue = nil
        }
    }
}

#endif // canImport(Vulkan)
