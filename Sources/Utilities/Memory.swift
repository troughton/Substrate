//
//  Memory.swift
//  Raytracer
//
//  Created by Thomas Roughton on 23/07/17.
//

@_fixed_layout
public final class MemoryArena {
    @usableFromInline
    static let blockAlignment = 256
    
    @usableFromInline
    let blockSize : Int
    @usableFromInline
    var currentBlockPos = 0
    @usableFromInline
    var currentAllocSize = -1
    @usableFromInline
    var currentBlock : UnsafeMutableRawPointer? = nil
    @usableFromInline
    var usedBlocks = LinkedList<(Int, UnsafeMutableRawPointer)>()
    @usableFromInline
    var availableBlocks = LinkedList<(Int, UnsafeMutableRawPointer)>()
    
    // MemoryArena Public Methods
    public init(blockSize: Int = 262144) {
        self.blockSize = blockSize
    }
    
    deinit {
        self.currentBlock?.deallocate()
        for block in self.usedBlocks {
            block.1.deallocate()
        }
        for block in self.availableBlocks {
            block.1.deallocate()
        }
    }
    
    @inlinable
    public func allocate(bytes: Int, alignedTo alignment: Int) -> UnsafeMutableRawPointer {
        let alignedPosition = (currentBlockPos + alignment - 1) & ~(alignment - 1)
        
        if (alignedPosition + bytes > currentAllocSize) {
            // Add current block to usedBlocks list
            if let currentBlock = self.currentBlock {
                usedBlocks.append((currentAllocSize, currentBlock))
                self.currentBlock = nil
                self.currentAllocSize = 0
            }
            
            // Try to get memory block from availableBlocks
            let iterator = self.availableBlocks.makeIterator()
            while let block = iterator.next() {
                if block.0 >= bytes {
                    self.currentAllocSize = block.0
                    self.currentBlock = block.1;
                    iterator.removeLast()
                    break
                }
            }
            if self.currentBlock == nil {
                self.currentAllocSize = max(bytes, self.blockSize);
                self.currentBlock = UnsafeMutableRawPointer.allocate(byteCount: currentAllocSize, alignment: MemoryArena.blockAlignment)
            }
            self.currentBlockPos = 0
            return self.allocate(bytes: bytes, alignedTo: alignment)
        }
        let retVal = self.currentBlock! + alignedPosition
        self.currentBlockPos = (alignedPosition + bytes)
        return retVal
    }
    
    /// NOTE: Returns uninitialised memory that the user is responsible for initialising or deinitialising.
    @inlinable
    public func allocate<T>(count: Int = 1) -> UnsafeMutablePointer<T> {
        let stride = count == 1 ? MemoryLayout<T>.size : MemoryLayout<T>.stride
        let retVal = self.allocate(bytes: count * stride, alignedTo: MemoryLayout<T>.alignment).bindMemory(to: T.self, capacity: count)
        
        return retVal
    }
    
    @inlinable
    public func reset() {
        self.currentBlockPos = 0
        self.availableBlocks.prependAndClear(contentsOf: usedBlocks)
    }
    
    public var totalAllocatedSize : Int {
        var total = self.currentAllocSize
        for block in self.usedBlocks { total += block.0 }
        for block in self.availableBlocks { total += block.0 }
        return total
    }
}
