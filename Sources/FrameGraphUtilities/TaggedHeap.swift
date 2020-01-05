//
//  TaggedHeap.swift
//  NaughtyDogAllocator
//
//  Created by Thomas Roughton on 8/05/19.
//  Copyright © 2019 Thomas Roughton. All rights reserved.
//

import Foundation

// For debugging: use the system allocator rather than the tagged heap.
@usableFromInline let useSystemAllocator = false

public enum TaggedHeap {
    // Block based allocator
    // Each block is 2MiB
    // Each block is owned by a UInt64 tag (e.g. hashed allocator name + frame number).
    
    // Everything is stored in bitsets.
    // We need: a list of allocated blocks (bitset)
    // A per-tag list of blocks assigned to that tag. Could use a dictionary of [Tag : BitSet] and a pool of free [BitSet]s? Means data is malloc'ed instead, but does that really matter?
    // Also need a spin-lock.
    
    public typealias Tag = UInt64
    public static let blockSize = 2 * 1024 * 1024
    
    static var blockCount : Int = 0
    static var bitSetStorageCount : Int = 0
    @usableFromInline static var heapMemory : UnsafeMutableRawPointer? = nil
    static var spinLock = SpinLock()
    static var filledBlocks : AtomicBitSet! = nil
    
    static var blocksByTag : [Tag : BitSet]! = nil
    static var freeBitsets : [BitSet]! = nil
    
    #if os(macOS)
    public static let heapCapacity = 2 * 1024 * 1024 * 1024
    #else
    public static let heapCapacity = 512 * 1024 * 1024
    #endif
    
    public static func initialise(capacity: Int = TaggedHeap.heapCapacity) {
        self.blockCount = (capacity + TaggedHeap.blockSize - 1) / TaggedHeap.blockSize
        self.bitSetStorageCount = (self.blockCount + BitSet.bitsPerElement) / BitSet.bitsPerElement
        
        self.heapMemory = UnsafeMutableRawPointer.allocate(byteCount: TaggedHeap.blockSize * blockCount, alignment: TaggedHeap.blockSize)
        
        self.filledBlocks = AtomicBitSet(storageCount: bitSetStorageCount)
        self.blocksByTag = [:]
        self.freeBitsets = []
    }
    
    static func findContiguousBlock(count: Int) -> Int {
        for i in 0..<(self.blockCount - count) {
            if self.filledBlocks.testBitsAreClear(in: i..<(i + count)) {
                return i
            }
        }
        
        return .max
    }
    
    static func taggedBlockList(tag: Tag) -> BitSet {
        if let tagList = self.blocksByTag[tag] {
            return tagList
        }
        
        let list = self.freeBitsets.popLast() ?? BitSet(storageCount: self.bitSetStorageCount)
        self.blocksByTag[tag] = list
        return list
    }
    
    public static func allocateBlocks(tag: Tag, count: Int) -> UnsafeMutableRawPointer {
        var blockIndex = self.findContiguousBlock(count: count)
        if blockIndex == .max {
            print("TaggedHeap error: no free blocks available! Allocating from the system allocator; memory will be leaked.")
            return UnsafeMutableRawPointer.allocate(byteCount: count * TaggedHeap.blockSize, alignment: TaggedHeap.blockSize)
        }
        
        return self.spinLock.withLock {
            while !self.filledBlocks.testBitsAreClear(in: blockIndex..<(blockIndex + count)) {
                blockIndex = self.findContiguousBlock(count: count)
            }
            
            let tagBitset = self.taggedBlockList(tag: tag)
            self.filledBlocks.unsafelyUnwrapped.setBits(in: blockIndex..<(blockIndex + count))
            tagBitset.setBits(in: blockIndex..<(blockIndex + count))
            
            return self.heapMemory.unsafelyUnwrapped + blockIndex * TaggedHeap.blockSize
        }
    }
    
    /// For debugging only; not efficient.
    public static func tag(for pointer: UnsafeRawPointer) -> Tag? {
        return self.spinLock.withLock {
            let block = (pointer - UnsafeRawPointer(self.heapMemory!)) / self.blockSize
            assert(block >= 0 && block < self.blockCount)
            for (tag, blocks) in self.blocksByTag {
                if blocks[block] {
                    return tag
                }
            }
            return nil
        }
    }
    
