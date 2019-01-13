//
//  ResourceRegistry.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 23/12/17.
//

import SwiftFrameGraph
import Metal
import MetalKit
import Utilities

final class MTLFenceHolder {
    static var fenceIndex = 0
    
    let fence : MTLFence
    let index : Int
    
    init(fence: MTLFence) {
        self.fence = fence
        
        self.index = MTLFenceHolder.fenceIndex
        MTLFenceHolder.fenceIndex += 1
    }
    
    deinit {
        print("This shouldn't happen!")
    }
}

typealias MTLFenceType = MTLFence // MTLFenceHolder for debugging.

extension MTLFence {
    var fence : MTLFence {
        return self
    }
}

struct ResourceFences {
    /// The fences to wait on before reading from the resource.
    var readWaitFences : [MTLFenceType] = []
    
    /// The fences to wait on before writing to the resource.
    var writeWaitFences : [MTLFenceType] = []
}

protocol MTLResourceReference {
    associatedtype Resource : MTLResource
    
    var resource : Resource { get }
    
    /// The fences to wait on before using this resource.
    var usageFences : ResourceFences { get set }
    
    /// The fences that anything that uses the resource after should wait on.
    var disposalFences : ResourceFences { get set }
    
    /// Set by setDisposalFences to indicate the resource was used and should cycle fences this frame.
    var usedThisFrame : Bool { get set }
}

extension MTLResourceReference {
    mutating func setUsageFencesToDisposalFences() {
        defer { self.usedThisFrame = false }
        
        guard self.usedThisFrame else {
            return // The resource hasn't been used this frame. Leave the fences around for the next frame.
        }
        
        self.usageFences.readWaitFences.removeAll(keepingCapacity: true)
        self.usageFences.writeWaitFences.removeAll(keepingCapacity: true)
        
        let oldUsageFences = self.usageFences
        self.usageFences = self.disposalFences
        
        self.disposalFences = oldUsageFences
    }
}

struct MTLBufferReference : MTLResourceReference {
    let buffer : MTLBuffer
    let offset : Int
    var usedThisFrame: Bool = false
    
    var resource : MTLBuffer {
        return self.buffer
    }
    
    /// The fences to wait on before using this resource.
    var usageFences = ResourceFences()
    /// The fences that anything that uses the resource after should wait on.
    var disposalFences = ResourceFences()
    
    init(buffer: MTLBuffer, offset: Int) {
        self.buffer = buffer
        self.offset = offset
    }
}

struct MTLTextureReference : MTLResourceReference {
    var _texture : MTLTexture!
    var usedThisFrame: Bool = false
    
    var texture : MTLTexture {
        return _texture
    }
    
    var resource : MTLTexture {
        return self.texture
    }
    
    /// The fences to wait on before using this resource.
    var usageFences = ResourceFences()
    /// The fences that anything that uses the resource after should wait on.
    var disposalFences = ResourceFences()
    
    init(windowTexture: ()) {
        self._texture = nil
    }
    
    init(texture: MTLTexture) {
        self._texture = texture
    }
}

final class ResourceRegistry {
    
    let accessQueue = DispatchQueue(label: "Resource Registry Access")
    
    private var textureReferences = HashMap<ResourceProtocol.Handle, MTLTextureReference>()
    private var bufferReferences = HashMap<ResourceProtocol.Handle, MTLBufferReference>()
    private var argumentBufferReferences = HashMap<ResourceProtocol.Handle, MTLBufferReference>() // Separate since this needs to have thread-safe access.
    
    private var windowReferences = [ResourceProtocol.Handle : MTKView]()
    
    private var frameEndUnusedFences = [MTLFenceType]()
    private var unusedFences = [MTLFenceType]()
    private var fenceRetainCounts = [ObjectIdentifier : Int]()
    
    private let device : MTLDevice
    
    private let frameSharedBufferAllocator : TemporaryBufferAllocator
    private let frameSharedWriteCombinedBufferAllocator : TemporaryBufferAllocator
    
    #if os(macOS)
    private let frameManagedBufferAllocator : TemporaryBufferAllocator
    private let frameManagedWriteCombinedBufferAllocator : TemporaryBufferAllocator
    #endif
    
    #if os(iOS)
    private let memorylessTextureAllocator : PoolResourceAllocator
    #endif
    
    private let frameArgumentBufferAllocator : TemporaryBufferAllocator
    
