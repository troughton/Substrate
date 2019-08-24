//
//  VulkanDevice.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 6/01/18.
//

#if canImport(Vulkan)
import Vulkan
import FrameGraphCExtras

public enum QueueFamily : Int {
    case graphics
    case compute
    case copy
    case present
}

public struct QueueFamilies : OptionSet {
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    public init(_ family: QueueFamily) {
        switch family {
        case .graphics:
            self = .graphics
        case .compute:
            self = .compute
        case .copy:
            self = .copy
        case .present:
            self = .present
        }
    }
    
    public static let graphics = QueueFamilies(rawValue: 1 << 0)
    public static let compute = QueueFamilies(rawValue: 1 << 1)
    public static let copy = QueueFamilies(rawValue: 1 << 2)
    public static let present = QueueFamilies(rawValue: 1 << 3)
    
    public static var all : QueueFamilies = [.graphics, .compute, .copy, .present]
    
    public func isSingleQueue(indices: QueueFamilyIndices) -> Bool {
        var index : Int? = nil
        if self.contains(.graphics) {
            index = indices.graphics
        }
        if self.contains(.compute) {
            if index != nil, indices.compute != index {
                return false
            } else {
                index = indices.compute
            }
        }
        if self.contains(.copy) {
            if index != nil, indices.copy != index {
                return false
            } else {
                index = indices.copy
            }
        }
        if self.contains(.present) {
            return false // FIXME: what should we do here?
        }
        return true
        
    }
}

public struct QueueFamilyIndices {
    public let graphics : Int
    public let compute : Int
    public let copy : Int
    public let present : Int
    
    fileprivate init(device: VkPhysicalDevice, surface: VkSurfaceKHR) {
        
        var queueFamilyCount = 0 as UInt32
        vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, nil)
        
        var queueFamilies = [VkQueueFamilyProperties](repeating: VkQueueFamilyProperties(), count: Int(queueFamilyCount))
        vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, &queueFamilies)
        
        var graphicsFamily = -1
        var computeFamily = -1
        var transferFamily = -1
        var presentFamily = -1
        
        for (i, queueFamily) in queueFamilies.enumerated() {
            if queueFamily.queueCount == 0 {
                continue
            }
            
            if VkQueueFlagBits(queueFamily.queueFlags).contains(VK_QUEUE_GRAPHICS_BIT) {
                graphicsFamily = i
            }
            
            if VkQueueFlagBits(queueFamily.queueFlags).contains(VK_QUEUE_COMPUTE_BIT) {
                computeFamily = i
            }
            
            if VkQueueFlagBits(queueFamily.queueFlags).contains(VK_QUEUE_TRANSFER_BIT) {
                transferFamily = i
            }
            
            var presentSupport = false as VkBool32
            vkGetPhysicalDeviceSurfaceSupportKHR(device, UInt32(i), surface, &presentSupport)
            
            if presentSupport != false {
                presentFamily = i
            }
            
            if graphicsFamily != -1 && computeFamily != -1 && presentFamily != -1 {
                break
            }
        }
        
        if transferFamily == -1 { // Transfer family is optional as all graphics/compute queues implicitly support it.
            transferFamily = graphicsFamily
        }
        
        self.graphics = graphicsFamily
        self.compute = computeFamily
        self.copy = transferFamily
        self.present = presentFamily
    }
}

public final class VulkanPhysicalDevice {
    public let vkDevice : VkPhysicalDevice
    public let queueFamilyIndices : QueueFamilyIndices
    
    init(device: VkPhysicalDevice, surface: VkSurfaceKHR) {
        self.vkDevice = device
        self.queueFamilyIndices = QueueFamilyIndices(device: device, surface: surface)
    }
    
