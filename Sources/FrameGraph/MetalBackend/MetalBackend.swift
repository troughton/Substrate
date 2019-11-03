//
//  MetalRenderer.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 23/12/17.
//

#if canImport(Metal)

import FrameGraphUtilities
import Metal

extension MTLResourceOptions {
    static var frameGraphTrackedHazards : MTLResourceOptions {
        // This gives us a convenient way to toggle whether the FrameGraph or Metal should handle resource tracking.
        return .hazardTrackingModeUntracked
    }
}

final class MetalBackend : _RenderBackendProtocol {
    let device : MTLDevice
    let resourceRegistry : MetalPersistentResourceRegistry
    let stateCaches : MetalStateCaches
    
    var activeContext : MetalFrameGraphContext? = nil
    
    var queueSyncEvents = [MTLEvent?](repeating: nil, count: QueueRegistry.maxQueues)
    
    public init(libraryPath: String? = nil) {
        self.device = MTLCreateSystemDefaultDevice()!
        self.stateCaches = MetalStateCaches(device: self.device, libraryPath: libraryPath)
        self.resourceRegistry = MetalPersistentResourceRegistry(device: device)
        
        // Push constants go immediately after the argument buffers.
        RenderBackend.pushConstantPath = ResourceBindingPath(stages: [.vertex, .fragment], type: .buffer, argumentBufferIndex: nil, index: 8)
    }
    
    public var api : RenderAPI {
        return .metal
    }
    
    public var renderDevice: Any {
        return self.device
    }
    
    @usableFromInline func setActiveContext(_ context: MetalFrameGraphContext) {
        assert(self.activeContext == nil)
        self.stateCaches.checkForLibraryReload()
        self.activeContext = context
    }
    
    @usableFromInline func materialisePersistentTexture(_ texture: Texture) -> Bool {
        return resourceRegistry.accessLock.withWriteLock {
            return self.resourceRegistry.allocateTexture(texture, properties: MetalTextureUsageProperties(texture.descriptor.usageHint)) != nil
        }
    }
    
    @usableFromInline func registerWindowTexture(texture: Texture, context: Any) {
        self.resourceRegistry.registerWindowTexture(texture: texture, context: context)
    }
    
    @usableFromInline func materialisePersistentBuffer(_ buffer: Buffer) -> Bool {
        return resourceRegistry.accessLock.withWriteLock {
            return self.resourceRegistry.allocateBuffer(buffer) != nil
        }
    }
    
    @usableFromInline func materialiseHeap(_ heap: Heap) -> Bool {
        return self.resourceRegistry.allocateHeap(heap) != nil
    }

    @usableFromInline func dispose(texture: Texture) {
        self.resourceRegistry.disposeTexture(texture)
    }
    
    @usableFromInline func dispose(buffer: Buffer) {
        self.resourceRegistry.disposeBuffer(buffer)
    }
    
    @usableFromInline func dispose(argumentBuffer: _ArgumentBuffer) {
        self.resourceRegistry.disposeArgumentBuffer(argumentBuffer)
    }
    
    @usableFromInline func dispose(argumentBufferArray: _ArgumentBufferArray) {
        self.resourceRegistry.disposeArgumentBufferArray(argumentBufferArray)
    }
    
    @usableFromInline func dispose(heap: Heap) {
        self.resourceRegistry.disposeHeap(heap)
    }
    
    public var isDepth24Stencil8PixelFormatSupported: Bool {
        #if os(macOS)
        return self.device.isDepth24Stencil8PixelFormatSupported
        #else
        return false
        #endif
    }
    
    public var threadExecutionWidth: Int {
        return self.stateCaches.currentThreadExecutionWidth
    }
    
    @usableFromInline func bufferContents(for buffer: Buffer, range: Range<Int>) -> UnsafeMutableRawPointer {
        let bufferReference = self.activeContext?.resourceMap.bufferForCPUAccess(buffer) ?? resourceRegistry.accessLock.withReadLock { resourceRegistry[buffer]! }
        return bufferReference.buffer.contents() + bufferReference.offset + range.lowerBound
    }
    
