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
    case accelerationStructure
    case intersectionFunctionTable
    case objectPayload
    case hazardTrackingGroup
    
    public var isMaterialisedOnFirstUse: Bool {
        switch self {
        case .argumentBuffer, .visibleFunctionTable, .intersectionFunctionTable:
            return true
        default:
            return false
        }
    }
}

/*!
 @abstract Points at which a fence may be waited on or signaled.
 @constant RenderStageVertex   All vertex work prior to rasterization has completed.
 @constant RenderStageFragment All rendering work has completed.
 */
public struct RenderStages : OptionSet, Hashable, Sendable {
    
    public let rawValue : UInt
    
    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }
    
    public static let vertex: RenderStages = RenderStages(rawValue: 1 << 0)
    public static let fragment: RenderStages = RenderStages(rawValue: 1 << 1)
    public static let tile: RenderStages = RenderStages(rawValue: 1 << 2)
    public static let object: RenderStages = RenderStages(rawValue: 1 << 3)
    public static let mesh: RenderStages = RenderStages(rawValue: 1 << 4)
    
    public static let compute: RenderStages = RenderStages(rawValue: 1 << 5)
    public static let blit: RenderStages = RenderStages(rawValue: 1 << 6)
    
    public static let cpuBeforeRender: RenderStages = RenderStages(rawValue: 1 << 7)
    
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
    
    @inlinable @inline(__always)
    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }
    
    @inlinable
    public static var persistent: ResourceFlags { ResourceFlags(rawValue: 1 << 0) }
    
    @inlinable
    public static var windowHandle: ResourceFlags { ResourceFlags(rawValue: 1 << 1) }
    
    @inlinable
    public static var historyBuffer: ResourceFlags { ResourceFlags(rawValue: 1 << 2) }
    
    @inlinable
    public static var externalOwnership: ResourceFlags { ResourceFlags(rawValue: 1 << 3) }
    
    @inlinable
    public static var immutableOnceInitialised: ResourceFlags { ResourceFlags(rawValue: 1 << 4) }
    
    /// If this resource is a view into another resource.
    @inlinable
    public static var resourceView: ResourceFlags { ResourceFlags(rawValue: 1 << 5) }
}

public struct ResourceStateFlags : OptionSet, Sendable {
    public let rawValue: UInt16
    
    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }
    
    public static let initialised = ResourceStateFlags(rawValue: 1 << 0)
}

public struct ResourceAccessType: OptionSet, Hashable, Sendable {
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

public protocol ResourceProtocol: Sendable {
    init(handle: Handle)
    init?(_ resource: Resource)
    func dispose()
    
    var handle: Handle { get }
    var stateFlags: ResourceStateFlags { get nonmutating set }
    
    var label: String? { get nonmutating set }
    var storageMode: StorageMode { get }
    var heap: Heap? { get }
    var baseResource: Resource? { get }
    var usages: ChunkArray<RecordedResourceUsage> { get nonmutating set }
    var resourceForUsageTracking: Resource { get }
    
    /// The command buffer index on which to wait on a particular queue `queue` before it is safe to perform an access of type `type`.
    subscript(waitIndexFor queue: Queue, accessType type: ResourceAccessType) -> UInt64 { get nonmutating set }
    
    /// Returns whether or not a resource handle represents a valid GPU resource.
    /// A resource handle is valid if it is a transient resource that was allocated in the current frame
    /// or is a persistent resource that has not been disposed.
    var isValid: Bool { get }
    
    /// Returns whether the resource is known to currently be in use by the CPU or GPU.
    var isKnownInUse: Bool { get }
    
    var hasPendingRenderGraph: Bool { get }
    
    /// Marks the resource as being currently in use by `renderGraph`, ensuring that, if `dispose()` is called,
    /// it will not get deallocated until after the `renderGraph` has completed.
    func markAsUsed(by renderGraph: RenderGraph)
    
    func markAsUsed(activeRenderGraphMask: ActiveRenderGraphMask)
    
    var purgeableState: ResourcePurgeableState { get nonmutating set }
    func updatePurgeableState(to: ResourcePurgeableState) -> ResourcePurgeableState
    
