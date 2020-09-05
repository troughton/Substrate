//
//  TextureSubresourceMask.swift
//  
//
//  Created by Thomas Roughton on 23/08/20.
//

import Foundation
import FrameGraphUtilities

public struct TextureSubresourceMask: Equatable {
    @usableFromInline var value: UInt64 = .max // Meaning the entire resource is in use.
    
    public init() {
        
    }
    
    @inlinable
    static func uintCount(bitCount: Int) -> Int {
        return (bitCount + UInt64.bitWidth - 1) / UInt64.bitWidth
    }
    
    @usableFromInline
    mutating func reserveStorage(bitCount: Int, allocator: AllocatorType) {
        precondition(bitCount > UInt64.bitWidth)
        if self.value == .max { // We haven't allocated the storage yet, so allocate it now.
            let uintCount = Self.uintCount(bitCount: bitCount)
            let storage = Allocator.allocate(type: UInt64.self, capacity: uintCount, allocator: allocator)
            storage.initialize(repeating: .max, count: uintCount)
            self.value = UInt64(UInt(bitPattern: storage))
        }
    }
    
    public subscript(slice slice: Int, level level: Int, descriptor: TextureDescriptor, allocator: AllocatorType) -> Bool {
        get {
            let count = descriptor.slicesPerLevel * descriptor.mipmapLevelCount
            
            // Arranged by level, then slice
            let index = level * descriptor.slicesPerLevel + slice
            precondition(index < count)
            
            if count < UInt64.bitWidth {
                assert(index < UInt.bitWidth)
                return self.value[bit: index]
            } else {
                if self.value == .max { // Meaning the entire resource is in use.
                    return true
                }
                let storagePtr = UnsafeMutablePointer<UInt64>(bitPattern: UInt(exactly: self.value)!)!
                let (uintIndex, bitIndex) = index.quotientAndRemainder(dividingBy: UInt64.bitWidth)
                return storagePtr[uintIndex][bit: bitIndex]
            }
        }
        set {
            let count = descriptor.slicesPerLevel * descriptor.mipmapLevelCount
            
            // Arranged by level, then slice
            let index = level * descriptor.slicesPerLevel + slice
            precondition(index < count)
            
            if count < UInt64.bitWidth {
                assert(index < UInt.bitWidth)
                self.value[bit: index] = newValue
            } else {
                self.reserveStorage(bitCount: count, allocator: allocator)
                let storagePtr = UnsafeMutablePointer<UInt64>(bitPattern: UInt(exactly: self.value)!)!
                let (uintIndex, bitIndex) = index.quotientAndRemainder(dividingBy: UInt64.bitWidth)
                storagePtr[uintIndex][bit: bitIndex] = newValue
            }
        }
    }
    
    public mutating func clear(descriptor: TextureDescriptor, allocator: AllocatorType) {
        self.withUnsafeMutablePointerToStorage(descriptor: descriptor, allocator: allocator) { storage in
            storage.assign(repeating: 0)
        }
    }
    
    @inlinable
    public func withUnsafePointerToStorage<T>(descriptor: TextureDescriptor, _ perform: (UnsafeBufferPointer<UInt64>) throws -> T) rethrows -> T {
        let count = descriptor.slicesPerLevel * descriptor.mipmapLevelCount
        if count <= UInt64.bitWidth {
            return try withUnsafePointer(to: self.value, { try perform(UnsafeBufferPointer(start: $0, count: 1)) })
        } else {
            let storagePtr = UnsafePointer<UInt64>(bitPattern: UInt(exactly: self.value)!)!
            return try perform(UnsafeBufferPointer(start: storagePtr, count: Self.uintCount(bitCount: count)))
        }
    }
    
    @inlinable
    public mutating func withUnsafeMutablePointerToStorage<T>(descriptor: TextureDescriptor, allocator: AllocatorType, _ perform: (UnsafeMutableBufferPointer<UInt64>) throws -> T) rethrows -> T {
        let count = descriptor.slicesPerLevel * descriptor.mipmapLevelCount
        if count <= UInt64.bitWidth {
            return try withUnsafeMutablePointer(to: &self.value, { try perform(UnsafeMutableBufferPointer(start: $0, count: 1)) })
        } else {
            self.reserveStorage(bitCount: count, allocator: allocator)
            let storagePtr = UnsafeMutablePointer<UInt64>(bitPattern: UInt(exactly: self.value)!)!
            return try perform(UnsafeMutableBufferPointer(start: storagePtr, count: Self.uintCount(bitCount: count)))
        }
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
        
        self.withUnsafeMutablePointerToStorage(descriptor: descriptor, allocator: allocator) { elements in
            range.withUnsafePointerToStorage(descriptor: descriptor) { otherElements in
                for i in elements.indices {
                    elements[i] |= otherElements[i]
                }
            }
        }
    }
    
    public static func ==(lhs: TextureSubresourceMask, rhs: TextureSubresourceMask) -> Bool {
        return lhs.value == rhs.value // TODO: This will incorrectly return false when the pointees are identical but the pointers differ; maybe we could encode the storageCount in the value pointer (changing the value pointer to an offset into the tagged heap)?
    }
}
