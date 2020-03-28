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

/// The value to wait for on the event associated with this FrameGraph context.
struct MetalContextWaitEvent {
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

struct MetalFrameResourceMap {
    let persistentRegistry : MetalPersistentResourceRegistry
    let transientRegistry : MetalTransientResourceRegistry
    
    subscript(buffer: Buffer) -> MTLBufferReference {
        if buffer._usesPersistentRegistry {
            return persistentRegistry[buffer]!
        } else {
            return transientRegistry[buffer]!
        }
    }
    
    subscript(texture: Texture) -> MTLTexture {
        if texture._usesPersistentRegistry {
            return persistentRegistry[texture]!
        } else {
            return transientRegistry[texture]!
        }
    }
    
    subscript(buffer: _ArgumentBuffer) -> MTLBufferReference {
        if buffer._usesPersistentRegistry {
            return persistentRegistry[buffer]!
        } else {
            return transientRegistry[buffer]!
        }
    }
    
    subscript(buffer: _ArgumentBufferArray) -> MTLBufferReference {
        if buffer._usesPersistentRegistry {
            return persistentRegistry[buffer]!
        } else {
            return transientRegistry[buffer]!
        }
    }
    
    func bufferForCPUAccess(_ buffer: Buffer) -> MTLBufferReference {
        if buffer._usesPersistentRegistry {
            return persistentRegistry[buffer]!
        } else {
            return transientRegistry.accessLock.withLock { transientRegistry.allocateBufferIfNeeded(buffer) }
        }
    }
    
    func textureForCPUAccess(_ texture: Texture) -> MTLTexture {
        if texture._usesPersistentRegistry {
            return persistentRegistry[texture]!
        } else {
            return transientRegistry.accessLock.withLock { transientRegistry.allocateTextureIfNeeded(texture, usage: MetalTextureUsageProperties(texture.descriptor.usageHint))! }
        }
    }
    
    func renderTargetTexture(_ texture: Texture) throws -> MTLTexture {
        if texture.flags.contains(.windowHandle) {
            return try self.transientRegistry.allocateWindowHandleTexture(texture, persistentRegistry: persistentRegistry)
        }
        return self[texture]
    }
}

final class MetalPersistentResourceRegistry {
    var accessLock = ReaderWriterLock()
    
    var heapReferences = PersistentResourceMap<Heap, MTLHeap>()
    var textureReferences = PersistentResourceMap<Texture, MTLTextureReference>()
    var bufferReferences = PersistentResourceMap<Buffer, MTLBufferReference>()
    var argumentBufferReferences = PersistentResourceMap<_ArgumentBuffer, MTLBufferReference>() 
    var argumentBufferArrayReferences = PersistentResourceMap<_ArgumentBufferArray, MTLBufferReference>() 
    
    var windowReferences = [Texture : CAMetalLayer]()
    
    private let device : MTLDevice
    
    public init(device: MTLDevice) {
        self.device = device
        
        self.prepareFrame()
        MetalFenceRegistry.instance.device = self.device
    }
    
    deinit {
        self.heapReferences.deinit()
        self.textureReferences.deinit()
        self.bufferReferences.deinit()
        self.argumentBufferReferences.deinit()
        self.argumentBufferArrayReferences.deinit()
    }
    
    public func prepareFrame() {
        MetalFenceRegistry.instance.clearCompletedFences()
    }
    
    public func registerWindowTexture(texture: Texture, context: Any) {
        self.windowReferences[texture] = (context as! CAMetalLayer)
    }
    
    @discardableResult
    public func allocateHeap(_ heap: Heap) -> MTLHeap? {
        precondition(heap._usesPersistentRegistry)
        
        let descriptor = MTLHeapDescriptor(heap.descriptor)
        
        let mtlHeap = self.device.makeHeap(descriptor: descriptor)
        
        assert(self.heapReferences[heap] == nil)
        self.heapReferences[heap] = mtlHeap
        
        return mtlHeap
    }
    
