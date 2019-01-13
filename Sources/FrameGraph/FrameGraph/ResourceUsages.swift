//
//  ResourceUsages.swift
//  FrameGraph
//
//  Created by Joseph Bennett on 20/12/17.
//

import Utilities
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

@_fixed_layout
public struct LinkedNode<T> {
    public var next: UnsafeMutablePointer<LinkedNode>?
    public var sortIndex : Int
    public var element: T
    
    @inlinable
    public init(value: T, sortIndex: Int) {
        self.element = value
        self.sortIndex = sortIndex
    }
}

public typealias ResourceUsageNodePtr = UnsafeMutablePointer<LinkedNode<ResourceUsage>>

extension UnsafeMutablePointer where Pointee == LinkedNode<ResourceUsage> {
    @inlinable
    var asNextPointer : UnsafeMutablePointer<UnsafeMutablePointer<LinkedNode<ResourceUsage>>?> {
        return UnsafeMutableRawPointer(self).assumingMemoryBound(to: UnsafeMutablePointer<LinkedNode<ResourceUsage>>?.self)
    }
}

// Note: must be bitwise identical to LinkedNode<ResourceUsage>
@_fixed_layout
public struct ResourceUsagesList : Sequence {
    @usableFromInline
    var head : ResourceUsageNodePtr? = nil
    var sortIndex : Int = -1
    var dummyUsage = ResourceUsage(type: .unusedArgumentBuffer, stages: [], inArgumentBuffer: false, firstCommandOffset: 0, renderPass: Unmanaged<RenderPassRecord>.fromOpaque(UnsafeRawPointer(bitPattern: 1)!))
    
    @inlinable
    public init() {
        
    }
    
    @inlinable
    public static func createNode(usage: ResourceUsage, arena: MemoryArena) -> ResourceUsageNodePtr {
        let node = arena.allocate() as ResourceUsageNodePtr
        node.initialize(to: LinkedNode(value: usage, sortIndex: usage.renderPassRecord.passIndex))
        return node
    }
    
    // This doesn't need any special synchronisation since nodes can only be merged within a render pass.
    @inlinable
    public func nextNodeWithUsage(type: ResourceUsageType, stages: RenderStages, inArgumentBuffer: Bool, commandOffset: Int, renderPass: Unmanaged<RenderPassRecord>, arena: MemoryArena) -> (ResourceUsageNodePtr, isNew: Bool) {
        let passIndex = renderPass.takeUnretainedValue().passIndex
        if let tail = self.findNode(passIndex: passIndex), tail.pointee.sortIndex == passIndex {
            assert(tail.pointee.element._renderPass.toOpaque() == renderPass.toOpaque())
            if let newUsage = tail.pointee.element.mergeOrCreateNewUsage(type: type, stages: stages, inArgumentBuffer: inArgumentBuffer, firstCommandOffset: commandOffset, renderPass: renderPass) {
                assert(renderPass.toOpaque() != tail.pointee.element._renderPass.toOpaque() || commandOffset >= tail.pointee.element.commandRangeInPass.lowerBound, "Adding a new usage which starts before the previous usage has ended.")
                let node = ResourceUsagesList.createNode(usage: newUsage, arena: arena)
                return (node, true)
            } else {
                return (tail, false)
            }
        }
        return (ResourceUsagesList.createNode(usage: ResourceUsage(type: type, stages: stages, inArgumentBuffer: inArgumentBuffer, firstCommandOffset: commandOffset, renderPass: renderPass), arena: arena), true)
    }
    
