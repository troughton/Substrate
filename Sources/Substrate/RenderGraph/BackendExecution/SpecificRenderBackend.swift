//
//  File.swift
//  
//
//  Created by Thomas Roughton on 7/04/20.
//

import SubstrateUtilities
import Dispatch

protocol SpecificRenderBackend: _RenderBackendProtocol {
    associatedtype RenderTargetDescriptor: BackendRenderTargetDescriptor
    associatedtype CommandBuffer: BackendCommandBuffer where CommandBuffer.Backend == Self
    
    associatedtype QueueImpl: Substrate.BackendQueue where QueueImpl.Backend == Self
    associatedtype Event
    associatedtype CompactedResourceCommandType: Sendable
    
    associatedtype TransientResourceRegistry: BackendTransientResourceRegistry where TransientResourceRegistry.Backend == Self
    associatedtype PersistentResourceRegistry: BackendPersistentResourceRegistry where PersistentResourceRegistry.Backend == Self
    
    associatedtype ResourceReference
    associatedtype BufferReference
    associatedtype TextureReference
    associatedtype ArgumentBufferReference
    associatedtype VisibleFunctionTableReference
    associatedtype IntersectionFunctionTableReference
    
    associatedtype InterEncoderDependencyType: Dependency
    
    static var activeContextTaskLocal: TaskLocal<RenderGraphContextImpl<Self>?> { get }
    static var requiresResourceResidencyTracking: Bool { get }
    
    var supportsMemorylessAttachments: Bool { get }
    
    func makeQueue(renderGraphQueue: Queue) -> QueueImpl
    func makeSyncEvent(for queue: Queue) -> Event
    func freeSyncEvent(for queue: Queue)
    func syncEvent(for queue: Queue) -> Event?
    
    func reloadShaderLibraryIfNeeded() async
    
    var resourceRegistry: PersistentResourceRegistry { get }
    func makeTransientRegistry(index: Int, inflightFrameCount: Int, queue: Queue) -> TransientResourceRegistry
    
    func compactResourceCommands(queue: Queue, commandInfo: FrameCommandInfo<RenderTargetDescriptor>, commandGenerator: ResourceCommandGenerator<Self>, into: inout [CompactedResourceCommand<CompactedResourceCommandType>]) async
    func didCompleteCommand(_ index: UInt64, queue: Queue, context: RenderGraphContextImpl<Self>) // Called on the context's DispatchQueue.
    
    func fillVisibleFunctionTable(_ table: VisibleFunctionTable, firstUseCommandIndex: Int) async
    func fillIntersectionFunctionTable(_ table: IntersectionFunctionTable, firstUseCommandIndex: Int) async
}

extension SpecificRenderBackend {
    func didCompleteCommand(_ index: UInt64, queue: Queue, context: RenderGraphContextImpl<Self>) {
        
    }
}

protocol BackendRenderTargetDescriptor: AnyObject, Sendable {
    init(renderPass: RenderPassRecord)
    var descriptor: RenderTargetsDescriptor { get }
    func descriptorMergedWithPass(_ pass: RenderPassRecord, allRenderPasses: [RenderPassRecord], storedTextures: inout [Texture]) -> Self
    func finalise(allRenderPasses: [RenderPassRecord], storedTextures: inout [Texture])
}

protocol BackendQueue: AnyObject {
    associatedtype Backend: SpecificRenderBackend where Backend.QueueImpl == Self
    
    func makeCommandBuffer(
        commandInfo: FrameCommandInfo<Backend.RenderTargetDescriptor>,
        transientRegistry: Backend.TransientResourceRegistry?,
        compactedResourceCommands: [CompactedResourceCommand<Backend.CompactedResourceCommandType>]) -> Backend.CommandBuffer
}

protocol BackendCommandBuffer: AnyObject, Sendable {
    associatedtype Backend: SpecificRenderBackend where Backend.CommandBuffer == Self
    
    func encodeCommands(encoderIndex: Int) async
    