    @usableFromInline func buffer(_ buffer: Buffer, didModifyRange range: Range<Int>) {
        #if os(macOS)
        if range.isEmpty { return }
        if buffer.descriptor.storageMode == .managed {
            let mtlBuffer = self.activeContext?.resourceMap.bufferForCPUAccess(buffer) ?? resourceRegistry.accessLock.withReadLock { resourceRegistry[buffer]! }
            let offsetRange = (range.lowerBound + mtlBuffer.offset)..<(range.upperBound + mtlBuffer.offset)
            mtlBuffer.buffer.didModifyRange(offsetRange)
        }
        #endif
    }

    @usableFromInline func registerExternalResource(_ resource: Resource, backingResource: Any) {
        self.resourceRegistry.importExternalResource(resource, backingResource: backingResource)
    }
    
    public func backingResource(_ resource: Resource) -> Any? {
        return resourceRegistry.accessLock.withReadLock {
            if let buffer = resource.buffer {
                let bufferReference = resourceRegistry[buffer]
                assert(bufferReference == nil || bufferReference?.offset == 0)
                return bufferReference?.buffer
            } else if let texture = resource.texture {
                return resourceRegistry[texture]
            }
            return nil
        }
    }
    
    @usableFromInline func copyTextureBytes(from texture: Texture, to bytes: UnsafeMutableRawPointer, bytesPerRow: Int, region: Region, mipmapLevel: Int) {
        assert(texture.flags.contains(.persistent) || self.activeContext != nil, "GPU memory for a transient texture may not be accessed outside of a FrameGraph RenderPass.")
        
        let mtlTexture = self.activeContext?.resourceMap.textureForCPUAccess(texture) ?? resourceRegistry.accessLock.withReadLock { resourceRegistry[texture]! }
        mtlTexture.getBytes(bytes, bytesPerRow: bytesPerRow, from: MTLRegion(region), mipmapLevel: mipmapLevel)
    }
    
    @usableFromInline func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) {
        assert(texture.flags.contains(.persistent) || self.activeContext != nil, "GPU memory for a transient texture may not be accessed outside of a FrameGraph RenderPass.")
        
        let mtlTexture = self.activeContext?.resourceMap.textureForCPUAccess(texture) ?? resourceRegistry.accessLock.withReadLock { resourceRegistry[texture]! }
        mtlTexture.replace(region: MTLRegion(region), mipmapLevel: mipmapLevel, withBytes: bytes, bytesPerRow: bytesPerRow)
    }
    
    @usableFromInline func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, slice: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int) {
        assert(texture.flags.contains(.persistent) || self.activeContext != nil, "GPU memory for a transient texture may not be accessed outside of a FrameGraph RenderPass.")
               
        let mtlTexture = self.activeContext?.resourceMap.textureForCPUAccess(texture) ?? resourceRegistry.accessLock.withReadLock { resourceRegistry[texture]! }
        mtlTexture.replace(region: MTLRegion(region), mipmapLevel: mipmapLevel, slice: slice, withBytes: bytes, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerImage)
    }
    
    @usableFromInline
    func renderPipelineReflection(descriptor: RenderPipelineDescriptor, renderTarget: RenderTargetDescriptor) -> PipelineReflection? {
        return self.stateCaches.renderPipelineReflection(descriptor: descriptor, renderTarget: renderTarget)
    }
    
    @usableFromInline
    func computePipelineReflection(descriptor: ComputePipelineDescriptor) -> PipelineReflection? {
        return self.stateCaches.computePipelineReflection(descriptor: descriptor)
    }
    
    @usableFromInline func argumentBufferPath(at index: Int, stages: RenderStages) -> ResourceBindingPath {
        let stages = MTLRenderStages(stages)
        return ResourceBindingPath(stages: stages, type: .buffer, argumentBufferIndex: nil, index: index)
    }
}

#endif // canImport(Metal)
