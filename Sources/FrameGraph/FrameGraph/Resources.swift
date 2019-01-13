//
//  Resources.swift
//  RenderAPI
//
//  Created by Joseph Bennett on 18/12/17.
//

import Utilities

public enum ResourceType : UInt8 {
    case buffer = 1
    case texture
    case sampler
    case threadgroupMemory
    case argumentBuffer
    case argumentBufferArray
    case imageblockData
    case imageblock
}

/*!
 @abstract Points at which a fence may be waited on or signaled.
 @constant RenderStageVertex   All vertex work prior to rasterization has completed.
 @constant RenderStageFragment All rendering work has completed.
 */
@_fixed_layout
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
    
    public var hashValue: Int {
        return Int(bitPattern: self.rawValue)
    }
}

@_fixed_layout
public struct ResourceFlags : OptionSet {
    public let rawValue: UInt8
    
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
    
    public static let persistent = ResourceFlags(rawValue: 1 << 0)
    public static let windowHandle = ResourceFlags(rawValue: 1 << 1)
    public static let historyBuffer = ResourceFlags(rawValue: 1 << 2)
    public static let immutableOnceInitialised = ResourceFlags(rawValue: 1 << 4)
}

@_fixed_layout
public struct ResourceStateFlags : OptionSet {
    public let rawValue: UInt16
    
    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }
    
    public static let initialised = ResourceStateFlags(rawValue: 1 << 0)
}

public enum ResourceAccessType {
    case read
    case write
    case readWrite
}

public protocol ResourceProtocol : Hashable {
    
    init(existingHandle: Handle)
    func dispose()
    
    var handle : Handle { get }
    var stateFlags : ResourceStateFlags { get nonmutating set }
    
    var usages : ResourceUsagesList { get }
    
    var label : String? { get nonmutating set }
    var storageMode : StorageMode { get }
    
    var readWaitFrame : UInt64 { get nonmutating set }
    var writeWaitFrame : UInt64 { get nonmutating set }
}

@_fixed_layout
public struct Resource : ResourceProtocol, Hashable {
    public let handle : Handle
    
    @inlinable
    public init<R : ResourceProtocol>(_ resource: R) {
        self.handle = resource.handle
    }
    
    @inlinable
    public init(existingHandle: Handle) {
        self.handle = existingHandle
    }
    
    @inlinable
    public var buffer : Buffer? {
        if self.type == .buffer {
            return Buffer(existingHandle: self.handle)
        } else {
            return nil
        }
    }
    
    @inlinable
    public var texture : Texture? {
        if self.type == .texture {
            return Texture(existingHandle: self.handle)
        } else {
            return nil
        }
    }
    
    @inlinable
    public var argumentBuffer : ArgumentBuffer? {
        if self.type == .argumentBuffer {
            return ArgumentBuffer(existingHandle: self.handle)
        } else {
            return nil
        }
    }
    
    @inlinable
    public var argumentBufferArray : ArgumentBufferArray? {
        if self.type == .argumentBufferArray {
            return ArgumentBufferArray(existingHandle: self.handle)
        } else {
            return nil
        }
    }
    
