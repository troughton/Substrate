//
//  ArgumentEncoder.swift
//  RenderAPI
//
//  Created by Thomas Roughton on 22/02/18.
//

import Foundation
import SubstrateUtilities
import Atomics

public protocol FunctionArgumentKey {
    var stringValue : String { get }
    func bindingPath(arrayIndex: Int, argumentBufferPath: ResourceBindingPath?) -> ResourceBindingPath?
}

extension RawRepresentable where Self.RawValue == String {
    public var stringValue : String {
        return self.rawValue
    }
}

#if canImport(Metal)
import Metal

public struct MetalIndexedFunctionArgument : FunctionArgumentKey {
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

extension FunctionArgumentKey {
    
    public func bindingPath(arrayIndex: Int, argumentBufferPath: ResourceBindingPath?) -> ResourceBindingPath? {
        return nil
    }
    
    func bindingPath(argumentBufferPath: ResourceBindingPath?, arrayIndex: Int, pipelineReflection: PipelineReflection) -> ResourceBindingPath? {
        return self.bindingPath(arrayIndex: arrayIndex, argumentBufferPath: argumentBufferPath) ?? pipelineReflection.bindingPath(argumentName: self.stringValue, arrayIndex: arrayIndex, argumentBufferPath: argumentBufferPath)
    }
    
    func computedBindingPath(pipelineReflection: PipelineReflection) -> ResourceBindingPath? {
        return self.bindingPath(arrayIndex: 0, argumentBufferPath: nil) ?? pipelineReflection.bindingPath(argumentName: self.stringValue, arrayIndex: 0, argumentBufferPath: nil)
    }
}

extension String : FunctionArgumentKey {
    public var stringValue : String {
        return self
    }
}

public protocol ArgumentBufferEncodable {
    static var activeStages : RenderStages { get }
    
    mutating func encode(into argBuffer: ArgumentBuffer, setIndex: Int, bindingEncoder: ResourceBindingEncoder?)
}

@available(*, deprecated, renamed: "ArgumentBuffer")
public typealias _ArgumentBuffer = ArgumentBuffer

@available(*, deprecated, renamed: "ArgumentBuffer")
public typealias _ArgumentBufferArray = ArgumentBufferArray

public struct ArgumentBuffer : ResourceProtocol {
    @usableFromInline let _handle : UnsafeRawPointer
    public var handle : Handle { return UInt64(UInt(bitPattern: _handle)) }
    
    public enum ArgumentResource {
        case buffer(Buffer, offset: Int)
        case texture(Texture)
        case accelerationStructure(AccelerationStructure)
        case sampler(SamplerDescriptor)
        // Where offset is the source offset in the source Data.
        case bytes(offset: Int, length: Int)
    }
    
    public init(handle: Handle) {
        assert(Resource(handle: handle).type == .argumentBuffer)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
    }
    
    public init(renderGraph: RenderGraph? = nil, flags: ResourceFlags = []) {
        precondition(!flags.contains(.historyBuffer), "Argument Buffers cannot be used as history buffers.")
        
        if flags.contains(.persistent) {
            self = PersistentArgumentBufferRegistry.instance.allocate(descriptor: (), heap: nil, flags: flags)
        } else {
            guard let renderGraph = renderGraph ?? RenderGraph.activeRenderGraph else {
                fatalError("The RenderGraph must be specified for transient resources created outside of a render pass' execute() method.")
            }
            precondition(renderGraph.transientRegistryIndex >= 0, "Transient resources are not supported on the RenderGraph \(renderGraph)")
            
            self = TransientArgumentBufferRegistry.instances[renderGraph.transientRegistryIndex].allocate(descriptor: (), flags: flags)
        }
        
        assert(self.encoder == nil)
    }
    
    public init<A : ArgumentBufferEncodable>(encoding arguments: A, setIndex: Int, renderGraph: RenderGraph? = nil, flags: ResourceFlags = []) {
        self.init(renderGraph: renderGraph, flags: flags)
        self.label = "Descriptor Set for \(String(reflecting: A.self))"
        
        var arguments = arguments
        arguments.encode(into: self, setIndex: setIndex, bindingEncoder: nil)
    }
    