    public func presentQueueIndex(surface: VkSurfaceKHR) -> Int? {
        
        var queueFamilyCount = 0 as UInt32
        vkGetPhysicalDeviceQueueFamilyProperties(self.vkDevice, &queueFamilyCount, nil)
        
        var queueFamilies = [VkQueueFamilyProperties](repeating: VkQueueFamilyProperties(), count: Int(queueFamilyCount))
        vkGetPhysicalDeviceQueueFamilyProperties(self.vkDevice, &queueFamilyCount, &queueFamilies)
        
        var bestIndex : Int? = nil
        
        for (i, queueFamily) in queueFamilies.enumerated() {
        
            var presentSupport = false as VkBool32
            vkGetPhysicalDeviceSurfaceSupportKHR(self.vkDevice, UInt32(i), surface, &presentSupport)
        
            if queueFamily.queueCount > 0 && (presentSupport != false) {
                if i == self.queueFamilyIndices.graphics { return i }
                if bestIndex == nil { bestIndex = i }
            }
        }

        return nil
    }
    
    public func queueFamilyIndices(for families: QueueFamilies) -> [UInt32] {
        var indices = Set<Int>()
        if families.contains(.graphics) {
            indices.insert(self.queueFamilyIndices.graphics)
        }
        if families.contains(.compute) {
            indices.insert(self.queueFamilyIndices.compute)
        }
        if families.contains(.copy) {
            indices.insert(self.queueFamilyIndices.copy)
        }
        if families.contains(.present) {
            indices.insert(self.queueFamilyIndices.present)
        }
        return indices.map { UInt32($0) }
    }
    
    public func queueFamilyIndex(renderPassType: RenderPassType) -> Int {
        switch renderPassType {
        case .draw:
            return self.queueFamilyIndices.graphics
        case .compute, .external:
            return self.queueFamilyIndices.compute
        case .blit:
            return self.queueFamilyIndices.copy
        case .cpu:
            fatalError()
        }
    }
}

public final class VulkanDevice {
    public let physicalDevice : VulkanPhysicalDevice
    let vkDevice : VkDevice
    
    private(set) var eventPool : VulkanEventPool! = nil
    private(set) var semaphorePool : VulkanSemaphorePool! = nil
    private(set) var fencePool : VulkanFencePool! = nil
    
    private(set) var queues : [VulkanQueue] = []
    
    init(physicalDevice: VulkanPhysicalDevice) {
        self.physicalDevice = physicalDevice
        
        let queueIndicesArray = physicalDevice.queueFamilyIndices(for: [.graphics, .compute, .copy])
        
        self.vkDevice = queueIndicesArray.withUnsafeBufferPointer { queueIndices in
            return VkDeviceCreate(physicalDevice.vkDevice, queueIndices.baseAddress, queueIndices.count)
        }
        
        self.eventPool = VulkanEventPool(device: self)
        self.semaphorePool = VulkanSemaphorePool(device: self)
        self.fencePool = VulkanFencePool(device: self)
        
        let queueIndices = physicalDevice.queueFamilyIndices
        
        var queues = [VulkanQueue]()
        let graphicsQueue = VulkanQueue(device: self, queueFamilies: .graphics)
        queues.append(graphicsQueue)
        
        let computeQueue = queueIndices.compute == queueIndices.copy ? graphicsQueue : VulkanQueue(device: self, queueFamilies: .compute)
        queues.append(computeQueue)
        
        let copyQueue : VulkanQueue
        if queueIndices.copy == queueIndices.graphics {
            copyQueue = graphicsQueue
        } else if queueIndices.copy == queueIndices.compute {
            copyQueue = computeQueue
        } else {
            copyQueue = VulkanQueue(device: self, queueFamilies: .copy)
        }
        queues.append(copyQueue)
        
        self.queues = queues
    }
    
    public func queueForFamily(_ queue: QueueFamily) -> VulkanQueue {
        return self.queues[queue.rawValue]
    }
    
    deinit {
        vkDestroyDevice(self.vkDevice, nil)
    }
}

#endif // canImport(Vulkan)
