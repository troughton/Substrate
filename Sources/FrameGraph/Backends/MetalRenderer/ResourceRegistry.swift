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

class MTLBufferReference {
    let buffer : MTLBuffer
    let offset : Int
    
    /// The fence to wait on before reading from the buffer.
    var readWaitFence : MTLFence? = nil
    
    /// The fences to wait on before writing to the buffer
    var writeWaitFences : [MTLFence]? = nil
    
    init(buffer: MTLBuffer, offset: Int) {
        self.buffer = buffer
        self.offset = offset
    }
}

class MTLTextureReference {
    let texture : MTLTexture
    
    /// The fence to wait on before reading from the texture.
    var readWaitFence : MTLFence? = nil
    
    /// The fences to wait on before writing to the texture.
    var writeWaitFences : [MTLFence]? = nil
    
    init(texture: MTLTexture) {
        self.texture = texture
    }
}

final class ResourceRegistry {
    
    private var textureReferences = [ResourceProtocol.Handle : MTLTextureReference]()
    private var bufferReferences = [ResourceProtocol.Handle : MTLBufferReference]()
    
    private var windowReferences = [ResourceProtocol.Handle : MTKView]()
    
    private var fenceMappings = [Int : MTLFence]()
    private var unusedFences = [MTLFence]()
    private var fenceRetainCounts = [ObjectIdentifier : Int]()
    
    private let device : MTLDevice
    
    private let frameSharedBufferAllocator : TemporaryBufferAllocator
    private let frameSharedWriteCombinedBufferAllocator : TemporaryBufferAllocator
    private let frameManagedBufferAllocator : TemporaryBufferAllocator
    private let frameManagedWriteCombinedBufferAllocator : TemporaryBufferAllocator
    
    private let stagingTextureAllocator : PoolResourceAllocator
    private let privateAllocator : PoolResourceAllocator //HeapResourceAllocator
    
    // A double-buffered allocator for small per-frame private resources.
    private let smallPrivateAllocator : TemporaryBufferAllocator //MultiFrameHeapResourceAllocator
    private let smallAllocationThreshold = 2 * 1024 * 1024 // 2MB
    
    private let colorRenderTargetAllocator : PoolResourceAllocator // HeapResourceAllocator
    private let depthRenderTargetAllocator : PoolResourceAllocator // HeapResourceAllocator
    
    private let historyBufferAllocator : PoolResourceAllocator
    private let persistentAllocator : PersistentResourceAllocator
    
    private var frameCPUBuffers = [Buffer]()
    private var frameCPUTextures = [Texture]()
    private var frameArgumentBuffers = [ResourceProtocol.Handle]()
    
    public private(set) var frameDrawables : [MTLDrawable] = []
    
    public var frameGraphHasResourceAccess = false
    
    public init(device: MTLDevice, numInflightFrames: Int) {
        self.device = device
        
        self.stagingTextureAllocator = PoolResourceAllocator(device: device, numFrames: numInflightFrames)
        self.historyBufferAllocator = PoolResourceAllocator(device: device, numFrames: 1)
        
        self.persistentAllocator = PersistentResourceAllocator(device: device)
        
        self.frameSharedBufferAllocator = TemporaryBufferAllocator(device: device, numFrames: numInflightFrames, blockSize: 256 * 1024, options: .storageModeShared)
        self.frameSharedWriteCombinedBufferAllocator = TemporaryBufferAllocator(device: device, numFrames: numInflightFrames, blockSize: 2 * 1024 * 1024, options: [.storageModeShared, .cpuCacheModeWriteCombined])
        self.frameManagedBufferAllocator = TemporaryBufferAllocator(device: device, numFrames: numInflightFrames, blockSize: 1024 * 1024, options: .storageModeManaged)
        self.frameManagedWriteCombinedBufferAllocator = TemporaryBufferAllocator(device: device, numFrames: numInflightFrames, blockSize: 2 * 1024 * 1024, options: [.storageModeManaged, .cpuCacheModeWriteCombined])
        
        let heapDescriptor = MTLHeapDescriptor()
        heapDescriptor.size = 1 << 24 // A 16MB heap
        heapDescriptor.storageMode = .private
        self.privateAllocator = PoolResourceAllocator(device: device, numFrames: 1) // HeapResourceAllocator(device: device, defaultDescriptor: heapDescriptor, framePurgeability: .empty)
        
        // The small private allocator is multi-buffered to avoid the need for fence waits.
        self.smallPrivateAllocator = TemporaryBufferAllocator(device: device, numFrames: 2, blockSize: 4 * smallAllocationThreshold, options: .storageModePrivate) // MultiFrameHeapResourceAllocator(device: device, defaultDescriptor: heapDescriptor, framePurgeability: .empty, numFrames: 2)
        
        heapDescriptor.size = 40_000_000 // A 40MB heap
        self.depthRenderTargetAllocator = PoolResourceAllocator(device: device, numFrames: 1) // HeapResourceAllocator(device: device, defaultDescriptor: heapDescriptor, framePurgeability: .empty)
        
        heapDescriptor.size = 200_000_000 // A 200MB heap
        self.colorRenderTargetAllocator = PoolResourceAllocator(device: device, numFrames: 1) // HeapResourceAllocator(device: device, defaultDescriptor: heapDescriptor, framePurgeability: .empty)
    }
    