    public func findNode(passIndex: Int) -> ResourceUsageNodePtr? {
        // Find the last node for which the pass index is > passIndex
        // We need to return the pointer to the node for which we need to set the next pointer on.
        
        var node = self.head
        while let curNode = node, curNode.pointee.sortIndex > passIndex {
            node = curNode.pointee.next
        }
        
        return node
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
    public var firstActiveUsage : ResourceUsage? {
        for usage in self {
            if usage.renderPassRecord.isActive, usage.type != .unusedRenderTarget, usage.type != .unusedArgumentBuffer {
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

extension UnsafeMutablePointer where Pointee == ResourceUsagesList {
    
    @inlinable
    func append(_ usage: ResourceUsage, arena: MemoryArena) {
        let node = ResourceUsagesList.createNode(usage: usage, arena: arena)
        self.append(node)
    }
    
    @inlinable
    func withInsertionNode<T>(passIndex: Int, perform: (ResourceUsageNodePtr) -> T) -> T {
        // Find the last node for which the pass index is > passIndex
        // We need to return the pointer to the node for which we need to set the next pointer on.
        return self.withMemoryRebound(to: LinkedNode<ResourceUsage>.self, capacity: 1) { node -> T in
            var node = node
            while let curNode = node.pointee.next, curNode.pointee.sortIndex > passIndex {
                node = curNode
            }
            
            return perform(node)
        }
    }
    
     @inlinable
     func append(_ usageNode: ResourceUsageNodePtr) {
        let passIndex = usageNode.pointee.element.renderPassRecord.passIndex
        self.withInsertionNode(passIndex: passIndex, perform: { insertionNode in
            var insertionNode = insertionNode
            
            var success = false
            
            repeat {
                if let nextNode = insertionNode.pointee.next, nextNode.pointee.sortIndex > usageNode.pointee.sortIndex {
                    insertionNode = nextNode
                    continue
                }
                
                usageNode.asNextPointer.pointee = insertionNode.asNextPointer.pointee
                
                if let nextNode = usageNode.asNextPointer.pointee, nextNode.pointee.sortIndex > usageNode.pointee.sortIndex {
                    continue
                }
                
                success = LinkedNodeHeaderCompareAndSwap(
                    UnsafeMutableRawPointer(insertionNode).assumingMemoryBound(to: LinkedNodeHeader.self),
                                               UnsafeMutableRawPointer(usageNode).assumingMemoryBound(to: LinkedNodeHeader.self)
                )
                
            } while !success
        })
    }
    
    func reverse() {
        var currNode = self.pointee.head
        var prevNode : ResourceUsageNodePtr? = nil
        
        while currNode != nil {
            let nextNode = currNode?.pointee.next
            currNode?.pointee.next = prevNode
            prevNode = currNode;
            currNode = nextNode
        }
        
        self.pointee.head = prevNode
    }
}

extension ResourceUsageType {
    @inlinable
    public var isRead : Bool {
        switch self {
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
        switch self {
        case .write, .readWrite, .readWriteRenderTarget, .writeOnlyRenderTarget, .inputAttachmentRenderTarget, .blitDestination, .blitSynchronisation:
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
    public var renderPassRecord : RenderPassRecord {
        return _renderPass.takeUnretainedValue()
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
    public var commandRange : Range<Int> {
        let startIndex = renderPassRecord.commandRange!.lowerBound
        return (self.commandRangeInPass.lowerBound + startIndex)..<(self.commandRangeInPass.upperBound + startIndex)
    }
    
    /// - returns: The new usage, if the usage couldn't be merged with self.
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
        
        readWriteMergeCheck: if self.commandRangeInPass.contains(firstCommandOffset), stages == self.stages, self.type != type {
            assert(self._renderPass.toOpaque() == renderPass.toOpaque())
            assert(self.inArgumentBuffer == inArgumentBuffer)
            
            switch (type, self.type) {
            case (.read, .readWrite), (.write, .write), (.write, .readWrite):
                break
            case (.read, .write), (.readWrite, .read), (.write, .read):
                self.type = .readWrite
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
            self._renderPass.toOpaque() == renderPass.toOpaque() &&
            self.inArgumentBuffer == inArgumentBuffer {
            self.stages.formUnion(stages)
            self.commandRangeInPass = Range(uncheckedBounds: (self.commandRangeInPass.lowerBound, firstCommandOffset + 1))
            return nil
        }
        
        return ResourceUsage(type: type, stages: stages, inArgumentBuffer: inArgumentBuffer, firstCommandOffset: firstCommandOffset, renderPass: renderPass)
        
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

@_fixed_layout
public class ResourceUsages {
    
    @usableFromInline
    let usageNodesArena = MemoryArena()
    
    // ResourceUsages should hold exactly one strong reference to each resource.
    // It needs at least one to guarantee that the resource lives to the end of the frame.
    @usableFromInline
    var resources = Set<Resource>()
    
    
    @inlinable
    init() {
        
    }
    
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
            resource.usagesPointer.append(ResourceUsage(type: .read, stages: .cpuBeforeRender, inArgumentBuffer: false, firstCommandOffset: 0, renderPass: renderPass), arena: self.usageNodesArena)
        }
    }
    
    func addWrittenResources(_ resources: [Resource], `for` renderPass: Unmanaged<RenderPassRecord>) {
        for resource in resources {
            self.registerResource(resource)
            resource.usagesPointer.append(ResourceUsage(type: .write, stages: .cpuBeforeRender, inArgumentBuffer: false, firstCommandOffset: 0, renderPass: renderPass), arena: self.usageNodesArena)
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
            resource.usagesPointer.append(usagePtr)
            self.registerResource(resource)
        }

        assert(usagePtr.pointee.element.renderPassRecord === encoder.passRecord)
        
        return usagePtr
    }
    
    /// NOTE: Must be called _before_ the command that uses the resource.
    @inlinable
    public func addResourceUsage<C : CommandEncoder, R: ResourceProtocol>(`for` resource: R, commandIndex: Int, encoder: C, usageType: ResourceUsageType, stages: RenderStages, inArgumentBuffer: Bool) {
        
        let _ = self.resourceUsageNode(for: resource.handle, encoder: encoder, usageType: usageType, stages: stages, inArgumentBuffer: inArgumentBuffer, firstCommandOffset: commandIndex)
    }
    
}
