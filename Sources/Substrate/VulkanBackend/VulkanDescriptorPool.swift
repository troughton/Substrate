//
//  DescriptorManager.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 10/01/18.
//

#if canImport(Vulkan)
import Vulkan
import SubstrateCExtras

final class VulkanDescriptorPool {
    public static let maxSetsPerPool : UInt32 = 64
    
    private let vkDescriptorPool : VkDescriptorPool
    public let usesIncrementalRelease : Bool
    
    private let device : VulkanDevice
    
    init(device: VulkanDevice, incrementalRelease: Bool) {
        self.device = device
        self.usesIncrementalRelease = incrementalRelease
        
        var poolSizes = [VkDescriptorPoolSize]()
        
        let descriptorTypes = [VK_DESCRIPTOR_TYPE_SAMPLER,
                     VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,
                     VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
                     VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER,
                     VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER,
                     VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                     VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                     VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
                     VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC,
                     VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT,
                     VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT]
        
        for type in descriptorTypes {
            var descriptorPoolSize = VkDescriptorPoolSize()
            descriptorPoolSize.type = type
            descriptorPoolSize.descriptorCount = VulkanDescriptorPool.maxSetsPerPool
            poolSizes.append(descriptorPoolSize)
        }
    
        self.vkDescriptorPool = poolSizes.withUnsafeBufferPointer { (poolSizes) -> VkDescriptorPool in
         
            var descriptorPoolCreateInfo = VkDescriptorPoolCreateInfo()
            descriptorPoolCreateInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO
            descriptorPoolCreateInfo.flags = incrementalRelease ? VkDescriptorPoolCreateFlags(VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT) : 0
            descriptorPoolCreateInfo.maxSets = VulkanDescriptorPool.maxSetsPerPool * UInt32(descriptorTypes.count)
            descriptorPoolCreateInfo.poolSizeCount = UInt32(descriptorTypes.count)
            descriptorPoolCreateInfo.pPoolSizes = poolSizes.baseAddress

            var descriptorPool : VkDescriptorPool? = nil
            
            guard vkCreateDescriptorPool(device.vkDevice, &descriptorPoolCreateInfo, nil, &descriptorPool) == VK_SUCCESS else {
                fatalError("Failed to create descriptor pool")
            }
            
            return descriptorPool!
        }
    }
    
    deinit {
        vkDestroyDescriptorPool(device.vkDevice, self.vkDescriptorPool, nil)
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
    
    // Used for descriptor pools for transient resources.
    public func resetDescriptorPool() {
        vkResetDescriptorPool(self.device.vkDevice, self.vkDescriptorPool, 0)
    }
    
    // Used for persistent descriptor sets.
    public func freeDescriptorSet(_ descriptorSet: VkDescriptorSet) {
        precondition(self.usesIncrementalRelease)
        withUnsafePointer(to: descriptorSet as VkDescriptorSet?) {
            vkFreeDescriptorSets(self.device.vkDevice, self.vkDescriptorPool, 1, $0).check()
        }
    }
}
       
#endif // canImport(Vulkan)
