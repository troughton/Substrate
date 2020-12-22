//
//  ChunkArray.swift
//  
//
//  Created by Thomas Roughton on 23/08/20.
//

public struct ChunkArray<Element>: Collection {
    @inlinable
    public static var elementsPerChunk: Int { 8 }
    
    @usableFromInline typealias Storage = (Element, Element, Element, Element, Element, Element, Element, Element)
    
    @usableFromInline
    struct Chunk {
        @usableFromInline var elements: Storage
        @usableFromInline var next: UnsafeMutablePointer<Chunk>?
    }
    
    public var count: Int
    @usableFromInline var next: UnsafeMutablePointer<Chunk>?
    @usableFromInline var tail: UnsafeMutablePointer<Chunk>?
    
    @inlinable
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
    public subscript(_ index: Int) -> Element {
        get {
            return self[pointerTo: index].pointee
        }
        set {
            self[pointerTo: index].pointee = newValue
        }
    }
    
    @inlinable
    public subscript(pointerTo index: Int) -> UnsafeMutablePointer<Element> {
        precondition(index >= 0 && index < self.count)
        let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: ChunkArray.elementsPerChunk)
        var currentChunk = self.next!
        for _ in 0..<chunkIndex {
            currentChunk = currentChunk.pointee.next!
        }
        return UnsafeMutableRawPointer(currentChunk).assumingMemoryBound(to: Element.self).advanced(by: indexInChunk)
    }
    
    @inlinable
    public var pointerToLast: UnsafeMutablePointer<Element> {
        precondition(self.count > 0)
        let index = self.count - 1
        let indexInChunk = index % ChunkArray.elementsPerChunk
        return UnsafeMutableRawPointer(self.tail!).assumingMemoryBound(to: Element.self).advanced(by: indexInChunk)
    }
    
    @inlinable
    public var last: Element {
        get {
            return self.pointerToLast.pointee
        }
        set {
            self.pointerToLast.pointee = newValue
        }
    }
    
    @inlinable
    public mutating func append(_ element: Element, allocator: AllocatorType) {
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
            }
            self.tail = newChunk
        }
        UnsafeMutableRawPointer(self.tail.unsafelyUnwrapped).assumingMemoryBound(to: Element.self).advanced(by: indexInChunk).initialize(to: element)
        self.count += 1
    }
    
    @inlinable
    @discardableResult
    public mutating func removeBySwappingWithBack(index: Int, allocator: AllocatorType) -> Element {
        precondition(index < self.count)
        if index == self.count - 1 {
            return self.removeLast(allocator: allocator)
        }
        
        let elementPointer = self[pointerTo: index]
        let element = elementPointer.move()
        elementPointer.moveAssign(from: self.pointerToLast, count: 1)
        
        let (_, indexInChunk) = self.count.quotientAndRemainder(dividingBy: ChunkArray.elementsPerChunk)
        if indexInChunk == 0 {
            self.removeTailChunk(allocator: allocator)
        }
        
        self.count -= 1
        return element
    }
    
    @usableFromInline
    mutating func removeTailChunk(allocator: AllocatorType) {
        var currentChunk = self.next
        var previousChunk = currentChunk
        while currentChunk != self.tail {
            previousChunk = currentChunk
            currentChunk = currentChunk?.pointee.next!
        }
        previousChunk?.pointee.next = nil
        self.tail = previousChunk
        if let currentChunk = currentChunk {
            Allocator.deallocate(currentChunk, allocator: allocator)
        }
    }
    
    @inlinable
    @discardableResult
    public mutating func removeLast(allocator: AllocatorType) -> Element {
        precondition(self.count > 0)
        
        let value = self.pointerToLast.move()
        
        let (_, indexInChunk) = self.count.quotientAndRemainder(dividingBy: ChunkArray.elementsPerChunk)
        if indexInChunk == 0 {
            self.removeTailChunk(allocator: allocator)
        }
        
        self.count -= 1
        return value
    }
    
    public mutating func removeAll(allocator: AllocatorType) {
        var nextChunk = self.next
        while let chunk = nextChunk {
            nextChunk = chunk.pointee.next
            Allocator.deallocate(chunk, allocator: allocator)
        }
        self = ChunkArray()
    }
    
    public struct Iterator : IteratorProtocol {
        public typealias Element = ChunkArray.Element
        
        @usableFromInline
        let elementCount: Int
        @usableFromInline
        var chunk: UnsafeMutablePointer<Chunk>?
        @usableFromInline
        var index = 0
        
        @inlinable
        init(currentChunk: UnsafeMutablePointer<Chunk>?, elementCount: Int) {
            self.chunk = currentChunk
            self.elementCount = elementCount
        }
        
        @inlinable
        public mutating func next() -> Element? {
            if self.index < self.elementCount {
                let indexInChunk = self.index % ChunkArray.elementsPerChunk
                let currentChunk = self.chunk.unsafelyUnwrapped
                let element = UnsafeMutableRawPointer(currentChunk).assumingMemoryBound(to: Element.self)[indexInChunk]
                self.index += 1
                
                if indexInChunk + 1 == ChunkArray.elementsPerChunk {
                    self.chunk = currentChunk.pointee.next
                }
                return element
            }
            return nil
        }
    }
    
    @inlinable
    public func makeIterator() -> Iterator {
        return Iterator(currentChunk: self.next, elementCount: self.count)
    }
    
}

