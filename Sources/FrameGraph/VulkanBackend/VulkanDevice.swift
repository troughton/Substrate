//
//  VulkanDevice.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 6/01/18.
//

#if canImport(Vulkan)
import Vulkan
import FrameGraphCExtras

enum QueueFamily : Int {
    case graphics
    case compute
    case copy
    case present
}

public final class VulkanPhysicalDevice {
    public let vkDevice : VkPhysicalDevice
    let queueFamilies: [VkQueueFamilyProperties]
    
    init(device: VkPhysicalDevice) {
        self.vkDevice = device
        
        var queueFamilyCount = 0 as UInt32
        vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, nil)
        
        var queueFamilies = [VkQueueFamilyProperties](repeating: VkQueueFamilyProperties(), count: Int(queueFamilyCount))
        vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, &queueFamilies)
        
        for i in queueFamilies.indices {
            if VkQueueFlagBits(queueFamilies[i].queueFlags).intersection([VK_QUEUE_GRAPHICS_BIT, VK_QUEUE_COMPUTE_BIT]) != [] {
                queueFamilies[i].queueFlags |= VK_QUEUE_TRANSFER_BIT.rawValue // All queues support transfer operations.
            }
        }
        
        self.queueFamilies = queueFamilies
    }
    
    public func supportsPixelFormat(_ format: PixelFormat) -> Bool {
        guard let vkFormat = VkFormat(pixelFormat: format) else { return false }
        var formatProperties = VkFormatProperties()
        vkGetPhysicalDeviceFormatProperties(self.vkDevice, vkFormat, &formatProperties)
        return formatProperties.linearTilingFeatures != 0 || formatProperties.optimalTilingFeatures != 0
    }
}

public final class VulkanDevice {
    
    static let deviceExtensions : [StaticString] = [
        "VK_KHR_swapchain", // VK_KHR_SWAPCHAIN_EXTENSION_NAME
        "VK_KHR_timeline_semaphore"
    ]
    
    public let physicalDevice : VulkanPhysicalDevice
    let vkDevice : VkDevice
    
    private(set) var queues : [VulkanDeviceQueue] = []
    
