//
//  MetalRenderer.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 23/12/17.
//

#if canImport(Metal)

import SubstrateUtilities
@preconcurrency import Metal

extension MTLResourceOptions {
    static var substrateTrackedHazards : MTLResourceOptions {
        // This gives us a convenient way to toggle whether the RenderGraph or Metal should handle resource tracking.
#if SUBSTRATE_USE_PLATFORM_HAZARD_TRACKING
        if #available(macOS 10.15, *) {
            return .hazardTrackingModeTracked
        } else {
            // Fallback on earlier versions
            return []
        }
#else
        return .hazardTrackingModeUntracked
#endif
    }
}

@available(OSX 10.15, iOS 13.0, tvOS 13.0, *)
extension MTLHazardTrackingMode {
    static var substrateTrackedHazards : MTLHazardTrackingMode {
        // This gives us a convenient way to toggle whether the RenderGraph or Metal should handle resource tracking.
#if SUBSTRATE_USE_PLATFORM_HAZARD_TRACKING
        return .tracked
#else
        return .untracked
#endif
    }
}

#if targetEnvironment(macCatalyst)
@objc protocol MTLBufferShim: MTLResource {
    func didModifyRange(_ range: NSRange)
}
#endif

extension MTLDevice {
    @inlinable
    public var isAppleSiliconGPU: Bool {
        #if targetEnvironment(simulator)
        return false
        #elseif (os(iOS) || os(tvOS) || os(watchOS)) && !(targetEnvironment(macCatalyst) || targetEnvironment(simulator))
        return true
        #else
        if #available(macOS 11.0, macCatalyst 14.0, *) {
            return self.supportsFamily(.apple1)
        } else {
            return false
        }
        #endif
    }
}

fileprivate func ??<T>(lhs: T?, rhs: () async -> T) async -> T {
    if let result = lhs {
        return result
    }
    return await rhs()
}

public final class MetalBackend : SpecificRenderBackend, @unchecked Sendable {
    @TaskLocal static var activeContext: RenderGraphContextImpl<MetalBackend>? = nil
    
    static var activeContextTaskLocal: TaskLocal<RenderGraphContextImpl<MetalBackend>?> { $activeContext }
    
    typealias BufferReference = MTLBufferReference
    typealias TextureReference = MTLTextureReference
    typealias ArgumentBufferReference = MTLBufferReference
    typealias VisibleFunctionTableReference = MTLVisibleFunctionTable
    typealias IntersectionFunctionTableReference = MTLIntersectionFunctionTable
    typealias SamplerReference = MTLSamplerState
    typealias ResourceReference = MTLResource
    
    typealias TransientResourceRegistry = MetalTransientResourceRegistry
    typealias PersistentResourceRegistry = MetalPersistentResourceRegistry
    
    typealias CommandBuffer = MetalCommandBuffer
    typealias RenderTargetDescriptor = MetalRenderTargetDescriptor
    typealias Event = MTLEvent
    typealias BackendQueue = MTLCommandQueue
    
    typealias CompactedResourceCommandType = MetalCompactedResourceCommandType
    typealias InterEncoderDependencyType = CoarseDependency
    
    let device : MTLDevice
    let resourceRegistry : MetalPersistentResourceRegistry
    let stateCaches : MetalStateCaches
    let enableValidation : Bool
    let enableShaderHotReloading : Bool
    
    var queueSyncEvents = [MTLEvent?](repeating: nil, count: QueueRegistry.maxQueues)
    
    init(device: MTLDevice?, libraryPath: String? = nil, enableValidation: Bool = true, enableShaderHotReloading: Bool = true) {
        self.device = device ?? MTLCreateSystemDefaultDevice()!
        self.stateCaches = MetalStateCaches(device: self.device, libraryPath: libraryPath)
        self.resourceRegistry = MetalPersistentResourceRegistry(device: self.device, stateCaches: self.stateCaches)
        self.stateCaches.resourceRegistry = self.resourceRegistry
        self.enableValidation = enableValidation
        self.enableShaderHotReloading = enableShaderHotReloading
    }
    
    public var api : RenderAPI {
        return .metal
    }
    
    public var renderDevice: Any {
        return self.device
    }
    
    @usableFromInline var argumentBufferImpl: _ArgumentBufferImpl.Type {
        MetalArgumentBufferImpl.self
    }
    
    public var shaderLibrary: MTLLibrary {
        get {
            return self.stateCaches.functionCache.library
        }
    }
    
    func reloadShaderLibraryIfNeeded() async {
        if self.enableShaderHotReloading {
            await self.stateCaches.checkForLibraryReload()
        }
    }
    
