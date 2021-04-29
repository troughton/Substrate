//
//  Resources.swift
//  RenderAPI
//
//  Created by Joseph Bennett on 18/12/17.
//

import SubstrateUtilities
import Atomics

public enum ResourceType : UInt8 {
    case buffer = 1
    case texture
    case heap
    case sampler
    case threadgroupMemory
    case argumentBuffer
    case argumentBufferArray
    case imageblockData
    case imageblock
    case visibleFunctionTable
    case primitiveAccelerationStructure
    case instanceAccelerationStructure
    case intersectionFunctionTable
}

/*!
 @abstract Points at which a fence may be waited on or signaled.
 @constant RenderStageVertex   All vertex work prior to rasterization has completed.
 @constant RenderStageFragment All rendering work has completed.
 */
public struct RenderStages : OptionSet, Hashable {
    
    public let rawValue : UInt
    
    @inlinable
    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }
    
    public static var vertex: RenderStages = RenderStages(rawValue: 1 << 0)
    public static var fragment: RenderStages = RenderStages(rawValue: 1 << 1)
    
    public static var compute: RenderStages = RenderStages(rawValue: 1 << 5)
    public static var blit: RenderStages = RenderStages(rawValue: 1 << 6)
    
    public static var cpuBeforeRender: RenderStages = RenderStages(rawValue: 1 << 7)
    
    public var first : RenderStages {
        switch (self.contains(.vertex), self.contains(.fragment)) {
        case (true, _):
            return .vertex
        case (false, true):
            return .fragment
        default:
            return self
        }
    }
    
    public var last : RenderStages {
        switch (self.contains(.vertex), self.contains(.fragment)) {
        case (_, true):
            return .fragment
        case (true, false):
            return .vertex
        default:
            return self
        }
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.rawValue)
    }
}

public struct ResourceFlags : OptionSet {
    public let rawValue: UInt16
    
    @inlinable
    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }
    
    public static let persistent = ResourceFlags(rawValue: 1 << 0)
    public static let windowHandle = ResourceFlags(rawValue: 1 << 1)
    public static let historyBuffer = ResourceFlags(rawValue: 1 << 2)
    public static let externalOwnership = ResourceFlags(rawValue: (1 << 3) | (1 << 0))
    public static let immutableOnceInitialised = ResourceFlags(rawValue: 1 << 4)
    /// If this resource is a view into another resource.
    public static let resourceView = ResourceFlags(rawValue: 1 << 5)
}

public struct ResourceStateFlags : OptionSet {
    public let rawValue: UInt16
    
    @inlinable
    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }
    
    public static let initialised = ResourceStateFlags(rawValue: 1 << 0)
}

public struct ResourceAccessType: OptionSet {
    public let rawValue: UInt8
    
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
    
    public static let read = ResourceAccessType(rawValue: 1 << 0)
    public static let write = ResourceAccessType(rawValue: 1 << 1)
    public static let readWrite: ResourceAccessType = [.read, .write]
}

public enum ResourcePurgeableState {
    case nonDiscardable
    case discardable
    case discarded
}

public typealias ActiveRenderGraphMask = UInt8

public protocol ResourceProtocol : Hashable {
    init(handle: Handle)
    func dispose()
    
    var handle: Handle { get }
    var stateFlags: ResourceStateFlags { get nonmutating set }
    
    var usages: ChunkArray<ResourceUsage> { get nonmutating set }
    
    var label: String? { get nonmutating set }
    var storageMode: StorageMode { get }

    /// The command buffer index on which to wait on a particular queue `queue` before it is safe to perform an access of type `type`.
    subscript(waitIndexFor queue: Queue, accessType type: ResourceAccessType) -> UInt64 { get nonmutating set }
    
    /// Returns whether or not a resource handle represents a valid GPU resource.
    /// A resource handle is valid if it is a transient resource that was allocated in the current frame
    /// or is a persistent resource that has not been disposed.
    var isValid: Bool { get }
    
    /// Returns whether the resource is known to currently be in use by the CPU or GPU.
    var isKnownInUse: Bool { get }
    
    /// Marks the resource as being currently in use by `renderGraph`, ensuring that, if `dispose()` is called,
    /// it will not get deallocated until after the `renderGraph` has completed.
    func markAsUsed(by renderGraph: RenderGraph)
    
    func markAsUsed(activeRenderGraphMask: ActiveRenderGraphMask)
    
    var purgeableState: ResourcePurgeableState { get nonmutating set }
    func updatePurgeableState(to: ResourcePurgeableState) -> ResourcePurgeableState
}

extension ResourceProtocol {
    
    @inlinable
    public static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.handle == rhs.handle
    }
    
    /// Note that setting the purgeable state to discardable or discarded while the resource is in use results in invalid behaviour.
    public var purgeableState: ResourcePurgeableState {
        get {
            return RenderBackend.updatePurgeableState(for: Resource(self), to: nil)
        }
        nonmutating set {
            _ = self.updatePurgeableState(to: newValue)
        }
    }
    
    /// Note that updating the purgeable state to discardable or discarded while the resource is in use results in invalid behaviour.
    @discardableResult
    public func updatePurgeableState(to: ResourcePurgeableState) -> ResourcePurgeableState {
        let oldValue = RenderBackend.updatePurgeableState(for: Resource(self), to: to)
        if to == .discarded || oldValue == .discarded {
            self.discardContents()
        }
        return oldValue
    }
    
    public func markAsUsed(by renderGraph: RenderGraph) {
        self.markAsUsed(activeRenderGraphMask: 1 << renderGraph.queue.index)
    }
}

public struct Resource : ResourceProtocol, Hashable {
    @usableFromInline let _handle : UnsafeRawPointer
    @inlinable public var handle : Handle { return UInt64(UInt(bitPattern: _handle)) }
    
    @inlinable
    public init<R : ResourceProtocol>(_ resource: R) {
        self._handle = UnsafeRawPointer(bitPattern: UInt(resource.handle))!
    }
    
    @inlinable
    public init(handle: Handle) {
        assert(ResourceType(rawValue: ResourceType.RawValue(truncatingIfNeeded: handle.bits(in: Self.typeBitsRange))) != nil)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
    }
    
    @inlinable
    public var buffer : Buffer? {
        if self.type == .buffer {
            return Buffer(handle: self.handle)
        } else {
            return nil
        }
    }
    
    @inlinable
    public var texture : Texture? {
        if self.type == .texture {
            return Texture(handle: self.handle)
        } else {
            return nil
        }
    }
    
    @inlinable
    public var argumentBuffer : ArgumentBuffer? {
        if self.type == .argumentBuffer {
            return ArgumentBuffer(handle: self.handle)
        } else {
            return nil
        }
    }
    
