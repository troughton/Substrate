//
//  ArgumentEncoder.swift
//  RenderAPI
//
//  Created by Thomas Roughton on 22/02/18.
//

import Foundation
import SubstrateUtilities
import Atomics

#if canImport(Metal)
import Metal
#endif

public protocol ArgumentBufferEncodable {
    static var activeStages : RenderStages { get }
    
    static var argumentBufferDescriptor: ArgumentBufferDescriptor { get }
    
    mutating func encode(into argBuffer: ArgumentBuffer, setIndex: Int, bindingEncoder: ResourceBindingEncoder?) async
}

@available(*, deprecated, renamed: "ArgumentBuffer")
public typealias _ArgumentBuffer = ArgumentBuffer

public struct ArgumentDescriptor: Hashable, Sendable {
    public enum ArgumentResourceType: Hashable, Sendable {
        case inlineData(type: DataType)
        case constantBuffer(alignment: Int = 0)
        case storageBuffer
        case texture(type: TextureType)
        case sampler
        case accelerationStructure
    }
    
    public var resourceType: ArgumentResourceType // VkDescriptorSetLayoutBinding.descriptorType
    public var index: Int // VkDescriptorSetLayoutBinding.binding
    public var arrayLength: Int // VkDescriptorSetLayoutBinding.descriptorCount
    public var accessType: ResourceAccessType // VkDescriptorSetLayoutBinding.descriptorType
    @usableFromInline var encodedBufferOffset: Int
    @usableFromInline var encodedBufferStride: Int
    
    public init(resourceType: ArgumentResourceType, index: Int? = nil, arrayLength: Int = 1, accessType: ResourceAccessType = .read) {
        self.resourceType = resourceType
        self.index = index ?? -1
        self.arrayLength = arrayLength
        self.accessType = accessType
        self.encodedBufferOffset = -1
        self.encodedBufferStride = 0
        
        let sizeAndAlign = RenderBackend._backend!.argumentBufferImpl.encodedBufferSizeAndAlign(forArgument: self)
        self.encodedBufferStride = sizeAndAlign.size.roundedUpToMultiple(of: sizeAndAlign.alignment)
    }
}

extension ArgumentDescriptor.ArgumentResourceType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .inlineData(let type):
            return "inlineData(type: .\(type))"
        case .constantBuffer(let alignment):
            return "constantBuffer(alignment: \(alignment))"
        case .storageBuffer:
            return "storageBuffer"
        case .texture(let type):
            let typeString = String(describing: type)
            return "texture(type: .\(typeString))"
        case .sampler:
            return "sampler"
        case .accelerationStructure:
            return "accelerationStructure"
        }
    }
}

public struct ArgumentBufferDescriptor: Hashable, Sendable {
    public var arguments: [ArgumentDescriptor]
    public var storageMode: StorageMode
    @usableFromInline var bufferLength: Int
    
    @inlinable
    public init(arguments: [ArgumentDescriptor], storageMode: StorageMode = .shared) {
        self.arguments = arguments
        self.storageMode = storageMode
        
        var offset = 0
        var nextIndex = 0
        for i in self.arguments.indices {
            precondition(self.arguments[i].index < 0 || self.arguments[i].index >= nextIndex, "Arguments must be in order of ascending index.")
            self.arguments[i].index = max(self.arguments[i].index, nextIndex)
            
            offset = offset.roundedUpToMultiple(of: self.arguments[i].encodedBufferStride)
            self.arguments[i].encodedBufferOffset = offset
            nextIndex = self.arguments[i].index + self.arguments[i].arrayLength
            offset += self.arguments[i].encodedBufferStride * self.arguments[i].arrayLength
        }
        
        self.bufferLength = offset
    }
}

public struct ArgumentBuffer : ResourceProtocol {
    @usableFromInline let _handle : UnsafeRawPointer
    @inlinable public var handle : Handle { return UInt64(UInt(bitPattern: _handle)) }
    
    public enum ArgumentResource {
        case buffer(Buffer, offset: Int)
        case texture(Texture)
        case accelerationStructure(AccelerationStructure)
        case visibleFunctionTable(VisibleFunctionTable)
        case intersectionFunctionTable(IntersectionFunctionTable)
        case sampler(SamplerState)
        // Where offset is the source offset in the source Data.
        case bytes(offset: Int, length: Int)
        
