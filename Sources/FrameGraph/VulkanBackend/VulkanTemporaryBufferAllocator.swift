//
//  Memory.swift
//  Raytracer
//
//  Created by Thomas Roughton on 23/07/17.
//

#if canImport(Vulkan)
import Vulkan
import FrameGraphUtilities
import FrameGraphCExtras
import SwiftFrameGraph

fileprivate class TemporaryBufferArena {
    
    private static let blockAlignment = 64
    
    let device : VulkanDevice
    let allocator : VmaAllocator
    
    private let blockSize : Int
    var currentBlockPos = 0
    var currentBlock : VulkanBuffer? = nil
    var usedBlocks = LinkedList<VulkanBuffer>()
    var availableBlocks = LinkedList<VulkanBuffer>()
    
    // MemoryArena Public Methods
    public init(blockSize: Int = 262144, allocator: VmaAllocator, device: VulkanDevice) {
        self.blockSize = blockSize
        self.allocator = allocator
        self.device = device
        
    }
    
    func allocate(bytes: Int, alignedTo alignment: Int) -> (VulkanBuffer, Int) {
        let alignedPosition = (currentBlockPos + alignment - 1) & ~(alignment - 1)
        
        if (alignedPosition + bytes > (currentBlock?.descriptor.size ?? 0)) {
            // Add current block to usedBlocks list
            if let currentBlock = self.currentBlock {
                usedBlocks.append(currentBlock)
                self.currentBlock = nil
            }
            
            
            // Try to get memory block from availableBlocks
            let iterator = self.availableBlocks.makeIterator()
            while let block = iterator.next() {
                if block.descriptor.size >= bytes {
                    self.currentBlock = block
                    iterator.removeLast()
                    break
                }
            }
            if self.currentBlock == nil {
                let allocationSize = max(bytes, self.blockSize)
                
                let renderAPIDescriptor = BufferDescriptor(length: allocationSize, storageMode: .managed, cacheMode: .defaultCache, usage: .shaderRead)
                
                var allocInfo = VmaAllocationCreateInfo()
                allocInfo.usage = VMA_MEMORY_USAGE_CPU_TO_GPU
                // FIXME: is it actually valid to have a buffer being used without ownership transfers?
                let descriptor = VulkanBufferDescriptor(renderAPIDescriptor, usage: .uniformBuffer, sharingMode: .concurrent(QueueFamilies.all))
                var buffer : VkBuffer? = nil
                var allocation : VmaAllocation? = nil
                var allocationInfo = VmaAllocationInfo()
                descriptor.withBufferCreateInfo(device: self.device) { (info) in
                    var info = info
                    vmaCreateBuffer(self.allocator, &info, &allocInfo, &buffer, &allocation, &allocationInfo)
                }
                
                self.currentBlock = VulkanBuffer(device: self.device, buffer: buffer!, allocator: self.allocator, allocation: allocation!, allocationInfo: allocationInfo, descriptor: descriptor)
            }
            self.currentBlockPos = 0
            return self.allocate(bytes: bytes, alignedTo: alignment)
        }
        let retVal = (self.currentBlock!, alignedPosition)
        self.currentBlockPos = (alignedPosition + bytes)
        return retVal
    }
    
    func reset() {
        self.currentBlockPos = 0
        self.availableBlocks.prependAndClear(contentsOf: usedBlocks)
    }
}

class TemporaryBufferAllocator {
    private var arenas : [TemporaryBufferArena]
    
    let numFrames : Int
    private var currentIndex : Int = 0
    
    public init(numFrames: Int, allocator: VmaAllocator, device: VulkanDevice) {
        self.numFrames = numFrames
        self.arenas = (0..<numFrames).map { _ in TemporaryBufferArena(allocator: allocator, device: device) }
    }
    
    public func bufferStoring(bytes: UnsafeRawPointer, length: Int) -> (VulkanBuffer, Int) {
        let (buffer, offset) = self.arenas[self.currentIndex].allocate(bytes: length, alignedTo: 256)
        let destination = buffer.map(range: offset..<(offset + length))
        destination.copyMemory(from: bytes, byteCount: length)
        buffer.unmapMemory(range: offset..<(offset + length))
        return (buffer, offset)
    }
    
    public func cycleFrames() {
        self.currentIndex = (self.currentIndex + 1) % self.numFrames
        self.arenas[self.currentIndex].reset()
    }
}

#endif // canImport(Vulkan)