    @inlinable
    public var argumentBufferArray : ArgumentBufferArray? {
        if self.type == .argumentBufferArray {
            return ArgumentBufferArray(handle: self.handle)
        } else {
            return nil
        }
    }
    
    @inlinable
    public var heap : Heap? {
        if self.type == .heap {
            return Heap(handle: self.handle)
        } else {
            return nil
        }
    }
    
    @inlinable
    public var stateFlags: ResourceStateFlags {
        get {
            switch self.type {
            case .buffer:
                return Buffer(handle: self.handle).stateFlags
            case .texture:
                return Texture(handle: self.handle).stateFlags
            case .argumentBuffer:
                return ArgumentBuffer(handle: self.handle).stateFlags
            case .argumentBufferArray:
                return ArgumentBufferArray(handle: self.handle).stateFlags
            default:
                fatalError()
            }
        }
        nonmutating set {
            switch self.type {
            case .buffer:
                Buffer(handle: self.handle).stateFlags = newValue
            case .texture:
                Texture(handle: self.handle).stateFlags = newValue
            case .argumentBuffer:
                ArgumentBuffer(handle: self.handle).stateFlags = newValue
            case .argumentBufferArray:
                ArgumentBufferArray(handle: self.handle).stateFlags = newValue
            default:
                fatalError()
            }
        }
    }
    
    @inlinable
    public var storageMode: StorageMode {
        get {
            switch self.type {
            case .buffer:
                return Buffer(handle: self.handle).storageMode
            case .texture:
                return Texture(handle: self.handle).storageMode
            case .argumentBuffer:
                return ArgumentBuffer(handle: self.handle).storageMode
            case .argumentBufferArray:
                return ArgumentBufferArray(handle: self.handle).storageMode
            default:
                fatalError()
            }
        }
    }
    
    @inlinable
    public var label: String? {
        get {
            switch self.type {
            case .buffer:
                return Buffer(handle: self.handle).label
            case .texture:
                return Texture(handle: self.handle).label
            case .argumentBuffer:
                return ArgumentBuffer(handle: self.handle).label
            case .argumentBufferArray:
                return ArgumentBufferArray(handle: self.handle).label
            default:
                fatalError()
            }
        }
        nonmutating set {
            switch self.type {
            case .buffer:
                Buffer(handle: self.handle).label = newValue
            case .texture:
                Texture(handle: self.handle).label = newValue
            case .argumentBuffer:
                ArgumentBuffer(handle: self.handle).label = newValue
            case .argumentBufferArray:
                ArgumentBufferArray(handle: self.handle).label = newValue
            default:
                fatalError()
            }
        }
    }
    
    @inlinable
    public subscript(waitIndexFor queue: Queue, accessType type: ResourceAccessType) -> UInt64 {
        get {
            switch self.type {
            case .buffer:
                return Buffer(handle: self.handle)[waitIndexFor: queue, accessType: type]
            case .texture:
                return Texture(handle: self.handle)[waitIndexFor: queue, accessType: type]
            case .argumentBuffer:
                return ArgumentBuffer(handle: self.handle)[waitIndexFor: queue, accessType: type]
            case .argumentBufferArray:
                return ArgumentBufferArray(handle: self.handle)[waitIndexFor: queue, accessType: type]
            default:
                return 0
            }
        }
        nonmutating set {
            switch self.type {
            case .buffer:
                Buffer(handle: self.handle)[waitIndexFor: queue, accessType: type] = newValue
            case .texture:
                Texture(handle: self.handle)[waitIndexFor: queue, accessType: type] = newValue
            case .argumentBuffer:
                ArgumentBuffer(handle: self.handle)[waitIndexFor: queue, accessType: type] = newValue
            case .argumentBufferArray:
                ArgumentBufferArray(handle: self.handle)[waitIndexFor: queue, accessType: type] = newValue
            default:
                fatalError()
            }
        }
    }
    
    @inlinable
    public var usages: ChunkArray<ResourceUsage> {
        get {
            switch self.type {
            case .buffer:
                return Buffer(handle: self.handle).usages
            case .texture:
                return Texture(handle: self.handle).usages
            case .argumentBuffer:
                return ArgumentBuffer(handle: self.handle).usages
            default:
                return ChunkArray()
            }
        }
        nonmutating set {
            switch self.type {
            case .buffer:
                Buffer(handle: self.handle).usages = newValue
            case .texture:
                Texture(handle: self.handle).usages = newValue
            case .argumentBuffer:
                ArgumentBuffer(handle: self.handle).usages = newValue
            default:
                fatalError()
            }
        }
    }
    
    @inlinable
    public var isKnownInUse: Bool {
        switch self.type {
        case .buffer:
            return Buffer(handle: self.handle).isKnownInUse
        case .texture:
            return Texture(handle: self.handle).isKnownInUse
        case .argumentBuffer:
            return ArgumentBuffer(handle: self.handle).isKnownInUse
        case .argumentBufferArray:
            return ArgumentBufferArray(handle: self.handle).isKnownInUse
        case .heap:
            return Heap(handle: self.handle).isKnownInUse
        default:
            fatalError()
        }
    }
    
    @inlinable
    public var isValid: Bool {
        switch self.type {
        case .buffer:
            return Buffer(handle: self.handle).isValid
        case .texture:
            return Texture(handle: self.handle).isValid
        case .argumentBuffer:
            return ArgumentBuffer(handle: self.handle).isValid
        case .argumentBufferArray:
            return ArgumentBufferArray(handle: self.handle).isValid
        case .heap:
            return Heap(handle: self.handle).isValid
        default:
            fatalError()
        }
    }
    
    @inlinable
    public var baseResource: Resource? {
        get {
            switch self.type {
            case .texture:
                return Texture(handle: self.handle).baseResource
            default:
                return nil
            }
        }
    }
    
    public func markAsUsed(activeRenderGraphMask: ActiveRenderGraphMask) {
        switch self.type {
        case .buffer:
            Buffer(handle: self.handle).markAsUsed(activeRenderGraphMask: activeRenderGraphMask)
        case .texture:
            Texture(handle: self.handle).markAsUsed(activeRenderGraphMask: activeRenderGraphMask)
        case .argumentBuffer:
            ArgumentBuffer(handle: self.handle).markAsUsed(activeRenderGraphMask: activeRenderGraphMask)
        case .argumentBufferArray:
            ArgumentBufferArray(handle: self.handle).markAsUsed(activeRenderGraphMask: activeRenderGraphMask)
        case .heap:
            Heap(handle: self.handle).markAsUsed(activeRenderGraphMask: activeRenderGraphMask)
        default:
            break
        }
    }
    
