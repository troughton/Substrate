//
//  SubresourceMask.swift
//  
//
//  Created by Thomas Roughton on 23/08/20.
//

import Foundation
import FrameGraphUtilities

extension TextureDescriptor {
    @inlinable
    var slicesPerLevel: Int {
        var sliceCount = self.arrayLength * self.depth
        if self.textureType == .typeCube || self.textureType == .typeCubeArray {
            sliceCount *= 6
        }
        return sliceCount
    }
    
    @inlinable
    var subresourceCount: Int {
        return self.slicesPerLevel * self.mipmapLevelCount
    }
}

/// Represents a range of subresources within a texture.
/// Warning: depending on the texture slice count, this may behave as either a value or a reference type; as such, it should be treated as a move-only type.
public struct SubresourceMask {
    public typealias Element = UInt64
    @usableFromInline var value: Element = .max // .max means the entire resource is in use, and 0 means the entire resource is inactive
    
    public init() {
        
    }
    
    @inlinable
    public init(source: SubresourceMask, subresourceCount: Int, allocator: AllocatorType) {
        if source.value == .max {
            self.value = .max
            return
        }
        self.withUnsafeMutablePointerToStorage(subresourceCount: subresourceCount, allocator: allocator) { elements in
            source.withUnsafePointerToStorage(subresourceCount: subresourceCount) { sourceElements in
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
        if self.value == .max || self.value == 0 { // We haven't allocated the storage yet, so allocate it now.
            let uintCount = Self.uintCount(bitCount: bitCount)
            let storage = Allocator.allocate(type: Element.self, capacity: uintCount, allocator: allocator)
            storage.initialize(repeating: .max, count: uintCount)
            
            self.maskLastElement(bitCount: bitCount)
            
            self.value = Element(UInt(bitPattern: storage))
        }
    }
    
    
    public func deallocateStorage(subresourceCount: Int, allocator: AllocatorType) {
        guard allocator.requiresDeallocation, Self.uintCount(bitCount: subresourceCount) > 1,
              self.value != 0, self.value != .max else {
            return
        }
        
        let storagePointer = UnsafeMutablePointer<Element>(bitPattern: UInt(exactly: self.value)!)!
        Allocator.deallocate(storagePointer, allocator: allocator)
    }
    
    
    @inlinable
    public subscript(index: Int, subresourceCount count: Int) -> Bool {
        get {
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
    }
    
    @inlinable
    public subscript(index: Int, subresourceCount count: Int, allocator allocator: AllocatorType) -> Bool {
        get {
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
                
                self.makeCanonical(subresourceCount: count, allocator: allocator)
            }
        }
    }
    
    @inlinable
    mutating func makeCanonical(subresourceCount: Int, allocator: AllocatorType) {
        if self.value == .max || self.value == 0 { return }
        
        var setToValue: Element? = nil
        self.withUnsafePointerToStorage(subresourceCount: subresourceCount) { elements in
            if elements.allSatisfy({ $0 == 0 }) {
                setToValue = 0
                return
            }
            
            for element in elements.dropLast() {
                if element != .max {
                    return
                }
            }
            
            let bitCount = subresourceCount
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
            self.deallocateStorage(subresourceCount: subresourceCount, allocator: allocator)
            self.value = setToValue
        }
    }
    
    public mutating func clear(subresourceCount: Int, allocator: AllocatorType) {
        self.withUnsafeMutablePointerToStorage(subresourceCount: subresourceCount, allocator: allocator) { storage in
            storage.assign(repeating: 0)
        }
    }
    
    @inlinable
    public func withUnsafePointerToStorage<T>(subresourceCount count: Int, _ perform: (UnsafeBufferPointer<Element>) throws -> T) rethrows -> T {
        if count <= Element.bitWidth {
            return try withUnsafePointer(to: self.value, { try perform(UnsafeBufferPointer(start: $0, count: 1)) })
        } else {
            let storagePtr = UnsafePointer<Element>(bitPattern: UInt(exactly: self.value)!)!
            return try perform(UnsafeBufferPointer(start: storagePtr, count: Self.uintCount(bitCount: count)))
        }
    }
    
    @inlinable
    public mutating func withUnsafeMutablePointerToStorage<T>(subresourceCount count: Int, allocator: AllocatorType, _ perform: (UnsafeMutableBufferPointer<Element>) throws -> T) rethrows -> T {
        if count <= Element.bitWidth {
            return try withUnsafeMutablePointer(to: &self.value, { try perform(UnsafeMutableBufferPointer(start: $0, count: 1)) })
        } else {
            self.reserveStorage(bitCount: count, allocator: allocator)
            let storagePtr = UnsafeMutablePointer<Element>(bitPattern: UInt(exactly: self.value)!)!
            return try perform(UnsafeMutableBufferPointer(start: storagePtr, count: Self.uintCount(bitCount: count)))
        }
    }
    
    @inlinable
    mutating func merge(with range: SubresourceMask, operator: (Element, Element) -> Element, subresourceCount: Int, allocator: AllocatorType) {
        self.withUnsafeMutablePointerToStorage(subresourceCount: subresourceCount, allocator: allocator) { elements in
            range.withUnsafePointerToStorage(subresourceCount: subresourceCount) { otherElements in
                for i in elements.indices {
                    elements[i] = `operator`(elements[i], otherElements[i])
                }
            }
        }
        self.makeCanonical(subresourceCount: subresourceCount, allocator: allocator)
    }
    
    @inlinable
    public mutating func formUnion(with range: SubresourceMask, subresourceCount: Int, allocator: AllocatorType) {
        if self.value == .max {
            return
        }
        if range.value == .max {
            self.value = .max
            return
        }
        
        self.merge(with: range, operator: |, subresourceCount: subresourceCount, allocator: allocator)
    }
    
    @inlinable
    public mutating func formIntersection(with range: SubresourceMask, subresourceCount: Int, allocator: AllocatorType) {
        if self.value == 0 || range.value == .max {
            return
        }
        if range.value == 0 {
            self.value = 0
            return
        }
        
        self.merge(with: range, operator: &, subresourceCount: subresourceCount, allocator: allocator)
    }
    
    @inlinable
    public func intersects(with range: SubresourceMask, subresourceCount: Int) -> Bool {
        if self.value == 0 || range.value == 0 {
            return false
        }
        if self.value == .max || range.value == .max {
            return true
        }
        
        return self.withUnsafePointerToStorage(subresourceCount: subresourceCount) { elements in
            range.withUnsafePointerToStorage(subresourceCount: subresourceCount) { otherElements in
                for i in elements.indices {
                    if elements[i] & otherElements[i] != 0 {
                        return true
                    }
                }
                return false
            }
        }
    }
    
    @inlinable
    public mutating func removeAll(in range: SubresourceMask, subresourceCount: Int, allocator: AllocatorType) {
        if range.value == 0 {
            return
        } else if range.value == .max {
            self.clear(subresourceCount: subresourceCount, allocator: allocator)
        }
        
        self.merge(with: range, operator: { a, b in a & ~b }, subresourceCount: subresourceCount, allocator: allocator)
        self.maskLastElement(bitCount: subresourceCount)
    }
    
    @inlinable
    public func isEqual(to other: SubresourceMask, subresourceCount: Int) -> Bool {
        if self.value == other.value { return true }
        if subresourceCount <= Element.bitWidth {
            return false
        }
        
        return self.withUnsafePointerToStorage(subresourceCount: subresourceCount) { elements in
            return other.withUnsafePointerToStorage(subresourceCount: subresourceCount) { otherElements in
                return zip(elements, otherElements).allSatisfy({ $0 == $1 })
            }
        }
        
    }
}

extension SubresourceMask {
    
    @inlinable
    public subscript(slice slice: Int, level level: Int, descriptor descriptor: TextureDescriptor) -> Bool {
        get {
            let count = descriptor.subresourceCount
            
            // Arranged by level, then slice
            let index = level * descriptor.slicesPerLevel + slice
                print("Checking bit \(index) for slice \(slice) and level \(level)")
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
                let storagePtr = UnsafePointer<Element>(bitPattern: UInt(exactly: self.value)!)!
                let (uintIndex, bitIndex) = index.quotientAndRemainder(dividingBy: Element.bitWidth)
                print("Checking bit \(index) for slice \(slice) and level \(level) in \(storagePtr[uintIndex])")
                return storagePtr[uintIndex][bit: bitIndex]
            }
        }
    }
    
    @inlinable
    public subscript(slice slice: Int, level level: Int, descriptor descriptor: TextureDescriptor, allocator allocator: AllocatorType) -> Bool {
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
                
                self.makeCanonical(subresourceCount: descriptor.subresourceCount, allocator: allocator)
            }
        }
    }
}
