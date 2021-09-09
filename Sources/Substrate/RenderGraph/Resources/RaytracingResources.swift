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
        
        var readWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { self.readWaitIndices }
        var writeWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { self.writeWaitIndices }
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


// MARK: - VisibleFunctionTable

public struct VisibleFunctionTable : ResourceProtocol {

    @usableFromInline let _handle : UnsafeRawPointer
    @inlinable public var handle : Handle { return UInt64(UInt(bitPattern: _handle)) }
    
    public init(handle: Handle) {
        assert(Resource(handle: handle).type == .visibleFunctionTable)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public init(functionCount: Int) {
        let flags : ResourceFlags = .persistent
        
        self = VisibleFunctionTableRegistry.instance.allocate(descriptor: functionCount, heap: nil, flags: flags)
    }
   
    public var stateFlags: ResourceStateFlags {
        get {
            return self[\.stateFlags] ?? []
        }
        nonmutating set {
            self[\.stateFlags] = newValue
        }
    }
    
    public var functions: [FunctionDescriptor?] {
        _read {
            yield self.pointer(for: \.functions).pointee
        }
        _modify {
            let previousHash = self.functions.hashValue
            yield &self.pointer(for: \.functions).pointee
            if self.functions.hashValue != previousHash {
                self.stateFlags.remove(.initialised)
            }
        }
    }
    
    public var pipelineState : UnsafeRawPointer? {
        get {
            return UnsafeRawPointer.AtomicOptionalRepresentation.atomicLoad(at: self.pointer(for: \.pipelineStates), ordering: .relaxed)
        }
    }
    
    /// Allows us to perform a compare-and-swap on the argument buffer encoder.
    func replacePipelineState(with newPipelineState: UnsafeRawPointer, expectingCurrentValue: UnsafeRawPointer?) -> Bool {
        return UnsafeRawPointer.AtomicOptionalRepresentation.atomicWeakCompareExchange(expected: expectingCurrentValue, desired: newPipelineState, at: self.pointer(for: \.pipelineStates), successOrdering: .relaxed, failureOrdering: .relaxed).exchanged
    }
    
    public var storageMode: StorageMode {
        return .private
    }
    
    public static var resourceType: ResourceType { .visibleFunctionTable }
}

extension VisibleFunctionTable: ResourceProtocolImpl {
    typealias SharedProperties = VisibleFunctionTableProperties
    typealias TransientProperties = EmptyProperties<Int>
    typealias PersistentProperties = VisibleFunctionTableProperties.PersistentProperties
    
    static func transientRegistry(index: Int) -> TransientChunkRegistry<VisibleFunctionTable>? {
        return nil
    }
    
    static var persistentRegistry: PersistentRegistry<Self> { VisibleFunctionTableRegistry.instance }
    
    typealias Descriptor = Int // size
}

extension VisibleFunctionTable: CustomStringConvertible {
    public var description: String {
        return "VisibleFunctionTable(handle: \(self.handle)) { \(self.label.map { "label: \($0), "} ?? "")functions: \(self.functions) }"
    }
}

struct VisibleFunctionTableProperties: SharedResourceProperties {
    
    struct PersistentProperties: PersistentResourceProperties {
        /// The index that must be completed on the GPU for each queue before the CPU can read from this resource's memory.
        let readWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The index that must be completed on the GPU for each queue before the CPU can write to this resource's memory.
        let writeWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        let stateFlags : UnsafeMutablePointer<ResourceStateFlags>
        
        @usableFromInline
        init(capacity: Int) {
            self.readWaitIndices = .allocate(capacity: capacity)
            self.writeWaitIndices = .allocate(capacity: capacity)
            self.stateFlags = .allocate(capacity: capacity)
        }
        
        @usableFromInline
        func deallocate() {
            self.readWaitIndices.deallocate()
            self.writeWaitIndices.deallocate()
            self.stateFlags.deallocate()
        }
        
        @usableFromInline
        func initialize(index: Int, descriptor functionCount: Int, heap: Heap?, flags: ResourceFlags) {
            self.readWaitIndices.advanced(by: index).initialize(to: .zero)
            self.writeWaitIndices.advanced(by: index).initialize(to: .zero)
            self.stateFlags.advanced(by: index).initialize(to: [])
        }
        
        @usableFromInline
        func deinitialize(from index: Int, count: Int) {
            self.readWaitIndices.advanced(by: index).deinitialize(count: count)
            self.writeWaitIndices.advanced(by: index).deinitialize(count: count)
            self.stateFlags.advanced(by: index).deinitialize(count: count)
        }
        
