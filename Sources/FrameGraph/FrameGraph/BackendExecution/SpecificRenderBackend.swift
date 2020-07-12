//
//  File.swift
//  
//
//  Created by Thomas Roughton on 7/04/20.
//

import FrameGraphUtilities

protocol SpecificRenderBackend: _RenderBackendProtocol {
    associatedtype RenderTargetDescriptor: BackendRenderTargetDescriptor
    associatedtype CommandBuffer: BackendCommandBuffer where CommandBuffer.Backend == Self
    
    associatedtype BackendQueue
    associatedtype Event
    associatedtype CompactedResourceCommandType
    
    associatedtype TransientResourceRegistry: BackendTransientResourceRegistry where TransientResourceRegistry.Backend == Self
    associatedtype PersistentResourceRegistry: BackendPersistentResourceRegistry where PersistentResourceRegistry.Backend == Self
    
    associatedtype BufferReference
    associatedtype TextureReference
    associatedtype ArgumentBufferReference
    associatedtype ArgumentBufferArrayReference
    associatedtype SamplerReference
    
    associatedtype InterEncoderDependencyType: Dependency
    
    static var requiresResourceResidencyTracking: Bool { get }
    static var requiresBufferUsage: Bool { get }
    static var requiresTextureLayoutTransitions: Bool { get }
    
    func makeQueue(frameGraphQueue: Queue) -> BackendQueue
    func makeSyncEvent(for queue: Queue) -> Event
    func freeSyncEvent(for queue: Queue)
    func syncEvent(for queue: Queue) -> Event?
    
    func setActiveContext(_ context: FrameGraphContextImpl<Self>?)
    
    var resourceRegistry: PersistentResourceRegistry { get }
    func makeTransientRegistry(index: Int, inflightFrameCount: Int) -> TransientResourceRegistry
    
    func compactResourceCommands(queue: Queue, resourceMap: FrameResourceMap<Self>, commandInfo: FrameCommandInfo<Self>, commandGenerator: ResourceCommandGenerator<Self>, into: inout [CompactedResourceCommand<CompactedResourceCommandType>])
    
    static func fillArgumentBuffer(_ argumentBuffer: _ArgumentBuffer, storage: ArgumentBufferReference, resourceMap: FrameResourceMap<Self>)
    static func fillArgumentBufferArray(_ argumentBufferArray: _ArgumentBufferArray, storage: ArgumentBufferArrayReference, resourceMap: FrameResourceMap<Self>)
}

protocol BackendRenderTargetDescriptor: class {
    init(renderPass: RenderPassRecord)
    var descriptor: RenderTargetDescriptor { get }
    func descriptorMergedWithPass(_ pass: RenderPassRecord, resourceUsages: ResourceUsages, storedTextures: inout [Texture]) -> Self
    func finalise(resourceUsages: ResourceUsages, storedTextures: inout [Texture])
}

protocol BackendCommandBuffer: class {
    associatedtype Backend: SpecificRenderBackend
    
    init(backend: Backend,
         queue: Backend.BackendQueue,
         commandInfo: FrameCommandInfo<Backend>,
         textureUsages: [Texture: TextureUsageProperties],
         resourceMap: FrameResourceMap<Backend>,
         compactedResourceCommands: [CompactedResourceCommand<Backend.CompactedResourceCommandType>])
    
    func encodeCommands(encoderIndex: Int)
    
    func waitForEvent(_ event: Backend.Event, value: UInt64)
    func signalEvent(_ event: Backend.Event, value: UInt64)
    func presentSwapchains(resourceRegistry: Backend.TransientResourceRegistry)
    func commit(onCompletion: @escaping (Self) -> Void)
    
    var gpuStartTime: Double { get }
    var gpuEndTime: Double { get }
    
    var error: Error? { get }
}

protocol ResourceRegistry: class {
    associatedtype Backend: SpecificRenderBackend
    
    subscript(buffer: Buffer) -> Backend.BufferReference? { get }
    subscript(texture: Texture) -> Backend.TextureReference? { get }
    subscript(argumentBuffer: _ArgumentBuffer) -> Backend.ArgumentBufferReference? { get }
    subscript(argumentBufferArray: _ArgumentBufferArray) -> Backend.ArgumentBufferArrayReference? { get }
    
    func prepareFrame()
    func cycleFrames()
    func allocateArgumentBufferIfNeeded(_ buffer: _ArgumentBuffer) -> Backend.ArgumentBufferReference
    func allocateArgumentBufferArrayIfNeeded(_ buffer: _ArgumentBufferArray) -> Backend.ArgumentBufferArrayReference
}

protocol BackendTransientResourceRegistry: ResourceRegistry where Backend.TransientResourceRegistry == Self {
    static func isAliasedHeapResource(resource: Resource) -> Bool
    
    var accessLock: SpinLock { get set }
    
    func allocateBufferIfNeeded(_ buffer: Buffer, usage: BufferUsage, forceGPUPrivate: Bool) -> Backend.BufferReference
    func allocateTextureIfNeeded(_ texture: Texture, usage: TextureUsageProperties, forceGPUPrivate: Bool) -> Backend.TextureReference
    func allocateWindowHandleTexture(_ texture: Texture) throws -> Backend.TextureReference
    func allocateTextureView(_ texture: Texture, usage: TextureUsageProperties, resourceMap: FrameResourceMap<Backend>) -> Backend.TextureReference
    
    func setDisposalFences(on resource: Resource, to fences: [FenceDependency])
    func disposeTexture(_ texture: Texture, waitEvent: ContextWaitEvent)
    func disposeBuffer(_ buffer: Buffer, waitEvent: ContextWaitEvent)
    func disposeArgumentBuffer(_ buffer: _ArgumentBuffer, waitEvent: ContextWaitEvent)
    func disposeArgumentBufferArray(_ buffer: _ArgumentBufferArray, waitEvent: ContextWaitEvent)
    
    func withHeapAliasingFencesIfPresent(for resourceHandle: Resource.Handle, perform: (inout [FenceDependency]) -> Void)
    
    var textureWaitEvents: TransientResourceMap<Texture, ContextWaitEvent> { get }
    var bufferWaitEvents: TransientResourceMap<Buffer, ContextWaitEvent> { get }
    var argumentBufferWaitEvents: TransientResourceMap<_ArgumentBuffer, ContextWaitEvent>? { get }
    var argumentBufferArrayWaitEvents: TransientResourceMap<_ArgumentBufferArray, ContextWaitEvent>? { get }
    var historyBufferResourceWaitEvents: [Resource : ContextWaitEvent] { get }
}

extension BackendTransientResourceRegistry {
    var argumentBufferWaitEvents: TransientResourceMap<_ArgumentBuffer, ContextWaitEvent>? { nil }
    var argumentBufferArrayWaitEvents: TransientResourceMap<_ArgumentBufferArray, ContextWaitEvent>? { nil }
}

protocol BackendPersistentResourceRegistry: ResourceRegistry where Backend.PersistentResourceRegistry == Self {
    subscript(sampler: SamplerDescriptor) -> Backend.SamplerReference { get }
    
    func allocateBuffer(_ buffer: Buffer, usage: BufferUsage) -> Backend.BufferReference?
    func allocateTexture(_ texture: Texture, usage: TextureUsageProperties) -> Backend.TextureReference?
    
    func disposeTexture(_ texture: Texture)
    func disposeBuffer(_ buffer: Buffer)
    func disposeArgumentBuffer(_ buffer: _ArgumentBuffer)
    func disposeArgumentBufferArray(_ buffer: _ArgumentBufferArray)
}