    func waitForEvent(_ event: Backend.Event, value: UInt64)
    func signalEvent(_ event: Backend.Event, value: UInt64)
    func presentSwapchains(resourceRegistry: Backend.TransientResourceRegistry, onPresented: RenderGraph.SwapchainPresentedCallback?)
    func commit(onCompletion: @escaping (Self) -> Void)
    
    var gpuStartTime: DispatchTime { get }
    var gpuEndTime: DispatchTime { get }
    
    var error: Error? { get }
}

protocol BackendTransientResourceRegistry: Sendable {
    static func isAliasedHeapResource(resource: Resource) -> Bool
    
    // ResourceRegistry requirements:
    associatedtype Backend: SpecificRenderBackend where Backend.TransientResourceRegistry == Self
    
    var accessLock: SpinLock { get }
    
    func prepareFrame()
    func cycleFrames()
    func allocateArgumentBufferIfNeeded(_ buffer: ArgumentBuffer) -> Backend.ArgumentBufferReference
    
    // TransientResourceRegistry requirements:
    
    func registerWindowTexture(for texture: Texture, swapchain: Swapchain) async
    
    func allocateBufferIfNeeded(_ buffer: Buffer, forceGPUPrivate: Bool) -> Backend.BufferReference
    func allocateTextureIfNeeded(_ texture: Texture, forceGPUPrivate: Bool, isStoredThisFrame: Bool) async -> Backend.TextureReference
    func allocateWindowHandleTexture(_ texture: Texture) async throws -> Backend.TextureReference
    func allocateTextureView(_ texture: Texture) -> Backend.TextureReference
#if canImport(Metal)
    func allocateArgumentBufferView(argumentBuffer: ArgumentBuffer, buffer: Buffer, offset: Int) -> Backend.BufferReference
#endif
    
    func setDisposalFences(on resource: Resource, to fences: [FenceDependency])
    func disposeTexture(_ texture: Texture, waitEvent: ContextWaitEvent)
    func disposeBuffer(_ buffer: Buffer, waitEvent: ContextWaitEvent)
    func disposeArgumentBuffer(_ buffer: ArgumentBuffer, waitEvent: ContextWaitEvent)
    
    func withHeapAliasingFencesIfPresent(for resourceHandle: Resource.Handle, perform: (inout [FenceDependency]) -> Void)
    
    var textureWaitEvents: TransientResourceMap<Texture, ContextWaitEvent> { get }
    var bufferWaitEvents: TransientResourceMap<Buffer, ContextWaitEvent> { get }
    var argumentBufferWaitEvents: TransientResourceMap<ArgumentBuffer, ContextWaitEvent>? { get }
    var historyBufferResourceWaitEvents: [Resource : ContextWaitEvent] { get }
}

extension BackendTransientResourceRegistry {
    var argumentBufferWaitEvents: TransientResourceMap<ArgumentBuffer, ContextWaitEvent>? { nil }
}

protocol BackendPersistentResourceRegistry: AnyObject {
    
    // ResourceRegistry requirements:
    associatedtype Backend: SpecificRenderBackend where Backend.PersistentResourceRegistry == Self
    
    func cycleFrames()
    
    // PersistentResourceRegistry requirements:
    
    subscript(sampler: SamplerDescriptor) -> SamplerState { get async }
    
    func allocateBuffer(_ buffer: Buffer) -> Backend.BufferReference?
    func allocateTexture(_ texture: Texture) -> Backend.TextureReference?
    func allocateArgumentBuffer(_ buffer: ArgumentBuffer) -> Backend.ArgumentBufferReference?
    
    func allocateVisibleFunctionTable(_ table: VisibleFunctionTable) -> Backend.VisibleFunctionTableReference?
    func allocateIntersectionFunctionTable(_ table: IntersectionFunctionTable) -> Backend.IntersectionFunctionTableReference?
    
    func prepareMultiframeBuffer(_ buffer: Buffer, frameIndex: UInt64)
    func prepareMultiframeTexture(_ texture: Texture, frameIndex: UInt64)
    
    func dispose(resource: Resource)
}