    @inlinable
    public func dispose() {
        switch self.type {
        case .buffer:
            Buffer(handle: self.handle).dispose()
        case .texture:
            Texture(handle: self.handle).dispose()
        case .argumentBuffer:
            ArgumentBuffer(handle: self.handle).dispose()
        case .argumentBufferArray:
            ArgumentBufferArray(handle: self.handle).dispose()
        case .heap:
            Heap(handle: self.handle).dispose()
        default:
            break
        }
    }
}

extension Resource: CustomStringConvertible {
    public var description: String {
        switch self.type {
        case .buffer:
            return Buffer(handle: self.handle).description
        case .texture:
            return Texture(handle: self.handle).description
        case .argumentBuffer:
            return ArgumentBuffer(handle: self.handle).description
        case .argumentBufferArray:
            return ArgumentBufferArray(handle: self.handle).description
        case .heap:
            return Heap(handle: self.handle).description
        default:
            return "Resource(type: \(self.type), index: \(self.index), flags: \(self.flags))"
        }
    }
}

extension Resource : CustomHashable {
    public var customHashValue : Int {
        return self.hashValue
    }
}

extension ResourceProtocol {
    public typealias Handle = UInt64
    
    @inlinable
    public static var typeBitsRange : Range<Int> { return 56..<64 }
    
    @inlinable
    public static var flagBitsRange : Range<Int> { return 40..<56 }
    
    @inlinable
    public static var generationBitsRange : Range<Int> { return 32..<40 }
    
    @inlinable
    public static var transientRegistryIndexBitsRange : Range<Int> { return 28..<32 }
    
    @inlinable
    public static var indexBitsRange : Range<Int> { return 0..<28 }
    
    @inlinable
    public var type : ResourceType {
        return ResourceType(rawValue: ResourceType.RawValue(truncatingIfNeeded: self.handle.bits(in: Self.typeBitsRange)))!
    }
    
    @inlinable
    public var flags : ResourceFlags {
        return ResourceFlags(rawValue: ResourceFlags.RawValue(truncatingIfNeeded: self.handle.bits(in: Self.flagBitsRange)))
    }

    @inlinable
    public var generation : UInt8 {
        return UInt8(truncatingIfNeeded: self.handle.bits(in: Self.generationBitsRange))
    }
    
    @inlinable
    public var transientRegistryIndex : Int {
        return Int(self.handle.bits(in: Self.transientRegistryIndexBitsRange))
    }
    
    @inlinable
    public var index : Int {
        return Int(truncatingIfNeeded: self.handle.bits(in: Self.indexBitsRange))
    }
    
    @inlinable
    public var _usesPersistentRegistry : Bool {
        if self.flags.contains(.persistent) || self.flags.contains(.historyBuffer) {
            return true
        } else {
            return false
        }
    }
    
    @inlinable
    public func markAsInitialised() {
        self.stateFlags.formUnion(.initialised)
    }
    
    @inlinable
    public func discardContents() {
        self.stateFlags.remove(.initialised)
    }
    
    @inlinable
    public var isTextureView : Bool {
        return self.flags.contains(.resourceView)
    }
    
    @inlinable
    public var usages : ChunkArray<ResourceUsage> {
        get {
            return ChunkArray()
        }
        nonmutating set {
            fatalError()
        }
    }
    
    @inlinable
    public subscript(waitIndexFor queue: Queue, accessType type: ResourceAccessType) -> UInt64 {
        get {
            return 0
        }
        nonmutating set {
            fatalError()
        }
    }
    
    public func waitForCPUAccess(accessType: ResourceAccessType) {
        guard self.flags.contains(.persistent) else { return }
        if !self.stateFlags.contains(.initialised) { return }
        
        for queue in QueueRegistry.allQueues {
            let waitIndex = self[waitIndexFor: queue, accessType: accessType]
            queue.waitForCommand(waitIndex)
        }
    }
    
    @inlinable
    public var stateFlags : ResourceStateFlags {
        get {
            return []
        }
        nonmutating set {
            _ = newValue
        }
    }
}

public struct Heap : ResourceProtocol {
    @usableFromInline let _handle : UnsafeRawPointer
    @inlinable public var handle : Handle { return UInt64(UInt(bitPattern: _handle)) }
    
    @inlinable
    public init(handle: Handle) {
        assert(Resource(handle: handle).type == .heap)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
    }
    
    @inlinable
    public init?(size: Int, type: HeapType = .automaticPlacement, storageMode: StorageMode = .managed, cacheMode: CPUCacheMode = .defaultCache) {
        self.init(descriptor: HeapDescriptor(size: size, type: type, storageMode: storageMode, cacheMode: cacheMode))
    }
    
    @inlinable
    public init?(descriptor: HeapDescriptor) {
        let flags : ResourceFlags = .persistent
        
        let index = HeapRegistry.instance.allocate(descriptor: descriptor)
        let handle = index | (UInt64(flags.rawValue) << Self.flagBitsRange.lowerBound) | (UInt64(ResourceType.heap.rawValue) << Self.typeBitsRange.lowerBound)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
        
        if !RenderBackend.materialiseHeap(self) {
            self.dispose()
            return nil
        }
    }
    
    @inlinable
    public var size : Int {
        return self.descriptor.size
    }
    
    public var usedSize: Int {
        return RenderBackend.usedSize(for: self)
    }
    
    public var currentAllocatedSize: Int {
        return RenderBackend.currentAllocatedSize(for: self)
    }
    
    public func maxAvailableSize(forAlignment alignment: Int) -> Int {
        return RenderBackend.maxAvailableSize(forAlignment: alignment, in: self)
    }
    
    @inlinable
    public internal(set) var descriptor : HeapDescriptor {
        get {
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: HeapRegistry.Chunk.itemsPerChunk)
            return HeapRegistry.instance.chunks[chunkIndex].descriptors[indexInChunk]
        }
        nonmutating set {
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: HeapRegistry.Chunk.itemsPerChunk)
            HeapRegistry.instance.chunks[chunkIndex].descriptors[indexInChunk] = newValue
        }
    }
    
    @inlinable
    public var storageMode: StorageMode {
        return self.descriptor.storageMode
    }
    
    @inlinable
    public var cacheMode: CPUCacheMode {
        return self.descriptor.cacheMode
    }
    
    @inlinable
    public var label : String? {
        get {
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: HeapRegistry.Chunk.itemsPerChunk)
            return HeapRegistry.instance.chunks[chunkIndex].labels[indexInChunk]
        }
        nonmutating set {
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: HeapRegistry.Chunk.itemsPerChunk)
            HeapRegistry.instance.chunks[chunkIndex].labels[indexInChunk] = newValue
        }
    }
    
    /// Returns whether the resource is known to currently be in use by the CPU or GPU.
    @inlinable
    public var isKnownInUse: Bool {
        guard self._usesPersistentRegistry else {
            return true
        }
        let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: HeapRegistry.Chunk.itemsPerChunk)
        let activeRenderGraphMask = UInt8.AtomicRepresentation.atomicLoad(at: HeapRegistry.instance.chunks[chunkIndex].activeRenderGraphs.advanced(by: indexInChunk), ordering: .relaxed)
        if activeRenderGraphMask != 0 {
            return true // The resource is still being used by a yet-to-be-submitted RenderGraph.
        }
        return false
    }
    
    public func markAsUsed(activeRenderGraphMask: ActiveRenderGraphMask) {
        guard self._usesPersistentRegistry else {
            return
        }
        let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: HeapRegistry.Chunk.itemsPerChunk)
        UInt8.AtomicRepresentation.atomicLoadThenBitwiseOr(with: activeRenderGraphMask, at: HeapRegistry.instance.chunks[chunkIndex].activeRenderGraphs.advanced(by: indexInChunk), ordering: .relaxed)
    }

    public func dispose() {
        guard self._usesPersistentRegistry else {
            return
        }
        HeapRegistry.instance.dispose(self)
    }
    
    @inlinable
    public var isValid : Bool {
        let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: HeapRegistry.Chunk.itemsPerChunk)
        return HeapRegistry.instance.chunks[chunkIndex].generations[indexInChunk] == self.generation
    }
}