    @inlinable
    public var stateFlags: ResourceStateFlags {
        get {
            switch self.type {
            case .buffer:
                return Buffer(existingHandle: self.handle).stateFlags
            case .texture:
                return Texture(existingHandle: self.handle).stateFlags
            case .argumentBuffer:
                return ArgumentBuffer(existingHandle: self.handle).stateFlags
            case .argumentBufferArray:
                return ArgumentBufferArray(existingHandle: self.handle).stateFlags
            default:
                fatalError()
            }
        }
        nonmutating set {
            switch self.type {
            case .buffer:
                Buffer(existingHandle: self.handle).stateFlags = newValue
            case .texture:
                Texture(existingHandle: self.handle).stateFlags = newValue
            case .argumentBuffer:
                ArgumentBuffer(existingHandle: self.handle).stateFlags = newValue
            case .argumentBufferArray:
                ArgumentBufferArray(existingHandle: self.handle).stateFlags = newValue
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
                return Buffer(existingHandle: self.handle).storageMode
            case .texture:
                return Texture(existingHandle: self.handle).storageMode
            case .argumentBuffer:
                return ArgumentBuffer(existingHandle: self.handle).storageMode
            case .argumentBufferArray:
                return ArgumentBufferArray(existingHandle: self.handle).storageMode
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
                return Buffer(existingHandle: self.handle).label
            case .texture:
                return Texture(existingHandle: self.handle).label
            case .argumentBuffer:
                return ArgumentBuffer(existingHandle: self.handle).label
            case .argumentBufferArray:
                return ArgumentBufferArray(existingHandle: self.handle).label
            default:
                fatalError()
            }
        }
        nonmutating set {
            switch self.type {
            case .buffer:
                Buffer(existingHandle: self.handle).label = newValue
            case .texture:
                Texture(existingHandle: self.handle).label = newValue
            case .argumentBuffer:
                ArgumentBuffer(existingHandle: self.handle).label = newValue
            case .argumentBufferArray:
                ArgumentBufferArray(existingHandle: self.handle).label = newValue
            default:
                fatalError()
            }
        }
    }
    
    @inlinable
    public var readWaitFrame: UInt64 {
        get {
            switch self.type {
            case .buffer:
                return Buffer(existingHandle: self.handle).readWaitFrame
            case .texture:
                return Texture(existingHandle: self.handle).readWaitFrame
            default:
                return 0
            }
        }
        nonmutating set {
            switch self.type {
            case .buffer:
                Buffer(existingHandle: self.handle).readWaitFrame = newValue
            case .texture:
                Texture(existingHandle: self.handle).readWaitFrame = newValue
            default:
                break
            }
        }
    }
    
    @inlinable
    public var writeWaitFrame: UInt64 {
        get {
            switch self.type {
            case .buffer:
                return Buffer(existingHandle: self.handle).writeWaitFrame
            case .texture:
                return Texture(existingHandle: self.handle).writeWaitFrame
            default:
                return 0
            }
        }
        nonmutating set {
            switch self.type {
            case .buffer:
                Buffer(existingHandle: self.handle).writeWaitFrame = newValue
            case .texture:
                Texture(existingHandle: self.handle).writeWaitFrame = newValue
            default:
                break
            }
        }
    }
    
    @inlinable
    public var usages: ResourceUsagesList {
        get {
            switch self.type {
            case .buffer:
                return Buffer(existingHandle: self.handle).usages
            case .texture:
                return Texture(existingHandle: self.handle).usages
            default:
                return ResourceUsagesList()
            }
        }
    }
    
    @inlinable
    internal var usagesPointer: UnsafeMutablePointer<ResourceUsagesList> {
        get {
            switch self.type {
            case .buffer:
                return Buffer(existingHandle: self.handle).usagesPointer
            case .texture:
                return Texture(existingHandle: self.handle).usagesPointer
            default:
                fatalError()
            }
        }
    }
    