    private let stagingTextureAllocator : PoolResourceAllocator
    private let privateAllocator : SingleFrameHeapResourceAllocator
    
    // A double-buffered allocator for small per-frame private resources.
    private let smallPrivateAllocator : MultiFrameHeapResourceAllocator
    private let smallAllocationThreshold = 2 * 1024 * 1024 // 2MB
    
    private let colorRenderTargetAllocator : SingleFrameHeapResourceAllocator
    private let depthRenderTargetAllocator : SingleFrameHeapResourceAllocator
    
    private let historyBufferAllocator : PoolResourceAllocator
    private let persistentAllocator : PersistentResourceAllocator
    
    public private(set) var frameDrawables : [CAMetalDrawable] = []
    
    public var frameGraphHasResourceAccess = false
    
    public init(device: MTLDevice, numInflightFrames: Int) {
        self.device = device
        
        self.stagingTextureAllocator = PoolResourceAllocator(device: device, numFrames: numInflightFrames)
        self.historyBufferAllocator = PoolResourceAllocator(device: device, numFrames: 1)
        
        self.persistentAllocator = PersistentResourceAllocator(device: device)
        
        self.frameSharedBufferAllocator = TemporaryBufferAllocator(device: device, numFrames: numInflightFrames, blockSize: 256 * 1024, options: .storageModeShared)
        self.frameSharedWriteCombinedBufferAllocator = TemporaryBufferAllocator(device: device, numFrames: numInflightFrames, blockSize: 2 * 1024 * 1024, options: [.storageModeShared, .cpuCacheModeWriteCombined])
        
        #if os(macOS)
        self.frameManagedBufferAllocator = TemporaryBufferAllocator(device: device, numFrames: numInflightFrames, blockSize: 1024 * 1024, options: .storageModeManaged)
        self.frameManagedWriteCombinedBufferAllocator = TemporaryBufferAllocator(device: device, numFrames: numInflightFrames, blockSize: 2 * 1024 * 1024, options: [.storageModeManaged, .cpuCacheModeWriteCombined])
        self.frameArgumentBufferAllocator = TemporaryBufferAllocator(device: device, numFrames: numInflightFrames, blockSize: 2 * 1024 * 1024, options: [.storageModeManaged, .cpuCacheModeWriteCombined])
        #else
        self.frameArgumentBufferAllocator = TemporaryBufferAllocator(device: device, numFrames: numInflightFrames, blockSize: 2 * 1024 * 1024, options: [.storageModeShared, .cpuCacheModeWriteCombined])
        self.memorylessTextureAllocator = PoolResourceAllocator(device: device, numFrames: 1)
        #endif
        
        
        let heapDescriptor = MTLHeapDescriptor()
        heapDescriptor.size = 1 << 24 // A 16MB heap
        heapDescriptor.storageMode = .private
        self.privateAllocator = SingleFrameHeapResourceAllocator(device: device, defaultDescriptor: heapDescriptor, framePurgeability: .empty)
        
        // The small private allocator is multi-buffered to minimise the need for fence waits.
        self.smallPrivateAllocator = MultiFrameHeapResourceAllocator(device: device, defaultDescriptor: heapDescriptor, framePurgeability: .empty, numFrames: 3)
        
        heapDescriptor.size = 40_000_000 // A 40MB heap
        self.depthRenderTargetAllocator = SingleFrameHeapResourceAllocator(device: device, defaultDescriptor: heapDescriptor, framePurgeability: .empty)
        
        heapDescriptor.size = 200_000_000 // A 200MB heap
        self.colorRenderTargetAllocator = SingleFrameHeapResourceAllocator(device: device, defaultDescriptor: heapDescriptor, framePurgeability: .empty)

        let fenceRetainFunc : (MTLFenceType) -> Void = { [unowned self] fence in
            self.retainFence(fence)
        }
        
        let fenceReleaseFunc : (MTLFenceType) -> Void = { [unowned self] fence in
            self.releaseFence(fence)
        }
        
        self.stagingTextureAllocator.fenceRetainFunc = fenceRetainFunc
        self.historyBufferAllocator.fenceRetainFunc = fenceRetainFunc
        self.persistentAllocator.fenceRetainFunc = fenceRetainFunc
        self.privateAllocator.fenceRetainFunc = fenceRetainFunc
        self.smallPrivateAllocator.fenceRetainFunc = fenceRetainFunc
        self.colorRenderTargetAllocator.fenceRetainFunc = fenceRetainFunc
        self.depthRenderTargetAllocator.fenceRetainFunc = fenceRetainFunc

        self.privateAllocator.fenceReleaseFunc = fenceReleaseFunc
        self.smallPrivateAllocator.fenceReleaseFunc = fenceReleaseFunc
        self.colorRenderTargetAllocator.fenceReleaseFunc = fenceReleaseFunc
        self.depthRenderTargetAllocator.fenceReleaseFunc = fenceReleaseFunc
        self.stagingTextureAllocator.fenceReleaseFunc = fenceReleaseFunc
        self.historyBufferAllocator.fenceReleaseFunc = fenceReleaseFunc
        self.persistentAllocator.fenceReleaseFunc = fenceReleaseFunc
        
        #if os(iOS)
        self.memorylessTextureAllocator.fenceRetainFunc = fenceRetainFunc
        self.memorylessTextureAllocator.fenceReleaseFunc = fenceReleaseFunc
        #endif
    }
    
