//
//  Memory.swift
//  Raytracer
//
//  Created by Thomas Roughton on 23/07/17.
//

import Utilities
import Metal
import RenderAPI

fileprivate class TemporaryBufferArena {
    
    private static let blockAlignment = 64
    
    let device : MTLDevice
    let options : MTLResourceOptions
    
    private let blockSize : Int
    var currentBlockPos = 0
    var currentBlock : MTLBuffer? = nil
    var usedBlocks = LinkedList<MTLBuffer>()
    var availableBlocks = LinkedList<MTLBuffer>()
    
    // MemoryArena Public Methods
    public init(blockSize: Int = 262144, device: MTLDevice, options: MTLResourceOptions) {
        self.blockSize = blockSize
        self.device = device
        self.options = options
    }
    
    func allocate(bytes: Int, alignedTo alignment: Int) -> (MTLBuffer, Int) {
        let alignedPosition = (currentBlockPos + alignment - 1) & ~(alignment - 1)
        
        if (alignedPosition + bytes > (currentBlock?.length ?? -1)) {
            // Add current block to usedBlocks list
            if let currentBlock = self.currentBlock {
                usedBlocks.append(currentBlock)
                self.currentBlock = nil
            }
            
            
            // Try to get memory block from availableBlocks
            let iterator = self.availableBlocks.makeIterator()
            while let block = iterator.next() {
                if block.length >= bytes {
                    self.currentBlock = block
                    iterator.removeLast()
                    break
                }
            }
            if self.currentBlock == nil {
                let allocationSize = max(bytes, self.blockSize)
                
                self.currentBlock = device.makeBuffer(length: allocationSize, options: [self.options, .hazardTrackingModeUntracked])
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

class TemporaryBufferAllocator : BufferAllocator {
    
    private var arenas : [TemporaryBufferArena]
    
    let numFrames : Int
    let options : MTLResourceOptions
    private var currentIndex : Int = 0
    
    public init(device: MTLDevice, numFrames: Int, blockSize: Int, options: MTLResourceOptions) {
        self.numFrames = numFrames
        self.options = options
        self.arenas = (0..<numFrames).map { _ in TemporaryBufferArena(blockSize: blockSize, device: device, options: options) }
    }
    
    public func allocate(bytes: Int) -> (MTLBuffer, Int) {
        let alignment = 256
        return self.arenas[self.currentIndex].allocate(bytes: bytes, alignedTo: alignment)
    }
    
    func collectBufferWithLength(_ length: Int, options: MTLResourceOptions) -> MTLBufferReference {
        let (buffer, offset) = self.allocate(bytes: length)
        return MTLBufferReference(buffer: buffer, offset: offset)
    }
    
    func depositBuffer(_ buffer: MTLBufferReference) {
        // No-op; the buffers are cleared in cycleFrames.
    }
    
    public func cycleFrames() {
        self.currentIndex = (self.currentIndex + 1) % self.numFrames
        self.arenas[self.currentIndex].reset()
    }
}
