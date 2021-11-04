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
    
    static var resourceType: ResourceType { get }
}

protocol ResourceProtocolImpl: ResourceProtocol {
    associatedtype Descriptor
    associatedtype SharedProperties: SharedResourceProperties where SharedProperties.Descriptor == Descriptor
    associatedtype TransientProperties: ResourceProperties where TransientProperties.Descriptor == Descriptor
    associatedtype PersistentProperties: PersistentResourceProperties where PersistentProperties.Descriptor == Descriptor
    
    associatedtype TransientRegistry: Substrate.TransientRegistry where TransientRegistry.Resource == Self
    typealias PersistentRegistry = Substrate.PersistentRegistry<Self>
    
    static var itemsPerChunk: Int { get }
    
    static func transientRegistry(index: Int) -> TransientRegistry?
    static var persistentRegistry: PersistentRegistry { get }
    
    var usages: ChunkArray<ResourceUsage> { get nonmutating set }
}

extension ResourceProtocolImpl {
    static var itemsPerChunk: Int { 256 }
    
    @inlinable
    public init?(_ resource: Resource) {
        guard Self.resourceType == resource.type else { return nil }
        self.init(handle: resource.handle)
    }
    
    @_transparent
    func pointer<T>(for keyPath: KeyPath<SharedProperties, UnsafeMutablePointer<T>>) -> UnsafeMutablePointer<T> {
        if self._usesPersistentRegistry {
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: Self.itemsPerChunk)
            return Self.persistentRegistry.sharedChunks[chunkIndex][keyPath: keyPath].advanced(by: indexInChunk)
        } else {
            let (properties, indexInChunk) = Self.transientRegistry(index: self.transientRegistryIndex)!.sharedProperties(index: self.index)
            return properties[keyPath: keyPath].advanced(by: indexInChunk)
        }
    }
    
    @_transparent
    func pointer<T>(for keyPath: KeyPath<TransientProperties, UnsafeMutablePointer<T>>) -> UnsafeMutablePointer<T>? {
        if self._usesPersistentRegistry {
            return nil
        }
        let (properties, indexInChunk) = Self.transientRegistry(index: self.transientRegistryIndex)!.transientProperties(index: self.index)
        return properties[keyPath: keyPath].advanced(by: indexInChunk)
    }
    
    @_transparent
    func pointer<T>(for keyPath: KeyPath<PersistentProperties, UnsafeMutablePointer<T>>) -> UnsafeMutablePointer<T>? {
        guard self._usesPersistentRegistry else { return nil }
        
        let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: Self.itemsPerChunk)
        return Self.persistentRegistry.persistentChunks[chunkIndex][keyPath: keyPath].advanced(by: indexInChunk)
    }
    
    @inlinable @inline(__always)
    subscript<T>(keyPath: KeyPath<SharedProperties, UnsafeMutablePointer<T>>) -> T {
        get {
            return self.pointer(for: keyPath).pointee
        }
        nonmutating set {
            self.pointer(for: keyPath).pointee = newValue
        }
    }
    
    @inlinable @inline(__always)
    subscript<T>(keyPath: KeyPath<TransientProperties, UnsafeMutablePointer<T>>) -> T? {
        get {
            return self.pointer(for: keyPath)?.pointee
        }
        nonmutating set {
            guard let pointer = self.pointer(for: keyPath), let newValue = newValue else { return }
            pointer.pointee = newValue
        }
    }
    
    @inlinable @inline(__always)
    subscript<T>(keyPath: KeyPath<TransientProperties, UnsafeMutablePointer<T?>>) -> T? {
        get {
            return self.pointer(for: keyPath)?.pointee
        }
        nonmutating set {
            guard let pointer = self.pointer(for: keyPath) else { return }
            pointer.pointee = newValue
        }
    }
    
    @inlinable @inline(__always)
    subscript<T>(keyPath: KeyPath<PersistentProperties, UnsafeMutablePointer<T>>) -> T? {
        get {
            return self.pointer(for: keyPath)?.pointee
        }
        nonmutating set {
            guard let pointer = self.pointer(for: keyPath), let newValue = newValue else { return }
            pointer.pointee = newValue
        }
    }
    
    @inlinable @inline(__always)
    subscript<T>(keyPath: KeyPath<PersistentProperties, UnsafeMutablePointer<T?>>) -> T? {
        get {
            return self.pointer(for: keyPath)?.pointee
        }
        nonmutating set {
            guard let pointer = self.pointer(for: keyPath) else { return }
            pointer.pointee = newValue
        }
    }
    
    @_transparent
    var _usagesPointer: UnsafeMutablePointer<ChunkArray<ResourceUsage>>? {
        if self._usesPersistentRegistry {
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: Self.itemsPerChunk)
            return Self.persistentRegistry.sharedChunks[chunkIndex].usagesOptional?.advanced(by: indexInChunk)
        } else {
            let (properties, indexInChunk) = Self.transientRegistry(index: self.transientRegistryIndex)!.sharedProperties(index: self.index)
            return properties.usagesOptional?.advanced(by: indexInChunk)
        }
    }
    
    public var usages: ChunkArray<ResourceUsage> {
        get {
            return self._usagesPointer?.pointee ?? .init()
        }
        nonmutating set {
            self._usagesPointer?.pointee = newValue
        }
    }
    
    public var isValid : Bool {
        if self._usesPersistentRegistry {
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: Self.itemsPerChunk)
            return Self.persistentRegistry.generationChunks[chunkIndex][indexInChunk] == self.generation
        } else {
            return Self.transientRegistry(index: self.transientRegistryIndex)?.generation == self.generation
        }
    }
}