    public func registerWindowTexture(texture: Texture, context: Any) {
        self.windowReferences[texture.handle] = (context as! MTKView)
    }
    
    func allocatorForTexture(storageMode: MTLStorageMode, flags: ResourceFlags, textureParams: (PixelFormat, MTLTextureUsage)) -> TextureAllocator {
        
        if flags.contains(.persistent) {
            return self.persistentAllocator
        }
        if flags.contains(.historyBuffer) {
            assert(storageMode == .private)
            return self.historyBufferAllocator
        }
        
        #if os(iOS)
        if storageMode == .memoryless {
            return self.memorylessTextureAllocator
        }
        #endif
        
        if storageMode != .private {
            return self.stagingTextureAllocator
        } else {
            if textureParams.0.isDepth || textureParams.0.isStencil {
                return self.depthRenderTargetAllocator
            } else {
                return self.colorRenderTargetAllocator
            }
        }
    }
    
    func allocatorForBuffer(length: Int, storageMode: StorageMode, cacheMode: CPUCacheMode, flags: ResourceFlags) -> BufferAllocator {
        
        if flags.contains(.persistent) {
            return self.persistentAllocator
        }
        if flags.contains(.historyBuffer) {
            assert(storageMode == .private)
            return self.historyBufferAllocator
        }
        switch storageMode {
        case .private:
            if length <= self.smallAllocationThreshold {
                return self.smallPrivateAllocator
            }
            return self.privateAllocator
        case .managed:
            #if os(macOS)
            switch cacheMode {
            case .writeCombined:
                return self.frameManagedWriteCombinedBufferAllocator
            case .defaultCache:
                return self.frameManagedBufferAllocator
            }
            #else
            fallthrough
            #endif
        
        case .shared:
            switch cacheMode {
            case .writeCombined:
                return self.frameSharedWriteCombinedBufferAllocator
            case .defaultCache:
                return self.frameSharedBufferAllocator
            }
        }
    }
    
    func needsWaitFencesOnFrameCompletion(resource: Resource) -> Bool {
        let flags = resource.flags
        let storageMode : StorageMode = resource.storageMode
        var size = Int.max
        if let buffer = resource.buffer {
            size = buffer.descriptor.length
        }
        
        if flags.contains(.windowHandle) {
            return false
        }
        
        // All non-private resources are multiple buffered and so don't need wait fences.
        return (storageMode == .private && size > self.smallAllocationThreshold) || flags.intersection([.persistent, .historyBuffer]) != []
    }
    
    @discardableResult
    public func allocateTexture(_ texture: Texture, properties: TextureUsageProperties) -> MTLTexture? {
        if texture.flags.contains(.windowHandle) {
            // Reserve a slot in texture references so we can later insert the texture reference in a thread-safe way, but don't actually allocate anything yet
            self.textureReferences[texture.handle] = MTLTextureReference(windowTexture: ())
            return nil
        }
        
        let descriptor = MTLTextureDescriptor(texture.descriptor, usage: properties.usage)
        
        #if os(iOS)
        if properties.canBeMemoryless {
            descriptor.storageMode = .memoryless
        }
        #endif
        
        let allocator = self.allocatorForTexture(storageMode: descriptor.storageMode, flags: texture.flags, textureParams: (texture.descriptor.pixelFormat, properties.usage))
        let mtlTexture = allocator.collectTextureWithDescriptor(descriptor)
        
        assert(self.textureReferences[texture.handle] == nil)
        self.textureReferences[texture.handle] = mtlTexture
        return mtlTexture.texture
    }
    
