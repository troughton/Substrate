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
    
    @inlinable
    mutating func mergeOrAppendUsage(_ usage: ResourceUsage, resource: Resource, allocator: TagAllocator.ThreadView) {
        var usage = usage
        if self.isEmpty || !self.last.mergeWithUsage(&usage, allocator: .tagThreadView(allocator)) {
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
    public var resource: Resource
    public var inArgumentBuffer : Bool
    @usableFromInline
    let _renderPassRecord : Unmanaged<RenderPassRecord>
    public var commandRange : Range<Int> // References the range in the pass before and during RenderGraph compilation, and the range in the full commands array after.
    public var activeRange: ActiveResourceRange = .fullResource
    
    
    @inlinable
    init(resource: Resource, type: ResourceUsageType, stages: RenderStages, activeRange: ActiveResourceRange, inArgumentBuffer: Bool, firstCommandOffset: Int, renderPass: RenderPassRecord) {
        self.resource = resource
        self.type = type
        self.stages = stages
        self.activeRange = activeRange
        self._renderPassRecord = Unmanaged.passUnretained(renderPass)
        self.commandRange = Range(firstCommandOffset...firstCommandOffset)
        self.inArgumentBuffer = inArgumentBuffer
    }
    
    @inlinable
    var renderPassRecord: RenderPassRecord {
        return self._renderPassRecord._withUnsafeGuaranteedRef { $0 }
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
        return self.stages != .cpuBeforeRender && self.type != .unusedRenderTarget && self.type != .unusedArgumentBuffer && self._renderPassRecord._withUnsafeGuaranteedRef { $0.type != .external && $0.isActive }
    }
    
    /// - returns: Whether the usages could be merged.
    @usableFromInline
    mutating func mergeWithUsage(_ nextUsage: inout ResourceUsage, allocator: AllocatorType) -> Bool {
        if self._renderPassRecord.toOpaque() != nextUsage._renderPassRecord.toOpaque() || self.resource != nextUsage.resource {
            return false
        }
        
        let rangesOverlap = self.commandRange.lowerBound < nextUsage.commandRange.upperBound && nextUsage.commandRange.lowerBound < self.commandRange.upperBound
        let subresourcesOverlap = self.activeRange.intersects(with: nextUsage.activeRange, subresourceCount: resource.subresourceCount)

        if !rangesOverlap, !self.type.isRenderTarget || !(self.type.isWrite && nextUsage.type.isRead) {
            // Don't merge usages of different types with non-overlapping ranges, and don't merge a write with a possible dependent read unless they're render target accesses.
            return false
        }
        
        if self.type.isRenderTarget || nextUsage.type.isRenderTarget {
            if self.type == .read || nextUsage.type == .read {
                // If we just wrote to a different mip than the one we're using as a
                
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
                    self.inArgumentBuffer = self.inArgumentBuffer || nextUsage.inArgumentBuffer
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
            if !subresourcesOverlap, self.type != nextUsage.type {
                return false
            }

            switch (self.type, nextUsage.type) {
                case (.read, .readWrite),
                     (.readWrite, .read),
                     (.read, .write),
                     (.write, .read),
                     (.readWrite, .write),
                     (.write, .readWrite):
                    self.type = .readWrite

                case _ where self.type == nextUsage.type:
                    break
                case _ where self.type.isWrite && nextUsage.type.isWrite:
                    preconditionFailure("Resource simultaneously bound for conflicting writes.")

                default:
                    return false

            }
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
        return "ResourceUsage(type: \(self.type), stages: \(self.stages), inArgumentBuffer: \(self.inArgumentBuffer), activeRange: \(self.activeRange), pass: \(self.renderPassRecord.name), commandRange: \(self.commandRange))"
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