    @discardableResult
    public func allocateTexture(_ texture: Texture, properties: MetalTextureUsageProperties) -> MTLTexture? {
        precondition(texture._usesPersistentRegistry)
        
        if texture.flags.contains(.windowHandle) {
            // Reserve a slot in texture references so we can later insert the texture reference in a thread-safe way, but don't actually allocate anything yet
            self.textureReferences[texture] = MTLTextureReference(windowTexture: ())
            return nil
        }
        
        // NOTE: all synchronisation is managed through the per-queue waitIndices associated with the resource.
        
        let descriptor = MTLTextureDescriptor(texture.descriptor, usage: properties.usage)
        
        let mtlTexture : MTLTextureReference
        if let heap = texture.heap {
            guard let mtlHeap = self.heapReferences[heap] else {
                print("Warning: requested heap \(heap) for texture \(texture) is invalid.")
                return nil
            }
            guard let texture = mtlHeap.makeTexture(descriptor: descriptor) else { return nil }
            mtlTexture = MTLTextureReference(texture: Unmanaged<MTLTexture>.passRetained(texture))
        } else {
            guard let texture = self.device.makeTexture(descriptor: descriptor) else { return nil }
            mtlTexture = MTLTextureReference(texture: Unmanaged<MTLTexture>.passRetained(texture))
        }
        
        if let label = texture.label {
            mtlTexture.texture.label = label
        }
        
        assert(self.textureReferences[texture] == nil)
        self.textureReferences[texture] = mtlTexture
        
        return mtlTexture.texture
    }
    
    @discardableResult
    public func allocateBuffer(_ buffer: Buffer) -> MTLBufferReference? {
        precondition(buffer._usesPersistentRegistry)
        
        // NOTE: all synchronisation is managed through the per-queue waitIndices associated with the resource.
        
        let options = MTLResourceOptions(storageMode: buffer.descriptor.storageMode, cacheMode: buffer.descriptor.cacheMode)
        
        let mtlBuffer : MTLBufferReference
        
        if let heap = buffer.heap {
            guard let mtlHeap = self.heapReferences[heap] else {
                print("Warning: requested heap \(heap) for buffer \(buffer) is invalid.")
                return nil
            }
            guard let buffer = mtlHeap.makeBuffer(length: buffer.descriptor.length, options: options) else { return nil }
            mtlBuffer = MTLBufferReference(buffer: Unmanaged<MTLBuffer>.passRetained(buffer), offset: 0)
        } else {
            guard let buffer = self.device.makeBuffer(length: buffer.descriptor.length, options: options) else { return nil }
            mtlBuffer = MTLBufferReference(buffer: Unmanaged<MTLBuffer>.passRetained(buffer), offset: 0)
        }
        
        if let label = buffer.label {
            mtlBuffer.buffer.label = label
        }
        
        assert(self.bufferReferences[buffer] == nil)
        self.bufferReferences[buffer] = mtlBuffer
        
        return mtlBuffer
    }
    
    func allocateArgumentBufferStorage<A : ResourceProtocol>(for argumentBuffer: A, encodedLength: Int) -> MTLBufferReference {
//        #if os(macOS)
//        let options : MTLResourceOptions = [.storageModeManaged, .frameGraphTrackedHazards]
//        #else
        let options : MTLResourceOptions = [.storageModeShared, .frameGraphTrackedHazards]
//        #endif
        
        return MTLBufferReference(buffer: Unmanaged.passRetained(self.device.makeBuffer(length: encodedLength, options: options)!), offset: 0)
    }
    
    @discardableResult
    func allocateArgumentBufferIfNeeded(_ argumentBuffer: _ArgumentBuffer) -> MTLBufferReference {
        if let baseArray = argumentBuffer.sourceArray {
            _ = self.allocateArgumentBufferArrayIfNeeded(baseArray)
            return self.argumentBufferReferences[argumentBuffer]!
        }
        if let mtlArgumentBuffer = self.argumentBufferReferences[argumentBuffer] {
            return mtlArgumentBuffer
        }
        
        let argEncoder = Unmanaged<MTLArgumentEncoder>.fromOpaque(argumentBuffer.encoder!).takeUnretainedValue()
        let storage = self.allocateArgumentBufferStorage(for: argumentBuffer, encodedLength: argEncoder.encodedLength)
        
        self.argumentBufferReferences[argumentBuffer] = storage
        
        return storage
    }
    
