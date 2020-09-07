//
//  TextureSubresourceMask.swift
//  
//
//  Created by Thomas Roughton on 23/08/20.
//

import Foundation
import FrameGraphUtilities

extension TextureDescriptor {
    @inlinable
    var subresourceCount: Int {
        return self.slicesPerLevel * self.mipmapLevelCount
    }
}

/// Represents a range of subresources within a texture.
/// Warning: depending on the texture slice count, this may behave as either a value or a reference type; as such, it should be treated as a move-only type.
public struct TextureSubresourceMask {
    public typealias Element = UInt64
    @usableFromInline var value: Element = .max // .max means the entire resource is in use, and 0 means the entire resource is inactive
    
    public init() {
        
    }
    
    public init(source: TextureSubresourceMask, descriptor: TextureDescriptor, allocator: AllocatorType) {
        if source.value == .max {
            self.value = .max
            return
        }
        self.withUnsafeMutablePointerToStorage(descriptor: descriptor, allocator: allocator) { elements in
            source.withUnsafePointerToStorage(descriptor: descriptor) { sourceElements in
                _ = elements.initialize(from: sourceElements)
            }
        }
    }
    
    @inlinable
    static func uintCount(bitCount: Int) -> Int {
        return (bitCount + Element.bitWidth - 1) / Element.bitWidth
    }
    
    @inlinable
    mutating func maskLastElement(bitCount: Int) {
        if self.value == .max || self.value == 0 { return }
        
        let lastElementBits = bitCount % Element.bitWidth
        if lastElementBits != 0 {
            let uintCount = Self.uintCount(bitCount: bitCount)
            if uintCount <= 1 {
                self.value &= (1 << lastElementBits) - 1
            } else {
                let storage = UnsafeMutablePointer<Element>(bitPattern: UInt(exactly: self.value)!)!
                
                let lastElementBits = bitCount % Element.bitWidth
                if lastElementBits != 0 {
                    storage[uintCount - 1] &= (1 << lastElementBits) - 1
                }
            }
        }
    }
    
    @usableFromInline
    mutating func reserveStorage(bitCount: Int, allocator: AllocatorType) {
        precondition(bitCount > Element.bitWidth)
        precondition(!allocator.requiresDeallocation, "Allocators which require deallocation calls are unsupported for TextureSubresourceMask.")
        if self.value == .max { // We haven't allocated the storage yet, so allocate it now.
            let uintCount = Self.uintCount(bitCount: bitCount)
            let storage = Allocator.allocate(type: Element.self, capacity: uintCount, allocator: allocator)
            storage.initialize(repeating: .max, count: uintCount)
            
            self.maskLastElement(bitCount: bitCount)
            
            self.value = Element(UInt(bitPattern: storage))
        }
    }
    
    @inlinable
    mutating func makeCanonical(descriptor: TextureDescriptor) {
        if self.value == .max || self.value == 0 { return }
        
        var setToValue: Element? = nil
        self.withUnsafePointerToStorage(descriptor: descriptor) { elements in
            if elements.allSatisfy({ $0 == 0 }) {
                setToValue = 0
                return
            }
            
            for element in elements.dropLast() {
                if element != .max {
                    return
                }
            }
            
            let bitCount = descriptor.subresourceCount
            let lastElementBits = bitCount % Element.bitWidth
            if lastElementBits != 0 {
                let uintCount = Self.uintCount(bitCount: bitCount)
                
                let lastElementBits = bitCount % Element.bitWidth
                if lastElementBits != 0, elements[uintCount - 1] != (1 << lastElementBits) - 1 {
                    return
                }
            } else {
                if elements.last! != .max {
                    return
                }
            }
            
            setToValue = .max // Ensure that .max for value is the _only_ representation of a full resource.
        }
        if let setToValue = setToValue {
            self.value = setToValue
        }
    }
    
    public subscript(slice slice: Int, level level: Int, descriptor: TextureDescriptor, allocator: AllocatorType) -> Bool {
        get {
            let count = descriptor.subresourceCount
            
            // Arranged by level, then slice
            let index = level * descriptor.slicesPerLevel + slice
            precondition(index < count)
            
            if count < Element.bitWidth {
                assert(index < UInt.bitWidth)
                return self.value[bit: index]
            } else {
                if self.value == .max { // Meaning the entire resource is in use.
                    return true
                } else if self.value == 0 {
                    return false
                }
                let storagePtr = UnsafeMutablePointer<Element>(bitPattern: UInt(exactly: self.value)!)!
                let (uintIndex, bitIndex) = index.quotientAndRemainder(dividingBy: Element.bitWidth)
                return storagePtr[uintIndex][bit: bitIndex]
            }
        }
        set {
            let count = descriptor.subresourceCount
            
            // Arranged by level, then slice
            let index = level * descriptor.slicesPerLevel + slice
            precondition(index < count)
            
            if count < Element.bitWidth {
                assert(index < UInt.bitWidth)
                self.value[bit: index] = newValue
            } else {
                if self.value == .max, newValue {
                    return
                }
                if self.value == 0, !newValue {
                    return
                }
                self.reserveStorage(bitCount: count, allocator: allocator)
                let storagePtr = UnsafeMutablePointer<Element>(bitPattern: UInt(exactly: self.value)!)!
                let (uintIndex, bitIndex) = index.quotientAndRemainder(dividingBy: Element.bitWidth)
                storagePtr[uintIndex][bit: bitIndex] = newValue
                
                self.makeCanonical(descriptor: descriptor)
            }
        }
    }
    
