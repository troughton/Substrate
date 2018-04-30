/*
    pbrt source code is Copyright(c) 1998-2016
                        Matt Pharr, Greg Humphreys, and Wenzel Jakob.
    This file is part of pbrt.
    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are
    met:
    - Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    - Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
    IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
    TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
    PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
    HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
    SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
    LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
    DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
    THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
    (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
    OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

//
//  Memory.swift
//  Raytracer
//
//  Created by Thomas Roughton on 23/07/17.
//  Adapted from https://github.com/mmp/pbrt-v3/blob/master/src/core/memory.h

public class MemoryArena {
    
    private static let blockAlignment = 256
    
    private let blockSize : Int
    var currentBlockPos = 0
    var currentAllocSize = -1
    var currentBlock : UnsafeMutableRawPointer? = nil
    var usedBlocks = LinkedList<(Int, UnsafeMutableRawPointer)>()
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
    public func allocate<T>(count: Int = 1) -> UnsafeMutablePointer<T> {
        let stride = count == 1 ? MemoryLayout<T>.size : MemoryLayout<T>.stride
        let retVal = self.allocate(bytes: count * stride, alignedTo: MemoryLayout<T>.alignment).bindMemory(to: T.self, capacity: count)
        
        return retVal
    }
    
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
