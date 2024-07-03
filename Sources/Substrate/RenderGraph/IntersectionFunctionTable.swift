//
//  IntersectionFunctionTable.swift
//  
//
//  Created by Thomas Roughton on 29/05/21.
//

import Foundation
import Atomics
import SubstrateUtilities

public struct IntersectionFunctionInputAttributes : OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    
    @inlinable
    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }
    
    @inlinable
    public static var instancing: IntersectionFunctionInputAttributes { IntersectionFunctionInputAttributes(rawValue: 1 << 0) }
    
    @inlinable
    public static var triangleData: IntersectionFunctionInputAttributes { IntersectionFunctionInputAttributes(rawValue: 1 << 1) }
    
    @inlinable
    public static var worldSpaceData: IntersectionFunctionInputAttributes { IntersectionFunctionInputAttributes(rawValue: 1 << 2) }
}

public enum IntersectionFunctionType: Hashable, Sendable {
    case triangle
    case curve
}

public struct IntersectionFunctionTableDescriptor: Hashable, Equatable, Sendable {
    public let pipelineState: PipelineState
    public let renderStage: RenderStages
    public let functionCount: Int
    
    public init(pipelineState: PipelineState, renderStage: RenderStages, functionCount: Int) {
        self.pipelineState = pipelineState
        self.renderStage = renderStage
        self.functionCount = functionCount
    }
}

// MARK: - IntersectionFunctionTable

public struct IntersectionFunctionTable : ResourceProtocol {
    public enum FunctionType: Hashable {
        case defaultOpaqueFunction(type: IntersectionFunctionType = .triangle, inputAttributes: IntersectionFunctionInputAttributes)
        case function(FunctionDescriptor)
    }
    
    public enum BufferType: Hashable {
        case buffer(Buffer, offset: Int)
        case argumentBuffer(ArgumentBuffer)
        case argumentBufferArray(ArgumentBufferArray)
        case functionTable(VisibleFunctionTable)
    }
    

    public let handle: ResourceHandle
    
    public init(handle: Handle) {
        assert(handle.resourceType == .intersectionFunctionTable)
        self.handle = handle
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public init(pipelineState: RenderPipelineState, stage: RenderStages, functionCount: Int) {
        self.init(descriptor: IntersectionFunctionTableDescriptor(pipelineState: pipelineState, renderStage: stage, functionCount: functionCount))
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public init(pipelineState: ComputePipelineState, functionCount: Int) {
        self.init(descriptor: IntersectionFunctionTableDescriptor(pipelineState: pipelineState, renderStage: .compute, functionCount: functionCount))
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public init(descriptor: IntersectionFunctionTableDescriptor) {
        let flags : ResourceFlags = .persistent
        
        self = IntersectionFunctionTableRegistry.instance.allocate(descriptor: descriptor, heap: nil, flags: flags)
        
        if !RenderBackend.materialisePersistentResource(self) {
            self.dispose()
        }
    }
    
    var pipelineState : PipelineState {
        return self.descriptor.pipelineState
    }
    
    public var storageMode: StorageMode {
        return .private
    }
    
    public var stateFlags: ResourceStateFlags {
        get {
            return self[\.stateFlags] ?? []
        }
        nonmutating set {
            self[\.stateFlags] = newValue
        }
    }
    
    public static var resourceType: ResourceType { .intersectionFunctionTable }
    
    public var functions: [FunctionType?] {
        _read {
            yield self.pointer(for: \.functions).pointee
        }
        _modify {
            yield &self.pointer(for: \.functions).pointee
            self.stateFlags.remove(.initialised)
        }
    }
    
    public var buffers: AutoGrowingArray<BufferType> {
        _read {
            yield self.pointer(for: \.buffers).pointee
        }
        _modify {
            yield &self.pointer(for: \.buffers).pointee
            self.stateFlags.remove(.initialised)
        }
    }
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
    
    @usableFromInline static var tracksUsages: Bool { true }
}

extension IntersectionFunctionTable: CustomStringConvertible {
    public var description: String {
        return "IntersectionFunctionTable(handle: \(self.handle)) { \(self.label.map { "label: \($0), "} ?? "")descriptor: \(self.descriptor) }"
    }
}

@usableFromInline struct IntersectionFunctionTableProperties: ResourceProperties {
    
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
        func initialize(index: Int, descriptor: IntersectionFunctionTableDescriptor, heap: Heap?, flags: ResourceFlags) {
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
    
    let functions: UnsafeMutablePointer<[IntersectionFunctionTable.FunctionType?]>
    let buffers: UnsafeMutablePointer<AutoGrowingArray<IntersectionFunctionTable.BufferType>>
    
    @usableFromInline init(capacity: Int) {
        self.functions = .allocate(capacity: capacity)
        self.buffers = .allocate(capacity: capacity)
    }
    
    @usableFromInline func deallocate() {
        self.functions.deallocate()
        self.buffers.deallocate()
    }
    
    @usableFromInline func initialize(index: Int, descriptor: IntersectionFunctionTableDescriptor, heap: Heap?, flags: ResourceFlags) {
        self.functions.advanced(by: index).initialize(to: .init(repeating: nil, count: descriptor.functionCount))
        self.buffers.advanced(by: index).initialize(to: .init())
    }
    
    @usableFromInline func deinitialize(from index: Int, count: Int) {
        self.functions.advanced(by: index).deinitialize(count: count)
        self.buffers.advanced(by: index).deinitialize(count: count)
    }
}

final class IntersectionFunctionTableRegistry: PersistentRegistry<IntersectionFunctionTable> {
    static let instance = IntersectionFunctionTableRegistry()
    
    func markAllAsUninitialised() {
        for chunkIndex in 0..<chunkCount {
            let baseItem = chunkIndex * IntersectionFunctionTable.itemsPerChunk
            let chunkItemCount = min(self.nextFreeIndex - baseItem, IntersectionFunctionTable.itemsPerChunk)
            for i in 0..<chunkItemCount {
                self.persistentChunks![chunkIndex].stateFlags[i].remove(.initialised)
            }
        }
    }
}