    static var resourceType: ResourceType { get }
}

public protocol GroupHazardTrackableResource: ResourceProtocol {
    var hazardTrackingGroup: HazardTrackingGroup<Self>? { get nonmutating set }
}

@usableFromInline
protocol ResourceProtocolImpl: GroupHazardTrackableResource, Hashable, CustomHashable {
    associatedtype Descriptor
    associatedtype SharedProperties: ResourceProperties where SharedProperties.Descriptor == Descriptor
    associatedtype TransientProperties: ResourceProperties where TransientProperties.Descriptor == Descriptor
    associatedtype PersistentProperties: PersistentResourceProperties where PersistentProperties.Descriptor == Descriptor
    
    associatedtype TransientRegistry: Substrate.TransientRegistry where TransientRegistry.Resource == Self
    typealias PersistentRegistry = Substrate.PersistentRegistry<Self>
    
    static var itemsPerChunk: Int { get }
    
    static func transientRegistry(index: Int) -> TransientRegistry?
    static var persistentRegistry: PersistentRegistry { get }
    
    static var tracksUsages: Bool { get }
}

extension ResourceProtocolImpl {
    @inlinable static var itemsPerChunk: Int { 256 }
    
    @inlinable
    public init?(_ resource: Resource) {
        guard Self.resourceType == resource.type else { return nil }
        self.init(handle: resource.handle)
    }
    
    @inlinable
    public var customHashValue : Int {
        return Int(truncatingIfNeeded: self.handle.bitPattern)
    }
    
    public func dispose() {
        guard self._usesPersistentRegistry, self.isValid else {
            return
        }
        self.heap?.childResources.remove(Resource(self))
        Self.persistentRegistry.dispose(self)
    }
    
    
    @_transparent
    @inlinable
    func pointer<T>(for keyPath: KeyPath<SharedResourceProperties<Descriptor>, UnsafeMutablePointer<T>>) -> UnsafeMutablePointer<T> {
        if self._usesPersistentRegistry {
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: Self.itemsPerChunk)
            return Self.persistentRegistry.sharedPropertyChunks[chunkIndex][keyPath: keyPath].advanced(by: indexInChunk)
        } else {
            let (properties, indexInChunk) = Self.transientRegistry(index: self.transientRegistryIndex)!.sharedResourceProperties(index: self.index)
            return properties[keyPath: keyPath].advanced(by: indexInChunk)
        }
    }
    
