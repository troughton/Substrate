//
//  TextureSubresourceMask.swift
//  
//
//  Created by Thomas Roughton on 23/08/20.
//

import Foundation
import FrameGraphUtilities

public struct TextureSubresourceMask {
    @usableFromInline var value: UInt64 = .max // Meaning the entire resource is in use.
    
    public init() {
        
    }
    
    mutating func reserveStorage(bitCount: Int, allocator: AllocatorType) {
        precondition(bitCount > UInt64.bitWidth)
        if self.value == .max { // We haven't allocated the storage yet, so allocate it now.
            let uintCount = (bitCount + UInt64.bitWidth - 1) / UInt64.bitWidth
            let storage = Allocator.allocate(type: UInt64.self, capacity: uintCount, allocator: allocator)
            storage.initialize(repeating: .max, count: uintCount)
            self.value = UInt64(UInt(bitPattern: storage))
        }
    }
    
    subscript(slice slice: Int, level level: Int, descriptor: TextureDescriptor, allocator: AllocatorType) -> Bool {
        get {
            let count = descriptor.arrayLength * descriptor.mipmapLevelCount
            
            // Arranged by level, then slice
            let index = level * descriptor.arrayLength + slice
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
            let count = descriptor.arrayLength * descriptor.mipmapLevelCount
            
            // Arranged by level, then slice
            let index = level * descriptor.arrayLength + slice
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
    
    @inlinable
    public func withUnsafePointerToStorage<T>(descriptor: TextureDescriptor, _ perform: (UnsafePointer<UInt64>) throws -> T) rethrows -> T {
        let count = descriptor.arrayLength * descriptor.mipmapLevelCount
        if count <= UInt64.bitWidth {
            return try withUnsafePointer(to: self.value, perform)
        } else {
            let storagePtr = UnsafePointer<UInt64>(bitPattern: UInt(exactly: self.value)!)!
            return try perform(storagePtr)
        }
    }
    
    @inlinable
    public mutating func withUnsafeMutablePointerToStorage<T>(descriptor: TextureDescriptor, _ perform: (UnsafeMutablePointer<UInt64>) throws -> T) rethrows -> T {
        let count = descriptor.arrayLength * descriptor.mipmapLevelCount
        if count <= UInt64.bitWidth {
            return try withUnsafeMutablePointer(to: &self.value, perform)
        } else {
            let storagePtr = UnsafeMutablePointer<UInt64>(bitPattern: UInt(exactly: self.value)!)!
            return try perform(storagePtr)
        }
    }
}
