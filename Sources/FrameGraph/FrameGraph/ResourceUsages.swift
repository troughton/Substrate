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
    
    // This doesn't need any special synchronisation since nodes can only be merged within a render pass.
    @inlinable
    mutating func mergeOrAppendUsage(type: ResourceUsageType, stages: RenderStages, inArgumentBuffer: Bool, commandOffset: Int, renderPass: RenderPassRecord, allocator: TagAllocator.ThreadView) -> ResourceUsagePointer {
        let passIndex = renderPass.passIndex
        if !self.isEmpty, self.last.renderPassRecord.passIndex == passIndex {
            assert(self.last.renderPassRecord === renderPass)
            if let newUsage = self.last.mergeOrCreateNewUsage(type: type, stages: stages, inArgumentBuffer: inArgumentBuffer, firstCommandOffset: commandOffset, renderPass: renderPass) {
                assert(renderPass !== self.last.renderPassRecord || commandOffset >= self.last.commandRangeInPass.lowerBound, "Adding a new usage which starts before the previous usage has ended.")
                self.append(newUsage, allocator: .tagThreadView(allocator))
            }
        } else {
            self.append(ResourceUsage(type: type, stages: stages, inArgumentBuffer: inArgumentBuffer, firstCommandOffset: commandOffset, renderPass: renderPass), allocator: .tagThreadView(allocator))
        }
        return self.pointerToLast
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
    
    @inlinable
    static func areMergeable(_ typeA: ResourceUsageType, _ typeB: ResourceUsageType) -> Bool {
        // We can only merge resources of the same type, and we can only merge writes if they're contained within a render target.
        return typeA == typeB &&
            (!typeA.isWrite || typeA.isRenderTarget)
    }
}

// Note: must be a value type.
public struct ResourceUsage {
    public var type : ResourceUsageType
    public var stages : RenderStages
    public var inArgumentBuffer : Bool
    @usableFromInline
    unowned(unsafe) var renderPassRecord : RenderPassRecord
    @usableFromInline
    var commandRangeInPass : Range<Int>
    public var textureSubresourceMask: TextureSubresourceMask
    public var bufferAccessedRange: Range<Int>
    