extension Heap: CustomStringConvertible {
    public var description: String {
        return "Heap(handle: \(self.handle)) { \(self.label.map { "label: \($0), "} ?? "")descriptor: \(self.descriptor), flags: \(self.flags) }"
    }
}


public struct Buffer : ResourceProtocol {
    public struct TextureViewDescriptor {
        public var descriptor : TextureDescriptor
        public var offset : Int
        public var bytesPerRow : Int
        
        @inlinable
        public init(descriptor: TextureDescriptor, offset: Int, bytesPerRow: Int) {
            self.descriptor = descriptor
            self.offset = offset
            self.bytesPerRow = bytesPerRow
        }
    }
    
    @usableFromInline let _handle : UnsafeRawPointer
    @inlinable public var handle : Handle { return UInt64(UInt(bitPattern: _handle)) }
    
    @inlinable
    public init(handle: Handle) {
        assert(Resource(handle: handle).type == .buffer)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
    }
   
    @available(*, deprecated, renamed: "init(length:storageMode:cacheMode:usage:bytes:renderGraph:flags:)")
    @inlinable
    public init(length: Int, storageMode: StorageMode = .managed, cacheMode: CPUCacheMode = .defaultCache, usage: BufferUsage = .unknown, bytes: UnsafeRawPointer? = nil, frameGraph: RenderGraph?, flags: ResourceFlags = []) {
        self.init(length: length, storageMode: storageMode, cacheMode: cacheMode, usage: usage, bytes: bytes, renderGraph: frameGraph, flags: flags)
    }
    
    @inlinable
    public init(length: Int, storageMode: StorageMode = .managed, cacheMode: CPUCacheMode = .defaultCache, usage: BufferUsage = .unknown, bytes: UnsafeRawPointer? = nil, renderGraph: RenderGraph? = nil, flags: ResourceFlags = []) {
        self.init(descriptor: BufferDescriptor(length: length, storageMode: storageMode, cacheMode: cacheMode, usage: usage), bytes: bytes, renderGraph: renderGraph, flags: flags)
    }
    
    @available(*, deprecated, renamed: "init(descriptor:renderGraph:flags:)")
    @inlinable
    public init(descriptor: BufferDescriptor, frameGraph: RenderGraph?, flags: ResourceFlags = []) {
        self.init(descriptor: descriptor, renderGraph: frameGraph, flags: flags)
    }
    
    @inlinable
    public init(descriptor: BufferDescriptor, renderGraph: RenderGraph? = nil, flags: ResourceFlags = []) {
        let index : UInt64
        if flags.contains(.persistent) || flags.contains(.historyBuffer) {
            index = PersistentBufferRegistry.instance.allocate(descriptor: descriptor, heap: nil, flags: flags)
        } else {
            guard let renderGraph = renderGraph ?? RenderGraph.activeRenderGraph else {
                 fatalError("The RenderGraph must be specified for transient resources created outside of a render pass' execute() method.")
             }
            index = TransientBufferRegistry.instances[renderGraph.transientRegistryIndex].allocate(descriptor: descriptor, flags: flags)
        }
        
        let handle = index | (UInt64(flags.rawValue) << Self.flagBitsRange.lowerBound) | (UInt64(ResourceType.buffer.rawValue) << Self.typeBitsRange.lowerBound)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
        
        if self.flags.contains(.persistent) {
            assert(!descriptor.usageHint.isEmpty, "Persistent resources must explicitly specify their usage.")
            let didAllocate = RenderBackend.materialisePersistentBuffer(self)
            assert(didAllocate, "Allocation failed for persistent buffer \(self)")
        }
    }
    
    @available(*, deprecated, renamed: "init(descriptor:bytes:renderGraph:flags:)")
    @inlinable
    public init(descriptor: BufferDescriptor, bytes: UnsafeRawPointer?, frameGraph: RenderGraph?, flags: ResourceFlags = []) {
        self.init(descriptor: descriptor, bytes: bytes, renderGraph: frameGraph, flags: flags)
    }
    
    @inlinable
    public init(descriptor: BufferDescriptor, bytes: UnsafeRawPointer?, renderGraph: RenderGraph? = nil, flags: ResourceFlags = []) {
        self.init(descriptor: descriptor, renderGraph: renderGraph, flags: flags)
        
        if let bytes = bytes {
            assert(self.descriptor.storageMode != .private)
            self[0..<self.descriptor.length, accessType: .write].withContents { $0.copyMemory(from: bytes, byteCount: self.descriptor.length) }
        }
    }
    
    @inlinable
    public init?(length: Int, usage: BufferUsage = .unknown, bytes: UnsafeRawPointer? = nil, heap: Heap, flags: ResourceFlags = [.persistent]) {
        self.init(descriptor: BufferDescriptor(length: length, storageMode: heap.storageMode, cacheMode: heap.cacheMode, usage: usage), bytes: bytes, heap: heap, flags: flags)
    }
    
    @inlinable
    public init?(descriptor: BufferDescriptor, heap: Heap, flags: ResourceFlags = [.persistent]) {
        assert(flags.contains(.persistent), "Heap-allocated resources must be persistent.")
        assert(!descriptor.usageHint.isEmpty, "Persistent resources must explicitly specify their usage.")
        
        let index = PersistentBufferRegistry.instance.allocate(descriptor: descriptor, heap: heap, flags: flags)
        let handle = index | (UInt64(flags.rawValue) << Self.flagBitsRange.lowerBound) | (UInt64(ResourceType.buffer.rawValue) << Self.typeBitsRange.lowerBound)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
        
        if !RenderBackend.materialisePersistentBuffer(self) {
            self.dispose()
            return nil
        }
    }
    