    init(flags: ResourceFlags = [], sourceArray: ArgumentBufferArray) {
        if flags.contains(.persistent) {
            self = PersistentArgumentBufferRegistry.instance.allocate(flags: flags, sourceArray: sourceArray)
        } else {
            self = TransientArgumentBufferRegistry.instances[sourceArray.transientRegistryIndex].allocate(flags: flags, sourceArray: sourceArray)
        }
        
        assert(self.encoder == nil)
    }
    
    public var sourceArray : ArgumentBufferArray? {
        if self.flags.contains(.resourceView) {
            return self[\.sourceArrays]
        }
        return nil
    }
    
    public var stateFlags: ResourceStateFlags {
        get {
            return []
        }
        nonmutating set {
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
        if self._usesPersistentRegistry {
            return UnsafeRawPointer.AtomicOptionalRepresentation.atomicWeakCompareExchange(expected: expectingCurrentValue, desired: newEncoder, at: self.pointer(for: \.encoders), successOrdering: .relaxed, failureOrdering: .relaxed).exchanged
        } else {
            return UnsafeRawPointer.AtomicOptionalRepresentation.atomicWeakCompareExchange(expected: expectingCurrentValue, desired: newEncoder, at: self.pointer(for: \.encoders), successOrdering: .relaxed, failureOrdering: .relaxed).exchanged
        }
    }
    
    public var enqueuedBindings : ExpandingBuffer<(FunctionArgumentKey, Int, ArgumentBuffer.ArgumentResource)> {
        _read {
            yield self.pointer(for: \.enqueuedBindings).pointee
        }
        nonmutating _modify {
            self.waitForCPUAccess(accessType: .write)
            
            yield &self.pointer(for: \.enqueuedBindings).pointee
            
            self.stateFlags.remove(.initialised)
        }
    }
    
    public var bindings : ExpandingBuffer<(ResourceBindingPath, ArgumentBuffer.ArgumentResource)> {
        _read {
            yield self.pointer(for: \.bindings).pointee
        }
        nonmutating _modify {
            yield &self.pointer(for: \.bindings).pointee
        }
    }
    
    public var label : String? {
        get {
            return self[\.labels]
        }
        nonmutating set {
            self[\.labels] = newValue
            RenderBackend.updateLabel(on: self)
        }
    }
    
    public var storageMode: StorageMode {
        return .shared
    }
    
    // Thread-safe
    public func translateEnqueuedBindings(_ closure: (FunctionArgumentKey, Int, ArgumentBuffer.ArgumentResource) -> ResourceBindingPath?) {
        
        func translateBindings() {
            var i = 0
            while i < self.enqueuedBindings.count {
                let (key, arrayIndex, binding) = self.enqueuedBindings[i]
                if let bindingPath = closure(key, arrayIndex, binding) {
                    self.enqueuedBindings.remove(at: i)
                    self.bindings.append((bindingPath, binding))
                } else {
                    i += 1
                }
            }
        }

        if self._usesPersistentRegistry {
            PersistentArgumentBufferRegistry.instance.lock.withLock {
                translateBindings()
            }
        } else {
            TransientArgumentBufferRegistry.instances[self.transientRegistryIndex].lock.withLock {
                translateBindings()
            }
        }
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
    
    public subscript(waitIndexFor queue: Queue, accessType type: ResourceAccessType) -> UInt64 {
        get {
            guard self._usesPersistentRegistry else { return 0 }
            if type == .read {
                return self.pointer(for: \.readWaitIndices)?.pointee[Int(queue.index)] ?? 0
            } else {
                return self.pointer(for: \.writeWaitIndices)?.pointee[Int(queue.index)] ?? 0
            }
        }
        nonmutating set {
            guard self._usesPersistentRegistry else { return }
            if type == .read || type == .readWrite {
                self.pointer(for: \.readWaitIndices)!.pointee[Int(queue.index)] = newValue
            }
            if type == .write || type == .readWrite {
                self.pointer(for: \.writeWaitIndices)!.pointee[Int(queue.index)]  = newValue
            }
        }
    }
    
    /// Returns whether the resource is known to currently be in use by the CPU or GPU.
    public var isKnownInUse: Bool {
        guard let activeRenderGraphs = self.pointer(for: \.activeRenderGraphs) else {
            return true
        }
        let activeRenderGraphMask = UInt8.AtomicRepresentation.atomicLoad(at: activeRenderGraphs, ordering: .relaxed)
        if activeRenderGraphMask != 0 {
            return true // The resource is still being used by a yet-to-be-submitted RenderGraph.
        }
        for queue in QueueRegistry.allQueues {
            if self[waitIndexFor: queue, accessType: .readWrite] > queue.lastCompletedCommand {
                return true
            }
        }
        return false
    }
    
    public func markAsUsed(activeRenderGraphMask: ActiveRenderGraphMask) {
        guard let activeRenderGraphs = self.pointer(for: \.activeRenderGraphs) else {
            return
        }
        UInt8.AtomicRepresentation.atomicLoadThenBitwiseOr(with: activeRenderGraphMask, at: activeRenderGraphs, ordering: .relaxed)
    }
    
    public func dispose() {
        guard self._usesPersistentRegistry, self.isValid else {
            return
        }
        PersistentArgumentBufferRegistry.instance.dispose(self)
    }
    
    public var isValid : Bool {
        if self._usesPersistentRegistry {
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: Self.itemsPerChunk)
            return PersistentArgumentBufferRegistry.instance.generationChunks[chunkIndex][indexInChunk] == self.generation
        } else {
            return TransientArgumentBufferRegistry.instances[self.transientRegistryIndex].generation == self.generation
        }
    }
    
    
    public func setBuffer(_ buffer: Buffer?, offset: Int, key: FunctionArgumentKey, arrayIndex: Int = 0) {
        guard let buffer = buffer else { return }
        
        assert(!self.flags.contains(.persistent) || buffer.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        self.enqueuedBindings.append(
            (key, arrayIndex, .buffer(buffer, offset: offset))
        )
    }
    
    public func setTexture(_ texture: Texture, key: FunctionArgumentKey, arrayIndex: Int = 0) {
        assert(!self.flags.contains(.persistent) || texture.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        self.enqueuedBindings.append(
            (key, arrayIndex, .texture(texture))
        )
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public func setAccelerationStructure(_ structure: AccelerationStructure, key: FunctionArgumentKey, arrayIndex: Int = 0) {
        assert(!self.flags.contains(.persistent) || structure.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        self.enqueuedBindings.append(
            (key, arrayIndex, .accelerationStructure(structure))
        )
    }
    
    @inlinable
    public func setSampler(_ sampler: SamplerDescriptor, key: FunctionArgumentKey, arrayIndex: Int = 0) {
        self.enqueuedBindings.append(
            (key, arrayIndex, .sampler(sampler))
        )
    }
    
    public func setValue<T>(_ value: T, key: FunctionArgumentKey, arrayIndex: Int = 0) {
        assert(_isPOD(T.self), "Only POD types should be used with setValue.")
        
        var value = value
        withUnsafeBytes(of: &value) { bufferPointer in
            self.setBytes(bufferPointer.baseAddress!, length: bufferPointer.count, for: key, arrayIndex: arrayIndex)
        }
    }
    
    public func setValue<T : ResourceProtocol>(_ value: T, key: FunctionArgumentKey, arrayIndex: Int = 0) {
        preconditionFailure("setValue should not be used with resources; use setBuffer or setTexture instead.")
    }
    
    public func setBytes(_ bytes: UnsafeRawPointer, length: Int, for key: FunctionArgumentKey, arrayIndex: Int = 0) {
        let currentOffset = self._copyBytes(bytes, length: length)
        self.enqueuedBindings.append(
            (key, arrayIndex, .bytes(offset: currentOffset, length: length))
        )
    }
    
    public static var resourceType: ResourceType {
        return .argumentBuffer
    }
}

extension ArgumentBuffer {
    
    public func setBuffers(_ buffers: [Buffer], offsets: [Int], keys: [FunctionArgumentKey]) {
        for (buffer, (offset, key)) in zip(buffers, zip(offsets, keys)) {
            self.setBuffer(buffer, offset: offset, key: key)
        }
    }
    
    public func setTextures(_ textures: [Texture], keys: [FunctionArgumentKey]) {
        for (texture, key) in zip(textures, keys) {
            self.setTexture(texture, key: key)
        }
    }
    
    public func setSamplers(_ samplers: [SamplerDescriptor], keys: [FunctionArgumentKey]) {
        for (sampler, key) in zip(samplers, keys) {
            self.setSampler(sampler, key: key)
        }
    }
}

extension ArgumentBuffer: ResourceProtocolImpl {
    typealias SharedProperties = ArgumentBufferProperties
    typealias TransientProperties = EmptyProperties<Void>
    typealias PersistentProperties = ArgumentBufferProperties.PersistentArgumentBufferProperties
    
    static func transientRegistry(index: Int) -> TransientArgumentBufferRegistry? {
        return TransientArgumentBufferRegistry.instances[index]
    }
    
    static var persistentRegistry: PersistentRegistry<Self> { PersistentArgumentBufferRegistry.instance }
    
    typealias Descriptor = Void
}


extension ArgumentBuffer: CustomStringConvertible {
    public var description: String {
        return "ArgumentBuffer(handle: \(self.handle)) { \(self.label.map { "label: \($0), "} ?? "")bindings: \(self.bindings), enqueuedBindings: \(self.enqueuedBindings), flags: \(self.flags) }"
    }
}

public struct ArgumentBufferArray : ResourceProtocol {

    @usableFromInline let _handle : UnsafeRawPointer
    public var handle : Handle { return UInt64(UInt(bitPattern: _handle)) }
    
    public init(handle: Handle) {
        assert(Resource(handle: handle).type == .argumentBufferArray)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
    }
    
    public init(renderGraph: RenderGraph? = nil, flags: ResourceFlags = []) {
        precondition(!flags.contains(.historyBuffer), "Argument Buffers cannot be used as history buffers.")
        
        if flags.contains(.persistent) {
            self = PersistentArgumentBufferArrayRegistry.instance.allocate(descriptor: (), heap: nil, flags: flags)
        } else {
            guard let renderGraph = renderGraph ?? RenderGraph.activeRenderGraph else {
                fatalError("The RenderGraph must be specified for transient resources created outside of a render pass' execute() method.")
            }
            precondition(renderGraph.transientRegistryIndex >= 0, "Transient resources are not supported on the RenderGraph \(renderGraph)")
            self = TransientArgumentBufferArrayRegistry.instances[renderGraph.transientRegistryIndex].allocate(descriptor: (),flags: flags)
        }
    }
    
    public var isKnownInUse: Bool {
        return self._bindings.contains(where: { $0?.isKnownInUse ?? false })
    }
    
    public func markAsUsed(activeRenderGraphMask: ActiveRenderGraphMask) {
        for binding in self._bindings {
            binding?.markAsUsed(activeRenderGraphMask: activeRenderGraphMask)
        }
    }
    
    public func dispose() {
        guard self._usesPersistentRegistry, self.isValid else {
            return
        }
        for binding in self._bindings {
            binding?.dispose()
        }
        PersistentArgumentBufferArrayRegistry.instance.dispose(self)
    }
    
    public var stateFlags: ResourceStateFlags {
        get {
            return []
        }
        nonmutating set {
        }
    }
    
    public var _bindings : [ArgumentBuffer?] {
        _read {
            yield self.pointer(for: \.bindings).pointee
        }
        nonmutating _modify {
            yield &self.pointer(for: \.bindings).pointee
        }
    }
    
    public var label : String? {
        get {
            return self.pointer(for: \.labels).pointee
        }
        nonmutating set {
            self.pointer(for: \.labels).pointee = newValue
        }
    }
    
    public var storageMode: StorageMode {
        return .shared
    }
    
    public subscript(waitIndexFor queue: Queue, accessType type: ResourceAccessType) -> UInt64 {
        get {
            return 0
        }
        nonmutating set {
            // Argument buffer array waits are handled at ArgumentBuffer granularity
           _ = newValue
        }
    }
    
    public var isValid : Bool {
        if self._usesPersistentRegistry {
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: Self.itemsPerChunk)
            return PersistentArgumentBufferArrayRegistry.instance.generationChunks[chunkIndex][indexInChunk] == self.generation
        } else {
            return TransientArgumentBufferArrayRegistry.instances[self.transientRegistryIndex].generation == self.generation
        }
    }
    
    public static var resourceType: ResourceType {
        return .argumentBufferArray
    }
}

extension ArgumentBufferArray: ResourceProtocolImpl {
    typealias SharedProperties = ArgumentBufferArrayProperties
    typealias TransientProperties = EmptyProperties<Void>
    typealias PersistentProperties = ArgumentBufferProperties.PersistentArgumentBufferProperties
    
    static func transientRegistry(index: Int) -> TransientArgumentBufferArrayRegistry? {
        return TransientArgumentBufferArrayRegistry.instances[index]
    }
    
    static var persistentRegistry: PersistentRegistry<Self> { PersistentArgumentBufferArrayRegistry.instance }
    
    typealias Descriptor = Void
}


extension ArgumentBufferArray: CustomStringConvertible {
    public var description: String {
        return "ArgumentBuffer(handle: \(self.handle)) { \(self.label.map { "label: \($0), "} ?? "")bindings: \(self._bindings), flags: \(self.flags) }"
    }
}


public struct TypedArgumentBuffer<K : FunctionArgumentKey> : ResourceProtocol {
    public let argumentBuffer : ArgumentBuffer
    
    public init(handle: Handle) {
        self.argumentBuffer = ArgumentBuffer(handle: handle)
    }
    
    @available(*, deprecated, renamed: "init(renderGraph:flags:)")
    public init(frameGraph: RenderGraph?, flags: ResourceFlags = []) {
        self.init(renderGraph: frameGraph, flags: flags)
    }
    
    public init(renderGraph: RenderGraph? = nil, flags: ResourceFlags = []) {
        self.argumentBuffer = ArgumentBuffer(renderGraph: renderGraph, flags: flags)
        self.argumentBuffer.label = "Argument Buffer \(K.self)"
    }
    
    public func dispose() {
        self.argumentBuffer.dispose()
    }
    
    public var handle: Resource.Handle {
        return self.argumentBuffer.handle
    }
    
    public var stateFlags: ResourceStateFlags {
        get {
            return self.argumentBuffer.stateFlags
        }
        nonmutating set {
            self.argumentBuffer.stateFlags = newValue
        }
    }
    
    public var flags : ResourceFlags {
        return self.argumentBuffer.flags
    }
    
    public var sourceArray : TypedArgumentBufferArray<K>? {
        return self.argumentBuffer.sourceArray.map { TypedArgumentBufferArray(handle: $0.handle) }
    }
    
    public var isKnownInUse: Bool {
        return self.argumentBuffer.isKnownInUse
    }
    
    public func markAsUsed(activeRenderGraphMask: ActiveRenderGraphMask) {
        self.argumentBuffer.markAsUsed(activeRenderGraphMask: activeRenderGraphMask)
    }
    
    public var isValid: Bool {
        return self.argumentBuffer.isValid
    }
    
    public var label : String? {
        get {
            return self.argumentBuffer.label
        }
        nonmutating set {
            self.argumentBuffer.label = newValue
        }
    }
    
    public var storageMode: StorageMode {
        return self.argumentBuffer.storageMode
    }
    
    public func setBuffer(_ buffer: Buffer?, offset: Int, key: K, arrayIndex: Int = 0) {
        guard let buffer = buffer else { return }
        
        assert(!self.flags.contains(.persistent) || buffer.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        self.argumentBuffer.enqueuedBindings.append(
            (key, arrayIndex, .buffer(buffer, offset: offset))
        )
    }
    
    public func setTexture(_ texture: Texture, key: K, arrayIndex: Int = 0) {
        assert(!self.flags.contains(.persistent) || texture.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        self.argumentBuffer.enqueuedBindings.append(
            (key, arrayIndex, .texture(texture))
        )
    }
    
    public func setSampler(_ sampler: SamplerDescriptor, key: K, arrayIndex: Int = 0) {
        self.argumentBuffer.enqueuedBindings.append(
            (key, arrayIndex, .sampler(sampler))
        )
    }

    public func setValue<T : ResourceProtocol>(_ value: T, key: K, arrayIndex: Int = 0) {
        assertionFailure("Cannot set a resource with setValue; did you mean to use setTexture or setBuffer?")
    }
    
    public func setValue<T>(_ value: T, key: K, arrayIndex: Int = 0) {
        assert(_isPOD(T.self), "Only POD types should be used with setValue.")
        
        var value = value
        withUnsafeBytes(of: &value) { bufferPointer in
            self.setBytes(bufferPointer.baseAddress!, length: bufferPointer.count, for: key, arrayIndex: arrayIndex)
        }
    }
    
    public func setValue<T : ResourceProtocol>(_ value: T, key: FunctionArgumentKey, arrayIndex: Int = 0) {
        preconditionFailure("setValue should not be used with resources; use setBuffer or setTexture instead.")
    }
    
    public func setBytes(_ bytes: UnsafeRawPointer, length: Int, for key: K, arrayIndex: Int = 0) {
        let currentOffset = self.argumentBuffer._copyBytes(bytes, length: length)
        self.argumentBuffer.enqueuedBindings.append(
            (key, arrayIndex, .bytes(offset: currentOffset, length: length))
        )
    }
    
    public static var resourceType: ResourceType {
        return .argumentBuffer
    }
}

extension TypedArgumentBuffer {
    
    public func setBuffers(_ buffers: [Buffer], offsets: [Int], keys: [K]) {
        for (buffer, (offset, key)) in zip(buffers, zip(offsets, keys)) {
            self.setBuffer(buffer, offset: offset, key: key)
        }
    }
    
    public func setTextures(_ textures: [Texture], keys: [K]) {
        for (texture, key) in zip(textures, keys) {
            self.setTexture(texture, key: key)
        }
    }
    
    public func setSamplers(_ samplers: [SamplerDescriptor], keys: [K]) {
        for (sampler, key) in zip(samplers, keys) {
            self.setSampler(sampler, key: key)
        }
    }
}

public struct TypedArgumentBufferArray<K : FunctionArgumentKey> : ResourceProtocol {
    public let argumentBufferArray : ArgumentBufferArray
    
    public init(handle: Handle) {
        self.argumentBufferArray = ArgumentBufferArray(handle: handle)
    }
    
    @available(*, deprecated, renamed: "init(renderGraph:flags:)")
    public init(frameGraph: RenderGraph?, flags: ResourceFlags = []) {
        self.init(renderGraph: frameGraph, flags: flags)
    }
    
    public init(renderGraph: RenderGraph? = nil, flags: ResourceFlags = []) {
        self.argumentBufferArray = ArgumentBufferArray(renderGraph: renderGraph, flags: flags)
        self.argumentBufferArray.label = "Argument Buffer Array \(K.self)"
    }
    
    public var isKnownInUse: Bool {
        return self.argumentBufferArray.isKnownInUse
    }
    
    public func markAsUsed(activeRenderGraphMask: ActiveRenderGraphMask) {
        self.argumentBufferArray.markAsUsed(activeRenderGraphMask: activeRenderGraphMask)
    }
    
    public func dispose() {
        self.argumentBufferArray.dispose()
    }
    
    public var handle: ArgumentBufferArray.Handle {
        return self.argumentBufferArray.handle
    }
    
    public var stateFlags: ResourceStateFlags {
        get {
            return self.argumentBufferArray.stateFlags
        }
        nonmutating set {
            self.argumentBufferArray.stateFlags = newValue
        }
    }
    
    public var label : String? {
        get {
            return self.argumentBufferArray.label
        }
        nonmutating set {
            self.argumentBufferArray.label = newValue
        }
    }
    
    public var storageMode: StorageMode {
        return self.argumentBufferArray.storageMode
    }
    
    public var isValid: Bool {
        return self.argumentBufferArray.isValid
    }
    
    public func reserveCapacity(_ capacity: Int) {
        self.argumentBufferArray._bindings.reserveCapacity(capacity)
    }
    
    public subscript(index: Int) -> TypedArgumentBuffer<K> {
        get {
            if index >= self.argumentBufferArray._bindings.count {
                self.argumentBufferArray._bindings.append(contentsOf: repeatElement(nil, count: index - self.argumentBufferArray._bindings.count + 1))
            }
            
            if let buffer = self.argumentBufferArray._bindings[index] {
                return TypedArgumentBuffer(handle: buffer.handle)
            }
            
            let buffer = ArgumentBuffer(flags: [self.flags, .resourceView], sourceArray: self.argumentBufferArray)
            self.argumentBufferArray._bindings[index] = buffer
            return TypedArgumentBuffer(handle: buffer.handle)
        }
    }
    
    public static var resourceType: ResourceType {
        return .argumentBufferArray
    }
}
