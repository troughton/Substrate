//
//  VulkanArgumentBuffer.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 16/03/18.
//

#if canImport(Vulkan)
import Vulkan
import SubstrateCExtras

// TODO: this will need to change to accomodate immutable samplers.

final class VulkanArgumentBuffer {
    let device : VulkanDevice
    let layout: VulkanDescriptorSetLayout
    let descriptorSet : VkDescriptorSet

    private var images = [VulkanImage]()
    private var buffers = [VulkanBuffer]()
    
    public init(device: VulkanDevice, layout: VulkanDescriptorSetLayout, descriptorSet: VkDescriptorSet) {
        self.device = device
        self.layout = layout
        self.descriptorSet = descriptorSet
    }
}

extension VulkanArgumentBuffer {
    
    func encodeArguments(from buffer: _ArgumentBuffer, commandIndex: Int, resourceMap: FrameResourceMap<VulkanBackend>) {
        let pipelineReflection = self.layout.pipelineReflection
        let setIndex = self.layout.set

        var descriptorWrites = [VkWriteDescriptorSet]()

        let bufferInfoSentinel = UnsafePointer<VkDescriptorBufferInfo>(bitPattern: 0x10)
        let imageInfoSentinel = UnsafePointer<VkDescriptorImageInfo>(bitPattern: 0x20)
        let inlineUniformSentinel = UnsafeRawPointer(bitPattern: 0x30)
    
        var imageInfos = [VkDescriptorImageInfo]()
        var bufferInfos = [VkDescriptorBufferInfo]()
        var inlineBlocks = [VkWriteDescriptorSetInlineUniformBlockEXT]()

        for (bindingPath, binding) in buffer.bindings {
            
            assert(setIndex == Int(bindingPath.set), "Resources in an argument buffer cannot be in different sets.")
            
            let resource = pipelineReflection[bindingPath]
            
            var descriptorWrite = VkWriteDescriptorSet()
            descriptorWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
            descriptorWrite.dstBinding = bindingPath.binding
            descriptorWrite.dstArrayElement = bindingPath.arrayIndexVulkan
            descriptorWrite.descriptorCount = 1
            descriptorWrite.descriptorType = VkDescriptorType(resource.type, dynamic: false)!
            descriptorWrite.dstSet = self.descriptorSet
            descriptorWrite.pBufferInfo = nil
            descriptorWrite.pImageInfo = nil

            switch binding {
            case .texture(let texture):
                let image = resourceMap[texture].image

                self.images.append(image)
            
                let usage = texture.usages.first(where: { $0.inArgumentBuffer && $0.commandRange.lowerBound >= commandIndex })!

                var imageInfo = VkDescriptorImageInfo()
                imageInfo.imageLayout = image.layout(commandIndex: usage.commandRange.lowerBound, subresourceRange: .fullResource)
                imageInfo.imageView = image.defaultImageView.vkView
                
                descriptorWrite.pImageInfo = imageInfoSentinel
                imageInfos.append(imageInfo)

            case .buffer(let buffer, let offset):
                let vkBuffer = resourceMap[buffer]
                self.buffers.append(vkBuffer.buffer)

                var bufferInfo = VkDescriptorBufferInfo()
                bufferInfo.buffer = vkBuffer.buffer.vkBuffer
                bufferInfo.offset = VkDeviceSize(offset) + VkDeviceSize(vkBuffer.offset)
                if resource.bindingRange.count == 0 {
                    // FIXME: should be constrained to maxUniformBufferRange or maxStorageBufferRange
                    bufferInfo.range = VK_WHOLE_SIZE
                } else {
                    bufferInfo.range = VkDeviceSize(resource.bindingRange.count)
                }

                descriptorWrite.pBufferInfo = bufferInfoSentinel
                bufferInfos.append(bufferInfo)

            case .sampler(let descriptor):
                var imageInfo = VkDescriptorImageInfo()
                imageInfo.sampler = resourceMap[descriptor]
            
                descriptorWrite.pImageInfo = imageInfoSentinel
                imageInfos.append(imageInfo)

            case .bytes(let offset, let length):
                let bytes = buffer._bytes(offset: offset)
                
                var writeDescriptorSetInlineUniformBlock = VkWriteDescriptorSetInlineUniformBlockEXT()
                writeDescriptorSetInlineUniformBlock.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_INLINE_UNIFORM_BLOCK_EXT;
                writeDescriptorSetInlineUniformBlock.dataSize = UInt32(length)
                writeDescriptorSetInlineUniformBlock.pData = bytes
                inlineBlocks.append(writeDescriptorSetInlineUniformBlock)

                descriptorWrite.descriptorType = VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT
                descriptorWrite.descriptorCount = UInt32(length)
                descriptorWrite.pNext = inlineUniformSentinel
            }

            descriptorWrites.append(descriptorWrite)
        }
        
        imageInfos.withUnsafeBufferPointer { imageInfos in
            var imageInfoOffset = 0
    
            bufferInfos.withUnsafeBufferPointer { bufferInfos in
                var bufferInfoOffset = 0
                
                inlineBlocks.withUnsafeBufferPointer { inlineBlocks in
                    var inlineBlocksOffset = 0
                    
                    for i in 0..<descriptorWrites.count {
                        if descriptorWrites[i].pBufferInfo == bufferInfoSentinel {
                            descriptorWrites[i].pBufferInfo = bufferInfos.baseAddress?.advanced(by: bufferInfoOffset)
                            bufferInfoOffset += 1
                        } else if descriptorWrites[i].pImageInfo == imageInfoSentinel {
                            descriptorWrites[i].pImageInfo = imageInfos.baseAddress?.advanced(by: imageInfoOffset)
                            imageInfoOffset += 1
                        } else if descriptorWrites[i].pNext == inlineUniformSentinel {
                            descriptorWrites[i].pNext = UnsafeRawPointer(inlineBlocks.baseAddress?.advanced(by: inlineBlocksOffset))
                            inlineBlocksOffset += 1
                        }
                    }
                    
                    vkUpdateDescriptorSets(self.device.vkDevice, UInt32(descriptorWrites.count), &descriptorWrites, 0, nil)
                }
            }
        }
    }
}

#endif // canImport(Vulkan)
