//
//  HazardTrackingGroup.swift
//  
//
//  Created by Thomas Roughton on 5/07/21.
//

import Foundation
import SubstrateUtilities

@usableFromInline struct _HazardTrackingGroup: ResourceProtocol {
    // Idea is: you assign a hazard tracking group to a resource, and then all ResourceUsages are shared for resources within that group, meaning you only track the group and not the (potentially thousands) of individual resources.
    // Argument buffers will need to keep a list of their tracked subresources (namely, hazard tracking groups for resources with one assigned and individual resources for ones without).
    // That will work for the resource command generator/pass dependency tracking, but optimising ResourceBindingEncoder.updateResourceUsages(endingEncoding:) will be more difficult
    
    @usableFromInline let _handle : UnsafeRawPointer
    @inlinable public var handle : Handle { return UInt64(UInt(bitPattern: _handle)) }
    
    public init(handle: Handle) {
        assert(Resource(handle: handle).type == .hazardTrackingGroup)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
    }
    
    public init(resourceType: ResourceType) {
        let flags : ResourceFlags = .persistent
        
        self = HazardTrackingGroupRegistry.instance.allocate(descriptor: resourceType, heap: nil, flags: flags)
    }
    
    public var resourceType: ResourceType {
        return self[\.resourceTypes]
    }
    
    public var storageMode: StorageMode {
        return .shared
    }
    
    public var heap : Heap? {
        return nil
    }
    
    func resourcesPointer<R: ResourceProtocol & Hashable>(ofType type: R.Type) -> UnsafeMutablePointer<Set<R>> {
        return UnsafeMutableRawPointer(self.pointer(for: \.resources)).assumingMemoryBound(to: Set<R>.self)
    }
    
    public static var resourceType: ResourceType {
        return .hazardTrackingGroup
    }
}

public struct HazardTrackingGroup<R: ResourceProtocol> {
    @usableFromInline let group: _HazardTrackingGroup
    
    public init() {
        self.group = .init(resourceType: R.resourceType)
    }
    
    init?(_ resource: Resource) {
        guard resource.type == .hazardTrackingGroup else { return nil }
        let group = _HazardTrackingGroup(handle: resource.handle)
        guard group.resourceType == R.resourceType else { return nil }
        self.group = group
    }
    
    public func dispose() {
        self.group.dispose()
    }
    
    public var label: String? {
        get {
            return self.group.label
        }
        set {
            self.group.label = newValue
        }
    }
    
    public var usages: ChunkArray<RecordedResourceUsage> {
        get {
            return self.group.usages
        }
        set {
            self.group.usages = newValue
        }
    }
    
    public var isValid: Bool {
        return self.group.isValid
    }
}

extension HazardTrackingGroup where R: Hashable {
    public var resources: Set<R> {
        _read {
            HazardTrackingGroupRegistry.instance.lock.lock()
            yield self.group.resourcesPointer(ofType: R.self).pointee
            HazardTrackingGroupRegistry.instance.lock.unlock()
        }
        nonmutating _modify {
            guard self.isValid else {
                var resources = Set<R>()
                yield &resources
                return
            }
            
            HazardTrackingGroupRegistry.instance.lock.lock()
            yield &UnsafeMutableRawPointer(self.group.pointer(for: \.resources)).assumingMemoryBound(to: Set<R>.self).pointee
            HazardTrackingGroupRegistry.instance.lock.unlock()
        }
    }
}

extension HazardTrackingGroup: CustomStringConvertible where R: Hashable {
    public var description: String {
        return "HazardTrackingGroup(\(self.label.map { "label: \($0), "} ?? "")resources: \(self.resources) }"
    }
}

extension _HazardTrackingGroup: ResourceProtocolImpl {
    @usableFromInline typealias SharedProperties = HazardTrackingGroupProperties
    @usableFromInline typealias TransientProperties = EmptyProperties<ResourceType>
    @usableFromInline typealias PersistentProperties = HazardTrackingGroupProperties.PersistentProperties
    
