//
//  ResourceUsages.swift
//  FrameGraph
//
//  Created by Joseph Bennett on 20/12/17.
//

import RenderAPI
import Utilities

// This 'PerformOrder' type is necessary to make sure the command goes to the right Command Encoder
public enum PerformOrder : Comparable {
    case before // Before the command index
    case after // After the command index
    
    public static func <(lhs: PerformOrder, rhs: PerformOrder) -> Bool {
        return lhs == .before && rhs == .after
    }
}

struct LinkedNode<T> {
    public var element: T
    var next: UnsafeMutablePointer<LinkedNode>?
    
    public init(value: T) {
        self.element = value
    }
}

typealias ResourceUsageNodePtr = UnsafeMutablePointer<LinkedNode<ResourceUsage>>

public struct ResourceUsagesList : Sequence {
    private let arena : Unmanaged<MemoryArena>
    
    private var head : ResourceUsageNodePtr? = nil
    private var tail : ResourceUsageNodePtr? = nil
    
    public private(set) var count = 0
    
    public init(arena: MemoryArena) {
        self.arena = Unmanaged.passUnretained(arena)
    }
    
    public mutating func append(_ usage: ResourceUsage) {
        let node = self.createNode(usage: usage)
        self.append(node)
    }
    
    func createNode(usage: ResourceUsage) -> ResourceUsageNodePtr {
        let node = arena.takeUnretainedValue().allocate() as ResourceUsageNodePtr
        node.initialize(to: LinkedNode(value: usage))
        return node
    }
    
    mutating func append(_ usageNode: ResourceUsageNodePtr) {
        if let currentTail = self.tail {
            currentTail.pointee.next = usageNode
            self.tail = usageNode
        } else {
            self.head = usageNode
            self.tail = usageNode
        }
        
        self.count += 1
    }
    
    mutating func nextNodeWithUsage(type: ResourceUsageType, stages: RenderStages, inArgumentBuffer: Bool, commandOffset: Int, renderPass: RenderPassRecord) -> (ResourceUsageNodePtr, isNew: Bool) {
        if let tail = self.tail {
            if let newUsage = self.last.mergeOrCreateNewUsage(type: type, stages: stages, inArgumentBuffer: inArgumentBuffer, firstCommandOffset: commandOffset, renderPass: renderPass) {
                assert(renderPass !== tail.pointee.element.renderPass || commandOffset >= tail.pointee.element.commandRangeInPass.lowerBound, "Adding a new usage which starts before the previous usage has ended.")
                let node = self.createNode(usage: newUsage)
                return (node, true)
            } else {
                return (tail, false)
            }
        }
        return (self.createNode(usage: ResourceUsage(type: type, stages: stages, inArgumentBuffer: inArgumentBuffer, firstCommandOffset: commandOffset, renderPass: renderPass)), true)
    }

    public var first : ResourceUsage {
        get {
            return self.head!.pointee.element
        }
        set {
            self.head!.pointee.element = newValue
        }
    }
    
    public var last : ResourceUsage {
        get {
            return self.tail!.pointee.element
        }
        set {
            self.tail!.pointee.element = newValue
        }
    }

    public var firstActiveUsage : ResourceUsage? {
        for usage in self {
            if usage.renderPass.isActive {
                return usage
            }
        }
        return nil
    }
    
    public var isEmpty : Bool {
        return self.head == nil
    }
    
    public struct Iterator : IteratorProtocol {
        public typealias Element = ResourceUsage
        
        var nextNode : ResourceUsageNodePtr?
        
        public mutating func next() -> ResourceUsage? {
            if let node = nextNode {
                let element = node.pointee.element
                nextNode = node.pointee.next
                return element
            }
            return nil
        }
    }
    
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
    private var _renderPass : Unmanaged<RenderPassRecord>
    var commandRangeInPass : Range<Int>
    