    public mutating func clear(descriptor: TextureDescriptor, allocator: AllocatorType) {
        self.withUnsafeMutablePointerToStorage(descriptor: descriptor, allocator: allocator) { storage in
            storage.assign(repeating: 0)
        }
    }
    
    @inlinable
    public func withUnsafePointerToStorage<T>(descriptor: TextureDescriptor, _ perform: (UnsafeBufferPointer<Element>) throws -> T) rethrows -> T {
        let count = descriptor.subresourceCount
        if count <= Element.bitWidth {
            return try withUnsafePointer(to: self.value, { try perform(UnsafeBufferPointer(start: $0, count: 1)) })
        } else {
            let storagePtr = UnsafePointer<Element>(bitPattern: UInt(exactly: self.value)!)!
            return try perform(UnsafeBufferPointer(start: storagePtr, count: Self.uintCount(bitCount: count)))
        }
    }
    
    @inlinable
    public mutating func withUnsafeMutablePointerToStorage<T>(descriptor: TextureDescriptor, allocator: AllocatorType, _ perform: (UnsafeMutableBufferPointer<Element>) throws -> T) rethrows -> T {
        let count = descriptor.subresourceCount
        if count <= Element.bitWidth {
            return try withUnsafeMutablePointer(to: &self.value, { try perform(UnsafeMutableBufferPointer(start: $0, count: 1)) })
        } else {
            self.reserveStorage(bitCount: count, allocator: allocator)
            let storagePtr = UnsafeMutablePointer<Element>(bitPattern: UInt(exactly: self.value)!)!
            return try perform(UnsafeMutableBufferPointer(start: storagePtr, count: Self.uintCount(bitCount: count)))
        }
    }
    
    @inlinable
    mutating func merge(with range: TextureSubresourceMask, operator: (Element, Element) -> Element, descriptor: TextureDescriptor, allocator: AllocatorType) {
        self.withUnsafeMutablePointerToStorage(descriptor: descriptor, allocator: allocator) { elements in
            range.withUnsafePointerToStorage(descriptor: descriptor) { otherElements in
                for i in elements.indices {
                    elements[i] = `operator`(elements[i], otherElements[i])
                }
            }
        }
        self.makeCanonical(descriptor: descriptor)
    }
    
    @inlinable
    public mutating func formUnion(with range: TextureSubresourceMask, descriptor: TextureDescriptor, allocator: AllocatorType) {
        if self.value == .max {
            return
        }
        if range.value == .max {
            self.value = .max
            return
        }
        
        self.merge(with: range, operator: |, descriptor: descriptor, allocator: allocator)
    }
    
    @inlinable
    public mutating func formIntersection(with range: TextureSubresourceMask, descriptor: TextureDescriptor, allocator: AllocatorType) {
        if range.value == .max {
            return
        }
        
        self.merge(with: range, operator: &, descriptor: descriptor, allocator: allocator)
    }
    
    @inlinable
    public mutating func removeAll(in range: TextureSubresourceMask, descriptor: TextureDescriptor, allocator: AllocatorType) {
        if range.value == 0 {
            return
        } else if range.value == .max {
            self.clear(descriptor: descriptor, allocator: allocator)
        }
        
        self.merge(with: range, operator: { a, b in a & ~b }, descriptor: descriptor, allocator: allocator)
        self.maskLastElement(bitCount: descriptor.subresourceCount)
    }
    
    @inlinable
    public func isEqual(to other: TextureSubresourceMask, descriptor: TextureDescriptor) -> Bool {
        if self.value == other.value { return true }
        let subresourceCount = descriptor.subresourceCount
        if subresourceCount <= Element.bitWidth {
            return false
        }
        
        return self.withUnsafePointerToStorage(descriptor: descriptor) { elements in
            return other.withUnsafePointerToStorage(descriptor: descriptor) { otherElements in
                return zip(elements, otherElements).allSatisfy({ $0 == $1 })
            }
        }
        
    }
}