    @usableFromInline func materialisePersistentResource(_ resource: Resource) -> Bool {
        switch resource.type {
        case .texture:
            return self.resourceRegistry.allocateTexture(Texture(resource)!) != nil
        case .buffer:
            return self.resourceRegistry.allocateBuffer(Buffer(resource)!) != nil
        case .heap:
            return self.resourceRegistry.allocateHeap(Heap(resource)!) != nil
        case .argumentBuffer:
            return self.resourceRegistry.allocateArgumentBuffer(ArgumentBuffer(resource)!) != nil
        case .argumentBufferArray:
            return self.resourceRegistry.allocateArgumentBufferArray(ArgumentBufferArray(resource)!) != nil
        case .accelerationStructure:
            return self.resourceRegistry.allocateAccelerationStructure(AccelerationStructure(resource)!) != nil
        case .visibleFunctionTable:
            return self.resourceRegistry.allocateVisibleFunctionTable(VisibleFunctionTable(resource)!) != nil
        case .intersectionFunctionTable:
            return self.resourceRegistry.allocateIntersectionFunctionTable(IntersectionFunctionTable(resource)!) != nil
        default:
            preconditionFailure("Unhandled resource type in materialiseResource")
        }
    }
    
    @usableFromInline func replaceBackingResource(for resource: Resource, with: Any?) -> Any? {
        self.resourceRegistry.replaceBackingResource(for: resource, with: with)
    }
    
    @usableFromInline func updateLabel(on resource: Resource) {
        if let buffer = Buffer(resource), let mtlBuffer = buffer.mtlBuffer {
            if !buffer._usesPersistentRegistry, buffer.storageMode == .shared || buffer.storageMode == .managed {
                if let label = buffer.label {
                    mtlBuffer.buffer.addDebugMarker(label, range: mtlBuffer.offset..<(mtlBuffer.offset + buffer.descriptor.length))
                }
            } else {
                mtlBuffer.buffer.label = buffer.label
            }
        } else if let argumentBuffer = ArgumentBuffer(resource), let mtlBuffer = argumentBuffer.mtlBuffer {
            if !argumentBuffer._usesPersistentRegistry, argumentBuffer.storageMode == .shared || argumentBuffer.storageMode == .managed {
                if let label = argumentBuffer.label {
                    mtlBuffer.buffer.addDebugMarker(label, range: mtlBuffer.offset..<(mtlBuffer.offset + argumentBuffer.descriptor.bufferLength))
                }
            } else {
                mtlBuffer.buffer.label = argumentBuffer.label
            }
        } else if let texture = Texture(resource) {
            texture.mtlTexture?.label = texture.label
        } else if let heap = Heap(resource) {
            heap.mtlHeap.label = heap.label
        } else if let accelerationStructure = AccelerationStructure(resource) {
            accelerationStructure.mtlAccelerationStructure?.label = accelerationStructure.label
        } else if let table = VisibleFunctionTable(resource) {
            table.mtlVisibleFunctionTable?.label = table.label
        } else if let table = IntersectionFunctionTable(resource) {
            table.mtlIntersectionFunctionTable?.label = table.label
        }
    }
    
    @usableFromInline func updatePurgeableState(for resource: Resource, to newState: ResourcePurgeableState?) -> ResourcePurgeableState {
        let mtlState = MTLPurgeableState(newState)
        if let buffer = Buffer(resource), let mtlBuffer = buffer.mtlBuffer?.wrappedValue {
            return ResourcePurgeableState(
                MetalResourcePurgeabilityManager.instance.setPurgeableState(on: mtlBuffer, to: mtlState)
            )!
        } else if let texture = Texture(resource), let mtlTexture = texture.mtlTexture {
            return ResourcePurgeableState(
                MetalResourcePurgeabilityManager.instance.setPurgeableState(on: mtlTexture, to: mtlState)
            )!
        } else if let heap = Heap(resource) {
            return ResourcePurgeableState(
                MetalResourcePurgeabilityManager.instance.setPurgeableState(on: heap.mtlHeap, to: mtlState)
            )!
        }
        return .nonDiscardable
    }
    
    public func sizeAndAlignment(for buffer: BufferDescriptor) -> (size: Int, alignment: Int) {
        let sizeAndAlign = self.device.heapBufferSizeAndAlign(length: buffer.length, options: MTLResourceOptions(storageMode: buffer.storageMode, cacheMode: buffer.cacheMode, isAppleSiliconGPU: self.isAppleSiliconGPU))
        return (sizeAndAlign.size, sizeAndAlign.align)
    }
    
    public func sizeAndAlignment(for texture: TextureDescriptor) -> (size: Int, alignment: Int) {
        let sizeAndAlign = self.device.heapTextureSizeAndAlign(descriptor: MTLTextureDescriptor(texture, usage: MTLTextureUsage(texture.usageHint), isAppleSiliconGPU: self.isAppleSiliconGPU))
        return (sizeAndAlign.size, sizeAndAlign.align)
    }
    
    @usableFromInline func usedSize(for heap: Heap) -> Int {
        return heap.mtlHeap.usedSize
    }
    
    @usableFromInline func currentAllocatedSize(for heap: Heap) -> Int {
        return heap.mtlHeap.currentAllocatedSize
    }
    