    public init(type: ResourceUsageType, stages: RenderStages, inArgumentBuffer: Bool, firstCommandOffset: Int, renderPass: RenderPassRecord) {
        self.type = type
        self.stages = stages
        self._renderPass = Unmanaged.passUnretained(renderPass)
        self.commandRangeInPass = Range(firstCommandOffset...firstCommandOffset)
        self.inArgumentBuffer = inArgumentBuffer
    }
    
    public var renderPass : RenderPassRecord {
        return _renderPass.takeUnretainedValue()
    }
    
    public var isRead : Bool {
        switch self.type {
        case .read, .readWrite, .blitSource, .blitSynchronisation, 
             .vertexBuffer, .indexBuffer, .indirectBuffer, .readWriteRenderTarget,
             .inputAttachment, .constantBuffer: 
            return true
        default:
            return false
        }
    }
    
    public var isWrite : Bool {
        switch self.type {
        case .write, .readWrite, .readWriteRenderTarget, .writeOnlyRenderTarget, .blitDestination, .blitSynchronisation:
            return true
        default:
            return false
        }
    }
    
    public var commandRange : Range<Int> {
        let startIndex = renderPass.commandRange!.lowerBound
        return (self.commandRangeInPass.lowerBound + startIndex)..<(self.commandRangeInPass.upperBound + startIndex)
    }
    
