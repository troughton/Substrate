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

extension String {
    init<T>(cStringTuple: T) {
        self = withUnsafePointer(to: cStringTuple) {
            return $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size / MemoryLayout<CChar>.stride) {
                return String(cString: $0)
            }
        }
    }
}

extension VkLayerProperties {
    var layerNameStr : String {
        return String(cStringTuple: self.layerName)
    }
}

extension VkExtensionProperties {
    var extensionNameStr : String {
        return String(cStringTuple: self.extensionName)
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
