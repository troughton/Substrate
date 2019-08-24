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

class VulkanSubmitInfo {
    var submitInfo : VkSubmitInfo
    var commandBuffer : VkCommandBuffer?
    
    let waitSemaphores = ExpandingBuffer<VkSemaphore?>()
    let signalSemaphores = ExpandingBuffer<VkSemaphore?>()
    let waitStageMasks = ExpandingBuffer<VkPipelineStageFlags>()
    
    init(resources: CommandBufferResources) {
        self.commandBuffer = resources.commandBuffer

        // print("Submit info for resources \(ObjectIdentifier(resources))")
        
        for semaphore in resources.waitSemaphores {
            waitSemaphores.append(semaphore.vkSemaphore)
            waitStageMasks.append(VkPipelineStageFlags(semaphore.stages))
        }
        for semaphore in resources.signalSemaphores {
            signalSemaphores.append(semaphore.vkSemaphore)
        }

        // print("Wait semaphore is \(waitSemaphores[0]) (count: \(waitSemaphores.count))")
        // print("Signal semaphore is \(signalSemaphores[0]) (count: \(signalSemaphores.count))")
        // print("\n\n")

        var submitInfo = VkSubmitInfo()
        submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO
        submitInfo.pSignalSemaphores = UnsafePointer(signalSemaphores.buffer)
        submitInfo.signalSemaphoreCount = UInt32(signalSemaphores.count)
        submitInfo.pWaitSemaphores = UnsafePointer(waitSemaphores.buffer)
        submitInfo.waitSemaphoreCount = UInt32(waitSemaphores.count)
        submitInfo.pWaitDstStageMask = UnsafePointer(waitStageMasks.buffer)
        
        submitInfo.pCommandBuffers = escapingPointer(to: &self.commandBuffer)
        submitInfo.commandBufferCount = 1
        
        self.submitInfo = submitInfo
            
    }
}

public final class VulkanQueue {
    public let device : VulkanDevice
    public let vkQueue : VkQueue
    
    private var submissionBuffers = [CommandBufferResources]()
    
    init(device: VulkanDevice, queueFamilies: QueueFamilies) {
        self.device = device
        
        let queueFamilyIndices = self.device.physicalDevice.queueFamilyIndices(for: queueFamilies)
        assert(queueFamilyIndices.count == 1)
        
        var queue : VkQueue? = nil
        vkGetDeviceQueue(self.device.vkDevice, queueFamilyIndices.first!, 0, &queue)
        
        self.vkQueue = queue!
    }
    
    func addCommandBuffer(resources: CommandBufferResources) {
        self.submissionBuffers.append(resources)
    }
    
    func submit(fence: VkFence?) {
        defer { self.submissionBuffers.removeAll(keepingCapacity: true) }
        
        let submitInfos = self.submissionBuffers.map { VulkanSubmitInfo(resources: $0) }
        let vkSubmitInfos = submitInfos.map { $0.submitInfo }
        
        let _ = withExtendedLifetime(submitInfos) {
            vkSubmitInfos.withUnsafeBufferPointer { submitInfos in
                vkQueueSubmit(self.vkQueue, UInt32(submitInfos.count), submitInfos.baseAddress, fence).check()
            }
        }
    }
    
}

final class VulkanQueueCommandPool {
    let device : VulkanDevice
    let vkPool : VkCommandPool
    private var commandBuffers = [VkCommandBuffer]()

    init(device: VulkanDevice, vkPool: VkCommandPool) {
        self.device = device
        self.vkPool = vkPool
    }

    public func allocateCommandBuffer() -> VkCommandBuffer {
        if let commandBuffer = self.commandBuffers.popLast() {
            return commandBuffer
        }

        var commandBufferAllocateInfo = VkCommandBufferAllocateInfo()
        commandBufferAllocateInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO
        commandBufferAllocateInfo.commandPool = self.vkPool
        commandBufferAllocateInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY
        commandBufferAllocateInfo.commandBufferCount = 1
        
        var commandBuffer : VkCommandBuffer? = nil
        vkAllocateCommandBuffers(self.device.vkDevice, &commandBufferAllocateInfo, &commandBuffer).check()

        return commandBuffer!
    }

