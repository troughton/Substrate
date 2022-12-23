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
        if !RenderBackend.materialiseResource(self) {
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
    @usableFromInline typealias SharedProperties = AccelerationStructureProperties
    @usableFromInline typealias TransientProperties = EmptyProperties<Int>
    @usableFromInline typealias PersistentProperties = AccelerationStructureProperties.PersistentProperties
    
    @usableFromInline static func transientRegistry(index: Int) -> TransientChunkRegistry<AccelerationStructure>? {
        return nil
    }
    
    @usableFromInline static var persistentRegistry: PersistentRegistry<Self> { AccelerationStructureRegistry.instance }
    
    @usableFromInline typealias Descriptor = Int // size
}

extension AccelerationStructure: CustomStringConvertible {
    public var description: String {
        return "AccelerationStructure(handle: \(self.handle)) { \(self.label.map { "label: \($0), "} ?? "")size: \(self.size) }"
    }
}

@usableFromInline struct AccelerationStructureProperties: SharedResourceProperties {
    @usableFromInline struct PersistentProperties: PersistentResourceProperties {
        
        /// The index that must be completed on the GPU for each queue before the CPU can read from this resource's memory.
        let readWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The index that must be completed on the GPU for each queue before the CPU can write to this resource's memory.
        let writeWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The RenderGraphs that are currently using this resource.
        let activeRenderGraphs : UnsafeMutablePointer<UInt8.AtomicRepresentation>
        
        @usableFromInline init(capacity: Int) {
            self.readWaitIndices = .allocate(capacity: capacity)
            self.writeWaitIndices = .allocate(capacity: capacity)
            self.activeRenderGraphs = .allocate(capacity: capacity)
        }
        
        @usableFromInline func deallocate() {
            self.readWaitIndices.deallocate()
            self.writeWaitIndices.deallocate()
            self.activeRenderGraphs.deallocate()
        }
        
        @usableFromInline func initialize(index: Int, descriptor size: Int, heap: Heap?, flags: ResourceFlags) {
            self.readWaitIndices.advanced(by: index).initialize(to: SIMD8(repeating: 0))
            self.writeWaitIndices.advanced(by: index).initialize(to: SIMD8(repeating: 0))
            self.activeRenderGraphs.advanced(by: index).initialize(to: UInt8.AtomicRepresentation(0))
        }
        
        @usableFromInline func deinitialize(from index: Int, count: Int) {
            self.readWaitIndices.advanced(by: index).deinitialize(count: count)
            self.writeWaitIndices.advanced(by: index).deinitialize(count: count)
            self.activeRenderGraphs.advanced(by: index).deinitialize(count: count)
        }
        
        @usableFromInline var readWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { self.readWaitIndices }
        @usableFromInline var writeWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { self.writeWaitIndices }
        @usableFromInline var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { activeRenderGraphs }
    }
    
    let sizes : UnsafeMutablePointer<Int>
    let usages : UnsafeMutablePointer<ChunkArray<RecordedResourceUsage>>
    let descriptors : UnsafeMutablePointer<AccelerationStructureDescriptor?>
    let backingResources : UnsafeMutablePointer<UnsafeMutableRawPointer?>
    
#if canImport(Metal)
    let gpuAddresses: UnsafeMutablePointer<UInt64>
#endif
    
    @usableFromInline init(capacity: Int) {
        self.sizes = .allocate(capacity: capacity)
        self.usages = .allocate(capacity: capacity)
        self.descriptors = .allocate(capacity: capacity)
        self.backingResources = .allocate(capacity: capacity)
        
#if canImport(Metal)
        self.gpuAddresses = UnsafeMutablePointer.allocate(capacity: capacity)
#endif
    }
    
    @usableFromInline func deallocate() {
        self.sizes.deallocate()
        self.usages.deallocate()
        self.descriptors.deallocate()
        self.backingResources.deallocate()
        
#if canImport(Metal)
        self.gpuAddresses.deallocate()
#endif
    }
    
