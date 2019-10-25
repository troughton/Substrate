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

public final class MetalBackend : _FrameGraphBackend {
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
        
        RenderBackend.backend = self

        // Push constants go immediately after the argument buffers.
        RenderBackend.pushConstantPath = ResourceBindingPath(stages: [.vertex, .fragment], type: .buffer, argumentBufferIndex: nil, index: 8)
    }
    
    public var renderDevice: Any {
        return self.device
    }
    
    @usableFromInline func beginFrameResourceAccess() {
        self.frameGraph.beginFrameResourceAccess()
    }
    
    @usableFromInline func materialisePersistentTexture(_ texture: Texture) {
        resourceRegistry.accessLock.withWriteLock {
            _ = self.resourceRegistry.allocateTexture(texture, properties: MetalTextureUsageProperties(texture.descriptor.usageHint))
        }
    }
    
    @usableFromInline func registerWindowTexture(texture: Texture, context: Any) {
        self.resourceRegistry.registerWindowTexture(texture: texture, context: context)
    }
    
    @usableFromInline func materialisePersistentBuffer(_ buffer: Buffer) {
        _ = resourceRegistry.accessLock.withWriteLock {
            self.resourceRegistry.allocateBuffer(buffer)
        }
    }
    
    @usableFromInline func materialiseHeap(_ heap: Heap) {
        self.resourceRegistry.allocateHeap(heap)
    }

    @usableFromInline func dispose(texture: Texture) {
        self.resourceRegistry.disposeTexture(texture, keepingReference: false, waitEvent: resourceRegistry.textureWaitEvents[texture] ?? MetalWaitEvent())
    }
    
    @usableFromInline func dispose(buffer: Buffer) {
        self.resourceRegistry.disposeBuffer(buffer, keepingReference: false, waitEvent: resourceRegistry.bufferWaitEvents[buffer] ?? MetalWaitEvent())
    }
    
    @usableFromInline func dispose(argumentBuffer: _ArgumentBuffer) {
        self.resourceRegistry.disposeArgumentBuffer(argumentBuffer, keepingReference: false, waitEvent: resourceRegistry.argumentBufferWaitEvents[argumentBuffer] ?? MetalWaitEvent())
    }
    
    @usableFromInline func dispose(argumentBufferArray: _ArgumentBufferArray) {
        self.resourceRegistry.disposeArgumentBufferArray(argumentBufferArray, keepingReference: false, waitEvent: resourceRegistry.argumentBufferArrayWaitEvents[argumentBufferArray] ?? MetalWaitEvent())
    }
    
    @usableFromInline func executeFrameGraph(passes: [RenderPassRecord], dependencyTable: DependencyTable<SwiftFrameGraph.DependencyType>, resourceUsages: ResourceUsages, completion: @escaping () -> Void) {
        autoreleasepool {
            self.frameGraph.executeFrameGraph(passes: passes, dependencyTable: dependencyTable, resourceUsages: resourceUsages, completion: completion)
        }
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
        return resourceRegistry.accessLock.withWriteLock {
            resourceRegistry.bufferContents(for: buffer) + range.lowerBound
        }
    }
    
    @usableFromInline func buffer(_ buffer: Buffer, didModifyRange range: Range<Int>) {
        #if os(macOS)
        if range.isEmpty { return }
        if buffer.descriptor.storageMode == .managed {
            let mtlBuffer = resourceRegistry.accessLock.withReadLock { resourceRegistry[buffer]! }
            let offsetRange = (range.lowerBound + mtlBuffer.offset)..<(range.upperBound + mtlBuffer.offset)
            mtlBuffer.buffer.didModifyRange(offsetRange)
        }
        #endif
    }

    @usableFromInline func registerExternalResource(_ resource: Resource, backingResource: Any) {
        self.resourceRegistry.importExternalResource(resource, backingResource: backingResource)
    }
    
    @usableFromInline func backingResource(_ resource: Resource) -> Any? {
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
        resourceRegistry.accessLock.withWriteLock {
            resourceRegistry.copyTextureBytes(from: texture, to: bytes, bytesPerRow: bytesPerRow, region: region, mipmapLevel: mipmapLevel)
        }
    }
    
    @usableFromInline func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) {
        resourceRegistry.accessLock.withWriteLock {
            resourceRegistry.replaceTextureRegion(texture: texture, region: region, mipmapLevel: mipmapLevel, withBytes: bytes, bytesPerRow: bytesPerRow)
        }
    }
    
    @usableFromInline func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, slice: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int) {
        resourceRegistry.accessLock.withWriteLock {
            resourceRegistry.replaceTextureRegion(texture: texture, region: region, mipmapLevel: mipmapLevel, slice: slice, withBytes: bytes, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerImage)
        }
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