extension ResourceProtocol {
    @inlinable @inline(__always)
    public static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.handle == rhs.handle
    }
    
    /// Destructive changes to purgeability will be applied once all pending GPU commands have completed,
    /// while non-destructive changes will be applied immediately.
    /// Note that using the resource after setting the purgeable state to discardable or discarded results in invalid behaviour.
    public var purgeableState: ResourcePurgeableState {
        get {
            return RenderBackend.updatePurgeableState(for: Resource(self), to: nil)
        }
        nonmutating set {
            _ = self.updatePurgeableState(to: newValue)
        }
    }
    
    /// Destructive changes to purgeability will be applied once all pending GPU commands have completed,
    /// while non-destructive changes will be applied immediately.
    /// Note that using the resource after setting the purgeable state to discardable or discarded results in invalid behaviour.
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
    
    public var backingResource: Any? {
        return RenderBackend.backingResource(self)
    }
}

public struct Resource : ResourceProtocol, Hashable {

    @usableFromInline let _handle : UnsafeRawPointer
    @inlinable public var handle : Handle { return UInt64(UInt(bitPattern: _handle)) }
    
    public init<R : ResourceProtocol>(_ resource: R) {
        self._handle = UnsafeRawPointer(bitPattern: UInt(resource.handle))!
    }
    
    public init(handle: Handle) {
        assert(ResourceType(rawValue: ResourceType.RawValue(truncatingIfNeeded: handle.bits(in: Self.typeBitsRange))) != nil)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
    }
    
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
    