    public func registerWindowTexture(texture: Texture, context: Any) {
        self.windowReferences[texture.handle] = (context as! MTKView)
    }
    
    func allocatorForTexture(storageMode: StorageMode, flags: ResourceFlags, textureParams: (PixelFormat, MTLTextureUsage)) -> TextureAllocator {
        
        if flags.contains(.persistent) {
            return self.persistentAllocator
        }
        if flags.contains(.historyBuffer) {
            assert(storageMode == .private)
            return self.historyBufferAllocator
        }
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
            switch cacheMode {
            case .writeCombined:
                return self.frameManagedWriteCombinedBufferAllocator
            case .defaultCache:
                return self.frameManagedBufferAllocator
            }
        
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
        let storageMode : StorageMode
        var size = Int.max
        if let buffer = resource.buffer {
            storageMode = buffer.descriptor.storageMode
            size = buffer.descriptor.length
        } else {
            storageMode = resource.texture!.descriptor.storageMode
        }
        
        if flags.contains(.windowHandle) {
            return false
        }
        
        return (storageMode == .private && size > self.smallAllocationThreshold) || flags.contains(.persistent) || (flags.contains(.historyBuffer) && !resource.stateFlags.contains(.initialised))
    }
    
    func needsWaitFencesOnDispose(size: Int, storageMode: StorageMode, flags: ResourceFlags) -> Bool {
        return storageMode == .private && size > self.smallAllocationThreshold && !flags.contains(.windowHandle)
    }
    