    @discardableResult
    public func allocateRenderTargetTexture(_ texture: Texture) throws -> MTLTexture {
        if texture.flags.contains(.windowHandle) {
            return try DispatchQueue.main.sync(execute: {
                // Retrieving the drawable needs to be done on the main thread.
                // Also update and check the MTLTextureReference on the same thread so that subsequent render passes
                // retrieving the same texture always see the same result (and so nextDrawable() only gets called once).
                
                return try autoreleasepool { () throws -> MTLTexture in
                    // The texture reference should always be present but the texture itself might not be.
                    if let texture = self.textureReferences[texture.handle]!._texture {
                        return texture
                    }
                    
                    let windowReference = self.windowReferences[texture.handle]!
                    
                    guard let mtlDrawable = (windowReference.layer as! CAMetalLayer).nextDrawable() else {
                        throw RenderTargetTextureError.unableToRetrieveDrawable(texture)
                    }
                    
                    let drawableTexture = mtlDrawable.texture
                    if drawableTexture.width >= texture.descriptor.size.width && drawableTexture.height >= texture.descriptor.size.height {
                        self.frameDrawables.append(mtlDrawable)
                        self.textureReferences[texture.handle]!._texture = drawableTexture
                        return drawableTexture
                    } else {
                        // The window was resized to be smaller than the texture size. We can't render directly to that, so instead
                        // throw an error.
                        throw RenderTargetTextureError.invalidSizeDrawable(texture)
                    }
                }
            })
        }
    
        // Otherwise, the texture has already been allocated as part of a materialiseTexture call.
        return self[texture]!
    }
    
    @discardableResult
    public func allocateBuffer(_ buffer: Buffer) -> MTLBufferReference {
        let allocator = self.allocatorForBuffer(length: buffer.descriptor.length, storageMode: buffer.descriptor.storageMode, cacheMode: buffer.descriptor.cacheMode, flags: buffer.flags)
        let mtlBuffer = allocator.collectBufferWithLength(buffer.descriptor.length, options: MTLResourceOptions(storageMode: buffer.descriptor.storageMode, cacheMode: buffer.descriptor.cacheMode))
        
        assert(self.bufferReferences[buffer.handle] == nil)
        self.bufferReferences[buffer.handle] = mtlBuffer
        
        return mtlBuffer
    }
    
    @discardableResult
    public func allocateBufferIfNeeded(_ buffer: Buffer) -> MTLBufferReference {
        if let mtlBuffer = self.bufferReferences[buffer.handle] {
            return mtlBuffer
        }
        return self.allocateBuffer(buffer)
    }
    
    @discardableResult
    public func allocateTextureIfNeeded(_ texture: Texture, usage: TextureUsageProperties) -> MTLTexture? {
        if let mtlTexture = self.textureReferences[texture.handle]?.texture {
            assert(mtlTexture.pixelFormat == MTLPixelFormat(texture.descriptor.pixelFormat))
            return mtlTexture
        }
        return self.allocateTexture(texture, properties: usage)
    }
    
    func allocateArgumentBufferStorage<A : ResourceProtocol>(for argumentBuffer: A, encodedLength: Int) -> MTLBufferReference {
        #if os(macOS)
        let options : MTLResourceOptions = [.storageModeManaged, .cpuCacheModeWriteCombined, .hazardTrackingModeUntracked]
        #else
        let options : MTLResourceOptions = [.storageModeShared, .cpuCacheModeWriteCombined, .hazardTrackingModeUntracked]
        #endif
        
        if argumentBuffer.flags.contains(.persistent) {
            return self.persistentAllocator.collectBufferWithLength(encodedLength, options: options)
        }
        return self.frameArgumentBufferAllocator.collectBufferWithLength(encodedLength, options: options)
    }
    