    public static var resourceType: ResourceType {
        fatalError()
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
    
    public func markAsInitialised() {
        self.stateFlags.formUnion(.initialised)
    }
    
    public func discardContents() {
        self.stateFlags.remove(.initialised)
    }
    
    public var isTextureView : Bool {
        return self.flags.contains(.resourceView)
    }
    
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
            queue.waitForCommandCompletion(waitIndex)
        }
    }
    
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
    
    public init(handle: Handle) {
        assert(Resource(handle: handle).type == .heap)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
    }
    
    public init?(size: Int, type: HeapType = .automaticPlacement, storageMode: StorageMode = .managed, cacheMode: CPUCacheMode = .defaultCache) {
        self.init(descriptor: HeapDescriptor(size: size, type: type, storageMode: storageMode, cacheMode: cacheMode))
    }
    
    public init?(descriptor: HeapDescriptor) {
        let flags : ResourceFlags = .persistent
        
        self = HeapRegistry.instance.allocate(descriptor: descriptor, heap: nil, flags: flags)
        
        if !RenderBackend.materialiseHeap(self) {
            self.dispose()
            return nil
        }
    }
    
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
    
    public internal(set) var descriptor : HeapDescriptor {
        get {
            return self[\.descriptors]!
        }
        nonmutating set {
            self[\.descriptors] = newValue
        }
    }
    
    public var storageMode: StorageMode {
        return self.descriptor.storageMode
    }
    
    public var cacheMode: CPUCacheMode {
        return self.descriptor.cacheMode
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
    
    /// Returns whether the resource is known to currently be in use by the CPU or GPU.
    public var isKnownInUse: Bool {
        guard let activeRenderGraphs = self.pointer(for: \.activeRenderGraphs) else {
            return true
        }
        let activeRenderGraphMask = UInt8.AtomicRepresentation.atomicLoad(at: activeRenderGraphs, ordering: .relaxed)
        if activeRenderGraphMask != 0 {
            return true // The resource is still being used by a yet-to-be-submitted RenderGraph.
        }
        return false
    }
    
    public func markAsUsed(activeRenderGraphMask: ActiveRenderGraphMask) {
        guard let activeRenderGraphs = self.pointer(for: \.activeRenderGraphs) else {
            return
        }
        UInt8.AtomicRepresentation.atomicLoadThenBitwiseOr(with: activeRenderGraphMask, at: activeRenderGraphs, ordering: .relaxed)
    }
    
    public var childResources: Set<Resource> {
        _read {
            guard self.isValid else {
                yield []
                return
            }
            
            HeapRegistry.instance.lock.lock()
            yield self.pointer(for: \.childResources)!.pointee
            HeapRegistry.instance.lock.unlock()
        }
        nonmutating _modify {
            guard self.isValid else {
                var resources = Set<Resource>()
                yield &resources
                return
            }
            
            HeapRegistry.instance.lock.lock()
            yield &self.pointer(for: \.childResources)!.pointee
            HeapRegistry.instance.lock.unlock()
        }
    }
    
    public func dispose() {
        guard self._usesPersistentRegistry, self.isValid else {
            return
        }
        HeapRegistry.instance.dispose(self)
    }
    
    public static var resourceType: ResourceType {
        return .heap
    }
}

extension Heap: ResourceProtocolImpl {
    typealias SharedProperties = EmptyProperties<HeapDescriptor>
    typealias TransientProperties = EmptyProperties<HeapDescriptor>
    typealias PersistentProperties = HeapProperties
    
    static func transientRegistry(index: Int) -> TransientChunkRegistry<Heap>? {
        return nil
    }
    
    static var persistentRegistry: PersistentRegistry<Self> { HeapRegistry.instance }
    
    typealias Descriptor = HeapDescriptor
}

