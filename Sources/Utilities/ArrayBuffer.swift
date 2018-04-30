//
//  ReferenceArray.swift
//  InterdimensionalLlama
//
//  Created by Thomas Roughton on 5/04/17.
//
//

import Swift

public extension Array {
    @discardableResult
    mutating func remove(at index: Index, preservingOrder: Bool) -> Element {
        if preservingOrder {
            return self.remove(at: index)
        } else {
            let last = self.removeLast()
            let value = index == self.count ? last : self[index]
            if index != self.count {
                self[index] = last
            }
            return value
        }
    }
}

public final class FixedSizeBuffer<Element> : MutableCollection, RandomAccessCollection {
    
    public typealias SubSequence = Slice<FixedSizeBuffer<Element>>
    public typealias Index = Int
    
    public let allocator : AllocatorType
    public private(set) var capacity : Int
    public private(set) var buffer : UnsafeMutablePointer<Element>
    
    // @inlinable
    public init(allocator: AllocatorType = .system, capacity: Int, defaultValue: Element) {
        self.allocator = allocator
        
        self.capacity = capacity
        self.buffer = Allocator.allocate(capacity: capacity, allocator: allocator)
        self.buffer.initialize(repeating: defaultValue, count: self.capacity)
    }
    
    public init(allocator: AllocatorType = .system, uninitializedCapacity: Int) {
        assert(uninitializedCapacity > 0)
        
        self.allocator = allocator
        
        self.capacity = uninitializedCapacity
        self.buffer = Allocator.allocate(capacity: capacity, allocator: allocator)
    }
    
    @inlinable
    public subscript(index: Int) -> Element {
        get {
            return self.buffer.advanced(by: index).pointee
        } set {
            self.buffer.advanced(by: index).pointee = newValue
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
        self.buffer.deinitialize(count: self.capacity)
        Allocator.deallocate(self.buffer, allocator: self.allocator)
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
    
    @_versioned
    var capacity : Int
    public private(set) var buffer : UnsafeMutablePointer<Element>
    
    public private(set) var count : Int = 0
    
    // @inlinable
    public init(allocator: AllocatorType = .system, initialCapacity: Int = 16) {
        self.allocator = allocator
        self.capacity = initialCapacity
        self.buffer =  Allocator.allocate(capacity: capacity, allocator: allocator)
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
            return self.buffer.advanced(by: index).pointee
        } set {
            self.buffer.advanced(by: index).pointee = newValue
        }
    }
    
    @inlinable
    public func append(_ element: Element) {
        self.resize(capacity: self.count + 1)
        self.buffer.advanced(by: self.count).initialize(to: element)
        self.count += 1
    }
    
    @inlinable
    public func append(from: UnsafePointer<Element>, count: Int) {
        self.resize(capacity: self.count + count)
        self.buffer.advanced(by: self.count).initialize(from: from, count: count)
        self.count += count
    }
    
    @inlinable
    public func removeAll() {
        self.buffer.deinitialize(count: self.count)
        self.count = 0
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
    public func resize(capacity: Int) {
        if self.capacity < capacity {
            let newCapacity = Swift.max(self.capacity * 2, capacity)

            let newBaseAddress = Allocator.allocate(capacity: newCapacity, allocator: self.allocator) as UnsafeMutablePointer<Element>
            newBaseAddress.moveInitialize(from: self.buffer, count: self.count)
            
            Allocator.deallocate(buffer, allocator: self.allocator)
            
            self.buffer = newBaseAddress
            self.capacity = newCapacity
        }
    }
    
    public func sort(by areInIncreasingOrder: (Element, Element) -> Bool) {
        var bufferPointer = UnsafeMutableBufferPointer(start: self.buffer, count: self.count)
        bufferPointer.sort(by: areInIncreasingOrder)
    }
    
    public func index(after i: Int) -> Int {
        return i + 1
    }
    
    deinit {
        self.buffer.deinitialize(count: self.count)
        Allocator.deallocate(self.buffer, allocator: self.allocator)
    }
}

public extension ExpandingBuffer where Element : Comparable {
    public func sort() {
        var bufferPointer = UnsafeMutableBufferPointer(start: self.buffer, count: self.count)
        bufferPointer.sort()
    }
}

public extension ExpandingBuffer where Element == UInt8 {
    @inlinable
    public func append<T>(_ element: T) {
        self.resize(capacity: self.count + MemoryLayout.size(ofValue: element))
        UnsafeMutableRawPointer(self.buffer.advanced(by: self.count)).assumingMemoryBound(to: T.self).initialize(to: element)
        self.count += MemoryLayout.size(ofValue: element)
    }
}
