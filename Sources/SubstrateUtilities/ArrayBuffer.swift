//
//  ReferenceArray.swift
//  InterdimensionalLlama
//
//  Created by Thomas Roughton on 5/04/17.
//
//

import Swift

extension Array {
    @discardableResult
    @inlinable
    public mutating func remove(at index: Index, preservingOrder: Bool) -> Element {
        if preservingOrder {
            return self.remove(at: index)
        } else {
            self.swapAt(index, self.count - 1)
            return self.removeLast()
        }
    }
}

public final class FixedSizeBuffer<Element> : MutableCollection, RandomAccessCollection {
    
    public typealias SubSequence = Slice<FixedSizeBuffer<Element>>
    public typealias Index = Int
    
    public let allocator : AllocatorType
    public private(set) var capacity : Int
    public private(set) var buffer : UnsafeMutablePointer<Element>!
    
    // @inlinable
    public init(allocator: AllocatorType = .system, capacity: Int, defaultValue: Element) {
        assert(capacity > 0)
        
        self.allocator = allocator
        
        self.capacity = capacity
        self.buffer = Allocator.allocate(capacity: capacity, allocator: allocator)
        self.buffer!.initialize(repeating: defaultValue, count: self.capacity)
    }
    
    public init(allocator: AllocatorType = .system, uninitializedCapacity: Int) {
        self.allocator = allocator
        self.capacity = uninitializedCapacity

        if uninitializedCapacity == 0 {
            self.buffer = nil
        } else {
            self.buffer = Allocator.allocate(capacity: capacity, allocator: allocator)
        }
    }
    
    public convenience init(allocator: AllocatorType = .system, from array: [Element]) {
        self.init(allocator: allocator, uninitializedCapacity: array.count)
        
        for (i, element) in array.enumerated() {
            self.buffer![i] = element
        }
    }
    
    public convenience init(allocator: AllocatorType = .system, from: UnsafePointer<Element>, count: Int) {
        self.init(allocator: allocator, uninitializedCapacity: count)
        self.buffer.initialize(from: from, count: count)
    }
    
    @inlinable
    public subscript(index: Int) -> Element {
        get {
            assert(index >= self.startIndex && index < endIndex, "Index out of bounds")
            return self.buffer!.advanced(by: index).pointee
        } set {
            assert(index >= self.startIndex && index < endIndex, "Index out of bounds")
            self.buffer!.advanced(by: index).pointee = newValue
        }
    }
    
    @inlinable
    public var startIndex: Int {
        return 0
    }
    
    @inlinable
    public var endIndex: Int {
        return self.capacity
    }
    
    public func sort(by areInIncreasingOrder: (Element, Element) -> Bool) {
        var bufferPointer = UnsafeMutableBufferPointer(start: buffer, count: self.capacity)
        bufferPointer.sort(by: areInIncreasingOrder)
    }
    
    @inlinable
    public func index(after i: Int) -> Int {
        return i + 1
    }
    
    deinit {
        if let buffer = self.buffer {
            buffer.deinitialize(count: self.capacity)
            Allocator.deallocate(buffer, allocator: self.allocator)
        }
    }
}

extension FixedSizeBuffer : ExpressibleByArrayLiteral {
    
    public convenience init(arrayLiteral elements: Element...) {
        
        self.init(uninitializedCapacity: elements.count)
        _ = UnsafeMutableBufferPointer(start: self.buffer, count: elements.count).initialize(from: elements)
    }
}

public final class ExpandingBuffer<Element> : MutableCollection, RandomAccessCollection {
    
    public typealias SubSequence = Slice<ExpandingBuffer<Element>>
    public typealias Index = Int
    
    public let allocator : AllocatorType
    
    public var capacity : Int
    public var buffer : UnsafeMutablePointer<Element>!
    
    public var count : Int = 0
    
    @inlinable
    public init(allocator: AllocatorType = .system, initialCapacity: Int = 16) {
        self.allocator = allocator
        self.capacity = initialCapacity
        if initialCapacity > 0 {
            self.buffer = Allocator.allocate(capacity: capacity, allocator: allocator)
        } else {
            self.buffer = nil
        }
        
        if case .custom(let arena) = self.allocator {
            assert(arena.takeUnretainedValue().currentBlockPos >= self.capacity * MemoryLayout<Element>.stride)
        }
    }
    