extension Heap: CustomStringConvertible {
    public var description: String {
        return "Heap(handle: \(self.handle)) { \(self.label.map { "label: \($0), "} ?? "")descriptor: \(self.descriptor), flags: \(self.flags) }"
    }
}


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
        
        @inlinable
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
        precondition(descriptor.length >= 1, "Length \(descriptor.length) must be at least 1.")
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
        
        if !modifiedRange.isEmpty {
            RenderBackend.buffer(self, didModifyRange: modifiedRange)
        }
        self.stateFlags.formUnion(.initialised)
        return result
    }
    
    public func withMutableContents<A>(range: Range<Int>, _ perform: (_ buffer: UnsafeMutableRawBufferPointer, _ modifiedRange: inout Range<Int>) /* async */ throws -> A) /*reasync */rethrows -> A {
        self.waitForCPUAccess(accessType: .readWrite)
        let contents = RenderBackend.bufferContents(for: self, range: range)
        var modifiedRange = range
        
        let result = try /* await */perform(UnsafeMutableRawBufferPointer(start: UnsafeMutableRawPointer(contents), count: range.count), &modifiedRange)
        
        if !modifiedRange.isEmpty {
            RenderBackend.buffer(self, didModifyRange: modifiedRange)
        }
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
    
    public var label : String? {
        get {
            return self[\.labels]
        }
        nonmutating set {
            self[\.labels] = newValue
            RenderBackend.updateLabel(on: self)
        }
    }
    
    var _deferredSliceActions : [DeferredBufferSlice] {
        get {
            return self[\.deferredSliceActions]!
        }
        nonmutating set {
            self[\.deferredSliceActions] = newValue
        }
    }
    
    public subscript(waitIndexFor queue: Queue, accessType type: ResourceAccessType) -> UInt64 {
        get {
            guard self._usesPersistentRegistry else { return 0 }
            if type == .read {
                return self[\.readWaitIndices]![Int(queue.index)]
            } else {
                return self[\.writeWaitIndices]![Int(queue.index)]
            }
        }
        nonmutating set {
            guard self._usesPersistentRegistry else { return }
            
            if type == .read || type == .readWrite {
                self[\.readWaitIndices]![Int(queue.index)] = newValue
            }
            if type == .write || type == .readWrite {
                self[\.writeWaitIndices]![Int(queue.index)] = newValue
            }
        }
    }
    
    /// Returns whether the resource is known to currently be in use by the CPU or GPU.
    public var isKnownInUse: Bool {
        guard let activeRenderGraphs = self.pointer(for: \.activeRenderGraphs) else {
            return true // Transient resource
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
        self.heap?.markAsUsed(activeRenderGraphMask: activeRenderGraphMask)
        
        guard let activeRenderGraphs = self.pointer(for: \.activeRenderGraphs) else {
            return
        }
        UInt8.AtomicRepresentation.atomicLoadThenBitwiseOr(with: activeRenderGraphMask, at: activeRenderGraphs, ordering: .relaxed)
    }
    
    public func dispose() {
        guard self._usesPersistentRegistry, self.isValid else {
            return
        }
        self.heap?.childResources.remove(Resource(self))
        PersistentBufferRegistry.instance.dispose(self)
    }
    
    public static var resourceType: ResourceType {
        return .buffer
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
    
    public init(handle: Handle) {
        assert(Resource(handle: handle).type == .texture)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
    }
    
    @available(*, deprecated, renamed: "init(descriptor:renderGraph:flags:)")
    public init(descriptor: TextureDescriptor, frameGraph: RenderGraph?, flags: ResourceFlags = []) {
        self.init(descriptor: descriptor, renderGraph: frameGraph, flags: flags)
    }
    
    public init(descriptor: TextureDescriptor, renderGraph: RenderGraph? = nil, flags: ResourceFlags = []) {
        precondition((1...16384).contains(descriptor.width) && (1...16384).contains(descriptor.height) && (1...16384).contains(descriptor.depth), "Invalid size for descriptor \(descriptor); all dimensions must be in the range 1...16384")
        
        if flags.contains(.persistent) || flags.contains(.historyBuffer) {
            self = PersistentTextureRegistry.instance.allocate(descriptor: descriptor, heap: nil, flags: flags)
        } else {
            guard let renderGraph = renderGraph ?? RenderGraph.activeRenderGraph else {
                fatalError("The RenderGraph must be specified for transient resources created outside of a render pass' execute() method.")
            }
            precondition(renderGraph.transientRegistryIndex >= 0, "Transient resources are not supported on the RenderGraph \(renderGraph)")
            self = TransientTextureRegistry.instances[renderGraph.transientRegistryIndex].allocate(descriptor: descriptor, flags: flags)
        }
        
        if self.flags.contains(.persistent) {
            assert(!descriptor.usageHint.isEmpty, "Persistent resources must explicitly specify their usage.")
            let didAllocate = RenderBackend.materialisePersistentTexture(self)
            assert(didAllocate, "Allocation failed for persistent texture \(self)")
            if !didAllocate { self.dispose() }
        }
    }
    
    public static func _createPersistentTextureWithoutDescriptor(flags: ResourceFlags = [.persistent]) -> Texture {
        precondition(flags.contains(.persistent))
        return PersistentTextureRegistry.instance.allocateHandle(flags: flags)
    }
    
    public func _initialisePersistentTexture(descriptor: TextureDescriptor, heap: Heap?) {
        precondition(self.flags.contains(.persistent))
        PersistentTextureRegistry.instance.initialize(resource: self, descriptor: descriptor, heap: heap, flags: self.flags)
        
        assert(!descriptor.usageHint.isEmpty, "Persistent resources must explicitly specify their usage.")
        let didAllocate = RenderBackend.materialisePersistentTexture(self)
        assert(didAllocate, "Allocation failed for persistent texture \(self)")
        if !didAllocate { self.dispose() }
    }
    
    public init?(descriptor: TextureDescriptor, heap: Heap, flags: ResourceFlags = [.persistent]) {
        precondition(descriptor.width <= 16384 && descriptor.height <= 16384 && descriptor.depth <= 1024)
        
        assert(flags.contains(.persistent), "Heap-allocated resources must be persistent.")
        assert(!descriptor.usageHint.isEmpty, "Persistent resources must explicitly specify their usage.")
        
        self = PersistentTextureRegistry.instance.allocate(descriptor: descriptor, heap: heap, flags: flags)
        
        if !RenderBackend.materialisePersistentTexture(self) {
            self.dispose()
            return nil
        }
        
        heap.childResources.insert(Resource(self))
    }
    
    @available(*, deprecated, renamed: "init(descriptor:externalResource:renderGraph:flags:)")
    public init(descriptor: TextureDescriptor, externalResource: Any, frameGraph: RenderGraph?, flags: ResourceFlags = [.persistent, .externalOwnership]) {
        self.init(descriptor: descriptor, externalResource: externalResource, renderGraph: frameGraph, flags: flags)
    }
    
    public init(descriptor: TextureDescriptor, externalResource: Any, renderGraph: RenderGraph? = nil, flags: ResourceFlags = [.persistent, .externalOwnership]) {
        if flags.contains(.persistent) || flags.contains(.historyBuffer) {
            self = PersistentTextureRegistry.instance.allocate(descriptor: descriptor, heap: nil, flags: flags)
        } else {
            guard let renderGraph = renderGraph ?? RenderGraph.activeRenderGraph else {
                fatalError("The RenderGraph must be specified for transient resources created outside of a render pass' execute() method.")
            }
            self = TransientTextureRegistry.instances[renderGraph.transientRegistryIndex].allocate(descriptor: descriptor, flags: flags)
        }
        
        if self.flags.contains(.persistent) {
            assert(!descriptor.usageHint.isEmpty, "Persistent resources must explicitly specify their usage.")
        }
        RenderBackend.registerExternalResource(Resource(self), backingResource: externalResource)
    }
    
    public init(viewOf base: Texture, descriptor: TextureViewDescriptor, renderGraph: RenderGraph? = nil) {
        let flags : ResourceFlags = .resourceView
        
        guard let transientRegistryIndex = renderGraph?.transientRegistryIndex ?? RenderGraph.activeRenderGraph?.transientRegistryIndex ?? (!base._usesPersistentRegistry ? base.transientRegistryIndex : nil) else {
            fatalError("The RenderGraph must be specified for transient resources created outside of a render pass' execute() method.")
        }
        precondition(transientRegistryIndex >= 0, "Transient resources are not supported on this RenderGraph")
        
        self = TransientTextureRegistry.instances[transientRegistryIndex].allocate(descriptor: descriptor, baseResource: base, flags: flags)
    }
    
    public init(viewOf base: Buffer, descriptor: Buffer.TextureViewDescriptor, renderGraph: RenderGraph? = nil) {
        let flags : ResourceFlags = .resourceView
        
        guard let transientRegistryIndex = renderGraph?.transientRegistryIndex ?? RenderGraph.activeRenderGraph?.transientRegistryIndex ?? (!base._usesPersistentRegistry ? base.transientRegistryIndex : nil) else {
            fatalError("The RenderGraph must be specified for transient resources created outside of a render pass' execute() method.")
        }
        precondition(transientRegistryIndex >= 0, "Transient resources are not supported on this RenderGraph")
        
        self = TransientTextureRegistry.instances[transientRegistryIndex].allocate(descriptor: descriptor, baseResource: base, flags: flags)
    }
    
    @available(*, deprecated, renamed: "init(descriptor:isMinimised:nativeWindow:renderGraph:)")
    public init(windowId: Int, descriptor: TextureDescriptor, isMinimised: Bool, nativeWindow: Any, frameGraph: RenderGraph) {
        self.init(descriptor: descriptor, isMinimised: isMinimised, nativeWindow: nativeWindow, renderGraph: frameGraph)
    }
    
    @available(*, deprecated, renamed: "init(descriptor:isMinimised:nativeWindow:renderGraph:)")
    public init(windowId: Int, descriptor: TextureDescriptor, isMinimised: Bool, nativeWindow: Any, renderGraph: RenderGraph) {
        self.init(descriptor: descriptor, isMinimised: isMinimised, nativeWindow: nativeWindow, renderGraph: renderGraph)
    }
    
    public init(descriptor: TextureDescriptor, isMinimised: Bool, nativeWindow: Any, renderGraph: RenderGraph) {
        self.init(descriptor: descriptor, renderGraph: renderGraph, flags: isMinimised ? [] : .windowHandle)
        
        if !isMinimised {
            RenderBackend.registerWindowTexture(texture: self, context: nativeWindow)
        }
    }
    
    public func copyBytes(to bytes: UnsafeMutableRawPointer, bytesPerRow: Int, region: Region, mipmapLevel: Int) {
        self.waitForCPUAccess(accessType: .read)
        RenderBackend.copyTextureBytes(from: self, to: bytes, bytesPerRow: bytesPerRow, region: region, mipmapLevel: mipmapLevel)
    }
    
    public func replace(region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) {
        self.waitForCPUAccess(accessType: .write)
        
        RenderBackend.replaceTextureRegion(texture: self, region: region, mipmapLevel: mipmapLevel, withBytes: bytes, bytesPerRow: bytesPerRow)
    }
    
    public func replace(region: Region, mipmapLevel: Int, slice: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int) {
        self.waitForCPUAccess(accessType: .write)
        
        RenderBackend.replaceTextureRegion(texture: self, region: region, mipmapLevel: mipmapLevel, slice: slice, withBytes: bytes, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerImage)
    }
    
    public var stateFlags: ResourceStateFlags {
        get {
            if self.flags.intersection([.historyBuffer, .persistent]) == [] {
                return []
            }
            return self[\.stateFlags] ?? []
        }
        nonmutating set {
            assert(self.flags.intersection([.historyBuffer, .persistent]) != [], "State flags can only be set on persistent resources.")
            
            self[\.stateFlags] = newValue
        }
    }
    
    public var storageMode: StorageMode {
        return self.descriptor.storageMode
    }
    
    public internal(set) var descriptor : TextureDescriptor {
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
    
    public var label : String? {
        get {
            return self[\.labels]
        }
        nonmutating set {
            self[\.labels] = newValue
        }
    }
    
    public subscript(waitIndexFor queue: Queue, accessType type: ResourceAccessType) -> UInt64 {
        get {
            if type == .read {
                return self[\.readWaitIndices]?[Int(queue.index)] ?? 0
            } else {
                return self[\.writeWaitIndices]?[Int(queue.index)] ?? 0
            }
        }
        nonmutating set {
            guard self._usesPersistentRegistry else { return }
            
            if type == .read || type == .readWrite {
                self[\.readWaitIndices]?[Int(queue.index)] = newValue
            }
            if type == .write || type == .readWrite {
                self[\.writeWaitIndices]?[Int(queue.index)] = newValue
            }
        }
    }
    
    public var size : Size {
        return Size(width: self.descriptor.width, height: self.descriptor.height, depth: self.descriptor.depth)
    }
    
    public var width : Int {
        return self.descriptor.width
    }
    
    public var height : Int {
        return self.descriptor.height
    }
    
    public var depth : Int {
        return self.descriptor.depth
    }
    
    public var baseResource : Resource? {
        get {
            if !self.isTextureView {
                return nil
            } else {
                return self[\.baseResources]
            }
        }
    }
    
    public var textureViewBaseInfo : TextureViewBaseInfo? {
        if !self.isTextureView {
            return nil
        } else {
            return self[\.textureViewInfos]
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
        self.baseResource?.markAsUsed(activeRenderGraphMask: activeRenderGraphMask)
        self.heap?.markAsUsed(activeRenderGraphMask: activeRenderGraphMask)
        
        guard let activeRenderGraphs = self.pointer(for: \.activeRenderGraphs) else {
            return
        }
        UInt8.AtomicRepresentation.atomicLoadThenBitwiseOr(with: activeRenderGraphMask, at: activeRenderGraphs, ordering: .relaxed)
    }
    
    public func dispose() {
        guard self._usesPersistentRegistry, self.isValid else {
            return
        }
        self.heap?.childResources.remove(Resource(self))
        PersistentTextureRegistry.instance.dispose(self)
    }
    
    public static let invalid = Texture(descriptor: TextureDescriptor(type: .type2D, format: .r32Float, width: 1, height: 1, mipmapped: false, storageMode: .private, usage: .shaderRead), flags: .persistent)
    
    public static var resourceType: ResourceType {
        return .texture
    }
}

extension Texture: ResourceProtocolImpl {
    typealias SharedProperties = TextureProperties
    typealias TransientProperties = TextureProperties.TransientTextureProperties
    typealias PersistentProperties = TextureProperties.PersistentTextureProperties
    
    static func transientRegistry(index: Int) -> TransientTextureRegistry? {
        return TransientTextureRegistry.instances[index]
    }
    
    static var persistentRegistry: PersistentRegistry<Self> { PersistentTextureRegistry.instance }
    
    typealias Descriptor = TextureDescriptor
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
