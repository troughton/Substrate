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
        self = withUnsafeBytes(of: cStringTuple) {
            return String(cString: $0.bindMemory(to: CChar.self))
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

extension VmaAllocationCreateInfo {
    init(storageMode: StorageMode, cacheMode: CPUCacheMode) {
        self.init()
        if storageMode == .private {
            self.preferredFlags = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT.rawValue
        } else {
            self.requiredFlags = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT.rawValue
            if storageMode == .shared {
                self.requiredFlags |= VK_MEMORY_PROPERTY_HOST_COHERENT_BIT.rawValue
            } else if storageMode == .managed {
                self.preferredFlags |= VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT.rawValue
            }
            if cacheMode == .defaultCache {
                self.preferredFlags |= VK_MEMORY_PROPERTY_HOST_CACHED_BIT.rawValue
            }
            self.flags = VMA_ALLOCATION_CREATE_MAPPED_BIT.rawValue
        }
    }
}

#endif // canImport(Vulkan)
