//
//  VulkanCommandPool.swift
//  VkRenderer
//
//  Created by Joseph Bennett on 15/01/18.
//

#if canImport(Vulkan)
import Vulkan
@_implementationOnly import SubstrateCExtras
import SubstrateUtilities
import Dispatch

/// Wraps a Vulkan queue.
final class VulkanDeviceQueue {
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
        commandPoolCreateInfo.flags = VkCommandPoolCreateFlags([VK_COMMAND_POOL_CREATE_TRANSIENT_BIT, VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT])
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

/// Wraps the RenderGraph abstraction of a queue, which may map to multiple Vulkan queues.
final class VulkanQueue: BackendQueue {
    typealias Backend = VulkanBackend
    
    let backend: VulkanBackend
    let device : VulkanDevice
    
    init(backend: VulkanBackend, device: VulkanDevice) {
        self.backend = backend
        self.device = device
    }
    
    func makeCommandBuffer(commandInfo: FrameCommandInfo<VulkanRenderTargetDescriptor>, resourceMap: FrameResourceMap<Backend>, compactedResourceCommands: [CompactedResourceCommand<Backend.CompactedResourceCommandType>]) -> VulkanCommandBuffer {
        let queue = device.queues[0] // TODO: use queues other than the main queue.
        return VulkanCommandBuffer(backend: self.backend, queue: queue, commandInfo: commandInfo, resourceMap: resourceMap, compactedResourceCommands: compactedResourceCommands)
    }
}

#endif // canImport(Vulkan)
