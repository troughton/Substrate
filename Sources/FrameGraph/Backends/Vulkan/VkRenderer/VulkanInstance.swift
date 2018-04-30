//
//  VkInstance.swift
//  VkRenderer
//
//  Created by Joseph Bennett on 1/01/18.
//

import CVkRenderer

// public typealias VkCmdPushDescriptorSetKHRFunc = @convention(c) (VkCommandBuffer, VkPipelineBindPoint, VkPipelineLayout, UInt32, UInt32, UnsafePointer<VkWriteDescriptorSet>) -> Void
// public fileprivate(set) var vkCmdPushDescriptorSetKHR : VkCmdPushDescriptorSetKHRFunc! = nil

public final class VulkanInstance {
    public let instance : VkInstance

    public init?() {
        let instance = VkInstanceCreate()
        
        if instance == nil {
            return nil
        }
        self.instance = instance!

        self.registerExtensionFunctions()
    }
    
    deinit {
        vkDestroyInstance(instance, nil)
    }

    func registerExtensionFunctions() {
        // vkCmdPushDescriptorSetKHR = unsafeBitCast(vkGetInstanceProcAddr(instance, "vkCmdPushDescriptorSetKHR"), to: VkCmdPushDescriptorSetKHRFunc.self)
    }
    
    public func copyAllDevices(surface: VkSurfaceKHR) -> [VulkanPhysicalDevice] {
        var deviceCount = 0 as UInt32
        vkEnumeratePhysicalDevices(self.instance, &deviceCount, nil)
        
        if deviceCount == 0 {
            fatalError("Failed to find hardware with Vulkan support.")
        }
        
        var devices = [VkPhysicalDevice?](repeating: nil, count: Int(deviceCount))
        vkEnumeratePhysicalDevices(self.instance, &deviceCount, &devices)
        
        return devices.map { VulkanPhysicalDevice(device: $0!, surface: surface) }
    }
    
    public func createSystemDefaultDevice(surface: VkSurfaceKHR) -> VulkanPhysicalDevice? {
        return self.copyAllDevices(surface: surface).first
    }
}