    public func depositCommandBuffer(_ commandBuffer: VkCommandBuffer) {
        self.commandBuffers.append(commandBuffer)
    }

    deinit {
        vkDestroyCommandPool(self.device.vkDevice, self.vkPool, nil)
    }
}

public final class VulkanFrameCommandPool {
    private static let resetThreshold = 1000

    let commandPools : [VulkanQueueCommandPool?]
    
    let device : VulkanDevice
    let descriptorPool : VulkanDescriptorPool
    
    private var resetCounter = 0
    private var needsReset = false

    init(device: VulkanDevice) {
        self.device = device
        
        var commandPoolCreateInfo = VkCommandPoolCreateInfo()
        commandPoolCreateInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO
        commandPoolCreateInfo.flags = VkCommandPoolCreateFlags(VK_COMMAND_POOL_CREATE_TRANSIENT_BIT)
        
        let familyIndices = device.physicalDevice.queueFamilyIndices(for: QueueFamilies.all)
        let maxIndex = Int(familyIndices.max()!)

        var commandPools = [VulkanQueueCommandPool?](repeating: nil, count: maxIndex + 1)

        for familyIndex in familyIndices {
            commandPoolCreateInfo.queueFamilyIndex = familyIndex
            
            var commandPool : VkCommandPool? = nil
            guard vkCreateCommandPool(device.vkDevice, &commandPoolCreateInfo, nil, &commandPool) == VK_SUCCESS else {
                fatalError("Failed to create command pool for queue family index \(familyIndex)")
            }

            commandPools[Int(familyIndex)] = VulkanQueueCommandPool(device: device, vkPool: commandPool!)
        }

        self.commandPools = commandPools
        
        self.descriptorPool = VulkanDescriptorPool(device: device, incrementalRelease: false)
    }
    
    public func allocateCommandBufferResources(passType: RenderPassType) -> CommandBufferResources {
        defer { needsReset = true }

        let familyIndex = self.device.physicalDevice.queueFamilyIndex(renderPassType: passType)
        let commandBuffer = self.commandPools[familyIndex]!.allocateCommandBuffer()
        
        let commandBufferResources = CommandBufferResources(device: self.device, commandBuffer: commandBuffer, commandPool: self, queueFamilyIndex: familyIndex)
        
        return commandBufferResources
    }

    public func reset(commandBuffer: VkCommandBuffer, queueFamilyIndex: Int, usedDescriptorSets descriptorSets: inout [VkDescriptorSet?]) {
        self.descriptorPool.freeDescriptorSets(&descriptorSets)

        self.commandPools[queueFamilyIndex]!.depositCommandBuffer(commandBuffer)

        // Periodically reset all resources to the pool to avoid fragmentation/over-allocation.
        let resetResources = resetCounter == (VulkanFrameCommandPool.resetThreshold - 1)

        guard self.needsReset else { return } // Only reset from the first CommandBufferResources deinit for this frame.
        defer { self.needsReset = false }

        defer { resetCounter = (resetCounter + 1) % VulkanFrameCommandPool.resetThreshold }

        for pool in self.commandPools {
            guard let pool = pool else { continue }
            vkResetCommandPool(self.device.vkDevice, pool.vkPool, resetResources ? VkCommandPoolResetFlags(VK_COMMAND_POOL_RESET_RELEASE_RESOURCES_BIT) : 0)
        }
    }
}

public final class VulkanCommandPool {

    let device : VulkanDevice
    let numInflightFrames : Int
    private let pools : [VulkanFrameCommandPool]
    private var currentFrameIndex = 0

    init(device: VulkanDevice, numInflightFrames: Int) {
        self.device = device
        self.numInflightFrames = numInflightFrames
        self.pools = (0..<numInflightFrames).map { _ in VulkanFrameCommandPool(device: device) }
    }
    
    public func allocateCommandBufferResources(passType: RenderPassType) -> CommandBufferResources {
        return self.pools[currentFrameIndex].allocateCommandBufferResources(passType: passType)
    }

    public func cycleFrames() {
        self.currentFrameIndex = (self.currentFrameIndex &+ 1) % self.numInflightFrames
    }
}

#endif // canImport(Vulkan)
