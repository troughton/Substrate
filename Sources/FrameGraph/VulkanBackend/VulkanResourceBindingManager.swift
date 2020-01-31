//
//  ResourceBindingManager.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 6/03/18.
//

#if canImport(Vulkan)
import Vulkan
import FrameGraphCExtras

final class ResourceBindingManager {
    
    final class DescriptorSetBindingManager {
        let set : UInt32
        weak var bindingManager : ResourceBindingManager!
        
        var descriptorCounts = [UInt32](repeating: 0, count: 32)
        
        var dynamicBuffers : BitSet = []
        var dynamicOffsets = [UInt32]()
        var needsRebind = false
        
        private var setIsMutable = false
        private var _vkSet : VkDescriptorSet? = nil
        private var _previousLayout : VkDescriptorSetLayout? = nil
        
        var mutableSet : VkDescriptorSet {
            if let vkSet = _vkSet, self.setIsMutable {
                return vkSet
            }
            
            let layout = self.bindingManager.pipelineReflection.descriptorSetLayout(set: self.set, dynamicBuffers: self.dynamicBuffers).vkLayout
            let set = self.bindingManager.commandBufferResources.descriptorPool.allocateSet(layout: layout)
            self.bindingManager.commandBufferResources.descriptorSets.append(set)
            
            if _vkSet != nil, layout == _previousLayout {
                // Copy over the current set.
                
                var copyDescriptors = [VkCopyDescriptorSet]()

                for (binding, count) in self.descriptorCounts.enumerated() where count > 0 {
                    var copySet = VkCopyDescriptorSet()
                    copySet.sType = VK_STRUCTURE_TYPE_COPY_DESCRIPTOR_SET
                    copySet.srcSet = _vkSet
                    copySet.srcBinding = UInt32(binding)
                    copySet.srcArrayElement = 0
                    copySet.dstSet = set
                    copySet.dstBinding = UInt32(binding)
                    copySet.dstArrayElement = 0
                    copySet.descriptorCount = count

                    copyDescriptors.append(copySet)
                }

                vkUpdateDescriptorSets(bindingManager.device.vkDevice, 0, nil, UInt32(copyDescriptors.count), copyDescriptors)
            }
            
            _vkSet = set
            _previousLayout = layout
            self.setIsMutable = true
            return set
        }
        
        init(set: UInt32, bindingManager: ResourceBindingManager) {
            self.set = set
            self.bindingManager = bindingManager
        }
        
        func setBuffer(_ buffer: Buffer, offset: UInt32, bindingPath: ResourceBindingPath, hasDynamicOffsets: Bool) {
            let buffer = bindingManager.resourceMap[buffer]
            self.setBuffer(buffer, offset: offset, bindingPath: bindingPath, hasDynamicOffsets: hasDynamicOffsets)
        }
        
        func setBuffer(_ buffer: VkBufferReference, offset: UInt32, bindingPath: ResourceBindingPath, hasDynamicOffsets: Bool) {
            self.needsRebind = true
            
            bindingManager.commandBufferResources.buffers.append(buffer.buffer)
            
            self.descriptorCounts[Int(bindingPath.binding)] = 1

            let resource = bindingManager.pipelineReflection[bindingPath]
            
            var descriptorWrite = VkWriteDescriptorSet()
            descriptorWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
            descriptorWrite.dstBinding = bindingPath.binding
            descriptorWrite.dstArrayElement = bindingPath.arrayIndexVulkan
            descriptorWrite.descriptorCount = 1
            descriptorWrite.descriptorType = VkDescriptorType(resource.type, dynamic: hasDynamicOffsets)!
            descriptorWrite.dstSet = self.mutableSet
            
            var bufferInfo = VkDescriptorBufferInfo()
            bufferInfo.buffer = buffer.buffer.vkBuffer
            bufferInfo.offset = VkDeviceSize(buffer.offset) + (hasDynamicOffsets ? 0 : VkDeviceSize(offset))
            if resource.bindingRange.count == 0 {
                // FIXME: should be constrained to maxUniformBufferRange or maxStorageBufferRange
                bufferInfo.range = VK_WHOLE_SIZE
            } else {
                bufferInfo.range = VkDeviceSize(resource.bindingRange.count)
            }
            
            withUnsafePointer(to: &bufferInfo) { bufferInfo in
                descriptorWrite.pBufferInfo = bufferInfo
                vkUpdateDescriptorSets(bindingManager.device.vkDevice, 1, &descriptorWrite, 0, nil)
            }
            
            if hasDynamicOffsets {
                self.setBufferOffset(offset, bindingPath: bindingPath)
            }
        }
        