    // `encoder` is taken as a closure since retrieving an argument encoder from the state caches has a small cost.
    func allocateArgumentBufferIfNeeded(_ argumentBuffer: ArgumentBuffer, bindingPath: ResourceBindingPath, encoder: () -> MTLArgumentEncoder, stateCaches: StateCaches) -> MTLBufferReference {
        return self.accessQueue.sync {
            if let mtlArgumentBuffer = self.argumentBufferReferences[argumentBuffer.handle] {
                return mtlArgumentBuffer
            }
            
            let argEncoder = encoder()
            let storage = self.allocateArgumentBufferStorage(for: argumentBuffer, encodedLength: argEncoder.encodedLength)
            
            argEncoder.setArgumentBuffer(storage.buffer, offset: storage.offset)
            argEncoder.encodeArguments(from: argumentBuffer, argumentBufferPath: bindingPath, resourceRegistry: self, stateCaches: stateCaches)
            
            #if os(macOS)
            storage.buffer.didModifyRange(storage.offset..<(storage.offset + argEncoder.encodedLength))
            #endif
            
            self.argumentBufferReferences[argumentBuffer.handle] = storage
            
            return storage
        }
    }
    
    // `encoder` is taken as a closure since retrieving an argument encoder from the state caches has a small cost.
    func allocateArgumentBufferArrayIfNeeded(_ argumentBufferArray: ArgumentBufferArray, bindingPath: ResourceBindingPath, encoder: () -> MTLArgumentEncoder, stateCaches: StateCaches) -> MTLBufferReference {
        return self.accessQueue.sync {
        if let mtlArgumentBuffer = self.argumentBufferReferences[argumentBufferArray.handle] {
            return mtlArgumentBuffer
        }
        
        let argEncoder = encoder()
        let storage = self.allocateArgumentBufferStorage(for: argumentBufferArray, encodedLength: argEncoder.encodedLength * argumentBufferArray.bindings.count)
        
        for (i, argumentBuffer) in argumentBufferArray.bindings.enumerated() {
            guard let argumentBuffer = argumentBuffer else { continue }
            
            argEncoder.setArgumentBuffer(storage.buffer, startOffset: storage.offset, arrayElement: i)
            
            argEncoder.encodeArguments(from: argumentBuffer, argumentBufferPath: bindingPath, resourceRegistry: self, stateCaches: stateCaches)
        }
        
        #if os(macOS)
        storage.buffer.didModifyRange(storage.offset..<(storage.offset + argEncoder.encodedLength * argumentBufferArray.bindings.count))
        #endif
            
        self.argumentBufferReferences[argumentBufferArray.handle] = storage
        
        return storage
}
    }
    
    // These subscript methods should only be called after 'allocate' has been called.
    // If you hit an error here, check if you forgot to make a resource persistent.
    public subscript(texture: Texture) -> MTLTexture? {
        return self.textureReferences[texture.handle]?.texture
    }
    
    public subscript(texture texture: Texture.Handle) -> MTLTexture? {
        return self.textureReferences[texture]!.texture
    }
    
    public subscript(textureReference texture: Texture) -> MTLTextureReference? {
        return self.textureReferences[texture.handle]!
    }
    
    public subscript(textureReference texture: Texture.Handle) -> MTLTextureReference? {
        return self.textureReferences[texture]!
    }
    
    public subscript(buffer: Buffer) -> MTLBufferReference? {
        return self.bufferReferences[buffer.handle]
    }
    
    public subscript(buffer buffer: Buffer.Handle) -> MTLBufferReference? {
        return self.bufferReferences[buffer]
    }
    
    func releaseMultiframeFences<R : MTLResourceReference>(on resourceRef: inout R) {
        resourceRef.usageFences.writeWaitFences.forEach {
            self.releaseFence($0)
        }
        
        resourceRef.usageFences.readWaitFences.forEach {
            self.releaseFence($0)
        }
    }
    
    public func releaseMultiframeFences(on texture: Texture) {
        self.textureReferences.withValue(forKey: texture.handle, perform: { (mtlTexturePtr, initialised) in
            guard initialised else { return }
            self.releaseMultiframeFences(on: &mtlTexturePtr.pointee)
        })
    }
    
    public func releaseMultiframeFences(on buffer: Buffer) {
        self.bufferReferences.withValue(forKey: buffer.handle, perform: { (mtlBufferPtr, initialised) in
            guard initialised else { return }
            self.releaseMultiframeFences(on: &mtlBufferPtr.pointee)
        })
    }
    
