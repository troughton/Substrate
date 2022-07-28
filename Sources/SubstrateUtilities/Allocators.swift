//
//  Allocators.swift
//  SceneGraph
//
//  Created by Thomas Roughton on 26/03/18.
//

import Foundation
import Dispatch

public enum AllocatorType {
    case system
    case tag(TagAllocator)
    case threadLocalTag(ThreadLocalTagAllocator)
    case lockingTag(LockingTagAllocator)
    case tagTaskView(TagAllocator.StaticTaskView)
    case custom(Unmanaged<MemoryArena>)
    
    @inlinable
    public init(_ tag: TagAllocator) {
        self = .tag(tag)
    }
    
    @inlinable
    public init(_ threadLocalTag: ThreadLocalTagAllocator) {
        self = .threadLocalTag(threadLocalTag)
    }
    
    @inlinable
    public init(_ lockingTag: LockingTagAllocator) {
        self = .lockingTag(lockingTag)
    }
    
    @inlinable
    public init(_ tagTaskView: TagAllocator.StaticTaskView) {
        self = .tagTaskView(tagTaskView)
    }
    
    @inlinable
    public init(_ arena: Unmanaged<MemoryArena>) {
        self = .custom(arena)
    }
    
    @inlinable
    public var requiresDeallocation: Bool {
        switch self {
        case .system:
            return true
        default:
            return false
        }
    }
}

public final class Allocator {
    
    public static func allocate(byteCount: Int, alignment: Int, allocator: AllocatorType) -> UnsafeMutableRawPointer {
        switch allocator {
        case .system:
            return UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: alignment)
        case .tag(let tagAllocator):
            return tagAllocator.dynamicThreadView.allocate(bytes: byteCount, alignment: alignment)
        case .threadLocalTag(let tagAllocator):
            return tagAllocator.allocate(bytes: byteCount, alignment: alignment)
        case .lockingTag(let tagAllocator):
            return tagAllocator.allocate(bytes: byteCount, alignment: alignment)
        case .tagTaskView(let tagAllocator):
            return tagAllocator.allocate(bytes: byteCount, alignment: alignment)
        case .custom(let arena):
            return arena.takeUnretainedValue().allocate(bytes: byteCount, alignedTo: alignment)
        }
    }
    
    @inlinable
    public static func allocate<T>(type: T.Type = T.self, capacity: Int = 1, allocator: AllocatorType) -> UnsafeMutablePointer<T> {
        return self.allocate(byteCount: capacity * MemoryLayout<T>.stride, alignment: MemoryLayout<T>.alignment, allocator: allocator).bindMemory(to: T.self, capacity: capacity)
    }
    
    @inlinable
    public static func emplace<T>(value: T, allocator: AllocatorType) -> AllocatedHandle<T> {
        let memory = self.allocate(type: T.self, capacity: 1, allocator: allocator)
        memory.initialize(to: value)
        return AllocatedHandle(pointer: memory)
    }
    
    @inlinable
    public static func deallocate(_ memory: UnsafeMutableRawPointer, allocator: AllocatorType) {
        switch allocator {
        case .system:
            memory.deallocate()
        case .tag, .lockingTag, .tagTaskView, .threadLocalTag:
            break
        case .custom:
            break
        }
    }
    
    @inlinable
    public static func deallocate<T>(_ memory: UnsafeMutablePointer<T>, allocator: AllocatorType) {
        switch allocator {
        case .system:
            memory.deallocate()
        case .tag(let tagAllocator):
            assert(_isPOD(T.self) || tagAllocator.isValid)
            tagAllocator.deallocate(memory)
        case .threadLocalTag(let tagAllocator):
            assert(_isPOD(T.self) || tagAllocator.allocator.isValid)
            tagAllocator.deallocate(memory)
        case .lockingTag(let tagAllocator):
            assert(_isPOD(T.self) || tagAllocator.isValid)
            tagAllocator.deallocate(memory)
        case .tagTaskView(let tagAllocator):
            assert(_isPOD(T.self) || tagAllocator.allocator.isValid)
            tagAllocator.deallocate(memory)
        default:
            break
        }
    }
}

@dynamicMemberLookup
public struct AllocatedHandle<T> {
    public let pointer: UnsafeMutablePointer<T>
    
    @inlinable
    public init(pointer: UnsafeMutablePointer<T>) {
        self.pointer = pointer
    }
    
    @inlinable
    public subscript<U>(dynamicMember keyPath: KeyPath<T, U>) -> U {
        return self.pointer.pointee[keyPath: keyPath]
    }
    
    @inlinable
    public subscript<U>(dynamicMember keyPath: WritableKeyPath<T, U>) -> U {
        get {
            return self.pointer.pointee[keyPath: keyPath]
        }
        set {
            self.pointer.pointee[keyPath: keyPath] = newValue
        }
    }
}
