//
//  Memory.swift
//  Raytracer
//
//  Created by Thomas Roughton on 23/07/17.
//

#if canImport(Metal)

import SubstrateUtilities
@preconcurrency import Metal

fileprivate class TemporaryBufferArena {
    
    private static let blockAlignment = 64
    
    let device : MTLDevice
    let options : MTLResourceOptions
    
    private let blockSize : Int
    var currentBlockPos = 0
    var currentBlock : MTLBuffer? = nil
    var usedBlocks = [MTLBuffer]()
    var availableBlocks = [(buffer: MTLBuffer, isPurged: Bool)]()
    
    // MemoryArena Public Methods
    public init(blockSize: Int = 262144, device: MTLDevice, options: MTLResourceOptions) {
        self.blockSize = blockSize
        self.device = device
        self.options = options
    }
    
    func allocate(bytes: Int, alignedTo alignment: Int) -> (MTLBuffer, Int) {
        let alignment = bytes == 0 ? 1 : alignment // Don't align for empty allocations
        let alignedPosition = (currentBlockPos + alignment - 1) & ~(alignment - 1)
        
        if (alignedPosition + bytes > (currentBlock?.length ?? -1)) {
            // Add current block to usedBlocks list
            if let currentBlock = self.currentBlock {
                usedBlocks.append(currentBlock)
                self.currentBlock = nil
            }
            
            // Try to get memory block from availableBlocks
            var i = 0
            while i < self.availableBlocks.count {
                let (block, isPurged) = self.availableBlocks[i]
                if block.length >= bytes {
                    if isPurged {
                        block.setPurgeableState(.nonVolatile)
                    }
                    self.currentBlock = block
                    self.availableBlocks.remove(at: i, preservingOrder: false)
                    break
                }
                i += 1
            }
            if self.currentBlock == nil {
                let allocationSize = max(bytes * 3 / 2, self.blockSize)
                
                self.currentBlock = device.makeBuffer(length: allocationSize, options: [self.options, .substrateTrackedHazards])
                
#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
                self.currentBlock!.label = "Block for TemporaryBufferArena \(ObjectIdentifier(self))"
#endif
            }
            self.currentBlockPos = 0
            return self.allocate(bytes: bytes, alignedTo: alignment)
        }
        let retVal = (self.currentBlock!, alignedPosition)
        self.currentBlockPos = (alignedPosition + bytes)
        return retVal
    }
    
    func makePurgeable() {
        precondition(self.usedBlocks.isEmpty && self.currentBlock == nil)
        for i in self.availableBlocks.indices {
            self.availableBlocks[i].buffer.setPurgeableState(.empty)
            self.availableBlocks[i].isPurged = true
        }
    }
    
    func flush() {
    #if os(macOS) || targetEnvironment(macCatalyst)
        if self.options.contains(.storageModeManaged) {
            for block in self.usedBlocks {
                block.didModifyRange(0..<block.length)
            }
            if self.currentBlockPos > 0 {
                self.currentBlock?.didModifyRange(0..<self.currentBlockPos)
            }
        }
    #endif
    }
    
    func reset() {
        self.availableBlocks.append(contentsOf: self.usedBlocks.lazy.map { ($0, false) })
        self.usedBlocks.removeAll(keepingCapacity: true)
        if let currentBlock = self.currentBlock {
            self.availableBlocks.append((currentBlock, false))
        }
        for (buffer, _) in self.availableBlocks {
            buffer.removeAllDebugMarkers()
        }
        self.currentBlock = nil
        self.currentBlockPos = 0
    }
}

class MetalTemporaryBufferAllocator : MetalBufferAllocator {
    private var arenas : [TemporaryBufferArena]
    
    let numFrames : Int
    let options : MTLResourceOptions
    let alignment: Int
    private var currentIndex : Int = 0
    private var waitEvent : ContextWaitEvent = .init()
    private var nextFrameWaitEvent : ContextWaitEvent = .init()
    
    public init(device: MTLDevice, numFrames: Int, blockSize: Int, options: MTLResourceOptions) {
        self.numFrames = numFrames
        self.options = options
        self.alignment = device.isAppleSiliconGPU ? 16 : 256
        self.arenas = (0..<numFrames).map { _ in TemporaryBufferArena(blockSize: blockSize, device: device, options: options) }
    }
    
    public func allocate(bytes: Int) -> (MTLBuffer, Int) {
        return self.arenas[self.currentIndex].allocate(bytes: bytes, alignedTo: self.alignment)
    }
    
    func collectBufferWithLength(_ length: Int, options: MTLResourceOptions) -> (MTLBufferReference, [FenceDependency], ContextWaitEvent) {
        assert(options == self.options)
        let (buffer, offset) = self.allocate(bytes: length)
        return (MTLBufferReference(buffer: Unmanaged.passUnretained(buffer), offset: offset), [], self.waitEvent)
    }
    
    func depositBuffer(_ buffer: MTLBufferReference, fences: [FenceDependency], waitEvent: ContextWaitEvent) {
        assert(fences.isEmpty)
        if self.nextFrameWaitEvent.waitValue < waitEvent.waitValue {
            self.nextFrameWaitEvent = waitEvent
        }  else {
            self.nextFrameWaitEvent.afterStages.formUnion(waitEvent.afterStages)
        }
    }
    
    func flush() {
        self.arenas[self.currentIndex].flush()
    }
        
    func makePurgeable() {
        for arena in self.arenas {
            arena.makePurgeable()
        }
    }
    
    public func cycleFrames() {
        self.arenas[self.currentIndex].reset()
        self.currentIndex = (self.currentIndex + 1) % self.numFrames
        self.waitEvent = self.nextFrameWaitEvent
        self.nextFrameWaitEvent = .init()
    }
}

#endif // canImport(Metal)