    @_transparent
    @inlinable
    func pointer<T>(for keyPath: KeyPath<SharedProperties, UnsafeMutablePointer<T>>) -> UnsafeMutablePointer<T> {
        if self._usesPersistentRegistry {
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: Self.itemsPerChunk)
            return Self.persistentRegistry.sharedChunks![chunkIndex][keyPath: keyPath].advanced(by: indexInChunk)
        } else {
            let (properties, indexInChunk) = Self.transientRegistry(index: self.transientRegistryIndex)!.sharedProperties(index: self.index)
            return properties[keyPath: keyPath].advanced(by: indexInChunk)
        }
    }
    
    @_transparent
    @inlinable
    func pointer<T>(for keyPath: KeyPath<TransientProperties, UnsafeMutablePointer<T>>) -> UnsafeMutablePointer<T>? {
        if self._usesPersistentRegistry {
            return nil
        }
        let (properties, indexInChunk) = Self.transientRegistry(index: self.transientRegistryIndex)!.transientProperties(index: self.index)
        return properties[keyPath: keyPath].advanced(by: indexInChunk)
    }
    
    @_transparent
    @inlinable
    func pointer<T>(for keyPath: KeyPath<PersistentProperties, UnsafeMutablePointer<T>>) -> UnsafeMutablePointer<T>? {
        guard self._usesPersistentRegistry else { return nil }
        
        let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: Self.itemsPerChunk)
        return Self.persistentRegistry.persistentChunks?[chunkIndex][keyPath: keyPath].advanced(by: indexInChunk)
    }
    
    @inlinable @inline(__always)
    subscript<T>(keyPath: KeyPath<SharedResourceProperties<Descriptor>, UnsafeMutablePointer<T>>) -> T {
        get {
            return self.pointer(for: keyPath).pointee
        }
        nonmutating set {
            self.pointer(for: keyPath).pointee = newValue
        }
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
    
    public var hazardTrackingGroup: HazardTrackingGroup<Self>? {
        get {
            guard self.flags.contains(.persistent) else {
                return nil
            }
            
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: Self.itemsPerChunk)
            return Self.persistentRegistry.sharedPropertyChunks[chunkIndex].hazardTrackingGroups[indexInChunk].map { HazardTrackingGroup($0)! }
        }
        nonmutating set {
            guard let newValue = newValue else {
                precondition(self.hazardTrackingGroup == nil, "Cannot remove a resource from a hazard tracking group after it has been added to it.")
                return
            }
            precondition(self.flags.contains(.persistent), "Hazard tracking groups can only be set on persistent resources.")
            
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: Self.itemsPerChunk)
            newValue.resources.insert(self)
            Self.persistentRegistry.sharedPropertyChunks[chunkIndex].hazardTrackingGroups[indexInChunk] = newValue.group
        }
    }
    
    @usableFromInline
    var _usagesPointer: UnsafeMutablePointer<ChunkArray<RecordedResourceUsage>>? {
        if self._usesPersistentRegistry {
            if let hazardTrackingGroup = self.hazardTrackingGroup {
                return hazardTrackingGroup.group._usagesPointer
            }
            
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: Self.itemsPerChunk)
            return Self.persistentRegistry.sharedPropertyChunks[chunkIndex].usages?.advanced(by: indexInChunk)
        } else {
            let (properties, indexInChunk) = Self.transientRegistry(index: self.transientRegistryIndex)!.sharedResourceProperties(index: self.index)
            return properties.usages?.advanced(by: indexInChunk)
        }
    }
    
    public internal(set) var descriptor: Descriptor {
        get {
            if self._usesPersistentRegistry {
                let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: Self.itemsPerChunk)
                return Self.persistentRegistry.sharedPropertyChunks[chunkIndex].descriptors?[indexInChunk] ?? unsafeBitCast((), to: Descriptor.self)
            } else {
                let (properties, indexInChunk) = Self.transientRegistry(index: self.transientRegistryIndex)!.sharedResourceProperties(index: self.index)
                return properties.descriptors?[indexInChunk] ?? unsafeBitCast((), to: Descriptor.self)
            }
        }
        nonmutating set {
            if self._usesPersistentRegistry {
                let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: Self.itemsPerChunk)
                Self.persistentRegistry.sharedPropertyChunks[chunkIndex].descriptors?.advanced(by: indexInChunk).pointee = newValue
            } else {
                let (properties, indexInChunk) = Self.transientRegistry(index: self.transientRegistryIndex)!.sharedResourceProperties(index: self.index)
                properties.descriptors?.advanced(by: indexInChunk).pointee = newValue
            }
        }
    }
    
    public var usages: ChunkArray<RecordedResourceUsage> {
        get {
            let trackingResource = self.resourceForUsageTracking
            if trackingResource.handle != self.handle {
                return trackingResource.usages
            } else {
                return self._usagesPointer?.pointee ?? .init()
            }
        }
        nonmutating set {
            let trackingResource = self.resourceForUsageTracking
            if trackingResource.handle != self.handle {
                trackingResource.usages = newValue
            } else {
                self._usagesPointer?.pointee = newValue
            }
        }
    }
    
    @inline(__always)
    var _activeRenderGraphsPointer: UnsafeMutablePointer<UInt8.AtomicRepresentation>? {
        if self._usesPersistentRegistry {
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: Self.itemsPerChunk)
            return Self.persistentRegistry.persistentChunks?[chunkIndex].activeRenderGraphsOptional?.advanced(by: indexInChunk)
        } else {
            return nil
        }
    }
    
    
    @inline(__always)
    var _readWaitIndicesPointer: UnsafeMutablePointer<QueueCommandIndex.AtomicRepresentation>? {
        if self._usesPersistentRegistry {
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: Self.itemsPerChunk)
            return Self.persistentRegistry.persistentChunks?[chunkIndex].readWaitIndicesOptional?.advanced(by: indexInChunk * QueueCommandIndices.scalarCount)
        } else {
            return nil
        }
    }
    
    @inline(__always)
    var _writeWaitIndicesPointer: UnsafeMutablePointer<QueueCommandIndex.AtomicRepresentation>? {
        if self._usesPersistentRegistry {
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: Self.itemsPerChunk)
            return Self.persistentRegistry.persistentChunks?[chunkIndex].writeWaitIndicesOptional?.advanced(by: indexInChunk * QueueCommandIndices.scalarCount)
        } else {
            return nil
        }
    }
    
    public subscript(waitIndexFor queue: Queue, accessType type: ResourceAccessType) -> QueueCommandIndex {
        get {
            guard self._usesPersistentRegistry else { return 0 }
            if type == .read {
                guard let pointer = self._readWaitIndicesPointer else { return 0 }
                return QueueCommandIndex.AtomicRepresentation.atomicLoad(at: pointer.advanced(by: Int(queue.index)), ordering: .relaxed)
            } else {
                guard let pointer = self._writeWaitIndicesPointer else { return 0 }
                return QueueCommandIndex.AtomicRepresentation.atomicLoad(at: pointer.advanced(by: Int(queue.index)), ordering: .relaxed)
            }
        }
        nonmutating set {
            guard self._usesPersistentRegistry else { return }
            
            if type == .read || type == .readWrite {
                if let pointer = self._readWaitIndicesPointer {
                    QueueCommandIndex.AtomicRepresentation.atomicMax(at: pointer.advanced(by: Int(queue.index)), value: newValue)
                }
            }
            if type == .write || type == .readWrite {
                if let pointer = self._writeWaitIndicesPointer {
                    QueueCommandIndex.AtomicRepresentation.atomicMax(at: pointer.advanced(by: Int(queue.index)), value: newValue)
                }
            }
        }
    }
    
    public var hasPendingRenderGraph: Bool {
        guard self._usesPersistentRegistry else {
            return true
        }
        let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: Self.itemsPerChunk)
        if let activeRenderGraphs = Self.persistentRegistry.persistentChunks?[chunkIndex].activeRenderGraphsOptional {
            let activeRenderGraphMask = UInt8.AtomicRepresentation.atomicLoad(at: activeRenderGraphs.advanced(by: indexInChunk), ordering: .relaxed)
            return activeRenderGraphMask != 0
        }
        return false
    }
        
    
    /// Returns whether the resource is known to currently be in use by the CPU or GPU.
    public var isKnownInUse: Bool {
        guard let activeRenderGraphs = self._activeRenderGraphsPointer else {
            return !self._usesPersistentRegistry && self.isValid
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
        
        guard let activeRenderGraphs = self._activeRenderGraphsPointer else {
            return
        }
        UInt8.AtomicRepresentation.atomicLoadThenBitwiseOr(with: activeRenderGraphMask, at: activeRenderGraphs, ordering: .relaxed)
    }
    
    @_transparent
    var _labelsPointer : UnsafeMutablePointer<String?> {
        if self._usesPersistentRegistry {
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: Self.itemsPerChunk)
            return Self.persistentRegistry.sharedPropertyChunks[chunkIndex].labels.advanced(by: indexInChunk)
        } else {
            return Self.transientRegistry(index: self.transientRegistryIndex)!.labelPointer(index: self.index)
        }
    }
    
    public var label : String? {
        get {
            return self._labelsPointer.pointee
        }
        nonmutating set {
            self._labelsPointer.pointee = newValue
            RenderBackend.updateLabel(on: self)
        }
    }
    
    var backingResourcePointer: UnsafeMutableRawPointer? {
        get {
            return self.pointer(for: \.backingResources).pointee
        }
        nonmutating set {
            self.pointer(for: \.backingResources).pointee = newValue
        }
    }
    
    public var resourceForUsageTracking: Resource {
        return (self.hazardTrackingGroup.map { Resource($0.group) } ?? self.baseResource) ?? Resource(self)
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
    
    public var heap: Heap? {
        return nil
    }
    
    public var baseResource: Resource? {
        return nil
    }
}