    @discardableResult
    func allocateArgumentBufferArrayIfNeeded(_ argumentBufferArray: _ArgumentBufferArray) -> MTLBufferReference {
        if let mtlArgumentBuffer = self.argumentBufferArrayReferences[argumentBufferArray] {
            return mtlArgumentBuffer
        }
        
        let argEncoder = Unmanaged<MTLArgumentEncoder>.fromOpaque(argumentBufferArray._bindings.first(where: { $0?.encoder != nil })!!.encoder!).takeUnretainedValue()
        let storage = self.allocateArgumentBufferStorage(for: argumentBufferArray, encodedLength: argEncoder.encodedLength * argumentBufferArray._bindings.count)
        
        for (i, argumentBuffer) in argumentBufferArray._bindings.enumerated() {
            guard let argumentBuffer = argumentBuffer else { continue }
            
            let localStorage = MTLBufferReference(buffer: storage._buffer, offset: storage.offset + i * argEncoder.encodedLength)
            self.argumentBufferReferences[argumentBuffer] = localStorage
        }
        
        self.argumentBufferArrayReferences[argumentBufferArray] = storage
        
        return storage
    }
    
    public func importExternalResource(_ resource: Resource, backingResource: Any) {
        self.prepareFrame()
        if let texture = resource.texture {
            self.textureReferences[texture] = MTLTextureReference(texture: Unmanaged.passRetained(backingResource as! MTLTexture))
        } else if let buffer = resource.buffer {
            self.bufferReferences[buffer] = MTLBufferReference(buffer: Unmanaged.passRetained(backingResource as! MTLBuffer), offset: 0)
        }
    }
    
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

    func disposeHeap(_ heap: Heap) {
        self.heapReferences.removeValue(forKey: heap)
    }
    
    func disposeTexture(_ texture: Texture) {
        if let mtlTexture = self.textureReferences.removeValue(forKey: texture) {
            if texture.flags.contains(.windowHandle) {
                return
            }
            
            mtlTexture._texture.release()
        }
    }
    
    func disposeBuffer(_ buffer: Buffer) {
        if let mtlBuffer = self.bufferReferences.removeValue(forKey: buffer) {
            mtlBuffer._buffer.release()
        }
    }
    
    func disposeArgumentBuffer(_ buffer: _ArgumentBuffer) {
        if let mtlBuffer = self.argumentBufferReferences.removeValue(forKey: buffer) {
            assert(buffer.sourceArray == nil, "Persistent argument buffers from an argument buffer array should not be disposed individually; this needs to be fixed within the Metal FrameGraph backend.")
            mtlBuffer._buffer.release()
        }
    }
    
    func disposeArgumentBufferArray(_ buffer: _ArgumentBufferArray) {
        if let mtlBuffer = self.argumentBufferArrayReferences.removeValue(forKey: buffer) {
            mtlBuffer._buffer.release()
        }
    }
}


final class MetalTransientResourceRegistry {
    let persistentRegistry : MetalPersistentResourceRegistry
    var accessLock = SpinLock()
    
    private var textureReferences : TransientResourceMap<Texture, MTLTextureReference>
    private var bufferReferences : TransientResourceMap<Buffer, MTLBufferReference>
    private var argumentBufferReferences : TransientResourceMap<_ArgumentBuffer, MTLBufferReference>
    private var argumentBufferArrayReferences : TransientResourceMap<_ArgumentBufferArray, MTLBufferReference>
    
    var textureWaitEvents : TransientResourceMap<Texture, MetalContextWaitEvent>
    var bufferWaitEvents : TransientResourceMap<Buffer, MetalContextWaitEvent>
    var argumentBufferWaitEvents : TransientResourceMap<_ArgumentBuffer, MetalContextWaitEvent>
    var argumentBufferArrayWaitEvents : TransientResourceMap<_ArgumentBufferArray, MetalContextWaitEvent>
    var historyBufferResourceWaitEvents = [Resource : MetalContextWaitEvent]() // since history buffers use the persistent (rather than transient) resource maps.
    