    @inlinable
    init(type: ResourceUsageType, stages: RenderStages, inArgumentBuffer: Bool, firstCommandOffset: Int, renderPass: RenderPassRecord) {
        self.type = type
        self.stages = stages
        self.renderPassRecord = renderPass
        self.commandRangeInPass = Range(firstCommandOffset...firstCommandOffset)
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
    
    @inlinable
    public var commandRange : Range<Int> {
        let startIndex = renderPassRecord.commandRange!.lowerBound
        return (self.commandRangeInPass.lowerBound + startIndex)..<(self.commandRangeInPass.upperBound + startIndex)
    }
    
    /// - returns: The new usage, if the usage couldn't be merged with self.
    @inlinable
    mutating func mergeOrCreateNewUsage(type: ResourceUsageType, stages: RenderStages, inArgumentBuffer: Bool, firstCommandOffset: Int, renderPass: RenderPassRecord) -> ResourceUsage? {
        assert(self.renderPassRecord === renderPass)
        
        if type == .inputAttachment && self.type.isRenderTarget { // Transform a resource read within a render target into a readWriteRenderTarget.
            self.type = .inputAttachmentRenderTarget
            self.stages.formUnion(stages)
            self.inArgumentBuffer = self.inArgumentBuffer || inArgumentBuffer
            self.commandRangeInPass = Range(uncheckedBounds: (self.commandRangeInPass.lowerBound, firstCommandOffset + 1))
            return nil
        }
        
        readWriteMergeCheck: if self.commandRangeInPass.contains(firstCommandOffset), stages == self.stages, self.type != type {
            assert(self.renderPassRecord === renderPass)
            assert(self.inArgumentBuffer == inArgumentBuffer)
            
            switch (type, self.type) {
            case (.read, .readWrite), (.write, .write), (.write, .readWrite):
                break
            case (.read, .write), (.readWrite, .read), (.write, .read):
                self.type = .readWrite
            case (.writeOnlyRenderTarget, .readWriteRenderTarget), (.readWriteRenderTarget, .writeOnlyRenderTarget):
                self.type = .readWriteRenderTarget
            case (_, _) where !type.isWrite && !self.type.isWrite:
                // If neither are writes, then it's fine to have conflicting uses.
                // This might occur e.g. when reading from a buffer while simultaneously using it as an indirect buffer.
                break readWriteMergeCheck
            default:
                assertionFailure("Resource simulaneously bound for conflicting uses.")
            }
            
            return nil
        }
        
        if ResourceUsageType.areMergeable(self.type, type) &&
            self.inArgumentBuffer == inArgumentBuffer {
            self.stages.formUnion(stages)
            self.commandRangeInPass = Range(uncheckedBounds: (self.commandRangeInPass.lowerBound, firstCommandOffset + 1))
            return nil
        }
        
        return ResourceUsage(type: type, stages: stages, inArgumentBuffer: inArgumentBuffer, firstCommandOffset: firstCommandOffset, renderPass: renderPass)
        
    }
}


extension ResourceUsage : CustomStringConvertible {
    public var description: String {
        return "ResourceUsage(type: \(self.type), stages: \(self.stages), inArgumentBuffer: \(self.inArgumentBuffer), pass: \(self.renderPassRecord.pass.name), commandRangeInPass: \(self.commandRangeInPass))"
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

// Responsible for holding a per-thread allocator for Resource usage nodes, along with keeping track of all resources seen on this thread.
// Can safely switch between multiple render passes being executed on the same thread (e.g. in different fibres).
@usableFromInline
class ResourceUsages {
    
    @usableFromInline
    unowned(unsafe) var frameGraph: FrameGraph! = nil
    
    @usableFromInline
    var usageNodeAllocator : TagAllocator.ThreadView! = nil
    
    @usableFromInline
    var usageArrays = [Resource: ChunkArray<ResourceUsage>]()
    
    @inlinable
    init() {
        
    }
    
    func reset() {
        self.usageArrays.removeAll(keepingCapacity: true)
        self.usageNodeAllocator = nil
    }
    
    @inlinable
    subscript(usagesFor resource: Resource) -> ChunkArray<ResourceUsage> {
        get {
            return self.usageArrays[resource] ?? ChunkArray()
        }
        set {
            self.usageArrays[resource] = newValue
        }
    }
    
    func addReadResources(_ resources: [Resource], `for` renderPass: RenderPassRecord) {
        for resource in resources {
            self[usagesFor: resource].append(ResourceUsage(type: .read, stages: .cpuBeforeRender, inArgumentBuffer: false, firstCommandOffset: 0, renderPass: renderPass), allocator: .tagThreadView(self.usageNodeAllocator))
        }
    }
    
    func addWrittenResources(_ resources: [Resource], `for` renderPass: RenderPassRecord) {
        for resource in resources {
            self[usagesFor: resource].append(ResourceUsage(type: .write, stages: .cpuBeforeRender, inArgumentBuffer: false, firstCommandOffset: 0, renderPass: renderPass), allocator: .tagThreadView(self.usageNodeAllocator))
        }
    }
    
    
    /// NOTE: Must be called _before_ the command that uses the resource.
    @inlinable
    public func resourceUsageNode<C : CommandEncoder>(`for` resourceHandle: Resource.Handle, encoder: C, usageType: ResourceUsageType, stages: RenderStages, inArgumentBuffer: Bool, firstCommandOffset: Int) -> ResourceUsagePointer {
        assert(encoder.renderPass.writtenResources.isEmpty || encoder.renderPass.writtenResources.contains(where: { $0.handle == resourceHandle }) || encoder.renderPass.readResources.contains(where: { $0.handle == resourceHandle }), "Resource \(resourceHandle) used but not declared.")
        
        let resource = Resource(handle: resourceHandle)
        assert(resource.isValid, "Resource \(resource) is invalid; it may be being used in a frame after it was created if it's a transient resource, or else may have been disposed if it's a persistent resource.")
        
        assert(resource.type != .argumentBuffer || !usageType.isWrite, "Read-write argument buffers are currently unsupported.")
        assert(!usageType.isWrite || !resource.flags.contains(.immutableOnceInitialised) || !resource.stateFlags.contains(.initialised), "immutableOnceInitialised resource \(resource) is being written to after it has been initialised.")
        
        if resource.flags.contains(.persistent) {
            if let textureUsage = resource.texture?.descriptor.usageHint {
                if usageType == .read {
                    assert(textureUsage.contains(.shaderRead))
                }
                if usageType.isRenderTarget {
                    assert(textureUsage.contains(.renderTarget))
                }
                if usageType == .write || usageType == .readWrite {
                    assert(textureUsage.contains(.shaderWrite))
                }
                if usageType == .blitSource {
                    assert(textureUsage.contains(.blitSource))
                }
                if usageType == .blitDestination {
                    assert(textureUsage.contains(.blitDestination))
                }
            } else if let bufferUsage = resource.buffer?.descriptor.usageHint {
                if usageType == .read {
                    assert(bufferUsage.contains(.shaderRead))
                }
                if usageType == .write || usageType == .readWrite {
                    assert(bufferUsage.contains(.shaderWrite))
                }
                if usageType == .blitSource {
                    assert(bufferUsage.contains(.blitSource))
                }
                if usageType == .blitDestination {
                    assert(bufferUsage.contains(.blitDestination))
                }
                if usageType == .vertexBuffer {
                    assert(bufferUsage.contains(.vertexBuffer))
                }
                if usageType == .indexBuffer {
                    assert(bufferUsage.contains(.indexBuffer))
                }
            }
        }
        
        
        let usagePtr = self[usagesFor: resource].mergeOrAppendUsage(type: usageType, stages: stages, inArgumentBuffer: inArgumentBuffer, commandOffset: firstCommandOffset, renderPass: encoder.passRecord, allocator: self.usageNodeAllocator)
        
        return usagePtr
    }
    
    /// NOTE: Must be called _before_ the command that uses the resource.
    @inlinable
    public func addResourceUsage<C : CommandEncoder, R: ResourceProtocol>(`for` resource: R, commandIndex: Int, encoder: C, usageType: ResourceUsageType, stages: RenderStages, inArgumentBuffer: Bool) {
        
        let _ = self.resourceUsageNode(for: resource.handle, encoder: encoder, usageType: usageType, stages: stages, inArgumentBuffer: inArgumentBuffer, firstCommandOffset: commandIndex)
    }
    
}
