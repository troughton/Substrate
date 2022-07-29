//
//  Buffer.swift
//  
//
//  Created by Thomas Roughton on 2/07/21.
//

import SubstrateUtilities

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
    

    @usableFromInline let _handle : UnsafeRawPointer
    @inlinable public var handle : Handle { return UInt64(UInt(bitPattern: _handle)) }
    
    /// Retrieves a `Buffer` from an existing valid `Buffer` handle.
    ///
    /// - Parameter handle: the handle for the buffer to retrieve.
    public init(handle: Handle) {
        assert(Resource(handle: handle).type == .buffer)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
    }
    
    @available(*, deprecated, renamed: "init(length:storageMode:cacheMode:usage:bytes:renderGraph:flags:)")
    public init(length: Int, storageMode: StorageMode = .managed, cacheMode: CPUCacheMode = .defaultCache, usage: BufferUsage = .unknown, bytes: UnsafeRawPointer? = nil, frameGraph: RenderGraph?, flags: ResourceFlags = []) {
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
    public init(length: Int, storageMode: StorageMode = .managed, cacheMode: CPUCacheMode = .defaultCache, usage: BufferUsage = .unknown, bytes: UnsafeRawPointer? = nil, renderGraph: RenderGraph? = nil, flags: ResourceFlags = []) {
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
        } else {
            guard let renderGraph = renderGraph ?? RenderGraph.activeRenderGraph else {
                fatalError("The RenderGraph must be specified for transient resources created outside of a render pass' execute() method.")
            }
            precondition(renderGraph.transientRegistryIndex >= 0, "Transient resources are not supported on the RenderGraph \(renderGraph)")
            self = TransientBufferRegistry.instances[renderGraph.transientRegistryIndex].allocate(descriptor: descriptor, flags: flags)
        }
        
        if self.flags.contains(.persistent) {
            assert(!descriptor.usageHint.isEmpty, "Persistent resources must explicitly specify their usage.")
            let didAllocate = RenderBackend.materialiseResource(self)
            assert(didAllocate, "Allocation failed for persistent buffer \(self)")
            if !didAllocate { self.dispose() }
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
    public init?(length: Int, usage: BufferUsage = .unknown, bytes: UnsafeRawPointer? = nil, heap: Heap, flags: ResourceFlags = [.persistent]) {
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
        
        if !RenderBackend.materialiseResource(self) {
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
        let contents = RenderBackend.bufferContents(for: self, range: range)
        return try /* await */perform(UnsafeRawBufferPointer(start: UnsafeRawPointer(contents), count: range.count))
    }
    
    @inlinable
    func _withMutableContents<A>(range: Range<Int>, checkHasCPUAccess: Bool = true, _ perform: (_ buffer: UnsafeMutableRawBufferPointer, _ modifiedRange: inout Range<Int>) /* async */ throws -> A) /*reasync */rethrows -> A {
        if checkHasCPUAccess { self.checkHasCPUAccess(accessType: .readWrite) }
        let contents = RenderBackend.bufferContents(for: self, range: range)
        var modifiedRange = range
        
        let result = try /* await */perform(UnsafeMutableRawBufferPointer(start: UnsafeMutableRawPointer(contents), count: range.count), &modifiedRange)
        
        if !modifiedRange.isEmpty, self._usesPersistentRegistry { // Transient buffers are flushed automatically before rendering.
            RenderBackend.buffer(self, didModifyRange: modifiedRange)
        }
        self.stateFlags.formUnion(.initialised)
        return result
    }
    
    @inlinable
    func _withMutableContents<A>(range: Range<Int>, checkHasCPUAccess: Bool = true, _ perform: (_ buffer: UnsafeMutableRawBufferPointer, _ modifiedRange: inout Range<Int>) async throws -> A) async rethrows -> A {
        if checkHasCPUAccess { self.checkHasCPUAccess(accessType: .readWrite) }
        let contents = RenderBackend.bufferContents(for: self, range: range)
        var modifiedRange = range
        
        let result = try await perform(UnsafeMutableRawBufferPointer(start: UnsafeMutableRawPointer(contents), count: range.count), &modifiedRange)
        
        if !modifiedRange.isEmpty, self._usesPersistentRegistry { // Transient buffers are flushed automatically before rendering.
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
        if let contents = RenderBackend.bufferContents(for: self, range: range) {
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
        if let _ = RenderBackend.bufferContents(for: self, range: range) {
            return try await self._withMutableContents(range: range, checkHasCPUAccess: false, perform)
        } else {
            preconditionFailure("Buffer \(self) has not been materialised at the time of the withMutableContents call.")
        }
    }
    
    @inlinable
    public func fill(with perform: @escaping (_ buffer: UnsafeMutableRawBufferPointer, _ filledRange: inout Range<Int>) -> Void) {
        if let _ = RenderBackend.bufferContents(for: self, range: self.range) {
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
        
        if let contents = RenderBackend.bufferContents(for: self, range: range) {
            let range = 0..<source.count * MemoryLayout<C.Element>.stride
            _ = UnsafeMutableRawBufferPointer(start: contents, count: range.count).initializeMemory(as: C.Element.self, from: source)
            if self._usesPersistentRegistry { // Transient buffers are flushed automatically before rendering.
                RenderBackend.buffer(self, didModifyRange: range)
            }
            self.stateFlags.formUnion(.initialised)
        } else {
            self._deferredSliceActions.append(DeferredBufferSlice(closure: {
                $0.withMutableContents(range: range, {
                    let initializedBuffer = $0.bindMemory(to: C.Element.self).initialize(from: source)
                    $1 = 0..<initializedBuffer.1 * MemoryLayout<C.Element>.stride
                })
            }))
        }
    }
    
    /// Makes the contents of the byte range `range` visible to the GPU.
    /// This call is usually unnecessary; the withMutableContents functions will call this for you.
    @inlinable
    public func flushRange(_ range: Range<Int>) {
        if self._usesPersistentRegistry { // Transient buffers are flushed automatically before rendering.
            RenderBackend.buffer(self, didModifyRange: range)
        }
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
    
    public internal(set) var descriptor : BufferDescriptor {
        get {
            return self[\.descriptors]
        }
        nonmutating set {
            self[\.descriptors] = newValue
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
    typealias SharedProperties = BufferProperties
    typealias TransientProperties = BufferProperties.TransientProperties
    typealias PersistentProperties = BufferProperties.PersistentProperties
    
    static func transientRegistry(index: Int) -> TransientBufferRegistry? {
        return TransientBufferRegistry.instances[index]
    }
    
    static var persistentRegistry: PersistentRegistry<Self> { PersistentBufferRegistry.instance }
    
    typealias Descriptor = BufferDescriptor
}

@usableFromInline
struct BufferProperties: SharedResourceProperties {
    
    struct TransientProperties: ResourceProperties {
        var deferredSliceActions : UnsafeMutablePointer<[DeferredBufferSlice]>
        
        @usableFromInline
        init(capacity: Int) {
            self.deferredSliceActions = UnsafeMutablePointer.allocate(capacity: capacity)
        }
        
        @usableFromInline
        func deallocate() {
            self.deferredSliceActions.deallocate()
        }
        
        @usableFromInline
        func initialize(index: Int, descriptor: BufferDescriptor, heap: Heap?, flags: ResourceFlags) {
            self.deferredSliceActions.advanced(by: index).initialize(to: [])
        }
        
        @usableFromInline
        func deinitialize(from index: Int, count: Int) {
            self.deferredSliceActions.advanced(by: index).deinitialize(count: count)
        }
    }
    
    struct PersistentProperties: PersistentResourceProperties {
        
        let stateFlags : UnsafeMutablePointer<ResourceStateFlags>
        /// The index that must be completed on the GPU for each queue before the CPU can read from this resource's memory.
        let readWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The index that must be completed on the GPU for each queue before the CPU can write to this resource's memory.
        let writeWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The RenderGraphs that are currently using this resource.
        let activeRenderGraphs : UnsafeMutablePointer<UInt8.AtomicRepresentation>
        let heaps : UnsafeMutablePointer<Heap?>
        
        @usableFromInline
        init(capacity: Int) {
            self.stateFlags = .allocate(capacity: capacity)
            self.readWaitIndices = .allocate(capacity: capacity)
            self.writeWaitIndices = .allocate(capacity: capacity)
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
            self.readWaitIndices.advanced(by: index).initialize(to: SIMD8(repeating: 0))
            self.writeWaitIndices.advanced(by: index).initialize(to: SIMD8(repeating: 0))
            self.activeRenderGraphs.advanced(by: index).initialize(to: UInt8.AtomicRepresentation(0))
            self.heaps.advanced(by: index).initialize(to: heap)
        }
        
        @usableFromInline
        func deinitialize(from index: Int, count: Int) {
            self.stateFlags.advanced(by: index).deinitialize(count: count)
            self.readWaitIndices.advanced(by: index).deinitialize(count: count)
            self.writeWaitIndices.advanced(by: index).deinitialize(count: count)
            self.activeRenderGraphs.advanced(by: index).deinitialize(count: count)
            self.heaps.advanced(by: index).deinitialize(count: count)
        }
        
        var readWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { self.readWaitIndices }
        var writeWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { self.writeWaitIndices }
        var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { self.activeRenderGraphs }
    }
    
    var descriptors : UnsafeMutablePointer<BufferDescriptor>
    var usages : UnsafeMutablePointer<ChunkArray<ResourceUsage>>
    
    init(capacity: Int) {
        self.descriptors = UnsafeMutablePointer.allocate(capacity: capacity)
        self.usages = UnsafeMutablePointer.allocate(capacity: capacity)
    }
    
    func deallocate() {
        self.descriptors.deallocate()
        self.usages.deallocate()
    }
    
    func initialize(index: Int, descriptor: BufferDescriptor, heap: Heap?, flags: ResourceFlags) {
        self.descriptors.advanced(by: index).initialize(to: descriptor)
        self.usages.advanced(by: index).initialize(to: ChunkArray())
    }
    
    func deinitialize(from index: Int, count: Int) {
        self.descriptors.advanced(by: index).deinitialize(count: count)
        self.usages.advanced(by: index).deinitialize(count: count)
    }
    
    var usagesOptional: UnsafeMutablePointer<ChunkArray<ResourceUsage>>? { self.usages }
}


final class TransientBufferRegistry: TransientFixedSizeRegistry<Buffer> {
    static let instances = TransientRegistryArray<TransientBufferRegistry>()
}

final class PersistentBufferRegistry: PersistentRegistry<Buffer> {
    static let instance = PersistentBufferRegistry()
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
