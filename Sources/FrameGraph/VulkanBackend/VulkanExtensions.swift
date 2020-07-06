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


extension VkResult {
    @discardableResult
    @inlinable
    public func check(line: Int = #line, function: String = #function) -> Bool {
        assert(self == VK_SUCCESS, "Vulkan command failed on line \(line) of function \(function) with code: \(self)")
        return self == VK_SUCCESS
    }
}

#endif // canImport(Vulkan)