public struct ResourceHandle: Hashable, @unchecked Sendable {
    @inlinable @inline(__always)
    public static var typeBitsRange : Range<Int> { return 56..<64 }
    
    @inlinable @inline(__always)
    public static var flagBitsRange : Range<Int> { return 40..<56 }
    
    @inlinable @inline(__always)
    public static var generationBitsRange : Range<Int> { return 32..<40 }
    
    @inlinable @inline(__always)
    public static var transientRegistryIndexBitsRange : Range<Int> { return 28..<32 }
    
    @inlinable @inline(__always)
    public static var indexBitsRange : Range<Int> { return 0..<28 }
    
    @usableFromInline var _handle: UnsafeRawPointer
    
    @inlinable @inline(__always)
    public var bitPattern: UInt64 { return UInt64(UInt(bitPattern: _handle)) }
    
    @inlinable
    public init(bitPattern handle: UInt64) {
        assert(ResourceType(rawValue: ResourceType.RawValue(truncatingIfNeeded: handle.bits(in: Resource.typeBitsRange))) != nil)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
    }
    
    @inlinable @inline(__always)
    public var resourceType: ResourceType {
        return ResourceType(rawValue: ResourceType.RawValue(truncatingIfNeeded: self.bitPattern.bits(in: Resource.typeBitsRange)))!
    }
    