        public var resource: Resource? {
            switch self {
            case .buffer(let buffer, _):
                return Resource(buffer)
            case .texture(let texture):
                return Resource(texture)
            case .accelerationStructure(let structure):
                return Resource(structure)
            case .visibleFunctionTable(let table):
                return Resource(table)
            case .intersectionFunctionTable(let table):
                return Resource(table)
            case .sampler, .bytes:
                return nil
            }
        }
        
        public var activeRangeOffsetIntoResource: Int {
            switch self {
            case .buffer(_, let offset):
                return offset
            default:
                return 0
            }
        }
    }
    
    public init(handle: Handle) {
        assert(Resource(handle: handle).type == .argumentBuffer)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
    }
   
    public init(bindingPath: ResourceBindingPath, pipelineState: PipelineState, renderGraph: RenderGraph? = nil) {
        guard let renderGraph = renderGraph ?? RenderGraph.activeRenderGraph else {
            fatalError("The RenderGraph must be specified for transient resources created outside of a render pass' execute() method.")
        }
        guard let descriptor = pipelineState.argumentBufferDescriptor(at: bindingPath) else {
            preconditionFailure("Binding path \(bindingPath) does not represent an argument buffer binding in the provided pipeline reflection.")
        }
        precondition(renderGraph.transientRegistryIndex >= 0, "Transient resources are not supported on the RenderGraph \(renderGraph)")
        
        self = TransientArgumentBufferRegistry.instances[renderGraph.transientRegistryIndex].allocate(descriptor: descriptor, flags: [])
        
        if descriptor.storageMode != .private {
            renderGraph.context.transientRegistry!.accessLock.withLock {
                _ = renderGraph.context.transientRegistry!.allocateArgumentBufferIfNeeded(self)
            }
        }
    }
    
    public init(descriptor: ArgumentBufferDescriptor, renderGraph: RenderGraph? = nil, flags: ResourceFlags = []) {
        precondition(!flags.contains(.historyBuffer), "Argument Buffers cannot be used as history buffers.")
        
        if flags.contains(.persistent) {
            self = PersistentArgumentBufferRegistry.instance.allocate(descriptor: descriptor, heap: nil, flags: flags)
            _ = RenderBackend.materialisePersistentResource(self)
        } else {
            guard let renderGraph = renderGraph ?? RenderGraph.activeRenderGraph else {
                fatalError("The RenderGraph must be specified for transient resources created outside of a render pass' execute() method.")
            }
            precondition(renderGraph.transientRegistryIndex >= 0, "Transient resources are not supported on the RenderGraph \(renderGraph)")
            
            self = TransientArgumentBufferRegistry.instances[renderGraph.transientRegistryIndex].allocate(descriptor: descriptor, flags: flags)
            
            if descriptor.storageMode != .private {
                renderGraph.context.transientRegistry!.accessLock.withLock {
                    _ = renderGraph.context.transientRegistry!.allocateArgumentBufferIfNeeded(self)
                }
            }
        }
        
        // Transient resources:
        // - CPU visible
        //  - Buffers and argument buffers only
        //  - Suballocated from an arena allocator
        //  - Available as soon as there's a GPU frame free (so necessitates 'await')
        //
        // - GPU private
        //  - Heap allocated, aliased
        //  - Allocated on render graph execution.
        //
        // What changes:
        // - Argument buffers can't be encoded until all resources to be encoded are available (so in a CPU render pass for transient resources);
        //   that can either be managed by the API or forced onto the user.
        // - No more transient CPU-visible textures (but that was just allocating and disposing a persistent texture anyway).
        // - Lazy materialise only applies to GPU-private resources
        
    }
    
    public init<A : ArgumentBufferEncodable>(encoding arguments: A, setIndex: Int, renderGraph: RenderGraph? = nil, flags: ResourceFlags = []) async {
        self.init(descriptor: A.argumentBufferDescriptor, renderGraph: renderGraph, flags: flags)

#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
    self.label = "Resource Set for \(String(reflecting: A.self))"
#endif
        
        var arguments = arguments
        await arguments.encode(into: self, setIndex: setIndex, bindingEncoder: nil)
    }
    
    public var stateFlags: ResourceStateFlags {
        get {
            return self.pointer(for: \.stateFlags).pointee
        }
        nonmutating set {
            self.pointer(for: \.stateFlags).pointee = newValue
        }
    }
    
    
#if canImport(Metal)
    // For Metal: residency tracking.
    
