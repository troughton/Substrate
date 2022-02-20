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
    case hazardTrackingGroup
    
    public var isMaterialisedOnFirstUse: Bool {
        switch self {
        case .argumentBuffer, .argumentBufferArray, .visibleFunctionTable, .intersectionFunctionTable:
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
    var usages: ChunkArray<ResourceUsage> { get nonmutating set }
    var resourceForUsageTracking: Resource { get }
    
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

public protocol GroupHazardTrackableResource: ResourceProtocol {
    var hazardTrackingGroup: HazardTrackingGroup<Self>? { get nonmutating set }
}

protocol ResourceProtocolImpl: GroupHazardTrackableResource, Hashable, CustomHashable {
    associatedtype Descriptor
    associatedtype SharedProperties: SharedResourceProperties where SharedProperties.Descriptor == Descriptor
    associatedtype TransientProperties: ResourceProperties where TransientProperties.Descriptor == Descriptor
    associatedtype PersistentProperties: PersistentResourceProperties where PersistentProperties.Descriptor == Descriptor
    
    associatedtype TransientRegistry: Substrate.TransientRegistry where TransientRegistry.Resource == Self
    typealias PersistentRegistry = Substrate.PersistentRegistry<Self>
    
    static var itemsPerChunk: Int { get }
    
    static func transientRegistry(index: Int) -> TransientRegistry?
    static var persistentRegistry: PersistentRegistry { get }
}

extension ResourceProtocolImpl {
    static var itemsPerChunk: Int { 256 }
    
    @inlinable
    public init?(_ resource: Resource) {
        guard Self.resourceType == resource.type else { return nil }
        self.init(handle: resource.handle)
    }
    
    @inlinable
    public var customHashValue : Int {
        return Int(truncatingIfNeeded: self.handle)
    }
    
    public func dispose() {
        guard self._usesPersistentRegistry, self.isValid else {
            return
        }
        self.heap?.childResources.remove(Resource(self))
        Self.persistentRegistry.dispose(self)
    }
    
    @_transparent
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
        return Self.persistentRegistry.persistentChunks?[chunkIndex][keyPath: keyPath].advanced(by: indexInChunk)
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
            return Self.persistentRegistry.hazardTrackingGroupChunks[chunkIndex][indexInChunk]
        }
        nonmutating set {
            guard let newValue = newValue else {
                precondition(self.hazardTrackingGroup == nil, "Cannot remove a resource from a hazard tracking group after it has been added to it.")
                return
            }
            precondition(self.flags.contains(.persistent), "Hazard tracking groups can only be set on persistent resources.")
            
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: Self.itemsPerChunk)
            newValue.resources.insert(self)
            Self.persistentRegistry.hazardTrackingGroupChunks[chunkIndex][indexInChunk] = newValue
        }
    }
    
    @inlinable
    var _usagesPointer: UnsafeMutablePointer<ChunkArray<ResourceUsage>>? {
        if self._usesPersistentRegistry {
            if let hazardTrackingGroup = self.hazardTrackingGroup {
                return hazardTrackingGroup.group._usagesPointer
            }
            
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: Self.itemsPerChunk)
            return Self.persistentRegistry.sharedChunks?[chunkIndex].usagesOptional?.advanced(by: indexInChunk)
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
    
    @_transparent
    var _activeRenderGraphsPointer: UnsafeMutablePointer<UInt8.AtomicRepresentation>? {
        if self._usesPersistentRegistry {
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: Self.itemsPerChunk)
            return Self.persistentRegistry.persistentChunks?[chunkIndex].activeRenderGraphsOptional?.advanced(by: indexInChunk)
        } else {
            return nil
        }
    }
    
    
    @_transparent
    var _readWaitIndicesPointer: UnsafeMutablePointer<QueueCommandIndices>? {
        if self._usesPersistentRegistry {
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: Self.itemsPerChunk)
            return Self.persistentRegistry.persistentChunks?[chunkIndex].readWaitIndicesOptional?.advanced(by: indexInChunk)
        } else {
            return nil
        }
    }
    
    @_transparent
    var _writeWaitIndicesPointer: UnsafeMutablePointer<QueueCommandIndices>? {
        if self._usesPersistentRegistry {
            let (chunkIndex, indexInChunk) = self.index.quotientAndRemainder(dividingBy: Self.itemsPerChunk)
            return Self.persistentRegistry.persistentChunks?[chunkIndex].writeWaitIndicesOptional?.advanced(by: indexInChunk)
        } else {
            return nil
        }
    }
    
    public subscript(waitIndexFor queue: Queue, accessType type: ResourceAccessType) -> UInt64 {
        get {
            guard self._usesPersistentRegistry else { return 0 }
            if type == .read {
                return self._readWaitIndicesPointer?.pointee[Int(queue.index)] ?? 0
            } else {
                return self._writeWaitIndicesPointer?.pointee[Int(queue.index)] ?? 0
            }
        }
        nonmutating set {
            guard self._usesPersistentRegistry else { return }
            
            if type == .read || type == .readWrite {
                self._readWaitIndicesPointer?.pointee[Int(queue.index)] = newValue
            }
            if type == .write || type == .readWrite {
                self._writeWaitIndicesPointer?.pointee[Int(queue.index)] = newValue
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
            return Self.persistentRegistry.labelChunks[chunkIndex].advanced(by: indexInChunk)
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

public struct Resource : ResourceProtocol, Hashable {
    public static var resourceType: ResourceType { fatalError() }

    @usableFromInline let _handle : UnsafeRawPointer
    @inlinable public var handle : Handle { return UInt64(UInt(bitPattern: _handle)) }
    
    public init<R : ResourceProtocol>(_ resource: R) {
        self._handle = UnsafeRawPointer(bitPattern: UInt(resource.handle))!
    }
    
    public init(handle: Handle) {
        assert(ResourceType(rawValue: ResourceType.RawValue(truncatingIfNeeded: handle.bits(in: Self.typeBitsRange))) != nil)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
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
    func withUnderlyingResource<R>(_ perform: (ResourceProtocol) -> R) -> R {
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
    
    public var usages: ChunkArray<ResourceUsage> {
        get {
            self[\.usages]
        }
        nonmutating set {
            self[\.usages] = newValue
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
        case .argumentBufferArray:
            return ArgumentBufferArray(handle: self.handle).description
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
            _ = newValue
        }
    }
    
    
    public func checkHasCPUAccess(accessType: ResourceAccessType) {
        guard self.flags.contains(.persistent) else { return }
        
        for queue in QueueRegistry.allQueues {
            let waitIndex = self[waitIndexFor: queue, accessType: accessType]
            precondition(queue.lastCompletedCommand >= waitIndex, "Resource \(self) is not accessible by the CPU for access type: \(accessType); use withContentsAsync or withMutableContentsAsync instead.")
        }
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
