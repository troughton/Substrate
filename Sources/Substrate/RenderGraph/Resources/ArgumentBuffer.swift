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
    
    mutating func encode(into argBuffer: ArgumentBuffer) async
}

@available(*, deprecated, renamed: "ArgumentBuffer")
public typealias _ArgumentBuffer = ArgumentBuffer

public struct ArgumentDescriptor: Hashable, Sendable {
    public enum ArgumentResourceType: Hashable, Sendable {
        case inlineData(type: DataType)
        case constantBuffer(alignment: Int = 0)
        case storageBuffer
#if canImport(Metal)
        case argumentBuffer
#endif
        case texture(type: TextureType)
        case sampler
        case accelerationStructure
    }
    
    public var resourceType: ArgumentResourceType // VkDescriptorSetLayoutBinding.descriptorType
    public var index: Int // VkDescriptorSetLayoutBinding.binding
    public var arrayLength: Int // VkDescriptorSetLayoutBinding.descriptorCount
    public var accessType: ResourceAccessType // VkDescriptorSetLayoutBinding.descriptorType
    @usableFromInline var encodedBufferAlignment: Int
    @usableFromInline var encodedBufferOffset: Int
    @usableFromInline var encodedBufferStride: Int
    
    public init(resourceType: ArgumentResourceType, index: Int? = nil, arrayLength: Int = 1, accessType: ResourceAccessType = .read) {
        self.resourceType = resourceType
        self.index = index ?? -1
        self.arrayLength = arrayLength
        self.accessType = accessType
        self.encodedBufferOffset = -1
        self.encodedBufferStride = 0
        self.encodedBufferAlignment = 0
        
        let sizeAndAlign = RenderBackend._backend!.argumentBufferImpl.encodedBufferSizeAndAlign(forArgument: self)
        self.encodedBufferAlignment = sizeAndAlign.alignment
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
        case .argumentBuffer:
            return "argumentBuffer"
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
    @usableFromInline var _arguments: [ArgumentDescriptor]
    
    public var arguments: [ArgumentDescriptor] {
        get {
            self._arguments
        }
        set {
            self._arguments = newValue
            self.calculateBufferOffsets()
        }
    }
    public var storageMode: StorageMode
    
    @usableFromInline var _elementStride: Int
    @usableFromInline var _alignment: Int
    @usableFromInline var totalArgumentCount: Int
    
    @inlinable
    public var bufferAlignment: Int {
        return self._alignment
    }
    
    @inlinable
    public var bufferLength: Int {
        return self._elementStride
    }
    
    @inlinable
    public init(arguments: [ArgumentDescriptor], storageMode: StorageMode = .shared) {
        self._arguments = arguments
        self.storageMode = storageMode
        
        self._elementStride = 0
        self._alignment = 16
        self.totalArgumentCount = 0
        self.calculateBufferOffsets()
    }
    
    @inlinable
    mutating func calculateBufferOffsets() {
        var offset = 0
        var nextIndex = 0
        var maxAlign = 0
        for i in self._arguments.indices {
            precondition(self._arguments[i].index < 0 || self._arguments[i].index >= nextIndex, "Arguments must be in order of ascending index.")
            self._arguments[i].index = max(self._arguments[i].index, nextIndex)
            
            maxAlign = max(maxAlign, self._arguments[i].encodedBufferAlignment)
            
            offset = offset.roundedUpToMultiple(of: self._arguments[i].encodedBufferAlignment)
            self._arguments[i].encodedBufferOffset = offset
            nextIndex = self._arguments[i].index + self._arguments[i].arrayLength
            offset += self._arguments[i].encodedBufferStride * self._arguments[i].arrayLength
        }
        
        self.totalArgumentCount = nextIndex
        self._alignment = maxAlign
        
        let elementStride = offset.roundedUpToMultiple(of: maxAlign)
        self._elementStride = elementStride
    }
}

public struct ArgumentBuffer : ResourceProtocol {
    public let handle: ResourceHandle
    
