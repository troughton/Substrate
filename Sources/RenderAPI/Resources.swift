//
//  Resources.swift
//  RenderAPI
//
//  Created by Joseph Bennett on 18/12/17.
//


public enum ResourceType {
    case buffer
    case texture
    case sampler
    case threadgroupMemory
}

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

public struct ResourceFlags : OptionSet {
    public let rawValue: UInt16
    
    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }
    
    public static let persistent = ResourceFlags(rawValue: 1 << 0)
    public static let windowHandle = ResourceFlags(rawValue: 1 << 1)
    
    public static let historyBuffer = ResourceFlags(rawValue: 1 << 2)

    public static let initialised = ResourceFlags(rawValue: 1 << 3)
}

public class Resource : Hashable {
    public typealias Handle = ObjectIdentifier
    
    public var label : String? = nil
    public internal(set) var flags : ResourceFlags
    
    init(flags: ResourceFlags) {
        self.flags = flags
    }
    
    public var hashValue: Int {
        return ObjectIdentifier(self).hashValue
    }
    
    public static func ==(lhs: Resource, rhs: Resource) -> Bool {
        return lhs === rhs
    }

    public func markAsInitialised() {
        self.flags.formUnion(.initialised)
    }
    
    public var handle : ObjectIdentifier {
        return ObjectIdentifier(self)
    }
}

public final class Texture : Resource {
    public private(set) var descriptor : TextureDescriptor
    
    public init(descriptor: TextureDescriptor, flags: ResourceFlags = []) {
        self.descriptor = descriptor
        super.init(flags: flags)
        
        if self.flags.contains(.persistent) {
            assert(!descriptor.usageHint.isEmpty, "Persistent resources must explicitly specify their usage.")
            RenderBackend.materialisePersistentTexture(self)
        }
    }
    
    public init(windowId: Int, descriptor: TextureDescriptor, isMinimised: Bool, nativeWindow: Any) {
        self.descriptor = descriptor
        super.init(flags: isMinimised ? [] : [.windowHandle])
        
        if !isMinimised {
            RenderBackend.registerWindowTexture(texture: self, context: nativeWindow)
        }
    }
    
    public func replace(region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) {
        RenderBackend.replaceTextureRegion(texture: self, region: region, mipmapLevel: mipmapLevel, withBytes: bytes, bytesPerRow: bytesPerRow)
    }
        
    public func makeHistoryBuffer(usageHint: TextureUsage) {
        assert(!self.flags.contains(.persistent))
        self.flags.formUnion(.historyBuffer)
        
        self.descriptor.usageHint.formUnion(usageHint)
    }
    
    deinit {
        if self.flags.contains(.persistent) || self.flags.contains([.historyBuffer, .initialised]) {
            RenderBackend.dispose(texture: self)
        }
    }
    
    public var type : ResourceType {
        return .texture
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
    
    public static func ==(lhs: Texture, rhs: Texture) -> Bool {
        return lhs === rhs
    }
}

private protocol DeferredBufferSlice {
    func apply(_ buffer: Buffer)
}

private final class DeferredRawBufferSlice : DeferredBufferSlice {
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

private final class DeferredTypedBufferSlice<T> : DeferredBufferSlice {
    let range : Range<Int>
    let closure : (BufferSlice<T>) -> Void
    
    init(range: Range<Int>, closure: @escaping (BufferSlice<T>) -> Void) {
        self.range = range
        self.closure = closure
    }
    
    func apply(_ buffer: Buffer) {
        self.closure(buffer[self.range])
    }
}

private final class EmptyBufferSlice : DeferredBufferSlice {
    let closure : (Buffer) -> Void
    
    init(closure: @escaping (Buffer) -> Void) {
        self.closure = closure
    }
    
    func apply(_ buffer: Buffer) {
        self.closure(buffer)
    }
}


public final class Buffer : Resource {
    public private(set) var descriptor : BufferDescriptor
    private var deferredSliceActions : [DeferredBufferSlice] = []

    public convenience init(length: Int, bytes: UnsafeRawPointer, flags: ResourceFlags = []) {
        self.init(descriptor: BufferDescriptor(length: length), bytes: bytes, flags: flags)
    }
    
