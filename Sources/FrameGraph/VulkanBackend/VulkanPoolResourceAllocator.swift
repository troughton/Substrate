//
//  PoolResourceAllocator.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 6/01/18.
//

#if canImport(Vulkan)
import Vulkan
import FrameGraphCExtras

final class PoolResourceAllocator : ResourceAllocator {
 
    struct ResourceReference<R> {
        let resource : R
        var framesUnused : Int = 0
        
        init(resource: R) {
            self.resource = resource
        }
    }
    
    let device : VulkanDevice
    let allocator : VmaAllocator
    
    private var buffers : [[ResourceReference<VulkanBuffer>]]
    private var images : [[ResourceReference<VulkanImage>]]
    
    private var buffersUsedThisFrame = [ResourceReference<VulkanBuffer>]()
    private var imagesUsedThisFrame = [ResourceReference<VulkanImage>]()
    
    let numFrames : Int
    let memoryUsage : VmaMemoryUsage
    private var currentIndex : Int = 0
    
    init(device: VulkanDevice, allocator: VmaAllocator, memoryUsage: VmaMemoryUsage, numFrames: Int) {
        self.numFrames = numFrames
        self.device = device
        self.allocator = allocator
        self.memoryUsage = memoryUsage
        self.buffers = [[ResourceReference<VulkanBuffer>]](repeating: [ResourceReference<VulkanBuffer>](), count: numFrames)
        self.images = [[ResourceReference<VulkanImage>]](repeating: [ResourceReference<VulkanImage>](), count: numFrames)
    }
  
    
    private func imageFitting(descriptor: VulkanImageDescriptor) -> VulkanImage? {
        
        for (i, imageRef) in self.images[currentIndex].enumerated() {
            if imageRef.resource.matches(descriptor: descriptor) {
                return self.images[currentIndex].remove(at: i, preservingOrder: false).resource
            }
        }
        
        return nil
    }
    
    private func bufferFitting(descriptor: VulkanBufferDescriptor) -> VulkanBuffer? {
        var bestIndex = -1
        var bestLength = UInt64.max
        
        for (i, bufferRef) in self.buffers[currentIndex].enumerated() {
            if bufferRef.resource.fits(descriptor: descriptor), bufferRef.resource.descriptor.size < bestLength {
                bestIndex = i
                bestLength = bufferRef.resource.descriptor.size
            }
        }
        
        if bestIndex != -1 {
            return self.buffers[currentIndex].remove(at: bestIndex, preservingOrder: false).resource
        } else {
            return nil
        }
    }

    func collectImage(descriptor: VulkanImageDescriptor) -> VulkanImage {
        if let image = self.imageFitting(descriptor: descriptor) {
            return image
        } else {
            var allocInfo = VmaAllocationCreateInfo()
            allocInfo.usage = self.memoryUsage
            
            var image : VkImage? = nil
            var allocation : VmaAllocation? = nil
            descriptor.withImageCreateInfo(device: self.device) { (info) in
                var info = info
                vmaCreateImage(self.allocator, &info, &allocInfo, &image, &allocation, nil)
            }
            
            return VulkanImage(device: self.device, image: image!, allocator: self.allocator, allocation: allocation!, descriptor: descriptor)
        }
    }
    
    func depositImage(_ image: VulkanImage) {
        //We can't just put the resource back into the array for the current frame, since it's not safe to use it for another buffers.count frames.
        self.imagesUsedThisFrame.append(ResourceReference(resource: image))
    }
    
    func collectBuffer(descriptor: VulkanBufferDescriptor) -> VulkanBuffer {
        if let buffer = self.bufferFitting(descriptor: descriptor) {
            return buffer
        } else {
            var allocInfo = VmaAllocationCreateInfo()
            allocInfo.usage = self.memoryUsage
            
            var buffer : VkBuffer? = nil
            var allocation : VmaAllocation? = nil
            var allocationInfo = VmaAllocationInfo()
            descriptor.withBufferCreateInfo(device: self.device) { (info) in
                var info = info
                vmaCreateBuffer(self.allocator, &info, &allocInfo, &buffer, &allocation, &allocationInfo)
            }
            
            return VulkanBuffer(device: self.device, buffer: buffer!, allocator: self.allocator, allocation: allocation!, allocationInfo: allocationInfo, descriptor: descriptor)
        }
    }
    
    func depositBuffer(_ buffer: VulkanBuffer) {
        //We can't just put the resource back into the array for the current frame, since it's not safe to use it for another buffers.count frames.
        self.buffersUsedThisFrame.append(ResourceReference(resource: buffer))
    }
    
    func cycleFrames() {
        do {
            var i = 0
            while i < self.buffers[self.currentIndex].count {
                self.buffers[self.currentIndex][i].framesUnused += 1
                
                if self.buffers[self.currentIndex][i].framesUnused > 2 {
                    self.buffers[self.currentIndex].remove(at: i, preservingOrder: false)
                } else {
                    i += 1
                }
            }
            
            self.buffers[self.currentIndex].append(contentsOf: buffersUsedThisFrame)
            self.buffersUsedThisFrame.removeAll(keepingCapacity: true)
        }
        
        do {
            var i = 0
            while i < self.images[self.currentIndex].count {
                self.images[self.currentIndex][i].framesUnused += 1
                
                if self.images[self.currentIndex][i].framesUnused > 2 {
                    self.images[self.currentIndex].remove(at: i, preservingOrder: false)
                } else {
                    i += 1
                }
            }
            
            self.images[self.currentIndex].append(contentsOf: imagesUsedThisFrame)
            self.imagesUsedThisFrame.removeAll(keepingCapacity: true)
        }
        
        self.currentIndex = (self.currentIndex + 1) % self.numFrames
    }
}

#endif // canImport(Vulkan)