    @inlinable @inline(__always)
    public var flags : ResourceFlags {
        return ResourceFlags(rawValue: ResourceFlags.RawValue(truncatingIfNeeded: self.bitPattern.bits(in: Self.flagBitsRange)))
    }
    
    @inlinable @inline(__always)
    public var generation : UInt8 {
        return UInt8(truncatingIfNeeded: self.bitPattern.bits(in: Self.generationBitsRange))
    }
    
    @inlinable @inline(__always)
    public var transientRegistryIndex : Int {
        return Int(self.bitPattern.bits(in: Self.transientRegistryIndexBitsRange))
    }
    
    @inlinable @inline(__always)
    public var index : Int {
        return Int(truncatingIfNeeded: self.bitPattern.bits(in: Self.indexBitsRange))
    }
}

public struct Resource : ResourceProtocol, Hashable {
    public static var resourceType: ResourceType { fatalError() }
    
    public let handle: ResourceHandle
    
    public init<R : ResourceProtocol>(_ resource: R) {
        self.handle = resource.handle
    }
    
    public init(handle: Handle) {
        self.handle = handle
    }
    
    
    public var heap : Heap? {
        if self.type == .heap {
            return Heap(handle: self.handle)
        } else {
            return self[\.heap]
        }
    }
    
    public var baseResource : Resource? {
        return self[\.baseResource]
    }
    
    @_transparent
    func withUnderlyingResource<R>(_ perform: (any ResourceProtocolImpl) -> R) -> R {
        switch self.type {
        case .buffer:
            return perform(Buffer(handle: self.handle))
        case .texture:
            return perform(Texture(handle: self.handle))
        case .argumentBuffer:
            return perform(ArgumentBuffer(handle: self.handle))
        case .argumentBufferArray:
            return perform(ArgumentBufferArray(handle: self.handle))
        case .heap:
            return perform(Heap(handle: self.handle))
        case .accelerationStructure:
            return perform(AccelerationStructure(handle: self.handle))
        case .intersectionFunctionTable:
            return perform(IntersectionFunctionTable(handle: self.handle))
        case .visibleFunctionTable:
            return perform(VisibleFunctionTable(handle: self.handle))
        case .hazardTrackingGroup:
            return perform(_HazardTrackingGroup(handle: self.handle))
        default:
            fatalError()
        }
    }
    
    @inline(__always)
    subscript<T>(_ property: KeyPath<ResourceProtocol, T>) -> T {
        get {
            return self.withUnderlyingResource({ $0[keyPath: property] })
        }
    }
    
    @inline(__always)
    subscript<T>(_ property: ReferenceWritableKeyPath<ResourceProtocol, T>) -> T {
        get {
            return self.withUnderlyingResource({ $0[keyPath: property] })
        }
        nonmutating set {
            self.withUnderlyingResource({ $0[keyPath: property] = newValue })
        }
    }
    
    public var stateFlags: ResourceStateFlags {
        get {
            return self[\.stateFlags]
        }
        nonmutating set {
            self[\.stateFlags] = newValue
        }
    }
    
    public var storageMode: StorageMode {
        get {
            return self[\.storageMode]
        }
    }
    
    public var label: String? {
        get {
            return self[\.label]
        }
        nonmutating set {
            self[\.label] = newValue
        }
    }
    
    public subscript(waitIndexFor queue: Queue, accessType type: ResourceAccessType) -> UInt64 {
        get {
            return self.withUnderlyingResource({ $0[waitIndexFor: queue, accessType: type] })
        }
        nonmutating set {
            self.withUnderlyingResource({ $0[waitIndexFor: queue, accessType: type] = newValue })
        }
    }
    
    public var usages: ChunkArray<RecordedResourceUsage> {
        get {
            self[\.usages]
        }
        nonmutating set {
            self[\.usages] = newValue
        }
    }
    
    var backingResourcePointer: UnsafeMutableRawPointer? {
        get {
            return self.withUnderlyingResource { impl in
                impl.backingResourcePointer
            }
        } set {
            self.withUnderlyingResource { impl in
                impl.backingResourcePointer = newValue
            }
        }
    }
    
