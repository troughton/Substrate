//
//  VulkanBuffer.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 6/01/18.
//

import SwiftFrameGraph
// import CVkRenderer
import CVkRenderer

struct VulkanBufferDescriptor : Equatable {
    var flags : VkBufferCreateFlags
    var size : VkDeviceSize
    var usageFlags : VkBufferUsageFlagBits
    var sharingMode : VulkanSharingMode
    
    init(_ descriptor: BufferDescriptor, usage: VkBufferUsageFlagBits, sharingMode: VulkanSharingMode) {
        assert(!usage.isEmpty, "Usage for buffer with descriptor \(descriptor) must not be empty.")

        self.flags = 0
        self.size = VkDeviceSize(descriptor.length)
        self.usageFlags = usage
        self.sharingMode = sharingMode
    }
    
    func withBufferCreateInfo(device: VulkanDevice, withInfo: (VkBufferCreateInfo) -> Void) {
        var createInfo = VkBufferCreateInfo()
        createInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO
        createInfo.flags = self.flags
        createInfo.size = self.size
        createInfo.flags = 0
        createInfo.usage = VkBufferCreateFlags(self.usageFlags)
        
        switch self.sharingMode {
        case .concurrent(let queueFamilies):
            let queueIndices = device.physicalDevice.queueFamilyIndices(for: queueFamilies)
            
            if queueIndices.count == 1 {
                fallthrough
            } else {
                createInfo.sharingMode = VK_SHARING_MODE_CONCURRENT
                queueIndices.withUnsafeBufferPointer { queueIndices in
                    createInfo.queueFamilyIndexCount = UInt32(queueIndices.count)
                    createInfo.pQueueFamilyIndices = queueIndices.baseAddress
                    withInfo(createInfo)
                }
            }
        case .exclusive:
            createInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE
            withInfo(createInfo)
        }
    }
}

class VulkanBuffer {
    let device : VulkanDevice
    let vkBuffer : VkBuffer
    let allocator : VmaAllocator
    let allocation : VmaAllocation
    let allocationInfo : VmaAllocationInfo
    let descriptor : VulkanBufferDescriptor
    
    var waitSemaphore : ResourceSemaphore? = nil
    
    var hasBeenHostUpdated = false
    
    init(device: VulkanDevice, buffer: VkBuffer, allocator: VmaAllocator, allocation: VmaAllocation, allocationInfo: VmaAllocationInfo, descriptor: VulkanBufferDescriptor) {
        self.device = device
        self.vkBuffer = buffer
        self.allocator = allocator
        self.allocation = allocation
        self.allocationInfo = allocationInfo
        self.descriptor = descriptor
    }
    
    func map(range: Range<Int>) -> UnsafeMutableRawPointer {
        var data : UnsafeMutableRawPointer? = nil
        vmaMapMemory(self.allocator, self.allocation, &data).check()
        self.hasBeenHostUpdated = true
        return data! + range.lowerBound
    }
    
    func unmapMemory(range: Range<Int>) {

        var memFlags = VkMemoryPropertyFlags()
        vmaGetMemoryTypeProperties(self.allocator, self.allocationInfo.memoryType, &memFlags);
        if !VkMemoryPropertyFlagBits(memFlags).contains(VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) {
            var memRange = VkMappedMemoryRange()
            memRange.sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE
            memRange.memory = self.allocationInfo.deviceMemory
            memRange.offset = self.allocationInfo.offset + VkDeviceSize(range.lowerBound)
            memRange.size   = VkDeviceSize(range.count)
            vkFlushMappedMemoryRanges(self.device.vkDevice, 1, &memRange)
        }

        vmaUnmapMemory(self.allocator, self.allocation)
    }
    
    func fits(descriptor: VulkanBufferDescriptor) -> Bool {
        return self.descriptor.flags == descriptor.flags &&
                self.descriptor.usageFlags.isSuperset(of: descriptor.usageFlags) &&
                self.descriptor.sharingMode ~= descriptor.sharingMode && // TODO: check compatibility rather than equality.
                self.descriptor.size >= descriptor.size
    }
    
    deinit {
        vmaDestroyBuffer(self.allocator, self.vkBuffer, self.allocation)
    }
}

class VulkanBufferView {
    public let buffer : VulkanBuffer
    public let vkView : VkBufferView
    
    fileprivate init(buffer: VulkanBuffer, vkView: VkBufferView) {
        self.buffer = buffer
        self.vkView = vkView
    }
    
    deinit {
        vkDestroyBufferView(self.buffer.device.vkDevice, self.vkView, nil)
    }
}
