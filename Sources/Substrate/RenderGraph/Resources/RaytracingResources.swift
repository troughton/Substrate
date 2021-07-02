//
//  RaytracingResources.swift
//  
//
//  Created by Thomas Roughton on 2/07/21.
//

import SubstrateUtilities

// MARK: - AccelerationStructure

public struct AccelerationStructure : ResourceProtocol {

    @usableFromInline let _handle : UnsafeRawPointer
    @inlinable public var handle : Handle { return UInt64(UInt(bitPattern: _handle)) }
    
    public init(handle: Handle) {
        assert(Resource(handle: handle).type == .accelerationStructure)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public init(size: Int) {
        let flags : ResourceFlags = .persistent
        
        self = AccelerationStructureRegistry.instance.allocate(descriptor: size, heap: nil, flags: flags)
        
        // vkCreateAccelerationStructureKHR
        if !RenderBackend.materialiseAccelerationStructure(self) {
            assertionFailure("Allocation failed for persistent texture \(self)")
            self.dispose()
        }
    }
    
    public var size : Int {
        get {
            return self[\.sizes]
        }
    }
    
    public internal(set) var descriptor : AccelerationStructureDescriptor? {
        get {
            self[\.descriptors]
        }
        nonmutating set {
            self[\.descriptors] = newValue
        }
    }
    
    public subscript(waitIndexFor queue: Queue, accessType type: ResourceAccessType) -> UInt64 {
        get {
            if type == .read {
                return self[\.readWaitIndices]?[Int(queue.index)] ?? 0
            } else {
                return self[\.writeWaitIndices]?[Int(queue.index)] ?? 0
            }
        }
        nonmutating set {
            guard self._usesPersistentRegistry else { return }
            if type == .read || type == .readWrite {
                self[\.readWaitIndices]![Int(queue.index)] = newValue
            }
            if type == .write || type == .readWrite {
                self[\.writeWaitIndices]![Int(queue.index)] = newValue
            }
        }
    }
    
    public var storageMode: StorageMode {
        return .private
    }
    
    public static var resourceType: ResourceType { .accelerationStructure }
}

extension AccelerationStructure: ResourceProtocolImpl {
    typealias SharedProperties = AccelerationStructureProperties
    typealias TransientProperties = EmptyProperties<Int>
    typealias PersistentProperties = AccelerationStructureProperties.PersistentProperties
    
    static func transientRegistry(index: Int) -> TransientChunkRegistry<AccelerationStructure>? {
        return nil
    }
    
    static var persistentRegistry: PersistentRegistry<Self> { AccelerationStructureRegistry.instance }
    
    typealias Descriptor = Int // size
}

extension AccelerationStructure: CustomStringConvertible {
    public var description: String {
        return "AccelerationStructure(handle: \(self.handle)) { \(self.label.map { "label: \($0), "} ?? "")size: \(self.size) }"
    }
}

struct AccelerationStructureProperties: SharedResourceProperties {
    struct PersistentProperties: PersistentResourceProperties {
        
        /// The index that must be completed on the GPU for each queue before the CPU can read from this resource's memory.
        let readWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The index that must be completed on the GPU for each queue before the CPU can write to this resource's memory.
        let writeWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The RenderGraphs that are currently using this resource.
        let activeRenderGraphs : UnsafeMutablePointer<UInt8.AtomicRepresentation>
        
        init(capacity: Int) {
            self.readWaitIndices = .allocate(capacity: capacity)
            self.writeWaitIndices = .allocate(capacity: capacity)
            self.activeRenderGraphs = .allocate(capacity: capacity)
        }
        
        func deallocate() {
            self.readWaitIndices.deallocate()
            self.writeWaitIndices.deallocate()
            self.activeRenderGraphs.deallocate()
        }
        
        func initialize(index: Int, descriptor size: Int, heap: Heap?, flags: ResourceFlags) {
            self.readWaitIndices.advanced(by: index).initialize(to: SIMD8(repeating: 0))
            self.writeWaitIndices.advanced(by: index).initialize(to: SIMD8(repeating: 0))
            self.activeRenderGraphs.advanced(by: index).initialize(to: UInt8.AtomicRepresentation(0))
        }
        
        func deinitialize(from index: Int, count: Int) {
            self.readWaitIndices.advanced(by: index).deinitialize(count: count)
            self.writeWaitIndices.advanced(by: index).deinitialize(count: count)
            self.activeRenderGraphs.advanced(by: index).deinitialize(count: count)
        }
        
        var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { activeRenderGraphs }
    }
    
    let sizes : UnsafeMutablePointer<Int>
    let usages : UnsafeMutablePointer<ChunkArray<ResourceUsage>>
    let descriptors : UnsafeMutablePointer<AccelerationStructureDescriptor?>
    
    init(capacity: Int) {
        self.sizes = .allocate(capacity: capacity)
        self.usages = .allocate(capacity: capacity)
        self.descriptors = .allocate(capacity: capacity)
    }
    
    func deallocate() {
        self.sizes.deallocate()
        self.usages.deallocate()
        self.descriptors.deallocate()
    }
    
    func initialize(index: Int, descriptor size: Int, heap: Heap?, flags: ResourceFlags) {
        self.sizes.advanced(by: index).initialize(to: size)
        self.usages.advanced(by: index).initialize(to: ChunkArray())
        self.descriptors.advanced(by: index).initialize(to: nil)
    }
    
    func deinitialize(from index: Int, count: Int) {
        self.sizes.advanced(by: index).deinitialize(count: count)
        self.usages.advanced(by: index).deinitialize(count: count)
        self.descriptors.advanced(by: index).deinitialize(count: count)
    }
    
    var usagesOptional: UnsafeMutablePointer<ChunkArray<ResourceUsage>>? { usages }
}

final class AccelerationStructureRegistry: PersistentRegistry<AccelerationStructure> {
    static let instance = AccelerationStructureRegistry()
}
