//
//  VkInstance.swift
//  VkRenderer
//
//  Created by Joseph Bennett on 1/01/18.
//

#if canImport(Vulkan)
import Vulkan
import FrameGraphCExtras

// public typealias VkCmdPushDescriptorSetKHRFunc = @convention(c) (VkCommandBuffer, VkPipelineBindPoint, VkPipelineLayout, UInt32, UInt32, UnsafePointer<VkWriteDescriptorSet>) -> Void
// public fileprivate(set) var vkCmdPushDescriptorSetKHR : VkCmdPushDescriptorSetKHRFunc! = nil

public struct VulkanVersion: CustomStringConvertible {
    var value : UInt32
    
    init(_ value: UInt32) {
        self.value = value
    }

    public init(major: Int, minor: Int, patch: Int) {
        self.value = (UInt32(major) << 22) | (UInt32(minor) << 12) | UInt32(patch)
    }

    public var major: Int {
        return Int(self.value >> 22)
    }

    public var minor: Int {
        return Int((self.value >> 12) & 0b11_1111_1111)
    }

    public var patch: Int {
        return Int(self.value & 0x0FFF)
    }

    static let apiVersion = VulkanVersion(major: 1, minor: 1, patch: 131)

    public var description: String {
        return "\(self.major).\(self.minor).\(self.patch)"
    }
}

public final class VulkanInstance {
    public let instance : VkInstance
    var debugCallback : VkDebugReportCallbackEXT? = nil

    static let validationLayers : [StaticString] = [
        "VK_LAYER_LUNARG_standard_validation"
    ]
    
    static func areLayersSupported(_ layers: [StaticString]) -> Bool {
        var layerCount : UInt32 = 0
        vkEnumerateInstanceLayerProperties(&layerCount, nil).check()
        
        var availableLayers = [VkLayerProperties](repeating: .init(), count: Int(layerCount))
        vkEnumerateInstanceLayerProperties(&layerCount, &availableLayers)

        for layerName in layers {
            let layerNameStr = layerName.description
            if !availableLayers.contains(where: { $0.layerNameStr == layerNameStr }) {
                return false
            }
        }
        
        return true
    }
    
    public init?(applicationName: String, applicationVersion: VulkanVersion, engineName: String, engineVersion: VulkanVersion) {
        
        var extensionsCount : UInt32 = 0
        if !vkEnumerateInstanceExtensionProperties(nil, &extensionsCount, nil).check(){
            print("Error occurred during instance extensions enumeration!")
            return nil
        }
        
        var availableExtensions = [VkExtensionProperties](repeating: .init(), count: Int(extensionsCount))
        if !vkEnumerateInstanceExtensionProperties(nil, &extensionsCount, &availableExtensions).check() {
            print("Error occurred during instance extensions enumeration!")
            return nil
        }
        
        var extensions: [String] = [
            VK_KHR_SURFACE_EXTENSION_NAME,
        ]
#if os(Windows)
        extensions.append(VK_KHR_WIN32_SURFACE_EXTENSION_NAME)
#endif
#if VK_USE_PLATFORM_XCB_KHR
        extensions.append(VK_KHR_XCB_SURFACE_EXTENSION_NAME)
#endif
#if os(Linux)
        extensions.append(VK_KHR_XLIB_SURFACE_EXTENSION_NAME)
#endif
        
        if _isDebugAssertConfiguration() {
            extensions.append(VK_EXT_DEBUG_REPORT_EXTENSION_NAME)
        }
        
        var extensionCStringPointers = [UnsafePointer<CChar>?]()
        extensionCStringPointers.reserveCapacity(extensions.count)
        
        let extensionsLength = extensions.reduce(0, { $0 + $1.utf8.count + 1 })
        let extensionBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: extensionsLength)
        extensionBuffer.initialize(repeating: 0, count: extensionsLength)
        var extensionCursor = extensionBuffer
        defer { extensionBuffer.deallocate() }

        for ext in extensions {
            guard  availableExtensions.contains(where: { $0.extensionNameStr == ext }) else {
                print("Could not find instance extension named \(ext)!")
                return nil
            }
            extensionCStringPointers.append(extensionCursor)
            for char in ext.utf8 {
                extensionCursor.pointee = CChar(char)
                extensionCursor += 1
            }
            extensionCursor += 1
        }

        var instance : VkInstance! = nil
        