    init?(physicalDevice: VulkanPhysicalDevice) {
        self.physicalDevice = physicalDevice

        do {
            var properties = VkPhysicalDeviceProperties()
            vkGetPhysicalDeviceProperties(physicalDevice.vkDevice, &properties)
            print("Using VkPhysicalDevice \(String(cStringTuple: properties.deviceName)) with API version \(VulkanVersion(properties.apiVersion)) and driver version \(VulkanVersion(properties.driverVersion))")
        }
        // Strategy: one render queue, as many async compute queues as we can get, and a couple of copy queues.
        
        // Enable all features apart from robust buffer access by default.
        var features = VkPhysicalDeviceFeatures2()
        features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2
        var features11 = VkPhysicalDeviceVulkan11Features()
        features11.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES
        var features12 = VkPhysicalDeviceVulkan12Features()
        features12.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES
        withUnsafeMutableBytes(of: &features12) { features12 in
            features11.pNext = features12.baseAddress
            withUnsafeMutableBytes(of: &features11) { features11 in
                features.pNext = features11.baseAddress
                vkGetPhysicalDeviceFeatures2(physicalDevice.vkDevice, &features)
            }
        }
        features.features.robustBufferAccess = VkBool32(VK_FALSE)
        
        var activeQueues = [(familyIndex: Int, queueIndex: Int)]()
        
        var device : VkDevice? = nil
        let queuePriority = 1.0 as Float
        withUnsafePointer(to: queuePriority) { queuePriorityPtr in
            
            var queueCreateInfos = [VkDeviceQueueCreateInfo]()
            
            var hasRenderQueue = false
            
            for (i, queueFamily) in physicalDevice.queueFamilies.enumerated() {
                var queueCreateInfo = VkDeviceQueueCreateInfo()
                queueCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO
                queueCreateInfo.queueFamilyIndex = UInt32(i)
                
                queueCreateInfo.pQueuePriorities = queuePriorityPtr
                queueCreateInfo.queueCount = 1
                
                let queueFlags = VkQueueFlagBits(queueFamily.queueFlags)
                if !hasRenderQueue, queueFlags.contains(VK_QUEUE_GRAPHICS_BIT) {
                    hasRenderQueue = true
                    queueCreateInfos.append(queueCreateInfo)
                    activeQueues.append((i, 0))
                } else if !queueFlags.contains(VK_QUEUE_GRAPHICS_BIT) {
                    for j in 0..<queueFamily.queueCount {
                        queueCreateInfos.append(queueCreateInfo)
                        activeQueues.append((i, Int(j)))
                    }
                }
            }
            
            var createInfo = VkDeviceCreateInfo()
            createInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
            
            queueCreateInfos.withUnsafeBufferPointer { queueCreateInfos in
                createInfo.queueCreateInfoCount = UInt32(queueCreateInfos.count)
                createInfo.pQueueCreateInfos = queueCreateInfos.baseAddress
                
                
                let extensions = VulkanDevice.deviceExtensions.map { ext -> UnsafePointer<CChar>? in
                    return UnsafeRawPointer(ext.utf8Start).assumingMemoryBound(to: CChar.self)
                }
                
                extensions.withUnsafeBufferPointer { extensions in
                    createInfo.enabledExtensionCount = UInt32(extensions.count)
                    createInfo.ppEnabledExtensionNames = extensions.baseAddress
                    
                    createInfo.enabledLayerCount = 0
                    
                    withUnsafeMutableBytes(of: &features12) { features12 in
                        features11.pNext = features12.baseAddress
                        withUnsafeMutableBytes(of: &features11) { features11 in
                            features.pNext = features11.baseAddress
                            
                            withUnsafeBytes(of: features) { deviceFeatures in
                                createInfo.pNext = deviceFeatures.baseAddress
                                
                                if !vkCreateDevice(physicalDevice.vkDevice, &createInfo, nil, &device).check() {
                                    print("Failed to create Vulkan logical device!")
                                }
                            }
                        }
                    }
                }
            }
        }
        
        if device == nil { return nil }
        self.vkDevice = device!
        
        let queues = activeQueues.map { (familyIndex, queueIndex) -> VulkanDeviceQueue in
            return VulkanDeviceQueue(device: self, familyIndex: familyIndex, queueIndex: queueIndex)
        }
        
        self.queues = queues
    }
    
    deinit {
        vkDestroyDevice(self.vkDevice, nil)
    }
    
    public func queueFamilyIndices(containingAllOf queueFlags: VkQueueFlagBits) -> [UInt32] {
        return self.physicalDevice.queueFamilies.enumerated().compactMap { (i, queue) in
            if VkQueueFlagBits(queue.queueFlags).contains(queueFlags) {
                return UInt32(i)
            } else {
                return nil
            }
        }
    }
    
    public func queueFamilyIndices(matchingAnyOf queueFlags: VkQueueFlagBits) -> [UInt32] {
        var indices = [UInt32]()
        for (i, queueFamily) in self.physicalDevice.queueFamilies.enumerated() {
            if VkQueueFlagBits(queueFamily.queueFlags).intersection(queueFlags) != [] {
                indices.append(UInt32(i))
            }
        }
        return indices
    }

    public func presentQueue(surface: VkSurfaceKHR) -> VulkanDeviceQueue? {
        for familyIndex in 0..<self.queues.count {
            var supported: VkBool32 = 0
            vkGetPhysicalDeviceSurfaceSupportKHR(self.physicalDevice.vkDevice, UInt32(familyIndex), surface, &supported).check()
            if supported != VK_FALSE {
                return self.queues.first(where: { $0.familyIndex == familyIndex })
            }
        }
        return nil
    }
}

#endif // canImport(Vulkan)
