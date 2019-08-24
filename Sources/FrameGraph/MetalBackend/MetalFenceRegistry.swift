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
    public var generation : UInt32
    public var index : UInt32
    
    init(generation: UInt32, index: UInt32) {
        self.generation = generation
        self.index = index
    }
    
    init() {
        self = MetalFenceRegistry.instance.allocate(frame: FrameGraph.currentFrameIndex)
    }
    
    var isValid : Bool {
        return self.index != .max && self.generation == MetalFenceRegistry.instance.generations[Int(self.index)]
    }
    
    var fence : MTLFence {
        assert(self.isValid)
        return MetalFenceRegistry.instance.fences[Int(self.index)].takeUnretainedValue()
    }
    
    var frame : UInt64 {
        assert(self.isValid)
        return MetalFenceRegistry.instance.frames[Int(self.index)]
    }
    
    func retain() {
        MetalFenceRegistry.instance.retain(self)
    }
    
    func release() {
        MetalFenceRegistry.instance.release(self)
    }
    
    public static let invalid = MetalFenceHandle(generation: .max, index: .max)
}


final class MetalFenceRegistry {
    public static let instance = MetalFenceRegistry()
    
    public let allocator : ResizingAllocator
    public var freeIndices = RingBuffer<UInt32>()
    public var pendingFreeIndices = [UInt32]()
    public var maxIndex : UInt32 = 0
    
    public var device : MTLDevice! = nil
    
    public var fences : UnsafeMutablePointer<Unmanaged<MTLFence>>
    public var generations : UnsafeMutablePointer<UInt32>
    public var retainCounts : UnsafeMutablePointer<UInt32>
    public var frames : UnsafeMutablePointer<UInt64>
    
    public init() {
        self.allocator = ResizingAllocator(allocator: .system)
        (self.fences, self.generations, self.retainCounts, self.frames) = allocator.reallocate(capacity: 256, initializedCount: 0)
        self.generations.initialize(repeating: 0, count: self.allocator.capacity)
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
            self.generations.advanced(by: Int(index)).initialize(to: 0)
        }
        
        self.retainCounts[Int(index)] = 1
        self.frames[Int(index)] = frame
        
        return MetalFenceHandle(generation: self.generations[Int(index)], index: index)
    }
    
    func delete(at index: UInt32) {
        assert(self.retainCounts[Int(index)] == 0)
        
        self.freeIndices.append(index)
        self.generations[Int(index)] = self.generations[Int(index)] &+ 1
    }
    
    public func retain(_ fence: MetalFenceHandle) {
        assert(fence.isValid)
        
        self.retainCounts[Int(fence.index)] += 1
    }
    
    public func release(_ fence: MetalFenceHandle) {
        guard fence.isValid else {
            return
        }
        
        self.retainCounts[Int(fence.index)] -= 1
        if self.retainCounts[Int(fence.index)] == 0 {
            self.pendingFreeIndices.append(fence.index)
        }
    }
    
    func clearCompletedFences() {
        let lastCompletedFrame = FrameCompletion.lastCompletedFrame
        for i in 0..<Int(self.maxIndex) {
            if self.retainCounts[i] != 0, self.frames[i] <= lastCompletedFrame {
                self.retainCounts[i] = 0
                self.delete(at: UInt32(i))
            }
        }
    }
    
    func cycleFrames() {
        self.freeIndices.reserveCapacity(self.freeIndices.count + self.pendingFreeIndices.count)
        for i in self.pendingFreeIndices {
            self.delete(at: i)
        }
        self.pendingFreeIndices.removeAll(keepingCapacity: true)
    }
    
    @inlinable
    public func ensureCapacity(_ capacity: Int) {
        if self.allocator.capacity < capacity {
            let oldCapacity = self.allocator.capacity
            let newCapacity = max(2 * oldCapacity, capacity)
            (self.fences, self.generations, self.retainCounts, self.frames) = allocator.reallocate(capacity: newCapacity, initializedCount: Int(self.maxIndex))
        }
    }
}

#endif // canImport(Metal)