    @usableFromInline static func transientRegistry(index: Int) -> TransientChunkRegistry<Self>? {
        return nil
    }
    
    @usableFromInline static var persistentRegistry: PersistentRegistry<Self> { HazardTrackingGroupRegistry.instance }
    
    @usableFromInline typealias Descriptor = ResourceType
}

@usableFromInline
struct HazardTrackingGroupProperties: SharedResourceProperties {
    @usableFromInline struct PersistentProperties: PersistentResourceProperties {
        /// The RenderGraphs that are currently using this resource.
        let activeRenderGraphs : UnsafeMutablePointer<UInt8.AtomicRepresentation>
        /// The index that must be completed on the GPU for each queue before the CPU can read from this resource's memory.
        let readWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The index that must be completed on the GPU for each queue before the CPU can write to this resource's memory.
        let writeWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        
        @usableFromInline init(capacity: Int) {
            self.activeRenderGraphs = .allocate(capacity: capacity)
            self.readWaitIndices = .allocate(capacity: capacity)
            self.writeWaitIndices = .allocate(capacity: capacity)
        }
        
        @usableFromInline func deallocate() {
            self.activeRenderGraphs.deallocate()
            self.readWaitIndices.deallocate()
            self.writeWaitIndices.deallocate()
        }
        
        @usableFromInline func initialize(index: Int, descriptor: ResourceType, heap: Heap?, flags: ResourceFlags) {
            self.activeRenderGraphs.advanced(by: index).initialize(to: UInt8.AtomicRepresentation(0))
            self.readWaitIndices.advanced(by: index).initialize(to: .zero)
            self.writeWaitIndices.advanced(by: index).initialize(to: .zero)
        }
        
        @usableFromInline func deinitialize(from index: Int, count: Int) {
            self.activeRenderGraphs.advanced(by: index).deinitialize(count: count)
            self.readWaitIndices.advanced(by: index).deinitialize(count: count)
            self.writeWaitIndices.advanced(by: index).deinitialize(count: count)
        }
        
        @usableFromInline var readWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { self.readWaitIndices }
        @usableFromInline var writeWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { self.writeWaitIndices }
        @usableFromInline var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { self.activeRenderGraphs }
    }
        
    
    let resourceTypes : UnsafeMutablePointer<ResourceType>
    let resources : UnsafeMutablePointer<Set<Resource>>
    let usages : UnsafeMutablePointer<ChunkArray<RecordedResourceUsage>>
    
    @usableFromInline init(capacity: Int) {
        self.resourceTypes = .allocate(capacity: capacity)
        self.resources = .allocate(capacity: capacity)
        self.usages = .allocate(capacity: capacity)
    }
    
    @usableFromInline func deallocate() {
        self.resourceTypes.deallocate()
        self.resources.deallocate()
        self.usages.deallocate()
    }
    
    @usableFromInline func initialize(index: Int, descriptor: ResourceType, heap: Heap?, flags: ResourceFlags) {
        self.resourceTypes.advanced(by: index).initialize(to: descriptor)
        self.resources.advanced(by: index).initialize(to: [])
        self.usages.advanced(by: index).initialize(to: ChunkArray())
    }
    
    @usableFromInline func deinitialize(from index: Int, count: Int) {
        self.resourceTypes.advanced(by: index).deinitialize(count: count)
        self.resources.advanced(by: index).deinitialize(count: count)
        self.usages.deinitialize(count: count)
    }
    
    @usableFromInline var usagesOptional: UnsafeMutablePointer<ChunkArray<RecordedResourceUsage>>? { self.usages }
}

@usableFromInline final class HazardTrackingGroupRegistry: PersistentRegistry<_HazardTrackingGroup> {
    @usableFromInline static let instance = HazardTrackingGroupRegistry()
}
