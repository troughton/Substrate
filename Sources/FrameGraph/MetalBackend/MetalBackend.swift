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

#if targetEnvironment(macCatalyst)
@objc protocol MTLBufferShim: MTLResource {
    func didModifyRange(_ range: NSRange)
}
#endif

final class MetalBackend : SpecificRenderBackend {

    typealias BufferReference = MTLBufferReference
    typealias TextureReference = MTLTextureReference
    typealias ArgumentBufferReference = MTLBufferReference
    typealias ArgumentBufferArrayReference = MTLBufferReference
    typealias SamplerReference = MTLSamplerState
    
    typealias TransientResourceRegistry = MetalTransientResourceRegistry
    typealias PersistentResourceRegistry = MetalPersistentResourceRegistry
    
    typealias RenderTargetDescriptor = MetalRenderTargetDescriptor
    
    let device : MTLDevice
    let resourceRegistry : MetalPersistentResourceRegistry
    let stateCaches : MetalStateCaches
    
    var activeContext : MetalFrameGraphContext? = nil
    
    var queueSyncEvents = [MTLEvent?](repeating: nil, count: QueueRegistry.maxQueues)
    
    public init(libraryPath: String? = nil) {
        self.device = MTLCreateSystemDefaultDevice()!
        self.stateCaches = MetalStateCaches(device: self.device, libraryPath: libraryPath)
        self.resourceRegistry = MetalPersistentResourceRegistry(device: device)
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
            return self.resourceRegistry.allocateTexture(texture, usage: TextureUsageProperties(texture.descriptor.usageHint)) != nil
        }
    }
    
    @usableFromInline func registerWindowTexture(texture: Texture, context: Any) {
        self.resourceRegistry.registerWindowTexture(texture: texture, context: context)
    }
    
    @usableFromInline func materialisePersistentBuffer(_ buffer: Buffer) -> Bool {
        return resourceRegistry.accessLock.withWriteLock {
            return self.resourceRegistry.allocateBuffer(buffer, usage: buffer.descriptor.usageHint) != nil
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
        #if os(macOS) || targetEnvironment(macCatalyst)
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
        #if os(macOS) || targetEnvironment(macCatalyst)
        if range.isEmpty { return }
        if buffer.descriptor.storageMode == .managed {
            let mtlBuffer = self.activeContext?.resourceMap.bufferForCPUAccess(buffer) ?? resourceRegistry.accessLock.withReadLock { resourceRegistry[buffer]! }
            let offsetRange = (range.lowerBound + mtlBuffer.offset)..<(range.upperBound + mtlBuffer.offset)
            #if targetEnvironment(macCatalyst)
            unsafeBitCast(mtlBuffer.buffer, to: MTLBufferShim.self).didModifyRange(NSMakeRange(offsetRange.lowerBound, offsetRange.count))
            #else
            mtlBuffer.buffer.didModifyRange(offsetRange)
            #endif
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
        mtlTexture.texture.getBytes(bytes, bytesPerRow: bytesPerRow, from: MTLRegion(region), mipmapLevel: mipmapLevel)
    }
    
    @usableFromInline func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) {
        assert(texture.flags.contains(.persistent) || self.activeContext != nil, "GPU memory for a transient texture may not be accessed outside of a FrameGraph RenderPass.")
        
        let mtlTexture = self.activeContext?.resourceMap.textureForCPUAccess(texture) ?? resourceRegistry.accessLock.withReadLock { resourceRegistry[texture]! }
        mtlTexture.texture.replace(region: MTLRegion(region), mipmapLevel: mipmapLevel, withBytes: bytes, bytesPerRow: bytesPerRow)
    }
    
    @usableFromInline func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, slice: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int) {
        assert(texture.flags.contains(.persistent) || self.activeContext != nil, "GPU memory for a transient texture may not be accessed outside of a FrameGraph RenderPass.")
               
        let mtlTexture = self.activeContext?.resourceMap.textureForCPUAccess(texture) ?? resourceRegistry.accessLock.withReadLock { resourceRegistry[texture]! }
        mtlTexture.texture.replace(region: MTLRegion(region), mipmapLevel: mipmapLevel, slice: slice, withBytes: bytes, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerImage)
    }
    
    @usableFromInline
    func renderPipelineReflection(descriptor: RenderPipelineDescriptor, renderTarget: SwiftFrameGraph.RenderTargetDescriptor) -> PipelineReflection? {
        return self.stateCaches.renderPipelineReflection(descriptor: descriptor, renderTarget: renderTarget)
    }
    
    @usableFromInline
    func computePipelineReflection(descriptor: ComputePipelineDescriptor) -> PipelineReflection? {
        return self.stateCaches.computePipelineReflection(descriptor: descriptor)
    }

    @usableFromInline var pushConstantPath: ResourceBindingPath {
        return ResourceBindingPath(stages: [.vertex, .fragment], type: .buffer, argumentBufferIndex: nil, index: 0) // Push constants go at index 0
    }
    
    @usableFromInline func argumentBufferPath(at index: Int, stages: RenderStages) -> ResourceBindingPath {
        let stages = MTLRenderStages(stages)
        return ResourceBindingPath(stages: stages, type: .buffer, argumentBufferIndex: nil, index: index + 1) // Push constants go at index 0
    }
    
    // MARK: - SpecificRenderBackend conformance
    
    static var requiresResourceResidencyTracking: Bool {
        // Metal requires useResource calls for all untracked resources.
        return true
    }

    static var requiresBufferUsage: Bool {
        // Metal does not track buffer usages.
        return false
    }
    
    static func fillArgumentBuffer(_ argumentBuffer: _ArgumentBuffer, storage: MTLBufferReference, resourceMap: FrameResourceMap<MetalBackend>) {
        argumentBuffer.setArguments(storage: storage, resourceMap: resourceMap)
    }
    
    static func fillArgumentBufferArray(_ argumentBufferArray: _ArgumentBufferArray, storage: MTLBufferReference, resourceMap: FrameResourceMap<MetalBackend>) {
        argumentBufferArray.setArguments(storage: storage, resourceMap: resourceMap)
    }
}

#endif // canImport(Metal)
