//
//  ResourceUsages.swift
//  FrameGraph
//
//  Created by Joseph Bennett on 20/12/17.
//

import Utilities

// This 'PerformOrder' type is necessary to make sure the command goes to the right Command Encoder
public enum PerformOrder : Comparable {
    case before // Before the command index
    case after // After the command index
    
    @inlinable
    public static func <(lhs: PerformOrder, rhs: PerformOrder) -> Bool {
        return lhs == .before && rhs == .after
    }
}

@_fixed_layout
public struct LinkedNode<T> {
    public var element: T
    public var next: UnsafeMutablePointer<LinkedNode>?
    
    @inlinable
    public init(value: T) {
        self.element = value
    }
}

public typealias ResourceUsageNodePtr = UnsafeMutablePointer<LinkedNode<ResourceUsage>>

public struct ResourceUsagesList : Sequence {
    @usableFromInline
    var head : ResourceUsageNodePtr? = nil
    @usableFromInline
    var tail : ResourceUsageNodePtr? = nil
    
    // Mask in the frame into the count; lower 32 bits are the count, upper 32 are the frame.
    public private(set) var count = 0
    
    @inlinable
    public init() {
        
    }
    
    @inlinable
    public mutating func append(_ usage: ResourceUsage, arena: MemoryArena) {
        let node = self.createNode(usage: usage, arena: arena)
        self.append(node)
    }
    
    @inlinable
    public func createNode(usage: ResourceUsage, arena: MemoryArena) -> ResourceUsageNodePtr {
        let node = arena.allocate() as ResourceUsageNodePtr
        node.initialize(to: LinkedNode(value: usage))
        return node
    }
    
    @inlinable
    public mutating func append(_ usageNode: ResourceUsageNodePtr) {
        if let currentTail = self.tail {
            currentTail.pointee.next = usageNode
            self.tail = usageNode
        } else {
            self.head = usageNode
            self.tail = usageNode
        }
        
        self.count += 1
    }
    
    @inlinable
    public mutating func nextNodeWithUsage(type: ResourceUsageType, stages: RenderStages, inArgumentBuffer: Bool, commandOffset: Int, renderPass: Unmanaged<RenderPassRecord>, arena: MemoryArena) -> (ResourceUsageNodePtr, isNew: Bool) {
        if let tail = self.tail {
            if let newUsage = self.last.mergeOrCreateNewUsage(type: type, stages: stages, inArgumentBuffer: inArgumentBuffer, firstCommandOffset: commandOffset, renderPass: renderPass) {
                assert(renderPass.toOpaque() != tail.pointee.element._renderPass.toOpaque() || commandOffset >= tail.pointee.element.commandRangeInPass.lowerBound, "Adding a new usage which starts before the previous usage has ended.")
                let node = self.createNode(usage: newUsage, arena: arena)
                return (node, true)
            } else {
                return (tail, false)
            }
        }
        return (self.createNode(usage: ResourceUsage(type: type, stages: stages, inArgumentBuffer: inArgumentBuffer, firstCommandOffset: commandOffset, renderPass: renderPass), arena: arena), true)
    }

    @inlinable
    public var first : ResourceUsage {
        get {
            return self.head!.pointee.element
        }
        set {
            self.head!.pointee.element = newValue
        }
    }
    
    @inlinable
    public var last : ResourceUsage {
        get {
            return self.tail!.pointee.element
        }
        set {
            self.tail!.pointee.element = newValue
        }
    }

    @inlinable
    public var firstActiveUsage : ResourceUsage? {
        for usage in self {
            if usage.renderPass.isActive {
                return usage
            }
        }
        return nil
    }
    
    @inlinable
    public var isEmpty : Bool {
        return self.head == nil
    }
    
    @_fixed_layout
    public struct Iterator : IteratorProtocol {
        public typealias Element = ResourceUsage
        
        @usableFromInline
        var nextNode : ResourceUsageNodePtr?
        
        @inlinable
        public init(nextNode: ResourceUsageNodePtr?) {
            self.nextNode = nextNode
        }
        
