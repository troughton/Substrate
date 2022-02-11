//
//  TaggedHeap.swift
//  NaughtyDogAllocator
//
//  Created by Thomas Roughton on 8/05/19.
//  Copyright © 2019 Thomas Roughton. All rights reserved.
//

import Foundation
import Atomics

extension UnsafeMutableRawBufferPointer {
    fileprivate func contains(_ pointer: UnsafeRawPointer) -> Bool {
        guard let start = self.baseAddress else { return false }
        return pointer >= UnsafeRawPointer(start) && pointer < UnsafeRawPointer(start + self.count)
    }
}

public enum TaggedHeap {
    // Block based allocator
    // Each block is 2MiB
    // Each block is owned by a UInt64 tag (e.g. hashed allocator name + frame number).
    
    // Everything is stored in bitsets.
    // We need: a list of allocated blocks (bitset)
    // A per-tag list of blocks assigned to that tag. Could use a dictionary of [Tag : BitSet] and a pool of free [BitSet]s? Means data is malloc'ed instead, but does that really matter?
    // Also need a spin-lock.
    
    public enum Strategy {
        case suballocate(capacity: Int, blockSize: Int = 2 * 1024 * 1024)
        case allocatePerBlock(blockSize: Int = 64 * 1024)
    }
    
    static let maxTasksPerAllocator = 512
    public static let maxThreadPoolWidth = 128 // GCD pool width (64) rounded up to the next power of two.
    
    public typealias Tag = UInt64
    public static var blockSize = 64 * 1024
    
    static var strategy: Strategy = .allocatePerBlock()
    
    static var blockCount : Int = 0
    static var bitSetStorageCount : Int = 0
    @usableFromInline static var heapMemory : UnsafeMutableRawPointer? = nil
    static var spinLock = SpinLock()
    static var filledBlocks : AtomicBitSet! = nil
    
    static var blocksByTag : [Tag : BitSet]! = nil
    static var freeBitsets : [BitSet]! = nil
    
    static var allocationsByTag : [Tag : [UnsafeMutableRawBufferPointer]] = [:]
    static var freeBlocks : [Int : [UnsafeMutableRawPointer]] = [:]
    
    #if os(macOS) || targetEnvironment(macCatalyst)
    public static let defaultHeapCapacity = 512 * 1024 * 1024 // 2 * 1024 * 1024 * 1024
    #else
    public static let defaultHeapCapacity = 256 * 1024 * 1024
    #endif
    
    public static func initialise(capacity: Int) {
        self.initialise(strategy: .suballocate(capacity: capacity))
    }
    