    mutating func mergeOrCreateNewUsage(type: ResourceUsageType, stages: RenderStages, inArgumentBuffer: Bool, firstCommandOffset: Int, renderPass: RenderPassRecord) -> ResourceUsage? {
        if self.type == type &&
            self.renderPass === renderPass &&
            self.inArgumentBuffer == inArgumentBuffer {
            self.stages.formUnion(stages)
            self.commandRangeInPass = Range(self.commandRangeInPass.lowerBound...firstCommandOffset)
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

public class ResourceUsages {
    
    let usageNodesArena = MemoryArena()
    var usages : [ObjectIdentifier : ResourceUsagesList] = [:]
    
    private var readResources : [ObjectIdentifier : Set<ObjectIdentifier>]  = [:]
    private var writtenResources : [ObjectIdentifier : Set<ObjectIdentifier>]  = [:]

    // ResourceUsages should hold exactly one strong reference to each resource.
    // It needs at least one to guarantee that the resource lives to the end of the frame.
    var resources : [ObjectIdentifier : Resource] = [:]
    
    public var allResources : AnyCollection<Resource> {
        return AnyCollection(self.resources.values)
    }
    
    func reset() {
        self.resources.removeAll(keepingCapacity: true)
        self.readResources.removeAll(keepingCapacity: true)
        self.writtenResources.removeAll(keepingCapacity: true)
        self.usages.removeAll(keepingCapacity: true)
        self.usageNodesArena.reset()
    }
    
    public subscript(resource: ObjectIdentifier) -> Resource? {
        return self.resources[resource]
    }
    
    public subscript(usagesFor resource: ObjectIdentifier) -> ResourceUsagesList {
        get {
            return self.usages[resource, default: ResourceUsagesList(arena: self.usageNodesArena)]
        }
        
        set {
            self.usages[resource] = newValue
        }
    }
    
    public subscript(usagesFor resource: Resource) -> ResourceUsagesList {
        get {
            return self[usagesFor: ObjectIdentifier(resource)]
        }
        
        set {
            self[usagesFor: ObjectIdentifier(resource)] = newValue
        }
    }
    
    public func readResources(`for` renderPass : RenderPass) -> Set<ObjectIdentifier> {
        return readResources[ObjectIdentifier(renderPass), default: []]
    }
    
    public func writtenResources(`for` renderPass : RenderPass) -> Set<ObjectIdentifier> {
        return writtenResources[ObjectIdentifier(renderPass), default: []]
    }
    
    func addReadResources(_ resources: [Resource], `for` renderPass: RenderPass) {
        
        for resource in resources {
            readResources[ObjectIdentifier(renderPass), default: []].insert(ObjectIdentifier(resource))

        }
    }
    
    func addWrittenResources(_ resources: [Resource], `for` renderPass: RenderPass) {
        
        for resource in resources {
            writtenResources[ObjectIdentifier(renderPass), default: []].insert(ObjectIdentifier(resource))
        }
    }
    
    func registerResource(_ resource: Resource) {
        self.resources[resource.handle] = resource
    }
    
    /// NOTE: Must be called _before_ the command that uses the resource.
    func resourceUsageNode<C : CommandEncoder>(`for` resource: ObjectIdentifier, encoder: C, usageType: ResourceUsageType, stages: RenderStages, inArgumentBuffer: Bool, firstCommandOffset: Int) -> ResourceUsageNodePtr {
        
        assert(encoder.renderPass.writtenResources.isEmpty || encoder.renderPass.writtenResources.contains(where: { ObjectIdentifier($0) == resource }) || encoder.renderPass.readResources.contains(where: { ObjectIdentifier($0) == resource }), "Resource \(resource) used but not declared.")
        
        let (usagePtr, isNew) = self[usagesFor: resource].nextNodeWithUsage(type: usageType, stages: stages, inArgumentBuffer: inArgumentBuffer, commandOffset: firstCommandOffset, renderPass: encoder.passRecord)
        
        // For each resource, is the resource usage different from what is was previously used for?
        if isNew {
            self[usagesFor: resource].append(usagePtr)
            
            if usagePtr.pointee.element.isRead {
                self.readResources[ObjectIdentifier(encoder.renderPass), default: []].insert(resource)
            }
            
            if usagePtr.pointee.element.isWrite {
                self.writtenResources[ObjectIdentifier(encoder.renderPass), default: []].insert(resource)
            }
            assert(usagePtr.pointee.element.type == .argumentBufferUnused || usagePtr.pointee.element.isRead || usagePtr.pointee.element.isWrite)
        }
        
        return usagePtr
    }
    
    /// NOTE: Must be called _before_ the command that uses the resource.
    func addResourceUsage<C : CommandEncoder>(`for` resource: Resource, commandIndex: Int, encoder: C, usageType: ResourceUsageType, stages: RenderStages, inArgumentBuffer: Bool) {
        
        assert(encoder.renderPass.writtenResources.isEmpty || encoder.renderPass.writtenResources.contains(resource) || encoder.renderPass.readResources.contains(resource), "Resource \(resource) used but not declared.")
        
        let resourceIdentifier = resource.handle
        
        let usage : ResourceUsage
        let isNew : Bool
        if self[usagesFor: resource].isEmpty {
            usage = ResourceUsage(type: usageType, stages: stages, inArgumentBuffer: inArgumentBuffer, firstCommandOffset: commandIndex, renderPass: encoder.passRecord)
            isNew = true
        } else {
            if let newUsage = self[usagesFor: resource].last.mergeOrCreateNewUsage(type: usageType, stages: stages, inArgumentBuffer: inArgumentBuffer, firstCommandOffset: commandIndex, renderPass: encoder.passRecord) {
                usage = newUsage
                isNew = true
            } else {
                usage = self[usagesFor: resource].last
                isNew = false
            }
        }
        
        // For each resource, is the resource usage different from what is was previously used for?
        if isNew {
            self[usagesFor: resource].append(usage)
            self.resources[resourceIdentifier] = resource
            
            if usage.isRead {
                self.readResources[ObjectIdentifier(encoder.renderPass), default: []].insert(ObjectIdentifier(resource))
            }
            
            if usage.isWrite {
                self.writtenResources[ObjectIdentifier(encoder.renderPass), default: []].insert(ObjectIdentifier(resource))
            }
            assert(usage.type == .argumentBufferUnused || usage.isRead || usage.isWrite)
        }
    }

}
