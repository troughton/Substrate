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
            renderPipelineReflection: { [self] (pipeline, renderTarget) in self.renderPipelineReflection(descriptor: pipeline, renderTarget: renderTarget) },
            computePipelineReflection: { [self] (pipeline) in self.computePipelineReflection(descriptor: pipeline) },
            disposeTexture: { [self] texture in self.dispose(texture: texture) },
            disposeBuffer: { [self] buffer in self.dispose(buffer: buffer) },
            disposeArgumentBuffer: { [self] argumentBuffer in self.dispose(argumentBuffer: argumentBuffer) },
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
        self.resourceRegistry.allocateTextureIfNeeded(texture, usage: MTLTextureUsage(texture.descriptor.usageHint))
    }
    
    public func registerWindowTexture(texture: Texture, context: Any) {
        self.resourceRegistry.registerWindowTexture(texture: texture, context: context)
    }
    
    public func materialisePersistentBuffer(_ buffer: Buffer) {
        self.resourceRegistry.allocateBufferIfNeeded(buffer)
    }
    
    public func dispose(texture: Texture) {
        self.resourceRegistry.disposeTexture(texture, readFence: nil, writeFences: nil)
    }
    
    public func dispose(buffer: Buffer) {
        self.resourceRegistry.disposeBuffer(buffer, readFence: nil, writeFences: nil)
    }
    
    public func dispose(argumentBuffer: ArgumentBuffer) {
        self.resourceRegistry.disposeArgumentBuffer(argumentBuffer)
    }
    
    public func executeFrameGraph(passes: [RenderPassRecord], resourceUsages: ResourceUsages, commands: [FrameGraphCommand], completion: @escaping () -> Void) {
        autoreleasepool {
            self.frameGraph.executeFrameGraph(passes: passes, resourceUsages: resourceUsages, commands: commands, completion: completion)
        }
    }
    
    public var isDepth24Stencil8PixelFormatSupported: Bool {
        return self.device.isDepth24Stencil8PixelFormatSupported
    }
    
    public var threadExecutionWidth: Int {
        return self.stateCaches.currentThreadExecutionWidth
    }
    
    public func bufferContents(for buffer: Buffer, range: Range<Int>) -> UnsafeMutableRawPointer {
        return resourceRegistry.bufferContents(for: buffer) + range.lowerBound
    }
    
    public func buffer(_ buffer: Buffer, didModifyRange range: Range<Int>) {
        if buffer.descriptor.storageMode == .managed {
            let mtlBuffer = resourceRegistry[buffer]!
            let offsetRange = (range.lowerBound + mtlBuffer.offset)..<(range.upperBound + mtlBuffer.offset)
            mtlBuffer.buffer.didModifyRange(offsetRange)
        }
    }
    
    public func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) {
        resourceRegistry.replaceTextureRegion(texture: texture, region: region, mipmapLevel: mipmapLevel, withBytes: bytes, bytesPerRow: bytesPerRow)
    }
    
    public func renderPipelineReflection(descriptor: RenderPipelineDescriptor, renderTarget: RenderTargetDescriptor) -> PipelineReflection {
        return self.stateCaches.renderPipelineReflection(descriptor: descriptor, renderTarget: renderTarget)
    }
    
    public func computePipelineReflection(descriptor: ComputePipelineDescriptor) -> PipelineReflection {
        return self.stateCaches.computePipelineReflection(descriptor: descriptor)
    }
    
}