    public static func initialise(strategy: Strategy = .suballocate(capacity: TaggedHeap.defaultHeapCapacity)) {
        self.strategy = strategy
        switch strategy {
        case .allocatePerBlock(let blockSize):
            self.blockSize = blockSize
            self.allocationsByTag = [:]
        case .suballocate(let capacity, let blockSize):
            self.blockSize = blockSize
            self.blockCount = (capacity + TaggedHeap.blockSize - 1) / TaggedHeap.blockSize
            self.bitSetStorageCount = (self.blockCount + BitSet.bitsPerElement) / BitSet.bitsPerElement
            
            self.heapMemory = UnsafeMutableRawPointer.allocate(byteCount: TaggedHeap.blockSize * blockCount, alignment: TaggedHeap.blockSize)
            self.filledBlocks = AtomicBitSet(storageCount: bitSetStorageCount)
            self.blocksByTag = [:]
            self.freeBitsets = []
        }
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
        if case .allocatePerBlock = self.strategy {
            return self.spinLock.withLock { () -> UnsafeMutableRawPointer in
                if let pointer = self.freeBlocks[count]?.popLast() {
                    if self.freeBlocks[count]!.isEmpty {
                        self.freeBlocks.removeValue(forKey: count)
                    }
                    self.allocationsByTag[tag, default: []].append(.init(start: pointer, count: TaggedHeap.blockSize * count))
                    return pointer
                }
                
                // Try to allocate blocks off the end of our largest allocation.
                let targetBlockCount = self.freeBlocks.keys.reduce(count, { currentBest, blockSize in
                    if blockSize > currentBest {
                        return blockSize
                    } else {
                        return currentBest
                    }
                })
                
                if targetBlockCount > count {
                    let blocks = self.freeBlocks[targetBlockCount]!.removeLast()
                    if self.freeBlocks[targetBlockCount]!.isEmpty {
                        self.freeBlocks.removeValue(forKey: targetBlockCount)
                    }
                    
                    let pointer = blocks + TaggedHeap.blockSize * count
                    self.freeBlocks[targetBlockCount - count, default: []].append(blocks)
                    self.allocationsByTag[tag, default: []].append(.init(start: pointer, count: TaggedHeap.blockSize * count))
                    return pointer
                }
                
                let pointer = UnsafeMutableRawBufferPointer.allocate(byteCount: TaggedHeap.blockSize * count, alignment: TaggedHeap.blockSize)
                self.allocationsByTag[tag, default: []].append(pointer)
                return pointer.baseAddress!
            }
        }
        
        var blockIndex = self.findContiguousBlock(count: count)
        if blockIndex == .max {
            print("TaggedHeap error: no free blocks available! Switching to per-block allocations; all previous allocations will be leaked.")
            self.spinLock.withLock {
                self.initialise(strategy: .allocatePerBlock())
            }
            return self.allocateBlocks(tag: tag, count: count)
        }
        
        let block = self.spinLock.withLock { () -> UnsafeMutableRawPointer in
            while !self.filledBlocks.testBitsAreClear(in: blockIndex..<(blockIndex + count)) {
                blockIndex = self.findContiguousBlock(count: count)
                
                if blockIndex == .max {
                    print("TaggedHeap error: no free blocks available! Switching to per-block allocations; all previous allocations will be leaked.")
                    self.initialise(strategy: .allocatePerBlock())
                    let pointer = UnsafeMutableRawBufferPointer.allocate(byteCount: TaggedHeap.blockSize * count, alignment: TaggedHeap.blockSize)
                    self.allocationsByTag[tag, default: []].append(pointer)
                    return pointer.baseAddress!
                }
            }
            
            let tagBitset = self.taggedBlockList(tag: tag)
            self.filledBlocks.unsafelyUnwrapped.setBits(in: blockIndex..<(blockIndex + count))
            tagBitset.setBits(in: blockIndex..<(blockIndex + count))
            
            return self.heapMemory.unsafelyUnwrapped + blockIndex * TaggedHeap.blockSize
        }
        return block
    }
    
    /// For debugging only; not efficient.
    public static func tag(for pointer: UnsafeRawPointer) -> Tag? {
        return self.spinLock.withLock {
            if case .allocatePerBlock = self.strategy {
                for (tag, allocationList) in self.allocationsByTag {
                    for allocation in allocationList {
                        if allocation.contains(pointer) {
                            return tag
                        }
                    }
                }
                return nil
            }
    
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
            if case .allocatePerBlock = self.strategy {
                return self.allocationsByTag[tag]?.contains(where: {
                    $0.contains(pointer)
                }) ?? false
            }
            
            let block = (pointer - UnsafeRawPointer(self.heapMemory!)) / self.blockSize
            assert(block >= 0 && block < self.blockCount)
            
            guard let blocks = self.blocksByTag[tag] else {
                return false
            }
            return blocks[block]
        }
    }
    
