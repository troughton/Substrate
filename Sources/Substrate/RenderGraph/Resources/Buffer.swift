//
//  Buffer.swift
//  
//
//  Created by Thomas Roughton on 2/07/21.
//

import SubstrateUtilities
import Atomics

/// `Buffer` represents a contiguous block of untyped GPU-visible memory.
/// Whenever data is accessed or written on the GPU, it is represented in Swift CPU code as a `Buffer`.
///
/// By default, `Buffer`s are transient and associated with a particular (usually the currently-executing) `RenderGraph`.
/// They are given backing GPU memory when the `RenderGraph` executes and are invalidated once the `RenderGraph`
/// has been submitted to the GPU. This is a useful default when passing data to the GPU that changes per frame.
///
/// If a `Buffer` needs to persist across multiple frames, `ResourceFlags.persistent` must be passed to its initialiser;
/// persistent buffers are created immediately and are valid until `Buffer.dispose()` is called on the buffer instance.
/// Note that `Buffer`s are _not_ reference-counted; you must manually manage their lifetime.
public struct Buffer : ResourceProtocol {
    public struct TextureViewDescriptor {
        public var descriptor : TextureDescriptor
        public var offset : Int
        public var bytesPerRow : Int
        
        public init(descriptor: TextureDescriptor, offset: Int, bytesPerRow: Int) {
            self.descriptor = descriptor
            self.offset = offset
            self.bytesPerRow = bytesPerRow
        }
    }
    
    public let handle: ResourceHandle
    
    /// Retrieves a `Buffer` from an existing valid `Buffer` handle.
    ///
    /// - Parameter handle: the handle for the buffer to retrieve.
    public init(handle: Handle) {
        assert(handle.resourceType == .buffer)
        self.handle = handle
    }
    
    @available(*, deprecated, renamed: "init(length:storageMode:cacheMode:usage:bytes:renderGraph:flags:)")
    public init(length: Int, storageMode: StorageMode = .managed, cacheMode: CPUCacheMode = .defaultCache, usage: BufferUsage = [], bytes: UnsafeRawPointer? = nil, frameGraph: RenderGraph?, flags: ResourceFlags = []) {
        self.init(length: length, storageMode: storageMode, cacheMode: cacheMode, usage: usage, bytes: bytes, renderGraph: frameGraph, flags: flags)
    }
    
    /// Creates a new GPU-visible buffer.
    ///
    /// - Parameter length: The minimum length, in bytes, of the buffer's allocation.
    /// - Parameter storageMode: The storage mode for the buffer, representing the pool of memory from which the buffer should be allocated.
    /// - Parameter cacheMode: The CPU cache mode for the created buffer, if it is CPU-visible. Write-combined buffers _may_ have better write performance from the CPU but will have considerable overhead when being read by the CPU.
    /// - Parameter usage: The ways in which the created buffer will be used by the GPU. Only required for persistent or history buffers; transient buffers will infer their usage.
    /// - Parameter bytes: `length` bytes to optionally copy to the buffer. The buffer must be CPU-visible, and it must either be persistent or be created during `RenderGraph` execution.
    /// - Parameter renderGraph: The render graph that this buffer will be used with, if this is a transient buffer. Only necessary for transient buffers created outside of `RenderGraph` execution (e.g. in a render pass' `init` method).
    /// - Parameter flags: The flags with which to create the buffer; for example, `ResourceFlags.persistent` for a persistent buffer.
    /// - SeeAlso: `init(descriptor:renderGraph:flags)`
    public init(length: Int, storageMode: StorageMode = .managed, cacheMode: CPUCacheMode = .defaultCache, usage: BufferUsage = [], bytes: UnsafeRawPointer? = nil, renderGraph: RenderGraph? = nil, flags: ResourceFlags = []) {
        self.init(descriptor: BufferDescriptor(length: length, storageMode: storageMode, cacheMode: cacheMode, usage: usage), bytes: bytes, renderGraph: renderGraph, flags: flags)
    }
    
