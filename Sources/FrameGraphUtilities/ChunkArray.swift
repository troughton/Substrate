//
//  ChunkArray.swift
//  
//
//  Created by Thomas Roughton on 23/08/20.
//

public struct ChunkArray<T>: Collection {
    @inlinable
    public static var elementsPerChunk: Int { 8 }
    
    @usableFromInline typealias Storage = (T, T, T, T, T, T, T, T)
    
    @usableFromInline
    struct Chunk {
        @usableFromInline var elements: Storage
        @usableFromInline var next: UnsafeMutablePointer<Chunk>?
    }
    
    public var count: Int
    @usableFromInline var next: UnsafeMutablePointer<Chunk>?
    @usableFromInline var tail: UnsafeMutablePointer<Chunk>?
    
    public init() {
        self.count = 0
    }
    
    
    @inlinable
    public var startIndex: Int { 0 }
    
    @inlinable
    public var endIndex: Int { self.count }
    
    @inlinable
    public func index(after i: Int) -> Int {
        precondition(i < self.count)
        return i + 1
    }
    
    @inlinable
    public subscript(_ index: Int) -> T {
        get {
            precondition(index >= 0 && index < self.count)
            let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: ChunkArray.elementsPerChunk)
            var currentChunk = self.next!
            for _ in 0..<chunkIndex {
                currentChunk = currentChunk.pointee.next!
            }
            return UnsafeMutableRawPointer(currentChunk).assumingMemoryBound(to: T.self)[indexInChunk]
        }
        set {
            precondition(index >= 0 && index < self.count)
            let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: ChunkArray.elementsPerChunk)
            var currentChunk = self.next!
            for _ in 0..<chunkIndex {
                currentChunk = currentChunk.pointee.next!
            }
            return UnsafeMutableRawPointer(currentChunk).assumingMemoryBound(to: T.self)[indexInChunk] = newValue
        }
    }
    
    @inlinable
    public var last: T {
        get {
            precondition(self.count > 0 )
            let index = self.count - 1
            let indexInChunk = index % ChunkArray.elementsPerChunk
            return UnsafeMutableRawPointer(self.tail!).assumingMemoryBound(to: T.self)[indexInChunk]
        }
        set {
            precondition(self.count > 0 )
            let index = self.count - 1
            let indexInChunk = index % ChunkArray.elementsPerChunk
            UnsafeMutableRawPointer(self.tail!).assumingMemoryBound(to: T.self)[indexInChunk] = newValue
        }
    }
    
    @inlinable
    public mutating func append(_ element: T, allocator: AllocatorType) {
        if case .system = allocator {
        } else {
            precondition(_isPOD(T.self))
        }
        
        let insertionIndex = self.count
        let indexInChunk = insertionIndex % ChunkArray.elementsPerChunk
        if indexInChunk == 0 {
            let newChunkBytes = Allocator.allocate(byteCount: MemoryLayout<Chunk>.size, alignment: MemoryLayout<Chunk>.alignment, allocator: allocator)
            newChunkBytes.initializeMemory(as: UInt8.self, repeating: 0, count: MemoryLayout<Chunk>.size)
            let newChunk = newChunkBytes.bindMemory(to: Chunk.self, capacity: 1)
            
            if let currentTail = self.tail {
                currentTail.pointee.next = newChunk
            } else {
                self.next = newChunk
                self.tail = newChunk
            }
        }
        UnsafeMutableRawPointer(self.tail.unsafelyUnwrapped).assumingMemoryBound(to: T.self).advanced(by: indexInChunk).initialize(to: element)
        self.count += 1
    }
    
    @inlinable
    public mutating func removeLast(allocator: AllocatorType) -> T {
        precondition(self.count > 0)
        
        let (chunkIndex, indexInChunk) = self.count.quotientAndRemainder(dividingBy: ChunkArray.elementsPerChunk)
        var currentChunk = self.next!
        var previousChunk = currentChunk
        for _ in 0..<chunkIndex {
            previousChunk = currentChunk
            currentChunk = currentChunk.pointee.next!
        }
        
        let value = UnsafeMutableRawPointer(currentChunk).assumingMemoryBound(to: T.self).advanced(by: indexInChunk).move()
        
        if indexInChunk == 0 {
            previousChunk.pointee.next = nil
            Allocator.deallocate(currentChunk, allocator: allocator)
        }
        
        self.count -= 1
        return value
    }
    
    
    public struct Iterator : IteratorProtocol {
        public typealias Element = T
        
        @usableFromInline
        var chunk: UnsafeMutablePointer<Chunk>?
        @usableFromInline
        var indexInChunk = 0
        
        @inlinable
        init(currentChunk: UnsafeMutablePointer<Chunk>?) {
            self.chunk = currentChunk
        }
        
        @inlinable
        public mutating func next() -> T? {
            if let currentChunk = self.chunk {
                let element = UnsafeMutableRawPointer(currentChunk).assumingMemoryBound(to: T.self)[self.indexInChunk]
                self.indexInChunk += 1
                if self.indexInChunk >= ChunkArray.elementsPerChunk {
                    self.indexInChunk = 0
                    self.chunk = currentChunk.pointee.next
                }
                return element
            }
            return nil
        }
    }
    
    @inlinable
    public func makeIterator() -> Iterator {
        return Iterator(currentChunk: self.next)
    }
    
}