    fileprivate init(allocator: AllocatorType = .system, uninitializedCapacity: Int) {
        assert(uninitializedCapacity > 0)
        
        self.allocator = allocator
        
        self.capacity = uninitializedCapacity
        self.buffer = Allocator.allocate(capacity: capacity, allocator: allocator)
    }
    
    @inlinable
    public subscript(index: Int) -> Element {
        get {
            assert(index < self.capacity)
            return self.buffer.unsafelyUnwrapped.advanced(by: index).pointee
        } set {
            assert(index < self.capacity)
            self.buffer.unsafelyUnwrapped.advanced(by: index).pointee = newValue
        }
    }
    
    @inlinable
    public func append(_ element: Element) {
        self.reserveCapacity(self.count + 1)
        self.buffer.unsafelyUnwrapped.advanced(by: self.count).initialize(to: element)
        self.count += 1
    }
    
    @inlinable
    public func append<S : Sequence>(contentsOf sequence: S) where S.Element == Element {
        self.reserveCapacity(self.count + sequence.underestimatedCount)
        for element in sequence {
            self.append(element)
        }
    }
    
    @inlinable
    public func append(from: UnsafePointer<Element>, count: Int) {
        self.reserveCapacity( self.count + count)
        self.buffer.unsafelyUnwrapped.advanced(by: self.count).initialize(from: from, count: count)
        self.count += count
    }
    
    @inlinable
    public func append(repeating element: Element, count: Int) {
        precondition(count >= 0)
        guard count > 0 else { return }
        
        self.reserveCapacity(self.count + count)
        self.buffer.unsafelyUnwrapped.advanced(by: self.count).initialize(repeating: element, count: count)
        self.count += count
    }
    
    @inlinable
    public func removeAll() {
        self.buffer?.deinitialize(count: self.count)
        self.count = 0
    }
    
    @inlinable
    @discardableResult
    public func removeLast() -> Element {
        let last = self.buffer.unsafelyUnwrapped.advanced(by: self.count - 1).move()
        self.count -= 1
        return last
    }
    
    @inlinable
    @discardableResult
    public func popLast() -> Element? {
        return self.isEmpty ? nil : self.removeLast()
    }
    
    @inlinable
    public func removeRange(_ range: Range<Int>) {
        precondition(range.clamped(to: self.indices) == range)
        self.buffer.unsafelyUnwrapped.advanced(by: range.lowerBound).deinitialize(count: range.count)
        if range.upperBound < self.count {
            self.buffer.unsafelyUnwrapped.advanced(by: range.lowerBound).moveInitialize(from: self.buffer.unsafelyUnwrapped.advanced(by: range.upperBound), count: self.count - range.upperBound)
        }
        self.count -= range.count
    }
    
    @inlinable
    @discardableResult
    public func remove(at index: Int) -> Element {
        precondition(self.indices.contains(index))
        let element = self.buffer.unsafelyUnwrapped.advanced(by: index).move()
        if index < self.count {
            self.buffer.unsafelyUnwrapped.advanced(by: index).moveInitialize(from: self.buffer.unsafelyUnwrapped.advanced(by: index + 1), count: self.count - index + 1)
        }
        self.count -= 1
        return element
    }


    @inlinable
    public func removePrefix(count: Int) {
        precondition(!self.isEmpty)
        let count = Swift.min(count, self.count)
        let remainder = self.count - count
        self.buffer.unsafelyUnwrapped.deinitialize(count: count)
        self.buffer.unsafelyUnwrapped.moveInitialize(from: self.buffer.unsafelyUnwrapped.advanced(by: count), count: remainder)
        self.count = remainder
    }
    
    @inlinable
    public var startIndex: Int {
        return 0
    }
    
    @inlinable
    public var endIndex: Int {
        return self.count
    }
    
    @inlinable
    public func reserveCapacity(_ capacity: Int) {
        if self.capacity < capacity {
            let newCapacity = Swift.max((self.capacity * 3) / 2, capacity)

            let newBaseAddress = Allocator.allocate(capacity: newCapacity, allocator: self.allocator) as UnsafeMutablePointer<Element>
            
            if let buffer = self.buffer {
                newBaseAddress.moveInitialize(from: buffer, count: self.count)
                Allocator.deallocate(buffer, allocator: self.allocator)
            }
            
            self.buffer = newBaseAddress
            self.capacity = newCapacity
        }
    }
    