    public static func free(tag: Tag) {
        if case .allocatePerBlock = self.strategy {
            self.spinLock.withLock {
                guard let allocations = self.allocationsByTag.removeValue(forKey: tag) else { return }
                for allocation in allocations {
                    self.freeBlocks[allocation.count / TaggedHeap.blockSize, default: []].append(allocation.baseAddress!)
                }
            }
            return
        }
        
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
public struct LockingTagAllocator: Sendable {
    
    @usableFromInline
    struct Header {
        @usableFromInline var lock : UInt32.AtomicRepresentation
        @usableFromInline let tag : TaggedHeap.Tag
        @usableFromInline var memory : UnsafeMutableRawPointer
        @usableFromInline var offset : Int
        @usableFromInline var allocationSize : Int
        
        @inlinable
        init(tag: TaggedHeap.Tag, memory: UnsafeMutableRawPointer, offset: Int, allocationSize: Int) {
            self.lock = .init(SpinLockState.free.rawValue)
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
    
    private var lockPointer: UnsafeMutablePointer<UInt32.AtomicRepresentation> {
        return UnsafeMutableRawPointer(self.header).assumingMemoryBound(to: UInt32.AtomicRepresentation.self)
    }
    
    @usableFromInline
    func lock() {
        let lockPointer = self.lockPointer
        while UInt32.AtomicRepresentation.atomicLoad(at: lockPointer, ordering: .relaxed) == SpinLockState.taken.rawValue ||
                UInt32.AtomicRepresentation.atomicExchange(SpinLockState.taken.rawValue, at: lockPointer, ordering: .acquiring) == SpinLockState.taken.rawValue {
            yieldCPU()
        }
    }
    
    @usableFromInline
    func unlock() {
        _ = UInt32.AtomicRepresentation.atomicExchange(SpinLockState.free.rawValue, at: self.lockPointer, ordering: .releasing)
    }
    
    @inlinable
    public var isValid : Bool {
        return TaggedHeap.tagMatches(self.header.pointee.tag, pointer: self.header.pointee.memory)
    }
    
    public func allocate(bytes: Int, alignment: Int) -> UnsafeMutableRawPointer {
        self.lock()
        defer { self.unlock() }
        return self.header.pointee.allocate(bytes: bytes, alignment: alignment)
    }
    
    @inlinable
    public func allocate<T>(type: T.Type = T.self, capacity: Int) -> UnsafeMutablePointer<T> {
        return self.allocate(bytes: capacity * MemoryLayout<T>.stride, alignment: MemoryLayout<T>.alignment).bindMemory(to: T.self, capacity: capacity)
    }
    
    public func deallocate(_ pointer: UnsafeMutableRawPointer) {
        // No-op.
    }

    @inlinable
    public func deallocate<T>(_ pointer: UnsafeMutablePointer<T>) {
        // No-op.
    }
}

/// A tag allocator that maintains a per-thread block.
public struct TagAllocator: Sendable {
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
        public var memoryStart : UnsafeMutableRawPointer? = nil
        public var memoryEnd : UnsafeMutableRawPointer? = nil
        
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
    
    @usableFromInline var executorMap: ExecutorAtomicLinearProbingMap {
        let threadCount = self.header.pointee.threadCount
        let bucketsPointer = self.memory.advanced(by: MemoryLayout<Header>.stride + threadCount * MemoryLayout<AllocationBlock>.stride)
            .assumingMemoryBound(to: UnsafeRawPointer.AtomicOptionalRepresentation.self)
        return ExecutorAtomicLinearProbingMap(buckets:
                                                UnsafeMutableBufferPointer(start: bucketsPointer, count: threadCount)
                                              )
    }
    
    public var tag: TaggedHeap.Tag {
        return self.header.pointee.tag
    }
    
    @inlinable
    public init(tag: TaggedHeap.Tag, threadCount: Int = TaggedHeap.maxThreadPoolWidth) {
        let firstBlock = TaggedHeap.allocateBlocks(tag: tag, count: 1)
        self.memory = firstBlock
        
        let header = Header(tag: tag, threadCount: threadCount)
        firstBlock.bindMemory(to: Header.self, capacity: 1).initialize(to: header)
        
        let allocationBlockOffset = firstBlock.advanced(by: MemoryLayout<Header>.stride)
        allocationBlockOffset.bindMemory(to: AllocationBlock.self, capacity: threadCount).initialize(repeating: AllocationBlock(), count: threadCount)
        
        let executorMapOffset = allocationBlockOffset.advanced(by: MemoryLayout<AllocationBlock>.stride * threadCount)
        executorMapOffset.bindMemory(to: UnsafeRawPointer.AtomicOptionalRepresentation.self, capacity: threadCount).initialize(repeating: .init(nil), count: threadCount)
        
        let memoryStart = executorMapOffset.advanced(by: MemoryLayout<UnsafeRawPointer.AtomicOptionalRepresentation>.stride * threadCount)
        
        self.blocks[0].memoryStart = memoryStart
        self.blocks[0].memoryEnd = firstBlock + TaggedHeap.blockSize
        assert(self.blocks[0].memoryEnd! >= memoryStart, "ThreadCount \(threadCount) overflowed the TaggedHeap block size.")
    }
    
    @inlinable
    public var isValid : Bool {
        return TaggedHeap.tagMatches(self.tag, pointer: self.memory)
    }
    
    @inlinable
    public mutating func reset() {
        let header = self.header.pointee
        self = TagAllocator(tag: header.tag, threadCount: header.threadCount)
    }
    
    @inlinable
    public func allocate(bytes: Int, alignment: Int, threadIndex: Int) -> UnsafeMutableRawPointer {
        assert(self.isValid)
        assert((0..<self.header.pointee.threadCount).contains(threadIndex), "Thread index \(threadIndex) is not in the range \(0..<self.header.pointee.threadCount)")
        
        let blockPtr = self.blocks.advanced(by: threadIndex)
        if let memory = blockPtr.pointee.memoryStart?.alignedUpwards(withAlignment: alignment), memory + bytes <= blockPtr.pointee.memoryEnd! {
            blockPtr.pointee.memoryStart = memory + bytes
            return memory
        }
        
        let requiredBlocks = (bytes + TaggedHeap.blockSize - 1) / TaggedHeap.blockSize
        let memory = TaggedHeap.allocateBlocks(tag: self.header.pointee.tag, count: requiredBlocks)
        blockPtr.pointee.memoryStart = memory + bytes
        blockPtr.pointee.memoryEnd = memory + requiredBlocks * TaggedHeap.blockSize
        
        return memory
    }
    
    @inlinable
    public func allocate<T>(type: T.Type = T.self, capacity: Int, threadIndex: Int) -> UnsafeMutablePointer<T> {
        return self.allocate(bytes: capacity * MemoryLayout<T>.stride, alignment: MemoryLayout<T>.alignment, threadIndex: threadIndex).bindMemory(to: T.self, capacity: capacity)
    }
    
    @inlinable
    public func deallocate(_ pointer: UnsafeMutableRawPointer) {
        // No-op.
    }
    
    @inlinable
    public func deallocate<T>(_ pointer: UnsafeMutablePointer<T>) {
        // No-op.
    }
    
    /// Calls a statically-set function to determine the current thread.
    public struct DynamicThreadView: Sendable {
        @usableFromInline var allocator : TagAllocator
        
        @inlinable
        public init(allocator: TagAllocator) {
            self.allocator = allocator
        }
        
        @inlinable
        public func allocate(bytes: Int, alignment: Int) -> UnsafeMutableRawPointer {
            return self.allocator.allocate(bytes: bytes, alignment: alignment, threadIndex: self.allocator.executorMap.bucketIndexForCurrentThread)
        }
        
        @inlinable
        public func allocate<T>(type: T.Type = T.self, capacity: Int) -> UnsafeMutablePointer<T> {
            return self.allocator.allocate(capacity: capacity, threadIndex: self.allocator.executorMap.bucketIndexForCurrentThread)
        }

        @inlinable
        public func deallocate(_ pointer: UnsafeMutableRawPointer) {
            // No-op.
        }
        
        @inlinable
        public func deallocate<T>(_ pointer: UnsafeMutablePointer<T>) {
            // No-op.
        }
    }
    
    @inlinable
    public var dynamicThreadView : DynamicThreadView {
        return DynamicThreadView(allocator: self)
    }
    
    /// Locked to a single executor determined when the executor view was created.
    public struct StaticTaskView {
        @usableFromInline var allocator : TagAllocator
        public var taskIndex : Int
        
        @inlinable
        public init(allocator: TagAllocator, taskIndex: Int) {
            self.allocator = allocator
            self.taskIndex = taskIndex
        }
        
        @inlinable
        public func allocate(bytes: Int, alignment: Int) -> UnsafeMutableRawPointer {
            assert(self.taskIndex == self.allocator.executorMap.bucketIndexForCurrentTask)
            return self.allocator.allocate(bytes: bytes, alignment: alignment, threadIndex: self.taskIndex)
        }
        
        @inlinable
        public func allocate<T>(type: T.Type = T.self, capacity: Int) -> UnsafeMutablePointer<T> {
            assert(self.taskIndex == self.allocator.executorMap.bucketIndexForCurrentTask)
            return self.allocator.allocate(capacity: capacity, threadIndex: self.taskIndex)
        }

        @inlinable
        public func deallocate(_ pointer: UnsafeMutableRawPointer) {
            // No-op.
        }
        
        @inlinable
        public func deallocate<T>(_ pointer: UnsafeMutablePointer<T>) {
            // No-op.
        }
    }
    
    // NOTE: staticTaskView can only be used within the current task.
    @inlinable
    public var staticTaskView: StaticTaskView {
        return StaticTaskView(allocator: self, taskIndex: self.executorMap.bucketIndexForCurrentTask)
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

extension UnsafeMutableRawPointer {
    // https://stackoverflow.com/questions/4840410/how-to-align-a-pointer-in-c
    @inlinable
    func alignedUpwards(withAlignment align: Int) -> UnsafeMutableRawPointer {
        assert(align > 0 && (align & (align - 1)) == 0); /* Power of 2 */
        
        var addr = Int(bitPattern: self)
        addr = (addr &+ (align &- 1)) & -align   // Round up to align-byte boundary
        assert(addr >= UInt(bitPattern: self))
        return UnsafeMutableRawPointer(bitPattern: addr).unsafelyUnwrapped
    }
}

extension UnsignedInteger {
    @inlinable
    var isPowerOfTwo: Bool {
        return (self != 0) && (self & (self - 1)) == 0
    }
}

@usableFromInline
struct ExecutorAtomicLinearProbingMap {
    public let buckets: UnsafeMutableBufferPointer<UnsafeRawPointer.AtomicOptionalRepresentation>
    @usableFromInline let bucketMask: Int
    
    @inlinable
    public init(buckets: UnsafeMutableBufferPointer<UnsafeRawPointer.AtomicOptionalRepresentation>) {
        precondition(buckets.count.magnitude.isPowerOfTwo)
        self.buckets = buckets
        self.bucketMask = buckets.count &- 1
    }
    
    @inlinable
    public func bucketIndex(for address: UnsafeRawPointer) -> Int {
        let startBucket = (Int(bitPattern: address) / (MemoryLayout<Int>.stride)) & self.bucketMask
        
        var testIndex = startBucket
        repeat {
            let bucketPointer = buckets.baseAddress!.advanced(by: testIndex)
            let bucketVal = UnsafeRawPointer.AtomicOptionalRepresentation.atomicLoad(at: bucketPointer, ordering: .relaxed)
            if bucketVal == address {
                return testIndex
            } else if bucketVal == nil, UnsafeRawPointer.AtomicOptionalRepresentation.atomicCompareExchange(expected: nil, desired: address, at: bucketPointer, ordering: .relaxed).exchanged {
                return testIndex
            }
            testIndex = (testIndex &+ 1) & self.bucketMask
        } while testIndex != startBucket
        preconditionFailure("Map is full! Not enough capacity to insert \(address)")
    }
    
    @inlinable
    public func clearBucket(for address: UnsafeRawPointer) {
        let startBucket = (Int(bitPattern: address) / (MemoryLayout<Int>.stride)) & self.bucketMask
        
        var testIndex = startBucket
        repeat {
            let bucketPointer = buckets.baseAddress!.advanced(by: testIndex)
            let bucketVal = UnsafeRawPointer.AtomicOptionalRepresentation.atomicLoad(at: bucketPointer, ordering: .relaxed)
            if bucketVal == address {
                UnsafeRawPointer.AtomicOptionalRepresentation.atomicStore(nil, at: bucketPointer, ordering: .relaxed)
            }
            testIndex = (testIndex &+ 1) & self.bucketMask
        } while testIndex != startBucket
        preconditionFailure("Address \(address) is not in map!")
    }
    
    @inlinable
    public var bucketIndexForCurrentTask: Int {
        guard let task = _getCurrentAsyncTask() else {
            preconditionFailure("Must be executed from a task thread.")
        }
        
        return self.bucketIndex(for: task)
    }
    
    @inlinable
    public var bucketIndexForCurrentThread: Int {
        let threadID = pthread_self()
        return self.bucketIndex(for: UnsafeRawPointer(threadID))
    }
}

@_silgen_name("swift_task_getCurrent")
@usableFromInline func _getCurrentAsyncTask() -> UnsafeRawPointer?
