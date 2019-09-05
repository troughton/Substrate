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
    
    init() {
        self = MetalFenceRegistry.instance.allocate()
    }
    
    var isValid : Bool {
        return self.index != .max
    }
    
    var fence : MTLFence {
        assert(self.isValid)
        return MetalFenceRegistry.instance.fences[Int(self.index)].takeUnretainedValue()
    }
    
    
    public static let invalid = MetalFenceHandle(index: .max)
}


final class MetalFenceRegistry {
    public static let instance = MetalFenceRegistry()
    
    public let allocator : ResizingAllocator
    public var maxIndex : UInt32 = 0
    public var nextIndex : UInt32 = 0
    
    public var device : MTLDevice! = nil
    
    public var fences : UnsafeMutablePointer<Unmanaged<MTLFence>>
    
    public init() {
        self.allocator = ResizingAllocator(allocator: .system)
        (self.fences) = allocator.reallocate(capacity: 256, initializedCount: 0)
    }
    
    deinit {
        self.fences.deinitialize(count: Int(self.maxIndex))
    }
    
    public func allocate() -> MetalFenceHandle {
        let index : UInt32
        if nextIndex < maxIndex {
            index = nextIndex
            nextIndex += 1
        } else {
            index = self.maxIndex
            self.ensureCapacity(Int(self.maxIndex + 1))
            self.maxIndex += 1
        }
        
        return MetalFenceHandle(index: index)
    }
    
    func cycleFrames() {
        self.nextIndex = 0
    }
    
    @inlinable
    public func ensureCapacity(_ capacity: Int) {
        if self.allocator.capacity < capacity {
            let oldCapacity = self.allocator.capacity
            let newCapacity = max(2 * oldCapacity, capacity)
            (self.fences) = allocator.reallocate(capacity: newCapacity, initializedCount: Int(self.maxIndex))
        }
    }
}

#endif // canImport(Metal)