    @usableFromInline func maxAvailableSize(forAlignment alignment: Int, in heap: Heap) -> Int {
        return heap.mtlHeap.maxAvailableSize(alignment: alignment)
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    @usableFromInline func accelerationStructureSizes(for descriptor: AccelerationStructureDescriptor) -> AccelerationStructureSizes {
        let sizes = self.device.accelerationStructureSizes(descriptor: descriptor.metalDescriptor())
        return AccelerationStructureSizes(accelerationStructureSize: sizes.accelerationStructureSize, buildScratchBufferSize: sizes.buildScratchBufferSize, refitScratchBufferSize: sizes.refitScratchBufferSize)
    }
    
    @usableFromInline func dispose(resource: Resource) {
        self.resourceRegistry.dispose(resource: resource)
    }
    
    public func supportsPixelFormat(_ pixelFormat: PixelFormat, usage: TextureUsage) -> Bool {
        let usage = usage.subtracting([.blitSource, .blitDestination])
        
        switch pixelFormat {
        case .depth24Unorm_stencil8:
            #if os(macOS) || targetEnvironment(macCatalyst)
            return self.device.isDepth24Stencil8PixelFormatSupported
            #else
            return false
            #endif
        case .r8Unorm_sRGB, .rg8Unorm_sRGB:
            #if targetEnvironment(simulator)
            return false
            #else
            return self.isAppleSiliconGPU
            #endif
        case .bc1_rgba, .bc1_rgba_sRGB,
             .bc2_rgba, .bc2_rgba_sRGB,
             .bc3_rgba, .bc3_rgba_sRGB,
             .bc4_rUnorm, .bc4_rSnorm,
             .bc5_rgUnorm, .bc5_rgSnorm,
             .bc6H_rgbFloat, .bc6H_rgbuFloat,
             .bc7_rgbaUnorm, .bc7_rgbaUnorm_sRGB:
            
            #if os(macOS)
            if usage.intersection([.shaderWrite, .colorAttachment]) != [] {
                return false
            }
            if #available(macOS 11.0, *) {
                return self.device.supportsBCTextureCompression
            }
            return !self.isAppleSiliconGPU
            #else
            return false
            #endif
        default:
            return true
        }
    }
    