    @discardableResult
    public func allocateTexture(_ texture: Texture, usage: MTLTextureUsage) -> MTLTexture {
        let mtlTexture : MTLTextureReference
        
        if texture.flags.contains(.windowHandle) {
            let windowReference = self.windowReferences[texture.handle]!
            
            let mtlDrawable = DispatchQueue.main.sync { () -> CAMetalDrawable in
                var mtlDrawable : CAMetalDrawable? = nil
                while mtlDrawable == nil {
                    mtlDrawable = (windowReference.layer as! CAMetalLayer).nextDrawable()
                    if mtlDrawable == nil {
                        sched_yield() // Wait until the OS can give us a texture to draw with.
                    }
                }
                return mtlDrawable!
            }
            let drawableTexture = mtlDrawable.texture
            if drawableTexture.width >= texture.descriptor.size.width && drawableTexture.height >= texture.descriptor.size.height {
                mtlTexture = MTLTextureReference(texture: drawableTexture)
                self.frameDrawables.append(mtlDrawable)
            } else {
                // The window was resized to be smaller than the texture size. We can't render directly to that, so instead
                // let's render to an offscreen texture and not present anything.
                let allocator = self.allocatorForTexture(storageMode: .private, flags: [], textureParams: (texture.descriptor.pixelFormat, usage))
                mtlTexture = allocator.collectTextureWithDescriptor(MTLTextureDescriptor(texture.descriptor, usage: usage))
            }
        } else {
            let allocator = self.allocatorForTexture(storageMode: texture.descriptor.storageMode, flags: texture.flags, textureParams: (texture.descriptor.pixelFormat, usage))
            mtlTexture = allocator.collectTextureWithDescriptor(MTLTextureDescriptor(texture.descriptor, usage: usage))
        }
        
        assert(self.textureReferences[texture.handle] == nil)
        self.textureReferences[texture.handle] = mtlTexture
        return mtlTexture.texture
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
    public func allocateTextureIfNeeded(_ texture: Texture, usage: MTLTextureUsage) -> MTLTexture {
        if let mtlTexture = self.textureReferences[texture.handle]?.texture {
            assert(mtlTexture.pixelFormat == MTLPixelFormat(texture.descriptor.pixelFormat))
            return mtlTexture
        }
        return self.allocateTexture(texture, usage: usage)
    }
    
    func allocateArgumentBufferStorage<A : ResourceProtocol>(for argumentBuffer: A, encodedLength: Int) -> MTLBufferReference {
        if argumentBuffer.flags.contains(.persistent) {
            return self.persistentAllocator.collectBufferWithLength(encodedLength, options: [.storageModeManaged, .hazardTrackingModeUntracked])
        }
        return self.frameManagedBufferAllocator.collectBufferWithLength(encodedLength, options: [.storageModeManaged, .hazardTrackingModeUntracked])
    }
    
    // `encoder` is taken as a closure since retrieving an argument encoder from the state caches has a small cost.
    func allocateArgumentBufferIfNeeded(_ argumentBuffer: ArgumentBuffer, bindingPath: ResourceBindingPath, encoder: () -> MTLArgumentEncoder, stateCaches: StateCaches) -> MTLBufferReference {
        if let mtlArgumentBuffer = self.bufferReferences[argumentBuffer.handle] {
            return mtlArgumentBuffer
        }
        
        let argEncoder = encoder()
        let storage = self.allocateArgumentBufferStorage(for: argumentBuffer, encodedLength: argEncoder.encodedLength)
        
        argEncoder.setArgumentBuffer(storage.buffer, offset: storage.offset)
        argEncoder.encodeArguments(from: argumentBuffer, argumentBufferPath: bindingPath, resourceRegistry: self, stateCaches: stateCaches)
        
        storage.buffer.didModifyRange(storage.offset..<(storage.offset + argEncoder.encodedLength))
        
        self.bufferReferences[argumentBuffer.handle] = storage
        if !argumentBuffer.flags.contains(.persistent) {
            self.frameArgumentBuffers.append(argumentBuffer.handle)
        }
        
        return storage
    }
    
    // `encoder` is taken as a closure since retrieving an argument encoder from the state caches has a small cost.
    func allocateArgumentBufferArrayIfNeeded(_ argumentBufferArray: ArgumentBufferArray, bindingPath: ResourceBindingPath, encoder: () -> MTLArgumentEncoder, stateCaches: StateCaches) -> MTLBufferReference {
        if let mtlArgumentBuffer = self.bufferReferences[argumentBufferArray.handle] {
            return mtlArgumentBuffer
        }
        
        let argEncoder = encoder()
        let storage = self.allocateArgumentBufferStorage(for: argumentBufferArray, encodedLength: argEncoder.encodedLength * argumentBufferArray.bindings.count)
        
        for (i, argumentBuffer) in argumentBufferArray.bindings.enumerated() {
            guard let argumentBuffer = argumentBuffer else { continue }
            
            argEncoder.setArgumentBuffer(storage.buffer, startOffset: storage.offset, arrayElement: i)
            
            argEncoder.encodeArguments(from: argumentBuffer, argumentBufferPath: bindingPath, resourceRegistry: self, stateCaches: stateCaches)
        }
        
        storage.buffer.didModifyRange(storage.offset..<(storage.offset + argEncoder.encodedLength * argumentBufferArray.bindings.count))
        
        self.bufferReferences[argumentBufferArray.handle] = storage
        if !argumentBufferArray.flags.contains(.persistent) {
            self.frameArgumentBuffers.append(argumentBufferArray.handle)
        }
        
        return storage
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
    
    public func disposeTexture(_ texture: Texture, readFence: MTLFence?, writeFences: [MTLFence]?) {
        if let mtlTexture = self.textureReferences.removeValue(forKey: texture.handle), !texture.flags.contains(.windowHandle) {
            mtlTexture.readWaitFence = readFence
            mtlTexture.writeWaitFences = writeFences
            let allocator = self.allocatorForTexture(storageMode: texture.descriptor.storageMode, flags: texture.flags, textureParams: (texture.descriptor.pixelFormat, mtlTexture.texture.usage))
            allocator.depositTexture(mtlTexture)
        }
    }
    
    public func disposeBuffer(_ buffer: Buffer, readFence: MTLFence?, writeFences: [MTLFence]?) {
        if let mtlBuffer = self.bufferReferences.removeValue(forKey: buffer.handle) {
            mtlBuffer.readWaitFence = readFence
            mtlBuffer.writeWaitFences = writeFences
            let allocator = self.allocatorForBuffer(length: buffer.descriptor.length, storageMode: buffer.descriptor.storageMode, cacheMode: buffer.descriptor.cacheMode, flags: buffer.flags)
            allocator.depositBuffer(mtlBuffer)
        }
    }
    
    public func disposeArgumentBuffer(_ buffer: ArgumentBuffer) {
        self.bufferReferences.removeValue(forKey: buffer.handle)
    }
    
    public func fenceWithId(_ id: Int) -> MTLFence {
        if let fence = self.fenceMappings[id] {
            return fence
        } else {
            let fence = self.unusedFences.popLast() ?? self.device.makeFence()!
            self.fenceMappings[id] = fence
            return fence
        }
    }
    
    public func retainFence(_ fence: MTLFence) {
        self.fenceRetainCounts[ObjectIdentifier(fence), default: 0] += 1
    }
    
    /// - parameter addToPoolImmediately: Whether to return the fence to the pool immediately or wait until the end of the frame.
    ///   Always returning immediately to the pool causes issues since our retain/release pairs aren't properly ordered, and it's
    ///   difficult to make them properly ordered since retain needs to run after updateFence to allow remapping to occur.
    public func releaseFence(_ fence: MTLFence, addToPoolImmediately: Bool) {
        let currentCount = self.fenceRetainCounts[ObjectIdentifier(fence)]!
        self.fenceRetainCounts[ObjectIdentifier(fence)] = currentCount - 1
        if currentCount == 1, addToPoolImmediately {
            self.unusedFences.append(fence)
        }
    }
    
    public func retainFenceWithId(_ id: Int) {
        let fence = self.fenceMappings[id]!
        self.retainFence(fence)
    }
    
    public func releaseFenceWithId(_ id: Int, addToPoolImmediately: Bool) {
        let fence = self.fenceMappings[id]!
        self.releaseFence(fence, addToPoolImmediately: addToPoolImmediately)
    }
    
    public func remapFenceId(_ id: Int, toExistingFenceWithId existingId: Int) {
        if id == existingId { return }
        assert(self.fenceMappings[id] == nil)
        let existingFence = self.fenceMappings[existingId]!
        self.fenceMappings[id] = existingFence
    }
    
    public func fenceWithOptionalId(_ id: Int?) -> MTLFence? {
        guard let id = id else { return nil }
        
        return self.fenceWithId(id)
    }
    
    public func bufferContents(for buffer: Buffer) -> UnsafeMutableRawPointer {
        assert(buffer.flags.contains(.persistent) || self.frameGraphHasResourceAccess, "GPU memory for a transient buffer may not be accessed outside of a FrameGraph RenderPass. Consider using withDeferredSlice instead.")
    
        if !buffer.flags.contains(.persistent) {
            self.frameCPUBuffers.append(buffer)
        }
        
        let bufferReference = self.allocateBufferIfNeeded(buffer)
        return bufferReference.buffer.contents() + bufferReference.offset
    }
    
    public func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) {
        assert(texture.flags.contains(.persistent) || self.frameGraphHasResourceAccess, "GPU memory for a transient texture may not be accessed outside of a FrameGraph RenderPass.")
        
        if !texture.flags.contains(.persistent) {
            self.frameCPUTextures.append(texture)
        }
        
        self.allocateTextureIfNeeded(texture, usage: MTLTextureUsage(texture.descriptor.usageHint)).replace(region: MTLRegion(region), mipmapLevel: mipmapLevel, withBytes: bytes, bytesPerRow: bytesPerRow)
    }
    
    public func cycleFrames() {
        while let buffer = self.frameCPUBuffers.popLast() {
            self.disposeBuffer(buffer, readFence: nil, writeFences: nil) // No fences for CPU resources.
        }
        
        while let texture = self.frameCPUTextures.popLast() {
            self.disposeTexture(texture, readFence: nil, writeFences: nil)
        }
        
        while let argBuffer = self.frameArgumentBuffers.popLast() {
            self.bufferReferences.removeValue(forKey: argBuffer)
        }
        
        self.stagingTextureAllocator.cycleFrames()
        self.privateAllocator.cycleFrames()
        self.smallPrivateAllocator.cycleFrames()
        self.historyBufferAllocator.cycleFrames()
        
        self.colorRenderTargetAllocator.cycleFrames()
        self.depthRenderTargetAllocator.cycleFrames()
        self.persistentAllocator.cycleFrames()
        
        self.frameSharedBufferAllocator.cycleFrames()
        self.frameManagedBufferAllocator.cycleFrames()
        self.frameManagedWriteCombinedBufferAllocator.cycleFrames()
        
        self.windowReferences.removeAll(keepingCapacity: true)
        self.frameDrawables.removeAll(keepingCapacity: true)
        
        var uniqueFencesToAdd = [ObjectIdentifier : MTLFence]()
        for fence in self.fenceMappings.values {
            if self.fenceRetainCounts[ObjectIdentifier(fence)]! == 0 {
                uniqueFencesToAdd[ObjectIdentifier(fence)] = fence
                
            }
        }
        self.unusedFences.append(contentsOf: uniqueFencesToAdd.values)
        self.fenceMappings.removeAll(keepingCapacity: true) // Removes any mappings to fences that are now attached to resources.
        
    }
}