    /// For debugging only; not efficient.
    public static func tagMatches(_ tag: Tag, pointer: UnsafeRawPointer) -> Bool {
        return self.spinLock.withLock {
            let block = (pointer - UnsafeRawPointer(self.heapMemory!)) / self.blockSize
            assert(block >= 0 && block < self.blockCount)
            
            guard let blocks = self.blocksByTag[tag] else {
                return false
            }
            return blocks[block]
        }
    }
    
    public static func free(tag: Tag) {
        // Should use a bit-list to track all blocks associated with a specific tag.
        self.spinLock.withLock {
            guard let blocks = self.blocksByTag.removeValue(forKey: tag) else { return }
            
            self.filledBlocks.clearBits(in: blocks)
            
            blocks.clear()
            self.freeBitsets.append(blocks)
        }
    }
}

/// A tag allocator which is shared between threads
public struct LockingTagAllocator {
    
    @usableFromInline
    struct Header {
        @usableFromInline var lock : SpinLock
        @usableFromInline let tag : TaggedHeap.Tag
        @usableFromInline var memory : UnsafeMutableRawPointer
        @usableFromInline var offset : Int
        @usableFromInline var allocationSize : Int
        
        @inlinable
        init(tag: TaggedHeap.Tag, memory: UnsafeMutableRawPointer, offset: Int, allocationSize: Int) {
            self.lock = SpinLock()
            self.tag = tag
            self.memory = memory
            self.offset = offset
            self.allocationSize = allocationSize
        }
        
        @inlinable
        mutating func allocate(bytes: Int, alignment: Int) -> UnsafeMutableRawPointer {
            let alignedOffset = (self.offset + alignment - 1) & ~(alignment - 1)
            if alignedOffset + bytes <= self.allocationSize {
                defer { self.offset = alignedOffset + bytes }
                return self.memory.advanced(by: alignedOffset)
            }
            
            let requiredBlocks = (bytes + TaggedHeap.blockSize - 1) / TaggedHeap.blockSize
            self.memory = TaggedHeap.allocateBlocks(tag: self.tag, count: requiredBlocks)
            self.allocationSize = requiredBlocks * TaggedHeap.blockSize
            self.offset = bytes
            
            return self.memory
        }
    }
    
    @usableFromInline let header : UnsafeMutablePointer<Header>
    
    @inlinable
    public init(tag: TaggedHeap.Tag) {
        let block = TaggedHeap.allocateBlocks(tag: tag, count: 1)
        
        let header = Header(
            tag: tag,
            memory: block,
            offset: MemoryLayout<Header>.stride,
            allocationSize: TaggedHeap.blockSize)
        
        self.header = block.bindMemory(to: Header.self, capacity: 1)
        self.header.initialize(to: header)
    }
    
    @inlinable
    public var isValid : Bool {
        return TaggedHeap.tagMatches(self.header.pointee.tag, pointer: self.header.pointee.memory)
    }
    
    @inlinable
    public func allocate(bytes: Int, alignment: Int) -> UnsafeMutableRawPointer {
        if useSystemAllocator {
            return .allocate(byteCount: bytes, alignment: alignment)
        }
        
        self.header.pointee.lock.lock()
        defer { self.header.pointee.lock.unlock() }
        return self.header.pointee.allocate(bytes: bytes, alignment: alignment)
    }
    
    @inlinable
    public func allocate<T>(capacity: Int) -> UnsafeMutablePointer<T> {
        if useSystemAllocator {
            return .allocate(capacity: capacity)
        }
        
        return self.allocate(bytes: capacity * MemoryLayout<T>.stride, alignment: MemoryLayout<T>.alignment).bindMemory(to: T.self, capacity: capacity)
    }
    
    @inlinable
    public func deallocate(_ pointer: UnsafeMutableRawPointer) {
        if useSystemAllocator {
            return pointer.deallocate()
        }
        
        // No-op.
    }