        applicationName.withCString { applicationName in
            engineName.withCString { engineName in
                var applicationInfo = VkApplicationInfo()
                applicationInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO
                applicationInfo.pNext = nil
                applicationInfo.pEngineName = engineName
                applicationInfo.pApplicationName = applicationName
                applicationInfo.engineVersion = engineVersion.value
                applicationInfo.applicationVersion = applicationVersion.value
                applicationInfo.apiVersion = VulkanVersion.apiVersion.value
                
                withUnsafePointer(to: &applicationInfo) { applicationInfo in
                    var instanceCreateInfo = VkInstanceCreateInfo()
                    instanceCreateInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
                    instanceCreateInfo.pNext = nil
                    instanceCreateInfo.flags = 0
                    instanceCreateInfo.pApplicationInfo = applicationInfo
                    
                    var layerNames = [UnsafePointer<CChar>?]()
                    
                    if _isDebugAssertConfiguration() {
                        if !VulkanInstance.areLayersSupported(VulkanInstance.validationLayers) {
                            print("Vulkan validation layers are not supported.")
                        } else {
                            for layer in VulkanInstance.validationLayers {
                                layerNames.append(UnsafeRawPointer(layer.utf8Start).assumingMemoryBound(to: CChar.self))
                            }
                        }
                    }
                    
                    layerNames.withUnsafeBufferPointer { layerNames in
                        instanceCreateInfo.enabledLayerCount = UInt32(layerNames.count)
                        instanceCreateInfo.ppEnabledLayerNames = layerNames.baseAddress

                        extensionCStringPointers.withUnsafeBufferPointer { extensions in
                            instanceCreateInfo.ppEnabledExtensionNames = extensions.baseAddress
                            instanceCreateInfo.enabledExtensionCount = UInt32(extensions.count)
                            
                            if !vkCreateInstance(&instanceCreateInfo, nil, &instance).check() {
                                print("Could not create Vulkan instance!")
                            }

                        }
                    }
                }
            }
        }
        
        if instance == nil {
            return nil
        }

        self.instance = instance
        
        if _isDebugAssertConfiguration() {
            if let vkCreateDebugReportCallbackEXT = unsafeBitCast(vkGetInstanceProcAddr(instance, "vkCreateDebugReportCallbackEXT"), to: PFN_vkCreateDebugReportCallbackEXT?.self) {
                
                /* Setup callback creation information */
                var callbackCreateInfo = VkDebugReportCallbackCreateInfoEXT()
                callbackCreateInfo.sType = VK_STRUCTURE_TYPE_DEBUG_REPORT_CREATE_INFO_EXT
                callbackCreateInfo.pNext = nil
                callbackCreateInfo.flags = ([VK_DEBUG_REPORT_ERROR_BIT_EXT,
                                             VK_DEBUG_REPORT_WARNING_BIT_EXT,
                                             VK_DEBUG_REPORT_PERFORMANCE_WARNING_BIT_EXT,
                                             VK_DEBUG_REPORT_DEBUG_BIT_EXT,
                                            // VK_DEBUG_REPORT_INFORMATION_BIT_EXT
                    ] as VkDebugReportFlagBitsEXT).rawValue
                
                callbackCreateInfo.pfnCallback = { flags, objectType, object,  location, messageCode, pLayerPrefix, pMessage, pUserData in
                    print(String(cString: pMessage!))
                    return VkBool32(VK_FALSE)
                }
                callbackCreateInfo.pUserData = nil
                
                /* Register the callback */
                if !vkCreateDebugReportCallbackEXT(instance, &callbackCreateInfo, nil, &self.debugCallback).check() {
                    print("Could not register Vulkan debug report callback.")
                } else {
                    print("Registered Vulkan debug callback.")
                }
            } else {
                print("Could not find Vulkan debug report callback.")
            }
        }
        
        self.registerExtensionFunctions()
    }
    
    deinit {
        if let debugCallback = self.debugCallback, let vkDestroyDebugReportCallbackEXT = unsafeBitCast(vkGetInstanceProcAddr(instance, "vkDestroyDebugReportCallbackEXT"), to: PFN_vkDestroyDebugReportCallbackEXT?.self) {
            vkDestroyDebugReportCallbackEXT(instance, debugCallback, nil)
        }
        vkDestroyInstance(instance, nil)
    }

    func registerExtensionFunctions() {
        // vkCmdPushDescriptorSetKHR = unsafeBitCast(vkGetInstanceProcAddr(instance, "vkCmdPushDescriptorSetKHR"), to: VkCmdPushDescriptorSetKHRFunc.self)
    }
    
    public func copyAllDevices() -> [VulkanPhysicalDevice] {
        var deviceCount = 0 as UInt32
        vkEnumeratePhysicalDevices(self.instance, &deviceCount, nil)
        
        if deviceCount == 0 {
            fatalError("Failed to find hardware with Vulkan support.")
        }
        
        var devices = [VkPhysicalDevice?](repeating: nil, count: Int(deviceCount))
        vkEnumeratePhysicalDevices(self.instance, &deviceCount, &devices)
        
        return devices.map { VulkanPhysicalDevice(device: $0!) }
    }
    
    public func createSystemDefaultDevice() -> VulkanPhysicalDevice? {
        let devices = self.copyAllDevices()
        
        let properties = devices.map { device -> VkPhysicalDeviceProperties in
            var properties = VkPhysicalDeviceProperties()
            vkGetPhysicalDeviceProperties(device.vkDevice, &properties)
            return properties
        }

        if let discreteGPUIndex = properties.firstIndex(where: { $0.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU }) {
            return devices[discreteGPUIndex]
        }

        if let integratedGPUIndex = properties.firstIndex(where: { $0.deviceType == VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU }) {
            return devices[integratedGPUIndex]
        }

        return devices.first
    }
}

#endif // canImport(Vulkan)
