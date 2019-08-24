//
//  Vulkan.swift
//  VkRenderer
//
//  Created by Joseph Bennett on 1/01/18.
//

#if canImport(Vulkan)
import Vulkan
import Foundation
import FrameGraphCExtras

extension VkLayerProperties {
    var layerNameStr : String {
        var layerName = self.layerName
        return withUnsafePointer(to: &layerName.0) {
            return String(cString: $0)
        }
    }
}

extension VkExtensionProperties {
    var extensionNameStr : String {
        var extensionName = self.extensionName
        return withUnsafePointer(to: &extensionName.0) {
            return String(cString: $0)
        }
    }
}

func vkMakeVersion(major: UInt32, minor: UInt32, patch: UInt32) -> UInt32 {
    return major << 22 | minor << 12 | patch
}


extension VkResult {
    @inlinable
    public func check(line: Int = #line, function: String = #function) {
        assert(self == VK_SUCCESS, "Vulkan command failed on line \(line) of function \(function) with code: \(self)")
    }
}

public final class Vulkan {
    
    public static let maxDescriptorSets = 16
    
    static func isLayerSupported(_ layer: String, supportedLayers: [VkLayerProperties]) -> Bool {
        return supportedLayers.map { $0.layerNameStr }.contains(layer)
    }
    
    static func enableLayerIfPresent(layerName: String, supportedLayers: [VkLayerProperties], requiredLayers: inout [String]) {
        if isLayerSupported(layerName, supportedLayers: supportedLayers) {
            requiredLayers.append(layerName)
        } else {
            print("Can't enable requested Vulkan layer \(layerName). Something bad might happen. Or not, depends on the layer.")
        }
    }
    
    static func enumerateInstanceLayerProperties() -> [VkLayerProperties] {
        var layerCount = 0 as UInt32
        vkEnumerateInstanceLayerProperties(&layerCount, nil)
        var layerProperties = [VkLayerProperties](repeating: VkLayerProperties(), count: Int(layerCount))
        vkEnumerateInstanceLayerProperties(&layerCount, &layerProperties)
        
        return layerProperties
    }
    
    static func enumerateInstanceExtensions() -> [VkExtensionProperties] {
        // Enumerate implicitly available extensions. The debug layers above just have VK_EXT_debug_report
        var extensionCount = 0 as UInt32
        vkEnumerateInstanceExtensionProperties(nil, &extensionCount, nil)
        var supportedExtensions = [VkExtensionProperties](repeating: VkExtensionProperties(), count: Int(extensionCount))
        vkEnumerateInstanceExtensionProperties(nil, &extensionCount, &supportedExtensions)
        
        return supportedExtensions
    }
}

#endif // canImport(Vulkan)