extension ChunkArray {
    /// A view enabling random access into a ChunkArray. Does not allow appending or removing.
    public struct RandomAccessView: RandomAccessCollection {
        public let array: ChunkArray
        @usableFromInline let chunks: UnsafePointer<UnsafeMutablePointer<Chunk>>?
        
        public init(array: ChunkArray, allocator: AllocatorType) {
            precondition(!allocator.requiresDeallocation)
            
            self.array = array
            
            if array.count > 2 * ChunkArray.elementsPerChunk {
                let chunkCount = (array.count + ChunkArray.elementsPerChunk - 1) / ChunkArray.elementsPerChunk
                let chunks = Allocator.allocate(type: UnsafeMutablePointer<Chunk>.self, capacity: chunkCount, allocator: allocator)
                
                var i = 0
                var currentChunk = array.next
                while let chunk = currentChunk {
                    chunks[i] = chunk
                    currentChunk = currentChunk?.pointee.next
                    i += 1
                }
                self.chunks = UnsafePointer(chunks)
            } else {
                self.chunks = nil
            }
        }
        
        @inlinable
        public var startIndex: Int {
            return 0
        }
        
        @inlinable
        public var endIndex: Int {
            return array.count
        }
        
        @inlinable
        func chunk(at chunkIndex: Int) -> UnsafeMutablePointer<Chunk> {
            return self.chunks?[chunkIndex] ?? (chunkIndex == 0 ? array.next! : array.tail!)
        }
        
        @inlinable
        public subscript(pointerTo index: Int) -> UnsafeMutablePointer<ChunkArray.Element> {
            precondition(index >= 0 && index < array.count)
            
            let (chunkIndex, indexInChunk) = index.quotientAndRemainder(dividingBy: ChunkArray.elementsPerChunk)
            return UnsafeMutableRawPointer(self.chunk(at: chunkIndex)).assumingMemoryBound(to: Element.self).advanced(by: indexInChunk)
        }
        
        @inlinable
        public subscript(index: Int) -> ChunkArray.Element {
            get {
                return self[pointerTo: index].pointee
            }
            set {
                self[pointerTo: index].pointee = newValue
            }
        }
    }
    
    @inlinable
    public func makeRandomAccessView(allocator: AllocatorType) -> RandomAccessView {
        return RandomAccessView(array: self, allocator: allocator)
    }
}
