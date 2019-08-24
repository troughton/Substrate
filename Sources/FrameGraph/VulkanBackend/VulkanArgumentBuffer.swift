//
//  VulkanArgumentBuffer.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 16/03/18.
//

#if canImport(Vulkan)
import Vulkan
import FrameGraphCExtras

// TODO: this will need to change to accomodate immutable samplers.

final class VulkanArgumentBuffer {
    let device : VulkanDevice
    let descriptorSet : VkDescriptorSet
    private let isTransient : Bool

    private var images = [VulkanImage]()
    private var buffers = [VulkanBuffer]()
    
    public init(arguments: ArgumentBuffer, bindingPath: VulkanResourceBindingPath, commandBufferResources: CommandBufferResources, pipelineReflection: VulkanPipelineReflection, resourceRegistry: ResourceRegistry, stateCaches: StateCaches) {
        self.device = commandBufferResources.device

        let layout = pipelineReflection.descriptorSetLayout(set: bindingPath.set, dynamicBuffers: []).vkLayout
        
        self.isTransient = !arguments.flags.contains(.persistent)

        if self.isTransient {
            self.descriptorSet = commandBufferResources.descriptorPool.allocateSet(layout: layout)
            commandBufferResources.descriptorSets.append(self.descriptorSet)
        } else {
            fatalError("Persistent argument buffers unimplemented on Vulkan.")
        }

        self.encodeArguments(from: arguments, pipelineReflection: pipelineReflection, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
    }

    deinit {
        if !self.isTransient {
            fatalError("Need to return the set to the pool.")
        }
    }
    
    func encodeArguments(from buffer: ArgumentBuffer, pipelineReflection: VulkanPipelineReflection, resourceRegistry: ResourceRegistry, stateCaches: StateCaches) {
        var descriptorWrites = [VkWriteDescriptorSet]()

        let bufferInfoSentinel = UnsafePointer<VkDescriptorBufferInfo>(bitPattern: 0x10)
        let imageInfoSentinel = UnsafePointer<VkDescriptorImageInfo>(bitPattern: 0x20)
    
        var imageInfos = [VkDescriptorImageInfo]()
        var bufferInfos = [VkDescriptorBufferInfo]()

        var setIndex = -1

        for (bindingPath, binding) in buffer.bindings {
            let vulkanPath = VulkanResourceBindingPath(bindingPath)
            
            assert(setIndex == -1 || setIndex == Int(vulkanPath.set), "Resources in an argument buffer cannot be in different sets.")
            setIndex = Int(vulkanPath.set)

            let resource = pipelineReflection[vulkanPath]
            
            var descriptorWrite = VkWriteDescriptorSet()
            descriptorWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
            descriptorWrite.dstBinding = vulkanPath.binding
            descriptorWrite.dstArrayElement = vulkanPath.arrayIndex
            descriptorWrite.descriptorCount = 1
            descriptorWrite.descriptorType = VkDescriptorType(resource.type, dynamic: false)!
            descriptorWrite.dstSet = self.descriptorSet
            descriptorWrite.pBufferInfo = nil
            descriptorWrite.pImageInfo = nil

            switch binding {
            case .texture(let texture):
                guard let image = resourceRegistry[texture] else { continue }

                self.images.append(image)
            
                var imageInfo = VkDescriptorImageInfo()
                imageInfo.imageLayout = image.layout
                imageInfo.imageView = image.defaultImageView.vkView
                
                descriptorWrite.pImageInfo = imageInfoSentinel
                imageInfos.append(imageInfo)

            case .buffer(let buffer, let offset):
                guard let vkBuffer = resourceRegistry[buffer] else { continue }
                self.buffers.append(vkBuffer)

                var bufferInfo = VkDescriptorBufferInfo()
                bufferInfo.buffer = vkBuffer.vkBuffer
                bufferInfo.offset = VkDeviceSize(offset)
                if resource.bindingRange.size == 0 {
                    // FIXME: should be constrained to maxUniformBufferRange or maxStorageBufferRange
                    bufferInfo.range = VK_WHOLE_SIZE
                } else {
                    bufferInfo.range = VkDeviceSize(resource.bindingRange.size)
                }

                descriptorWrite.pBufferInfo = bufferInfoSentinel
                bufferInfos.append(bufferInfo)

            case .sampler(let descriptor):
                var imageInfo = VkDescriptorImageInfo()
                imageInfo.sampler = stateCaches[descriptor]
            
                descriptorWrite.pImageInfo = imageInfoSentinel
                imageInfos.append(imageInfo)

            case .bytes(let offset, let length):
                let bytes = buffer._bytes(offset: offset)
                
                assert(self.isTransient)
                
                let (buffer, offset) = resourceRegistry.temporaryBufferAllocator.bufferStoring(bytes: bytes, length: Int(length))

                var bufferInfo = VkDescriptorBufferInfo()
                bufferInfo.buffer = buffer.vkBuffer
                bufferInfo.offset = VkDeviceSize(offset)
                bufferInfo.range = VkDeviceSize(length)
                
                descriptorWrite.pBufferInfo = bufferInfoSentinel
                bufferInfos.append(bufferInfo)
            }

            descriptorWrites.append(descriptorWrite)
        }
        
        imageInfos.withUnsafeBufferPointer { imageInfos in
            var imageInfoOffset = 0
    
            bufferInfos.withUnsafeBufferPointer { bufferInfos in
                var bufferInfoOffset = 0
                
                for i in 0..<descriptorWrites.count {
                    if descriptorWrites[i].pBufferInfo == bufferInfoSentinel {
                        descriptorWrites[i].pBufferInfo = bufferInfos.baseAddress?.advanced(by: bufferInfoOffset)
                        bufferInfoOffset += 1
                    } else {  
                        assert(descriptorWrites[i].pImageInfo == imageInfoSentinel)
                        descriptorWrites[i].pImageInfo = imageInfos.baseAddress?.advanced(by: imageInfoOffset)
                        imageInfoOffset += 1
                    }

                }
                
                vkUpdateDescriptorSets(self.device.vkDevice, UInt32(descriptorWrites.count), &descriptorWrites, 0, nil)
            }
        }
    }
}

#endif // canImport(Vulkan)
