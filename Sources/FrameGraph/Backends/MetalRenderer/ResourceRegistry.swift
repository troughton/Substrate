//
//  ResourceRegistry.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 23/12/17.
//

import RenderAPI
import FrameGraph
import Metal
import MetalKit
import Utilities

struct MTLBufferReference {
    let buffer : MTLBuffer
    let offset : Int
}

final class ResourceRegistry {
    
    private var textureReferences = [ObjectIdentifier : MTLTexture]()
    private var bufferReferences = [ObjectIdentifier : MTLBufferReference]()
    private var argumentBufferReferences = [ObjectIdentifier : MetalArgumentBuffer]()
    
    private var windowReferences = [ObjectIdentifier : MTKView]()
    
    private var fenceMappings = [Int : MTLFence]()
    private var unusedFences = [MTLFence]()
    
    private let device : MTLDevice
    
    private let frameSharedBufferAllocator : TemporaryBufferAllocator
    private let frameManagedBufferAllocator : TemporaryBufferAllocator
    private let frameManagedWriteCombinedBufferAllocator : TemporaryBufferAllocator
    
    private let stagingTextureAllocator : PoolResourceAllocator
    private let privateAllocator : HeapResourceAllocator
    
    private let colorRenderTargetAllocator : HeapResourceAllocator
    private let depthRenderTargetAllocator : HeapResourceAllocator
    
    private let historyBufferAllocator : PoolResourceAllocator
    private let persistentAllocator : PersistentResourceAllocator
    
    private var frameCPUBuffers = [Buffer]()
    private var frameCPUTextures = [Texture]()
    private var frameArgumentBuffers = [ObjectIdentifier]()
    
    public private(set) var frameDrawables : [MTLDrawable] = []
    
    public var frameGraphHasResourceAccess = false
    
    public init(device: MTLDevice, numInflightFrames: Int) {
        self.device = device
        
        self.stagingTextureAllocator = PoolResourceAllocator(device: device, numFrames: numInflightFrames)
        self.historyBufferAllocator = PoolResourceAllocator(device: device, numFrames: 1)
        
        self.persistentAllocator = PersistentResourceAllocator(device: device)
        
        self.frameSharedBufferAllocator = TemporaryBufferAllocator(device: device, numFrames: numInflightFrames, blockSize: 262144, options: .storageModeShared)
        self.frameManagedBufferAllocator = TemporaryBufferAllocator(device: device, numFrames: numInflightFrames, blockSize: 1024 * 1024, options: .storageModeManaged)
        self.frameManagedWriteCombinedBufferAllocator = TemporaryBufferAllocator(device: device, numFrames: numInflightFrames, blockSize: 1024 * 1024, options: [.storageModeManaged, .cpuCacheModeWriteCombined])
        
        let heapDescriptor = MTLHeapDescriptor()
        heapDescriptor.size = 1 << 24 // A 16MB heap
        heapDescriptor.storageMode = .private
        self.privateAllocator = HeapResourceAllocator(device: device, defaultDescriptor: heapDescriptor, framePurgeability: .empty)
        
        heapDescriptor.size = 40_000_000 // A 40MB heap
        self.depthRenderTargetAllocator = HeapResourceAllocator(device: device, defaultDescriptor: heapDescriptor, framePurgeability: .empty)
        
        heapDescriptor.size = 200_000_000 // A 200MB heap
        self.colorRenderTargetAllocator = HeapResourceAllocator(device: device, defaultDescriptor: heapDescriptor, framePurgeability: .empty)
    }
    
    public func registerWindowTexture(texture: Texture, context: Any) {
        self.windowReferences[ObjectIdentifier(texture)] = (context as! MTKView)
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
    
    func allocatorForBuffer(storageMode: StorageMode, cacheMode: CPUCacheMode, flags: ResourceFlags) -> BufferAllocator {
        
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
            switch cacheMode {
            case .writeCombined:
                return self.frameManagedWriteCombinedBufferAllocator
            case .defaultCache:
                return self.frameManagedBufferAllocator
            }
        
        case .shared:
            return self.frameSharedBufferAllocator
        }
    }
    
