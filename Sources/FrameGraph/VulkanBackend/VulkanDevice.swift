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

extension QueueCapabilities {
    init(_ family: QueueFamily) {
        switch family {
        case .graphics:
            self = .render
        case .compute:
            self = .compute
        case .copy:
            self = .blit
        case .present:
            self = .present
        }
    }
}

public final class VulkanPhysicalDevice {
    public let vkDevice : VkPhysicalDevice
    public let queueCapabilities : [QueueCapabilities]
    let queueFamilies: [VkQueueFamilyProperties]
    
    init(device: VkPhysicalDevice) {
        self.vkDevice = device
        
        var queueFamilyCount = 0 as UInt32
        vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, nil)
        
        var queueFamilies = [VkQueueFamilyProperties](repeating: VkQueueFamilyProperties(), count: Int(queueFamilyCount))
        vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, &queueFamilies)
        self.queueFamilies = queueFamilies
        
        self.queueCapabilities = queueFamilies.enumerated().map { (i, queueFamily) in
            var capabilities: QueueCapabilities = []
            let queueFlags = VkQueueFlagBits(queueFamily.queueFlags)
            if queueFlags.contains(VK_QUEUE_GRAPHICS_BIT) {
                capabilities.insert([.render, .blit])
            }
            if queueFlags.contains(VK_QUEUE_COMPUTE_BIT) {
                capabilities.insert([.compute, .blit])
            }
            if queueFlags.contains(VK_QUEUE_TRANSFER_BIT) {
                capabilities.insert(.blit)
            }
            
            // var presentSupport = false as VkBool32
            // vkGetPhysicalDeviceSurfaceSupportKHR(device, UInt32(i), surface, &presentSupport)
            
            if queueFlags.contains(VK_QUEUE_GRAPHICS_BIT) {
                // FIXME: presentation support may vary between devices.
                capabilities.insert(.present)
            }
            
            return capabilities
        }
    }
}

public final class VulkanDevice {
    
    static let deviceExtensions : [StaticString] = [
        "VK_KHR_swapchain", // VK_KHR_SWAPCHAIN_EXTENSION_NAME
    ]
    
    public let physicalDevice : VulkanPhysicalDevice
    let vkDevice : VkDevice
    
    private(set) var queues : [VulkanDeviceQueue] = []
    
    init?(physicalDevice: VulkanPhysicalDevice) {
        self.physicalDevice = physicalDevice
        
        // Strategy: one render queue, as many async compute queues as we can get, and a couple of copy queues.
        
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
            
            var deviceFeatures = VkPhysicalDeviceFeatures()
            deviceFeatures.independentBlend = VkBool32(VK_TRUE)
            deviceFeatures.depthClamp = VkBool32(VK_TRUE)
            deviceFeatures.depthBiasClamp = VkBool32(VK_TRUE)
            
            var createInfo = VkDeviceCreateInfo()
            createInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
            
            queueCreateInfos.withUnsafeBufferPointer { queueCreateInfos in
                createInfo.queueCreateInfoCount = UInt32(queueCreateInfos.count)
                createInfo.pQueueCreateInfos = queueCreateInfos.baseAddress
                
                withUnsafePointer(to: deviceFeatures) { deviceFeatures in
                    createInfo.pEnabledFeatures = deviceFeatures;
                                   
                    let extensions = VulkanDevice.deviceExtensions.map { ext -> UnsafePointer<CChar>? in
                        return UnsafeRawPointer(ext.utf8Start).assumingMemoryBound(to: CChar.self)
                    }
                    
                    extensions.withUnsafeBufferPointer { extensions in
                        createInfo.enabledExtensionCount = UInt32(extensions.count)
                        createInfo.ppEnabledExtensionNames = extensions.baseAddress
                        
                        createInfo.enabledLayerCount = 0
                        
                        if !vkCreateDevice(physicalDevice.vkDevice, &createInfo, nil, &device).check() {
                            print("Failed to create Vulkan logical device!")
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
    
    public func queueFamilyIndex(capabilities: QueueCapabilities, requiredCapability: QueueCapabilities) -> Int {
        assert(capabilities.contains(requiredCapability))
        
        // Check for an exact match first
        if let familyIndex = self.physicalDevice.queueCapabilities.firstIndex(of: capabilities) {
            return familyIndex
        }
        
        // Then, check for a superset.
        if let familyIndex = self.physicalDevice.queueCapabilities.firstIndex(where: { $0.contains(capabilities) }) {
            return familyIndex
        }
        
        // Check for an exact match
        if let familyIndex = self.physicalDevice.queueCapabilities.firstIndex(of: requiredCapability) {
            return familyIndex
        }
        
        // Check for a superset.
        if let familyIndex = self.physicalDevice.queueCapabilities.firstIndex(where: { $0.contains(requiredCapability) }) {
            return familyIndex
        }
        
        fatalError("No Vulkan queue supports the capability \(requiredCapability).")
    }
    
    public func deviceQueue(capabilities: QueueCapabilities, requiredCapability: QueueCapabilities) -> VulkanDeviceQueue {
        let familyIndex = self.queueFamilyIndex(capabilities: capabilities, requiredCapability: requiredCapability)
        return self.queues.first(where: { $0.familyIndex == familyIndex })!
    }
}

#endif // canImport(Vulkan)
