//
//  MetalRenderer.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 23/12/17.
//

import SwiftFrameGraph
import Metal

public final class MetalBackend : RenderBackendProtocol, FrameGraphBackend {
    public let maxInflightFrames : Int
    
    let device : MTLDevice
    let resourceRegistry : ResourceRegistry
    let stateCaches : StateCaches
    let frameGraph : MetalFrameGraph
    
    public init(numInflightFrames: Int, libraryPath: String? = nil) {
        self.device = MTLCreateSystemDefaultDevice()!
        self.resourceRegistry = ResourceRegistry(device: self.device, numInflightFrames: numInflightFrames)
        self.stateCaches = StateCaches(device: self.device, libraryPath: libraryPath)
        self.frameGraph = MetalFrameGraph(device: device, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
        
        self.maxInflightFrames = numInflightFrames
        
//        RenderBackend.backend = self
        
        RenderBackend._cachedBackend = _CachedRenderBackend(
            registerWindowTexture: { [self] (texture, context) in
                self.registerWindowTexture(texture: texture, context: context)
            },
            materialisePersistentTexture: { [self] texture in self.materialisePersistentTexture(texture) },
            materialisePersistentBuffer: { [self] buffer in self.materialisePersistentBuffer(buffer) },
            bufferContents: { [self] (buffer, range) in self.bufferContents(for: buffer, range: range) },
            bufferDidModifyRange: { [self] (buffer, range) in self.buffer(buffer, didModifyRange: range) },
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
            maxInflightFrames: { [self] in self.maxInflightFrames })
    }
    
    public var renderDevice: Any {
        return self.device
    }
    
    public func beginFrameResourceAccess() {
        self.frameGraph.beginFrameResourceAccess()
    }
    
    public func materialisePersistentTexture(_ texture: Texture) {
        resourceRegistry.accessQueue.sync {
            _ = self.resourceRegistry.allocateTexture(texture, properties: TextureUsageProperties(texture.descriptor.usageHint))
        }
    }
    
    public func registerWindowTexture(texture: Texture, context: Any) {
        self.resourceRegistry.registerWindowTexture(texture: texture, context: context)
    }
    
    public func materialisePersistentBuffer(_ buffer: Buffer) {
        _ = resourceRegistry.accessQueue.sync {
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
    
    public func executeFrameGraph(passes: [RenderPassRecord], resourceUsages: ResourceUsages, commands: [FrameGraphCommand], completion: @escaping () -> Void) {
        autoreleasepool {
            self.frameGraph.executeFrameGraph(passes: passes, resourceUsages: resourceUsages, commands: commands, completion: completion)
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
        return resourceRegistry.accessQueue.sync {
            resourceRegistry.bufferContents(for: buffer) + range.lowerBound
        }
    }
    
    public func buffer(_ buffer: Buffer, didModifyRange range: Range<Int>) {
        #if os(macOS)
        if range.isEmpty { return }
        if buffer.descriptor.storageMode == .managed {
            let mtlBuffer = resourceRegistry[buffer]!
            let offsetRange = (range.lowerBound + mtlBuffer.offset)..<(range.upperBound + mtlBuffer.offset)
            mtlBuffer.buffer.didModifyRange(offsetRange)
        }
        #endif
    }
    
    public func backingResource(_ resource: Resource) -> Any? {
        return resourceRegistry.accessQueue.sync {
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
    
    public func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) {
        resourceRegistry.accessQueue.sync {
            resourceRegistry.replaceTextureRegion(texture: texture, region: region, mipmapLevel: mipmapLevel, withBytes: bytes, bytesPerRow: bytesPerRow)
        }
    }
    
    public func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, slice: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int) {
        resourceRegistry.accessQueue.sync {
            resourceRegistry.replaceTextureRegion(texture: texture, region: region, mipmapLevel: mipmapLevel, slice: slice, withBytes: bytes, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerImage)
        }
    }
    
    public func renderPipelineReflection(descriptor: _RenderPipelineDescriptor, renderTarget: _RenderTargetDescriptor) -> PipelineReflection {
        return self.stateCaches.renderPipelineAccessQueue.sync { self.stateCaches.renderPipelineReflection(descriptor: descriptor, renderTarget: renderTarget) }
    }
    
    public func computePipelineReflection(descriptor: ComputePipelineDescriptor) -> PipelineReflection {
        return self.stateCaches.computePipelineAccessQueue.sync { self.stateCaches.computePipelineReflection(descriptor: descriptor) }
    }
    
}
