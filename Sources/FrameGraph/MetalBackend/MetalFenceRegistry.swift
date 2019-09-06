//
//  MetalFenceRegistry.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 20/07/19.
//

#if canImport(Metal)

import Metal
import FrameGraphUtilities

struct MetalFenceHandle : Equatable {
    public var index : UInt32
    
    init(index: UInt32) {
        self.index = index
    }
    
    init(label: String) {
        self = MetalFenceRegistry.instance.allocate(frame: FrameGraph.currentFrameIndex)
        self.fence.label = label
    }
    
    var isValid : Bool {
        return self.index != .max
    }
    
    var fence : MTLFence {
        assert(self.isValid)
        return MetalFenceRegistry.instance.fences[Int(self.index)].takeUnretainedValue()
    }
    
    var frame : UInt64 {
        assert(self.isValid)
        return MetalFenceRegistry.instance.frames[Int(self.index)]
    }
    
    public static let invalid = MetalFenceHandle(index: .max)
}


final class MetalFenceRegistry {
    public static let instance = MetalFenceRegistry()
    
    public let allocator : ResizingAllocator
    public var freeIndices = RingBuffer<UInt32>()
    public var maxIndex : UInt32 = 0
    
    public var device : MTLDevice! = nil
    
    public var fences : UnsafeMutablePointer<Unmanaged<MTLFence>>
    public var frames : UnsafeMutablePointer<UInt64>
    
    public init() {
        self.allocator = ResizingAllocator(allocator: .system)
        (self.fences, self.frames) = allocator.reallocate(capacity: 256, initializedCount: 0)
    }
    
    deinit {
        self.fences.deinitialize(count: Int(self.maxIndex))
    }
    
    public func allocate(frame: UInt64) -> MetalFenceHandle {
        let index : UInt32
        if let reusedIndex = self.freeIndices.popFirst() {
            index = reusedIndex
        } else {
            index = self.maxIndex
            self.ensureCapacity(Int(self.maxIndex + 1))
            self.maxIndex += 1
            
            self.fences.advanced(by: Int(index)).initialize(to: Unmanaged.passRetained(self.device.makeFence()!))
        }

        self.frames[Int(index)] = frame
        
        return MetalFenceHandle(index: index)
    }
    
    func delete(at index: UInt32) {
        self.freeIndices.append(index)
    }

    func clearCompletedFences() {
        let lastCompletedFrame = FrameCompletion.lastCompletedFrame
        for i in 0..<Int(self.maxIndex) {
            if self.frames[i] <= lastCompletedFrame {
                self.delete(at: UInt32(i))
            }
        }
    }
    
    @inlinable
    public func ensureCapacity(_ capacity: Int) {
        if self.allocator.capacity < capacity {
            let oldCapacity = self.allocator.capacity
            let newCapacity = max(2 * oldCapacity, capacity)
            (self.fences, self.frames) = allocator.reallocate(capacity: newCapacity, initializedCount: Int(self.maxIndex))
        }
    }
}

#endif // canImport(Metal)