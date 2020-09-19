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
    case tagThreadView(TagAllocator.ThreadView)
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
    public init(_ tagThreadView: TagAllocator.ThreadView) {
        self = .tagThreadView(tagThreadView)
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
    
    @inlinable
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
        case .tagThreadView(let tagAllocator):
            return tagAllocator.allocate(bytes: byteCount, alignment: alignment)
        case .custom(let arena):
            return arena.takeUnretainedValue().allocate(bytes: byteCount, alignedTo: alignment)
        }
    }
    
    @inlinable
    public static func allocate<T>(type: T.Type = T.self, capacity: Int = 1, allocator: AllocatorType) -> UnsafeMutablePointer<T> {
        switch allocator {
        case .system:
            return UnsafeMutablePointer.allocate(capacity: capacity)
        case .tag(let tagAllocator):
            return tagAllocator.dynamicThreadView.allocate(capacity: capacity)
        case .threadLocalTag(let tagAllocator):
            return tagAllocator.allocate(capacity: capacity)
        case .lockingTag(let tagAllocator):
            return tagAllocator.allocate(capacity: capacity)
        case .tagThreadView(let tagAllocator):
            return tagAllocator.allocate(capacity: capacity)
        case .custom(let arena):
            return arena.takeUnretainedValue().allocate(count: capacity)
        }
    }
    
    @inlinable
    public static func deallocate(_ memory: UnsafeMutableRawPointer, allocator: AllocatorType) {
        switch allocator {
        case .system:
            memory.deallocate()
        case .tag, .lockingTag, .tagThreadView, .threadLocalTag:
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
        case .tagThreadView(let tagAllocator):
            assert(_isPOD(T.self) || tagAllocator.allocator.isValid)
            tagAllocator.deallocate(memory)
        default:
            break
        }
    }
}