    @available(*, deprecated, renamed: "init(descriptor:renderGraph:flags:)")
    public init(descriptor: BufferDescriptor, frameGraph: RenderGraph?, flags: ResourceFlags = []) {
        self.init(descriptor: descriptor, renderGraph: frameGraph, flags: flags)
    }
    
    /// Creates a new GPU-visible buffer.
    ///
    /// - Parameter descriptor: The descriptor representing the properties with which the buffer should be created.
    /// - Parameter renderGraph: The render graph that this buffer will be used with, if this is a transient buffer. Only necessary for transient buffers created outside of `RenderGraph` execution (e.g. in a render pass' `init` method).
    /// - Parameter flags: The flags with which to create the buffer; for example, `ResourceFlags.persistent` for a persistent buffer.
    public init(descriptor: BufferDescriptor, renderGraph: RenderGraph? = nil, flags: ResourceFlags = []) {
        precondition(descriptor.length >= 1, "Length \(descriptor.length) must be at least 1.")
        
        if flags.contains(.persistent) || flags.contains(.historyBuffer) {
            self = PersistentBufferRegistry.instance.allocate(descriptor: descriptor, heap: nil, flags: flags)
            
            assert(!descriptor.usageHint.isEmpty, "Persistent resources must explicitly specify their usage.")
            let didAllocate = RenderBackend.materialisePersistentResource(self)
            assert(didAllocate, "Allocation failed for persistent buffer \(self)")
            if !didAllocate { self.dispose() }

        } else {
            precondition(descriptor.storageMode != .private || RenderGraph.activeRenderGraph == nil, "GPU-private transient resources cannot be created during render graph execution. Instead, create this resource in an init() method and pass in the render graph to use.")
            
            guard let renderGraph = renderGraph ?? RenderGraph.activeRenderGraph else {
                fatalError("The RenderGraph must be specified for transient resources created outside of a render pass' execute() method.")
            }
            precondition(renderGraph.transientRegistryIndex >= 0, "Transient resources are not supported on the RenderGraph \(renderGraph)")
            self = TransientBufferRegistry.instances[renderGraph.transientRegistryIndex].allocate(descriptor: descriptor, flags: flags)
            
            if descriptor.storageMode != .private {
                renderGraph.context.transientRegistry!.accessLock.withLock {
                    _ = renderGraph.context.transientRegistry!.allocateBufferIfNeeded(self, forceGPUPrivate: false)
                }
            }
        }
    }
    
    @available(*, deprecated, renamed: "init(descriptor:bytes:renderGraph:flags:)")
    public init(descriptor: BufferDescriptor, bytes: UnsafeRawPointer?, frameGraph: RenderGraph?, flags: ResourceFlags = []) {
        self.init(descriptor: descriptor, bytes: bytes, renderGraph: frameGraph, flags: flags)
    }
    
    /// Creates a new GPU-visible buffer.
    ///
    /// - Parameter descriptor: The descriptor representing the properties with which the buffer should be created.
    /// - Parameter bytes: `length` bytes to optionally copy to the buffer. The buffer must be CPU-visible, and it must either be persistent or be created during `RenderGraph` execution.
    /// - Parameter renderGraph: The render graph that this buffer will be used with, if this is a transient buffer. Only necessary for transient buffers created outside of `RenderGraph` execution (e.g. in a render pass' `init` method).
    /// - Parameter flags: The flags with which to create the buffer; for example, `ResourceFlags.persistent` for a persistent buffer.
    public init(descriptor: BufferDescriptor, bytes: UnsafeRawPointer?, renderGraph: RenderGraph? = nil, flags: ResourceFlags = []) {
        self.init(descriptor: descriptor, renderGraph: renderGraph, flags: flags)
        
        if let bytes = bytes {
            assert(self.descriptor.storageMode != .private)
            self.withMutableContents { contents, _ in contents.copyMemory(from: UnsafeRawBufferPointer(start: bytes, count: descriptor.length)) }
        }
    }
    
