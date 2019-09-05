//
//  MetalResourceRegistry.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 23/12/17.
//

#if canImport(Metal)

import Metal
import MetalKit
import FrameGraphUtilities

struct MetalWaitEvent {
    /// The value which the main wait event needs to reach before this resource can be used.
    var waitValue : UInt64 = 0
}

protocol MTLResourceReference {
    associatedtype Resource : MTLResource
    var resource : Resource { get }
}

// Must be a POD type and trivially copyable/movable
struct MTLBufferReference : MTLResourceReference {
    let _buffer : Unmanaged<MTLBuffer>
    let offset : Int
    
    var buffer : MTLBuffer {
        return self._buffer.takeUnretainedValue()
    }
    
    var resource : MTLBuffer {
        return self._buffer.takeUnretainedValue()
    }
    
    init(buffer: Unmanaged<MTLBuffer>, offset: Int) {
        self._buffer = buffer
        self.offset = offset
    }
}

// Must be a POD type and trivially copyable/movable
struct MTLTextureReference : MTLResourceReference {
    var _texture : Unmanaged<MTLTexture>!
    
    var texture : MTLTexture {
        return _texture.takeUnretainedValue()
    }
    
    var resource : MTLTexture {
        return self.texture
    }
    
    init(windowTexture: ()) {
        self._texture = nil
    }
    
    init(texture: Unmanaged<MTLTexture>) {
        self._texture = texture
    }
}

final class MetalResourceRegistry {
    
    var accessLock = ReaderWriterLock()
    
    private var textureReferences = ResourceMap<Texture, MTLTextureReference>()
    private var bufferReferences = ResourceMap<Buffer, MTLBufferReference>()
    private var argumentBufferReferences = ResourceMap<_ArgumentBuffer, MTLBufferReference>() // Separate since this needs to have thread-safe access.
    private var argumentBufferArrayReferences = ResourceMap<_ArgumentBufferArray, MTLBufferReference>() // Separate since this needs to have thread-safe access.
    
    var textureWaitEvents = ResourceMap<Texture, MetalWaitEvent>()
    var bufferWaitEvents = ResourceMap<Buffer, MetalWaitEvent>()
    var argumentBufferWaitEvents = ResourceMap<_ArgumentBuffer, MetalWaitEvent>()
    var argumentBufferArrayWaitEvents = ResourceMap<_ArgumentBufferArray, MetalWaitEvent>()
    
    private var heapResourceUsageFences = [Resource : [MetalFenceHandle]]()
    private var heapResourceDisposalFences = [Resource : [MetalFenceHandle]]()
    
    private var persistentResourceWaitEvents = [Resource : MetalWaitEvent]()
    
    private var windowReferences = [ResourceProtocol.Handle : MTKView]()
    
    private let device : MTLDevice
    
    private let frameSharedBufferAllocator : MetalTemporaryBufferAllocator
    private let frameSharedWriteCombinedBufferAllocator : MetalTemporaryBufferAllocator
    
    #if os(macOS)
    private let frameManagedBufferAllocator : MetalTemporaryBufferAllocator
    private let frameManagedWriteCombinedBufferAllocator : MetalTemporaryBufferAllocator
    #endif
    
    #if os(iOS)
    private let memorylessTextureAllocator : MetalPoolResourceAllocator
    #endif
    
    private let frameArgumentBufferAllocator : MetalTemporaryBufferAllocator
    
    private let stagingTextureAllocator : MetalPoolResourceAllocator
    private let privateAllocator : MetalHeapResourceAllocator
    
    private let colorRenderTargetAllocator : MetalHeapResourceAllocator
    private let depthRenderTargetAllocator : MetalHeapResourceAllocator
    
    private let historyBufferAllocator : MetalPoolResourceAllocator
    private let persistentAllocator : MetalPersistentResourceAllocator
    
    public private(set) var frameDrawables : [CAMetalDrawable] = []
    
    public var frameGraphHasResourceAccess = false
    