    public func sort(by areInIncreasingOrder: (Element, Element) -> Bool) {
        var bufferPointer = UnsafeMutableBufferPointer(start: self.buffer, count: self.count)
        bufferPointer.sort(by: areInIncreasingOrder)
    }
    
    @inlinable
    public func index(after i: Int) -> Int {
        return i + 1
    }
    
    deinit {
        if let buffer = self.buffer {
            // Leave POD types initialised since there's no harm in doing so.
            if !_isPOD(Element.self) {
               buffer.deinitialize(count: self.count)
            }
            
            Allocator.deallocate(buffer, allocator: self.allocator)
        }
    }
}

extension ExpandingBuffer where Element : Comparable {
    public func sort() {
        var bufferPointer = UnsafeMutableBufferPointer(start: self.buffer, count: self.count)
        bufferPointer.sort()
    }
}

extension ExpandingBuffer where Element == UInt8 {
    @inlinable
    public func append<S : Sequence>(_ sequence: S) {
        for element in sequence {
            self.append(element)
        }
    }
    
    @inlinable
    public func append<T>(_ element: T) {
        self.reserveCapacity(self.count + MemoryLayout.size(ofValue: element))
        UnsafeMutableRawPointer(self.buffer.unsafelyUnwrapped.advanced(by: self.count)).assumingMemoryBound(to: T.self).initialize(to: element)
        self.count += MemoryLayout.size(ofValue: element)
    }
    
    @inlinable
    public func append<T>(repeating element: T, count: Int) {
        assert(self.count % MemoryLayout<T>.alignment == 0)
        
        self.reserveCapacity(self.count + count * MemoryLayout<T>.stride)
        UnsafeMutableRawPointer(self.buffer.unsafelyUnwrapped.advanced(by: self.count)).assumingMemoryBound(to: T.self).initialize(repeating: element, count: count)
        self.count += count * MemoryLayout<T>.stride
    }
    
    @inlinable
    public func append<T>(from: UnsafePointer<T>, count: Int) {
        assert(self.count % MemoryLayout<T>.alignment == 0)
        self.reserveCapacity(self.count + count * MemoryLayout<T>.stride)
        
        UnsafeMutableRawPointer(self.buffer.unsafelyUnwrapped.advanced(by: self.count)).assumingMemoryBound(to: T.self).initialize(from: from, count: count)
        self.count += count * MemoryLayout<T>.stride
    }
    
    @inlinable
    public subscript<T>(index: Int, as type: T.Type) -> T {
        get {
            return UnsafeRawPointer(self.buffer.unsafelyUnwrapped).load(fromByteOffset: index * MemoryLayout<T>.stride, as: T.self)
        }
        set {
            UnsafeMutableRawPointer(self.buffer.unsafelyUnwrapped).storeBytes(of: newValue, toByteOffset: index * MemoryLayout<T>.stride, as: T.self)
        }
    }
    
    /// - returns: The index at which the bytes were appended
    @inlinable
    public func withStorageForAppendingBytes(count: Int, alignment: Int, _ closure: (UnsafeMutablePointer<Element>) throws -> Void) rethrows -> Int {
        let alignedInsertionPosition = self.count.roundedUpToMultiple(of: alignment)
        self.reserveCapacity(alignedInsertionPosition + count)
        try closure(self.buffer.unsafelyUnwrapped.advanced(by: alignedInsertionPosition))
        self.count = alignedInsertionPosition + count
        
        return alignedInsertionPosition
    }
}

extension ExpandingBuffer : Codable where Element : Codable {
    
    public enum CodingKeys : CodingKey {
        case count
        case elements
    }
    
    @inlinable
    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let count = try container.decode(Int.self, forKey: .count)
        
        self.init(initialCapacity: count)
        
        var nestedContainer = try container.nestedUnkeyedContainer(forKey: .elements)
        
        for i in 0..<count {
            let value = try nestedContainer.decode(Element.self)
            self.buffer.unsafelyUnwrapped.advanced(by: i).initialize(to: value)
        }
        
        self.count = count
    }
    
    @inlinable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.count, forKey: .count)
        
        var nestedContainer = container.nestedUnkeyedContainer(forKey: .elements)
        for i in self.startIndex..<self.endIndex {
            try nestedContainer.encode(self[i])
        }
    }
}