    private func setDisposalFences<R : MTLResourceReference>(_ resourceRef: inout R, readFence: MTLFenceType?, writeFences: [MTLFenceType]?) {
        assert(resourceRef.disposalFences.readWaitFences.isEmpty)
        assert(resourceRef.disposalFences.writeWaitFences.isEmpty)
        
        if let readFence = readFence {
            resourceRef.disposalFences.readWaitFences.append(readFence)
            self.retainFence(readFence)
            assert(self.fenceRetainCounts[ObjectIdentifier(readFence)]! > 0)
        }
        
        if let writeFences = writeFences {
            for fence in writeFences {
                resourceRef.disposalFences.writeWaitFences.append(fence)
                self.retainFence(fence)
                assert(self.fenceRetainCounts[ObjectIdentifier(fence)]! > 0)
            }
        }
        
        resourceRef.usedThisFrame = true
    }
    
    public func setDisposalFences(_ texture: Texture, readFence: MTLFenceType?, writeFences: [MTLFenceType]?) {
        guard !texture.flags.contains(.windowHandle) else { return }
        
        self.textureReferences.withValue(forKey: texture.handle, perform: { (mtlTexturePtr, initialised) in
            guard initialised else { return }
            self.setDisposalFences(&mtlTexturePtr.pointee, readFence: readFence, writeFences: writeFences)
        })
    }
    
    public func setDisposalFences(_ buffer: Buffer, readFence: MTLFenceType?, writeFences: [MTLFenceType]?) {
        self.bufferReferences.withValue(forKey: buffer.handle, perform: { (mtlBufferPtr, initialised) in
            guard initialised else { return }
            self.setDisposalFences(&mtlBufferPtr.pointee, readFence: readFence, writeFences: writeFences)
        })
    }

    public func disposeTexture(_ texture: Texture, keepingReference: Bool) {
        if var mtlTexture = (keepingReference ? self.textureReferences[texture.handle] : self.textureReferences.removeValue(forKey: texture.handle)) {
            if texture.flags.contains(.windowHandle) {
                return
            }
            
            mtlTexture.setUsageFencesToDisposalFences()
            
            let allocator = self.allocatorForTexture(storageMode: mtlTexture.texture.storageMode, flags: texture.flags, textureParams: (texture.descriptor.pixelFormat, mtlTexture.texture.usage))
            allocator.depositTexture(mtlTexture)
            
        }
    }
    
    public func disposeBuffer(_ buffer: Buffer, keepingReference: Bool) {
        if var mtlBuffer = (keepingReference ? self.bufferReferences[buffer.handle] : self.bufferReferences.removeValue(forKey: buffer.handle)) {
            
            mtlBuffer.setUsageFencesToDisposalFences()
            
            let allocator = self.allocatorForBuffer(length: buffer.descriptor.length, storageMode: buffer.descriptor.storageMode, cacheMode: buffer.descriptor.cacheMode, flags: buffer.flags)
            allocator.depositBuffer(mtlBuffer)
        }
    }
    
    public func disposeArgumentBuffer(_ buffer: ArgumentBuffer, keepingReference: Bool) {
        if !keepingReference {
            self.bufferReferences.removeValue(forKey: buffer.handle)
        }
    }
    
    public func disposeArgumentBufferArray(_ buffer: ArgumentBufferArray, keepingReference: Bool) {
        if !keepingReference {
            self.bufferReferences.removeValue(forKey: buffer.handle)
        }
    }

    public func allocateFence() -> MTLFenceType {
        
        let fence = self.unusedFences.popLast() ?? self.device.makeFence()!
        assert(self.fenceRetainCounts[ObjectIdentifier(fence), default: 0] == 0)
        self.fenceRetainCounts[ObjectIdentifier(fence)] = 1
        
        return fence
    }
    
    public func retainFence(_ fence: MTLFenceType) {
        assert(self.fenceRetainCounts[ObjectIdentifier(fence)]! > 0, "Retaining an already-released fence.")
        
        self.fenceRetainCounts[ObjectIdentifier(fence)]! += 1
    }
    
    public func releaseFence(_ fence: MTLFenceType) {
        self.fenceRetainCounts[ObjectIdentifier(fence)]! -= 1
        
        if self.fenceRetainCounts[ObjectIdentifier(fence)]! <= 0 {
            assert(self.fenceRetainCounts[ObjectIdentifier(fence)]! == 0)
            self.frameEndUnusedFences.append(fence)
        }
    }
    
    public func bufferContents(for buffer: Buffer) -> UnsafeMutableRawPointer {
        assert(buffer.flags.contains(.persistent) || self.frameGraphHasResourceAccess, "GPU memory for a transient buffer may not be accessed outside of a FrameGraph RenderPass. Consider using withDeferredSlice instead.")
        
        let bufferReference = self.allocateBufferIfNeeded(buffer)
        return bufferReference.buffer.contents() + bufferReference.offset
    }
    