    @discardableResult
    public func allocateTexture(_ texture: Texture, usage: MTLTextureUsage) -> MTLTexture {
        let mtlTexture : MTLTexture
        
        if texture.flags.contains(.windowHandle) {
            let windowReference = self.windowReferences[texture.handle]!
            
            let mtlDrawable = DispatchQueue.main.sync { () -> CAMetalDrawable in
                var mtlDrawable : CAMetalDrawable? = nil
                while mtlDrawable == nil {
                    mtlDrawable = (windowReference.layer as! CAMetalLayer).nextDrawable()
                    if mtlDrawable == nil {
                        sleep(0) // Wait until the OS can give us a texture to draw with.
                    }
                }
                return mtlDrawable!
            }
            let drawableTexture = mtlDrawable.texture
            if drawableTexture.width >= texture.descriptor.size.width && drawableTexture.height >= texture.descriptor.size.height {
                mtlTexture = drawableTexture
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
        return mtlTexture
    }
    
    @discardableResult
    public func allocateBuffer(_ buffer: Buffer) -> MTLBufferReference {
        let allocator = self.allocatorForBuffer(storageMode: buffer.descriptor.storageMode, cacheMode: buffer.descriptor.cacheMode, flags: buffer.flags)
        let mtlBuffer = allocator.collectBufferWithLength(buffer.descriptor.length, options: MTLResourceOptions(storageMode: buffer.descriptor.storageMode, cacheMode: buffer.descriptor.cacheMode))
        
        assert(self.bufferReferences[buffer.handle] == nil)
        self.bufferReferences[ObjectIdentifier(buffer)] = mtlBuffer
        
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
        if let mtlTexture = self.textureReferences[texture.handle] {
            assert(mtlTexture.pixelFormat == MTLPixelFormat(texture.descriptor.pixelFormat))
            return mtlTexture
        }
        return self.allocateTexture(texture, usage: usage)
    }
    
    func allocateArgumentBufferStorage(for argumentBuffer: ArgumentBuffer, encodedLength: Int) -> MTLBufferReference {
        if argumentBuffer.flags.contains(.persistent) {
            return self.persistentAllocator.collectBufferWithLength(encodedLength, options: [.storageModeManaged, .hazardTrackingModeUntracked])
        }
        return self.frameManagedBufferAllocator.collectBufferWithLength(encodedLength, options: [.storageModeManaged, .hazardTrackingModeUntracked])
    }
    
    // `encoder` is taken as a closure since retrieving an argument encoder from the state caches has a small cost.
    func allocateArgumentBufferIfNeeded(_ argumentBuffer: ArgumentBuffer, bindingPath: ResourceBindingPath, encoder: () -> MTLArgumentEncoder, stateCaches: StateCaches) -> MetalArgumentBuffer {
        if let mtlArgumentBuffer = self.argumentBufferReferences[argumentBuffer.handle] {
            return mtlArgumentBuffer
        }
        
        let argEncoder = encoder()
        let buffer = MetalArgumentBuffer(encoder: argEncoder, resourceRegistry: self, stateCaches: stateCaches, bindingPath: bindingPath, arguments: argumentBuffer)
        self.argumentBufferReferences[argumentBuffer.handle] = buffer
        if !argumentBuffer.flags.contains(.persistent) {
            self.frameArgumentBuffers.append(argumentBuffer.handle)
        }
        
        return buffer
    }
    
    // These subscript methods should only be called after 'allocate' has been called.
    // If you hit an error here, check if you forgot to make a resource persistent.
    public subscript(texture: Texture) -> MTLTexture? {
        return self.textureReferences[ObjectIdentifier(texture)]
    }
    
    public subscript(texture texture: ObjectIdentifier) -> MTLTexture? {
        return self.textureReferences[texture]!
    }
    
    public subscript(buffer: Buffer) -> MTLBufferReference? {
        return self.bufferReferences[ObjectIdentifier(buffer)]
    }
    
    public subscript(buffer buffer: ObjectIdentifier) -> MTLBufferReference? {
        return self.bufferReferences[buffer]
    }
    
    public func disposeTexture(_ texture: Texture) {
        if let mtlTexture = self.textureReferences.removeValue(forKey: texture.handle), !texture.flags.contains(.windowHandle) {
            let allocator = self.allocatorForTexture(storageMode: texture.descriptor.storageMode, flags: texture.flags, textureParams: (texture.descriptor.pixelFormat, mtlTexture.usage))
            allocator.depositTexture(mtlTexture)
        }
    }
    
    public func disposeBuffer(_ buffer: Buffer) {
        if let mtlBuffer = self.bufferReferences.removeValue(forKey: buffer.handle) {
            let allocator = self.allocatorForBuffer(storageMode: buffer.descriptor.storageMode, cacheMode: buffer.descriptor.cacheMode, flags: buffer.flags)
            allocator.depositBuffer(mtlBuffer)
        }
    }
    
    public func disposeArgumentBuffer(_ buffer: ArgumentBuffer) {
        self.argumentBufferReferences.removeValue(forKey: buffer.handle)
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
    
    public func bufferContents(for buffer: Buffer) -> UnsafeMutableRawPointer {
        assert(self[buffer] == nil || self.frameGraphHasResourceAccess, "Frame GPU memory for a pre-existing buffer may not be accessed outside of a FrameGraph RenderPass.")
            
        if !buffer.flags.contains(.persistent) {
            self.frameCPUBuffers.append(buffer)
        }
        
        let bufferReference = self.allocateBufferIfNeeded(buffer)
        return bufferReference.buffer.contents() + bufferReference.offset
    }
    
    public func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) {
        assert(self[texture] == nil || self.frameGraphHasResourceAccess, "Frame GPU memory for a pre-existing texture may not be accessed outside of a FrameGraph RenderPass.")
        
        if !texture.flags.contains(.persistent) {
            self.frameCPUTextures.append(texture)
        }
        
        self.allocateTextureIfNeeded(texture, usage: MTLTextureUsage(texture.descriptor.usageHint)).replace(region: MTLRegion(region), mipmapLevel: mipmapLevel, withBytes: bytes, bytesPerRow: bytesPerRow)
    }
    
    public func cycleFrames() {
        while let buffer = self.frameCPUBuffers.popLast() {
            self.disposeBuffer(buffer)
        }
        
        while let texture = self.frameCPUTextures.popLast() {
            self.disposeTexture(texture)
        }
        
        while let argBuffer = self.frameArgumentBuffers.popLast() {
            self.argumentBufferReferences.removeValue(forKey: argBuffer)
        }
        
        self.stagingTextureAllocator.cycleFrames()
        self.privateAllocator.cycleFrames()
        self.historyBufferAllocator.cycleFrames()
        
        self.colorRenderTargetAllocator.cycleFrames()
        self.depthRenderTargetAllocator.cycleFrames()
        self.persistentAllocator.cycleFrames()
        
        self.frameSharedBufferAllocator.cycleFrames()
        self.frameManagedBufferAllocator.cycleFrames()
        self.frameManagedWriteCombinedBufferAllocator.cycleFrames()
        
        self.windowReferences.removeAll(keepingCapacity: true)
        self.frameDrawables.removeAll(keepingCapacity: true)
        
        self.unusedFences.append(contentsOf: self.fenceMappings.values)
        self.fenceMappings.removeAll(keepingCapacity: true)
        
    }
}