    @inlinable
    public init?(descriptor: BufferDescriptor, bytes: UnsafeRawPointer?, heap: Heap, flags: ResourceFlags = [.persistent]) {
        self.init(descriptor: descriptor, heap: heap, flags: flags)
        
        if let bytes = bytes {
            assert(self.descriptor.storageMode != .private)
            self[0..<self.descriptor.length, accessType: .write].withContents { $0.copyMemory(from: bytes, byteCount: self.descriptor.length) }
        }
    }
    
    @inlinable
    public subscript(range: Range<Int>) -> RawBufferSlice {
        return self[range, accessType: .readWrite]
    }
    
    @inlinable
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
    
    @inlinable
    public subscript<T>(as type: T.Type, accessType accessType: ResourceAccessType = .readWrite) -> BufferSlice<T> {
        return self[byteRange: self.range, as: type, accessType: .readWrite]
    }
    
    @inlinable
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
    
    @inlinable
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
    
    @inlinable
    public var length : Int {
        return self.descriptor.length
    }
    
    @inlinable
    public var range : Range<Int> {
        return 0..<self.descriptor.length
    }
    
    @inlinable
    public var stateFlags: ResourceStateFlags {
        get {
            if self.flags.intersection([.historyBuffer, .persistent]) == [] {
                return []
            }
            
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: PersistentBufferRegistry.Chunk.itemsPerChunk)
            return PersistentBufferRegistry.instance.chunks[chunkIndex].stateFlags[indexInChunk]
        }
        nonmutating set {
            if self.flags.intersection([.historyBuffer, .persistent]) == [] { return }
            
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: PersistentBufferRegistry.Chunk.itemsPerChunk)
            PersistentBufferRegistry.instance.chunks[chunkIndex].stateFlags[indexInChunk] = newValue
        }
    }
    
    @inlinable
    public internal(set) var descriptor : BufferDescriptor {
        get {
            let index = self.index
            if self._usesPersistentRegistry {
                let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: PersistentBufferRegistry.Chunk.itemsPerChunk)
                return PersistentBufferRegistry.instance.chunks[chunkIndex].descriptors[indexInChunk]
            } else {
                return TransientBufferRegistry.instances[self.transientRegistryIndex].descriptors[index]
            }
        }
        nonmutating set {
            let index = self.index
            if self._usesPersistentRegistry {
                let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: PersistentBufferRegistry.Chunk.itemsPerChunk)
                PersistentBufferRegistry.instance.chunks[chunkIndex].descriptors[indexInChunk] = newValue
            } else {
                TransientBufferRegistry.instances[self.transientRegistryIndex].descriptors[index] = newValue
            }
        }
    }
    
    @inlinable
    public var heap : Heap? {
        if self._usesPersistentRegistry {
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: PersistentBufferRegistry.Chunk.itemsPerChunk)
            let heap = PersistentBufferRegistry.instance.chunks[chunkIndex].heaps[indexInChunk]
            return heap
        } else {
            return nil
        }
    }
    
    @inlinable
    public var storageMode: StorageMode {
        return self.descriptor.storageMode
    }
    
    @inlinable
    public var label : String? {
        get {
            let index = self.index
            if self._usesPersistentRegistry {
                let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: PersistentBufferRegistry.Chunk.itemsPerChunk)
                return PersistentBufferRegistry.instance.chunks[chunkIndex].labels[indexInChunk]
            } else {
                return TransientBufferRegistry.instances[self.transientRegistryIndex].labels[index]
            }
        }
        nonmutating set {
            let index = self.index
            if self._usesPersistentRegistry {
                let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: PersistentBufferRegistry.Chunk.itemsPerChunk)
                PersistentBufferRegistry.instance.chunks[chunkIndex].labels[indexInChunk] = newValue
                RenderBackend.updateLabel(on: self)
            } else {
                TransientBufferRegistry.instances[self.transientRegistryIndex].labels[index] = newValue
            }
        }
    }
    
    @inlinable
    public var _deferredSliceActions : [DeferredBufferSlice] {
        get {
            assert(!self._usesPersistentRegistry)
            
            return TransientBufferRegistry.instances[self.transientRegistryIndex].deferredSliceActions[self.index]
    
        }
        nonmutating set {
            assert(!self._usesPersistentRegistry)
            
            TransientBufferRegistry.instances[self.transientRegistryIndex].deferredSliceActions[self.index] = newValue
        }
    }
    
    public subscript(waitIndexFor queue: Queue, accessType type: ResourceAccessType) -> UInt64 {
        get {
            guard self._usesPersistentRegistry else { return 0 }
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: PersistentBufferRegistry.Chunk.itemsPerChunk)
            if type == .read {
                return PersistentBufferRegistry.instance.chunks[chunkIndex].readWaitIndices[indexInChunk][Int(queue.index)]
            } else {
                return PersistentBufferRegistry.instance.chunks[chunkIndex].writeWaitIndices[indexInChunk][Int(queue.index)]
            }
        }
        nonmutating set {
            guard self._usesPersistentRegistry else { return }
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: PersistentBufferRegistry.Chunk.itemsPerChunk)
            
            if type == .read || type == .readWrite {
                PersistentBufferRegistry.instance.chunks[chunkIndex].readWaitIndices[indexInChunk][Int(queue.index)] = newValue
            }
            if type == .write || type == .readWrite {
                PersistentBufferRegistry.instance.chunks[chunkIndex].writeWaitIndices[indexInChunk][Int(queue.index)] = newValue
            }
        }
    }
    
    @inlinable
    public var usages : ChunkArray<ResourceUsage> {
        get {
            let index = self.index
            if self._usesPersistentRegistry {
                let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: PersistentBufferRegistry.Chunk.itemsPerChunk)
                return PersistentBufferRegistry.instance.chunks[chunkIndex].usages[indexInChunk]
            } else {
                return TransientBufferRegistry.instances[self.transientRegistryIndex].usages[index]
            }
        }
        nonmutating set {
            let index = self.index
            if self._usesPersistentRegistry {
                let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: PersistentBufferRegistry.Chunk.itemsPerChunk)
                PersistentBufferRegistry.instance.chunks[chunkIndex].usages[indexInChunk] = newValue
            } else {
                TransientBufferRegistry.instances[self.transientRegistryIndex].usages[index] = newValue
            }
        }
    }
    
    /// Returns whether the resource is known to currently be in use by the CPU or GPU.
    @inlinable
    public var isKnownInUse: Bool {
        guard self._usesPersistentRegistry else {
            return true
        }
        let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: PersistentBufferRegistry.Chunk.itemsPerChunk)
        let activeRenderGraphMask = UInt8.AtomicRepresentation.atomicLoad(at: PersistentBufferRegistry.instance.chunks[chunkIndex].activeRenderGraphs.advanced(by: indexInChunk), ordering: .relaxed)
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
        self.heap?.markAsUsed(activeRenderGraphMask: activeRenderGraphMask)
        
        guard self._usesPersistentRegistry else {
            return
        }
        let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: PersistentBufferRegistry.Chunk.itemsPerChunk)
        UInt8.AtomicRepresentation.atomicLoadThenBitwiseOr(with: activeRenderGraphMask, at: PersistentBufferRegistry.instance.chunks[chunkIndex].activeRenderGraphs.advanced(by: indexInChunk), ordering: .relaxed)
    }

    public func dispose() {
        guard self._usesPersistentRegistry else {
            return
        }
        PersistentBufferRegistry.instance.dispose(self)
    }
    
    @inlinable
    public var isValid : Bool {
        if self._usesPersistentRegistry {
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: PersistentBufferRegistry.Chunk.itemsPerChunk)
            return PersistentBufferRegistry.instance.chunks[chunkIndex].generations[indexInChunk] == self.generation
        } else {
            return TransientBufferRegistry.instances[self.transientRegistryIndex].generation == self.generation
        }
    }
}