    public enum ArgumentResource {
        case buffer(Buffer, offset: Int)
        case texture(Texture)
#if canImport(Metal)
        case argumentBuffer(ArgumentBuffer)
#endif
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
#if canImport(Metal)
            case .argumentBuffer(let argumentBuffer):
                return Resource(argumentBuffer)
#endif
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
        assert(handle.resourceType == .argumentBuffer)
        self.handle = handle
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
    }
        
#if canImport(Metal)
        public init(descriptor: ArgumentBufferDescriptor, buffer: Buffer, offset: Int, renderGraph: RenderGraph? = nil) {
            let flags : ResourceFlags = .resourceView
            
            guard let renderGraph = renderGraph ?? RenderGraph.activeRenderGraph else {
                fatalError("The RenderGraph must be specified for transient resources created outside of a render pass' execute() method.")
            }
            precondition(renderGraph.transientRegistryIndex >= 0, "Transient resources are not supported on the RenderGraph \(renderGraph)")
            
            self = TransientArgumentBufferRegistry.instances[renderGraph.transientRegistryIndex].allocate(descriptor: descriptor, flags: flags)
            
            if buffer.backingResourcePointer != nil {
                renderGraph.context.transientRegistry!.accessLock.withLock {
                    _ = renderGraph.context.transientRegistry!.allocateArgumentBufferView(argumentBuffer: self, buffer: buffer, offset: offset)
                }
            }
            self.baseResource = Resource(buffer)
        }
#endif
    