    public init(descriptor: BufferDescriptor, flags: ResourceFlags = []) {
        self.descriptor = descriptor
        super.init(flags: flags)
        
        if self.flags.contains(.persistent) {
            assert(!descriptor.usageHint.isEmpty, "Persistent resources must explicitly specify their usage.")
            RenderBackend.materialisePersistentBuffer(self)
        }
    }
    
    public convenience init(descriptor: BufferDescriptor, bytes: UnsafeRawPointer, flags: ResourceFlags = []) {
        self.init(descriptor: descriptor, flags: flags)
        
        assert(self.descriptor.storageMode != .private)
        
        self[0..<self.descriptor.length].contents.copyMemory(from: bytes, byteCount: self.descriptor.length)
    }
    
    public subscript(range: Range<Int>) -> RawBufferSlice {
        return RawBufferSlice(buffer: self, range: range)
    }
    
    public func withDeferredSlice(range: Range<Int>, perform: @escaping (RawBufferSlice) -> Void) {
        if self.flags.contains(.persistent) {
            perform(self[range])
        } else {
            self.deferredSliceActions.append(DeferredRawBufferSlice(range: range, closure: perform))
        }
    }
    
    public subscript<T>(range: Range<Int>) -> BufferSlice<T> {
        return BufferSlice(buffer: self, range: range)
    }
    
    public func withDeferredSlice<T>(range: Range<Int>, perform: @escaping (BufferSlice<T>) -> Void) {
        if self.flags.contains(.persistent) {
            perform(self[range])
        } else {
            self.deferredSliceActions.append(DeferredTypedBufferSlice(range: range, closure: perform))
        }
    }
    
    public func onMaterialiseGPUBacking(perform: @escaping (Buffer) -> Void) {
        if self.flags.contains(.persistent) {
            perform(self)
        } else {
            self.deferredSliceActions.append(EmptyBufferSlice(closure: perform))
        }
    }

    public func applyDeferredSliceActions() {
        for action in self.deferredSliceActions {
            action.apply(self)
        }
        self.deferredSliceActions.removeAll(keepingCapacity: true)
    }
    
    public var range : Range<Int> {
        return 0..<self.descriptor.length
    }

        
    public func makeHistoryBuffer(usageHint: BufferUsage) {
        assert(!self.flags.contains(.persistent))
        self.flags.formUnion(.historyBuffer)

        self.descriptor.usageHint.formUnion(usageHint)
    }
    
    deinit {
        if self.flags.contains(.persistent)  || self.flags.contains([.historyBuffer, .initialised]) {
            RenderBackend.dispose(buffer: self)
        }
    }
    
    @inlinable
    public var type : ResourceType {
        return .buffer
    }
    
    public static func ==(lhs: Buffer, rhs: Buffer) -> Bool {
        return lhs === rhs
    }
}

public final class RawBufferSlice {
    public let buffer : Buffer
    public private(set) var range : Range<Int>
    public let contents : UnsafeMutableRawPointer
    
    internal init(buffer: Buffer, range: Range<Int>) {
        self.buffer = buffer
        self.range = range
        self.contents = RenderBackend.bufferContents(for: self.buffer, range: self.range)
    }
    
    public func setBytesWrittenCount(_ bytesAccessed: Int) {
        assert(bytesAccessed <= self.range.count)
        self.range = self.range.lowerBound..<(self.range.lowerBound + bytesAccessed)
    }
    
    deinit {
        RenderBackend.buffer(self.buffer, didModifyRange: self.range)
    }
}

public final class BufferSlice<T> {
    public let buffer : Buffer
    public private(set) var range : Range<Int>
    public let contents : UnsafeMutablePointer<T>
    
    internal init(buffer: Buffer, range: Range<Int>) {
        self.buffer = buffer
        self.range = range
        self.contents = RenderBackend.bufferContents(for: self.buffer, range: self.range).assumingMemoryBound(to: T.self)
    }
    
    @inlinable
    public subscript(index: Int) -> T {
        get {
            return self.contents[index]
        }
        set {
            self.contents[index] = newValue
        }
    }
    
    public func setElementsWrittenCount(_ elementsAccessed: Int) {
        let bytesAccessed = elementsAccessed * MemoryLayout<T>.size
        assert(bytesAccessed <= self.range.count)
        self.range = self.range.lowerBound..<(self.range.lowerBound + bytesAccessed)
    }
    
    deinit {
        RenderBackend.buffer(self.buffer, didModifyRange: self.range)
    }
}