    public var resourceForUsageTracking: Resource {
        return self.withUnderlyingResource({ $0.resourceForUsageTracking })
    }
    
    public var isKnownInUse: Bool {
        self[\.isKnownInUse]
    }
    
    public var isValid: Bool {
        self[\.isValid]
    }
    
    public var hasPendingRenderGraph: Bool {
        self.withUnderlyingResource({ $0.hasPendingRenderGraph })
    }
    
    public func markAsUsed(activeRenderGraphMask: ActiveRenderGraphMask) {
        self.withUnderlyingResource({ $0.markAsUsed(activeRenderGraphMask: activeRenderGraphMask) })
    }
    
    public func dispose() {
        self.withUnderlyingResource({ $0.dispose() })
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
        case .heap:
            return Heap(handle: self.handle).description
        case .accelerationStructure:
            return AccelerationStructure(handle: self.handle).description
        case .intersectionFunctionTable:
            return IntersectionFunctionTable(handle: self.handle).description
        case .visibleFunctionTable:
            return VisibleFunctionTable(handle: self.handle).description
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
    public typealias Handle = ResourceHandle
    
    @inlinable @inline(__always)
    public static var typeBitsRange : Range<Int> { return 56..<64 }
    
    @inlinable @inline(__always)
    public static var flagBitsRange : Range<Int> { return 40..<56 }
    
    @inlinable @inline(__always)
    public static var generationBitsRange : Range<Int> { return 32..<40 }
    
    @inlinable @inline(__always)
    public static var transientRegistryIndexBitsRange : Range<Int> { return 28..<32 }
    
    @inlinable @inline(__always)
    public static var indexBitsRange : Range<Int> { return 0..<28 }
    
    @inlinable @inline(__always)
    public var type : ResourceType {
        return self.handle.resourceType
    }
    
    @inlinable @inline(__always)
    public var flags : ResourceFlags {
        return self.handle.flags
    }
    
    @inlinable @inline(__always)
    public var generation : UInt8 {
        return self.handle.generation
    }
    
    @inlinable @inline(__always)
    public var transientRegistryIndex : Int {
        return self.handle.transientRegistryIndex
    }
    
    @inlinable @inline(__always)
    public var index : Int {
        return self.handle.index
    }
    
    @inlinable @inline(__always)
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
            _ = newValue
        }
    }
    
    public func isAvailableForCPUAccess(accessType: ResourceAccessType) -> Bool {
        guard self.flags.contains(.persistent) else { return self.isValid }
        
        for queue in QueueRegistry.allQueues {
            let waitIndex = self[waitIndexFor: queue, accessType: accessType]
            if queue.lastCompletedCommand < waitIndex {
                return false
            }
        }
        return true
    }
    
    public func checkHasCPUAccess(accessType: ResourceAccessType) {
        guard self.flags.contains(.persistent) else { return }
        
        precondition(self.isAvailableForCPUAccess(accessType: accessType), "Resource \(self) is not accessible by the CPU for access type: \(accessType); use withContentsAsync or withMutableContentsAsync instead.")
    }
    
    public func waitForCPUAccess(accessType: ResourceAccessType) async {
        guard self.flags.contains(.persistent) else { return }
        if !self.stateFlags.contains(.initialised) { return }
        
        for queue in QueueRegistry.allQueues {
            let waitIndex = self[waitIndexFor: queue, accessType: accessType]
            await queue.waitForCommandCompletion(waitIndex)
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

extension QueueCommandIndex.AtomicRepresentation {
    @discardableResult
    static func atomicMax(at pointer: UnsafeMutablePointer<Self>, value: QueueCommandIndex) -> Bool {
        var currentValue = Self.atomicLoad(at: pointer, ordering: .relaxed)
        guard currentValue <= value else { return false }
        repeat {
            let (exchanged, original) = Self.atomicWeakCompareExchange(expected: currentValue, desired: value, at: pointer, successOrdering: .relaxed, failureOrdering: .relaxed)
            if exchanged { return true }
            currentValue = original
        } while value > currentValue
        return false
    }
    
    static func snapshotIndices(at pointer: UnsafeMutablePointer<Self>, ordering: AtomicLoadOrdering) -> QueueCommandIndices {
        var result = QueueCommandIndices()
        for i in 0..<QueueCommandIndices.scalarCount {
            result[i] = Self.atomicLoad(at: pointer.advanced(by: i), ordering: .relaxed)
        }
        return result
    }
}