    public nonisolated var supportsResourceGPUAddresses: Bool {
        #if !targetEnvironment(simulator)
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, *) {
            return true
        }
        #endif
        return false
    }
    
    public var isAppleSiliconGPU: Bool {
        return self.device.isAppleSiliconGPU
    }
    
    public var hasUnifiedMemory: Bool {
        #if (os(iOS) || os(tvOS) || os(watchOS)) && !(targetEnvironment(macCatalyst) || targetEnvironment(simulator))
        return true
        #else
        if #available(OSX 10.15, *) {
            return self.device.hasUnifiedMemory
        } else {
            return self.device.name.contains("Intel")
        }
        #endif
    }
    
    public var supportsMemorylessAttachments: Bool {
        return self.isAppleSiliconGPU
    }
    
    
    @usableFromInline func buffer(_ buffer: Buffer, didModifyRange range: Range<Int>) {
        #if os(macOS) || targetEnvironment(macCatalyst)
        if range.isEmpty || self.isAppleSiliconGPU { return }
        if buffer.descriptor.storageMode == .managed {
            let mtlBuffer = buffer.mtlBuffer!
            let offsetRange = (range.lowerBound + mtlBuffer.offset)..<(range.upperBound + mtlBuffer.offset)
            #if targetEnvironment(macCatalyst)
            unsafeBitCast(mtlBuffer.wrappedValue, to: MTLBufferShim.self).didModifyRange(NSMakeRange(offsetRange.lowerBound, offsetRange.count))
            #else
            mtlBuffer.wrappedValue.didModifyRange(offsetRange)
            #endif
        }
        #endif
    }
    
    @usableFromInline func buffer(_ buffer: ArgumentBuffer, didModifyRange range: Range<Int>) {
        #if os(macOS) || targetEnvironment(macCatalyst)
        if range.isEmpty || self.isAppleSiliconGPU { return }
        if buffer.descriptor.storageMode == .managed {
            let mtlBuffer = buffer.mtlBuffer!
            let offsetRange = (range.lowerBound + mtlBuffer.offset)..<(range.upperBound + mtlBuffer.offset)
            #if targetEnvironment(macCatalyst)
            unsafeBitCast(mtlBuffer.wrappedValue, to: MTLBufferShim.self).didModifyRange(NSMakeRange(offsetRange.lowerBound, offsetRange.count))
            #else
            mtlBuffer.wrappedValue.didModifyRange(offsetRange)
            #endif
        }
        #endif
    }

    @usableFromInline func registerExternalResource(_ resource: Resource, backingResource: Any) {
        self.resourceRegistry.importExternalResource(resource, backingResource: backingResource)
    }
    
    public func backingResource(_ resource: Resource) -> Any? {
        if let buffer = Buffer(resource) {
            return buffer.backingResourcePointer.map { Unmanaged<MTLBuffer>.fromOpaque(UnsafeRawPointer($0)).takeUnretainedValue() }
        } else if let texture = Texture(resource) {
            return texture.backingResourcePointer.map { Unmanaged<MTLTexture>.fromOpaque(UnsafeRawPointer($0)).takeUnretainedValue() }
        } else if let heap = Heap(resource) {
            return heap.backingResourcePointer.map { Unmanaged<MTLHeap>.fromOpaque(UnsafeRawPointer($0)).takeUnretainedValue() }
        } else if let argumentBuffer = ArgumentBuffer(resource) {
            return argumentBuffer.backingResourcePointer.map { Unmanaged<MTLBuffer>.fromOpaque(UnsafeRawPointer($0)).takeUnretainedValue() }
        } else if let argumentBufferArray = ArgumentBufferArray(resource) {
            return argumentBufferArray.backingResourcePointer.map { Unmanaged<MTLBuffer>.fromOpaque(UnsafeRawPointer($0)).takeUnretainedValue() }
        } else if let accelerationStructure = AccelerationStructure(resource), #available(macOS 11.0, iOS 14.0, *) {
            return accelerationStructure.backingResourcePointer.map { Unmanaged<MTLAccelerationStructure>.fromOpaque(UnsafeRawPointer($0)).takeUnretainedValue() }
        }
        return nil
    }
    
    @usableFromInline func renderPipelineState(for descriptor: RenderPipelineDescriptor) async throws -> RenderPipelineState {
        return try await self.stateCaches.renderPipelineState(descriptor: descriptor)
    }
    
    @usableFromInline func computePipelineState(for descriptor: ComputePipelineDescriptor) async throws -> ComputePipelineState {
        return try await self.stateCaches.computePipelineState(descriptor: descriptor)
    }
    
    @usableFromInline func depthStencilState(for descriptor: DepthStencilDescriptor) async -> DepthStencilState {
        return await self.stateCaches.depthStencilCache[descriptor]
    }
    
    @usableFromInline func samplerState(for descriptor: SamplerDescriptor) async -> SamplerState {
        return await self.resourceRegistry[descriptor]
    }
    
    @usableFromInline func copyTextureBytes(from texture: Texture, to bytes: UnsafeMutableRawPointer, bytesPerRow: Int, region: Region, mipmapLevel: Int) async {
        assert(texture.flags.contains(.persistent) || Self.activeContext != nil, "GPU memory for a transient texture may not be accessed outside of a RenderGraph RenderPass.")
        
        texture.mtlTexture!.getBytes(bytes, bytesPerRow: bytesPerRow, from: MTLRegion(region), mipmapLevel: mipmapLevel)
    }
    
    @usableFromInline func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) async {
        assert(texture.flags.contains(.persistent) || Self.activeContext != nil, "GPU memory for a transient texture may not be accessed outside of a RenderGraph RenderPass.")
        
        texture.mtlTexture!.replace(region: MTLRegion(region), mipmapLevel: mipmapLevel, withBytes: bytes, bytesPerRow: bytesPerRow)
    }
    
    @usableFromInline func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, slice: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int) async {
        assert(texture.flags.contains(.persistent) || Self.activeContext != nil, "GPU memory for a transient texture may not be accessed outside of a RenderGraph RenderPass.")
               
        texture.mtlTexture!.replace(region: MTLRegion(region), mipmapLevel: mipmapLevel, slice: slice, withBytes: bytes, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerImage)
    }
    
    @usableFromInline
    func renderPipelineReflection(descriptor: RenderPipelineDescriptor) async -> PipelineReflection? {
        return await self.stateCaches.renderPipelineReflection(descriptor: descriptor)
    }
    
    @usableFromInline
    func computePipelineReflection(descriptor: ComputePipelineDescriptor) async -> PipelineReflection? {
        return await self.stateCaches.computePipelineReflection(descriptor: descriptor)
    }

    @usableFromInline var pushConstantPath: ResourceBindingPath {
        return ResourceBindingPath(type: MTLArgumentType.buffer, index: 0, argumentBufferIndex: nil, stages: [.vertex, .fragment]) // Push constants go at index 0
    }
    
    @usableFromInline func argumentBufferPath(at index: Int, stages: RenderStages) -> ResourceBindingPath {
        let stages = MTLRenderStages(stages)
        return ResourceBindingPath(type: MTLArgumentType.buffer, index: index + 1, argumentBufferIndex: nil, stages: stages) // Push constants go at index 0
    }
    
    @usableFromInline func argumentBufferEncoder(for descriptor: ArgumentBufferDescriptor) -> UnsafeRawPointer? {
        return UnsafeRawPointer(Unmanaged.passUnretained(self.stateCaches.argumentEncoderCache[descriptor]).toOpaque())
    }
    
    // MARK: - SpecificRenderBackend conformance
    
    static var requiresResourceResidencyTracking: Bool {
        // Metal requires useResource calls for all untracked resources.
        return true
    }
    
    @usableFromInline var requiresEmulatedInputAttachments: Bool {
        return !self.isAppleSiliconGPU
    }
    
    func fillVisibleFunctionTable(_ table: VisibleFunctionTable, firstUseCommandIndex: Int) async {
        guard #available(macOS 11.0, iOS 14.0, *) else { preconditionFailure() }
        
        let pipelineState = Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(table.pipelineState.state)).takeUnretainedValue()
        let mtlTable = table.mtlVisibleFunctionTable!
        
        if let renderPipeline = pipelineState as? MTLRenderPipelineState {
            guard #available(macOS 12.0, iOS 15.0, *) else {
                preconditionFailure()
            }
            for (i, function) in table.functions.enumerated() {
                guard let function = function, let mtlFunction = try? await stateCaches.functionCache.function(for: function) else { continue }
                mtlTable.setFunction(renderPipeline.functionHandle(function: mtlFunction, stage: MTLRenderStages(table.descriptor.renderStage)), index: i)
            }
        } else {
            let computePipeline = pipelineState as! MTLComputePipelineState
            for (i, function) in table.functions.enumerated() {
                guard let function = function, let mtlFunction = try? await stateCaches.functionCache.function(for: function) else { continue }
                mtlTable.setFunction(computePipeline.functionHandle(function: mtlFunction), index: i)
            }
        }
    }

    func fillIntersectionFunctionTable(_ table: IntersectionFunctionTable, firstUseCommandIndex: Int) async {
        guard #available(macOS 11.0, iOS 14.0, *) else { preconditionFailure() }
        
        let pipelineState = Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(table.pipelineState.state)).takeUnretainedValue()
        let mtlTable = table.mtlIntersectionFunctionTable!
        
        for (i, buffer) in table.buffers.enumerated() {
            guard let buffer = buffer else { continue }
            switch buffer {
            case .buffer(let buffer, let offset):
                guard let mtlBufferRef = buffer.mtlBuffer else { continue }
                mtlTable.setBuffer(mtlBufferRef.buffer, offset: mtlBufferRef.offset + offset, index: i)
            case .argumentBuffer(let argumentBuffer):
                guard let mtlBufferRef = argumentBuffer.mtlBuffer else { continue }
                mtlTable.setBuffer(mtlBufferRef.buffer, offset: mtlBufferRef.offset, index: i)
            case .argumentBufferArray(let argumentBufferArray):
                guard let mtlBufferRef = argumentBufferArray[0].mtlBuffer else { continue }
                mtlTable.setBuffer(mtlBufferRef.buffer, offset: mtlBufferRef.offset, index: i)
            case .functionTable(let functionTable):
                guard let mtlFunctionTable = functionTable.mtlVisibleFunctionTable else { continue }
                mtlTable.setVisibleFunctionTable(mtlFunctionTable, bufferIndex: i)
            }
        }
        
        if let renderPipeline = pipelineState as? MTLRenderPipelineState {
            guard #available(macOS 12.0, iOS 15.0, *) else {
                preconditionFailure()
            }
            for (i, function) in table.functions.enumerated() {
                guard let function = function else { continue }
                
                switch function {
                case .defaultOpaqueFunction(let type, let inputAttributes):
                    let intersectionFunctionSignature = MTLIntersectionFunctionSignature(inputAttributes)
                    switch type {
                    case .triangle:
                        mtlTable.setOpaqueTriangleIntersectionFunction(signature: intersectionFunctionSignature, index: i)
                    case .curve:
                        mtlTable.setOpaqueCurveIntersectionFunction(signature: intersectionFunctionSignature, index: i)
                    }
                case .function(let functionDescriptor):
                    guard let mtlFunction = try? await stateCaches.functionCache.function(for: functionDescriptor) else { continue }
                    mtlTable.setFunction(renderPipeline.functionHandle(function: mtlFunction, stage: MTLRenderStages(table.descriptor.renderStage)), index: i)
                }
            }
        } else {
            let computePipeline = pipelineState as! MTLComputePipelineState
            for (i, function) in table.functions.enumerated() {
                guard let function = function else { continue }
                
                switch function {
                case .defaultOpaqueFunction(let type, let inputAttributes):
                    let intersectionFunctionSignature = MTLIntersectionFunctionSignature(inputAttributes)
                    switch type {
                    case .triangle:
                        mtlTable.setOpaqueTriangleIntersectionFunction(signature: intersectionFunctionSignature, index: i)
                    case .curve:
                        mtlTable.setOpaqueCurveIntersectionFunction(signature: intersectionFunctionSignature, index: i)
                    }
                case .function(let functionDescriptor):
                    guard let mtlFunction = try? await stateCaches.functionCache.function(for: functionDescriptor) else { continue }
                    mtlTable.setFunction(computePipeline.functionHandle(function: mtlFunction), index: i)
                }
            }
        }
    }
    
    func makeQueue(renderGraphQueue: Queue) -> MetalCommandQueue {
        return MetalCommandQueue(backend: self, queue: self.device.makeCommandQueue()!)
    }

    func makeSyncEvent(for queue: Queue) -> MTLEvent {
        let event = self.device.makeEvent()!
        self.queueSyncEvents[Int(queue.index)] = event
        return event
    }
    
    func syncEvent(for queue: Queue) -> MTLEvent? {
        return self.queueSyncEvents[Int(queue.index)]
    }
    

    func freeSyncEvent(for queue: Queue) {
        assert(self.queueSyncEvents[Int(queue.index)] != nil)
        self.queueSyncEvents[Int(queue.index)] = nil
    }

    func makeTransientRegistry(index: Int, inflightFrameCount: Int, queue: Queue) -> MetalTransientResourceRegistry {
        return MetalTransientResourceRegistry(device: self.device, inflightFrameCount: inflightFrameCount, queue: queue, transientRegistryIndex: index, persistentRegistry: self.resourceRegistry)
    }

    func generateFenceCommands(queue: Queue, frameCommandInfo: FrameCommandInfo<MetalRenderTargetDescriptor>, commandGenerator: ResourceCommandGenerator<MetalBackend>, compactedResourceCommands: inout [CompactedResourceCommand<MetalCompactedResourceCommandType>]) async {
        // MARK: - Generate the fences
        
        let dependencies = commandGenerator.commandEncoderDependencies
        
        let commandEncoderCount = frameCommandInfo.commandEncoders.count
        let reductionMatrix = dependencies.transitiveReduction(hasDependency: { $0 != nil })
        
        for sourceIndex in (0..<commandEncoderCount) { // sourceIndex always points to the producing pass.
            let dependentRange = min(sourceIndex + 1, commandEncoderCount)..<commandEncoderCount
            
            var signalStages : MTLRenderStages = []
            var signalIndex = -1
            for dependentIndex in dependentRange where reductionMatrix.dependency(from: dependentIndex, on: sourceIndex) {
                let dependency = dependencies.dependency(from: dependentIndex, on: sourceIndex)!
                signalStages.formUnion(MTLRenderStages(dependency.signal.stages))
                signalIndex = max(signalIndex, dependency.signal.index)
            }
            
            if signalIndex < 0 { continue }
            
            var maxCommandBufferIndex = frameCommandInfo.commandEncoders[sourceIndex].commandBufferIndex
            
            let fence = MetalFenceHandle(encoderIndex: sourceIndex, queue: queue)
            
            compactedResourceCommands.append(CompactedResourceCommand<MetalCompactedResourceCommandType>(command: .updateFence(fence, afterStages: signalStages), index: signalIndex, order: .after))
            
            for dependentIndex in dependentRange where reductionMatrix.dependency(from: dependentIndex, on: sourceIndex) {
                let dependency = dependencies.dependency(from: dependentIndex, on: sourceIndex)!
                compactedResourceCommands.append(CompactedResourceCommand<MetalCompactedResourceCommandType>(command: .waitForFence(fence, beforeStages: MTLRenderStages(dependency.wait.stages)), index: dependency.wait.index, order: .before))
                
                maxCommandBufferIndex = max(maxCommandBufferIndex, frameCommandInfo.commandEncoders[dependentIndex].commandBufferIndex)
            }
            
            fence.commandBufferIndex = frameCommandInfo.globalCommandBufferIndex(frameIndex: maxCommandBufferIndex)
        }
    }

    func compactResourceCommands(queue: Queue, commandInfo: FrameCommandInfo<MetalRenderTargetDescriptor>, commandGenerator: ResourceCommandGenerator<MetalBackend>, into compactedResourceCommands: inout [CompactedResourceCommand<MetalCompactedResourceCommandType>]) async {
        guard !commandGenerator.commands.isEmpty else { return }
        assert(compactedResourceCommands.isEmpty)
        
        await self.generateFenceCommands(queue: queue, frameCommandInfo: commandInfo, commandGenerator: commandGenerator, compactedResourceCommands: &compactedResourceCommands)
        
        
        let allocator = ThreadLocalTagAllocator(tag: .renderGraphResourceCommandArrayTag)
        
        var currentEncoderIndex = 0
        var currentEncoder = commandInfo.commandEncoders[currentEncoderIndex]
        
        
        var barrierResources: [Unmanaged<MTLResource>] = []
        barrierResources.reserveCapacity(8) // we use memoryBarrier(resource) for up to eight resources, and memoryBarrier(scope) otherwise.
        
        var barrierScope: MTLBarrierScope = []
        var barrierAfterStages: MTLRenderStages = []
        var barrierBeforeStages: MTLRenderStages = []
        var barrierLastIndex: Int = .max
        
        var encoderResidentResources = Set<MetalResidentResource>()
        var encoderResidentHeaps = Set<MetalResidentHeap>()
        
        var encoderUseResourceCommandIndex: Int = .max
        var encoderUseResources = [UseResourceKey: [Unmanaged<MTLResource>]]()
        
        let addBarrier: (inout [CompactedResourceCommand<MetalCompactedResourceCommandType>]) -> Void = { compactedResourceCommands in
            #if os(macOS) || targetEnvironment(macCatalyst)
            let isRTBarrier = barrierScope.contains(.renderTargets) && !self.isAppleSiliconGPU
            #else
            let isRTBarrier = false
            #endif
            if barrierResources.count <= 8, !isRTBarrier {
                let memory = allocator.allocate(capacity: barrierResources.count) as UnsafeMutablePointer<Unmanaged<MTLResource>>
                memory.update(from: barrierResources, count: barrierResources.count)
                let bufferPointer = UnsafeMutableBufferPointer<MTLResource>(start: UnsafeMutableRawPointer(memory).assumingMemoryBound(to: MTLResource.self), count: barrierResources.count)
                
                compactedResourceCommands.append(.init(command: .resourceMemoryBarrier(resources: bufferPointer, afterStages: barrierAfterStages.last, beforeStages: barrierBeforeStages.first), index: barrierLastIndex, order: .before))
            } else {
                compactedResourceCommands.append(.init(command: .scopedMemoryBarrier(scope: barrierScope, afterStages: barrierAfterStages.last, beforeStages: barrierBeforeStages.first), index: barrierLastIndex, order: .before))
            }
            barrierResources.removeAll(keepingCapacity: true)
            barrierScope = []
            barrierAfterStages = []
            barrierBeforeStages = []
            barrierLastIndex = .max
        }
        
        let useResources: (inout [CompactedResourceCommand<MetalCompactedResourceCommandType>]) -> Void = { compactedResourceCommands in
            for (key, resources) in encoderUseResources where !resources.isEmpty {
                let memory = allocator.allocate(capacity: resources.count) as UnsafeMutablePointer<Unmanaged<MTLResource>>
                memory.update(from: resources, count: resources.count)
                let bufferPointer = UnsafeMutableBufferPointer<MTLResource>(start: UnsafeMutableRawPointer(memory).assumingMemoryBound(to: MTLResource.self), count: resources.count)
                
                compactedResourceCommands.append(.init(command: .useResources(bufferPointer, usage: key.usage, stages: key.stages), index: encoderUseResourceCommandIndex, order: .before))
            }
            encoderUseResourceCommandIndex = .max
            encoderUseResources.removeAll(keepingCapacity: true)
            encoderResidentResources.removeAll(keepingCapacity: true)
        }
        
        for command in commandGenerator.commands {
            if command.index >= barrierLastIndex { // For barriers, the barrier associated with command.index needs to happen _after_ any barriers required to happen _by_ barrierLastIndex
                addBarrier(&compactedResourceCommands)
            }
            
            while !currentEncoder.passRange.contains(command.index) {
                if !encoderResidentHeaps.isEmpty {
                    compactedResourceCommands.append(.init(command: .useHeaps(encoderResidentHeaps), index: currentEncoder.passRange.lowerBound, order: .before))
                    encoderResidentHeaps.removeAll()
                }
                
                currentEncoderIndex += 1
                currentEncoder = commandInfo.commandEncoders[currentEncoderIndex]
                
                useResources(&compactedResourceCommands)
                
                assert(barrierScope == [])
                assert(barrierResources.isEmpty)
            }
            
            // Strategy:
            // useResource should be batched together by usage to as early as possible in the encoder.
            // memoryBarriers should be as late as possible.
            switch command.command {
            case .useResource(let resource, let usage, let stages, let allowReordering):
                if resource.type == .heap, let backingResource = resource.backingResourcePointer {
                    let key = MetalResidentHeap(resource: .fromOpaque(backingResource), stages: MTLRenderStages(stages))
                    encoderResidentHeaps.insert(key)
                    continue
                }
                
                var computedUsageType: MTLResourceUsage = []
                if usage.contains(.inputAttachment), !self.isAppleSiliconGPU {
                    assert(resource.type == .texture || resource.type == .hazardTrackingGroup)
                    computedUsageType.formUnion(.read)
                } else {
                    if resource.type == .texture || HazardTrackingGroup<Texture>(resource) != nil, usage.contains(.shaderRead) {
                        computedUsageType.formUnion(.sample)
                    }
                    if usage.contains(.shaderRead) {
                        computedUsageType.formUnion(.read)
                    }
                    if usage.contains(.shaderWrite) {
                        computedUsageType.formUnion(.write)
                    }
                }
                
                if computedUsageType.isEmpty { continue }
                
                if !allowReordering {
                    let memory: UnsafeMutablePointer<Unmanaged<MTLResource>>
                    let count: Int
                    if resource.type == .hazardTrackingGroup {
                        let group = _HazardTrackingGroup(handle: resource.handle)
                        let resources = group.resourcesPointer(ofType: Resource.self).pointee
                        guard !resources.isEmpty else {
                            break
                        }
                        memory = allocator.allocate(capacity: resources.count)
                        var i = 0
                        for resource in resources {
                            guard let mtlResource = resource.backingResourcePointer else { continue }
                            memory.advanced(by: i).initialize(to: .fromOpaque(mtlResource))
                            i += 1
                        }
                        count = i
                    } else {
                        guard let mtlResource = resource.backingResourcePointer else { break }
                        memory = allocator.allocate(capacity: 1)
                        memory.initialize(to: .fromOpaque(mtlResource))
                        count = 1
                    }
                    
                    let bufferPointer = UnsafeMutableBufferPointer<MTLResource>(start: UnsafeMutableRawPointer(memory).assumingMemoryBound(to: MTLResource.self), count: count)
                    compactedResourceCommands.append(.init(command: .useResources(bufferPointer, usage: computedUsageType, stages: MTLRenderStages(stages)), index: command.index, order: .before))
                } else {
                    if resource.type == .hazardTrackingGroup {
                        let group = _HazardTrackingGroup(handle: resource.handle)
                        let resources = group.resourcesPointer(ofType: Resource.self).pointee
                        for resource in resources {
                            guard let mtlResource = resource.backingResourcePointer else { continue }
                            
                            let key = MetalResidentResource(resource: .fromOpaque(mtlResource), stages: MTLRenderStages(stages), usage: computedUsageType)
                            let (inserted, _) = encoderResidentResources.insert(key)
                            if inserted {
                                encoderUseResources[UseResourceKey(stages: MTLRenderStages(stages), usage: computedUsageType), default: []].append(.fromOpaque(mtlResource))
                            }
                        }
                    } else {
                        guard let mtlResource = resource.backingResourcePointer else { continue }
                        let key = MetalResidentResource(resource: .fromOpaque(mtlResource), stages: MTLRenderStages(stages), usage: computedUsageType)
                        let (inserted, _) = encoderResidentResources.insert(key)
                        if inserted {
                            encoderUseResources[UseResourceKey(stages: MTLRenderStages(stages), usage: computedUsageType), default: []].append(.fromOpaque(mtlResource))
                        }
                    }
                    encoderUseResourceCommandIndex = min(command.index, encoderUseResourceCommandIndex)
                }
                
            case .memoryBarrier(let resource, let afterUsage, let afterStages, let beforeCommand, let beforeUsage, let beforeStages, _):
                
                var scope: MTLBarrierScope = []
                
                #if os(macOS) || targetEnvironment(macCatalyst)
                let isRTBarrier = afterUsage.isRenderTarget || beforeUsage.isRenderTarget
                if isRTBarrier, !self.isAppleSiliconGPU {
                    scope.formUnion(.renderTargets)
                }
                #else
                let isRTBarrier = false
                #endif
                
                if !isRTBarrier {
                    if resource.type == .texture || HazardTrackingGroup<Texture>(resource) != nil {
                        scope.formUnion(.textures)
                    } else {
                        scope.formUnion(.buffers)
                    }
                }
                
                if barrierResources.count < 8, resource.type != .hazardTrackingGroup {
                    if let mtlResource = resource.backingResourcePointer {
                        barrierResources.append(.fromOpaque(mtlResource))
                    }
                }
                barrierScope.formUnion(scope)
                barrierAfterStages.formUnion(MTLRenderStages(afterStages))
                barrierBeforeStages.formUnion(MTLRenderStages(beforeStages))
                barrierLastIndex = min(beforeCommand, barrierLastIndex)
            }
        }
        
        if barrierLastIndex < .max {
            addBarrier(&compactedResourceCommands)
        }
        useResources(&compactedResourceCommands)
        
        if !encoderResidentHeaps.isEmpty {
            compactedResourceCommands.append(.init(command: .useHeaps(encoderResidentHeaps), index: currentEncoder.passRange.lowerBound, order: .before))
            encoderResidentHeaps.removeAll()
        }
        
        compactedResourceCommands.sort()
    }
    
    func didCompleteCommand(_ index: UInt64, queue: Queue, context: RenderGraphContextImpl<MetalBackend>) {
//        if index >= queue.lastSubmittedCommand, let contextRegistry = context.resourceRegistry {
//            Task {
//                try await Task.sleep(nanoseconds: 1_000_000_000) // wait for one second.
//                context.withContextAsync {
//                    if index >= queue.lastSubmittedCommand, await context.needsWaitOnAccessSemaphore {
//                        // If there are no more pending commands on the queue and there haven't been for a number of seconds, we can make all of the transient allocators purgeable.
//                        contextRegistry.makeTransientAllocatorsPurgeable()
//                    }
//                }
//            }
//        }
        MetalFenceRegistry.instance.clearCompletedFences()
        MetalResourcePurgeabilityManager.instance.processPurgeabilityChanges()
    }

}

#else

@available(*, unavailable)
typealias MetalBackend = UnavailableBackend

#endif // canImport(Metal)