    /// Suballocates a new persistent GPU-visible buffer from the provided heap.
    ///
    /// - Parameter length: The minimum length, in bytes, of the buffer's allocation.
    /// - Parameter usage: The ways in which the created buffer will be used by the GPU.
    /// - Parameter bytes: `length` bytes to optionally copy to the buffer. The buffer must be CPU-visible (i.e. allocated from a CPU-visible heap).
    /// - Parameter heap: The `Heap` from which to suballocate the buffer's memory.
    /// - Parameter flags: The flags with which to create the buffer. Must include `ResourceFlags.persistent`.
    /// - Returns: nil if the buffer could not be created (e.g. there is not enough unfragmented available space on the heap).
    public init?(length: Int, usage: BufferUsage = [], bytes: UnsafeRawPointer? = nil, heap: Heap, flags: ResourceFlags = [.persistent]) {
        self.init(descriptor: BufferDescriptor(length: length, storageMode: heap.storageMode, cacheMode: heap.cacheMode, usage: usage), bytes: bytes, heap: heap, flags: flags)
    }
    
    /// Suballocates a new persistent GPU-visible buffer from the provided heap.
    ///
    /// - Parameter descriptor: The descriptor representing the properties with which the buffer should be created. Properties which are already specified by the heap are ignored.
    /// - Parameter heap: The `Heap` from which to suballocate the buffer's memory.
    /// - Parameter flags: The flags with which to create the buffer. Must include `ResourceFlags.persistent`.
    /// - Returns: nil if the buffer could not be created (e.g. there is not enough unfragmented available space on the heap).
    public init?(descriptor: BufferDescriptor, bytes: UnsafeRawPointer? = nil, heap: Heap, flags: ResourceFlags = [.persistent]) {
        precondition(descriptor.length >= 1, "Length \(descriptor.length) must be at least 1.")
        
        assert(flags.contains(.persistent), "Heap-allocated resources must be persistent.")
        assert(!descriptor.usageHint.isEmpty, "Persistent resources must explicitly specify their usage.")
        
        var descriptor = descriptor
        descriptor.storageMode = heap.storageMode
        descriptor.cacheMode = heap.cacheMode
        
        self = PersistentBufferRegistry.instance.allocate(descriptor: descriptor, heap: heap, flags: flags)
        
        if !RenderBackend.materialisePersistentResource(self) {
            self.dispose()
            return nil
        }
        
        heap.childResources.insert(Resource(self))
        
        if let bytes = bytes {
            assert(self.descriptor.storageMode != .private)
            self.withMutableContents { contents, _ in contents.copyMemory(from: UnsafeRawBufferPointer(start: bytes, count: descriptor.length)) }
        }
    }
    
    public init(descriptor: BufferDescriptor, externalResource: Any, renderGraph: RenderGraph? = nil, flags: ResourceFlags = [.persistent, .externalOwnership]) {
        if flags.contains(.persistent) || flags.contains(.historyBuffer) {
            self = PersistentBufferRegistry.instance.allocate(descriptor: descriptor, heap: nil, flags: flags)
        } else {
            guard let renderGraph = renderGraph ?? RenderGraph.activeRenderGraph else {
                fatalError("The RenderGraph must be specified for transient resources created outside of a render pass' execute() method.")
            }
            self = TransientBufferRegistry.instances[renderGraph.transientRegistryIndex].allocate(descriptor: descriptor, flags: flags)
        }
        
        if self.flags.contains(.persistent) {
            assert(!descriptor.usageHint.isEmpty, "Persistent resources must explicitly specify their usage.")
        }
        RenderBackend.registerExternalResource(Resource(self), backingResource: externalResource)
    }
    
