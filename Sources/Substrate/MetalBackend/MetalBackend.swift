//
//  MetalRenderer.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 23/12/17.
//

#if canImport(Metal)

import SubstrateUtilities
import Metal

extension MTLResourceOptions {
    static var substrateTrackedHazards : MTLResourceOptions {
        // This gives us a convenient way to toggle whether the RenderGraph or Metal should handle resource tracking.
        return .hazardTrackingModeUntracked
    }
}

@available(OSX 10.15, iOS 13.0, tvOS 13.0, *)
extension MTLHazardTrackingMode {
    static var substrateTrackedHazards : MTLHazardTrackingMode {
        // This gives us a convenient way to toggle whether the RenderGraph or Metal should handle resource tracking.
        return .untracked
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
        #if (os(iOS) || os(tvOS) || os(watchOS)) && !targetEnvironment(macCatalyst)
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

final class MetalBackend : SpecificRenderBackend {

    typealias BufferReference = MTLBufferReference
    typealias TextureReference = MTLTextureReference
    typealias ArgumentBufferReference = MTLBufferReference
    typealias ArgumentBufferArrayReference = MTLBufferReference
    typealias SamplerReference = MTLSamplerState
    
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
    let activeContextLock = SpinLock()
    
    var activeContext : RenderGraphContextImpl<MetalBackend>? = nil
    
    var queueSyncEvents = [MTLEvent?](repeating: nil, count: QueueRegistry.maxQueues)
    
    public init(device: MTLDevice?, libraryPath: String? = nil, enableValidation: Bool = true, enableShaderHotReloading: Bool = true) {
        self.device = device ?? MTLCreateSystemDefaultDevice()!
        self.stateCaches = MetalStateCaches(device: self.device, libraryPath: libraryPath)
        self.resourceRegistry = MetalPersistentResourceRegistry(device: self.device)
        self.enableValidation = enableValidation
        self.enableShaderHotReloading = enableShaderHotReloading
    }
    
    public var api : RenderAPI {
        return .metal
    }
    
    public var renderDevice: Any {
        return self.device
    }
    
    func setActiveContext(_ context: RenderGraphContextImpl<MetalBackend>?) {
        if context != nil {
            self.activeContextLock.lock()
            assert(self.activeContext == nil)
            if self.enableShaderHotReloading {
                self.stateCaches.checkForLibraryReload()
            }
            self.activeContext = context
        } else {
            assert(self.activeContext != nil)
            self.activeContext = nil
            self.activeContextLock.unlock()
        }
    }
    
    @usableFromInline func materialisePersistentTexture(_ texture: Texture) -> Bool {
        return resourceRegistry.accessLock.withWriteLock {
            return self.resourceRegistry.allocateTexture(texture) != nil
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

    @usableFromInline func updateLabel(on resource: Resource) {
        self.resourceRegistry.accessLock.withReadLock {
            if let buffer = resource.buffer {
                self.resourceRegistry[buffer]?.buffer.label = buffer.label
            } else if let texture = resource.texture {
                self.resourceRegistry[texture]?.texture.label = texture.label
            }
        }
    }
    
    @usableFromInline func updatePurgeableState(for resource: Resource, to newState: ResourcePurgeableState?) -> ResourcePurgeableState {
        self.resourceRegistry.accessLock.withReadLock {
            let mtlState = MTLPurgeableState(newState)
            if let buffer = resource.buffer, let mtlBuffer = self.resourceRegistry[buffer]?.buffer {
                return ResourcePurgeableState(mtlBuffer.setPurgeableState(mtlState))!
            } else if let texture = resource.texture, let mtlTexture = self.resourceRegistry[texture]?.texture {
                return ResourcePurgeableState(mtlTexture.setPurgeableState(mtlState))!
            }
            return .nonDiscardable
        }
        
    }
    
    @usableFromInline func dispose(texture: Texture) {
        self.resourceRegistry.disposeTexture(texture)
    }
    
    @usableFromInline func dispose(buffer: Buffer) {
        self.resourceRegistry.disposeBuffer(buffer)
    }
    
    @usableFromInline func dispose(argumentBuffer: ArgumentBuffer) {
        self.resourceRegistry.disposeArgumentBuffer(argumentBuffer)
    }
    
    @usableFromInline func dispose(argumentBufferArray: ArgumentBufferArray) {
        self.resourceRegistry.disposeArgumentBufferArray(argumentBufferArray)
    }
    
    @usableFromInline func dispose(heap: Heap) {
        self.resourceRegistry.disposeHeap(heap)
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
            return self.isAppleSiliconGPU
        case .bc1_rgba, .bc1_rgba_sRGB,
             .bc2_rgba, .bc2_rgba_sRGB,
             .bc3_rgba, .bc3_rgba_sRGB,
             .bc4_rUnorm, .bc4_rSnorm,
             .bc5_rgUnorm, .bc5_rgSnorm,
             .bc6H_rgbFloat, .bc6H_rgbuFloat,
             .bc7_rgbaUnorm, .bc7_rgbaUnorm_sRGB:
            
            #if os(macOS)
            if usage.intersection([.shaderWrite, .renderTarget]) != [] {
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
    
    public var isAppleSiliconGPU: Bool {
        return self.device.isAppleSiliconGPU
    }
    
    public var hasUnifiedMemory: Bool {
        #if (os(iOS) || os(tvOS) || os(watchOS)) && !targetEnvironment(macCatalyst)
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
    
    @usableFromInline func bufferContents(for buffer: Buffer, range: Range<Int>) -> UnsafeMutableRawPointer {
        let bufferReference = self.activeContext?.resourceMap.bufferForCPUAccess(buffer) ?? resourceRegistry.accessLock.withReadLock { resourceRegistry[buffer]! }
        return bufferReference.buffer.contents() + bufferReference.offset + range.lowerBound
    }
    
    @usableFromInline func buffer(_ buffer: Buffer, didModifyRange range: Range<Int>) {
        #if os(macOS) || targetEnvironment(macCatalyst)
        if range.isEmpty || self.isAppleSiliconGPU { return }
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
                return resourceRegistry[texture]?.texture
            }
            return nil
        }
    }
    
    @usableFromInline func copyTextureBytes(from texture: Texture, to bytes: UnsafeMutableRawPointer, bytesPerRow: Int, region: Region, mipmapLevel: Int) {
        assert(texture.flags.contains(.persistent) || self.activeContext != nil, "GPU memory for a transient texture may not be accessed outside of a RenderGraph RenderPass.")
        
        let mtlTexture = self.activeContext?.resourceMap.textureForCPUAccess(texture) ?? resourceRegistry.accessLock.withReadLock { resourceRegistry[texture]! }
        mtlTexture.texture.getBytes(bytes, bytesPerRow: bytesPerRow, from: MTLRegion(region), mipmapLevel: mipmapLevel)
    }
    
    @usableFromInline func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) {
        assert(texture.flags.contains(.persistent) || self.activeContext != nil, "GPU memory for a transient texture may not be accessed outside of a RenderGraph RenderPass.")
        
        let mtlTexture = self.activeContext?.resourceMap.textureForCPUAccess(texture) ?? resourceRegistry.accessLock.withReadLock { resourceRegistry[texture]! }
        mtlTexture.texture.replace(region: MTLRegion(region), mipmapLevel: mipmapLevel, withBytes: bytes, bytesPerRow: bytesPerRow)
    }
    
    @usableFromInline func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, slice: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int) {
        assert(texture.flags.contains(.persistent) || self.activeContext != nil, "GPU memory for a transient texture may not be accessed outside of a RenderGraph RenderPass.")
               
        let mtlTexture = self.activeContext?.resourceMap.textureForCPUAccess(texture) ?? resourceRegistry.accessLock.withReadLock { resourceRegistry[texture]! }
        mtlTexture.texture.replace(region: MTLRegion(region), mipmapLevel: mipmapLevel, slice: slice, withBytes: bytes, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerImage)
    }
    
    @usableFromInline
    func renderPipelineReflection(descriptor: RenderPipelineDescriptor, renderTarget: Substrate.RenderTargetDescriptor) -> PipelineReflection? {
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
    
    var requiresEmulatedInputAttachments: Bool {
        return !self.isAppleSiliconGPU
    }
    
    static func fillArgumentBuffer(_ argumentBuffer: ArgumentBuffer, storage: MTLBufferReference, firstUseCommandIndex: Int, resourceMap: FrameResourceMap<MetalBackend>) {
        argumentBuffer.setArguments(storage: storage, resourceMap: resourceMap)
    }
    
    static func fillArgumentBufferArray(_ argumentBufferArray: ArgumentBufferArray, storage: MTLBufferReference, firstUseCommandIndex: Int, resourceMap: FrameResourceMap<MetalBackend>) {
        argumentBufferArray.setArguments(storage: storage, resourceMap: resourceMap)
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

    func makeTransientRegistry(index: Int, inflightFrameCount: Int) -> MetalTransientResourceRegistry {
        return MetalTransientResourceRegistry(device: self.device, inflightFrameCount: inflightFrameCount, transientRegistryIndex: index, persistentRegistry: self.resourceRegistry)
    }

    func generateFenceCommands(queue: Queue, frameCommandInfo: FrameCommandInfo<MetalBackend>, commandGenerator: ResourceCommandGenerator<MetalBackend>, compactedResourceCommands: inout [CompactedResourceCommand<MetalCompactedResourceCommandType>]) {
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
            
            let label = "Encoder \(sourceIndex) Fence"
            let commandBufferSignalValue = frameCommandInfo.signalValue(commandBufferIndex: frameCommandInfo.commandEncoders[sourceIndex].commandBufferIndex)
            let fence = MetalFenceHandle(label: label, queue: queue, commandBufferIndex: commandBufferSignalValue)
            
            compactedResourceCommands.append(CompactedResourceCommand<MetalCompactedResourceCommandType>(command: .updateFence(fence, afterStages: signalStages), index: signalIndex, order: .after))
            
            for dependentIndex in dependentRange where reductionMatrix.dependency(from: dependentIndex, on: sourceIndex) {
                let dependency = dependencies.dependency(from: dependentIndex, on: sourceIndex)!
                compactedResourceCommands.append(CompactedResourceCommand<MetalCompactedResourceCommandType>(command: .waitForFence(fence, beforeStages: MTLRenderStages(dependency.wait.stages)), index: dependency.wait.index, order: .before))
            }
        }
    }

    func compactResourceCommands(queue: Queue, resourceMap: FrameResourceMap<MetalBackend>, commandInfo: FrameCommandInfo<MetalBackend>, commandGenerator: ResourceCommandGenerator<MetalBackend>, into compactedResourceCommands: inout [CompactedResourceCommand<MetalCompactedResourceCommandType>]) {
        guard !commandGenerator.commands.isEmpty else { return }
        assert(compactedResourceCommands.isEmpty)
        
        self.generateFenceCommands(queue: queue, frameCommandInfo: commandInfo, commandGenerator: commandGenerator, compactedResourceCommands: &compactedResourceCommands)
        
        
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
                memory.assign(from: barrierResources, count: barrierResources.count)
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
                memory.assign(from: resources, count: resources.count)
                let bufferPointer = UnsafeMutableBufferPointer<MTLResource>(start: UnsafeMutableRawPointer(memory).assumingMemoryBound(to: MTLResource.self), count: resources.count)
                
                compactedResourceCommands.append(.init(command: .useResources(bufferPointer, usage: key.usage, stages: key.stages), index: encoderUseResourceCommandIndex, order: .before))
            }
            encoderUseResourceCommandIndex = .max
            encoderUseResources.removeAll(keepingCapacity: true)
            encoderResidentResources.removeAll(keepingCapacity: true)
        }
        
        let getResource: (Resource) -> Unmanaged<MTLResource>? = { resource in
            if let buffer = resource.buffer {
                return resourceMap[buffer].map { unsafeBitCast($0._buffer, to: Unmanaged<MTLResource>.self) }
            } else if let texture = resource.texture {
                return resourceMap[texture].map { unsafeBitCast($0._texture, to: Unmanaged<MTLResource>.self) }
            } else if let argumentBuffer = resource.argumentBuffer {
                return unsafeBitCast(resourceMap[argumentBuffer]._buffer, to: Unmanaged<MTLResource>.self)
            }
            fatalError()
        }
        
        for command in commandGenerator.commands {
            if command.index >= barrierLastIndex { // For barriers, the barrier associated with command.index needs to happen _after_ any barriers required to happen _by_ barrierLastIndex
                addBarrier(&compactedResourceCommands)
            }
            
            while !currentEncoder.commandRange.contains(command.index) {
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
                guard let mtlResource = getResource(resource) else { break }
                
                var computedUsageType: MTLResourceUsage = []
                if usage == .inputAttachmentRenderTarget || usage == .inputAttachment {
                    assert(resource.type == .texture)
                    computedUsageType.formUnion(.read)
                } else {
                    if resource.type == .texture, usage == .read {
                        computedUsageType.formUnion(.sample)
                    }
                    if usage.isRead {
                        computedUsageType.formUnion(.read)
                    }
                    if usage.isWrite {
                        computedUsageType.formUnion(.write)
                    }
                }
                
                if !allowReordering {
                    let memory = allocator.allocate(capacity: 1) as UnsafeMutablePointer<Unmanaged<MTLResource>>
                    memory.initialize(to: mtlResource)
                    let bufferPointer = UnsafeMutableBufferPointer<MTLResource>(start: UnsafeMutableRawPointer(memory).assumingMemoryBound(to: MTLResource.self), count: 1)
                    compactedResourceCommands.append(.init(command: .useResources(bufferPointer, usage: computedUsageType, stages: MTLRenderStages(stages)), index: command.index, order: .before))
                } else {
                    let key = MetalResidentResource(resource: mtlResource, stages: MTLRenderStages(stages), usage: computedUsageType)
                    let (inserted, _) = encoderResidentResources.insert(key)
                    if inserted {
                        encoderUseResources[UseResourceKey(stages: MTLRenderStages(stages), usage: computedUsageType), default: []].append(mtlResource)
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
                    if resource.type == .texture {
                        scope.formUnion(.textures)
                    } else if resource.type == .buffer || resource.type == .argumentBuffer || resource.type == .argumentBufferArray {
                        scope.formUnion(.buffers)
                    } else {
                        assertionFailure()
                    }
                }
                
                if barrierResources.count < 8 {
                    if let mtlResource = getResource(resource) {
                        barrierResources.append(mtlResource)
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
        
        compactedResourceCommands.sort()
    }

}

#endif // canImport(Metal)
