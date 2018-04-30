//
//  MetalRenderer.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 23/12/17.
//

import RenderAPI
import FrameGraph
import Metal

public final class MetalBackend : RenderBackendProtocol, FrameGraphBackend {
    public let maxInflightFrames : Int
    
    let device : MTLDevice
    let resourceRegistry : ResourceRegistry
    let stateCaches : StateCaches
    let frameGraph : MetalFrameGraph
    
    public init(numInflightFrames: Int) {
        self.device = MTLCreateSystemDefaultDevice()!
        self.resourceRegistry = ResourceRegistry(device: self.device, numInflightFrames: numInflightFrames)
        self.stateCaches = StateCaches(device: self.device)
        self.frameGraph = MetalFrameGraph(device: device, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
        
        self.maxInflightFrames = numInflightFrames
        
        RenderBackend.backend = self
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
        self.resourceRegistry.disposeTexture(texture)
    }
    
    public func dispose(buffer: Buffer) {
        self.resourceRegistry.disposeBuffer(buffer)
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
    
    public func setReflectionRenderPipeline(descriptor: RenderPipelineDescriptor, renderTarget: RenderTargetDescriptor) {
        self.stateCaches.setReflectionRenderPipeline(descriptor: descriptor, renderTarget: renderTarget)
    }
    
    public func setReflectionComputePipeline(descriptor: ComputePipelineDescriptor) {
        self.stateCaches.setReflectionComputePipeline(descriptor: descriptor)
    }
    
    public func bindingPath(argumentName: String, arrayIndex: Int, argumentBufferPath: ResourceBindingPath?) -> ResourceBindingPath? {
        return self.stateCaches.bindingPath(argumentName: argumentName, arrayIndex: arrayIndex, argumentBufferPath: argumentBufferPath)
    }
    
    public func bindingPath(argumentBuffer: ArgumentBuffer, argumentName: String) -> ResourceBindingPath? {
        return self.stateCaches.bindingPath(argumentName: argumentName, arrayIndex: 0, argumentBufferPath: nil)
    }
    
    public func argumentReflection(at path: ResourceBindingPath) -> ArgumentReflection? {
        return self.stateCaches.argumentReflection(at: path)
    }
    
    public func bindingIsActive(at path: ResourceBindingPath) -> Bool {
        return self.argumentReflection(at: path)?.isActive ?? false
    }
    
}
