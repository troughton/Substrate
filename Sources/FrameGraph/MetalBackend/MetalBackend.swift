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

public final class MetalBackend : RenderBackendProtocol, FrameGraphBackend {
    public let maxInflightFrames : Int
    
    let device : MTLDevice
    let resourceRegistry : MetalResourceRegistry
    let stateCaches : MetalStateCaches
    let frameGraph : MetalFrameGraph
    
    public init(numInflightFrames: Int, libraryPath: String? = nil) {
        self.device = MTLCreateSystemDefaultDevice()!
        self.resourceRegistry = MetalResourceRegistry(device: self.device, numInflightFrames: numInflightFrames)
        self.stateCaches = MetalStateCaches(device: self.device, libraryPath: libraryPath)
        self.frameGraph = MetalFrameGraph(device: device, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
        
        self.maxInflightFrames = numInflightFrames
        
//        RenderBackend.backend = self
        
        RenderBackend._cachedBackend = _CachedRenderBackend(
            registerExternalResource: { [self] (resource, backingResource) in
                self.registerExternalResource(resource, backingResource: backingResource)
            },
            registerWindowTexture: { [self] (texture, context) in
                self.registerWindowTexture(texture: texture, context: context)
            },
            materialisePersistentTexture: { [self] texture in self.materialisePersistentTexture(texture) },
            materialisePersistentBuffer: { [self] buffer in self.materialisePersistentBuffer(buffer) },
            bufferContents: { [self] (buffer, range) in self.bufferContents(for: buffer, range: range) },
            bufferDidModifyRange: { [self] (buffer, range) in self.buffer(buffer, didModifyRange: range) },
            copyTextureBytes: { [self] (texture, bytes, bytesPerRow, region, mipmapLevel) in self.copyTextureBytes(from: texture, to: bytes, bytesPerRow: bytesPerRow, region: region, mipmapLevel: mipmapLevel) },
            replaceTextureRegion: { [self] (texture, region, mipmapLevel, bytes, bytesPerRow) in self.replaceTextureRegion(texture: texture, region: region, mipmapLevel: mipmapLevel, withBytes: bytes, bytesPerRow: bytesPerRow) },
            replaceTextureRegionForSlice: { (texture, region, mipmapLevel, slice, bytes, bytesPerRow, bytesPerImage) in self.replaceTextureRegion(texture: texture, region: region, mipmapLevel: mipmapLevel, slice: slice, withBytes: bytes, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerImage) },
            renderPipelineReflection: { [self] (pipeline, renderTarget) in self.renderPipelineReflection(descriptor: pipeline, renderTarget: renderTarget) },
            computePipelineReflection: { [self] (pipeline) in self.computePipelineReflection(descriptor: pipeline) },
            disposeTexture: { [self] texture in self.dispose(texture: texture) },
            disposeBuffer: { [self] buffer in self.dispose(buffer: buffer) },
            disposeArgumentBuffer: { [self] argumentBuffer in self.dispose(argumentBuffer: argumentBuffer) },
            disposeArgumentBufferArray: { [self] argumentBufferArray in self.dispose(argumentBufferArray: argumentBufferArray) },
            backingResource: { [self] resource in return self.backingResource(resource) },
            isDepth24Stencil8PixelFormatSupported: { [self] in self.isDepth24Stencil8PixelFormatSupported },
            threadExecutionWidth: { [self] in self.threadExecutionWidth },
            renderDevice: { [self] in self.renderDevice },
            maxInflightFrames: { [self] in self.maxInflightFrames },
            argumentBufferPath: { (index, stages) in
                let stages = MTLRenderStages(stages)
                return ResourceBindingPath(stages: stages, type: .buffer, argumentBufferIndex: nil, index: index)
            }
        )
        
        // Push constants go immediately after the argument buffers.
        RenderBackend.pushConstantPath = ResourceBindingPath(stages: [.vertex, .fragment], type: .buffer, argumentBufferIndex: nil, index: 8)
    }
    
    public var renderDevice: Any {
        return self.device
    }
    
    public func beginFrameResourceAccess() {
        self.frameGraph.beginFrameResourceAccess()
    }
    
    public func materialisePersistentTexture(_ texture: Texture) {
        resourceRegistry.accessLock.withWriteLock {
            _ = self.resourceRegistry.allocateTexture(texture, properties: MetalTextureUsageProperties(texture.descriptor.usageHint))
        }
    }
    
    public func registerWindowTexture(texture: Texture, context: Any) {
        self.resourceRegistry.registerWindowTexture(texture: texture, context: context)
    }
    
    public func materialisePersistentBuffer(_ buffer: Buffer) {
        _ = resourceRegistry.accessLock.withWriteLock {
            self.resourceRegistry.allocateBuffer(buffer)
        }
    }
    
    public func dispose(texture: Texture) {
        self.resourceRegistry.disposeTexture(texture, keepingReference: false)
    }
    
    public func dispose(buffer: Buffer) {
        self.resourceRegistry.disposeBuffer(buffer, keepingReference: false)
    }
    
    public func dispose(argumentBuffer: _ArgumentBuffer) {
        self.resourceRegistry.disposeArgumentBuffer(argumentBuffer, keepingReference: false)
    }
    
    public func dispose(argumentBufferArray: _ArgumentBufferArray) {
        self.resourceRegistry.disposeArgumentBufferArray(argumentBufferArray, keepingReference: false)
    }
    
    public func executeFrameGraph(passes: [RenderPassRecord], dependencyTable: DependencyTable<SwiftFrameGraph.DependencyType>, resourceUsages: ResourceUsages, completion: @escaping () -> Void) {
        autoreleasepool {
            self.frameGraph.executeFrameGraph(passes: passes, dependencyTable: dependencyTable, resourceUsages: resourceUsages, completion: completion)
        }
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
    
    public func bufferContents(for buffer: Buffer, range: Range<Int>) -> UnsafeMutableRawPointer {
        return resourceRegistry.accessLock.withWriteLock {
            resourceRegistry.bufferContents(for: buffer) + range.lowerBound
        }
    }
    
    public func buffer(_ buffer: Buffer, didModifyRange range: Range<Int>) {
        #if os(macOS)
        if range.isEmpty { return }
        if buffer.descriptor.storageMode == .managed {
            let mtlBuffer = resourceRegistry.accessLock.withReadLock { resourceRegistry[buffer]! }
            let offsetRange = (range.lowerBound + mtlBuffer.offset)..<(range.upperBound + mtlBuffer.offset)
            mtlBuffer.buffer.didModifyRange(offsetRange)
        }
        #endif
    }

    public func registerExternalResource(_ resource: Resource, backingResource: Any) {
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
    

    public func copyTextureBytes(from texture: Texture, to bytes: UnsafeMutableRawPointer, bytesPerRow: Int, region: Region, mipmapLevel: Int) {
        resourceRegistry.accessLock.withWriteLock {
            resourceRegistry.copyTextureBytes(from: texture, to: bytes, bytesPerRow: bytesPerRow, region: region, mipmapLevel: mipmapLevel)
        }
    }
    
    public func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) {
        resourceRegistry.accessLock.withWriteLock {
            resourceRegistry.replaceTextureRegion(texture: texture, region: region, mipmapLevel: mipmapLevel, withBytes: bytes, bytesPerRow: bytesPerRow)
        }
    }
    
    public func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, slice: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int) {
        resourceRegistry.accessLock.withWriteLock {
            resourceRegistry.replaceTextureRegion(texture: texture, region: region, mipmapLevel: mipmapLevel, slice: slice, withBytes: bytes, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerImage)
        }
    }
    
    public func renderPipelineReflection(descriptor: RenderPipelineDescriptor, renderTarget: RenderTargetDescriptor) -> PipelineReflection? {
        return self.stateCaches.renderPipelineReflection(descriptor: descriptor, renderTarget: renderTarget)
    }
    
    public func computePipelineReflection(descriptor: ComputePipelineDescriptor) -> PipelineReflection? {
        return self.stateCaches.computePipelineReflection(descriptor: descriptor)
    }
    
    public func argumentBufferPath(at index: Int, stages: RenderStages) -> ResourceBindingPath {
        let stages = MTLRenderStages(stages)
        return ResourceBindingPath(stages: stages, type: .buffer, argumentBufferIndex: nil, index: index)
    }
    
}

#endif // canImport(Metal)