        func setBufferOffset(_ offset: UInt32, bindingPath: ResourceBindingPath) {
            self.needsRebind = true

            var offsetInOffsets = 0
            for i in 0..<Int(bindingPath.binding) {
                if self.dynamicBuffers.contains(BitSet(element: i)) {
                    offsetInOffsets += 1
                }
            }
            
            if offsetInOffsets >= self.dynamicOffsets.endIndex {
                self.dynamicOffsets.append(contentsOf: repeatElement(0, count: offsetInOffsets - self.dynamicOffsets.endIndex + 1))
            }
            
            self.dynamicOffsets[offsetInOffsets] = offset
        }
        
        func setTexture(_ texture: Texture, bindingPath: ResourceBindingPath) {
            self.needsRebind = true
            
            self.descriptorCounts[Int(bindingPath.binding)] = 1
            
            let resource = bindingManager.pipelineReflection[bindingPath]
            
            var descriptorWrite = VkWriteDescriptorSet()
            descriptorWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
            descriptorWrite.dstBinding = bindingPath.binding
            descriptorWrite.dstArrayElement = bindingPath.arrayIndexVulkan
            descriptorWrite.descriptorCount = 1
            descriptorWrite.descriptorType = VkDescriptorType(resource.type, dynamic: false)!
            descriptorWrite.dstSet = self.mutableSet
            
            let image = bindingManager.resourceMap[texture]
            bindingManager.commandBufferResources.images.append(image)
            
            var imageInfo = VkDescriptorImageInfo()
            imageInfo.imageLayout = image.layout
            imageInfo.imageView = image.defaultImageView.vkView
            
            withUnsafePointer(to: &imageInfo) { imageInfo in
                descriptorWrite.pImageInfo = imageInfo
                vkUpdateDescriptorSets(bindingManager.device.vkDevice, 1, &descriptorWrite, 0, nil)
            }
        }
        
        func setSamplerState(descriptor: SamplerDescriptor, bindingPath: ResourceBindingPath) {
            self.needsRebind = true
            
            self.descriptorCounts[Int(bindingPath.binding)] = 1
            
            var descriptorWrite = VkWriteDescriptorSet()
            descriptorWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
            descriptorWrite.dstBinding = bindingPath.binding
            descriptorWrite.dstArrayElement = bindingPath.arrayIndexVulkan
            descriptorWrite.descriptorCount = 1
            descriptorWrite.descriptorType = VK_DESCRIPTOR_TYPE_SAMPLER
            descriptorWrite.dstSet = self.mutableSet
            
            var imageInfo = VkDescriptorImageInfo()
            imageInfo.sampler = bindingManager.stateCaches[descriptor]
            
            withUnsafePointer(to: &imageInfo) { imageInfo in
                descriptorWrite.pImageInfo = imageInfo
                vkUpdateDescriptorSets(bindingManager.device.vkDevice, 1, &descriptorWrite, 0, nil)
            }
        }
        
        func bindDescriptorSet() {
            guard self.needsRebind else { return }
            defer { 
                self.needsRebind = false
                self.setIsMutable = false
            }

            vkCmdBindDescriptorSets(self.bindingManager.commandBuffer, bindingManager.bindPoint, bindingManager.encoder.pipelineLayout, self.set, 1, &self._vkSet, UInt32(self.dynamicOffsets.count), self.dynamicOffsets)
        }
    }
    
    private var commands = [FrameGraphCommand]()
    private var setManagers = [DescriptorSetBindingManager]()
    
    unowned(unsafe) var encoder : VulkanResourceBindingCommandEncoder!
    
    init(encoder: VulkanResourceBindingCommandEncoder) {
        self.encoder = encoder
    }
    
    var device : VulkanDevice {
        return self.encoder.device
    }
    
    var resourceMap : VulkanFrameResourceMap {
        return self.encoder.resourceMap
    }
    
    var pipelineReflection : VulkanPipelineReflection {
        return self.encoder.pipelineReflection
    }
    
    var commandBuffer : VkCommandBuffer {
        return self.encoder.commandBuffer
    }
    
    var commandBufferResources : CommandBufferResources {
        return self.encoder.commandBufferResources
    }
    
    var bindPoint : VkPipelineBindPoint {
        return self.encoder.bindPoint
    }
    
    var stateCaches : VulkanStateCaches {
        return self.encoder.stateCaches
    }

    func existingManagerForSet(_ set: UInt32) -> DescriptorSetBindingManager? {
        for setManager in self.setManagers {
            if setManager.set == set {
                return setManager
            }
        }
        return nil
    }
    
