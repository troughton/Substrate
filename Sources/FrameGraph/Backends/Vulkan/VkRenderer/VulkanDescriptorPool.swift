//
//  DescriptorManager.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 10/01/18.
//

import CVkRenderer

public final class VulkanDescriptorPool {
    public static let maxSetsPerPool : UInt32 = 64
    
    private let vkDescriptorPool : VkDescriptorPool
    public let usesIncrementalRelease : Bool
    
    private let device : VulkanDevice
    
    init(device: VulkanDevice, incrementalRelease: Bool) {
        self.device = device
        self.usesIncrementalRelease = incrementalRelease
        
        var poolSizes = [VkDescriptorPoolSize]()
        for typeIndex in VK_DESCRIPTOR_TYPE_BEGIN_RANGE.rawValue...VK_DESCRIPTOR_TYPE_END_RANGE.rawValue {
            var descriptorPoolSize = VkDescriptorPoolSize()
            descriptorPoolSize.type = VkDescriptorType(rawValue: typeIndex)
            descriptorPoolSize.descriptorCount = VulkanDescriptorPool.maxSetsPerPool
            poolSizes.append(descriptorPoolSize)
        }
    
        self.vkDescriptorPool = poolSizes.withUnsafeBufferPointer { (poolSizes) -> VkDescriptorPool in
         
            var descriptorPoolCreateInfo = VkDescriptorPoolCreateInfo()
            descriptorPoolCreateInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO
            descriptorPoolCreateInfo.flags = incrementalRelease ? VkDescriptorPoolCreateFlags(VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT) : 0
            descriptorPoolCreateInfo.maxSets = VulkanDescriptorPool.maxSetsPerPool * UInt32(VK_DESCRIPTOR_TYPE_RANGE_SIZE.rawValue)
            descriptorPoolCreateInfo.poolSizeCount = UInt32(VK_DESCRIPTOR_TYPE_RANGE_SIZE.rawValue)
            descriptorPoolCreateInfo.pPoolSizes = poolSizes.baseAddress

            var descriptorPool : VkDescriptorPool? = nil
            
            guard vkCreateDescriptorPool(device.vkDevice, &descriptorPoolCreateInfo, nil, &descriptorPool) == VK_SUCCESS else {
                fatalError("Failed to create descriptor pool")
            }
            
            return descriptorPool!
        }
    }
    
    public func allocateSet(layout: VkDescriptorSetLayout) -> VkDescriptorSet {
        var allocateInfo = VkDescriptorSetAllocateInfo()
        allocateInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO
        allocateInfo.descriptorPool = self.vkDescriptorPool
        allocateInfo.descriptorSetCount = 1
        var layout : VkDescriptorSetLayout? = layout
        
        var set : VkDescriptorSet? = nil
        withUnsafePointer(to: &layout) { layoutPtr in
            allocateInfo.pSetLayouts = layoutPtr
            vkAllocateDescriptorSets(self.device.vkDevice, &allocateInfo, &set).check()
        }
        
        return set!
    }
    
    public func freeDescriptorSets(_ descriptorSets: inout [VkDescriptorSet?]) {
        if self.usesIncrementalRelease {
            guard !descriptorSets.isEmpty else {
                return
            }
            vkFreeDescriptorSets(self.device.vkDevice, self.vkDescriptorPool, UInt32(descriptorSets.count), &descriptorSets)
        } else {
            vkResetDescriptorPool(self.device.vkDevice, self.vkDescriptorPool, 0)
        }
    }
}
        
        