    @usableFromInline func initialize(index: Int, descriptor size: Int, heap: Heap?, flags: ResourceFlags) {
        self.sizes.advanced(by: index).initialize(to: size)
        self.usages.advanced(by: index).initialize(to: ChunkArray())
        self.descriptors.advanced(by: index).initialize(to: nil)
        self.backingResources.advanced(by: index).initialize(to: nil)
        
#if canImport(Metal)
        self.gpuAddresses.advanced(by: index).initialize(to: 0)
#endif
    }
    
    @usableFromInline func deinitialize(from index: Int, count: Int) {
        self.sizes.advanced(by: index).deinitialize(count: count)
        self.usages.advanced(by: index).deinitialize(count: count)
        self.descriptors.advanced(by: index).deinitialize(count: count)
        self.backingResources.advanced(by: index).deinitialize(count: count)

#if canImport(Metal)
        self.gpuAddresses.advanced(by: index).deinitialize(count: count)
#endif
    }
    
    @usableFromInline var usagesOptional: UnsafeMutablePointer<ChunkArray<RecordedResourceUsage>>? { usages }
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
    init(functionCount: Int, pipelineState: OpaquePointer) {
        let flags : ResourceFlags = .persistent
        
        self = VisibleFunctionTableRegistry.instance.allocate(descriptor: functionCount, heap: nil, flags: flags)
        self.pipelineState = UnsafeRawPointer(pipelineState)
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public init(functionCount: Int, pipelineState: PipelineState) {
        self.init(functionCount: functionCount, pipelineState: pipelineState.state)
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
    
    var pipelineState : UnsafeRawPointer? {
        get {
            return self.pointer(for: \.pipelineStates).pointee
        }
        set {
            self.pointer(for: \.pipelineStates).pointee = newValue
        }
    }
    
    public var storageMode: StorageMode {
        return .private
    }
    
    public static var resourceType: ResourceType { .visibleFunctionTable }
}

extension VisibleFunctionTable: ResourceProtocolImpl {
    @usableFromInline typealias SharedProperties = VisibleFunctionTableProperties
    @usableFromInline typealias TransientProperties = EmptyProperties<Int>
    @usableFromInline typealias PersistentProperties = VisibleFunctionTableProperties.PersistentProperties
    
    @usableFromInline static func transientRegistry(index: Int) -> TransientChunkRegistry<VisibleFunctionTable>? {
        return nil
    }
    
    @usableFromInline static var persistentRegistry: PersistentRegistry<Self> { VisibleFunctionTableRegistry.instance }
    
    @usableFromInline typealias Descriptor = Int // size
}

extension VisibleFunctionTable: CustomStringConvertible {
    public var description: String {
        return "VisibleFunctionTable(handle: \(self.handle)) { \(self.label.map { "label: \($0), "} ?? "")functions: \(self.functions) }"
    }
}

@usableFromInline struct VisibleFunctionTableProperties: SharedResourceProperties {
    
    @usableFromInline struct PersistentProperties: PersistentResourceProperties {
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
        
        @usableFromInline var readWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { self.readWaitIndices }
        @usableFromInline var writeWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { self.writeWaitIndices }
        @usableFromInline var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { nil }
    }
    
    let functions : UnsafeMutablePointer<[FunctionDescriptor?]>
    let usages : UnsafeMutablePointer<ChunkArray<RecordedResourceUsage>>
    let pipelineStates : UnsafeMutablePointer<UnsafeRawPointer?>
    let backingResources : UnsafeMutablePointer<UnsafeMutableRawPointer?>
    
#if canImport(Metal)
    let gpuAddresses: UnsafeMutablePointer<UInt64>
#endif
    
    @usableFromInline init(capacity: Int) {
        self.functions = .allocate(capacity: capacity)
        self.usages = .allocate(capacity: capacity)
        self.pipelineStates = .allocate(capacity: capacity)
        self.backingResources = .allocate(capacity: capacity)
        
#if canImport(Metal)
        self.gpuAddresses = UnsafeMutablePointer.allocate(capacity: capacity)
#endif
    }
    
    @usableFromInline func deallocate() {
        self.functions.deallocate()
        self.usages.deallocate()
        self.pipelineStates.deallocate()
        self.backingResources.deallocate()
        
#if canImport(Metal)
        self.gpuAddresses.deallocate()
#endif
    }
    
    @usableFromInline func initialize(index: Int, descriptor functionCount: Int, heap: Heap?, flags: ResourceFlags) {
        self.functions.advanced(by: index).initialize(to: .init(repeating: nil, count: functionCount))
        self.usages.advanced(by: index).initialize(to: ChunkArray<RecordedResourceUsage>())
        self.pipelineStates.advanced(by: index).initialize(to: .init(nil))
        self.backingResources.advanced(by: index).initialize(to: nil)
        
#if canImport(Metal)
        self.gpuAddresses.advanced(by: index).initialize(to: 0)
#endif
    }
    
    @usableFromInline func deinitialize(from index: Int, count: Int) {
        self.functions.advanced(by: index).deinitialize(count: count)
        self.usages.advanced(by: index).deinitialize(count: count)
        self.pipelineStates.advanced(by: index).deinitialize(count: count)
        self.backingResources.advanced(by: index).deinitialize(count: count)
        
#if canImport(Metal)
        self.gpuAddresses.advanced(by: index).deinitialize(count: count)
#endif
    }
    
    @usableFromInline var usagesOptional: UnsafeMutablePointer<ChunkArray<RecordedResourceUsage>>? { self.usages }
}

@usableFromInline final class VisibleFunctionTableRegistry: PersistentRegistry<VisibleFunctionTable> {
    @usableFromInline static let instance = VisibleFunctionTableRegistry()
    
    func markAllAsUninitialised() {
        for chunkIndex in 0..<chunkCount {
            let baseItem = chunkIndex * VisibleFunctionTable.itemsPerChunk
            let chunkItemCount = min(self.nextFreeIndex - baseItem, VisibleFunctionTable.itemsPerChunk)
            for i in 0..<chunkItemCount {
                self.persistentChunks![chunkIndex].stateFlags[i].remove(.initialised)
                self.sharedChunks![chunkIndex].pipelineStates[i] = nil
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
    public init(pipelineState: PipelineState) {
        let flags : ResourceFlags = .persistent
        
        self = IntersectionFunctionTableRegistry.instance.allocate(descriptor: .init(functions: [], buffers: []), heap: nil, flags: flags)
        self.pipelineState = UnsafeRawPointer(pipelineState.state)
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public init(descriptor: IntersectionFunctionTableDescriptor, pipelineState: PipelineState) {
        let flags : ResourceFlags = .persistent
        
        self = IntersectionFunctionTableRegistry.instance.allocate(descriptor: descriptor, heap: nil, flags: flags)
        self.pipelineState = UnsafeRawPointer(pipelineState.state)
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
    
    
    var pipelineState : UnsafeRawPointer? {
        get {
            return self.pointer(for: \.pipelineStates).pointee
        }
        set {
            self.pointer(for: \.pipelineStates).pointee = newValue
        }
    }
    
    public var storageMode: StorageMode {
        return .private
    }
    
    public static var resourceType: ResourceType { .intersectionFunctionTable }
}

extension IntersectionFunctionTable: ResourceProtocolImpl {
    @usableFromInline typealias SharedProperties = IntersectionFunctionTableProperties
    @usableFromInline typealias TransientProperties = EmptyProperties<IntersectionFunctionTableDescriptor>
    @usableFromInline typealias PersistentProperties = IntersectionFunctionTableProperties.PersistentProperties
    
    @usableFromInline static func transientRegistry(index: Int) -> TransientChunkRegistry<IntersectionFunctionTable>? {
        return nil
    }
    
    @usableFromInline static var persistentRegistry: PersistentRegistry<Self> { IntersectionFunctionTableRegistry.instance }
    
    @usableFromInline typealias Descriptor = IntersectionFunctionTableDescriptor
}

extension IntersectionFunctionTable: CustomStringConvertible {
    public var description: String {
        return "IntersectionFunctionTable(handle: \(self.handle)) { \(self.label.map { "label: \($0), "} ?? "")descriptor: \(self.descriptor) }"
    }
}

@usableFromInline struct IntersectionFunctionTableProperties: SharedResourceProperties {
    
    @usableFromInline struct PersistentProperties: PersistentResourceProperties {
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
        
        
        @usableFromInline var readWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { self.readWaitIndices }
        @usableFromInline var writeWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { self.writeWaitIndices }
        @usableFromInline var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { nil }
    }
    
    let descriptors : UnsafeMutablePointer<IntersectionFunctionTableDescriptor>
    let usages : UnsafeMutablePointer<ChunkArray<RecordedResourceUsage>>
    let pipelineStates : UnsafeMutablePointer<UnsafeRawPointer?>
    let backingResources : UnsafeMutablePointer<UnsafeMutableRawPointer?>
    
#if canImport(Metal)
    let gpuAddresses: UnsafeMutablePointer<UInt64>
#endif
    
    @usableFromInline init(capacity: Int) {
        self.descriptors = .allocate(capacity: capacity)
        self.usages = .allocate(capacity: capacity)
        self.pipelineStates = .allocate(capacity: capacity)
        self.backingResources = .allocate(capacity: capacity)
        
#if canImport(Metal)
        self.gpuAddresses = UnsafeMutablePointer.allocate(capacity: capacity)
#endif
    }
    
    @usableFromInline func deallocate() {
        self.descriptors.deallocate()
        self.usages.deallocate()
        self.pipelineStates.deallocate()
        self.backingResources.deallocate()
        
#if canImport(Metal)
        self.gpuAddresses.deallocate()
#endif
    }
    
    @usableFromInline func initialize(index: Int, descriptor: IntersectionFunctionTableDescriptor, heap: Heap?, flags: ResourceFlags) {
        self.descriptors.advanced(by: index).initialize(to: descriptor)
        self.usages.advanced(by: index).initialize(to: ChunkArray<RecordedResourceUsage>())
        self.pipelineStates.advanced(by: index).initialize(to: .init(nil))
        self.backingResources.advanced(by: index).initialize(to: nil)
        
#if canImport(Metal)
        self.gpuAddresses.advanced(by: index).initialize(to: 0)
#endif
    }
    
    @usableFromInline func deinitialize(from index: Int, count: Int) {
        self.descriptors.advanced(by: index).deinitialize(count: count)
        self.usages.advanced(by: index).deinitialize(count: count)
        self.pipelineStates.advanced(by: index).deinitialize(count: count)
        self.backingResources.advanced(by: index).deinitialize(count: count)
        
#if canImport(Metal)
        self.gpuAddresses.advanced(by: index).deinitialize(count: count)
#endif
    }
    
    @usableFromInline var usagesOptional: UnsafeMutablePointer<ChunkArray<RecordedResourceUsage>>? { usages }
}

final class IntersectionFunctionTableRegistry: PersistentRegistry<IntersectionFunctionTable> {
    static let instance = IntersectionFunctionTableRegistry()
    
    func markAllAsUninitialised() {
        for chunkIndex in 0..<chunkCount {
            let baseItem = chunkIndex * IntersectionFunctionTable.itemsPerChunk
            let chunkItemCount = min(self.nextFreeIndex - baseItem, IntersectionFunctionTable.itemsPerChunk)
            for i in 0..<chunkItemCount {
                self.persistentChunks![chunkIndex].stateFlags[i].remove(.initialised)
                self.sharedChunks![chunkIndex].pipelineStates[i] = nil
            }
        }
    }
}
