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
    case frame(UInt64)
}

public final class Allocator {
    @_versioned
    static let inflightFrames : UInt64 = 3
    
    @_versioned
    static let arenas = (0..<inflightFrames).map { _ in MemoryArena(blockSize: 2 * 1024 * 1024) }
    
    @_versioned
    static let arenaAccessQueues = (0..<inflightFrames).map { _ in DispatchQueue(label: "Memory allocator queue") }
    
    @inlinable
    public static func allocate(byteCount: Int, alignment: Int, allocator: AllocatorType) -> UnsafeMutableRawPointer {
        switch allocator {
        case .system:
            return UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: alignment)
        case .frame(let frame):
            let allocatorIndex = Int(frame % Allocator.inflightFrames)
            return self.arenaAccessQueues[allocatorIndex].sync { self.arenas[allocatorIndex].allocate(bytes: byteCount, alignedTo: alignment) }
        }
    }
    
    @inlinable
    public static func allocate<T>(capacity: Int = 1, allocator: AllocatorType) -> UnsafeMutablePointer<T> {
        switch allocator {
        case .system:
            return UnsafeMutablePointer.allocate(capacity: capacity)
        case .frame(let frame):
            let allocatorIndex = Int(frame % Allocator.inflightFrames)
            return self.arenaAccessQueues[allocatorIndex].sync { self.arenas[allocatorIndex].allocate(count: capacity) }
        }
    }
    
    @inlinable
    public static func deallocate(_ memory: UnsafeMutableRawPointer, allocator: AllocatorType) {
        switch allocator {
        case .system:
            memory.deallocate()
        case .frame:
            break
        }
    }

    @inlinable
    public static func frameCompleted(_ frame: UInt64) {
        let allocatorIndex = Int(frame % Allocator.inflightFrames)
        self.arenaAccessQueues[allocatorIndex].sync { self.arenas[allocatorIndex].reset() }
    }
}