    private var heapResourceUsageFences = [Resource : [FenceDependency]]()
    private var heapResourceDisposalFences = [Resource : [FenceDependency]]()
    
    private let frameSharedBufferAllocator : MetalTemporaryBufferAllocator
    private let frameSharedWriteCombinedBufferAllocator : MetalTemporaryBufferAllocator
    
    #if os(macOS)
    private let frameManagedBufferAllocator : MetalTemporaryBufferAllocator
    private let frameManagedWriteCombinedBufferAllocator : MetalTemporaryBufferAllocator
    #endif
    
    private let historyBufferAllocator : MetalPoolResourceAllocator
    
    #if !os(macOS)
    private let memorylessTextureAllocator : MetalPoolResourceAllocator
    #endif
    
    private let frameArgumentBufferAllocator : MetalTemporaryBufferAllocator
    
    private let stagingTextureAllocator : MetalPoolResourceAllocator
    private let privateAllocator : MetalHeapResourceAllocator
    
    private let colorRenderTargetAllocator : MetalHeapResourceAllocator
    private let depthRenderTargetAllocator : MetalHeapResourceAllocator
    
    public private(set) var frameDrawables : [CAMetalDrawable] = []
    
    public init(device: MTLDevice, inflightFrameCount: Int, transientRegistryIndex: Int, persistentRegistry: MetalPersistentResourceRegistry) {
        self.persistentRegistry = persistentRegistry
        
        self.textureReferences = .init(transientRegistryIndex: transientRegistryIndex)
        self.bufferReferences = .init(transientRegistryIndex: transientRegistryIndex)
        self.argumentBufferReferences = .init(transientRegistryIndex: transientRegistryIndex)
        self.argumentBufferArrayReferences = .init(transientRegistryIndex: transientRegistryIndex)
        
        self.textureWaitEvents = .init(transientRegistryIndex: transientRegistryIndex)
        self.bufferWaitEvents = .init(transientRegistryIndex: transientRegistryIndex)
        self.argumentBufferWaitEvents = .init(transientRegistryIndex: transientRegistryIndex)
        self.argumentBufferArrayWaitEvents = .init(transientRegistryIndex: transientRegistryIndex)
        
        self.stagingTextureAllocator = MetalPoolResourceAllocator(device: device, numFrames: inflightFrameCount)
        self.historyBufferAllocator = MetalPoolResourceAllocator(device: device, numFrames: 1)
        
        self.frameSharedBufferAllocator = MetalTemporaryBufferAllocator(device: device, numFrames: inflightFrameCount, blockSize: 256 * 1024, options: [.storageModeShared, .frameGraphTrackedHazards])
        self.frameSharedWriteCombinedBufferAllocator = MetalTemporaryBufferAllocator(device: device, numFrames: inflightFrameCount, blockSize: 2 * 1024 * 1024, options: [.storageModeShared, .cpuCacheModeWriteCombined, .frameGraphTrackedHazards])
        
        #if os(macOS)
        self.frameManagedBufferAllocator = MetalTemporaryBufferAllocator(device: device, numFrames: inflightFrameCount, blockSize: 1024 * 1024, options: [.storageModeManaged, .frameGraphTrackedHazards])
        self.frameManagedWriteCombinedBufferAllocator = MetalTemporaryBufferAllocator(device: device, numFrames: inflightFrameCount, blockSize: 2 * 1024 * 1024, options: [.storageModeManaged, .cpuCacheModeWriteCombined, .frameGraphTrackedHazards])
        self.frameArgumentBufferAllocator = MetalTemporaryBufferAllocator(device: device, numFrames: inflightFrameCount, blockSize: 2 * 1024 * 1024, options: [.storageModeShared, .frameGraphTrackedHazards])
        #else
        self.frameArgumentBufferAllocator = MetalTemporaryBufferAllocator(device: device, numFrames: inflightFrameCount, blockSize: 2 * 1024 * 1024, options: [.storageModeShared, .frameGraphTrackedHazards])
        self.memorylessTextureAllocator = MetalPoolResourceAllocator(device: device, numFrames: 1)
        #endif
        
        self.privateAllocator = MetalHeapResourceAllocator(device: device)
        self.depthRenderTargetAllocator = MetalHeapResourceAllocator(device: device)
        self.colorRenderTargetAllocator = MetalHeapResourceAllocator(device: device)
        
        self.prepareFrame()
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
        MetalFenceRegistry.instance.clearCompletedFences()

        self.textureReferences.prepareFrame()
        self.bufferReferences.prepareFrame()
        self.argumentBufferReferences.prepareFrame()
        self.argumentBufferArrayReferences.prepareFrame()
        
        self.textureWaitEvents.prepareFrame()
        self.bufferWaitEvents.prepareFrame()
        self.argumentBufferWaitEvents.prepareFrame()
        self.argumentBufferArrayWaitEvents.prepareFrame()
    }
    