    @inlinable
    public func deallocate<T>(_ pointer: UnsafeMutablePointer<T>) {
        if useSystemAllocator {
            return pointer.deallocate()
        }
        // No-op.
    }
}

/// A tag allocator that maintains a per-thread block.
public struct TagAllocator {
    @usableFromInline
    struct Header {
        @usableFromInline let tag : TaggedHeap.Tag
        @usableFromInline let threadCount : Int
        
        @inlinable
        init(tag: TaggedHeap.Tag, threadCount: Int) {
            self.tag = tag
            self.threadCount = threadCount
        }
    }
    
    @usableFromInline
    struct AllocationBlock {
        public var memory : UnsafeMutableRawPointer? = nil
        public var size : Int = 0
        public var offset = 0
        
        @inlinable
        init() {
            
        }
    }
    
    @usableFromInline let memory : UnsafeMutableRawPointer
    
    @usableFromInline var header : UnsafeMutablePointer<Header> {
        return self.memory.assumingMemoryBound(to: Header.self)
    }
    
    @usableFromInline var blocks : UnsafeMutablePointer<AllocationBlock> {
        return self.memory.advanced(by: MemoryLayout<Header>.stride).assumingMemoryBound(to: AllocationBlock.self)
    }
    
    @inlinable
    public init(tag: TaggedHeap.Tag, threadCount: Int) {
        let firstBlock = TaggedHeap.allocateBlocks(tag: tag, count: 1)
        self.memory = firstBlock
        
        let header = Header(tag: tag, threadCount: threadCount)
        self.header.initialize(to: header)
        
        firstBlock.advanced(by: MemoryLayout<Header>.stride).bindMemory(to: AllocationBlock.self, capacity: threadCount)
        self.blocks.initialize(repeating: AllocationBlock(), count: threadCount)
        self.blocks[0].memory = firstBlock
        self.blocks[0].offset = MemoryLayout<Header>.stride + MemoryLayout<AllocationBlock>.stride * threadCount
    }
    
    @inlinable
    public var isValid : Bool {
        return TaggedHeap.tagMatches(self.header.pointee.tag, pointer: self.memory)
    }
    
    @inlinable
    public mutating func reset() {
        let header = self.header.pointee
        self = TagAllocator(tag: header.tag, threadCount: header.threadCount)
    }
    
    @inlinable
    public func allocate(bytes: Int, alignment: Int, threadIndex: Int) -> UnsafeMutableRawPointer {
        if useSystemAllocator {
            return .allocate(byteCount: bytes, alignment: alignment)
        }
        let blockPtr = self.blocks.advanced(by: threadIndex)
        let alignedOffset = (blockPtr.pointee.offset + alignment - 1) & ~(alignment - 1)
        if let memory = blockPtr.pointee.memory, alignedOffset + bytes <= blockPtr.pointee.size {
            defer { blockPtr.pointee.offset = alignedOffset + bytes }
            return memory.advanced(by: alignedOffset)
        }
        
        let requiredBlocks = (bytes + TaggedHeap.blockSize - 1) / TaggedHeap.blockSize
        let memory = TaggedHeap.allocateBlocks(tag: self.header.pointee.tag, count: requiredBlocks)
        blockPtr.pointee.memory = memory
        blockPtr.pointee.size = requiredBlocks * TaggedHeap.blockSize
        blockPtr.pointee.offset = bytes
        
        return memory
    }
    
    @inlinable
    public func allocate<T>(capacity: Int, threadIndex: Int) -> UnsafeMutablePointer<T> {
        return self.allocate(bytes: capacity * MemoryLayout<T>.stride, alignment: MemoryLayout<T>.alignment, threadIndex: threadIndex).bindMemory(to: T.self, capacity: capacity)
    }
    
    @inlinable
    public func deallocate(_ pointer: UnsafeMutableRawPointer) {
        if useSystemAllocator {
            return pointer.deallocate()
        }
        // No-op.
    }
    
    @inlinable
    public func deallocate<T>(_ pointer: UnsafeMutablePointer<T>) {
        if useSystemAllocator {
            return pointer.deallocate()
        }
        // No-op.
    }
    