    public func withContents<A>(checkHasCPUAccess: Bool = true, _ perform: (UnsafeRawBufferPointer) /* async */ throws -> A) /* reasync */ rethrows -> A {
        return try self.withContents(range: self.range, checkHasCPUAccess: checkHasCPUAccess, perform)
    }
    
    public func withContents<A>(range: Range<Int>, checkHasCPUAccess: Bool = true, _ perform: (UnsafeRawBufferPointer) /* async */ throws -> A) /* reasync */ rethrows -> A {
        if checkHasCPUAccess { self.checkHasCPUAccess(accessType: .read) }
        let contents = self[\.mappedContents]?.advanced(by: range.lowerBound)
        return try /* await */perform(UnsafeRawBufferPointer(start: UnsafeRawPointer(contents), count: range.count))
    }
    
    @inlinable
    func _withMutableContents<A>(range: Range<Int>, checkHasCPUAccess: Bool = true, _ perform: (_ buffer: UnsafeMutableRawBufferPointer, _ modifiedRange: inout Range<Int>) /* async */ throws -> A) /*reasync */rethrows -> A {
        if checkHasCPUAccess { self.checkHasCPUAccess(accessType: .readWrite) }
        let contents = self[\.mappedContents]?.advanced(by: range.lowerBound)
        var modifiedRange = range
        
        let result = try /* await */perform(UnsafeMutableRawBufferPointer(start: UnsafeMutableRawPointer(contents), count: range.count), &modifiedRange)
        
        if !modifiedRange.isEmpty { // Transient buffers are flushed automatically before rendering.
            RenderBackend.buffer(self, didModifyRange: modifiedRange)
        }
        self.stateFlags.formUnion(.initialised)
        return result
    }
    
    @inlinable
    func _withMutableContents<A>(range: Range<Int>, checkHasCPUAccess: Bool = true, _ perform: (_ buffer: UnsafeMutableRawBufferPointer, _ modifiedRange: inout Range<Int>) async throws -> A) async rethrows -> A {
        if checkHasCPUAccess { self.checkHasCPUAccess(accessType: .readWrite) }
        let contents = self[\.mappedContents]?.advanced(by: range.lowerBound)
        var modifiedRange = range
        
        let result = try await perform(UnsafeMutableRawBufferPointer(start: UnsafeMutableRawPointer(contents), count: range.count), &modifiedRange)
        
        if !modifiedRange.isEmpty { // Transient buffers are flushed automatically before rendering.
            RenderBackend.buffer(self, didModifyRange: modifiedRange)
        }
        self.stateFlags.formUnion(.initialised)
        return result
    }
    
    @inlinable
    public func withMutableContents<A>(checkHasCPUAccess: Bool = true, _ perform: (_ buffer: UnsafeMutableRawBufferPointer, _ modifiedRange: inout Range<Int>) /* async */ throws -> A) /* reasync */ rethrows -> A {
        return try self.withMutableContents(range: self.range, checkHasCPUAccess: checkHasCPUAccess, perform)
    }
    
    @inlinable
    public func withMutableContents<A>(range: Range<Int>, checkHasCPUAccess: Bool = true, _ perform: (_ buffer: UnsafeMutableRawBufferPointer, _ modifiedRange: inout Range<Int>) /* async */ throws -> A) /*reasync */rethrows -> A {
        return try self._withMutableContents(range: range, checkHasCPUAccess: checkHasCPUAccess, perform)
    }
    
    @inlinable
    public func withContents<A>(waitForAccess: Bool = true, _ perform: (UnsafeRawBufferPointer) async throws -> A) async rethrows -> A {
        return try await self.withContents(range: self.range, waitForAccess: waitForAccess, perform)
    }
    