    @inlinable
    public func dispose() {
        switch self.type {
        case .buffer:
            Buffer(existingHandle: self.handle).dispose()
        case .texture:
            Texture(existingHandle: self.handle).dispose()
        case .argumentBuffer:
            ArgumentBuffer(existingHandle: self.handle).dispose()
        case .argumentBufferArray:
            ArgumentBufferArray(existingHandle: self.handle).dispose()
        default:
            break
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
    public var type : ResourceType {
        return ResourceType(rawValue: ResourceType.RawValue(truncatingIfNeeded: self.handle >> 48)).unsafelyUnwrapped
    }
    
    @inlinable
    public var index : Int {
        return Int(truncatingIfNeeded: self.handle & 0x1FFFFFFF) // The lower 29 bits contain the index
    }
    
    @inlinable
    public var flags : ResourceFlags {
        return ResourceFlags(rawValue: ResourceFlags.RawValue(truncatingIfNeeded: (self.handle >> 32) & 0xFFFF))
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
    public var readWaitFrame : UInt64 {
        get {
            return Resource(existingHandle: self.handle).readWaitFrame
        }
        nonmutating set {
             Resource(existingHandle: self.handle).readWaitFrame = newValue
        }
    }
    
    @inlinable
    public var writeWaitFrame : UInt64 {
        get {
            return Resource(existingHandle: self.handle).writeWaitFrame
        }
        nonmutating set {
            Resource(existingHandle: self.handle).writeWaitFrame = newValue
        }
    }
    
    @inlinable
    public var usages : ResourceUsagesList {
        get {
            return Resource(existingHandle: self.handle).usages
        }
    }

    @inlinable
    internal var usagesPointer : UnsafeMutablePointer<ResourceUsagesList> {
        get {
            return Resource(existingHandle: self.handle).usagesPointer
        }
    }
    
    @inlinable
    public var label : String? {
        get {
            return Resource(existingHandle: self.handle).label
        }
        nonmutating set {
            Resource(existingHandle: self.handle).label = newValue
        }
    }
    
    @inlinable
    public var storageMode : StorageMode {
        get {
            return Resource(existingHandle: self.handle).storageMode
        }
    }
}

@_fixed_layout
public struct Buffer : ResourceProtocol {
    public let handle : Handle
    
    @inlinable
    public init(existingHandle: Handle) {
        self.handle = existingHandle
    }
    
    @inlinable
    public init(length: Int, storageMode: StorageMode = .managed, cacheMode: CPUCacheMode = .defaultCache, usage: BufferUsage = .unknown, bytes: UnsafeRawPointer? = nil, flags: ResourceFlags = []) {
        self.init(descriptor: BufferDescriptor(length: length, storageMode: storageMode, cacheMode: cacheMode, usage: usage), bytes: bytes, flags: flags)
    }
    
    @inlinable
    public init(descriptor: BufferDescriptor, flags: ResourceFlags = []) {
        let index : UInt64
        if flags.contains(.persistent) || flags.contains(.historyBuffer) {
            index = PersistentBufferRegistry.instance.allocate(descriptor: descriptor, flags: flags)
        } else {
            index = TransientBufferRegistry.instance.allocate(descriptor: descriptor, flags: flags)
        }
        
        self.handle = index | (UInt64(flags.rawValue) << 32) | (UInt64(ResourceType.buffer.rawValue) << 48)
        
        if self.flags.contains(.persistent) {
            assert(!descriptor.usageHint.isEmpty, "Persistent resources must explicitly specify their usage.")
            RenderBackend.materialisePersistentBuffer(self)
        }
    }
    
    @inlinable
    public init(descriptor: BufferDescriptor, bytes: UnsafeRawPointer? = nil, flags: ResourceFlags = []) {
        self.init(descriptor: descriptor, flags: flags)
        
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
    public subscript<T>(byteRange range: Range<Int>, as type: T.Type) -> BufferSlice<T> {
        return self[byteRange: range, as: type, accessType: .readWrite]
    }
    
    @inlinable
    public subscript<T>(byteRange range: Range<Int>, as type: T.Type, accessType accessType: ResourceAccessType) -> BufferSlice<T> {
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
    
    public func onMaterialiseGPUBacking(perform: @escaping (Buffer) -> Void) {
        if self.flags.contains(.persistent) {
            perform(self)
        } else {
            self._deferredSliceActions.append(EmptyBufferSlice(closure: perform))
        }
    }
    
    public func applyDeferredSliceActions() {
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
            return PersistentBufferRegistry.instance.stateFlags[self.index]
        }
        nonmutating set {
            if self.flags.intersection([.historyBuffer, .persistent]) == [] { return }
            
            PersistentBufferRegistry.instance.stateFlags[self.index] = newValue
        }
    }
    
    @inlinable
    public var descriptor : BufferDescriptor {
        get {
            let index = self.index
            if self._usesPersistentRegistry {
                return PersistentBufferRegistry.instance.descriptors[index]
            } else {
                return TransientBufferRegistry.instance.descriptors[index]
            }
        }
        nonmutating set {
            let index = self.index
            if self._usesPersistentRegistry {
                PersistentBufferRegistry.instance.descriptors[index] = newValue
            } else {
                TransientBufferRegistry.instance.descriptors[index] = newValue
            }
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
                return PersistentBufferRegistry.instance.labels[index]
            } else {
                return TransientBufferRegistry.instance.labels[index]
            }
        }
        nonmutating set {
            let index = self.index
            if self._usesPersistentRegistry {
                PersistentBufferRegistry.instance.labels[index] = newValue
            } else {
                TransientBufferRegistry.instance.labels[index] = newValue
            }
        }
    }
    
    @inlinable
    public var _deferredSliceActions : [DeferredBufferSlice] {
        get {
            assert(!self._usesPersistentRegistry)
            
            return TransientBufferRegistry.instance.deferredSliceActions[self.index]
    
        }
        nonmutating set {
            assert(!self._usesPersistentRegistry)
            
            TransientBufferRegistry.instance.deferredSliceActions[self.index] = newValue
        }
    }
    
    @inlinable
    public var readWaitFrame: UInt64 {
        get {
            guard self.flags.contains(.persistent) else { return 0 }
            return PersistentBufferRegistry.instance.readWaitFrames[self.index]
        }
        nonmutating set {
            guard self.flags.contains(.persistent) else { return }
            PersistentBufferRegistry.instance.readWaitFrames[self.index] = newValue
        }
    }
    
    @inlinable
    public var writeWaitFrame: UInt64 {
        get {
            guard self.flags.contains(.persistent) else { return 0 }
            return PersistentBufferRegistry.instance.writeWaitFrames[self.index]
        }
        nonmutating set {
            guard self.flags.contains(.persistent) else { return }
            PersistentBufferRegistry.instance.writeWaitFrames[self.index] = newValue
        }
    }
    
    @inlinable
    public func waitForCPUAccess(accessType: ResourceAccessType) {
        guard self.flags.contains(.persistent) else { return }
        
        let readWaitFrame = PersistentBufferRegistry.instance.readWaitFrames[self.index]
        let writeWaitFrame = PersistentBufferRegistry.instance.readWaitFrames[self.index]
        switch accessType {
        case .read:
            FrameCompletion.waitForFrame(readWaitFrame)
        case .write:
            FrameCompletion.waitForFrame(writeWaitFrame)
        case .readWrite:
            FrameCompletion.waitForFrame(max(readWaitFrame, writeWaitFrame))
        }
    }
    
    @inlinable
    public var usages : ResourceUsagesList {
        get {
            let index = self.index
            if self._usesPersistentRegistry {
                return PersistentBufferRegistry.instance.usages[index]
            } else {
                return TransientBufferRegistry.instance.usages[index]
            }
        }
    }
    
    @inlinable
    var usagesPointer : UnsafeMutablePointer<ResourceUsagesList> {
        get {
            let index = self.index
            if self._usesPersistentRegistry {
                return PersistentBufferRegistry.instance.usages.advanced(by: index)
            } else {
                return TransientBufferRegistry.instance.usages.advanced(by: index)
            }
        }
    }
    
    @inlinable
    public func dispose() {
        guard self._usesPersistentRegistry else {
            return
        }
        PersistentBufferRegistry.instance.dispose(self)
    }
}

@_fixed_layout
public struct Texture : ResourceProtocol {
    public let handle : Handle
    
    @inlinable
    public init(existingHandle: Handle) {
        self.handle = existingHandle
    }
    
    @inlinable
    public init(descriptor: TextureDescriptor, flags: ResourceFlags = []) {
        let index : UInt64
        if flags.contains(.persistent) || flags.contains(.historyBuffer) {
            index = PersistentTextureRegistry.instance.allocate(descriptor: descriptor, flags: flags)
        } else {
            index = TransientTextureRegistry.instance.allocate(descriptor: descriptor, flags: flags)
        }
        
        self.handle = index | (UInt64(flags.rawValue) << 32) | (UInt64(ResourceType.texture.rawValue) << 48)
        
        if self.flags.contains(.persistent) {
            assert(!descriptor.usageHint.isEmpty, "Persistent resources must explicitly specify their usage.")
            RenderBackend.materialisePersistentTexture(self)
        }
    }
    
    @inlinable
    public init(windowId: Int, descriptor: TextureDescriptor, isMinimised: Bool, nativeWindow: Any) {
        self.init(descriptor: descriptor, flags: isMinimised ? [] : .windowHandle)
        
        if !isMinimised {
            RenderBackend.registerWindowTexture(texture: self, context: nativeWindow)
        }
    }
    
    @inlinable
    public func replace(region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) {
        self.waitForCPUAccess(accessType: .write)
        
        RenderBackend.replaceTextureRegion(texture: self, region: region, mipmapLevel: mipmapLevel, withBytes: bytes, bytesPerRow: bytesPerRow)
    }
    
    @inlinable
    public var flags : ResourceFlags {
        return ResourceFlags(rawValue: ResourceFlags.RawValue(truncatingIfNeeded: (self.handle >> 32) & 0xFFFF))
    }
    
    @inlinable
    public var stateFlags: ResourceStateFlags {
        get {
            if self.flags.intersection([.historyBuffer, .persistent]) == [] {
                return []
            }
            return PersistentTextureRegistry.instance.stateFlags[self.index]
        }
        nonmutating set {
            assert(self.flags.intersection([.historyBuffer, .persistent]) != [], "State flags can only be set on persistent resources.")
            
            PersistentTextureRegistry.instance.stateFlags[self.index] = newValue
        }
    }
    
    @inlinable
    public var storageMode: StorageMode {
        return self.descriptor.storageMode
    }
    
    @inlinable
    public var descriptor : TextureDescriptor {
        get {
            let index = self.index
            if self._usesPersistentRegistry {
                return PersistentTextureRegistry.instance.descriptors[index]
            } else {
                return TransientTextureRegistry.instance.descriptors[index]
            }
        }
        nonmutating set {
            let index = self.index
            if self._usesPersistentRegistry {
                PersistentTextureRegistry.instance.descriptors[index] = newValue
            } else {
                TransientTextureRegistry.instance.descriptors[index] = newValue
            }
        }
    }
    
    @inlinable
    public var label : String? {
        get {
            let index = self.index
            if self._usesPersistentRegistry {
                return PersistentTextureRegistry.instance.labels[index]
            } else {
                return TransientTextureRegistry.instance.labels[index]
            }
        }
        nonmutating set {
            let index = self.index
            if self._usesPersistentRegistry {
                PersistentTextureRegistry.instance.labels[index] = newValue
            } else {
                TransientTextureRegistry.instance.labels[index] = newValue
            }
        }
    }
    
    @inlinable
    public var readWaitFrame: UInt64 {
        get {
            guard self.flags.contains(.persistent) else { return 0 }
            return PersistentTextureRegistry.instance.readWaitFrames[self.index]
        }
        nonmutating set {
            guard self.flags.contains(.persistent) else { return }
            PersistentTextureRegistry.instance.readWaitFrames[self.index] = newValue
        }
    }
    
    @inlinable
    public var writeWaitFrame: UInt64 {
        get {
            guard self.flags.contains(.persistent) else { return 0 }
            return PersistentTextureRegistry.instance.writeWaitFrames[self.index]
        }
        nonmutating set {
            guard self.flags.contains(.persistent) else { return }
            PersistentTextureRegistry.instance.writeWaitFrames[self.index] = newValue
        }
    }
    
    @inlinable
    public func waitForCPUAccess(accessType: ResourceAccessType) {
        guard self.flags.contains(.persistent) else { return }
        
        let readWaitFrame = PersistentTextureRegistry.instance.readWaitFrames[self.index]
        let writeWaitFrame = PersistentTextureRegistry.instance.readWaitFrames[self.index]
        switch accessType {
        case .read:
            FrameCompletion.waitForFrame(readWaitFrame)
        case .write:
            FrameCompletion.waitForFrame(writeWaitFrame)
        case .readWrite:
            FrameCompletion.waitForFrame(max(readWaitFrame, writeWaitFrame))
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
    public var usages : ResourceUsagesList {
        get {
            let index = self.index
            if self._usesPersistentRegistry {
                return PersistentTextureRegistry.instance.usages[index]
            } else {
                return TransientTextureRegistry.instance.usages[index]
            }
        }
    }
    
    @inlinable
    var usagesPointer: UnsafeMutablePointer<ResourceUsagesList> {
        get {
            let index = self.index
            if self._usesPersistentRegistry {
                return PersistentTextureRegistry.instance.usages.advanced(by: index)
            } else {
                return TransientTextureRegistry.instance.usages.advanced(by: index)
            }
        }
    }
    
    @inlinable
    public func dispose() {
        guard self._usesPersistentRegistry else {
            return
        }
        PersistentTextureRegistry.instance.dispose(self)
    }
    
    public static let invalid = Texture(descriptor: TextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: 1, height: 1, mipmapped: false, usageHint: .shaderRead), flags: .persistent)
    
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

@_fixed_layout
public final class RawBufferSlice {
    public let buffer : Buffer
    public private(set) var range : Range<Int>
    
    @usableFromInline
    let contents : UnsafeMutableRawPointer
    
    @usableFromInline
    let accessType : ResourceAccessType
    
    var writtenToGPU = false
    
    @inlinable
    internal init(buffer: Buffer, range: Range<Int>, accessType: ResourceAccessType) {
        self.buffer = buffer
        self.range = range
        self.contents = RenderBackend.bufferContents(for: self.buffer, range: self.range)
        self.accessType = accessType
    }
    
    @inlinable
    public func withContents<A>(_ perform: (UnsafeMutableRawPointer) throws -> A) rethrows -> A {
        return try perform(self.contents)
    }
    
    public func setBytesWrittenCount(_ bytesAccessed: Int) {
        assert(bytesAccessed <= self.range.count)
        self.range = self.range.lowerBound..<(self.range.lowerBound + bytesAccessed)
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

@_fixed_layout
public final class BufferSlice<T> {
    public let buffer : Buffer
    public private(set) var range : Range<Int>
    @usableFromInline
    let contents : UnsafeMutablePointer<T>
    @usableFromInline
    let accessType : ResourceAccessType
    
    var writtenToGPU = false
    
    @inlinable
    internal init(buffer: Buffer, range: Range<Int>, accessType: ResourceAccessType) {
        self.buffer = buffer
        self.range = range
        self.contents = RenderBackend.bufferContents(for: self.buffer, range: self.range).assumingMemoryBound(to: T.self)
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
    public func withContents<A>(_ perform: (UnsafeMutablePointer<T>) throws -> A) rethrows -> A {
        return try perform(self.contents)
    }
    
    public func setElementsWrittenCount(_ elementsAccessed: Int) {
        assert(self.accessType != .read)
        
        let bytesAccessed = elementsAccessed * MemoryLayout<T>.stride
        assert(bytesAccessed <= self.range.count)
        self.range = self.range.lowerBound..<(self.range.lowerBound + bytesAccessed)
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
