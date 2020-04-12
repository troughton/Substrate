//
//  SynchronisationPools.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 17/01/18.
//

#if canImport(Vulkan)
import Vulkan
import Dispatch
import FrameGraphCExtras

final class VulkanEventPool {
    
    class QueuePool {
        let device: VkDevice
        private var unusedEvents = [VkEvent]()
        private var indexedEvents = [Int : VkEvent]()
        
        init(device: VkDevice) {
            self.device = device
        }
        
        public func collectEvent(id: Int) -> VkEvent {
            assert(self.indexedEvents[id] == nil)
            
            var event : VkEvent? = nil
            event = self.unusedEvents.popLast()
            
            if event == nil {
                var createInfo = VkEventCreateInfo(sType: VK_STRUCTURE_TYPE_EVENT_CREATE_INFO, pNext: nil, flags: 0)
                vkCreateEvent(self.device, &createInfo, nil, &event)
            }
            
            self.indexedEvents[id] = event
            return event!
        }
        
        public func depositEvent(id: Int) -> VkEvent {
            let event = self.indexedEvents.removeValue(forKey: id)!
            self.unusedEvents.append(event)
            return event
        }
        
        deinit {
            for event in self.unusedEvents {
                vkDestroyEvent(self.device, event, nil)
            }
            
            for event in self.indexedEvents.values {
                vkDestroyEvent(self.device, event, nil)
            }
        }
    }
    
    let device : VulkanDevice
    
    let queuePools : [QueuePool]
    
    init(device: VulkanDevice) {
        self.device = device
        
        let queueIndices = device.physicalDevice.queueFamilyIndices
        
        var queuePools = [QueuePool]()
        
        let graphicsPool = QueuePool(device: device.vkDevice)
        queuePools.append(graphicsPool)
        
        let computePool = queueIndices.compute == queueIndices.copy ? graphicsPool : QueuePool(device: device.vkDevice)
        queuePools.append(computePool)
        
        let copyPool : QueuePool
        if queueIndices.copy == queueIndices.graphics {
            copyPool = graphicsPool
        } else if queueIndices.copy == queueIndices.compute {
            copyPool = computePool
        } else {
            copyPool = QueuePool(device: device.vkDevice)
        }
        queuePools.append(copyPool)
        
        self.queuePools = queuePools
    }
    
    public func collectEvent(id: Int, queue: QueueFamily) -> VkEvent {
        return self.poolForQueue(queue).collectEvent(id: id)
    }
    
    public func depositEvent(id: Int, queue: QueueFamily) -> VkEvent {
        return self.poolForQueue(queue).depositEvent(id: id)
    }
    
    public func poolForQueue(_ queue: QueueFamily) -> QueuePool {
        return self.queuePools[queue.rawValue]
    }
}

final class VulkanSemaphorePool {
    let device : VulkanDevice
    
    private var unusedSemaphores = [VkSemaphore]()
    private var indexedSemaphores = [Int : VkSemaphore]()
    
    init(device: VulkanDevice) {
        self.device = device
    }
    
    public func allocateSemaphore(id: Int) -> VkSemaphore {
        let semaphore = self.allocateSemaphore()
        
        self.indexedSemaphores[id] = semaphore
        return semaphore
    }
    
    public func allocateSemaphore() -> VkSemaphore {
        var semaphore : VkSemaphore? = nil
        semaphore = self.unusedSemaphores.popLast()
        
        if semaphore == nil {
            var createInfo = VkSemaphoreCreateInfo(sType: VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO, pNext: nil, flags: 0)
            vkCreateSemaphore(self.device.vkDevice, &createInfo, nil, &semaphore)
        }
        
        return semaphore!
    }
    
    public func collectSemaphore(id: Int) -> VkSemaphore {
        return self.indexedSemaphores[id]!
    }
    
    public func depositSemaphore(_ semaphore: VkSemaphore) {
        self.unusedSemaphores.append(semaphore)
    }
    
    deinit {
        for semaphore in self.unusedSemaphores {
            vkDestroySemaphore(self.device.vkDevice, semaphore, nil)
        }
        for semaphore in self.indexedSemaphores.values {
            vkDestroySemaphore(self.device.vkDevice, semaphore, nil)
        }
    }
}

#endif // canImport(Vulkan)