    /// Calls a statically-set function to determine the current thread.
    public struct DynamicThreadView {
        public static var threadIndexRetrievalFunc : (() -> Int) = { return 0 }
        
        @usableFromInline var allocator : TagAllocator
        
        @inlinable
        public init(allocator: TagAllocator) {
            self.allocator = allocator
        }
        
        @inlinable
        public func allocate(bytes: Int, alignment: Int) -> UnsafeMutableRawPointer {
            if useSystemAllocator {
                return .allocate(byteCount: bytes, alignment: alignment)
            }
            return self.allocator.allocate(bytes: bytes, alignment: alignment, threadIndex: DynamicThreadView.threadIndexRetrievalFunc())
        }
        
        @inlinable
        public func allocate<T>(capacity: Int) -> UnsafeMutablePointer<T> {
            if useSystemAllocator {
                return .allocate(capacity: capacity)
            }
            return self.allocator.allocate(capacity: capacity, threadIndex: DynamicThreadView.threadIndexRetrievalFunc())
        }

        @inlinable
        public func deallocate(_ pointer: UnsafeMutableRawPointer) {
            if useSystemAllocator {
                return pointer.deallocate()
            }
            // No-op.
        }
        
        @inlinable
        public func deallocate<T>(_ pointer: UnsafeMutablePointer<T>) {
            if useSystemAllocator {
                return pointer.deallocate()
            }
            // No-op.
        }
    }
    
    @inlinable
    public var dynamicThreadView : DynamicThreadView {
        return DynamicThreadView(allocator: self)
    }
    
    /// Locked to a single thread determined when the thread view was created.
    public struct ThreadView {
        @usableFromInline var allocator : TagAllocator
        public var threadIndex : Int
        
        @inlinable
        public init(allocator: TagAllocator, threadIndex: Int) {
            self.allocator = allocator
            self.threadIndex = threadIndex
        }
        
        @inlinable
        public func allocate(bytes: Int, alignment: Int) -> UnsafeMutableRawPointer {
            if useSystemAllocator {
                return .allocate(byteCount: bytes, alignment: alignment)
            }
            
            assert(DynamicThreadView.threadIndexRetrievalFunc() == threadIndex)
            return self.allocator.allocate(bytes: bytes, alignment: alignment, threadIndex: self.threadIndex)
        }
        
        @inlinable
        public func allocate<T>(capacity: Int) -> UnsafeMutablePointer<T> {
            if useSystemAllocator {
                return .allocate(capacity: capacity)
            }
            assert(DynamicThreadView.threadIndexRetrievalFunc() == threadIndex)
            return self.allocator.allocate(capacity: capacity, threadIndex: self.threadIndex)
        }

        @inlinable
        public func deallocate(_ pointer: UnsafeMutableRawPointer) {
            if useSystemAllocator {
                return pointer.deallocate()
            }
            // No-op.
        }
        
        @inlinable
        public func deallocate<T>(_ pointer: UnsafeMutablePointer<T>) {
            if useSystemAllocator {
                return pointer.deallocate()
            }
            // No-op.
        }
    }
}

/// Locked to a single thread determined when the thread view was created.
public struct ThreadLocalTagAllocator {
    @usableFromInline var allocator : TagAllocator
    
    @inlinable
    public init(tag: TaggedHeap.Tag) {
        self.allocator = TagAllocator(tag: tag, threadCount: 1)
    }
    
    @inlinable
    public func allocate(bytes: Int, alignment: Int) -> UnsafeMutableRawPointer {
        return self.allocator.allocate(bytes: bytes, alignment: alignment, threadIndex: 0)
    }
    
    @inlinable
    public func allocate<T>(capacity: Int) -> UnsafeMutablePointer<T> {
        return self.allocator.allocate(capacity: capacity, threadIndex: 0)
    }

    @inlinable
    public func deallocate(_ pointer: UnsafeMutableRawPointer) {
        self.allocator.deallocate(pointer)
    }
    
    @inlinable
    public func deallocate<T>(_ pointer: UnsafeMutablePointer<T>) {
        self.allocator.deallocate(pointer)
    }
}
