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
    @inlinable public var handle : Handle { return UInt64(UInt(bitPattern: _handle)) }
    
    public init(handle: Handle) {
        assert(Resource(handle: handle).type == .argumentBufferArray)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
    }
    
    public init(descriptor: ArgumentBufferDescriptor, renderGraph: RenderGraph? = nil, flags: ResourceFlags = []) {
        precondition(!flags.contains(.historyBuffer), "Argument Buffers cannot be used as history buffers.")
        
        if flags.contains(.persistent) {
            self = PersistentArgumentBufferArrayRegistry.instance.allocate(descriptor: descriptor, heap: nil, flags: flags)
        } else {
            guard let renderGraph = renderGraph ?? RenderGraph.activeRenderGraph else {
                fatalError("The RenderGraph must be specified for transient resources created outside of a render pass' execute() method.")
            }
            precondition(renderGraph.transientRegistryIndex >= 0, "Transient resources are not supported on the RenderGraph \(renderGraph)")
            self = TransientArgumentBufferArrayRegistry.instances[renderGraph.transientRegistryIndex].allocate(descriptor: descriptor, flags: flags)
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
    
    public var descriptor: ArgumentBufferDescriptor {
        _read {
            yield self.pointer(for: \.descriptors).pointee
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
    typealias TransientProperties = EmptyProperties<ArgumentBufferDescriptor>
    typealias PersistentProperties = ArgumentBufferProperties.PersistentArgumentBufferProperties
    
    static func transientRegistry(index: Int) -> TransientArgumentBufferArrayRegistry? {
        return TransientArgumentBufferArrayRegistry.instances[index]
    }
    
    static var persistentRegistry: PersistentRegistry<Self> { PersistentArgumentBufferArrayRegistry.instance }
    
    typealias Descriptor = ArgumentBufferDescriptor
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
    
    public init(descriptor: ArgumentBufferDescriptor, renderGraph: RenderGraph? = nil, flags: ResourceFlags = []) {
        self.argumentBufferArray = ArgumentBufferArray(descriptor: descriptor, renderGraph: renderGraph, flags: flags)
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
    
    @inlinable
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

final class TransientArgumentBufferArrayRegistry: TransientFixedSizeRegistry<ArgumentBufferArray> {
    static let instances = TransientRegistryArray<TransientArgumentBufferArrayRegistry>()
}

final class PersistentArgumentBufferArrayRegistry: PersistentRegistry<ArgumentBufferArray> {
    static let instance = PersistentArgumentBufferArrayRegistry()
}


struct ArgumentBufferArrayProperties: SharedResourceProperties {
    struct PersistentArgumentBufferArrayProperties: PersistentResourceProperties {
        let heaps : UnsafeMutablePointer<Heap?>
        
        init(capacity: Int) {
            self.heaps = .allocate(capacity: capacity)
        }
        
        func deallocate() {
            self.heaps.deallocate()
        }
        
        func initialize(index: Int, descriptor: Void, heap: Heap?, flags: ResourceFlags) {
            self.heaps.advanced(by: index).initialize(to: heap)
        }
        
        func deinitialize(from index: Int, count: Int) {
            self.heaps.advanced(by: index).deinitialize(count: count)
        }
        
        var readWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { nil }
        var writeWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { nil }
        var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { nil }
    }
    
    var bindings : UnsafeMutablePointer<[ArgumentBuffer?]>
    let descriptors: UnsafeMutablePointer<ArgumentBufferDescriptor>
    
    init(capacity: Int) {
        self.bindings = .allocate(capacity: capacity)
        self.descriptors = .allocate(capacity: capacity)
    }
    
    func deallocate() {
        self.bindings.deallocate()
        self.descriptors.deallocate()
    }
    
    func initialize(index: Int, descriptor: ArgumentBufferDescriptor, heap: Heap?, flags: ResourceFlags) {
        self.bindings.advanced(by: index).initialize(to: [])
        self.descriptors.advanced(by: index).initialize(to: descriptor)
    }
    
    func deinitialize(from index: Int, count: Int) {
        self.bindings.advanced(by: index).deinitialize(count: count)
        self.descriptors.advanced(by: index).deinitialize(count: count)
    }
    
    var usagesOptional: UnsafeMutablePointer<ChunkArray<ResourceUsage>>? { nil }
    
}