    public init<A : ArgumentBufferEncodable>(encoding arguments: A, renderGraph: RenderGraph? = nil, flags: ResourceFlags = []) async {
        self.init(descriptor: A.argumentBufferDescriptor, renderGraph: renderGraph, flags: flags)

#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
    self.label = "Resource Set for \(String(reflecting: A.self))"
#endif
        
        var arguments = arguments
        await arguments.encode(into: self)
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
    var encodedResourcesLock: SpinLock {
        get {
            return SpinLock(initializedLockAt: self.pointer(for: \.encodedResourcesLocks))
        }
    }
    
    var encodedResources: [Resource?] {
        _read {
            yield self.pointer(for: \.encodedResources).pointee
        }
        nonmutating _modify {
            yield &self.pointer(for: \.encodedResources).pointee
        }
    }
    
    var usedResources: HashSet<UnsafeMutableRawPointer> {
        _read {
            yield self.pointer(for: \.usedResources).pointee
        }
        nonmutating _modify {
            yield &self.pointer(for: \.usedResources).pointee
        }
    }
    
    var usedHeaps: HashSet<UnsafeMutableRawPointer> {
        _read {
            yield self.pointer(for: \.usedHeaps).pointee
        }
        nonmutating _modify {
            yield &self.pointer(for: \.usedHeaps).pointee
        }
    }
    
#endif
    
    func _reset(includingEncodedResources: Bool, includingParent: Bool) {
        // TODO: should we zero out the buffer?
#if canImport(Metal)
        self.encodedResourcesLock.withLock {
            if includingEncodedResources {
                for i in self.encodedResources.indices {
                    self.encodedResources[i] = nil
                }
            }
            
            self.usedResources.removeAll()
            self.usedHeaps.removeAll()
        }
        
        if includingParent, let array = self.baseResource.flatMap({ ArgumentBufferArray($0) }) {
            array.encodedResourcesLock.withLock {
                array.usedResources.removeAll()
                array.usedHeaps.removeAll()
            }
        }
#endif
    }
    
    public func reset() {
        self._reset(includingEncodedResources: true, includingParent: true)
    }
     
    public var storageMode: StorageMode {
        return self.descriptor.storageMode
    }
    
    public var baseResource: Resource? {
        get {
            return self.pointer(for: \.baseResources).pointee
        } nonmutating set {
            self.pointer(for: \.baseResources).pointee = newValue
        }
    }
    
    private func updateAccessWaitIndices<R: ResourceProtocolImpl>(resource: R, at index: Int) {
        guard resource._usesPersistentRegistry else { return }
        
        let argument = self.descriptor.arguments[self.descriptor.arguments.binarySearch(predicate: { $0.index <= index }) - 1]
        
        if argument.accessType == .read, let waitPointer = resource._readWaitIndicesPointer {
            let waitIndices = QueueCommandIndex.AtomicRepresentation.snapshotIndices(at: waitPointer, ordering: .relaxed)
            self[\.contentAccessWaitIndices] = pointwiseMax(waitIndices, self[\.contentAccessWaitIndices])
        }
        
        if argument.accessType == .readWrite || argument.accessType == .write, let waitPointer = resource._writeWaitIndicesPointer {
            let waitIndices = QueueCommandIndex.AtomicRepresentation.snapshotIndices(at: waitPointer, ordering: .relaxed)
            self[\.contentAccessWaitIndices] = pointwiseMax(waitIndices, self[\.contentAccessWaitIndices])
        }
    }
    
    public func setBuffer(_ buffer: Buffer?, offset: Int, at index: Int, arrayIndex: Int = 0) {
        guard let buffer = buffer else { return }
        self.checkHasCPUAccess(accessType: .write)
        
        assert(!self.flags.contains(.persistent) || buffer.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        
        self.updateAccessWaitIndices(resource: buffer, at: index)
        RenderBackend._backend.argumentBufferImpl.setBuffer(buffer, offset: offset, at: index, arrayIndex: arrayIndex, on: self)
    }
    
    public func setTexture(_ texture: Texture, at index: Int, arrayIndex: Int = 0) {
        self.checkHasCPUAccess(accessType: .write)
        
        assert(!self.flags.contains(.persistent) || texture.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        
        self.updateAccessWaitIndices(resource: texture, at: index)
        RenderBackend._backend.argumentBufferImpl.setTexture(texture, at: index, arrayIndex: arrayIndex, on: self)
    }
    
#if canImport(Metal)
    @available(macOS 11.0, iOS 14.0, *)
    public func setArgumentBuffer(_ buffer: ArgumentBuffer, at index: Int, arrayIndex: Int = 0) {
        self.checkHasCPUAccess(accessType: .write)
        
        assert(!self.flags.contains(.persistent) || (buffer.baseResource?.flags ?? buffer.flags).contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        
        self.updateAccessWaitIndices(resource: buffer, at: index)
        RenderBackend._backend.argumentBufferImpl.setArgumentBuffer(buffer, at: index, arrayIndex: arrayIndex, on: self)
    }
#endif
    
    @available(macOS 11.0, iOS 14.0, *)
    public func setAccelerationStructure(_ structure: AccelerationStructure, at index: Int, arrayIndex: Int = 0) {
        self.checkHasCPUAccess(accessType: .write)
        
        assert(!self.flags.contains(.persistent) || structure.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        
        self.updateAccessWaitIndices(resource: structure, at: index)
        RenderBackend._backend.argumentBufferImpl.setAccelerationStructure(structure, at: index, arrayIndex: arrayIndex, on: self)
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public func setVisibleFunctionTable(_ table: VisibleFunctionTable, at index: Int, arrayIndex: Int = 0) {
        self.checkHasCPUAccess(accessType: .write)
        
        assert(!self.flags.contains(.persistent) || table.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        
        self.updateAccessWaitIndices(resource: table, at: index)
        RenderBackend._backend.argumentBufferImpl.setVisibleFunctionTable(table, at: index, arrayIndex: arrayIndex, on: self)
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public func setIntersectionFunctionTable(_ table: IntersectionFunctionTable, at index: Int, arrayIndex: Int = 0) {
        self.checkHasCPUAccess(accessType: .write)
        
        assert(!self.flags.contains(.persistent) || table.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        
        self.updateAccessWaitIndices(resource: table, at: index)
        RenderBackend._backend.argumentBufferImpl.setIntersectionFunctionTable(table, at: index, arrayIndex: arrayIndex, on: self)
    }
    
    @inlinable
    public func setSampler(_ sampler: SamplerDescriptor, at index: Int, arrayIndex: Int = 0) async {
        self.checkHasCPUAccess(accessType: .write)
        
        let samplerState = await SamplerState(descriptor: sampler)
        self.setSampler(samplerState, at: index, arrayIndex: arrayIndex)
    }
    
    @inlinable
    public func setSampler(_ sampler: SamplerState, at index: Int, arrayIndex: Int = 0) {
        self.checkHasCPUAccess(accessType: .write)
        
        RenderBackend._backend.argumentBufferImpl.setSampler(sampler, at: index, arrayIndex: arrayIndex, on: self)
    }
    
    @inlinable
    public func setValue<T>(_ value: T, at index: Int, arrayIndex: Int = 0) {
        precondition(_isPOD(T.self), "Only POD types should be used with setValue.")
        
        withUnsafeBytes(of: value) { bytes in
            self.setBytes(bytes, at: index, arrayIndex: arrayIndex)
        }
    }
    
    public func setValue<T : ResourceProtocol>(_ value: T, at index: Int, arrayIndex: Int = 0) {
        preconditionFailure("setValue should not be used with resources; use setBuffer or setTexture instead.")
    }
    
    public func setBytes(_ bytes: UnsafeRawBufferPointer, at index: Int, arrayIndex: Int = 0) {
        self.checkHasCPUAccess(accessType: .write)
        
        RenderBackend._backend.argumentBufferImpl.setBytes(bytes, at: index, arrayIndex: arrayIndex, on: self)
    }
    
    public static var resourceType: ResourceType {
        return .argumentBuffer
    }
}

extension ArgumentBuffer: ResourceProtocolImpl {
    @usableFromInline typealias SharedProperties = ArgumentBufferProperties
    @usableFromInline typealias TransientProperties = EmptyProperties<ArgumentBufferDescriptor>
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
    @usableFromInline struct PersistentArgumentBufferProperties: PersistentResourceProperties {
        let heaps : UnsafeMutablePointer<Heap?>
        /// The index that must be completed on the GPU for each queue before the CPU can read from this resource's memory.
        let readWaitIndices : UnsafeMutablePointer<QueueCommandIndex.AtomicRepresentation>
        /// The index that must be completed on the GPU for each queue before the CPU can write to this resource's memory.
        let writeWaitIndices : UnsafeMutablePointer<QueueCommandIndex.AtomicRepresentation>
        /// The RenderGraphs that are currently using this resource.
        let activeRenderGraphs : UnsafeMutablePointer<UInt8.AtomicRepresentation>
        
        @usableFromInline init(capacity: Int) {
            self.heaps = .allocate(capacity: capacity)
            self.readWaitIndices = .allocate(capacity: capacity * QueueCommandIndices.scalarCount)
            self.writeWaitIndices = .allocate(capacity: capacity * QueueCommandIndices.scalarCount)
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
            self.readWaitIndices.advanced(by: indexInChunk * QueueCommandIndices.scalarCount).initialize(repeating: .init(0), count: QueueCommandIndices.scalarCount)
            self.writeWaitIndices.advanced(by: indexInChunk * QueueCommandIndices.scalarCount).initialize(repeating: .init(0), count: QueueCommandIndices.scalarCount)
            self.activeRenderGraphs.advanced(by: indexInChunk).initialize(to: UInt8.AtomicRepresentation(0))
        }
        
        @usableFromInline func initialize(index indexInChunk: Int) {
            self.heaps.advanced(by: indexInChunk).initialize(to: nil)
            self.readWaitIndices.advanced(by: indexInChunk * QueueCommandIndices.scalarCount).initialize(repeating: .init(0), count: QueueCommandIndices.scalarCount)
            self.writeWaitIndices.advanced(by: indexInChunk * QueueCommandIndices.scalarCount).initialize(repeating: .init(0), count: QueueCommandIndices.scalarCount)
            self.activeRenderGraphs.advanced(by: indexInChunk).initialize(to: UInt8.AtomicRepresentation(0))
        }
        
        @usableFromInline func deinitialize(from indexInChunk: Int, count: Int) {
            self.heaps.advanced(by: indexInChunk).deinitialize(count: count)
        }
        
        @usableFromInline var readWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndex.AtomicRepresentation>? { self.readWaitIndices }
        @usableFromInline var writeWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndex.AtomicRepresentation>? { self.writeWaitIndices }
        @usableFromInline var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { self.activeRenderGraphs }
    }
    
    let stateFlags: UnsafeMutablePointer<ResourceStateFlags>
    let contentAccessWaitIndices: UnsafeMutablePointer<QueueCommandIndices>
    @usableFromInline let mappedContents : UnsafeMutablePointer<UnsafeMutableRawPointer?>
    let backingBufferOffsets: UnsafeMutablePointer<Int>
    let baseResources: UnsafeMutablePointer<Resource?>
    
    #if canImport(Metal)
    let encoders : UnsafeMutablePointer<Unmanaged<MTLArgumentEncoder>?> // Some opaque backend type that can construct the argument buffer
    let encodedResources: UnsafeMutablePointer<[Resource?]>
    let encodedResourcesLocks: UnsafeMutablePointer<SpinLock.Storage>
    let usedResources: UnsafeMutablePointer<HashSet<UnsafeMutableRawPointer>>
    let usedHeaps: UnsafeMutablePointer<HashSet<UnsafeMutableRawPointer>>
    #endif
    
    @usableFromInline typealias Descriptor = ArgumentBufferDescriptor
    
    @usableFromInline init(capacity: Int) {
        self.stateFlags = .allocate(capacity: capacity)
        self.contentAccessWaitIndices = .allocate(capacity: capacity)
        self.mappedContents = .allocate(capacity: capacity)
        
        self.backingBufferOffsets = .allocate(capacity: capacity)
        self.baseResources = .allocate(capacity: capacity)

#if canImport(Metal)
        self.encoders = .allocate(capacity: capacity)
        self.encodedResources = .allocate(capacity: capacity)
        self.encodedResourcesLocks = .allocate(capacity: capacity)
        self.usedResources = .allocate(capacity: capacity)
        self.usedHeaps = .allocate(capacity: capacity)
#endif
    }
    
    @usableFromInline func deallocate() {
        self.stateFlags.deallocate()
        self.contentAccessWaitIndices.deallocate()
        self.mappedContents.deallocate()
        
        self.backingBufferOffsets.deallocate()
        self.baseResources.deallocate()
        
#if canImport(Metal)
        self.encoders.deallocate()
        self.encodedResources.deallocate()
        self.encodedResourcesLocks.deallocate()
        self.usedResources.deallocate()
        self.usedHeaps.deallocate()
#endif
    }
    
    @usableFromInline func initialize(index indexInChunk: Int, descriptor: ArgumentBufferDescriptor, heap: Heap?, flags: ResourceFlags) {
        self.stateFlags.advanced(by: indexInChunk).initialize(to: [])
        self.contentAccessWaitIndices.advanced(by: indexInChunk).initialize(to: .zero)
        self.mappedContents.advanced(by: indexInChunk).initialize(to: nil)
        
        self.backingBufferOffsets.advanced(by: indexInChunk).initialize(to: 0)
        self.baseResources.advanced(by: indexInChunk).initialize(to: nil)
        
#if canImport(Metal)
        self.encoders.advanced(by: indexInChunk).initialize(to: nil)
        let _ = SpinLock(at: self.encodedResourcesLocks.advanced(by: indexInChunk))
        self.encodedResources.advanced(by: indexInChunk).initialize(to: .init(repeating: nil, count: descriptor.totalArgumentCount))
        self.usedResources.advanced(by: indexInChunk).initialize(to: .init()) // TODO: pass in the appropriate allocator.
        self.usedHeaps.advanced(by: indexInChunk).initialize(to: .init())
#endif
    }
    
    @usableFromInline func deinitialize(from index: Int, count: Int) {
        self.stateFlags.advanced(by: index).deinitialize(count: count)
        self.contentAccessWaitIndices.advanced(by: index).deinitialize(count: count)
        self.mappedContents.advanced(by: index).deinitialize(count: count)
        
        self.backingBufferOffsets.advanced(by: index).deinitialize(count: count)
        self.baseResources.advanced(by: index).deinitialize(count: count)
        
#if canImport(Metal)
        self.encoders.advanced(by: index).deinitialize(count: count)
        for i in 0..<count {
            self.usedResources[index + i].deinit()
            self.usedHeaps[index + i].deinit()
        }
        self.encodedResources.advanced(by: index).deinitialize(count: count)
        self.usedResources.advanced(by: index).deinitialize(count: count)
        self.usedHeaps.advanced(by: index).deinitialize(count: count)
#endif
    }
}