extension Buffer: CustomStringConvertible {
    public var description: String {
        return "Buffer(handle: \(self.handle)) { \(self.label.map { "label: \($0), "} ?? "")descriptor: \(self.descriptor), stateFlags: \(self.stateFlags), flags: \(self.flags) }"
    }
}

public struct Texture : ResourceProtocol {
    public struct TextureViewDescriptor {
        public var pixelFormat: PixelFormat
        public var textureType: TextureType
        public var levels: Range<Int>
        public var slices: Range<Int>
        
        @inlinable
        public init(pixelFormat: PixelFormat, textureType: TextureType, levels: Range<Int> = -1..<0, slices: Range<Int> = -1..<0) {
            self.pixelFormat = pixelFormat
            self.textureType = textureType
            self.levels = levels
            self.slices = slices
        }
    }
    
    @usableFromInline let _handle : UnsafeRawPointer
    @inlinable public var handle : Handle { return UInt64(UInt(bitPattern: _handle)) }
    
    @inlinable
    public init(handle: Handle) {
        assert(Resource(handle: handle).type == .texture)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
    }
    
    @available(*, deprecated, renamed: "init(descriptor:renderGraph:flags:)")
    @inlinable
    public init(descriptor: TextureDescriptor, frameGraph: RenderGraph?, flags: ResourceFlags = []) {
        self.init(descriptor: descriptor, renderGraph: frameGraph, flags: flags)
    }
    
    @inlinable
    public init(descriptor: TextureDescriptor, renderGraph: RenderGraph? = nil, flags: ResourceFlags = []) {
        precondition(descriptor.width <= 16384 && descriptor.height <= 16384 && descriptor.depth <= 1024)
        
        let index : UInt64
        if flags.contains(.persistent) || flags.contains(.historyBuffer) {
            index = PersistentTextureRegistry.instance.allocate(descriptor: descriptor, heap: nil, flags: flags)
        } else {
            guard let renderGraph = renderGraph ?? RenderGraph.activeRenderGraph else {
                fatalError("The RenderGraph must be specified for transient resources created outside of a render pass' execute() method.")
            }
            index = TransientTextureRegistry.instances[renderGraph.transientRegistryIndex].allocate(descriptor: descriptor, flags: flags)
        }
        
        let handle = index | (UInt64(flags.rawValue) << Self.flagBitsRange.lowerBound) | (UInt64(ResourceType.texture.rawValue) << Self.typeBitsRange.lowerBound)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
        
        if self.flags.contains(.persistent) {
            assert(!descriptor.usageHint.isEmpty, "Persistent resources must explicitly specify their usage.")
            let didAllocate = RenderBackend.materialisePersistentTexture(self)
            assert(didAllocate, "Allocation failed for persistent texture \(self)")
        }
    }
        
    @inlinable
    public static func _createPersistentTextureWithoutDescriptor(flags: ResourceFlags = [.persistent]) -> Texture {
        precondition(flags.contains(.persistent))
        let index = PersistentTextureRegistry.instance.allocateHandle()
        let handle = index | (UInt64(flags.rawValue) << Self.flagBitsRange.lowerBound) | (UInt64(ResourceType.texture.rawValue) << Self.typeBitsRange.lowerBound)
        return Texture(handle: handle)
    }
    
    @inlinable
    public func _initialisePersistentTexture(descriptor: TextureDescriptor, heap: Heap?) {
        precondition(self.flags.contains(.persistent))
        PersistentTextureRegistry.instance.initialise(texture: self, descriptor: descriptor, heap: heap, flags: self.flags)
        
        assert(!descriptor.usageHint.isEmpty, "Persistent resources must explicitly specify their usage.")
        let didAllocate = RenderBackend.materialisePersistentTexture(self)
        assert(didAllocate, "Allocation failed for persistent texture \(self)")
    }
    
    @inlinable
    public init?(descriptor: TextureDescriptor, heap: Heap, flags: ResourceFlags = [.persistent]) {
        precondition(descriptor.width <= 16384 && descriptor.height <= 16384 && descriptor.depth <= 1024)
        
        assert(flags.contains(.persistent), "Heap-allocated resources must be persistent.")
        assert(!descriptor.usageHint.isEmpty, "Persistent resources must explicitly specify their usage.")
        
        let index = PersistentTextureRegistry.instance.allocate(descriptor: descriptor, heap: heap, flags: flags)
        let handle = index | (UInt64(flags.rawValue) << Self.flagBitsRange.lowerBound) | (UInt64(ResourceType.texture.rawValue) << Self.typeBitsRange.lowerBound)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
        
        if !RenderBackend.materialisePersistentTexture(self) {
            self.dispose()
            return nil
        }
    }
    
    @available(*, deprecated, renamed: "init(descriptor:externalResource:renderGraph:flags:)")
    @inlinable
    public init(descriptor: TextureDescriptor, externalResource: Any, frameGraph: RenderGraph?, flags: ResourceFlags = [.persistent, .externalOwnership]) {
        self.init(descriptor: descriptor, externalResource: externalResource, renderGraph: frameGraph, flags: flags)
    }
    