    public func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) {
        assert(texture.flags.contains(.persistent) || self.frameGraphHasResourceAccess, "GPU memory for a transient texture may not be accessed outside of a FrameGraph RenderPass.")
        
        self.allocateTextureIfNeeded(texture, usage: TextureUsageProperties(texture.descriptor.usageHint))
        self[texture]!.replace(region: MTLRegion(region), mipmapLevel: mipmapLevel, withBytes: bytes, bytesPerRow: bytesPerRow)
    }
    
    public func registerInitialisedHistoryBufferForDisposal(resource: Resource) {
        assert(resource.flags.contains(.historyBuffer) && resource.stateFlags.contains(.initialised))
        resource.dispose() // This will dispose it in the FrameGraph persistent allocator, which will in turn call dispose here at the end of the frame.
    }
    
    public func cycleFrames() {
        // Clear all transient resources at the end of the frame.
        
        self.textureReferences.forEachMutating { (handle, mtlResource, deleteEntry) in
            let resource = Resource(existingHandle: handle)
            if resource.flags.intersection([.historyBuffer, .persistent]) == [] {
                deleteEntry = true
            } else {
                mtlResource.setUsageFencesToDisposalFences()
                assert(mtlResource.usageFences.readWaitFences.allSatisfy({ self.fenceRetainCounts[ObjectIdentifier($0)]! > 0 }))
                assert(mtlResource.usageFences.writeWaitFences.allSatisfy({ self.fenceRetainCounts[ObjectIdentifier($0)]! > 0 }))
            }
        }
        
        self.bufferReferences.forEachMutating { (handle, mtlResource, deleteEntry) in
            let resource = Resource(existingHandle: handle)
            if resource.flags.intersection([.historyBuffer, .persistent]) == [] {
                deleteEntry = true
            } else {
                mtlResource.setUsageFencesToDisposalFences()
                assert(mtlResource.usageFences.readWaitFences.allSatisfy({ self.fenceRetainCounts[ObjectIdentifier($0)]! > 0 }))
                assert(mtlResource.usageFences.writeWaitFences.allSatisfy({ self.fenceRetainCounts[ObjectIdentifier($0)]! > 0 }))
            }
        }

        self.argumentBufferReferences.forEachMutating { (handle, mtlResource, deleteEntry) in
            let resource = Resource(existingHandle: handle)
            if resource.flags.intersection([.historyBuffer, .persistent]) == [] {
                deleteEntry = true
            } else {
                mtlResource.setUsageFencesToDisposalFences()
                assert(mtlResource.usageFences.readWaitFences.allSatisfy({ self.fenceRetainCounts[ObjectIdentifier($0)]! > 0 }))
                assert(mtlResource.usageFences.writeWaitFences.allSatisfy({ self.fenceRetainCounts[ObjectIdentifier($0)]! > 0 }))
            }
            
        }
        
        self.stagingTextureAllocator.cycleFrames()
        self.privateAllocator.cycleFrames()
        self.smallPrivateAllocator.cycleFrames()
        self.historyBufferAllocator.cycleFrames()
        
        self.colorRenderTargetAllocator.cycleFrames()
        self.depthRenderTargetAllocator.cycleFrames()
        self.persistentAllocator.cycleFrames()
        
        self.frameSharedBufferAllocator.cycleFrames()
        self.frameSharedWriteCombinedBufferAllocator.cycleFrames()
        
        #if os(macOS)
        self.frameManagedBufferAllocator.cycleFrames()
        self.frameManagedWriteCombinedBufferAllocator.cycleFrames()
        #elseif os(iOS)
        self.memorylessTextureAllocator.cycleFrames()
        #endif
        
        self.frameArgumentBufferAllocator.cycleFrames()
        
        self.windowReferences.removeAll(keepingCapacity: true)
        self.frameDrawables.removeAll(keepingCapacity: true)
        
        self.unusedFences.append(contentsOf: self.frameEndUnusedFences)
        self.frameEndUnusedFences.removeAll(keepingCapacity: true)
    
        assert(self.unusedFences.allSatisfy { fence in self.fenceRetainCounts[ObjectIdentifier(fence)]! == 0 })
        
    }
}
