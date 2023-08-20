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

@usableFromInline
struct ArgumentBufferArrayDescriptor {
    public var descriptor: ArgumentBufferDescriptor
    public var arrayLength: Int
    
    public init(descriptor: ArgumentBufferDescriptor, arrayLength: Int) {
        self.descriptor = descriptor
        self.arrayLength = arrayLength
    }
}

public struct ArgumentBufferArray : ResourceProtocol, Collection {
    @usableFromInline let _handle : UnsafeRawPointer
    @inlinable public var handle : Handle { return UInt64(UInt(bitPattern: _handle)) }
    
    public init(handle: Handle) {
        assert(Resource(handle: handle).type == .argumentBuffer)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
    }
    
    public init?(descriptor: ArgumentBufferDescriptor, arrayLength: Int) {
        let flags : ResourceFlags = .persistent
        
        self = PersistentArgumentBufferArrayRegistry.instance.allocate(descriptor: ArgumentBufferArrayDescriptor(descriptor: descriptor, arrayLength: arrayLength), heap: nil, flags: flags)
        
        if !RenderBackend.materialisePersistentResource(self) {
            self.dispose()
            return nil
        }
    }
    
    public internal(set) var descriptor : ArgumentBufferDescriptor {
        get {
            return self[\.descriptors]!.descriptor
        }
        nonmutating set {
            self[\.descriptors]!.descriptor = newValue
        }
    }
    
    public internal(set) var arrayLength : Int {
        get {
            return self[\.descriptors]!.arrayLength
        }
        nonmutating set {
            self[\.descriptors]!.arrayLength = newValue
        }
    }
    
    public var startIndex: Int {
        return 0
    }
    
    public var endIndex: Int {
        return self.arrayLength
    }
    
    public func index(after i: Int) -> Int {
        return i + 1
    }
    
    public subscript(position: Int) -> ArgumentBuffer {
        precondition(position > 0 && position < self.arrayLength)
        return (self[\.argumentBuffers]! as UnsafeMutablePointer<ArgumentBuffer>)[position]
    }
    
    public var storageMode: StorageMode {
        return self.descriptor.storageMode
    }
    
    public static var resourceType: ResourceType {
        return .argumentBufferArray
    }
}

extension ArgumentBufferArray: ResourceProtocolImpl {
    @usableFromInline typealias SharedProperties = EmptyProperties<ArgumentBufferArrayDescriptor>
    @usableFromInline typealias TransientProperties = EmptyProperties<ArgumentBufferArrayDescriptor>
    @usableFromInline typealias PersistentProperties = ArgumentBufferArrayProperties
    
    @usableFromInline static func transientRegistry(index: Int) -> TransientChunkRegistry<ArgumentBufferArray>? {
        return nil
    }
    
    @usableFromInline static var persistentRegistry: PersistentRegistry<Self> { PersistentArgumentBufferArrayRegistry.instance }
    
    @usableFromInline typealias Descriptor = ArgumentBufferArrayDescriptor
    
    @usableFromInline static var tracksUsages: Bool { false }
}

// Unlike the other transient registries, the transient argument buffer registry is chunk-based.
// This is because the number of argument buffers used within a frame can vary dramatically, and so a pre-assigned maximum is more likely to be hit.
@usableFromInline final class TransientArgumentBufferArrayRegistry: TransientChunkRegistry<ArgumentBuffer> {
    @usableFromInline static let instances = TransientRegistryArray<TransientArgumentBufferArrayRegistry>()
    
    override class var maxChunks: Int { 2048 }
}

final class PersistentArgumentBufferArrayRegistry: PersistentRegistry<ArgumentBufferArray> {
    static let instance = PersistentArgumentBufferArrayRegistry()
    
    override class var maxChunks: Int { 256 }
}

@usableFromInline
struct ArgumentBufferArrayProperties: PersistentResourceProperties {
    let descriptors : UnsafeMutablePointer<ArgumentBufferArrayDescriptor>
    let argumentBuffers : UnsafeMutablePointer<UnsafeMutablePointer<ArgumentBuffer>>
    /// The RenderGraphs that are currently using this resource.
    let activeRenderGraphs : UnsafeMutablePointer<UInt8.AtomicRepresentation>
    
    @usableFromInline init(capacity: Int) {
        self.descriptors = .allocate(capacity: capacity)
        self.argumentBuffers = .allocate(capacity: capacity)
        self.activeRenderGraphs = .allocate(capacity: capacity)
    }
    
    @usableFromInline func deallocate() {
        self.descriptors.deallocate()
        self.argumentBuffers.deallocate()
        self.activeRenderGraphs.deallocate()
    }
    
    @usableFromInline func initialize(index: Int, descriptor: ArgumentBufferArrayDescriptor, heap: Heap?, flags: ResourceFlags) {
        assert(heap == nil)
        
        self.descriptors.advanced(by: index).initialize(to: descriptor)
        self.argumentBuffers.advanced(by: index).initialize(to: .allocate(capacity: descriptor.arrayLength))
        for i in 0..<descriptor.arrayLength {
            self.argumentBuffers[index].advanced(by: i).initialize(to: PersistentArgumentBufferRegistry.instance.allocate(descriptor: descriptor.descriptor, heap: nil, flags: flags))
        }
        
        self.activeRenderGraphs.advanced(by: index).initialize(to: UInt8.AtomicRepresentation(0))
    }
    
    @usableFromInline func deinitialize(from index: Int, count: Int) {
        for i in index..<(index + count) {
            for j in 0..<self.descriptors[i].arrayLength {
                PersistentArgumentBufferRegistry.instance.disposeImmediately(self.argumentBuffers[i][j])
            }
            self.argumentBuffers[i].deallocate()
        }
        self.descriptors.advanced(by: index).deinitialize(count: count)
        self.argumentBuffers.advanced(by: index).deinitialize(count: count)
        self.activeRenderGraphs.advanced(by: index).deinitialize(count: count)
    }
    
    @usableFromInline var readWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { nil }
    @usableFromInline var writeWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { nil }
    @usableFromInline var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { activeRenderGraphs }
}