    @inlinable
    public func withContents<A>(range: Range<Int>, waitForAccess: Bool = true, _ perform: (UnsafeRawBufferPointer) async throws -> A) async rethrows -> A {
        if waitForAccess { await self.waitForCPUAccess(accessType: .read) }
        if let contents = self[\.mappedContents]?.advanced(by: range.lowerBound) {
            return try await perform(UnsafeRawBufferPointer(start: UnsafeRawPointer(contents), count: range.count))
        } else {
            preconditionFailure("Buffer \(self) has not been materialised at the time of the withContents call.")
        }
    }
    
    @inlinable
    public func withMutableContents<A>(waitForAccess: Bool = true, _ perform: (_ buffer: UnsafeMutableRawBufferPointer, _ modifiedRange: inout Range<Int>) async throws -> A) async rethrows -> A {
        return try await self.withMutableContents(range: self.range, waitForAccess: waitForAccess, perform)
    }
    
    @inlinable
    public func withMutableContents<A>(range: Range<Int>, waitForAccess: Bool = true, _ perform: (_ buffer: UnsafeMutableRawBufferPointer, _ modifiedRange: inout Range<Int>) async throws -> A) async rethrows -> A {
        if waitForAccess { await self.waitForCPUAccess(accessType: .readWrite) }
        if let _ = self[\.mappedContents] {
            return try await self._withMutableContents(range: range, checkHasCPUAccess: false, perform)
        } else {
            preconditionFailure("Buffer \(self) has not been materialised at the time of the withMutableContents call.")
        }
    }
    
    @inlinable
    public func fill(with perform: @escaping (_ buffer: UnsafeMutableRawBufferPointer, _ filledRange: inout Range<Int>) -> Void) {
        if let _ = self[\.mappedContents] {
            self.withMutableContents(perform)
        } else {
            self._deferredSliceActions.append(DeferredBufferSlice(closure: {
                $0.withMutableContents(perform)
            }))
        }
    }
    
    @inlinable
    public func fill<C : Collection>(from source: C) {
        let requiredCapacity = source.count * MemoryLayout<C.Element>.stride
        assert(self.length >= requiredCapacity)
        
        if let contents = self[\.mappedContents] {
            let range = 0..<source.count * MemoryLayout<C.Element>.stride
            if source.withContiguousStorageIfAvailable({ buffer in
                contents.copyMemory(from: UnsafeRawPointer(buffer.baseAddress!), byteCount: range.count)
            }) == nil {
                for (i, elem) in source.enumerated() {
                    contents.storeBytes(of: elem, toByteOffset: i * MemoryLayout<C.Element>.stride, as: C.Element.self)
                }
            }
            RenderBackend.buffer(self, didModifyRange: range)
            self.stateFlags.formUnion(.initialised)
        } else {
            self._deferredSliceActions.append(DeferredBufferSlice(closure: {
                $0.withMutableContents(range: range, { contents, initializedRange in
                    if source.withContiguousStorageIfAvailable({ buffer in
                        contents.copyMemory(from: UnsafeRawBufferPointer(buffer))
                    }) == nil {
                        for (i, elem) in source.enumerated() {
                            contents.baseAddress!.storeBytes(of: elem, toByteOffset: i * MemoryLayout<C.Element>.stride, as: C.Element.self)
                        }
                    }
                    
                    initializedRange = 0..<requiredCapacity
                })
            }))
        }
    }
    
    /// Makes the contents of the byte range `range` visible to the GPU.
    /// This call is usually unnecessary; the withMutableContents functions will call this for you.
    @inlinable
    public func flushRange(_ range: Range<Int>) {
        RenderBackend.buffer(self, didModifyRange: range)
    }
    
    func applyDeferredSliceActions() {
        // TODO: Add support for deferred slice actions to persistent resources.
        guard !self.flags.contains(.historyBuffer) else {
            return
        }
        
        for action in self._deferredSliceActions {
            action.apply(self)
        }
        self._deferredSliceActions.removeAll(keepingCapacity: true)
    }
    