        var readWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { self.readWaitIndices }
        var writeWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { self.writeWaitIndices }
        var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { nil }
    }
    
    let functions : UnsafeMutablePointer<[FunctionDescriptor?]>
    let usages : UnsafeMutablePointer<ChunkArray<ResourceUsage>>
    let pipelineStates : UnsafeMutablePointer<UnsafeRawPointer.AtomicOptionalRepresentation> // Some opaque backend type that can construct the argument buffer
    
    init(capacity: Int) {
        self.functions = .allocate(capacity: capacity)
        self.usages = .allocate(capacity: capacity)
        self.pipelineStates = .allocate(capacity: capacity)
    }
    
    func deallocate() {
        self.functions.deallocate()
        self.usages.deallocate()
        self.pipelineStates.deallocate()
    }
    
    func initialize(index: Int, descriptor functionCount: Int, heap: Heap?, flags: ResourceFlags) {
        self.functions.advanced(by: index).initialize(to: .init(repeating: nil, count: functionCount))
        self.usages.advanced(by: index).initialize(to: ChunkArray<ResourceUsage>())
        self.pipelineStates.advanced(by: index).initialize(to: .init(nil))
    }
    
    func deinitialize(from index: Int, count: Int) {
        self.functions.advanced(by: index).deinitialize(count: count)
        self.usages.advanced(by: index).deinitialize(count: count)
        self.pipelineStates.advanced(by: index).deinitialize(count: count)
    }
    
    var usagesOptional: UnsafeMutablePointer<ChunkArray<ResourceUsage>>? { self.usages }
}

final class VisibleFunctionTableRegistry: PersistentRegistry<VisibleFunctionTable> {
    static let instance = VisibleFunctionTableRegistry()
    
    func markAllAsUninitialised() {
        for chunkIndex in 0..<chunkCount {
            let baseItem = chunkIndex * VisibleFunctionTable.itemsPerChunk
            let chunkItemCount = min(self.nextFreeIndex - baseItem, VisibleFunctionTable.itemsPerChunk)
            for i in 0..<chunkItemCount {
                self.persistentChunks![chunkIndex].stateFlags[i].remove(.initialised)
                UnsafeRawPointer.AtomicOptionalRepresentation.atomicStore(nil, at: self.sharedChunks![chunkIndex].pipelineStates.advanced(by: i), ordering: .relaxed)
            }
        }
    }
}

// MARK: - IntersectionFunctionTable

public struct IntersectionFunctionTable : ResourceProtocol {

    @usableFromInline let _handle : UnsafeRawPointer
    @inlinable public var handle : Handle { return UInt64(UInt(bitPattern: _handle)) }
    