        @inlinable
        public mutating func next() -> ResourceUsage? {
            if let node = nextNode {
                let element = node.pointee.element
                nextNode = node.pointee.next
                return element
            }
            return nil
        }
    }
    
    @inlinable
    public func makeIterator() -> ResourceUsagesList.Iterator {
        return Iterator(nextNode: self.head)
    }
}

// Note: must be a value type.
@_fixed_layout
public struct ResourceUsage {
    public var type : ResourceUsageType
    public var stages : RenderStages
    public var inArgumentBuffer : Bool
    @usableFromInline
    var _renderPass : Unmanaged<RenderPassRecord>
    @usableFromInline
    var commandRangeInPass : Range<Int>
    
    
    @inlinable
    public init(type: ResourceUsageType, stages: RenderStages, inArgumentBuffer: Bool, firstCommandOffset: Int, renderPass: Unmanaged<RenderPassRecord>) {
        self.type = type
        self.stages = stages
        self._renderPass = renderPass
        self.commandRangeInPass = Range(firstCommandOffset...firstCommandOffset)
        self.inArgumentBuffer = inArgumentBuffer
    }
    
    @inlinable
    public var renderPass : RenderPassRecord {
        return _renderPass.takeUnretainedValue()
    }
    
    @inlinable
    public var isRead : Bool {
        switch self.type {
        case .read, .readWrite, .blitSource, .blitSynchronisation, 
             .vertexBuffer, .indexBuffer, .indirectBuffer, .readWriteRenderTarget,
             .inputAttachment, .inputAttachmentRenderTarget, .constantBuffer:
            return true
        default:
            return false
        }
    }
    
    @inlinable
    public var isWrite : Bool {
        switch self.type {
        case .write, .readWrite, .readWriteRenderTarget, .writeOnlyRenderTarget, .inputAttachmentRenderTarget, .blitDestination, .blitSynchronisation:
            return true
        default:
            return false
        }
    }
    
    @inlinable
    public var commandRange : Range<Int> {
        let startIndex = renderPass.commandRange!.lowerBound
        return (self.commandRangeInPass.lowerBound + startIndex)..<(self.commandRangeInPass.upperBound + startIndex)
    }
    
    @inlinable
    public mutating func mergeOrCreateNewUsage(type: ResourceUsageType, stages: RenderStages, inArgumentBuffer: Bool, firstCommandOffset: Int, renderPass: Unmanaged<RenderPassRecord>) -> ResourceUsage? {
        if type == .inputAttachment && self.type.isRenderTarget &&
            self._renderPass.toOpaque() == renderPass.toOpaque() { // Transform a resource read within a render target into a readWriteRenderTarget.
            self.type = .inputAttachmentRenderTarget
            self.stages.formUnion(stages)
            self.inArgumentBuffer = self.inArgumentBuffer || inArgumentBuffer
            self.commandRangeInPass = Range(uncheckedBounds: (self.commandRangeInPass.lowerBound, firstCommandOffset + 1))
            return nil
        }
        
        if self.type == type &&
            self._renderPass.toOpaque() == renderPass.toOpaque() &&
            self.inArgumentBuffer == inArgumentBuffer {
            self.stages.formUnion(stages)
            self.commandRangeInPass = Range(uncheckedBounds: (self.commandRangeInPass.lowerBound, firstCommandOffset + 1))
            return nil
        } else {
            return ResourceUsage(type: type, stages: stages, inArgumentBuffer: inArgumentBuffer, firstCommandOffset: firstCommandOffset, renderPass: renderPass)
        }
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
    public var hashValue : Int {
        return self.takeUnretainedValue().hashValue
    }
    
    public static func ==(lhs: Unmanaged, rhs: Unmanaged) -> Bool {
        return lhs.takeUnretainedValue() == rhs.takeUnretainedValue()
    }
}

extension UInt64 : CustomHashable {
    public var customHashValue : Int {
        return self.hashValue
    }
}

public class ResourceUsages {
    
    @usableFromInline
    let usageNodesArena = MemoryArena()