    func allocatorForTexture(storageMode: MTLStorageMode, flags: ResourceFlags, textureParams: (PixelFormat, MTLTextureUsage)) -> MetalTextureAllocator {
        assert(!flags.contains(.persistent))
        
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
        assert(!flags.contains(.persistent))
        
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
        assert(!flags.contains(.persistent))
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
        
        if texture._usesPersistentRegistry {
            precondition(texture.flags.contains(.historyBuffer))
            self.persistentRegistry.textureReferences[texture] = mtlTexture
            self.historyBufferResourceWaitEvents[Resource(texture)] = waitEvent
        } else {
            precondition(self.textureReferences[texture] == nil)
            self.textureReferences[texture] = mtlTexture
            self.textureWaitEvents[texture] = waitEvent
        }
        
        
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
    public func allocateWindowHandleTexture(_ texture: Texture, persistentRegistry: MetalPersistentResourceRegistry) throws -> MTLTexture {
        precondition( texture.flags.contains(.windowHandle))
        
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
                
                guard let windowReference = persistentRegistry.windowReferences.removeValue(forKey: texture),
                    let mtlDrawable = windowReference.nextDrawable() else {
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
    
    @discardableResult
    public func allocateBuffer(_ buffer: Buffer) -> MTLBufferReference? {
        var options = MTLResourceOptions(storageMode: buffer.descriptor.storageMode, cacheMode: buffer.descriptor.cacheMode)
        if buffer.descriptor.usageHint.contains(.textureView) {
            options.remove(.frameGraphTrackedHazards) // FIXME: workaround for a bug in Metal where setting hazardTrackingModeUntracked on a MTLTextureDescriptor doesn't stick
        }
        

        let allocator = self.allocatorForBuffer(length: buffer.descriptor.length, storageMode: buffer.descriptor.storageMode, cacheMode: buffer.descriptor.cacheMode, flags: buffer.flags)
        let (mtlBuffer, fences, waitEvent) = allocator.collectBufferWithLength(buffer.descriptor.length, options: options)
        
        if let label = buffer.label {
            mtlBuffer.buffer.label = label
        }
        
        if buffer._usesPersistentRegistry {
            precondition(buffer.flags.contains(.historyBuffer))
            self.persistentRegistry.bufferReferences[buffer] = mtlBuffer
            self.historyBufferResourceWaitEvents[Resource(buffer)] = waitEvent
        } else {
            precondition(self.bufferReferences[buffer] == nil)
            self.bufferReferences[buffer] = mtlBuffer
            self.bufferWaitEvents[buffer] = waitEvent
        }
        
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
        return self.allocateBuffer(buffer)!
    }
    
    @discardableResult
    public func allocateTextureIfNeeded(_ texture: Texture, usage: MetalTextureUsageProperties) -> MTLTexture? {
        if let mtlTexture = self.textureReferences[texture]?.texture {
            assert(mtlTexture.pixelFormat == MTLPixelFormat(texture.descriptor.pixelFormat))
            return mtlTexture
        }
        return self.allocateTexture(texture, properties: usage)
    }
    
    func allocateArgumentBufferStorage<A : ResourceProtocol>(for argumentBuffer: A, encodedLength: Int) -> (MTLBufferReference, [FenceDependency], MetalContextWaitEvent) {
//        #if os(macOS)
//        let options : MTLResourceOptions = [.storageModeManaged, .frameGraphTrackedHazards]
//        #else
        let options : MTLResourceOptions = [.storageModeShared, .frameGraphTrackedHazards]
//        #endif
        
        let allocator = self.allocatorForArgumentBuffer(flags: argumentBuffer.flags)
        return allocator.collectBufferWithLength(encodedLength, options: options)
    }
    
    @discardableResult
    func allocateArgumentBufferIfNeeded(_ argumentBuffer: _ArgumentBuffer) -> MTLBufferReference {
        if let baseArray = argumentBuffer.sourceArray {
            _ = self.allocateArgumentBufferArrayIfNeeded(baseArray)
            return self.argumentBufferReferences[argumentBuffer]!
        }
        if let mtlArgumentBuffer = self.argumentBufferReferences[argumentBuffer] {
            return mtlArgumentBuffer
        }
        
        let argEncoder = Unmanaged<MTLArgumentEncoder>.fromOpaque(argumentBuffer.encoder!).takeUnretainedValue()
        let (storage, fences, waitEvent) = self.allocateArgumentBufferStorage(for: argumentBuffer, encodedLength: argEncoder.encodedLength)
        assert(fences.isEmpty)
        
        self.argumentBufferReferences[argumentBuffer] = storage
        self.argumentBufferWaitEvents[argumentBuffer] = waitEvent
        
        return storage
    }
    
    @discardableResult
    func allocateArgumentBufferArrayIfNeeded(_ argumentBufferArray: _ArgumentBufferArray) -> MTLBufferReference {
        if let mtlArgumentBuffer = self.argumentBufferArrayReferences[argumentBufferArray] {
            return mtlArgumentBuffer
        }
        
        let argEncoder = Unmanaged<MTLArgumentEncoder>.fromOpaque(argumentBufferArray._bindings.first(where: { $0?.encoder != nil })!!.encoder!).takeUnretainedValue()
        let (storage, fences, waitEvent) = self.allocateArgumentBufferStorage(for: argumentBufferArray, encodedLength: argEncoder.encodedLength * argumentBufferArray._bindings.count)
        assert(fences.isEmpty)
        
        for (i, argumentBuffer) in argumentBufferArray._bindings.enumerated() {
            guard let argumentBuffer = argumentBuffer else { continue }
            
            let localStorage = MTLBufferReference(buffer: storage._buffer, offset: storage.offset + i * argEncoder.encodedLength)
            self.argumentBufferReferences[argumentBuffer] = localStorage
            self.argumentBufferWaitEvents[argumentBuffer] = waitEvent
        }
        
        self.argumentBufferArrayReferences[argumentBufferArray] = storage
        self.argumentBufferArrayWaitEvents[argumentBufferArray] = waitEvent
        
        return storage
    }
    
    public func importExternalResource(_ resource: Resource, backingResource: Any) {
        self.prepareFrame()
        if let texture = resource.texture {
            self.textureReferences[texture] = MTLTextureReference(texture: Unmanaged.passRetained(backingResource as! MTLTexture))
        } else if let buffer = resource.buffer {
            self.bufferReferences[buffer] = MTLBufferReference(buffer: Unmanaged.passRetained(backingResource as! MTLBuffer), offset: 0)
        }
    }
    
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
    
    public func withHeapAliasingFencesIfPresent(for resourceHandle: Resource.Handle, perform: (inout [FenceDependency]) -> Void) {
        let resource = Resource(handle: resourceHandle)
        
        perform(&self.heapResourceUsageFences[resource, default: []])
    }
    
    func setDisposalFences<R : ResourceProtocol>(on resource: R, to fences: [FenceDependency]) {
        assert(self.isAliasedHeapResource(resource: Resource(resource)))
        self.heapResourceDisposalFences[Resource(resource)] = fences
    }
    
    func disposeTexture(_ texture: Texture, waitEvent: MetalContextWaitEvent) {
        // We keep the reference around until the end of the frame since allocation/disposal is all processed ahead of time.
        
        let textureRef : MTLTextureReference?
        if texture._usesPersistentRegistry {
            precondition(texture.flags.contains(.historyBuffer))
            textureRef = self.persistentRegistry.textureReferences[texture]
            _ = textureRef?._texture.retain() // since the persistent registry releases its resources unconditionally on dispose, but we want the allocator to have ownership of it.
        } else {
            textureRef = self.textureReferences[texture]
        }
        
        if let mtlTexture = textureRef {
            if texture.flags.contains(.windowHandle) {
                return
            }
            if texture.isTextureView {
                mtlTexture._texture.release()
            }
            
            var fences : [FenceDependency] = []
            if self.isAliasedHeapResource(resource: Resource(texture)) {
                fences = self.heapResourceDisposalFences[Resource(texture)] ?? []
            }
            
            let allocator = self.allocatorForTexture(storageMode: mtlTexture.texture.storageMode, flags: texture.flags, textureParams: (texture.descriptor.pixelFormat, mtlTexture.texture.usage))
            allocator.depositTexture(mtlTexture, fences: fences, waitEvent: waitEvent)
        }
    }
    
    func disposeBuffer(_ buffer: Buffer, waitEvent: MetalContextWaitEvent) {
        // We keep the reference around until the end of the frame since allocation/disposal is all processed ahead of time.
        
        let bufferRef : MTLBufferReference?
        if buffer._usesPersistentRegistry {
            precondition(buffer.flags.contains(.historyBuffer))
            bufferRef = self.persistentRegistry.bufferReferences[buffer]
            _ = bufferRef?._buffer.retain() // since the persistent registry releases its resources unconditionally on dispose, but we want the allocator to have ownership of it.
        } else {
            bufferRef = self.bufferReferences[buffer]
        }
        
        if let mtlBuffer = bufferRef {
            var fences : [FenceDependency] = []
            if self.isAliasedHeapResource(resource: Resource(buffer)) {
                fences = self.heapResourceDisposalFences[Resource(buffer)] ?? []
            }
            
            let allocator = self.allocatorForBuffer(length: buffer.descriptor.length, storageMode: buffer.descriptor.storageMode, cacheMode: buffer.descriptor.cacheMode, flags: buffer.flags)
            allocator.depositBuffer(mtlBuffer, fences: fences, waitEvent: waitEvent)
        }
    }
    
    func disposeArgumentBuffer(_ buffer: _ArgumentBuffer, waitEvent: MetalContextWaitEvent) {
        if let mtlBuffer = self.argumentBufferReferences[buffer] {
            let allocator = self.allocatorForArgumentBuffer(flags: buffer.flags)
            allocator.depositBuffer(mtlBuffer, fences: [], waitEvent: waitEvent)
        }
    }
    
    func disposeArgumentBufferArray(_ buffer: _ArgumentBufferArray, waitEvent: MetalContextWaitEvent) {
        if let mtlBuffer = self.argumentBufferArrayReferences[buffer] {
            let allocator = self.allocatorForArgumentBuffer(flags: buffer.flags)
            allocator.depositBuffer(mtlBuffer, fences: [], waitEvent: waitEvent)
        }
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
        
        self.textureReferences.removeAll()
        self.bufferReferences.removeAll()
        self.argumentBufferReferences.removeAll()
        self.argumentBufferArrayReferences.removeAll()
        
        self.heapResourceUsageFences.removeAll(keepingCapacity: true)
        self.heapResourceDisposalFences.removeAll(keepingCapacity: true)
        
        self.stagingTextureAllocator.cycleFrames()
        self.privateAllocator.cycleFrames()
        self.historyBufferAllocator.cycleFrames()
        
        self.colorRenderTargetAllocator.cycleFrames()
        self.depthRenderTargetAllocator.cycleFrames()
        
        self.frameSharedBufferAllocator.cycleFrames()
        self.frameSharedWriteCombinedBufferAllocator.cycleFrames()
        
        #if os(macOS)
        self.frameManagedBufferAllocator.cycleFrames()
        self.frameManagedWriteCombinedBufferAllocator.cycleFrames()
        #elseif os(iOS)
        self.memorylessTextureAllocator.cycleFrames()
        #endif
        
        self.frameArgumentBufferAllocator.cycleFrames()
    }
}

#endif // canImport(Metal)