    @inlinable
    public init(descriptor: TextureDescriptor, externalResource: Any, renderGraph: RenderGraph? = nil, flags: ResourceFlags = [.persistent, .externalOwnership]) {
        let index : UInt64
        if flags.contains(.persistent) || flags.contains(.historyBuffer) {
            index = PersistentTextureRegistry.instance.allocate(descriptor: descriptor, heap: nil, flags: flags)
        } else {
            guard let renderGraph = renderGraph ?? RenderGraph.activeRenderGraph else {
                 fatalError("The RenderGraph must be specified for transient resources created outside of a render pass' execute() method.")
             }
            index = TransientTextureRegistry.instances[renderGraph.transientRegistryIndex].allocate(descriptor: descriptor, flags: flags)
        }
        
        let handle = index | (UInt64(flags.rawValue) << Self.flagBitsRange.lowerBound) | (UInt64(ResourceType.texture.rawValue) << Self.typeBitsRange.lowerBound)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
        
        if self.flags.contains(.persistent) {
            assert(!descriptor.usageHint.isEmpty, "Persistent resources must explicitly specify their usage.")
        }
        RenderBackend.registerExternalResource(Resource(self), backingResource: externalResource)
    }
    
    @inlinable
    public init(viewOf base: Texture, descriptor: TextureViewDescriptor, renderGraph: RenderGraph? = nil) {
        let flags : ResourceFlags = .resourceView
        
        guard let transientRegistryIndex = renderGraph?.transientRegistryIndex ?? RenderGraph.activeRenderGraph?.transientRegistryIndex ?? (!base._usesPersistentRegistry ? base.transientRegistryIndex : nil) else {
            fatalError("The RenderGraph must be specified for transient resources created outside of a render pass' execute() method.")
        }
        
        let index = TransientTextureRegistry.instances[transientRegistryIndex].allocate(descriptor: descriptor, baseResource: base)
        let handle = index | (UInt64(flags.rawValue) << Self.flagBitsRange.lowerBound) | (UInt64(ResourceType.texture.rawValue) << Self.typeBitsRange.lowerBound)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
    }
    
    @inlinable
    public init(viewOf base: Buffer, descriptor: Buffer.TextureViewDescriptor, renderGraph: RenderGraph? = nil) {
        let flags : ResourceFlags = .resourceView
    
        guard let transientRegistryIndex = renderGraph?.transientRegistryIndex ?? RenderGraph.activeRenderGraph?.transientRegistryIndex ?? (!base._usesPersistentRegistry ? base.transientRegistryIndex : nil) else {
            fatalError("The RenderGraph must be specified for transient resources created outside of a render pass' execute() method.")
        }
        
        let index = TransientTextureRegistry.instances[transientRegistryIndex].allocate(descriptor: descriptor, baseResource: base)
        let handle = index | (UInt64(flags.rawValue) << Self.flagBitsRange.lowerBound) | (UInt64(ResourceType.texture.rawValue) << Self.typeBitsRange.lowerBound)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
    }
    
    @available(*, deprecated, renamed: "init(descriptor:isMinimised:nativeWindow:renderGraph:)")
    @inlinable
    public init(windowId: Int, descriptor: TextureDescriptor, isMinimised: Bool, nativeWindow: Any, frameGraph: RenderGraph) {
        self.init(descriptor: descriptor, isMinimised: isMinimised, nativeWindow: nativeWindow, renderGraph: frameGraph)
    }
    
    @available(*, deprecated, renamed: "init(descriptor:isMinimised:nativeWindow:renderGraph:)")
    @inlinable
    public init(windowId: Int, descriptor: TextureDescriptor, isMinimised: Bool, nativeWindow: Any, renderGraph: RenderGraph) {
        self.init(descriptor: descriptor, isMinimised: isMinimised, nativeWindow: nativeWindow, renderGraph: renderGraph)
    }
    
    @inlinable
    public init(descriptor: TextureDescriptor, isMinimised: Bool, nativeWindow: Any, renderGraph: RenderGraph) {
        self.init(descriptor: descriptor, renderGraph: renderGraph, flags: isMinimised ? [] : .windowHandle)
        
        if !isMinimised {
            RenderBackend.registerWindowTexture(texture: self, context: nativeWindow)
        }
    }
    
    @inlinable
    public func copyBytes(to bytes: UnsafeMutableRawPointer, bytesPerRow: Int, region: Region, mipmapLevel: Int) {
        self.waitForCPUAccess(accessType: .read)
        RenderBackend.copyTextureBytes(from: self, to: bytes, bytesPerRow: bytesPerRow, region: region, mipmapLevel: mipmapLevel)
    }
    
    @inlinable
    public func replace(region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) {
        self.waitForCPUAccess(accessType: .write)
        
        RenderBackend.replaceTextureRegion(texture: self, region: region, mipmapLevel: mipmapLevel, withBytes: bytes, bytesPerRow: bytesPerRow)
    }
    
    @inlinable
    public func replace(region: Region, mipmapLevel: Int, slice: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int) {
        self.waitForCPUAccess(accessType: .write)
        
        RenderBackend.replaceTextureRegion(texture: self, region: region, mipmapLevel: mipmapLevel, slice: slice, withBytes: bytes, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerImage)
    }
    
