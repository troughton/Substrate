//
//  ResourceUsages.swift
//  RenderGraph
//
//  Created by Joseph Bennett on 20/12/17.
//

import SubstrateUtilities
import SubstrateCExtras

// This 'PerformOrder' type is necessary to make sure the command goes to the right Command Encoder
@usableFromInline enum PerformOrder : Comparable {
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
    
    mutating func mergeOrAppendUsage(_ usage: ResourceUsage, resource: Resource, allocator: TagAllocator, passCommands: ChunkArray<RenderGraphCommand>.RandomAccessView, passCommandOffset: Int) {
        guard !self.isEmpty, self.last.renderPassRecord == usage.renderPassRecord else {
            self.append(usage, allocator: .init(allocator))
            return
        }
        
        let subresourceCount = resource.subresourceCount
        guard let mergePointer = self.pointerToLast(where: { $0.renderPassRecord == usage.renderPassRecord && $0.activeRange.intersects(with: usage.activeRange, subresourceCount: subresourceCount) }) else {
            self.append(usage, allocator: .init(allocator))
            return
        }
        
        var usage = usage
        
        if usage.commandRange.lowerBound < mergePointer.pointee.commandRange.lowerBound {
            // We're inserting a duplicate usage (e.g. from a different subresource). Since all usages are passed to here in order, and the only reason this can occur is
            // via the 'previousLast.commandRange = usage.commandRange.upperBound..<previousLast.commandRange.upperBound' line below, there must already be a previous matching usage.
            
            let lastUsageBefore = self.pointerToLast(where: { $0.renderPassRecord == usage.renderPassRecord && $0.activeRange.intersects(with: usage.activeRange, subresourceCount: subresourceCount) && $0.commandRange.lowerBound <= usage.commandRange.lowerBound })!
            
            _ = lastUsageBefore.pointee.mergeWithUsage(&usage, allocator: .init(allocator))
            return
        }
        
        var previousLast = mergePointer.pointee
        
        if mergePointer.pointee.mergeWithUsage(&usage, allocator: .init(allocator)) {
            return
        }

        if previousLast.commandRange.upperBound > usage.commandRange.lowerBound {
            if previousLast.isWrite, !usage.isWrite {
                // Writes override reads; we should skip this usage.
                return
            }
            
            // Transform reads that overlap with writes into readWrites.
            switch usage.type {
            case .read:
                if previousLast.isWrite {
                    usage.type = .readWrite
                }
            case .write:
                if previousLast.isRead {
                    usage.type = .readWrite
                }
            default:
                break
            }
        }
        
        if usage.commandRange.lowerBound < mergePointer.pointee.commandRange.upperBound {
            mergePointer.pointee.commandRange = mergePointer.pointee.commandRange.lowerBound..<usage.commandRange.lowerBound
            
            if !passCommands[mergePointer.pointee.commandRange.offset(by: -passCommandOffset)].contains(where: { $0.isGPUActionCommand }) {
                // There are no active GPU commands in this range, so mark the usage as unused.
                mergePointer.pointee.type = .unusedArgumentBuffer
            }
        }
        
        self.append(usage, allocator: .init(allocator))
        
        // If the previous usage extended past the usage being added, add it again to the end of the list.
        if previousLast.commandRange.upperBound >= usage.commandRange.upperBound {
            previousLast.commandRange = usage.commandRange.upperBound..<previousLast.commandRange.upperBound
            
            if passCommands[previousLast.commandRange.offset(by: -passCommandOffset)].contains(where: { $0.isGPUActionCommand }) {
                self.append(previousLast, allocator: .init(allocator))
            }
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
    public var isUAVWrite : Bool {
        switch self {
        case .readWrite, .write:
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
    public var resource: Resource
    public var isIndirectlyBound : Bool // e.g. via a Metal argument buffer, Vulkan descriptor set, or an acceleration structure
    @usableFromInline
    let renderPassRecord : RenderPassRecord
    public var commandRange : Range<Int> // References the range in the pass before and during RenderGraph compilation, and the range in the full commands array after.
    public var activeRange: ActiveResourceRange = .fullResource
    
    
    @inlinable
    init(resource: Resource, type: ResourceUsageType, stages: RenderStages, activeRange: ActiveResourceRange, isIndirectlyBound: Bool, firstCommandOffset: Int, renderPass: RenderPassRecord) {
        self.resource = resource
        self.type = type
        self.stages = stages
        self.activeRange = activeRange
        self.renderPassRecord = renderPass
        self.commandRange = firstCommandOffset..<(firstCommandOffset + 1)
        self.isIndirectlyBound = isIndirectlyBound
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
        return self.stages != .cpuBeforeRender && self.type != .unusedRenderTarget && self.type != .unusedArgumentBuffer && self.renderPassRecord.type != .external && self.renderPassRecord.isActive
    }
    
    /// - returns: Whether the usages could be merged.
    @usableFromInline
    mutating func mergeWithUsage(_ nextUsage: inout ResourceUsage, allocator: AllocatorType) -> Bool {
        assert(self.renderPassRecord == nextUsage.renderPassRecord)
        assert(self.activeRange.intersects(with: nextUsage.activeRange, subresourceCount: resource.subresourceCount))
        
        let rangesOverlap = self.commandRange.lowerBound < nextUsage.commandRange.upperBound && nextUsage.commandRange.lowerBound < self.commandRange.upperBound
        
        if !rangesOverlap, self.type != nextUsage.type || (self.isWrite && nextUsage.type.isRead && !self.type.isRenderTarget) {
            // Don't merge usages of different types with non-overlapping ranges, and don't merge a write with a possible dependent read unless they're render target accesses.
            return false
        }
        
        if self.type.isRenderTarget || nextUsage.type.isRenderTarget {
            if self.type == .read || nextUsage.type == .read {
                // If we just wrote to a different mip than the one we're using as a render target.
                
                var readUsage = self
                var renderTargetUsage = nextUsage
                if readUsage.type != .read {
                    swap(&readUsage, &renderTargetUsage)
                }
                
                // It's an input attachment if we wrote to it before we started reading from it.
                var isInputAttachment = renderTargetUsage.commandRange.lowerBound < readUsage.commandRange.lowerBound
                                                                                        
                if !isInputAttachment, let previousRenderTargetUsage = self.resource.usages.dropLast().last(where: { $0.type.isRenderTarget }) {
                    if previousRenderTargetUsage.activeRange.isEqual(to: renderTargetUsage.activeRange, resource: self.resource), previousRenderTargetUsage.isWrite {
                        isInputAttachment = true
                    }
                }
                                                                                        
                if isInputAttachment {
                    self.type = .inputAttachmentRenderTarget
                    self.isIndirectlyBound = self.isIndirectlyBound || nextUsage.isIndirectlyBound
                    self.activeRange.formUnion(with: nextUsage.activeRange, resource: resource, allocator: allocator) // Since we're merging a read, it's technically possible to read from other levels/slices of the resource while simultaneously using it as an input attachment.
                } else {
                    return false
                }
                
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
            
            if self.type != nextUsage.type, !self.activeRange.isEqual(to: nextUsage.activeRange, subresourceCount: resource.subresourceCount) {
                return false
            }
            
            if self.type.isWrite, nextUsage.type.isRead {
                return false // We need to insert barriers between a write and a dependent read.
            }
            
            switch (self.type, nextUsage.type) {
                case (.read, .readWrite),
                    (.read, .write):
                    return false
                
                case  (.readWrite, .write):
                    self.type = .readWrite

                case _ where self.type == nextUsage.type:
                    break
                case _ where self.type.isWrite && nextUsage.type.isWrite:
                    preconditionFailure("Resource simultaneously bound for conflicting writes.")

                default:
                    return false
            }
            
            if self.isIndirectlyBound != nextUsage.isIndirectlyBound {
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
#if SUBSTRATE_DISABLE_AUTOMATIC_LABELS
        return "ResourceUsage(type: \(self.type), stages: \(self.stages), isIndirectlyBound: \(self.isIndirectlyBound), activeRange: \(self.activeRange), passIndex: \(self.renderPassRecord.passIndex), commandRange: \(self.commandRange))"
#else
        return "ResourceUsage(type: \(self.type), stages: \(self.stages), isIndirectlyBound: \(self.isIndirectlyBound), activeRange: \(self.activeRange), pass: \(self.renderPassRecord.name), commandRange: \(self.commandRange))"
#endif
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