    public init(device: MTLDevice, numInflightFrames: Int) {
        self.device = device
        
        self.stagingTextureAllocator = MetalPoolResourceAllocator(device: device, numFrames: numInflightFrames)
        self.historyBufferAllocator = MetalPoolResourceAllocator(device: device, numFrames: 1)
        
        self.persistentAllocator = MetalPersistentResourceAllocator(device: device)
        
        self.frameSharedBufferAllocator = MetalTemporaryBufferAllocator(device: device, numFrames: numInflightFrames, blockSize: 256 * 1024, options: [.storageModeShared, .frameGraphTrackedHazards])
        self.frameSharedWriteCombinedBufferAllocator = MetalTemporaryBufferAllocator(device: device, numFrames: numInflightFrames, blockSize: 2 * 1024 * 1024, options: [.storageModeShared, .cpuCacheModeWriteCombined, .frameGraphTrackedHazards])
        
        #if os(macOS)
        self.frameManagedBufferAllocator = MetalTemporaryBufferAllocator(device: device, numFrames: numInflightFrames, blockSize: 1024 * 1024, options: [.storageModeManaged, .frameGraphTrackedHazards])
        self.frameManagedWriteCombinedBufferAllocator = MetalTemporaryBufferAllocator(device: device, numFrames: numInflightFrames, blockSize: 2 * 1024 * 1024, options: [.storageModeManaged, .cpuCacheModeWriteCombined, .frameGraphTrackedHazards])
        self.frameArgumentBufferAllocator = MetalTemporaryBufferAllocator(device: device, numFrames: numInflightFrames, blockSize: 2 * 1024 * 1024, options: [.storageModeShared, .frameGraphTrackedHazards])
        #else
        self.frameArgumentBufferAllocator = MetalTemporaryBufferAllocator(device: device, numFrames: numInflightFrames, blockSize: 2 * 1024 * 1024, options: [.storageModeShared, .frameGraphTrackedHazards])
        self.memorylessTextureAllocator = MetalPoolResourceAllocator(device: device, numFrames: 1)
        #endif
        
        self.privateAllocator = MetalHeapResourceAllocator(device: device)
        self.depthRenderTargetAllocator = MetalHeapResourceAllocator(device: device)
        self.colorRenderTargetAllocator = MetalHeapResourceAllocator(device: device)
        
        self.prepareFrame()
        MetalFenceRegistry.instance.device = self.device
    }
    
    
    deinit {
        self.textureReferences.deinit()
        self.bufferReferences.deinit()
        self.argumentBufferReferences.deinit()
        self.argumentBufferArrayReferences.deinit()
        
        self.textureWaitEvents.deinit()
        self.bufferWaitEvents.deinit()
        self.argumentBufferWaitEvents.deinit()
        self.argumentBufferArrayWaitEvents.deinit()
    }
    
    public func prepareFrame() {
        self.textureReferences.prepareFrame()
        self.bufferReferences.prepareFrame()
        self.argumentBufferReferences.prepareFrame()
        self.argumentBufferArrayReferences.prepareFrame()
        
        self.textureWaitEvents.prepareFrame()
        self.bufferWaitEvents.prepareFrame()
        self.argumentBufferWaitEvents.prepareFrame()
        self.argumentBufferArrayWaitEvents.prepareFrame()
    }
    
    public func registerWindowTexture(texture: Texture, context: Any) {
        self.windowReferences[texture.handle] = (context as! MTKView)
    }
    