    public var length : Int {
        return self.descriptor.length
    }
    
    public var range : Range<Int> {
        return 0..<self.descriptor.length
    }
   
    public var stateFlags: ResourceStateFlags {
        get {
            if self.flags.intersection([.historyBuffer, .persistent]) == [] {
                return []
            }
            return self[\.stateFlags] ?? []
        }
        nonmutating set {
            if self.flags.intersection([.historyBuffer, .persistent]) == [] { return }
            
            self[\.stateFlags] = newValue
        }
    }
    
    public var heap : Heap? {
        return self[\.heaps]
    }
    
    public var storageMode: StorageMode {
        return self.descriptor.storageMode
    }
    
    @usableFromInline
    var _deferredSliceActions : [DeferredBufferSlice] {
        get {
            return self[\.deferredSliceActions]!
        }
        nonmutating set {
            self[\.deferredSliceActions] = newValue
        }
    }
    
    public static var resourceType: ResourceType {
        return .buffer
    }
}

extension Buffer: CustomStringConvertible {
    public var description: String {
        return "Buffer(handle: \(self.handle)) { \(self.label.map { "label: \($0), "} ?? "")descriptor: \(self.descriptor), stateFlags: \(self.stateFlags), flags: \(self.flags) }"
    }
}

extension Buffer: ResourceProtocolImpl {
    @usableFromInline typealias SharedProperties = BufferProperties
    @usableFromInline typealias TransientProperties = BufferProperties.TransientProperties
    @usableFromInline typealias PersistentProperties = BufferProperties.PersistentProperties
    
    @usableFromInline static func transientRegistry(index: Int) -> TransientBufferRegistry? {
        return TransientBufferRegistry.instances[index]
    }
    
    @usableFromInline static var persistentRegistry: PersistentRegistry<Self> { PersistentBufferRegistry.instance }
    
    @usableFromInline typealias Descriptor = BufferDescriptor
    
    @usableFromInline static var tracksUsages: Bool { true }
}

@usableFromInline
struct BufferProperties: ResourceProperties {
    
    @usableFromInline struct TransientProperties: ResourceProperties {
        let backingBufferOffsets: UnsafeMutablePointer<Int>
        let deferredSliceActions : UnsafeMutablePointer<[DeferredBufferSlice]>
        
        @usableFromInline
        init(capacity: Int) {
            self.backingBufferOffsets = UnsafeMutablePointer.allocate(capacity: capacity)
            self.deferredSliceActions = UnsafeMutablePointer.allocate(capacity: capacity)
        }
        
        @usableFromInline
        func deallocate() {
            self.backingBufferOffsets.deallocate()
            self.deferredSliceActions.deallocate()
        }
        
        @usableFromInline
        func initialize(index: Int, descriptor: BufferDescriptor, heap: Heap?, flags: ResourceFlags) {
            self.backingBufferOffsets.advanced(by: index).initialize(to: 0)
            self.deferredSliceActions.advanced(by: index).initialize(to: [])
        }
        
        @usableFromInline
        func deinitialize(from index: Int, count: Int) {
            self.backingBufferOffsets.advanced(by: index).deinitialize(count: count)
            self.deferredSliceActions.advanced(by: index).deinitialize(count: count)
        }
    }
    
    @usableFromInline struct PersistentProperties: PersistentResourceProperties {
        
        let stateFlags : UnsafeMutablePointer<ResourceStateFlags>
        /// The index that must be completed on the GPU for each queue before the CPU can read from this resource's memory.
        let readWaitIndices : UnsafeMutablePointer<QueueCommandIndex.AtomicRepresentation>
        /// The index that must be completed on the GPU for each queue before the CPU can write to this resource's memory.
        let writeWaitIndices : UnsafeMutablePointer<QueueCommandIndex.AtomicRepresentation>
        /// The RenderGraphs that are currently using this resource.
        let activeRenderGraphs : UnsafeMutablePointer<UInt8.AtomicRepresentation>
        let heaps : UnsafeMutablePointer<Heap?>
        