    @inlinable
    public var stateFlags: ResourceStateFlags {
        get {
            if self.flags.intersection([.historyBuffer, .persistent]) == [] {
                return []
            }
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: PersistentTextureRegistry.Chunk.itemsPerChunk)
            return PersistentTextureRegistry.instance.chunks[chunkIndex].stateFlags[indexInChunk]
        }
        nonmutating set {
            assert(self.flags.intersection([.historyBuffer, .persistent]) != [], "State flags can only be set on persistent resources.")
            
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: PersistentTextureRegistry.Chunk.itemsPerChunk)
            PersistentTextureRegistry.instance.chunks[chunkIndex].stateFlags[indexInChunk] = newValue
        }
    }
    
    @inlinable
    public var storageMode: StorageMode {
        return self.descriptor.storageMode
    }
    
    @inlinable
    public internal(set) var descriptor : TextureDescriptor {
        get {
            let index = self.index
            if self._usesPersistentRegistry {
                let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: PersistentTextureRegistry.Chunk.itemsPerChunk)
                return PersistentTextureRegistry.instance.chunks[chunkIndex].descriptors[indexInChunk]
            } else {
                return TransientTextureRegistry.instances[self.transientRegistryIndex].descriptors[index]
            }
        }
        nonmutating set {
            let index = self.index
            if self._usesPersistentRegistry {
                let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: PersistentTextureRegistry.Chunk.itemsPerChunk)
                PersistentTextureRegistry.instance.chunks[chunkIndex].descriptors[indexInChunk] = newValue
            } else {
                TransientTextureRegistry.instances[self.transientRegistryIndex].descriptors[index] = newValue
            }
        }
    }
    
    @inlinable
    public var heap : Heap? {
        if self._usesPersistentRegistry {
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: PersistentTextureRegistry.Chunk.itemsPerChunk)
            let heap = PersistentTextureRegistry.instance.chunks[chunkIndex].heaps[indexInChunk]
            return heap
        } else {
            return nil
        }
    }
    
    @inlinable
    public var label : String? {
        get {
            let index = self.index
            if self._usesPersistentRegistry {
                let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: PersistentTextureRegistry.Chunk.itemsPerChunk)
                return PersistentTextureRegistry.instance.chunks[chunkIndex].labels[indexInChunk]
            } else {
                return TransientTextureRegistry.instances[self.transientRegistryIndex].labels[index]
            }
        }
        nonmutating set {
            let index = self.index
            if self._usesPersistentRegistry {
                let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: PersistentTextureRegistry.Chunk.itemsPerChunk)
                PersistentTextureRegistry.instance.chunks[chunkIndex].labels[indexInChunk] = newValue
                RenderBackend.updateLabel(on: self)
            } else {
                TransientTextureRegistry.instances[self.transientRegistryIndex].labels[index] = newValue
            }
        }
    }
    
    public subscript(waitIndexFor queue: Queue, accessType type: ResourceAccessType) -> UInt64 {
        get {
            guard self.flags.contains(.persistent) else { return 0 }
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: PersistentTextureRegistry.Chunk.itemsPerChunk)
            if type == .read {
                return PersistentTextureRegistry.instance.chunks[chunkIndex].readWaitIndices[indexInChunk][Int(queue.index)]
            } else {
                return PersistentTextureRegistry.instance.chunks[chunkIndex].writeWaitIndices[indexInChunk][Int(queue.index)]
            }
        }
        nonmutating set {
            guard self._usesPersistentRegistry else { return }
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: PersistentTextureRegistry.Chunk.itemsPerChunk)
            
            if type == .read || type == .readWrite {
                PersistentTextureRegistry.instance.chunks[chunkIndex].readWaitIndices[indexInChunk][Int(queue.index)] = newValue
            }
            if type == .write || type == .readWrite {
                PersistentTextureRegistry.instance.chunks[chunkIndex].writeWaitIndices[indexInChunk][Int(queue.index)] = newValue
            }
        }
    }
    
    @inlinable
    public var size : Size {
        return Size(width: self.descriptor.width, height: self.descriptor.height, depth: self.descriptor.depth)
    }
    
    @inlinable
    public var width : Int {
        return self.descriptor.width
    }
    
    @inlinable
    public var height : Int {
        return self.descriptor.height
    }
    
    @inlinable
    public var depth : Int {
        return self.descriptor.depth
    }
    
    @inlinable
    public var usages : ChunkArray<ResourceUsage> {
        get {
            let index = self.index
            if self._usesPersistentRegistry {
                let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: PersistentTextureRegistry.Chunk.itemsPerChunk)
                return PersistentTextureRegistry.instance.chunks[chunkIndex].usages[indexInChunk]
            } else {
                return self.baseResource?.usages ?? TransientTextureRegistry.instances[self.transientRegistryIndex].usages[index]
            }
        }
        nonmutating set {
            let index = self.index
            if self._usesPersistentRegistry {
                let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: PersistentTextureRegistry.Chunk.itemsPerChunk)
                PersistentTextureRegistry.instance.chunks[chunkIndex].usages[indexInChunk] = newValue
            } else {
                if let baseResource = self.baseResource {
                    baseResource.usages = newValue
                } else {
                    TransientTextureRegistry.instances[self.transientRegistryIndex].usages[index] = newValue
                }
            }
        }
    }
    
    @inlinable
    public var baseResource : Resource? {
        get {
            let index = self.index
            if !self.isTextureView {
                return nil
            } else {
                return TransientTextureRegistry.instances[self.transientRegistryIndex].baseResources[index]
            }
        }
    }
    
    @inlinable
    public var textureViewBaseInfo : TextureViewBaseInfo? {
        let index = self.index
        if !self.isTextureView {
            return nil
        } else {
            return TransientTextureRegistry.instances[self.transientRegistryIndex].textureViewInfos[index]
        }
    }
    
    /// Returns whether the resource is known to currently be in use by the CPU or GPU.
    @inlinable
    public var isKnownInUse: Bool {
        guard self._usesPersistentRegistry else {
            return true
        }
        let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: PersistentTextureRegistry.Chunk.itemsPerChunk)
        let activeRenderGraphMask = UInt8.AtomicRepresentation.atomicLoad(at: PersistentTextureRegistry.instance.chunks[chunkIndex].activeRenderGraphs.advanced(by: indexInChunk), ordering: .relaxed)
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
        self.baseResource?.markAsUsed(activeRenderGraphMask: activeRenderGraphMask)
        self.heap?.markAsUsed(activeRenderGraphMask: activeRenderGraphMask)
        
        guard self._usesPersistentRegistry else {
            return
        }
        let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: PersistentTextureRegistry.Chunk.itemsPerChunk)
        UInt8.AtomicRepresentation.atomicLoadThenBitwiseOr(with: activeRenderGraphMask, at: PersistentTextureRegistry.instance.chunks[chunkIndex].activeRenderGraphs.advanced(by: indexInChunk), ordering: .relaxed)
    }
    
    public func dispose() {
        guard self._usesPersistentRegistry else {
            return
        }
        PersistentTextureRegistry.instance.dispose(self)
    }
    
    @inlinable
    public var isValid : Bool {
        if self._usesPersistentRegistry {
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: PersistentTextureRegistry.Chunk.itemsPerChunk)
            return PersistentTextureRegistry.instance.chunks[chunkIndex].generations[indexInChunk] == self.generation
        } else {
            return TransientTextureRegistry.instances[self.transientRegistryIndex].generation == self.generation
        }
    }
    
    public static let invalid = Texture(descriptor: TextureDescriptor(type: .type2D, format: .r32Float, width: 1, height: 1, mipmapped: false, storageMode: .private, usage: .shaderRead), flags: .persistent)
    
}


extension Texture: CustomStringConvertible {
    public var description: String {
        return "Texture(handle: \(self.handle)) { \(self.label.map { "label: \($0), "} ?? "")descriptor: \(self.descriptor), stateFlags: \(self.stateFlags), flags: \(self.flags) }"
    }
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
    
    @inlinable
    internal init(buffer: Buffer, range: Range<Int>, accessType: ResourceAccessType) {
        self.buffer = buffer
        self._range = range
        self.contents = RenderBackend.bufferContents(for: self.buffer, range: self._range)
        self.accessType = accessType
    }
    
    @inlinable
    public func withContents<A>(_ perform: (UnsafeMutableRawPointer) throws -> A) rethrows -> A {
        return try perform(self.contents)
    }
    
    @inlinable
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
    
    @inlinable
    internal init(buffer: Buffer, range: Range<Int>, accessType: ResourceAccessType) {
        self.buffer = buffer
        self._range = range
        self.contents = RenderBackend.bufferContents(for: self.buffer, range: self._range).bindMemory(to: T.self, capacity: range.count)
        self.accessType = accessType
    }
    
    @inlinable
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
    
    @inlinable
    public var range : Range<Int> {
        return self._range
    }
    
    @inlinable
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