    // ResourceUsages should hold exactly one strong reference to each resource.
    // It needs at least one to guarantee that the resource lives to the end of the frame.
    @usableFromInline
    var resources = Set<Resource>()
    
    public var allResources : Set<Resource> {
        return self.resources
    }
    
    func reset() {
        self.resources.removeAll(keepingCapacity: true)
        self.usageNodesArena.reset()
    }

    func addReadResources(_ resources: [Resource], `for` renderPass: Unmanaged<RenderPassRecord>) {
        for resource in resources {
            self.registerResource(resource)
            resource.usages.append(ResourceUsage(type: .read, stages: .cpuBeforeRender, inArgumentBuffer: false, firstCommandOffset: 0, renderPass: renderPass), arena: self.usageNodesArena)
        }
    }
    
    func addWrittenResources(_ resources: [Resource], `for` renderPass: Unmanaged<RenderPassRecord>) {
        for resource in resources {
            self.registerResource(resource)
            resource.usages.append(ResourceUsage(type: .write, stages: .cpuBeforeRender, inArgumentBuffer: false, firstCommandOffset: 0, renderPass: renderPass), arena: self.usageNodesArena)
        }
    }
    
    @inlinable
    public func registerResource(_ resource: Resource) {
        self.resources.insert(resource)
    }
    
    /// NOTE: Must be called _before_ the command that uses the resource.
    @inlinable
    public func resourceUsageNode<C : CommandEncoder>(`for` resourceHandle: Resource.Handle, encoder: C, usageType: ResourceUsageType, stages: RenderStages, inArgumentBuffer: Bool, firstCommandOffset: Int) -> ResourceUsageNodePtr {
        
        assert(encoder.renderPass.writtenResources.isEmpty || encoder.renderPass.writtenResources.contains(where: { $0.handle == resourceHandle }) || encoder.renderPass.readResources.contains(where: { $0.handle == resourceHandle }), "Resource \(resourceHandle) used but not declared.")
        
        let resource = Resource(existingHandle: resourceHandle)
        
        let (usagePtr, isNew) = resource.usages.nextNodeWithUsage(type: usageType, stages: stages, inArgumentBuffer: inArgumentBuffer, commandOffset: firstCommandOffset, renderPass: encoder.unmanagedPassRecord, arena: self.usageNodesArena)
        
        // For each resource, is the resource usage different from what is was previously used for?
        if isNew {
            resource.usages.append(usagePtr)
            self.registerResource(resource)
        }
        
        return usagePtr
    }
    
    /// NOTE: Must be called _before_ the command that uses the resource.
    @inlinable
    public func addResourceUsage<C : CommandEncoder, R: ResourceProtocol>(`for` resource: R, commandIndex: Int, encoder: C, usageType: ResourceUsageType, stages: RenderStages, inArgumentBuffer: Bool) {

        assert(encoder.renderPass.writtenResources.isEmpty || encoder.renderPass.writtenResources.contains(where: { $0.handle == resource.handle }) || encoder.renderPass.readResources.contains(where: { $0.handle == resource.handle }), "Resource \(resource) used but not declared.")
        
        
        let usage : ResourceUsage
        let isNew : Bool
        
        if resource.usages.isEmpty {
            usage = ResourceUsage(type: usageType, stages: stages, inArgumentBuffer: inArgumentBuffer, firstCommandOffset: commandIndex, renderPass: encoder.unmanagedPassRecord)
            isNew = true
        } else {
            if let newUsage = resource.usages.last.mergeOrCreateNewUsage(type: usageType, stages: stages, inArgumentBuffer: inArgumentBuffer, firstCommandOffset: commandIndex, renderPass: encoder.unmanagedPassRecord) {
                usage = newUsage
                isNew = true
            } else {
                usage = resource.usages.last
                isNew = false
            }
        }
        
        // For each resource, is the resource usage different from what is was previously used for?
        if isNew {
            resource.usages.append(usage, arena: self.usageNodesArena)
            self.registerResource(Resource(resource))
        }
    }

}