        @usableFromInline
        init(capacity: Int) {
            self.stateFlags = .allocate(capacity: capacity)
            self.readWaitIndices = .allocate(capacity: capacity * QueueCommandIndices.scalarCount)
            self.writeWaitIndices = .allocate(capacity: capacity * QueueCommandIndices.scalarCount)
            self.activeRenderGraphs = .allocate(capacity: capacity)
            self.heaps = .allocate(capacity: capacity)
        }
        
        @usableFromInline
        func deallocate() {
            self.stateFlags.deallocate()
            self.readWaitIndices.deallocate()
            self.writeWaitIndices.deallocate()
            self.activeRenderGraphs.deallocate()
            self.heaps.deallocate()
        }
        
        @usableFromInline
        func initialize(index: Int, descriptor: BufferDescriptor, heap: Heap?, flags: ResourceFlags) {
            self.stateFlags.advanced(by: index).initialize(to: [])
            self.readWaitIndices.advanced(by: index * QueueCommandIndices.scalarCount).initialize(repeating: .init(0), count: QueueCommandIndices.scalarCount)
            self.writeWaitIndices.advanced(by: index * QueueCommandIndices.scalarCount).initialize(repeating: .init(0), count: QueueCommandIndices.scalarCount)
            self.activeRenderGraphs.advanced(by: index).initialize(to: UInt8.AtomicRepresentation(0))
            self.heaps.advanced(by: index).initialize(to: heap)
        }
        
        @usableFromInline
        func deinitialize(from index: Int, count: Int) {
            self.stateFlags.advanced(by: index).deinitialize(count: count)
            self.readWaitIndices.advanced(by: index * QueueCommandIndices.scalarCount).deinitialize(count: count * QueueCommandIndices.scalarCount)
            self.writeWaitIndices.advanced(by: index * QueueCommandIndices.scalarCount).deinitialize(count: count * QueueCommandIndices.scalarCount)
            self.activeRenderGraphs.advanced(by: index).deinitialize(count: count)
            self.heaps.advanced(by: index).deinitialize(count: count)
        }
        
        @usableFromInline var readWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndex.AtomicRepresentation>? { self.readWaitIndices }
        @usableFromInline var writeWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndex.AtomicRepresentation>? { self.writeWaitIndices }
        @usableFromInline var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { self.activeRenderGraphs }
    }
    
    @usableFromInline let mappedContents : UnsafeMutablePointer<UnsafeMutableRawPointer?>
    
    @usableFromInline init(capacity: Int) {
        self.mappedContents = UnsafeMutablePointer.allocate(capacity: capacity)
    }
    
    @usableFromInline func deallocate() {
        self.mappedContents.deallocate()
    }
    
    @usableFromInline func initialize(index: Int, descriptor: BufferDescriptor, heap: Heap?, flags: ResourceFlags) {
        self.mappedContents.advanced(by: index).initialize(to: nil)
    }
    
    @usableFromInline func deinitialize(from index: Int, count: Int) {
        self.mappedContents.advanced(by: index).deinitialize(count: count)
    }
}


@usableFromInline final class TransientBufferRegistry: TransientFixedSizeRegistry<Buffer> {
    @usableFromInline static let instances = TransientRegistryArray<TransientBufferRegistry>()
}

@usableFromInline final class PersistentBufferRegistry: PersistentRegistry<Buffer> {
    @usableFromInline static let instance = PersistentBufferRegistry()
}


@usableFromInline
final class DeferredBufferSlice {
    @usableFromInline let closure : (Buffer) -> Void
    
    @inlinable
    init(closure: @escaping (Buffer) -> Void) {
        self.closure = closure
    }
    
    func apply(_ buffer: Buffer) {
        self.closure(buffer)
    }
}
