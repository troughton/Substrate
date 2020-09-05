//
//  ResourceUsages.swift
//  FrameGraph
//
//  Created by Joseph Bennett on 20/12/17.
//

import FrameGraphUtilities
import FrameGraphCExtras

// This 'PerformOrder' type is necessary to make sure the command goes to the right Command Encoder
public enum PerformOrder : Comparable {
    case before // Before the command index
    case after // After the command index
    
    @inlinable
    public static func <(lhs: PerformOrder, rhs: PerformOrder) -> Bool {
        return lhs == .before && rhs == .after
    }
}

@usableFromInline typealias ResourceUsagePointer = UnsafeMutablePointer<ResourceUsage>

extension ChunkArray where Element == ResourceUsage {
    @inlinable
    var firstActiveUsage : ResourceUsage? {
        for usage in self {
            if usage.renderPassRecord.isActive, usage.type != .unusedRenderTarget, usage.type != .unusedArgumentBuffer {
                return usage
            }
        }
        return nil
    }
    
    @inlinable
    mutating func mergeOrAppendUsage(_ usage: ResourceUsage, resource: Resource, allocator: TagAllocator.ThreadView) {
        var usage = usage
        if self.isEmpty || !self.last.mergeWithUsage(&usage, resource: resource, allocator: .tagThreadView(allocator)) {
            self.append(usage, allocator: .tagThreadView(allocator))
        }
    }
}

extension ResourceUsageType {
    @inlinable
    public var isRead : Bool {
        switch self {
        case .read, .readWrite, .blitSource, .blitSynchronisation, .mipGeneration,
             .vertexBuffer, .indexBuffer, .indirectBuffer, .readWriteRenderTarget,
             .inputAttachment, .inputAttachmentRenderTarget, .constantBuffer:
            return true
        default:
            return false
        }
    }
    
    @inlinable
    public var isWrite : Bool {
        switch self {
        case .write, .readWrite, .readWriteRenderTarget, .writeOnlyRenderTarget, .inputAttachmentRenderTarget, .blitDestination, .blitSynchronisation, .mipGeneration:
            return true
        default:
            return false
        }
    }
    
    @inlinable
    public var isUAVReadWrite : Bool {
        switch self {
        case .readWrite:
            return true
        default:
            return false
        }
    }
}

// Note: must be a value type.
public struct ResourceUsage {
    public var type : ResourceUsageType
    public var stages : RenderStages
    public var inArgumentBuffer : Bool
    @usableFromInline
    unowned(unsafe) var renderPassRecord : RenderPassRecord
    public var commandRange : Range<Int> // References the range in the pass before and during FrameGraph compilation, and the range in the full commands array aftre.
    public var activeRange: ActiveResourceRange = .fullResource
    
    @inlinable
    init(type: ResourceUsageType, stages: RenderStages, activeRange: ActiveResourceRange, inArgumentBuffer: Bool, firstCommandOffset: Int, renderPass: RenderPassRecord) {
        self.type = type
        self.stages = stages
        self.activeRange = activeRange
        self.renderPassRecord = renderPass
        self.commandRange = Range(firstCommandOffset...firstCommandOffset)
        self.inArgumentBuffer = inArgumentBuffer
    }
    
    @inlinable
    public var isRead : Bool {
        return self.type.isRead
    }
    
    @inlinable
    public var isWrite : Bool {
        return self.type.isWrite
    }
    
    @inlinable
    public var affectsGPUBarriers : Bool {
        return self.renderPassRecord.isActive && self.stages != .cpuBeforeRender && self.type != .unusedRenderTarget && self.renderPassRecord.pass.passType != .external
    }
    
    /// - returns: Whether the usages could be merged.
    @inlinable
    mutating func mergeWithUsage(_ nextUsage: inout ResourceUsage, resource: Resource, allocator: AllocatorType) -> Bool {
        if self.renderPassRecord !== nextUsage.renderPassRecord {
            return false
        }
        
        let rangesOverlap = self.commandRange.lowerBound < nextUsage.commandRange.upperBound && nextUsage.commandRange.lowerBound < self.commandRange.upperBound
        
        if !rangesOverlap, (nextUsage.type != self.type || nextUsage.activeRange != self.activeRange), !self.type.isRenderTarget || !(self.type.isWrite && nextUsage.type.isRead) {
            // Don't merge usages of different types with non-overlapping ranges, and don't merge a write with a possible dependent read unless they're render target accesses.
            return false
        }
        
        if !self.isWrite, !nextUsage.isWrite, nextUsage.type != self.type {
            return false // Don't merge reads of different types
        }
        
        if self.type.isRenderTarget || nextUsage.type.isRenderTarget {
            if self.type == .read || nextUsage.type == .read {
                self.type = .inputAttachmentRenderTarget
                self.inArgumentBuffer = true
            }
            
            if self.type != .inputAttachmentRenderTarget {
                assert(self.type.isRenderTarget && nextUsage.type.isRenderTarget)
                let isRead = self.type.isRead || nextUsage.type.isRead
                let isWrite = self.type.isWrite || nextUsage.type.isWrite
                
                if isRead {
                    self.type = .readWriteRenderTarget
                } else if isWrite {
                    self.type = .writeOnlyRenderTarget
                } else {
                    assert(self.type == .unusedRenderTarget && nextUsage.type == .unusedRenderTarget)
                }
            }
        } else {
            assert(self.type == nextUsage.type || !self.type.isWrite || !nextUsage.type.isWrite, "Resource simultaneously bound for conflicting writes.")
            if self.inArgumentBuffer != nextUsage.inArgumentBuffer {
                return false
            }
        }
        
        self.stages.formUnion(nextUsage.stages)
        if self.type != .inputAttachmentRenderTarget {
            self.activeRange.formUnion(with: nextUsage.activeRange, resource: resource, allocator: allocator)
        }
        self.commandRange = Range(uncheckedBounds: (min(self.commandRange.lowerBound, nextUsage.commandRange.lowerBound), max(self.commandRange.upperBound, nextUsage.commandRange.upperBound)))
        
        return true
    }
}


extension ResourceUsage : CustomStringConvertible {
    public var description: String {
        return "ResourceUsage(type: \(self.type), stages: \(self.stages), inArgumentBuffer: \(self.inArgumentBuffer), pass: \(self.renderPassRecord.pass.name), commandRange: \(self.commandRange))"
    }
}

fileprivate extension Array {
    var mutableLast : Element {
        get {
            return self[self.count - 1]
        }
        set {
            self[self.count - 1] = newValue
        }
    }
}

extension Unmanaged : Hashable, Equatable where Instance : Hashable {
    public func hash(into hasher: inout Hasher) {
        self.takeUnretainedValue().hash(into: &hasher)
    }
    
    public static func ==(lhs: Unmanaged, rhs: Unmanaged) -> Bool {
        return lhs.takeUnretainedValue() == rhs.takeUnretainedValue()
    }
}

extension UInt64 : CustomHashable {
    public var customHashValue : Int {
        return Int(truncatingIfNeeded: self)
    }
}
