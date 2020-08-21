//
//  PoolResourceAllocator.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 6/01/18.
//

#if canImport(Vulkan)
import Vulkan
import FrameGraphCExtras

final class VulkanPoolResourceAllocator : VulkanImageAllocator, VulkanBufferAllocator {
 
    struct ResourceReference<R> {
        let resource : R
        var waitSemaphore : ContextWaitEvent
        var framesUnused : Int = 0
        
        init(resource: R, waitSemaphore: ContextWaitEvent) {
            self.resource = resource
            self.waitSemaphore = waitSemaphore
        }
    }
    
    let device : VulkanDevice
    let allocator : VmaAllocator
    
    private var buffers : [[ResourceReference<VkBufferReference>]]
    private var images : [[ResourceReference<VkImageReference>]]
    
    private var buffersUsedThisFrame = [ResourceReference<VkBufferReference>]()
    private var imagesUsedThisFrame = [ResourceReference<VkImageReference>]()
    
    let numFrames : Int
    private var currentIndex : Int = 0
    
    init(device: VulkanDevice, allocator: VmaAllocator, numFrames: Int) {
        self.numFrames = numFrames
        self.device = device
        self.allocator = allocator
        self.buffers = [[ResourceReference<VkBufferReference>]](repeating: [], count: numFrames)
        self.images = [[ResourceReference<VkImageReference>]](repeating: [], count: numFrames)
    }
  
    
    private func imageFitting(descriptor: VulkanImageDescriptor) -> (VkImageReference, ContextWaitEvent)? {
        
        for (i, imageRef) in self.images[currentIndex].enumerated() {
            if imageRef.resource.image.matches(descriptor: descriptor) {
                let resourceRef = self.images[currentIndex].remove(at: i, preservingOrder: false)
                return (resourceRef.resource, resourceRef.waitSemaphore)
            }
        }
        
        return nil
    }
    
    private func bufferFitting(descriptor: VulkanBufferDescriptor) -> (VkBufferReference, ContextWaitEvent)? {
        var bestIndex = -1
        var bestLength = UInt64.max
        
        for (i, bufferRef) in self.buffers[currentIndex].enumerated() {
            if bufferRef.resource.buffer.fits(descriptor: descriptor), bufferRef.resource.buffer.descriptor.size < bestLength {
                bestIndex = i
                bestLength = bufferRef.resource.buffer.descriptor.size
            }
        }
        
        if bestIndex != -1 {
            let resourceRef = self.buffers[currentIndex].remove(at: bestIndex, preservingOrder: false)
            return (resourceRef.resource, resourceRef.waitSemaphore)
        } else {
            return nil
        }
    }

    func collectImage(descriptor: VulkanImageDescriptor) -> (VkImageReference, [FenceDependency], ContextWaitEvent) {
        if let image = self.imageFitting(descriptor: descriptor) {
            return (image.0, [], image.1)
        } else {
            var allocInfo = VmaAllocationCreateInfo(storageMode: descriptor.storageMode, cacheMode: descriptor.cacheMode)
            
            var image : VkImage? = nil
            var allocation : VmaAllocation? = nil
            descriptor.withImageCreateInfo(device: self.device) { (info) in
                var info = info
                vmaCreateImage(self.allocator, &info, &allocInfo, &image, &allocation, nil)
            }
            
            let vulkanImage = VulkanImage(device: self.device, image: image!, allocator: self.allocator, allocation: allocation!, descriptor: descriptor)
            return (VkImageReference(image: Unmanaged.passRetained(vulkanImage)),
                    [], ContextWaitEvent())
        }
    }
    
    func depositImage(_ image: VkImageReference, events: [FenceDependency], waitSemaphore: ContextWaitEvent) {
        assert(events.isEmpty)
        // Delay returning the resource to the pool until the start of the next frame so we don't need to track hazards within the frame.
        // This slightly increases memory usage but greatly simplifies resource tracking, and besides, heaps should be used instead
        // for cases where memory usage is important.
        self.imagesUsedThisFrame.append(ResourceReference(resource: image, waitSemaphore: waitSemaphore))
    }
    
    func collectBuffer(descriptor: VulkanBufferDescriptor) -> (VkBufferReference, [FenceDependency], ContextWaitEvent) {
        if let buffer = self.bufferFitting(descriptor: descriptor) {
            return (buffer.0, [], buffer.1)
        } else {
            var allocInfo = VmaAllocationCreateInfo(storageMode: descriptor.storageMode, cacheMode: descriptor.cacheMode)
            
            var buffer : VkBuffer? = nil
            var allocation : VmaAllocation? = nil
            var allocationInfo = VmaAllocationInfo()
            descriptor.withBufferCreateInfo(device: self.device) { (info) in
                var info = info
                vmaCreateBuffer(self.allocator, &info, &allocInfo, &buffer, &allocation, &allocationInfo)
            }
            
            let vulkanBuffer = VulkanBuffer(device: self.device, buffer: buffer!, allocator: self.allocator, allocation: allocation!, allocationInfo: allocationInfo, descriptor: descriptor)
            return (VkBufferReference(buffer: Unmanaged.passRetained(vulkanBuffer), offset: 0),
                    [], ContextWaitEvent())
        }
    }
    
    func depositBuffer(_ buffer: VkBufferReference, events: [FenceDependency], waitSemaphore: ContextWaitEvent) {
        assert(events.isEmpty)
        // Delay returning the resource to the pool until the start of the next frame so we don't need to track hazards within the frame.
        // This slightly increases memory usage but greatly simplifies resource tracking, and besides, heaps should be used instead
        // for cases where memory usage is important.
        self.buffersUsedThisFrame.append(ResourceReference(resource: buffer, waitSemaphore: waitSemaphore))
    }
    
    func cycleFrames() {
        do {
            var i = 0
            while i < self.buffers[self.currentIndex].count {
                self.buffers[self.currentIndex][i].framesUnused += 1
                
                if self.buffers[self.currentIndex][i].framesUnused > 2 {
                    let buffer = self.buffers[self.currentIndex].remove(at: i, preservingOrder: false)
                    buffer.resource._buffer.release()
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
                    let image = self.images[self.currentIndex].remove(at: i, preservingOrder: false)
                    image.resource._image.release()
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

