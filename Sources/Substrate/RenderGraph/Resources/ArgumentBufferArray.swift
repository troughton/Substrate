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
    public let handle: ResourceHandle
    
    public init(handle: Handle) {
        assert(handle.resourceType == .argumentBufferArray)
        self.handle = handle
    }
    
    public init(descriptor: ArgumentBufferDescriptor, arrayLength: Int) {
        let flags : ResourceFlags = .persistent
        
        self = PersistentArgumentBufferArrayRegistry.instance.allocate(descriptor: ArgumentBufferArrayDescriptor(descriptor: descriptor, arrayLength: arrayLength), heap: nil, flags: flags)
        
        let didAllocate = RenderBackend.materialisePersistentResource(self)
        assert(didAllocate, "Allocation failed for persistent buffer \(self)")
        if !didAllocate { self.dispose() }
        
        for i in 0..<self.arrayLength {
            self[i].baseResource = Resource(self)
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
    
    public func reset() {
        for element in self {
            element._reset(includingEncodedResources: true, includingParent: false)
        }
        
#if canImport(Metal)
        self.encodedResourcesLock.withLock {
            self.usedResources.removeAll()
            self.usedHeaps.removeAll()
        }
#endif
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
        precondition(position >= 0 && position < self.arrayLength)
        return (self[\.argumentBuffers]! as UnsafeMutablePointer<ArgumentBuffer>)[position]
    }
    
    public var storageMode: StorageMode {
        return self.descriptor.storageMode
    }
    
    public static var resourceType: ResourceType {
        return .argumentBufferArray
    }
    
#if canImport(Metal)
    // For Metal: residency tracking.
    var encodedResourcesLock: SpinLock {
        get {
            return SpinLock(initializedLockAt: self.pointer(for: \.encodedResourcesLocks)!)
        }
    }
    
    var usedResources: HashSet<UnsafeMutableRawPointer> {
        _read {
            yield self.pointer(for: \.usedResources)!.pointee
        }
        nonmutating _modify {
            yield &self.pointer(for: \.usedResources)!.pointee
        }
    }
    
    var usedHeaps: HashSet<UnsafeMutableRawPointer> {
        _read {
            yield self.pointer(for: \.usedHeaps)!.pointee
        }
        nonmutating _modify {
            yield &self.pointer(for: \.usedHeaps)!.pointee
        }
    }
    
#endif
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
    
    @usableFromInline static var tracksUsages: Bool { true }
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
    
#if canImport(Metal)
    let encodedResourcesLocks: UnsafeMutablePointer<SpinLock.Storage>
    let usedResources: UnsafeMutablePointer<HashSet<UnsafeMutableRawPointer>>
    let usedHeaps: UnsafeMutablePointer<HashSet<UnsafeMutableRawPointer>>
#endif
    
    @usableFromInline init(capacity: Int) {
        self.descriptors = .allocate(capacity: capacity)
        self.argumentBuffers = .allocate(capacity: capacity)
        self.activeRenderGraphs = .allocate(capacity: capacity)
        
#if canImport(Metal)
        self.encodedResourcesLocks = .allocate(capacity: capacity)
        self.usedResources = .allocate(capacity: capacity)
        self.usedHeaps = .allocate(capacity: capacity)
#endif
    }
    
    @usableFromInline func deallocate() {
        self.descriptors.deallocate()
        self.argumentBuffers.deallocate()
        self.activeRenderGraphs.deallocate()
        
#if canImport(Metal)
        self.encodedResourcesLocks.deallocate()
        self.usedResources.deallocate()
        self.usedHeaps.deallocate()
#endif
    }
    
    @usableFromInline func initialize(index: Int, descriptor: ArgumentBufferArrayDescriptor, heap: Heap?, flags: ResourceFlags) {
        assert(heap == nil)
        
        self.descriptors.advanced(by: index).initialize(to: descriptor)
        self.argumentBuffers.advanced(by: index).initialize(to: .allocate(capacity: descriptor.arrayLength))
        for i in 0..<descriptor.arrayLength {
            self.argumentBuffers[index].advanced(by: i).initialize(to: PersistentArgumentBufferRegistry.instance.allocate(descriptor: descriptor.descriptor, heap: nil, flags: flags))
        }
        
        self.activeRenderGraphs.advanced(by: index).initialize(to: UInt8.AtomicRepresentation(0))
        
#if canImport(Metal)
        let _ = SpinLock(at: self.encodedResourcesLocks.advanced(by: index))
        self.usedResources.advanced(by: index).initialize(to: .init()) // TODO: pass in the appropriate allocator.
        self.usedHeaps.advanced(by: index).initialize(to: .init())
#endif
    }
    
    @usableFromInline func deinitialize(from index: Int, count: Int) {
        for i in index..<(index + count) {
            for j in 0..<self.descriptors[i].arrayLength {
                PersistentArgumentBufferRegistry.instance.disposeImmediately(self.argumentBuffers[i][j], disposeInBackend: false)
            }
            self.argumentBuffers[i].deallocate()
        }
        self.descriptors.advanced(by: index).deinitialize(count: count)
        self.argumentBuffers.advanced(by: index).deinitialize(count: count)
        self.activeRenderGraphs.advanced(by: index).deinitialize(count: count)
        
#if canImport(Metal)
        for i in 0..<count {
            self.usedResources[index + i].deinit()
            self.usedHeaps[index + i].deinit()
        }
        self.usedResources.advanced(by: index).deinitialize(count: count)
        self.usedHeaps.advanced(by: index).deinitialize(count: count)
#endif
    }
    
    @usableFromInline var readWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndex.AtomicRepresentation>? { nil }
    @usableFromInline var writeWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndex.AtomicRepresentation>? { nil }
    @usableFromInline var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { activeRenderGraphs }
}
