//
//  ArgumentBufferArray.swift
//  
//
//  Created by Thomas Roughton on 2/07/21.
//

import SubstrateUtilities
import Foundation

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
    
    public var storageMode: StorageMode {
        return .shared
    }
    
    public subscript(waitIndexFor queue: Queue, accessType type: ResourceAccessType) -> UInt64 {
        get {
            guard self._usesPersistentRegistry else { return 0 }
            return self._bindings.lazy.map { $0?[waitIndexFor: queue, accessType: type] ?? 0 }.max() ?? 0
        }
        nonmutating set {
            guard self._usesPersistentRegistry else { return }
            for binding in self._bindings {
                binding?[waitIndexFor: queue, accessType: type] = newValue
            }
        }
    }
    
    public static var resourceType: ResourceType {
        return .argumentBufferArray
    }
}

extension ArgumentBufferArray: CustomStringConvertible {
    public var description: String {
        return "ArgumentBuffer(handle: \(self.handle)) { \(self.label.map { "label: \($0), "} ?? "")bindings: \(self._bindings), flags: \(self.flags) }"
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


public struct TypedArgumentBufferArray<K : FunctionArgumentKey> : ResourceProtocol {
    public let argumentBufferArray : ArgumentBufferArray
    
    public init?(_ resource: Resource) {
        guard let argBufferArray = ArgumentBufferArray(resource) else { return nil }
        self.argumentBufferArray = argBufferArray
    }
    
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
    
    public var usages: ChunkArray<ResourceUsage> {
        get {
            return self.argumentBufferArray.usages
        }
        nonmutating set {
            self.argumentBufferArray.usages = newValue
        }
    }
    
    public var resourceForUsageTracking: Resource {
        return self.argumentBufferArray.resourceForUsageTracking
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

extension TypedArgumentBufferArray: CustomStringConvertible {
    public var description: String {
        return self.argumentBufferArray.description
    }
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
        
        func initialize(index indexInChunk: Int, descriptor: Void, heap: Heap?, flags: ResourceFlags) {
            self.inlineDataStorage.advanced(by: indexInChunk).initialize(to: Data())
            self.heaps.advanced(by: indexInChunk).initialize(to: nil)
            self.readWaitIndices.advanced(by: indexInChunk).initialize(to: SIMD8(repeating: 0))
            self.writeWaitIndices.advanced(by: indexInChunk).initialize(to: SIMD8(repeating: 0))
            self.activeRenderGraphs.advanced(by: indexInChunk).initialize(to: UInt8.AtomicRepresentation(0))
        }
        
        func initialize(index indexInChunk: Int, sourceArray: ArgumentBufferArray) {
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
    
    let usages : UnsafeMutablePointer<ChunkArray<ResourceUsage>>
    let encoders : UnsafeMutablePointer<UnsafeRawPointer.AtomicOptionalRepresentation> // Some opaque backend type that can construct the argument buffer
    let enqueuedBindings : UnsafeMutablePointer<ExpandingBuffer<(FunctionArgumentKey, Int, ArgumentBuffer.ArgumentResource)>>
    let bindings : UnsafeMutablePointer<ExpandingBuffer<(ResourceBindingPath, ArgumentBuffer.ArgumentResource)>>
    let sourceArrays : UnsafeMutablePointer<ArgumentBufferArray?>
    
    typealias Descriptor = Void
    
    init(capacity: Int) {
        self.usages = .allocate(capacity: capacity)
        self.encoders = .allocate(capacity: capacity)
        self.enqueuedBindings = .allocate(capacity: capacity)
        self.bindings = .allocate(capacity: capacity)
        self.sourceArrays = .allocate(capacity: capacity)
    }
    
    func deallocate() {
        self.usages.deallocate()
        self.encoders.deallocate()
        self.enqueuedBindings.deallocate()
        self.bindings.deallocate()
        self.sourceArrays.deallocate()
    }
    
    func initialize(index indexInChunk: Int, descriptor: Void, heap: Heap?, flags: ResourceFlags) {
        self.usages.advanced(by: indexInChunk).initialize(to: ChunkArray())
        self.encoders.advanced(by: indexInChunk).initialize(to: UnsafeRawPointer.AtomicOptionalRepresentation(nil))
        self.enqueuedBindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
        self.bindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
        self.sourceArrays.advanced(by: indexInChunk).initialize(to: nil)
    }
    
    func initialize(index indexInChunk: Int, sourceArray: ArgumentBufferArray) {
        self.usages.advanced(by: indexInChunk).initialize(to: ChunkArray())
        self.encoders.advanced(by: indexInChunk).initialize(to: UnsafeRawPointer.AtomicOptionalRepresentation(nil))
        self.enqueuedBindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
        self.bindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
        self.sourceArrays.advanced(by: indexInChunk).initialize(to: sourceArray)
    }
    
    func deinitialize(from index: Int, count: Int) {
        self.usages.advanced(by: index).deinitialize(count: count)
        self.encoders.advanced(by: index).deinitialize(count: count)
        self.enqueuedBindings.advanced(by: index).deinitialize(count: count)
        self.bindings.advanced(by: index).deinitialize(count: count)
        self.sourceArrays.advanced(by: index).deinitialize(count: count)
    }
    
    var usagesOptional: UnsafeMutablePointer<ChunkArray<ResourceUsage>>? { self.usages }
}


final class TransientArgumentBufferArrayRegistry: TransientFixedSizeRegistry<ArgumentBufferArray> {
    static let instances = TransientRegistryArray<TransientArgumentBufferArrayRegistry>()
}

final class PersistentArgumentBufferArrayRegistry: PersistentRegistry<ArgumentBufferArray> {
    static let instance = PersistentArgumentBufferArrayRegistry()
}
