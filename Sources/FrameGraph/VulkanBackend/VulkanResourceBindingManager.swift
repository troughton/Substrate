//
//  ResourceBindingManager.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 6/03/18.
//

#if canImport(Vulkan)
import Vulkan
import SwiftFrameGraph
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
        
        
        func setBuffer(bindingPath: ResourceBindingPath, handle: Buffer.Handle, offset: UInt32, hasDynamicOffsets: Bool) {
            let buffer = bindingManager.resourceRegistry[buffer: handle]!
            self.setBuffer(bindingPath: bindingPath, buffer: buffer, offset: offset, hasDynamicOffsets: hasDynamicOffsets)
        }
        
        func setBuffer(bindingPath: ResourceBindingPath, buffer: VulkanBuffer, offset: UInt32, hasDynamicOffsets: Bool) {
            self.needsRebind = true
            
            let vkBindingPath = VulkanResourceBindingPath(bindingPath)
            bindingManager.commandBufferResources.buffers.append(buffer)
            
            self.descriptorCounts[Int(vkBindingPath.binding)] = 1

            let resource = bindingManager.pipelineReflection[vkBindingPath]
            
            var descriptorWrite = VkWriteDescriptorSet()
            descriptorWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
            descriptorWrite.dstBinding = vkBindingPath.binding
            descriptorWrite.dstArrayElement = vkBindingPath.arrayIndex
            descriptorWrite.descriptorCount = 1
            descriptorWrite.descriptorType = VkDescriptorType(resource.type, dynamic: hasDynamicOffsets)!
            descriptorWrite.dstSet = self.mutableSet
            
            var bufferInfo = VkDescriptorBufferInfo()
            bufferInfo.buffer = buffer.vkBuffer
            bufferInfo.offset = hasDynamicOffsets ? 0 : VkDeviceSize(offset)
            if resource.bindingRange.size == 0 {
                // FIXME: should be constrained to maxUniformBufferRange or maxStorageBufferRange
                bufferInfo.range = VK_WHOLE_SIZE
            } else {
                bufferInfo.range = VkDeviceSize(resource.bindingRange.size)
            }
            
            withUnsafePointer(to: &bufferInfo) { bufferInfo in
                descriptorWrite.pBufferInfo = bufferInfo
                vkUpdateDescriptorSets(bindingManager.device.vkDevice, 1, &descriptorWrite, 0, nil)
            }
            
            if hasDynamicOffsets {
                self.setBufferOffset(bindingPath: bindingPath, offset: offset)
            }
        }
        
        func setBufferOffset(bindingPath: ResourceBindingPath, offset: UInt32) {
            self.needsRebind = true
            
            let vulkanPath = VulkanResourceBindingPath(bindingPath)

            var offsetInOffsets = 0
            for i in 0..<Int(vulkanPath.binding) {
                if self.dynamicBuffers.contains(BitSet(element: i)) {
                    offsetInOffsets += 1
                }
            }
            
            if offsetInOffsets >= self.dynamicOffsets.endIndex {
                self.dynamicOffsets.append(contentsOf: repeatElement(0, count: offsetInOffsets - self.dynamicOffsets.endIndex + 1))
            }
            
            self.dynamicOffsets[offsetInOffsets] = offset
        }
        
        func setTexture(bindingPath: ResourceBindingPath, handle: Texture.Handle) {
            self.needsRebind = true
            
            let bindingPath = VulkanResourceBindingPath(bindingPath)
            self.descriptorCounts[Int(bindingPath.binding)] = 1
            
            let resource = bindingManager.pipelineReflection[bindingPath]
            
            var descriptorWrite = VkWriteDescriptorSet()
            descriptorWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
            descriptorWrite.dstBinding = bindingPath.binding
            descriptorWrite.dstArrayElement = bindingPath.arrayIndex
            descriptorWrite.descriptorCount = 1
            descriptorWrite.descriptorType = VkDescriptorType(resource.type, dynamic: false)!
            descriptorWrite.dstSet = self.mutableSet
            
            let image = bindingManager.resourceRegistry[texture: handle]!
            bindingManager.commandBufferResources.images.append(image)
            
            var imageInfo = VkDescriptorImageInfo()
            imageInfo.imageLayout = image.layout
            imageInfo.imageView = image.defaultImageView.vkView
            
            withUnsafePointer(to: &imageInfo) { imageInfo in
                descriptorWrite.pImageInfo = imageInfo
                vkUpdateDescriptorSets(bindingManager.device.vkDevice, 1, &descriptorWrite, 0, nil)
            }
        }
        
        func setSamplerState(bindingPath: ResourceBindingPath, descriptor: SamplerDescriptor) {
            self.needsRebind = true
            
            let bindingPath = VulkanResourceBindingPath(bindingPath)
            self.descriptorCounts[Int(bindingPath.binding)] = 1
            
            var descriptorWrite = VkWriteDescriptorSet()
            descriptorWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
            descriptorWrite.dstBinding = bindingPath.binding
            descriptorWrite.dstArrayElement = bindingPath.arrayIndex
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
    
    weak var encoder : VulkanResourceBindingCommandEncoder!
    
    init(encoder: VulkanResourceBindingCommandEncoder) {
        self.encoder = encoder
    }
    
    var device : VulkanDevice {
        return self.encoder.device
    }
    
    var resourceRegistry : ResourceRegistry {
        return self.encoder.resourceRegistry
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
    
    var stateCaches : StateCaches {
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
        let vkBindingPath = VulkanResourceBindingPath(bindingPath)
        let resourceInfo = self.pipelineReflection[vkBindingPath]
        
        switch resourceInfo.type {
        case .pushConstantBuffer:
            assert(resourceInfo.bindingRange.size == length, "The push constant size and the setBytes length must match.")
            vkCmdPushConstants(self.commandBuffer, encoder.pipelineLayout, VkShaderStageFlags(resourceInfo.accessedStages), resourceInfo.bindingRange.offset, length, bytes)
            
        default:
            let (buffer, offset) = self.resourceRegistry.temporaryBufferAllocator.bufferStoring(bytes: bytes, length: Int(length))
            self.setBuffer(bindingPath: bindingPath, buffer: buffer, offset: UInt32(offset), hasDynamicOffsets: false)
        }
    }
    
    private func setBuffer(bindingPath: ResourceBindingPath, handle: Buffer.Handle, offset: UInt32, hasDynamicOffsets: Bool) {
        let vkBindingPath = VulkanResourceBindingPath(bindingPath)
        self.managerForSet(vkBindingPath.set).setBuffer(bindingPath: bindingPath, handle: handle, offset: offset, hasDynamicOffsets: hasDynamicOffsets)
    }
    
    private func setBuffer(bindingPath: ResourceBindingPath, buffer: VulkanBuffer, offset: UInt32, hasDynamicOffsets: Bool) {
        let vkBindingPath = VulkanResourceBindingPath(bindingPath)
        self.managerForSet(vkBindingPath.set).setBuffer(bindingPath: bindingPath, buffer: buffer, offset: offset, hasDynamicOffsets: hasDynamicOffsets)
    }
    
    private func setBufferOffset(bindingPath: ResourceBindingPath, handle: Buffer.Handle, offset: UInt32) {
        let vkBindingPath = VulkanResourceBindingPath(bindingPath)
        self.managerForSet(vkBindingPath.set).setBufferOffset(bindingPath: bindingPath, offset: offset)
    }
    
    private func setTexture(bindingPath: ResourceBindingPath, handle: Texture.Handle) {
        let vkBindingPath = VulkanResourceBindingPath(bindingPath)
        self.managerForSet(vkBindingPath.set).setTexture(bindingPath: bindingPath, handle: handle)
    }
    
    private func setSamplerState(bindingPath: ResourceBindingPath, descriptor: SamplerDescriptor) {
        let vkBindingPath = VulkanResourceBindingPath(bindingPath)
        self.managerForSet(vkBindingPath.set).setSamplerState(bindingPath: bindingPath, descriptor: descriptor)
    }
    
    public func setBytes(args: UnsafePointer<FrameGraphCommand.SetBytesArgs>) {
        self.commands.append(.setBytes(args))
    }
    
    public func setBuffer(args: UnsafePointer<FrameGraphCommand.SetBufferArgs>) {
        let vkBindingPath = VulkanResourceBindingPath(args.pointee.bindingPath)
        
        if args.pointee.hasDynamicOffset {
            self.managerForSet(vkBindingPath.set).dynamicBuffers.insert(BitSet(element: Int(vkBindingPath.binding)))
        } else {
            self.managerForSet(vkBindingPath.set).dynamicBuffers.remove(BitSet(element: Int(vkBindingPath.binding)))
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
                self.setBuffer(bindingPath: args.pointee.bindingPath, handle: args.pointee.handle, offset: args.pointee.offset, hasDynamicOffsets: args.pointee.hasDynamicOffset)
            case .setBufferOffset(let args):
                self.setBufferOffset(bindingPath: args.pointee.bindingPath, handle: args.pointee.handle!, offset: args.pointee.offset)
            case .setTexture(let args):
                self.setTexture(bindingPath: args.pointee.bindingPath, handle: args.pointee.handle)
            case .setSamplerState(let args): // TODO: we can support immutable samplers in a similar way to dynamic buffer offsets.
                self.setSamplerState(bindingPath: args.pointee.bindingPath, descriptor: args.pointee.descriptor)
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
