//
//  Heap.swift
//  
//
//  Created by Thomas Roughton on 2/07/21.
//

import SubstrateUtilities
import Atomics

public struct Heap : ResourceProtocol {
    public let handle: ResourceHandle
    
    public init(handle: Handle) {
        assert(handle.resourceType == .heap)
        self.handle = handle
    }
    
    public init?(size: Int, type: HeapType = .automaticPlacement, storageMode: StorageMode = .managed, cacheMode: CPUCacheMode = .defaultCache) {
        self.init(descriptor: HeapDescriptor(size: size, type: type, storageMode: storageMode, cacheMode: cacheMode))
    }
    
    public init?(descriptor: HeapDescriptor) {
        let flags : ResourceFlags = .persistent
        
        self = HeapRegistry.instance.allocate(descriptor: descriptor, heap: nil, flags: flags)
        
        if !RenderBackend.materialisePersistentResource(self) {
            self.dispose()
            return nil
        }
    }
    
    public var size : Int {
        return self.descriptor.size
    }
    
    public var usedSize: Int {
        return RenderBackend.usedSize(for: self)
    }
    
    public var currentAllocatedSize: Int {
        return RenderBackend.currentAllocatedSize(for: self)
    }
    
    public func maxAvailableSize(forAlignment alignment: Int) -> Int {
        return RenderBackend.maxAvailableSize(forAlignment: alignment, in: self)
    }
    
    public internal(set) var descriptor : HeapDescriptor {
        get {
            return self[\.descriptors]!
        }
        nonmutating set {
            self[\.descriptors] = newValue
        }
    }
    
    public var storageMode: StorageMode {
        return self.descriptor.storageMode
    }
    
    public var cacheMode: CPUCacheMode {
        return self.descriptor.cacheMode
    }
    
    public var heap : Heap? {
        return nil
    }
    
    public var childResources: Set<Resource> {
        _read {
            guard self.isValid else {
                yield []
                return
            }
            
            HeapRegistry.instance.lock.lock()
            yield self.pointer(for: \.childResources)!.pointee
            HeapRegistry.instance.lock.unlock()
        }
        nonmutating _modify {
            guard self.isValid else {
                var resources = Set<Resource>()
                yield &resources
                return
            }
            
            HeapRegistry.instance.lock.lock()
            yield &self.pointer(for: \.childResources)!.pointee
            HeapRegistry.instance.lock.unlock()
        }
    }
    
    public static var resourceType: ResourceType {
        return .heap
    }
    
    
    public func dispose() {
        guard self._usesPersistentRegistry, self.isValid else {
            return
        }
        assert(self.childResources.isEmpty)
        Self.persistentRegistry.dispose(self)
    }
}

extension Heap: CustomStringConvertible {
    public var description: String {
        return "Heap(handle: \(self.handle)) { \(self.label.map { "label: \($0), "} ?? "")descriptor: \(self.descriptor), flags: \(self.flags) }"
    }
}

extension Heap: ResourceProtocolImpl {
    @usableFromInline typealias SharedProperties = EmptyProperties<HeapDescriptor>
    @usableFromInline typealias TransientProperties = EmptyProperties<HeapDescriptor>
    @usableFromInline typealias PersistentProperties = HeapProperties
    
    @usableFromInline static func transientRegistry(index: Int) -> TransientChunkRegistry<Heap>? {
        return nil
    }
    
    @usableFromInline static var persistentRegistry: PersistentRegistry<Self> { HeapRegistry.instance }
    
    @usableFromInline typealias Descriptor = HeapDescriptor
    
    @usableFromInline static var tracksUsages: Bool { true }
}

@usableFromInline
struct HeapProperties: PersistentResourceProperties {
    let descriptors : UnsafeMutablePointer<HeapDescriptor>
    let childResources : UnsafeMutablePointer<Set<Resource>>
    /// The RenderGraphs that are currently using this resource.
    let activeRenderGraphs : UnsafeMutablePointer<UInt8.AtomicRepresentation>
    
    @usableFromInline init(capacity: Int) {
        self.descriptors = .allocate(capacity: capacity)
        self.childResources = .allocate(capacity: capacity)
        self.activeRenderGraphs = .allocate(capacity: capacity)
    }
    
    @usableFromInline func deallocate() {
        self.descriptors.deallocate()
        self.childResources.deallocate()
        self.activeRenderGraphs.deallocate()
    }
    
    @usableFromInline func initialize(index: Int, descriptor: HeapDescriptor, heap: Heap?, flags: ResourceFlags) {
        assert(heap == nil)
        
        self.descriptors.advanced(by: index).initialize(to: descriptor)
        self.childResources.advanced(by: index).initialize(to: [])
        self.activeRenderGraphs.advanced(by: index).initialize(to: UInt8.AtomicRepresentation(0))
    }
    
    @usableFromInline func deinitialize(from index: Int, count: Int) {
        self.descriptors.advanced(by: index).deinitialize(count: count)
        self.childResources.advanced(by: index).deinitialize(count: count)
        self.activeRenderGraphs.advanced(by: index).deinitialize(count: count)
    }
    
    @usableFromInline var readWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndex.AtomicRepresentation>? { nil }
    @usableFromInline var writeWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndex.AtomicRepresentation>? { nil }
    @usableFromInline var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { activeRenderGraphs }
}

final class HeapRegistry: PersistentRegistry<Heap> {
    static let instance = HeapRegistry()
}