    public init(handle: Handle) {
        assert(Resource(handle: handle).type == .intersectionFunctionTable)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public init() {
        let flags : ResourceFlags = .persistent
        
        self = IntersectionFunctionTableRegistry.instance.allocate(descriptor: .init(functions: [], buffers: []), heap: nil, flags: flags)
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public init(descriptor: IntersectionFunctionTableDescriptor) {
        let flags : ResourceFlags = .persistent
        
        self = IntersectionFunctionTableRegistry.instance.allocate(descriptor: descriptor, heap: nil, flags: flags)
    }
    
    public internal(set) var descriptor : IntersectionFunctionTableDescriptor {
        get {
            self[\.descriptors]
        }
        nonmutating set {
            if newValue != self.descriptor {
                self.stateFlags.remove(.initialised)
            }
            self[\.descriptors] = newValue
        }
    }
    
    public var pipelineState : UnsafeRawPointer? {
        get {
            return UnsafeRawPointer.AtomicOptionalRepresentation.atomicLoad(at: self.pointer(for: \.pipelineStates), ordering: .relaxed)
        }
    }
    
    /// Allows us to perform a compare-and-swap on the argument buffer encoder.
    func replacePipelineState(with newPipelineState: UnsafeRawPointer, expectingCurrentValue: UnsafeRawPointer?) -> Bool {
        return UnsafeRawPointer.AtomicOptionalRepresentation.atomicWeakCompareExchange(expected: expectingCurrentValue, desired: newPipelineState, at: self.pointer(for: \.pipelineStates), successOrdering: .relaxed, failureOrdering: .relaxed).exchanged
    }
    
    public var storageMode: StorageMode {
        return .private
    }
    
    public static var resourceType: ResourceType { .intersectionFunctionTable }
}

extension IntersectionFunctionTable: ResourceProtocolImpl {
    typealias SharedProperties = IntersectionFunctionTableProperties
    typealias TransientProperties = EmptyProperties<IntersectionFunctionTableDescriptor>
    typealias PersistentProperties = IntersectionFunctionTableProperties.PersistentProperties
    
    static func transientRegistry(index: Int) -> TransientChunkRegistry<IntersectionFunctionTable>? {
        return nil
    }
    
    static var persistentRegistry: PersistentRegistry<Self> { IntersectionFunctionTableRegistry.instance }
    
    typealias Descriptor = IntersectionFunctionTableDescriptor
}

extension IntersectionFunctionTable: CustomStringConvertible {
    public var description: String {
        return "IntersectionFunctionTable(handle: \(self.handle)) { \(self.label.map { "label: \($0), "} ?? "")descriptor: \(self.descriptor) }"
    }
}

struct IntersectionFunctionTableProperties: SharedResourceProperties {
    
    struct PersistentProperties: PersistentResourceProperties {
        /// The index that must be completed on the GPU for each queue before the CPU can read from this resource's memory.
        let readWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The index that must be completed on the GPU for each queue before the CPU can write to this resource's memory.
        let writeWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        let stateFlags : UnsafeMutablePointer<ResourceStateFlags>
        
        @usableFromInline
        init(capacity: Int) {
            self.readWaitIndices = .allocate(capacity: capacity)
            self.writeWaitIndices = .allocate(capacity: capacity)
            self.stateFlags = .allocate(capacity: capacity)
        }
        
        @usableFromInline
        func deallocate() {
            self.readWaitIndices.deallocate()
            self.writeWaitIndices.deallocate()
            self.stateFlags.deallocate()
        }
        
        @usableFromInline
        func initialize(index: Int, descriptor: IntersectionFunctionTableDescriptor, heap: Heap?, flags: ResourceFlags) {
            self.readWaitIndices.advanced(by: index).initialize(to: .zero)
            self.writeWaitIndices.advanced(by: index).initialize(to: .zero)
            self.stateFlags.advanced(by: index).initialize(to: [])
        }
        
        @usableFromInline
        func deinitialize(from index: Int, count: Int) {
            self.readWaitIndices.advanced(by: index).deinitialize(count: count)
            self.writeWaitIndices.advanced(by: index).deinitialize(count: count)
            self.stateFlags.advanced(by: index).deinitialize(count: count)
        }
        
        
        var readWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { self.readWaitIndices }
        var writeWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { self.writeWaitIndices }
        var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { nil }
    }
    
    let descriptors : UnsafeMutablePointer<IntersectionFunctionTableDescriptor>
    let usages : UnsafeMutablePointer<ChunkArray<ResourceUsage>>
    let pipelineStates : UnsafeMutablePointer<UnsafeRawPointer.AtomicOptionalRepresentation>
    
    init(capacity: Int) {
        self.descriptors = .allocate(capacity: capacity)
        self.usages = .allocate(capacity: capacity)
        self.pipelineStates = .allocate(capacity: capacity)
    }
    
    func deallocate() {
        self.descriptors.deallocate()
        self.usages.deallocate()
        self.pipelineStates.deallocate()
    }
    
    func initialize(index: Int, descriptor: IntersectionFunctionTableDescriptor, heap: Heap?, flags: ResourceFlags) {
        self.descriptors.advanced(by: index).initialize(to: descriptor)
        self.usages.advanced(by: index).initialize(to: ChunkArray<ResourceUsage>())
        self.pipelineStates.advanced(by: index).initialize(to: .init(nil))
    }
    
    func deinitialize(from index: Int, count: Int) {
        self.descriptors.advanced(by: index).deinitialize(count: count)
        self.usages.advanced(by: index).deinitialize(count: count)
        self.pipelineStates.advanced(by: index).deinitialize(count: count)
    }
    
    var usagesOptional: UnsafeMutablePointer<ChunkArray<ResourceUsage>>? { usages }
}

final class IntersectionFunctionTableRegistry: PersistentRegistry<IntersectionFunctionTable> {
    static let instance = IntersectionFunctionTableRegistry()
    
    func markAllAsUninitialised() {
        for chunkIndex in 0..<chunkCount {
            let baseItem = chunkIndex * IntersectionFunctionTable.itemsPerChunk
            let chunkItemCount = min(self.nextFreeIndex - baseItem, IntersectionFunctionTable.itemsPerChunk)
            for i in 0..<chunkItemCount {
                self.persistentChunks![chunkIndex].stateFlags[i].remove(.initialised)
                UnsafeRawPointer.AtomicOptionalRepresentation.atomicStore(nil, at: self.sharedChunks![chunkIndex].pipelineStates.advanced(by: i), ordering: .relaxed)
            }
        }
    }
}
