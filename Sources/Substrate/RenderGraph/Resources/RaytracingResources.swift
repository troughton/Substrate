//
//  RaytracingResources.swift
//  
//
//  Created by Thomas Roughton on 2/07/21.
//

import SubstrateUtilities
import Atomics

// MARK: - AccelerationStructure

public struct AccelerationStructure : ResourceProtocol, Sendable {
    public let handle: ResourceHandle
    
    public init(handle: Handle) {
        assert(handle.resourceType == .accelerationStructure)
        self.handle = handle
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public init(size: Int) {
        let flags : ResourceFlags = .persistent
        
        self = AccelerationStructureRegistry.instance.allocate(descriptor: size, heap: nil, flags: flags)
        
        // vkCreateAccelerationStructureKHR
        if !RenderBackend.materialisePersistentResource(self) {
            assertionFailure("Allocation failed for acceleration structure \(self)")
            self.dispose()
        }
    }
    
    public var size : Int {
        get {
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: Self.itemsPerChunk)
            return Self.persistentRegistry.sharedPropertyChunks[chunkIndex].descriptors![indexInChunk]
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
    
    @usableFromInline static var tracksUsages: Bool { true }
}

extension AccelerationStructure: CustomStringConvertible {
    public var description: String {
        return "AccelerationStructure(handle: \(self.handle)) { \(self.label.map { "label: \($0), "} ?? "")size: \(self.size) }"
    }
}

@usableFromInline struct AccelerationStructureProperties: ResourceProperties {
    @usableFromInline struct PersistentProperties: PersistentResourceProperties {
        
        /// The index that must be completed on the GPU for each queue before the CPU can read from this resource's memory.
        let readWaitIndices : UnsafeMutablePointer<QueueCommandIndex.AtomicRepresentation>
        /// The index that must be completed on the GPU for each queue before the CPU can write to this resource's memory.
        let writeWaitIndices : UnsafeMutablePointer<QueueCommandIndex.AtomicRepresentation>
        /// The RenderGraphs that are currently using this resource.
        let activeRenderGraphs : UnsafeMutablePointer<UInt8.AtomicRepresentation>
        
        @usableFromInline init(capacity: Int) {
            self.readWaitIndices = .allocate(capacity: capacity * QueueCommandIndices.scalarCount)
            self.writeWaitIndices = .allocate(capacity: capacity * QueueCommandIndices.scalarCount)
            self.activeRenderGraphs = .allocate(capacity: capacity)
        }
        
        @usableFromInline func deallocate() {
            self.readWaitIndices.deallocate()
            self.writeWaitIndices.deallocate()
            self.activeRenderGraphs.deallocate()
        }
        
        @usableFromInline func initialize(index: Int, descriptor size: Int, heap: Heap?, flags: ResourceFlags) {
            self.readWaitIndices.advanced(by: index * QueueCommandIndices.scalarCount).initialize(repeating: .init(0), count: QueueCommandIndices.scalarCount)
            self.writeWaitIndices.advanced(by: index * QueueCommandIndices.scalarCount).initialize(repeating: .init(0), count: QueueCommandIndices.scalarCount)
            self.activeRenderGraphs.advanced(by: index).initialize(to: UInt8.AtomicRepresentation(0))
        }
        
        @usableFromInline func deinitialize(from index: Int, count: Int) {
            self.readWaitIndices.advanced(by: index * QueueCommandIndices.scalarCount).deinitialize(count: count * QueueCommandIndices.scalarCount)
            self.writeWaitIndices.advanced(by: index * QueueCommandIndices.scalarCount).deinitialize(count: count * QueueCommandIndices.scalarCount)
            self.activeRenderGraphs.advanced(by: index).deinitialize(count: count)
        }
        
        @usableFromInline var readWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndex.AtomicRepresentation>? { self.readWaitIndices }
        @usableFromInline var writeWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndex.AtomicRepresentation>? { self.writeWaitIndices }
        @usableFromInline var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { activeRenderGraphs }
    }
    
    let descriptors : UnsafeMutablePointer<AccelerationStructureDescriptor?> // since AccelerationStructure's associated descriptor is an Int representing the size
    
    @usableFromInline init(capacity: Int) {
        self.descriptors = .allocate(capacity: capacity)
    }
    
    @usableFromInline func deallocate() {
        self.descriptors.deallocate()
    }
    
    @usableFromInline func initialize(index: Int, descriptor size: Int, heap: Heap?, flags: ResourceFlags) {
        self.descriptors.advanced(by: index).initialize(to: nil)
    }
    
    @usableFromInline func deinitialize(from index: Int, count: Int) {
        self.descriptors.advanced(by: index).deinitialize(count: count)
    }
}

final class AccelerationStructureRegistry: PersistentRegistry<AccelerationStructure>, @unchecked Sendable {
    static let instance = AccelerationStructureRegistry()
}


// MARK: - VisibleFunctionTable

public struct VisibleFunctionTableDescriptor {
    public var functionCount: Int
    public var pipelineState: PipelineState
    public var renderStage: RenderStages
}

public struct VisibleFunctionTable : ResourceProtocol {
    public let handle: ResourceHandle
    
    public init(handle: Handle) {
        assert(handle.resourceType == .visibleFunctionTable)
        self.handle = handle
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    init(functionCount: Int, pipelineState: PipelineState, stage: RenderStages) {
        let flags : ResourceFlags = .persistent
        
        let descriptor = VisibleFunctionTableDescriptor(functionCount: functionCount, pipelineState: pipelineState, renderStage: stage)
        self = VisibleFunctionTableRegistry.instance.allocate(descriptor: descriptor, heap: nil, flags: flags)
        
        if !RenderBackend.materialisePersistentResource(self) {
            self.dispose()
        }
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public init(functionCount: Int, pipelineState: ComputePipelineState) {
        self.init(functionCount: functionCount, pipelineState: pipelineState, stage: .compute)
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
            yield &self.pointer(for: \.functions).pointee
            self.stateFlags.remove(.initialised)
        }
    }
    
    var pipelineState : PipelineState {
        return self.descriptor.pipelineState
    }
    
    public var storageMode: StorageMode {
        return .private
    }
    
    public static var resourceType: ResourceType { .visibleFunctionTable }
}

extension VisibleFunctionTable: ResourceProtocolImpl {
    @usableFromInline typealias SharedProperties = VisibleFunctionTableProperties
    @usableFromInline typealias TransientProperties = EmptyProperties<VisibleFunctionTableDescriptor>
    @usableFromInline typealias PersistentProperties = VisibleFunctionTableProperties.PersistentProperties
    
    @usableFromInline static func transientRegistry(index: Int) -> TransientChunkRegistry<VisibleFunctionTable>? {
        return nil
    }
    
    @usableFromInline static var persistentRegistry: PersistentRegistry<Self> { VisibleFunctionTableRegistry.instance }
    
    @usableFromInline typealias Descriptor = VisibleFunctionTableDescriptor // functionCount
    
    @usableFromInline static var tracksUsages: Bool { true }
}

extension VisibleFunctionTable: CustomStringConvertible {
    public var description: String {
        return "VisibleFunctionTable(handle: \(self.handle)) { \(self.label.map { "label: \($0), "} ?? "")functions: \(self.functions) }"
    }
}

@usableFromInline struct VisibleFunctionTableProperties: ResourceProperties {
    
    @usableFromInline struct PersistentProperties: PersistentResourceProperties {
        /// The index that must be completed on the GPU for each queue before the CPU can read from this resource's memory.
        let readWaitIndices : UnsafeMutablePointer<QueueCommandIndex.AtomicRepresentation>
        /// The index that must be completed on the GPU for each queue before the CPU can write to this resource's memory.
        let writeWaitIndices : UnsafeMutablePointer<QueueCommandIndex.AtomicRepresentation>
        let stateFlags : UnsafeMutablePointer<ResourceStateFlags>
        
        @usableFromInline
        init(capacity: Int) {
            self.readWaitIndices = .allocate(capacity: capacity * QueueCommandIndices.scalarCount)
            self.writeWaitIndices = .allocate(capacity: capacity * QueueCommandIndices.scalarCount)
            self.stateFlags = .allocate(capacity: capacity)
        }
        
        @usableFromInline
        func deallocate() {
            self.readWaitIndices.deallocate()
            self.writeWaitIndices.deallocate()
            self.stateFlags.deallocate()
        }
        
        @usableFromInline
        func initialize(index: Int, descriptor: VisibleFunctionTableDescriptor, heap: Heap?, flags: ResourceFlags) {
            self.readWaitIndices.advanced(by: index * QueueCommandIndices.scalarCount).initialize(repeating: .init(0), count: QueueCommandIndices.scalarCount)
            self.writeWaitIndices.advanced(by: index * QueueCommandIndices.scalarCount).initialize(repeating: .init(0), count: QueueCommandIndices.scalarCount)
            self.stateFlags.advanced(by: index).initialize(to: [])
        }
        
        @usableFromInline
        func deinitialize(from index: Int, count: Int) {
            self.readWaitIndices.advanced(by: index * QueueCommandIndices.scalarCount).deinitialize(count: count * QueueCommandIndices.scalarCount)
            self.writeWaitIndices.advanced(by: index * QueueCommandIndices.scalarCount).deinitialize(count: count * QueueCommandIndices.scalarCount)
            self.stateFlags.advanced(by: index).deinitialize(count: count)
        }
        
        @usableFromInline var readWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndex.AtomicRepresentation>? { self.readWaitIndices }
        @usableFromInline var writeWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndex.AtomicRepresentation>? { self.writeWaitIndices }
        @usableFromInline var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { nil }
    }
    
    let functions : UnsafeMutablePointer<[FunctionDescriptor?]>
    
    @usableFromInline init(capacity: Int) {
        self.functions = .allocate(capacity: capacity)
    }
    
    @usableFromInline func deallocate() {
        self.functions.deallocate()
    }
    
    @usableFromInline func initialize(index: Int, descriptor: VisibleFunctionTableDescriptor, heap: Heap?, flags: ResourceFlags) {
        self.functions.advanced(by: index).initialize(to: .init(repeating: nil, count: descriptor.functionCount))
    }
    
    @usableFromInline func deinitialize(from index: Int, count: Int) {
        self.functions.advanced(by: index).deinitialize(count: count)
    }
}

@usableFromInline final class VisibleFunctionTableRegistry: PersistentRegistry<VisibleFunctionTable>, @unchecked Sendable {
    @usableFromInline static let instance = VisibleFunctionTableRegistry()
    
    func markAllAsUninitialised() {
        for chunkIndex in 0..<chunkCount {
            let baseItem = chunkIndex * VisibleFunctionTable.itemsPerChunk
            let chunkItemCount = min(self.nextFreeIndex - baseItem, VisibleFunctionTable.itemsPerChunk)
            for i in 0..<chunkItemCount {
                self.persistentChunks![chunkIndex].stateFlags[i].remove(.initialised)
            }
        }
    }
}