    func allocatorForTexture(storageMode: MTLStorageMode, flags: ResourceFlags, textureParams: (PixelFormat, MTLTextureUsage)) -> MetalTextureAllocator {
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
    
    func allocatorForBuffer(length: Int, storageMode: StorageMode, cacheMode: CPUCacheMode, flags: ResourceFlags) -> MetalBufferAllocator {
        
        if flags.contains(.persistent) {
            return self.persistentAllocator
        }
        if flags.contains(.historyBuffer) {
            assert(storageMode == .private)
            return self.historyBufferAllocator
        }
        switch storageMode {
        case .private:
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
    
    func allocatorForArgumentBuffer(flags: ResourceFlags) -> MetalBufferAllocator {
        if flags.contains(.persistent) {
            return self.persistentAllocator
        }
        return self.frameArgumentBufferAllocator
    }
    
    
    func isAliasedHeapResource(resource: Resource) -> Bool {
        let flags = resource.flags
        let storageMode : StorageMode = resource.storageMode
        
        if flags.contains(.windowHandle) {
            return false
        }
        
        if flags.intersection([.persistent, .historyBuffer]) != [] {
            return false
        }
        
        return storageMode == .private
    }
    
    @discardableResult
    public func allocateTexture(_ texture: Texture, properties: MetalTextureUsageProperties) -> MTLTexture? {
        if texture._usesPersistentRegistry {
            // Ensure we can fit this new reference.
            self.textureReferences.prepareFrame()
        }
        
        if texture.flags.contains(.windowHandle) {
            // Reserve a slot in texture references so we can later insert the texture reference in a thread-safe way, but don't actually allocate anything yet
            self.textureReferences[texture] = MTLTextureReference(windowTexture: ())
            return nil
        }
        
        let descriptor = MTLTextureDescriptor(texture.descriptor, usage: properties.usage)
        
        #if os(iOS)
        if properties.canBeMemoryless {
            descriptor.storageMode = .memoryless
            descriptor.resourceOptions.formUnion(.storageModeMemoryless)
        }
        #endif
        
        let allocator = self.allocatorForTexture(storageMode: descriptor.storageMode, flags: texture.flags, textureParams: (texture.descriptor.pixelFormat, properties.usage))
        let (mtlTexture, fences, waitEvent) = allocator.collectTextureWithDescriptor(descriptor)
        if let label = texture.label {
            mtlTexture.texture.label = label
        }
        
        assert(self.textureReferences[texture] == nil)
        self.textureReferences[texture] = mtlTexture
        
        self.textureWaitEvents[texture] = waitEvent
        
        if !fences.isEmpty {
            self.heapResourceUsageFences[Resource(texture)] = fences
        }
        
        return mtlTexture.texture
    }
    
    @discardableResult
    public func allocateTextureView(_ texture: Texture, properties: MetalTextureUsageProperties) -> MTLTexture? {
        assert(texture.flags.intersection([.persistent, .windowHandle, .externalOwnership]) == [])
        
        let mtlTexture : MTLTexture
        
        let baseResource = texture.baseResource!
        switch texture.textureViewBaseInfo! {
        case .buffer(let bufferInfo):
            let mtlBuffer = self[buffer: baseResource.handle]!
            let descriptor = MTLTextureDescriptor(bufferInfo.descriptor, usage: properties.usage)
            mtlTexture = mtlBuffer.resource.makeTexture(descriptor: descriptor, offset: bufferInfo.offset, bytesPerRow: bufferInfo.bytesPerRow)!
        case .texture(let textureInfo):
            let baseTexture = self[texture: baseResource.handle]!
            if textureInfo.levels.lowerBound == -1 || textureInfo.slices.lowerBound == -1 {
                assert(textureInfo.levels.lowerBound == -1 && textureInfo.slices.lowerBound == -1)
                mtlTexture = baseTexture.makeTextureView(pixelFormat: MTLPixelFormat(textureInfo.pixelFormat))!
            } else {
                mtlTexture = baseTexture.makeTextureView(pixelFormat: MTLPixelFormat(textureInfo.pixelFormat), textureType: MTLTextureType(textureInfo.textureType), levels: textureInfo.levels, slices: textureInfo.slices)!
            }
        }
        
        assert(self.textureReferences[texture] == nil)
        self.textureReferences[texture] = MTLTextureReference(texture: Unmanaged.passRetained(mtlTexture))
        return mtlTexture
    }
    
    @discardableResult
    public func allocateRenderTargetTexture(_ texture: Texture) throws -> MTLTexture {
        if texture.flags.contains(.windowHandle) {
            var mtlTexture : MTLTexture! = nil
            var error : RenderTargetTextureError? = nil
            
            // Retrieving the drawable needs to be done on the main thread.
            // Also update and check the MTLTextureReference on the same thread so that subsequent render passes
            // retrieving the same texture always see the same result (and so nextDrawable() only gets called once).
            
            FrameGraph.jobManager.syncOnMainThread {
                 autoreleasepool {
                    // The texture reference should always be present but the texture itself might not be.
                    if let texture = self.textureReferences[texture]!._texture {
                        mtlTexture = texture.takeUnretainedValue()
                        return
                    }
                    
                    let windowReference = self.windowReferences[texture.handle]!
                    
                    guard let mtlDrawable = (windowReference.layer as! CAMetalLayer).nextDrawable() else {
                        error = RenderTargetTextureError.unableToRetrieveDrawable(texture)
                        return
                    }
                    
                    let drawableTexture = mtlDrawable.texture
                    if drawableTexture.width >= texture.descriptor.size.width && drawableTexture.height >= texture.descriptor.size.height {
                        self.frameDrawables.append(mtlDrawable)
                        self.textureReferences[texture]!._texture = Unmanaged.passUnretained(drawableTexture) // since it's owned by the MTLDrawable
                        mtlTexture = drawableTexture
                        return
                    } else {
                        // The window was resized to be smaller than the texture size. We can't render directly to that, so instead
                        // throw an error.
                        error = RenderTargetTextureError.invalidSizeDrawable(texture, requestedSize: Size(width: texture.descriptor.width, height: texture.descriptor.height), drawableSize: Size(width: drawableTexture.width, height: drawableTexture.height))
                        return
                    }
                }
                        
            }
            if let error = error {
                throw error
            } else {
                return mtlTexture
            }
        }
        
        // Otherwise, the texture has already been allocated as part of a materialiseTexture call.
        return self[texture]!
    }
    
    @discardableResult
    public func allocateBuffer(_ buffer: Buffer) -> MTLBufferReference {
        if buffer._usesPersistentRegistry {
            // Ensure we can fit this new reference.
            self.bufferReferences.prepareFrame()
        }
        
        let allocator = self.allocatorForBuffer(length: buffer.descriptor.length, storageMode: buffer.descriptor.storageMode, cacheMode: buffer.descriptor.cacheMode, flags: buffer.flags)
        var options = MTLResourceOptions(storageMode: buffer.descriptor.storageMode, cacheMode: buffer.descriptor.cacheMode)
        if buffer.descriptor.usageHint.contains(.textureView) {
            options.remove(.frameGraphTrackedHazards) // FIXME: workaround for a bug in Metal where setting hazardTrackingModeUntracked on a MTLTextureDescriptor doesn't stick
        }
        let (mtlBuffer, fences, waitEvent) = allocator.collectBufferWithLength(buffer.descriptor.length, options: options)
        if let label = buffer.label {
            mtlBuffer.buffer.label = label
        }
        
        assert(self.bufferReferences[buffer] == nil)
        self.bufferReferences[buffer] = mtlBuffer
        
        self.bufferWaitEvents[buffer] = waitEvent
        
        if !fences.isEmpty {
            self.heapResourceUsageFences[Resource(buffer)] = fences
        }
        
        return mtlBuffer
    }
    
    @discardableResult
    public func allocateBufferIfNeeded(_ buffer: Buffer) -> MTLBufferReference {
        if let mtlBuffer = self.bufferReferences[buffer] {
            return mtlBuffer
        }
        return self.allocateBuffer(buffer)
    }
    
    @discardableResult
    public func allocateTextureIfNeeded(_ texture: Texture, usage: MetalTextureUsageProperties) -> MTLTexture? {
        if let mtlTexture = self.textureReferences[texture]?.texture {
            assert(mtlTexture.pixelFormat == MTLPixelFormat(texture.descriptor.pixelFormat))
            return mtlTexture
        }
        return self.allocateTexture(texture, properties: usage)
    }
    
    func allocateArgumentBufferStorage<A : ResourceProtocol>(for argumentBuffer: A, encodedLength: Int) -> (MTLBufferReference, [MetalFenceHandle], MetalWaitEvent) {
//        #if os(macOS)
//        let options : MTLResourceOptions = [.storageModeManaged, .frameGraphTrackedHazards]
//        #else
        let options : MTLResourceOptions = [.storageModeShared, .frameGraphTrackedHazards]
//        #endif
        
        let allocator = self.allocatorForArgumentBuffer(flags: argumentBuffer.flags)
        return allocator.collectBufferWithLength(encodedLength, options: options)
    }
    
    @discardableResult
    func allocateArgumentBufferIfNeeded(_ argumentBuffer: _ArgumentBuffer, stateCaches: MetalStateCaches) -> MTLBufferReference {
        if let baseArray = argumentBuffer.sourceArray {
            _ = self.allocateArgumentBufferArrayIfNeeded(baseArray, stateCaches: stateCaches)
            return self.argumentBufferReferences[argumentBuffer]!
        }
        return self.accessLock.withWriteLock {
            if let mtlArgumentBuffer = self.argumentBufferReferences[argumentBuffer] {
                return mtlArgumentBuffer
            }
            
            let argEncoder = Unmanaged<MTLArgumentEncoder>.fromOpaque(argumentBuffer.encoder!).takeUnretainedValue()
            let (storage, fences, waitEvent) = self.allocateArgumentBufferStorage(for: argumentBuffer, encodedLength: argEncoder.encodedLength)
            assert(fences.isEmpty)
            
            argEncoder.setArgumentBuffer(storage.buffer, offset: storage.offset)
            argEncoder.encodeArguments(from: argumentBuffer, resourceRegistry: self, stateCaches: stateCaches)
            
//            #if os(macOS)
//            storage.buffer.didModifyRange(storage.offset..<(storage.offset + argEncoder.encodedLength))
//            #endif
            
            self.argumentBufferReferences[argumentBuffer] = storage
            self.argumentBufferWaitEvents[argumentBuffer] = waitEvent
            
            return storage
        }
    }
    
    @discardableResult
    func allocateArgumentBufferArrayIfNeeded(_ argumentBufferArray: _ArgumentBufferArray, stateCaches: MetalStateCaches) -> MTLBufferReference {
        return self.accessLock.withWriteLock {
            if let mtlArgumentBuffer = self.argumentBufferArrayReferences[argumentBufferArray] {
                return mtlArgumentBuffer
            }
            
            let argEncoder = Unmanaged<MTLArgumentEncoder>.fromOpaque(argumentBufferArray._bindings.first(where: { $0?.encoder != nil })!!.encoder!).takeUnretainedValue()
            let (storage, fences, waitEvent) = self.allocateArgumentBufferStorage(for: argumentBufferArray, encodedLength: argEncoder.encodedLength * argumentBufferArray._bindings.count)
            assert(fences.isEmpty)
            
            for (i, argumentBuffer) in argumentBufferArray._bindings.enumerated() {
                guard let argumentBuffer = argumentBuffer else { continue }
                
                argEncoder.setArgumentBuffer(storage.buffer, startOffset: storage.offset, arrayElement: i)
                
                argEncoder.encodeArguments(from: argumentBuffer, resourceRegistry: self, stateCaches: stateCaches)
                
                let localStorage = MTLBufferReference(buffer: storage._buffer, offset: storage.offset + i * argEncoder.encodedLength)
                self.argumentBufferReferences[argumentBuffer] = localStorage
                self.argumentBufferWaitEvents[argumentBuffer] = waitEvent
            }
            
//            #if os(macOS)
//            storage.buffer.didModifyRange(storage.offset..<(storage.offset + argEncoder.encodedLength * argumentBufferArray._bindings.count))
//            #endif
            
            self.argumentBufferArrayReferences[argumentBufferArray] = storage
            self.argumentBufferArrayWaitEvents[argumentBufferArray] = waitEvent
            
            return storage
        }
    }
    
    public func importExternalResource(_ resource: Resource, backingResource: Any) {
        self.prepareFrame()
        if let texture = resource.texture {
            self.textureReferences[texture] = MTLTextureReference(texture: Unmanaged.passRetained(backingResource as! MTLTexture))
        } else if let buffer = resource.buffer {
            self.bufferReferences[buffer] = MTLBufferReference(buffer: Unmanaged.passRetained(backingResource as! MTLBuffer), offset: 0)
        }
    }
    
    // These subscript methods should only be called after 'allocate' has been called.
    // If you hit an error here, check if you forgot to make a resource persistent.
    public subscript(texture: Texture) -> MTLTexture? {
        return self.textureReferences[texture]?.texture
    }
    
    public subscript(texture texture: Texture.Handle) -> MTLTexture? {
        return self.textureReferences[Texture(handle: texture)]!.texture
    }
    
    public subscript(textureReference texture: Texture) -> MTLTextureReference? {
        return self.textureReferences[texture]!
    }
    
    public subscript(textureReference texture: Texture.Handle) -> MTLTextureReference? {
        return self.textureReferences[Texture(handle: texture)]!
    }
    
    public subscript(buffer: Buffer) -> MTLBufferReference? {
        return self.bufferReferences[buffer]
    }
    
    public subscript(buffer buffer: Buffer.Handle) -> MTLBufferReference? {
        return self.bufferReferences[Buffer(handle: buffer)]
    }
    
    public subscript(argumentBuffer: _ArgumentBuffer) -> MTLBufferReference? {
        return self.argumentBufferReferences[argumentBuffer]
    }
    
    public subscript(argumentBufferArray: _ArgumentBufferArray) -> MTLBufferReference? {
        return self.argumentBufferArrayReferences[argumentBufferArray]
    }
    
    public func withHeapAliasingFencesIfPresent(for resourceHandle: Resource.Handle, perform: (inout [MetalFenceHandle]) -> Void) {
        let resource = Resource(handle: resourceHandle)
        
        perform(&self.heapResourceUsageFences[resource, default: []])
    }
    
    func setDisposalFences<R : ResourceProtocol>(on resource: R, to fences: [MetalFenceHandle]) {
        assert(self.isAliasedHeapResource(resource: Resource(resource)))
        self.heapResourceDisposalFences[Resource(resource)] = fences
    }
    
    func disposeTexture(_ texture: Texture, keepingReference: Bool, waitEvent: MetalWaitEvent) {
        if let mtlTexture = (keepingReference ? self.textureReferences[texture] : self.textureReferences.removeValue(forKey: texture)) {
            if texture.flags.contains(.windowHandle) {
                return
            }
            if texture.flags.contains(.externalOwnership) {
                mtlTexture._texture.release()
                return
            }
            if texture.isTextureView {
                mtlTexture._texture.release()
            }
            
            var fences : [MetalFenceHandle] = []
            if self.isAliasedHeapResource(resource: Resource(texture)) {
                fences = self.heapResourceDisposalFences[Resource(texture)] ?? []
            }
            
            let allocator = self.allocatorForTexture(storageMode: mtlTexture.texture.storageMode, flags: texture.flags, textureParams: (texture.descriptor.pixelFormat, mtlTexture.texture.usage))
            allocator.depositTexture(mtlTexture, fences: fences, waitEvent: waitEvent)
        }
    }
    
    func disposeBuffer(_ buffer: Buffer, keepingReference: Bool, waitEvent: MetalWaitEvent) {
        if let mtlBuffer = (keepingReference ? self.bufferReferences[buffer] : self.bufferReferences.removeValue(forKey: buffer)) {
            
            if buffer.flags.contains(.externalOwnership) {
                mtlBuffer._buffer.release()
                return
            }
            
            var fences : [MetalFenceHandle] = []
            if self.isAliasedHeapResource(resource: Resource(buffer)) {
                fences = self.heapResourceDisposalFences[Resource(buffer)] ?? []
            }
            
            let allocator = self.allocatorForBuffer(length: buffer.descriptor.length, storageMode: buffer.descriptor.storageMode, cacheMode: buffer.descriptor.cacheMode, flags: buffer.flags)
            allocator.depositBuffer(mtlBuffer, fences: fences, waitEvent: waitEvent)
        }
    }
    
    func disposeArgumentBuffer(_ buffer: _ArgumentBuffer, keepingReference: Bool, waitEvent: MetalWaitEvent) {
        if buffer.flags.contains(.persistent) {
            print("Disposing \(buffer)")
        }
        if let mtlBuffer = (keepingReference ? self.argumentBufferReferences[buffer] : self.argumentBufferReferences.removeValue(forKey: buffer)) {
            let allocator = self.allocatorForArgumentBuffer(flags: buffer.flags)
            
            assert(buffer.sourceArray == nil || !buffer.flags.contains(.persistent), "Persistent argument buffers from an argument buffer array should not be disposed individually; this needs to be fixed within the Metal FrameGraph backend.")
            allocator.depositBuffer(mtlBuffer, fences: [], waitEvent: waitEvent)
        }
    }
    
    func disposeArgumentBufferArray(_ buffer: _ArgumentBufferArray, keepingReference: Bool, waitEvent: MetalWaitEvent) {
        if let mtlBuffer = (keepingReference ? self.argumentBufferArrayReferences[buffer] : self.argumentBufferArrayReferences.removeValue(forKey: buffer)) {
            
            let allocator = self.allocatorForArgumentBuffer(flags: buffer.flags)
            allocator.depositBuffer(mtlBuffer, fences: [], waitEvent: waitEvent)
        }
    }
    
    func bufferContents(for buffer: Buffer) -> UnsafeMutableRawPointer {
        assert(buffer.flags.contains(.persistent) || self.frameGraphHasResourceAccess, "GPU memory for a transient buffer may not be accessed outside of a FrameGraph RenderPass. Consider using withDeferredSlice instead.")
        
        let bufferReference = self.allocateBufferIfNeeded(buffer)
        return bufferReference.buffer.contents() + bufferReference.offset
    }
    
    func copyTextureBytes(from texture: Texture, to bytes: UnsafeMutableRawPointer, bytesPerRow: Int, region: Region, mipmapLevel: Int) {
        assert(texture.flags.contains(.persistent) || self.frameGraphHasResourceAccess, "GPU memory for a transient texture may not be accessed outside of a FrameGraph RenderPass.")
        
        self.allocateTextureIfNeeded(texture, usage: MetalTextureUsageProperties(texture.descriptor.usageHint))
        self[texture]!.getBytes(bytes, bytesPerRow: bytesPerRow, from: MTLRegion(region), mipmapLevel: mipmapLevel)
    }
    
    func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) {
        assert(texture.flags.contains(.persistent) || self.frameGraphHasResourceAccess, "GPU memory for a transient texture may not be accessed outside of a FrameGraph RenderPass.")
        
        self.allocateTextureIfNeeded(texture, usage: MetalTextureUsageProperties(texture.descriptor.usageHint))
        self[texture]!.replace(region: MTLRegion(region), mipmapLevel: mipmapLevel, withBytes: bytes, bytesPerRow: bytesPerRow)
    }
    
    func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, slice: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int) {
        assert(texture.flags.contains(.persistent) || self.frameGraphHasResourceAccess, "GPU memory for a transient texture may not be accessed outside of a FrameGraph RenderPass.")
        
        self.allocateTextureIfNeeded(texture, usage: MetalTextureUsageProperties(texture.descriptor.usageHint))
        self[texture]!.replace(region: MTLRegion(region), mipmapLevel: mipmapLevel, slice: slice, withBytes: bytes, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerImage)
    }
    
    func registerInitialisedHistoryBufferForDisposal(resource: Resource) {
        assert(resource.flags.contains(.historyBuffer) && resource.stateFlags.contains(.initialised))
        resource.dispose() // This will dispose it in the FrameGraph persistent allocator, which will in turn call dispose here at the end of the frame.
    }
    
    func clearDrawables() {
        self.frameDrawables.removeAll(keepingCapacity: true)
    }
    
    func cycleFrames() {
        // Clear all transient resources at the end of the frame.
        
        self.textureReferences.removeAllTransient()
        self.bufferReferences.removeAllTransient()
        self.argumentBufferReferences.removeAllTransient()
        self.argumentBufferArrayReferences.removeAllTransient()
        
        self.heapResourceUsageFences.removeAll(keepingCapacity: true)
        self.heapResourceDisposalFences.removeAll(keepingCapacity: true)
        
        self.stagingTextureAllocator.cycleFrames()
        self.privateAllocator.cycleFrames()
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
        
        MetalFenceRegistry.instance.cycleFrames()
    }
}

#endif // canImport(Metal)