    func managerForSet(_ set: UInt32) -> DescriptorSetBindingManager {
        if let existingManager = self.existingManagerForSet(set) {
            return existingManager
        }
        let manager = DescriptorSetBindingManager(set: set, bindingManager: self)
        self.setManagers.append(manager)
        return manager
    }
    
    private func setBytes(bindingPath: ResourceBindingPath, bytes: UnsafeRawPointer, length: UInt32) {
        let resourceInfo = self.pipelineReflection[bindingPath]
        
        switch resourceInfo.type {
        case .pushConstantBuffer:
            assert(resourceInfo.bindingRange.count == length, "The push constant size and the setBytes length must match.")
            vkCmdPushConstants(self.commandBuffer, encoder.pipelineLayout, VkShaderStageFlags(resourceInfo.accessedStages), resourceInfo.bindingRange.lowerBound, length, bytes)
            
        default:
            fatalError("Need to implement VK_EXT_inline_uniform_block or else fall back to a temporary staging buffer")
        }
    }
    
    private func setBuffer(_ buffer: Buffer, offset: UInt32, bindingPath: ResourceBindingPath, hasDynamicOffsets: Bool) {
        self.managerForSet(bindingPath.set).setBuffer(buffer, offset: offset, bindingPath: bindingPath, hasDynamicOffsets: hasDynamicOffsets)
    }
    
    private func setBuffer(_ buffer: VkBufferReference, offset: UInt32, bindingPath: ResourceBindingPath, hasDynamicOffsets: Bool) { self.managerForSet(bindingPath.set).setBuffer(buffer, offset: offset, bindingPath: bindingPath, hasDynamicOffsets: hasDynamicOffsets)
    }
    
    private func setBufferOffset(_ offset: UInt32, bindingPath: ResourceBindingPath) { self.managerForSet(bindingPath.set).setBufferOffset(offset, bindingPath: bindingPath)
    }
    
    private func setTexture(_ texture: Texture, bindingPath: ResourceBindingPath) { self.managerForSet(bindingPath.set).setTexture(texture, bindingPath: bindingPath)
    }
    
    private func setSamplerState(descriptor: SamplerDescriptor, bindingPath: ResourceBindingPath) { self.managerForSet(bindingPath.set).setSamplerState(descriptor: descriptor, bindingPath: bindingPath)
    }
    
    public func setBytes(args: UnsafePointer<FrameGraphCommand.SetBytesArgs>) {
        self.commands.append(.setBytes(args))
    }
    
    public func setBuffer(args: UnsafePointer<FrameGraphCommand.SetBufferArgs>) {
        let bindingPath = args.pointee.bindingPath
        if args.pointee.hasDynamicOffset {
            self.managerForSet(bindingPath.set).dynamicBuffers.insert(BitSet(element: Int(bindingPath.binding)))
        } else {
            self.managerForSet(bindingPath.set).dynamicBuffers.remove(BitSet(element: Int(bindingPath.binding)))
        }
        
        self.commands.append(.setBuffer(args))
    }
    
    public func setBufferOffset(args: UnsafePointer<FrameGraphCommand.SetBufferOffsetArgs>) {
        self.commands.append(.setBufferOffset(args))
    }
    
    public func setTexture(args: UnsafePointer<FrameGraphCommand.SetTextureArgs>) {
        self.commands.append(.setTexture(args))
    }
    
    public func setSamplerState(args: UnsafePointer<FrameGraphCommand.SetSamplerStateArgs>) {
        self.commands.append(.setSamplerState(args))
    }
    
    public func bindDescriptorSets() {
        for command in self.commands {
            switch command {
            case .setBytes(let args):
                self.setBytes(bindingPath: args.pointee.bindingPath, bytes: args.pointee.bytes, length: args.pointee.length)
            case .setBuffer(let args):
                self.setBuffer(args.pointee.buffer, offset: args.pointee.offset, bindingPath: args.pointee.bindingPath, hasDynamicOffsets: args.pointee.hasDynamicOffset)
            case .setBufferOffset(let args):
                self.setBufferOffset(args.pointee.offset, bindingPath: args.pointee.bindingPath)
            case .setTexture(let args):
                self.setTexture(args.pointee.texture, bindingPath: args.pointee.bindingPath)
            case .setSamplerState(let args): // TODO: we can support immutable samplers in a similar way to dynamic buffer offsets.
                self.setSamplerState(descriptor: args.pointee.descriptor, bindingPath: args.pointee.bindingPath)
            default:
                fatalError()
            }
        }
        
        self.commands.removeAll(keepingCapacity: true)
        
        for setManager in self.setManagers {
            setManager.bindDescriptorSet()
        }
    }
}

#endif // canImport(Vulkan)