    public var usedResources: HashSet<UnsafeMutableRawPointer> {
        _read {
            yield self.pointer(for: \.usedResources).pointee
        }
        nonmutating _modify {
            yield &self.pointer(for: \.usedResources).pointee
        }
    }
    
    public var usedHeaps: HashSet<UnsafeMutableRawPointer> {
        _read {
            yield self.pointer(for: \.usedHeaps).pointee
        }
        nonmutating _modify {
            yield &self.pointer(for: \.usedHeaps).pointee
        }
    }
    
#endif
    
    /// A limit for the maximum buffer size that may be allocated by the backend for this argument buffer.
    /// Useful for capping the length of bindless arrays to the actually used capacity.
    public var maximumAllocationLength : Int {
        get {
            return self.pointer(for: \.maxAllocationLengths).pointee
        }
        nonmutating set {
            self.pointer(for: \.maxAllocationLengths).pointee = newValue
        }
    }
     
    public var storageMode: StorageMode {
        return self.descriptor.storageMode
    }
    
    public func setBuffer(_ buffer: Buffer?, offset: Int, at path: ResourceBindingPath) {
        guard let buffer = buffer else { return }
        self.checkHasCPUAccess(accessType: .write)
        
        assert(!self.flags.contains(.persistent) || buffer.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        
        RenderBackend._backend.argumentBufferImpl.setBuffer(buffer, offset: offset, at: path, on: self)
    }
    
    public func setTexture(_ texture: Texture, at path: ResourceBindingPath) {
        self.checkHasCPUAccess(accessType: .write)
        
        assert(!self.flags.contains(.persistent) || texture.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        RenderBackend._backend.argumentBufferImpl.setTexture(texture, at: path, on: self)
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public func setAccelerationStructure(_ structure: AccelerationStructure, at path: ResourceBindingPath) {
        self.checkHasCPUAccess(accessType: .write)
        
        assert(!self.flags.contains(.persistent) || structure.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        RenderBackend._backend.argumentBufferImpl.setAccelerationStructure(structure, at: path, on: self)
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public func setVisibleFunctionTable(_ table: VisibleFunctionTable, at path: ResourceBindingPath) {
        self.checkHasCPUAccess(accessType: .write)
        
        assert(!self.flags.contains(.persistent) || table.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        RenderBackend._backend.argumentBufferImpl.setVisibleFunctionTable(table, at: path, on: self)
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public func setIntersectionFunctionTable(_ table: IntersectionFunctionTable, at path: ResourceBindingPath) {
        self.checkHasCPUAccess(accessType: .write)
        
        assert(!self.flags.contains(.persistent) || table.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        RenderBackend._backend.argumentBufferImpl.setIntersectionFunctionTable(table, at: path, on: self)
    }
    
    @inlinable
    public func setSampler(_ sampler: SamplerDescriptor, at path: ResourceBindingPath) async {
        self.checkHasCPUAccess(accessType: .write)
        
        let samplerState = await SamplerState(descriptor: sampler)
        self.setSampler(samplerState, at: path)
    }
    
    @inlinable
    public func setSampler(_ sampler: SamplerState, at path: ResourceBindingPath) {
        self.checkHasCPUAccess(accessType: .write)
        
        RenderBackend._backend.argumentBufferImpl.setSampler(sampler, at: path, on: self)
    }
    
    @inlinable
    public func setValue<T>(_ value: T, at path: ResourceBindingPath) {
        precondition(_isPOD(T.self), "Only POD types should be used with setValue.")
        
        withUnsafeBytes(of: value) { bytes in
            self.setBytes(bytes, at: path)
        }
    }
    
    public func setValue<T : ResourceProtocol>(_ value: T, at path: ResourceBindingPath) {
        preconditionFailure("setValue should not be used with resources; use setBuffer or setTexture instead.")
    }
    
    public func setBytes(_ bytes: UnsafeRawBufferPointer, at path: ResourceBindingPath) {
        self.checkHasCPUAccess(accessType: .write)
        
        RenderBackend._backend.argumentBufferImpl.setBytes(bytes, at: path, on: self)
    }
    
    public static var resourceType: ResourceType {
        return .argumentBuffer
    }
}

extension ArgumentBuffer {
    
    public func setBuffers(_ buffers: [Buffer], offsets: [Int], paths: [ResourceBindingPath]) {
        for (buffer, (offset, path)) in zip(buffers, zip(offsets, paths)) {
            self.setBuffer(buffer, offset: offset, at: path)
        }
    }
    
    public func setTextures(_ textures: [Texture], paths: [ResourceBindingPath]) {
        for (texture, path) in zip(textures, paths) {
            self.setTexture(texture, at: path)
        }
    }
    
    public func setSamplers(_ samplers: [SamplerDescriptor], paths: [ResourceBindingPath]) async {
        for (sampler, path) in zip(samplers, paths) {
            await self.setSampler(sampler, at: path)
        }
    }
    
    
    public func setSamplers(_ samplers: [SamplerState], paths: [ResourceBindingPath]) {
        for (sampler, path) in zip(samplers, paths) {
            self.setSampler(sampler, at: path)
        }
    }
}

extension ArgumentBuffer: ResourceProtocolImpl {
    @usableFromInline typealias SharedProperties = ArgumentBufferProperties
    @usableFromInline typealias TransientProperties = ArgumentBufferProperties.TransientArgumentBufferProperties
    @usableFromInline typealias PersistentProperties = ArgumentBufferProperties.PersistentArgumentBufferProperties
    
    @usableFromInline static func transientRegistry(index: Int) -> TransientArgumentBufferRegistry? {
        return TransientArgumentBufferRegistry.instances[index]
    }
    
    @usableFromInline static var persistentRegistry: PersistentRegistry<Self> { PersistentArgumentBufferRegistry.instance }
    
    @usableFromInline typealias Descriptor = ArgumentBufferDescriptor
    
    @usableFromInline static var tracksUsages: Bool { true }
}


extension ArgumentBuffer: CustomStringConvertible {
    public var description: String {
        return "ArgumentBuffer(handle: \(self.handle)) { \(self.label.map { "label: \($0), "} ?? "") flags: \(self.flags) }"
    }
}

// Unlike the other transient registries, the transient argument buffer registry is chunk-based.
// This is because the number of argument buffers used within a frame can vary dramatically, and so a pre-assigned maximum is more likely to be hit.
@usableFromInline final class TransientArgumentBufferRegistry: TransientChunkRegistry<ArgumentBuffer> {
    @usableFromInline static let instances = TransientRegistryArray<TransientArgumentBufferRegistry>()
    
    override class var maxChunks: Int { 2048 }
}

final class PersistentArgumentBufferRegistry: PersistentRegistry<ArgumentBuffer> {
    static let instance = PersistentArgumentBufferRegistry()
    
    override class var maxChunks: Int { 256 }
}

@usableFromInline struct ArgumentBufferProperties: ResourceProperties {
    @usableFromInline struct TransientArgumentBufferProperties: ResourceProperties {
        let backingBufferOffsets: UnsafeMutablePointer<Int>
        
        @usableFromInline
        init(capacity: Int) {
            self.backingBufferOffsets = UnsafeMutablePointer.allocate(capacity: capacity)
        }
        
        @usableFromInline
        func deallocate() {
            self.backingBufferOffsets.deallocate()
        }
        
        @usableFromInline
        func initialize(index: Int, descriptor: ArgumentBufferDescriptor, heap: Heap?, flags: ResourceFlags) {
            self.backingBufferOffsets.advanced(by: index).initialize(to: 0)
        }
        
        @usableFromInline
        func deinitialize(from index: Int, count: Int) {
            self.backingBufferOffsets.advanced(by: index).deinitialize(count: count)
        }
    }
    
    @usableFromInline struct PersistentArgumentBufferProperties: PersistentResourceProperties {
        let heaps : UnsafeMutablePointer<Heap?>
        /// The index that must be completed on the GPU for each queue before the CPU can read from this resource's memory.
        let readWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The index that must be completed on the GPU for each queue before the CPU can write to this resource's memory.
        let writeWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The RenderGraphs that are currently using this resource.
        let activeRenderGraphs : UnsafeMutablePointer<UInt8.AtomicRepresentation>
        
        @usableFromInline init(capacity: Int) {
            self.heaps = .allocate(capacity: capacity)
            self.readWaitIndices = .allocate(capacity: capacity)
            self.writeWaitIndices = .allocate(capacity: capacity)
            self.activeRenderGraphs = .allocate(capacity: capacity)
        }
        
        @usableFromInline func deallocate() {
            self.heaps.deallocate()
            self.readWaitIndices.deallocate()
            self.writeWaitIndices.deallocate()
            self.activeRenderGraphs.deallocate()
        }
        
        @usableFromInline func initialize(index indexInChunk: Int, descriptor: ArgumentBufferDescriptor, heap: Heap?, flags: ResourceFlags) {
            self.heaps.advanced(by: indexInChunk).initialize(to: nil)
            self.readWaitIndices.advanced(by: indexInChunk).initialize(to: SIMD8(repeating: 0))
            self.writeWaitIndices.advanced(by: indexInChunk).initialize(to: SIMD8(repeating: 0))
            self.activeRenderGraphs.advanced(by: indexInChunk).initialize(to: UInt8.AtomicRepresentation(0))
        }
        
        @usableFromInline func initialize(index indexInChunk: Int) {
            self.heaps.advanced(by: indexInChunk).initialize(to: nil)
            self.readWaitIndices.advanced(by: indexInChunk).initialize(to: SIMD8(repeating: 0))
            self.writeWaitIndices.advanced(by: indexInChunk).initialize(to: SIMD8(repeating: 0))
            self.activeRenderGraphs.advanced(by: indexInChunk).initialize(to: UInt8.AtomicRepresentation(0))
        }
        
        @usableFromInline func deinitialize(from indexInChunk: Int, count: Int) {
            self.heaps.advanced(by: indexInChunk).deinitialize(count: count)
        }
        
        @usableFromInline var readWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { self.readWaitIndices }
        @usableFromInline var writeWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { self.writeWaitIndices }
        @usableFromInline var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { self.activeRenderGraphs }
    }
    
    let stateFlags: UnsafeMutablePointer<ResourceStateFlags>
    let maxAllocationLengths: UnsafeMutablePointer<Int>
    @usableFromInline let mappedContents : UnsafeMutablePointer<UnsafeMutableRawPointer?>
    
    #if canImport(Metal)
    let encoders : UnsafeMutablePointer<Unmanaged<MTLArgumentEncoder>?> // Some opaque backend type that can construct the argument buffer
    let usedResources: UnsafeMutablePointer<HashSet<UnsafeMutableRawPointer>>
    let usedHeaps: UnsafeMutablePointer<HashSet<UnsafeMutableRawPointer>>
    #endif
    
    @usableFromInline typealias Descriptor = ArgumentBufferDescriptor
    
    @usableFromInline init(capacity: Int) {
        self.stateFlags = .allocate(capacity: capacity)
        self.maxAllocationLengths = .allocate(capacity: capacity)
        self.mappedContents = UnsafeMutablePointer.allocate(capacity: capacity)

#if canImport(Metal)
        self.encoders = .allocate(capacity: capacity)
        self.usedResources = .allocate(capacity: capacity)
        self.usedHeaps = .allocate(capacity: capacity)
#endif
    }
    
    @usableFromInline func deallocate() {
        self.stateFlags.deallocate()
        self.maxAllocationLengths.deallocate()
        self.mappedContents.deallocate()
        
#if canImport(Metal)
        self.encoders.deallocate()
        self.usedResources.deallocate()
        self.usedHeaps.deallocate()
#endif
    }
    
    @usableFromInline func initialize(index indexInChunk: Int, descriptor: ArgumentBufferDescriptor, heap: Heap?, flags: ResourceFlags) {
        self.stateFlags.advanced(by: indexInChunk).initialize(to: [])
        self.maxAllocationLengths.advanced(by: indexInChunk).initialize(to: .max)
        self.mappedContents.advanced(by: indexInChunk).initialize(to: nil)
        
#if canImport(Metal)
        self.encoders.advanced(by: indexInChunk).initialize(to: nil)
        self.usedResources.advanced(by: indexInChunk).initialize(to: .init()) // TODO: pass in the appropriate allocator.
        self.usedHeaps.advanced(by: indexInChunk).initialize(to: .init())
#endif
    }
    
    @usableFromInline func deinitialize(from index: Int, count: Int) {
        self.stateFlags.advanced(by: index).deinitialize(count: count)
        self.maxAllocationLengths.advanced(by: index).deinitialize(count: count)
        self.mappedContents.advanced(by: index).deinitialize(count: count)
        
#if canImport(Metal)
        self.encoders.advanced(by: index).deinitialize(count: count)
        for i in 0..<count {
            self.usedResources[index + i].deinit()
            self.usedHeaps[index + i].deinit()
        }
        self.usedResources.advanced(by: index).deinitialize(count: count)
        self.usedHeaps.advanced(by: index).deinitialize(count: count)
#endif
    }
}

