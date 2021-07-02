//
//  Heap.swift
//  
//
//  Created by Thomas Roughton on 2/07/21.
//

import SubstrateUtilities

public struct Heap : ResourceProtocol {
    @usableFromInline let _handle : UnsafeRawPointer
    public var handle : Handle { return UInt64(UInt(bitPattern: _handle)) }
    
    public init(handle: Handle) {
        assert(Resource(handle: handle).type == .heap)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
    }
    
    public init?(size: Int, type: HeapType = .automaticPlacement, storageMode: StorageMode = .managed, cacheMode: CPUCacheMode = .defaultCache) {
        self.init(descriptor: HeapDescriptor(size: size, type: type, storageMode: storageMode, cacheMode: cacheMode))
    }
    
    public init?(descriptor: HeapDescriptor) {
        let flags : ResourceFlags = .persistent
        
        self = HeapRegistry.instance.allocate(descriptor: descriptor, heap: nil, flags: flags)
        
        if !RenderBackend.materialiseHeap(self) {
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
        return self
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
}

extension Heap: CustomStringConvertible {
    public var description: String {
        return "Heap(handle: \(self.handle)) { \(self.label.map { "label: \($0), "} ?? "")descriptor: \(self.descriptor), flags: \(self.flags) }"
    }
}

extension Heap: ResourceProtocolImpl {
    typealias SharedProperties = EmptyProperties<HeapDescriptor>
    typealias TransientProperties = EmptyProperties<HeapDescriptor>
    typealias PersistentProperties = HeapProperties
    
    static func transientRegistry(index: Int) -> TransientChunkRegistry<Heap>? {
        return nil
    }
    
    static var persistentRegistry: PersistentRegistry<Self> { HeapRegistry.instance }
    
    typealias Descriptor = HeapDescriptor
}

@usableFromInline
struct HeapProperties: PersistentResourceProperties {
    let descriptors : UnsafeMutablePointer<HeapDescriptor>
    let childResources : UnsafeMutablePointer<Set<Resource>>
    /// The RenderGraphs that are currently using this resource.
    let activeRenderGraphs : UnsafeMutablePointer<UInt8.AtomicRepresentation>
    
    init(capacity: Int) {
        self.descriptors = .allocate(capacity: capacity)
        self.childResources = .allocate(capacity: capacity)
        self.activeRenderGraphs = .allocate(capacity: capacity)
    }
    
    func deallocate() {
        self.descriptors.deallocate()
        self.childResources.deallocate()
        self.activeRenderGraphs.deallocate()
    }
    
    func initialize(index: Int, descriptor: HeapDescriptor, heap: Heap?, flags: ResourceFlags) {
        self.descriptors.advanced(by: index).initialize(to: descriptor)
        self.childResources.advanced(by: index).initialize(to: [])
        self.activeRenderGraphs.advanced(by: index).initialize(to: UInt8.AtomicRepresentation(0))
    }
    
    func deinitialize(from index: Int, count: Int) {
        self.descriptors.advanced(by: index).deinitialize(count: count)
        self.childResources.advanced(by: index).deinitialize(count: count)
        self.activeRenderGraphs.deinitialize(count: count)
    }
    
    var usagesOptional: UnsafeMutablePointer<ChunkArray<ResourceUsage>>? { nil }
    
    var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { nil }
}

final class HeapRegistry: PersistentRegistry<Heap> {
    static let instance = HeapRegistry()
}
