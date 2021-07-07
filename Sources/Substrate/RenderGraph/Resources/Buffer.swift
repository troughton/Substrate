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
    public var handle : Handle { return UInt64(UInt(bitPattern: _handle)) }
    
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
            let didAllocate = RenderBackend.materialisePersistentBuffer(self)
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
            self[0..<self.descriptor.length, accessType: .write].withContents { $0.copyMemory(from: bytes, byteCount: self.descriptor.length) }
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
        assert(flags.contains(.persistent), "Heap-allocated resources must be persistent.")
        assert(!descriptor.usageHint.isEmpty, "Persistent resources must explicitly specify their usage.")
        
        self = PersistentBufferRegistry.instance.allocate(descriptor: descriptor, heap: heap, flags: flags)
        
        if !RenderBackend.materialisePersistentBuffer(self) {
            self.dispose()
            return nil
        }
        
        heap.childResources.insert(Resource(self))
        
        
        if let bytes = bytes {
            assert(self.descriptor.storageMode != .private)
            self[0..<self.descriptor.length, accessType: .write].withContents { $0.copyMemory(from: bytes, byteCount: self.descriptor.length) }
        }
    }
    
    public func withContents<A>(_ perform: (UnsafeRawBufferPointer) /* async */ throws -> A) /* reasync */ rethrows -> A {
        self.waitForCPUAccess(accessType: .read)
        let contents = RenderBackend.bufferContents(for: self, range: self.range)
        return try /* await */perform(UnsafeRawBufferPointer(start: UnsafeRawPointer(contents), count: self.length))
    }
    
    public func withContents<A>(range: Range<Int>, _ perform: (UnsafeRawBufferPointer) /* async */ throws -> A) /* reasync */ rethrows -> A {
        self.waitForCPUAccess(accessType: .read)
        let contents = RenderBackend.bufferContents(for: self, range: range)
        return try /* await */perform(UnsafeRawBufferPointer(start: UnsafeRawPointer(contents), count: range.count))
    }
    
    public func withMutableContents<A>(_ perform: (_ buffer: UnsafeMutableRawBufferPointer, _ modifiedRange: inout Range<Int>) /* async */ throws -> A) /* reasync */ rethrows -> A {
        self.waitForCPUAccess(accessType: .readWrite)
        let contents = RenderBackend.bufferContents(for: self, range: self.range)
        var modifiedRange = self.range
        
        let result = try /* await */perform(UnsafeMutableRawBufferPointer(start: UnsafeMutableRawPointer(contents), count: self.length), &modifiedRange)
        
        RenderBackend.buffer(self, didModifyRange: modifiedRange)
        self.stateFlags.formUnion(.initialised)
        return result
    }
    
    public func withMutableContents<A>(range: Range<Int>, _ perform: (_ buffer: UnsafeMutableRawBufferPointer, _ modifiedRange: inout Range<Int>) /* async */ throws -> A) /*reasync */rethrows -> A {
        self.waitForCPUAccess(accessType: .readWrite)
        let contents = RenderBackend.bufferContents(for: self, range: range)
        var modifiedRange = range
        
        let result = try /* await */perform(UnsafeMutableRawBufferPointer(start: UnsafeMutableRawPointer(contents), count: range.count), &modifiedRange)
        
        RenderBackend.buffer(self, didModifyRange: modifiedRange)
        self.stateFlags.formUnion(.initialised)
        return result
    }
    
    public subscript(range: Range<Int>) -> RawBufferSlice {
        return self[range, accessType: .readWrite]
    }
    
    public subscript(range: Range<Int>, accessType accessType: ResourceAccessType) -> RawBufferSlice {
        self.waitForCPUAccess(accessType: accessType)
        return RawBufferSlice(buffer: self, range: range, accessType: accessType)
    }
    
    public func withDeferredSlice(range: Range<Int>, perform: @escaping (RawBufferSlice) -> Void) {
        if self.flags.contains(.persistent) {
            perform(self[range])
        } else {
            self._deferredSliceActions.append(DeferredRawBufferSlice(range: range, closure: perform))
        }
    }
    
    public subscript<T>(as type: T.Type, accessType accessType: ResourceAccessType = .readWrite) -> BufferSlice<T> {
        return self[byteRange: self.range, as: type, accessType: .readWrite]
    }
    
    public subscript<T>(byteRange range: Range<Int>, as type: T.Type, accessType accessType: ResourceAccessType = .readWrite) -> BufferSlice<T> {
        self.waitForCPUAccess(accessType: accessType)
        return BufferSlice(buffer: self, range: range, accessType: accessType)
    }
    
    public func withDeferredSlice<T>(byteRange range: Range<Int>, perform: @escaping (BufferSlice<T>) -> Void) {
        if self.flags.contains(.persistent) {
            perform(self[byteRange: range, as: T.self])
        } else {
            self._deferredSliceActions.append(DeferredTypedBufferSlice(range: range, closure: perform))
        }
    }
    
    public func fillWhenMaterialised<C : Collection>(from source: C) {
        let requiredCapacity = source.count * MemoryLayout<C.Element>.stride
        assert(self.length >= requiredCapacity)
        
        self.withDeferredSlice(byteRange: 0..<requiredCapacity) { (slice: BufferSlice<C.Element>) -> Void in
            slice.withContents { (contents: UnsafeMutablePointer<C.Element>) in
                _ = UnsafeMutableBufferPointer(start: contents, count: source.count).initialize(from: source)
            }
        }
    }
    
    public func onMaterialiseGPUBacking(perform: @escaping (Buffer) -> Void) {
        if self.flags.contains(.persistent) {
            perform(self)
        } else {
            self._deferredSliceActions.append(EmptyBufferSlice(closure: perform))
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
    static let instances = (0..<TransientRegistryManager.maxTransientRegistries).map { i in TransientBufferRegistry(transientRegistryIndex: i) }
}

final class PersistentBufferRegistry: PersistentRegistry<Buffer> {
    static let instance = PersistentBufferRegistry()
}


public protocol DeferredBufferSlice {
    func apply(_ buffer: Buffer)
}

final class DeferredRawBufferSlice : DeferredBufferSlice {
    let range : Range<Int>
    let closure : (RawBufferSlice) -> Void
    
    init(range: Range<Int>, closure: @escaping (RawBufferSlice) -> Void) {
        self.range = range
        self.closure = closure
    }
    
    func apply(_ buffer: Buffer) {
        self.closure(buffer[self.range])
    }
}

final class DeferredTypedBufferSlice<T> : DeferredBufferSlice {
    let range : Range<Int>
    let closure : (BufferSlice<T>) -> Void
    
    init(range: Range<Int>, closure: @escaping (BufferSlice<T>) -> Void) {
        self.range = range
        self.closure = closure
    }
    
    func apply(_ buffer: Buffer) {
        self.closure(buffer[byteRange: self.range, as: T.self])
    }
}

final class EmptyBufferSlice : DeferredBufferSlice {
    let closure : (Buffer) -> Void
    
    init(closure: @escaping (Buffer) -> Void) {
        self.closure = closure
    }
    
    func apply(_ buffer: Buffer) {
        self.closure(buffer)
    }
}

public final class RawBufferSlice {
    public let buffer : Buffer
    @usableFromInline var _range : Range<Int>
    
    @usableFromInline
    let contents : UnsafeMutableRawPointer
    
    @usableFromInline
    let accessType : ResourceAccessType
    
    var writtenToGPU = false
    
    internal init(buffer: Buffer, range: Range<Int>, accessType: ResourceAccessType) {
        self.buffer = buffer
        self._range = range
        self.contents = RenderBackend.bufferContents(for: self.buffer, range: self._range)
        self.accessType = accessType
    }
    
    public func withContents<A>(_ perform: (UnsafeMutableRawPointer) throws -> A) rethrows -> A {
        return try perform(self.contents)
    }
    
    public var range : Range<Int> {
        return self._range
    }
    
    public func setBytesWrittenCount(_ bytesAccessed: Int) {
        assert(bytesAccessed <= self.range.count)
        self._range = self.range.lowerBound..<(self.range.lowerBound + bytesAccessed)
        self.writtenToGPU = false
    }
    
    public func forceFlush() {
        if self.accessType == .read { return }
        
        RenderBackend.buffer(self.buffer, didModifyRange: self.range)
        self.writtenToGPU = true
        
        self.buffer.stateFlags.formUnion(.initialised)
    }
    
    deinit {
        if !self.writtenToGPU {
            self.forceFlush()
        }
    }
}

public final class BufferSlice<T> {
    public let buffer : Buffer
    @usableFromInline var _range : Range<Int>
    @usableFromInline
    let contents : UnsafeMutablePointer<T>
    @usableFromInline
    let accessType : ResourceAccessType
    
    var writtenToGPU = false
    
    internal init(buffer: Buffer, range: Range<Int>, accessType: ResourceAccessType) {
        self.buffer = buffer
        self._range = range
        self.contents = RenderBackend.bufferContents(for: self.buffer, range: self._range).bindMemory(to: T.self, capacity: range.count)
        self.accessType = accessType
    }
    
    public subscript(index: Int) -> T {
        get {
            assert(self.accessType != .write)
            return self.contents[index]
        }
        set {
            assert(self.accessType != .read)
            self.contents[index] = newValue
        }
    }
    
    public var range : Range<Int> {
        return self._range
    }
    
    public func withContents<A>(_ perform: (UnsafeMutablePointer<T>) throws -> A) rethrows -> A {
        return try perform(self.contents)
    }
    
    public func setElementsWrittenCount(_ elementsAccessed: Int) {
        assert(self.accessType != .read)
        
        let bytesAccessed = elementsAccessed * MemoryLayout<T>.stride
        assert(bytesAccessed <= self.range.count)
        self._range = self.range.lowerBound..<(self.range.lowerBound + bytesAccessed)
        self.writtenToGPU = false
    }
    
    public func forceFlush() {
        if self.accessType == .read { return }
        
        RenderBackend.buffer(self.buffer, didModifyRange: self.range)
        self.writtenToGPU = true
        
        self.buffer.stateFlags.formUnion(.initialised)
    }
    
    deinit {
        if !self.writtenToGPU {
            self.forceFlush()
        }
    }
}
