//
//  VulkanEventRegistry.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 20/07/19.
//

// See also: MetalFenceRegistry, since MTLFence is the Metal equivalent to VkEvent

#if canImport(Vulkan)

import Vulkan
import FrameGraphUtilities

struct VulkanEventHandle : Equatable {
    public var index : UInt32
    
    init(index: UInt32) {
        self.index = index
    }
    
    init(label: String, queue: Queue, commandBufferIndex: UInt64) {
        self = VulkanEventRegistry.instance.allocate(queue: queue, commandBufferIndex: commandBufferIndex)
    }
    
    var isValid : Bool {
        return self.index != .max
    }
    
    var event : VkEvent {
        assert(self.isValid)
        return VulkanEventRegistry.instance.events[Int(self.index)]
    }
    
    var commandBufferIndex : UInt64 {
        assert(self.isValid)
        return VulkanEventRegistry.instance.commandBufferIndices[Int(self.index)].1
    }
    
    public static let invalid = VulkanEventHandle(index: .max)
}


final class VulkanEventRegistry {
    public static let instance = VulkanEventRegistry()
    
    public let allocator : ResizingAllocator
    public var activeIndices = [UInt32]()
    public var freeIndices = RingBuffer<UInt32>()
    public var maxIndex : UInt32 = 0
    
    public var device : VkDevice! = nil
    
    public var events : UnsafeMutablePointer<VkEvent>
    public var commandBufferIndices : UnsafeMutablePointer<(Queue, UInt64)> // On the queue
    
    public init() {
        self.allocator = ResizingAllocator(allocator: .system)
        (self.events, self.commandBufferIndices) = allocator.reallocate(capacity: 256, initializedCount: 0)
    }
    
    deinit {
        for index in self.freeIndices {
            vkDestroyEvent(self.device, self.events[Int(index)], nil)
        }
    }
    
    public func allocate(queue: Queue, commandBufferIndex: UInt64) -> VulkanEventHandle {
        let index : UInt32
        if let reusedIndex = self.freeIndices.popFirst() {
            index = reusedIndex
        } else {
            index = self.maxIndex
            self.ensureCapacity(Int(self.maxIndex + 1))
            self.maxIndex += 1
            
            var event : VkEvent? = nil
            var createInfo = VkEventCreateInfo(sType: VK_STRUCTURE_TYPE_EVENT_CREATE_INFO, pNext: nil, flags: 0)
            vkCreateEvent(self.device, &createInfo, nil, &event).check()
            self.events.advanced(by: Int(index)).initialize(to: event!)
        }

        self.commandBufferIndices[Int(index)] = (queue, commandBufferIndex)
        self.activeIndices.append(index)
        
        return VulkanEventHandle(index: index)
    }
    
    func delete(at index: UInt32) {
        vkResetEvent(self.device, self.events[Int(index)])
        self.freeIndices.append(index)
    }

    func clearCompletedEvents() {
        var i = 0
        while i < self.activeIndices.count {
            let index = self.activeIndices[i]
            if self.commandBufferIndices[Int(index)].1 <= self.commandBufferIndices[Int(index)].0.lastCompletedCommand {
                self.delete(at: index)
                self.activeIndices.remove(at: i, preservingOrder: false)
            } else {
                i += 1
            }
        }
    }
    
    @inlinable
    public func ensureCapacity(_ capacity: Int) {
        if self.allocator.capacity < capacity {
            let oldCapacity = self.allocator.capacity
            let newCapacity = max(2 * oldCapacity, capacity)
            (self.events, self.commandBufferIndices) = allocator.reallocate(capacity: newCapacity, initializedCount: Int(self.maxIndex))
        }
    }
}

#endif // canImport(Metal)
