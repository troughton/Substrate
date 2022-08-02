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
@preconcurrency import Metal

public struct MetalIndexedFunctionArgument {
    public var type: MTLArgumentType
    public var index : Int
    public var stages : RenderStages
    
    public init(type: MTLArgumentType, index: Int, stages: RenderStages) {
        self.type = type
        self.index = index
        self.stages = stages
    }
    
    public var stringValue : String {
        return "\(type)_arg\(index)"
    }
    
    public func bindingPath(arrayIndex: Int, argumentBufferPath: ResourceBindingPath?) -> ResourceBindingPath? {
        return ResourceBindingPath(stages: MTLRenderStages(self.stages), type: self.type, argumentBufferIndex: nil, index: self.index + arrayIndex)
    }
}
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
    
    public init(resourceType: ArgumentResourceType, index: Int? = nil, arrayLength: Int = 1, accessType: ResourceAccessType = .read) {
        self.resourceType = resourceType
        self.index = index ?? -1
        self.arrayLength = arrayLength
        self.accessType = accessType
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
    
    @inlinable
    public init(arguments: [ArgumentDescriptor]) {
        self.arguments = arguments
        
        var nextIndex = 0
        for i in self.arguments.indices {
            precondition(self.arguments[i].index < 0 || self.arguments[i].index >= nextIndex, "Arguments must be in order of ascending index.")
            self.arguments[i].index = max(self.arguments[i].index, nextIndex)
            nextIndex = self.arguments[i].index + 1
        }
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
   
    public init(bindingPath: ResourceBindingPath, pipelineReflection: PipelineReflection, renderGraph: RenderGraph? = nil) {
        
        guard let renderGraph = renderGraph ?? RenderGraph.activeRenderGraph else {
            fatalError("The RenderGraph must be specified for transient resources created outside of a render pass' execute() method.")
        }
        guard let encoder = pipelineReflection.argumentBufferEncoder(at: bindingPath, currentEncoder: nil) else {
            preconditionFailure("Binding path \(bindingPath) does not represent an argument buffer binding in the provided pipeline reflection.")
        }
        precondition(renderGraph.transientRegistryIndex >= 0, "Transient resources are not supported on the RenderGraph \(renderGraph)")
        
        self = TransientArgumentBufferRegistry.instances[renderGraph.transientRegistryIndex].allocate(descriptor: .init(arguments: []), flags: [])
        
        assert(self.encoder == nil)
        self.replaceEncoder(with: encoder, expectingCurrentValue: nil)
    }
    
    public init(descriptor: ArgumentBufferDescriptor, renderGraph: RenderGraph? = nil, flags: ResourceFlags = []) {
        precondition(!flags.contains(.historyBuffer), "Argument Buffers cannot be used as history buffers.")
        
        if flags.contains(.persistent) {
            self = PersistentArgumentBufferRegistry.instance.allocate(descriptor: descriptor, heap: nil, flags: flags)
        } else {
            guard let renderGraph = renderGraph ?? RenderGraph.activeRenderGraph else {
                fatalError("The RenderGraph must be specified for transient resources created outside of a render pass' execute() method.")
            }
            precondition(renderGraph.transientRegistryIndex >= 0, "Transient resources are not supported on the RenderGraph \(renderGraph)")
            
            self = TransientArgumentBufferRegistry.instances[renderGraph.transientRegistryIndex].allocate(descriptor: descriptor, flags: flags)
        }
        
        assert(self.encoder == nil)
    }
    
    public init<A : ArgumentBufferEncodable>(encoding arguments: A, setIndex: Int, renderGraph: RenderGraph? = nil, flags: ResourceFlags = []) async {
        self.init(descriptor: A.argumentBufferDescriptor, renderGraph: renderGraph, flags: flags)

#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
    self.label = "Descriptor Set for \(String(reflecting: A.self))"
#endif
        
        var arguments = arguments
        await arguments.encode(into: self, setIndex: setIndex, bindingEncoder: nil)
    }
    
    public var descriptor: ArgumentBufferDescriptor {
        _read {
            yield self.pointer(for: \.descriptors).pointee
        }
    }
    
    public var stateFlags: ResourceStateFlags {
        get {
            return self.pointer(for: \.stateFlags).pointee
        }
        nonmutating set {
            self.pointer(for: \.stateFlags).pointee = newValue
        }
    }
    
    public var encoder : UnsafeRawPointer? {
        get {
            return UnsafeRawPointer.AtomicOptionalRepresentation.atomicLoad(at: self.pointer(for: \.encoders), ordering: .relaxed)
        }
    }
    
    /// Updates the encoder to also support encoding to bindingPath.
    func updateEncoder(pipelineReflection: PipelineReflection, bindingPath: ResourceBindingPath) {
        var hasSetEncoder = false
        repeat {
            let currentEncoder = self.encoder
            let newEncoder = pipelineReflection.argumentBufferEncoder(at: bindingPath, currentEncoder: currentEncoder)!
            hasSetEncoder = (newEncoder == currentEncoder) || self.replaceEncoder(with: newEncoder, expectingCurrentValue: currentEncoder)
        } while !hasSetEncoder
    }
    
    /// Allows us to perform a compare-and-swap on the argument buffer encoder.
    func replaceEncoder(with newEncoder: UnsafeRawPointer, expectingCurrentValue: UnsafeRawPointer?) -> Bool {
        return UnsafeRawPointer.AtomicOptionalRepresentation.atomicWeakCompareExchange(expected: expectingCurrentValue, desired: newEncoder, at: self.pointer(for: \.encoders), successOrdering: .relaxed, failureOrdering: .relaxed).exchanged
    }
    
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
    
    public var bindings : ExpandingBuffer<(ResourceBindingPath, ArgumentBuffer.ArgumentResource)> {
        _read {
            yield self.pointer(for: \.bindings).pointee
        }
    }
     
    public var storageMode: StorageMode {
        return .shared
    }
    
    public func _bytes(offset: Int) -> UnsafeRawPointer {
        if self._usesPersistentRegistry {
            return self.pointer(for: \.inlineDataStorage)!.pointee.withUnsafeBytes { return $0.baseAddress! + offset }
        } else {
            return UnsafeRawPointer(TransientArgumentBufferRegistry.instances[self.transientRegistryIndex].inlineDataAllocator.buffer!) + offset
        }
    }
    
    /// returns the offset in bytes into the buffer's storage
    public func _copyBytes(_ bytes: UnsafeRawPointer, length: Int) -> Int {
        if self._usesPersistentRegistry {
            return PersistentArgumentBufferRegistry.instance.lock.withLock {
                let inlineDataStorage = self.pointer(for: \.inlineDataStorage)!
                let offset = inlineDataStorage.pointee.count
                inlineDataStorage.pointee.append(bytes.assumingMemoryBound(to: UInt8.self), count: length)
                return offset
            }
        } else {
            return TransientArgumentBufferRegistry.instances[self.transientRegistryIndex].lock.withLock {
                let offset = TransientArgumentBufferRegistry.instances[self.transientRegistryIndex].inlineDataAllocator.count
                TransientArgumentBufferRegistry.instances[self.transientRegistryIndex].inlineDataAllocator.append(from: bytes.assumingMemoryBound(to: UInt8.self), count: length)
                return offset
            }
        }
    }
    
    public func setBuffer(_ buffer: Buffer?, offset: Int, at path: ResourceBindingPath) {
        guard let buffer = buffer else { return }
        
        assert(!self.flags.contains(.persistent) || buffer.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        self.bindings.append(
            (path, .buffer(buffer, offset: offset))
        )
    }
    
    public func setTexture(_ texture: Texture, at path: ResourceBindingPath) {
        assert(!self.flags.contains(.persistent) || texture.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        self.bindings.append(
            (path, .texture(texture))
        )
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public func setAccelerationStructure(_ structure: AccelerationStructure, at path: ResourceBindingPath) {
        assert(!self.flags.contains(.persistent) || structure.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        self.bindings.append(
            (path, .accelerationStructure(structure))
        )
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public func setVisibleFunctionTable(_ table: VisibleFunctionTable, at path: ResourceBindingPath) {
        assert(!self.flags.contains(.persistent) || table.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        self.bindings.append(
            (path, .visibleFunctionTable(table))
        )
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public func setIntersectionFunctionTable(_ table: IntersectionFunctionTable, at path: ResourceBindingPath) {
        assert(!self.flags.contains(.persistent) || table.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        self.bindings.append(
            (path, .intersectionFunctionTable(table))
        )
    }
    
    @inlinable
    public func setSampler(_ sampler: SamplerDescriptor, at path: ResourceBindingPath) async {
        let samplerState = await SamplerState(descriptor: sampler)
        self.setSampler(samplerState, at: path)
    }
    
    @inlinable
    public func setSampler(_ sampler: SamplerState, at path: ResourceBindingPath) {
        self.bindings.append(
            (path, .sampler(sampler))
        )
    }
    
    public func setValue<T>(_ value: T, at path: ResourceBindingPath) {
        assert(_isPOD(T.self), "Only POD types should be used with setValue.")
        
        var value = value
        withUnsafeBytes(of: &value) { bufferPointer in
            self.setBytes(bufferPointer.baseAddress!, length: bufferPointer.count, at: path)
        }
    }
    
    public func setValue<T : ResourceProtocol>(_ value: T, at path: ResourceBindingPath) {
        preconditionFailure("setValue should not be used with resources; use setBuffer or setTexture instead.")
    }
    
    public func setBytes(_ bytes: UnsafeRawPointer, length: Int, at path: ResourceBindingPath) {
        let currentOffset = self._copyBytes(bytes, length: length)
        self.bindings.append(
            (path, .bytes(offset: currentOffset, length: length))
        )
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
    typealias SharedProperties = ArgumentBufferProperties
    typealias TransientProperties = EmptyProperties<ArgumentBufferDescriptor>
    typealias PersistentProperties = ArgumentBufferProperties.PersistentArgumentBufferProperties
    
    static func transientRegistry(index: Int) -> TransientArgumentBufferRegistry? {
        return TransientArgumentBufferRegistry.instances[index]
    }
    
    static var persistentRegistry: PersistentRegistry<Self> { PersistentArgumentBufferRegistry.instance }
    
    typealias Descriptor = ArgumentBufferDescriptor
}


extension ArgumentBuffer: CustomStringConvertible {
    public var description: String {
        return "ArgumentBuffer(handle: \(self.handle)) { \(self.label.map { "label: \($0), "} ?? "")bindings: \(self.bindings), flags: \(self.flags) }"
    }
}

// Unlike the other transient registries, the transient argument buffer registry is chunk-based.
// This is because the number of argument buffers used within a frame can vary dramatically, and so a pre-assigned maximum is more likely to be hit.
final class TransientArgumentBufferRegistry: TransientChunkRegistry<ArgumentBuffer> {
    static let instances = TransientRegistryArray<TransientArgumentBufferRegistry>()
    
    override class var maxChunks: Int { 2048 }
    
    let inlineDataAllocator : ExpandingBuffer<UInt8> = .init()
}

final class PersistentArgumentBufferRegistry: PersistentRegistry<ArgumentBuffer> {
    static let instance = PersistentArgumentBufferRegistry()
    
    override class var maxChunks: Int { 256 }
}

struct ArgumentBufferProperties: SharedResourceProperties {
    struct PersistentArgumentBufferProperties: PersistentResourceProperties {
        let inlineDataStorage : UnsafeMutablePointer<Data>
        let heaps : UnsafeMutablePointer<Heap?>
        /// The index that must be completed on the GPU for each queue before the CPU can read from this resource's memory.
        let readWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The index that must be completed on the GPU for each queue before the CPU can write to this resource's memory.
        let writeWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The RenderGraphs that are currently using this resource.
        let activeRenderGraphs : UnsafeMutablePointer<UInt8.AtomicRepresentation>
        
        init(capacity: Int) {
            self.inlineDataStorage = .allocate(capacity: capacity)
            self.heaps = .allocate(capacity: capacity)
            self.readWaitIndices = .allocate(capacity: capacity)
            self.writeWaitIndices = .allocate(capacity: capacity)
            self.activeRenderGraphs = .allocate(capacity: capacity)
        }
        
        func deallocate() {
            self.inlineDataStorage.deallocate()
            self.heaps.deallocate()
            self.readWaitIndices.deallocate()
            self.writeWaitIndices.deallocate()
            self.activeRenderGraphs.deallocate()
        }
        
        func initialize(index indexInChunk: Int, descriptor: ArgumentBufferDescriptor, heap: Heap?, flags: ResourceFlags) {
            self.inlineDataStorage.advanced(by: indexInChunk).initialize(to: Data())
            self.heaps.advanced(by: indexInChunk).initialize(to: nil)
            self.readWaitIndices.advanced(by: indexInChunk).initialize(to: SIMD8(repeating: 0))
            self.writeWaitIndices.advanced(by: indexInChunk).initialize(to: SIMD8(repeating: 0))
            self.activeRenderGraphs.advanced(by: indexInChunk).initialize(to: UInt8.AtomicRepresentation(0))
        }
        
        func initialize(index indexInChunk: Int) {
            self.inlineDataStorage.advanced(by: indexInChunk).initialize(to: Data())
            self.heaps.advanced(by: indexInChunk).initialize(to: nil)
            self.readWaitIndices.advanced(by: indexInChunk).initialize(to: SIMD8(repeating: 0))
            self.writeWaitIndices.advanced(by: indexInChunk).initialize(to: SIMD8(repeating: 0))
            self.activeRenderGraphs.advanced(by: indexInChunk).initialize(to: UInt8.AtomicRepresentation(0))
        }
        
        func deinitialize(from indexInChunk: Int, count: Int) {
            self.inlineDataStorage.advanced(by: indexInChunk).deinitialize(count: count)
            self.heaps.advanced(by: indexInChunk).deinitialize(count: count)
        }
        
        var readWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { self.readWaitIndices }
        var writeWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { self.writeWaitIndices }
        var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { self.activeRenderGraphs }
    }
    
    let usages : UnsafeMutablePointer<ChunkArray<RecordedResourceUsage>>
    let descriptors: UnsafeMutablePointer<ArgumentBufferDescriptor>
    let encoders : UnsafeMutablePointer<UnsafeRawPointer.AtomicOptionalRepresentation> // Some opaque backend type that can construct the argument buffer
    let stateFlags: UnsafeMutablePointer<ResourceStateFlags>
    let maxAllocationLengths: UnsafeMutablePointer<Int>
    let bindings : UnsafeMutablePointer<ExpandingBuffer<(ResourceBindingPath, ArgumentBuffer.ArgumentResource)>>
    
    typealias Descriptor = ArgumentBufferDescriptor
    
    init(capacity: Int) {
        self.usages = .allocate(capacity: capacity)
        self.descriptors = .allocate(capacity: capacity)
        self.encoders = .allocate(capacity: capacity)
        self.stateFlags = .allocate(capacity: capacity)
        self.maxAllocationLengths = .allocate(capacity: capacity)
        self.bindings = .allocate(capacity: capacity)
    }
    
    func deallocate() {
        self.usages.deallocate()
        self.descriptors.deallocate()
        self.encoders.deallocate()
        self.stateFlags.deallocate()
        self.maxAllocationLengths.deallocate()
        self.bindings.deallocate()
    }
    
    func initialize(index indexInChunk: Int, descriptor: ArgumentBufferDescriptor, heap: Heap?, flags: ResourceFlags) {
        self.usages.advanced(by: indexInChunk).initialize(to: ChunkArray())
        self.descriptors.advanced(by: indexInChunk).initialize(to: descriptor)
        self.encoders.advanced(by: indexInChunk).initialize(to: UnsafeRawPointer.AtomicOptionalRepresentation(nil))
        self.stateFlags.advanced(by: indexInChunk).initialize(to: [])
        self.maxAllocationLengths.advanced(by: indexInChunk).initialize(to: .max)
        self.bindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
    }
    
    func deinitialize(from index: Int, count: Int) {
        self.usages.advanced(by: index).deinitialize(count: count)
        self.descriptors.advanced(by: index).deinitialize(count: count)
        self.encoders.advanced(by: index).deinitialize(count: count)
        self.stateFlags.advanced(by: index).deinitialize(count: count)
        self.maxAllocationLengths.advanced(by: index).deinitialize(count: count)
        self.bindings.advanced(by: index).deinitialize(count: count)
    }
    
    var usagesOptional: UnsafeMutablePointer<ChunkArray<RecordedResourceUsage>>? { self.usages }
}

