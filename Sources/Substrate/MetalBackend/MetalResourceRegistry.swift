//
//  MetalResourceRegistry.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 23/12/17.
//

#if canImport(Metal)

@preconcurrency import Metal
@preconcurrency import MetalKit
import SubstrateUtilities
import OSLog

protocol MTLResourceReference {
    associatedtype Resource : MTLResource
    var resource : Resource { get }
}

// Must be a POD type and trivially copyable/movable
struct MTLBufferReference : MTLResourceReference {
    let _buffer : Unmanaged<MTLBuffer>
    let offset : Int
    
    var buffer : MTLBuffer {
        return self._buffer.takeUnretainedValue()
    }
    
    var resource : MTLBuffer {
        return self._buffer.takeUnretainedValue()
    }
    
    init(buffer: Unmanaged<MTLBuffer>, offset: Int) {
        self._buffer = buffer
        self.offset = offset
    }
}

// Must be a POD type and trivially copyable/movable
struct MTLTextureReference : MTLResourceReference {
    var _texture : Unmanaged<MTLTexture>!
    
    // For window handle textures only.
    var disposeWaitValue: UInt64 = 0
    var disposeWaitQueue: Queue? = nil
    
    var texture : MTLTexture! {
        return _texture?.takeUnretainedValue()
    }
    
    var resource : MTLTexture {
        return self.texture
    }
    
    init(windowTexture: ()) {
        self._texture = nil
    }
    
    init(texture: Unmanaged<MTLTexture>) {
        self._texture = texture
    }
}

struct MTLTextureUsageProperties {
    var usage : MTLTextureUsage
    var canBeMemoryless : Bool
    
    init(usage: MTLTextureUsage, canBeMemoryless: Bool = false) {
        self.usage = usage
        self.canBeMemoryless = canBeMemoryless
    }
}

final actor MetalPersistentResourceRegistry: BackendPersistentResourceRegistry {
    typealias Backend = MetalBackend
    
    @available(macOS 11.0, iOS 14.0, *)
    typealias AccelerationStructureReference = MTLAccelerationStructure
    
    var samplerReferences = [SamplerDescriptor : SamplerState]()
    
    private let device : MTLDevice
    let stateCaches: MetalStateCaches
    
    public init(device: MTLDevice, stateCaches: MetalStateCaches) {
        self.device = device
        self.stateCaches = stateCaches
        
        MetalFenceRegistry.instance = .init(device: self.device)
    }
    
    @discardableResult
    public nonisolated func allocateHeap(_ heap: Heap) -> MTLHeap? {
        precondition(heap._usesPersistentRegistry)
        
        let descriptor = MTLHeapDescriptor(heap.descriptor, isAppleSiliconGPU: device.isAppleSiliconGPU)
        
        let mtlHeap = self.device.makeHeap(descriptor: descriptor)
        heap.backingResourcePointer = mtlHeap.map { Unmanaged.passRetained($0).toOpaque() }
        
        return mtlHeap
    }
    
    @discardableResult
    public nonisolated func allocateTexture(_ texture: Texture) -> MTLTextureReference? {
        precondition(texture._usesPersistentRegistry)
        
        if texture.flags.contains(.windowHandle) {
            // Reserve a slot in texture references so we can later insert the texture reference in a thread-safe way, but don't actually allocate anything yet
            texture.backingResourcePointer = nil
            return nil
        }
        
        // NOTE: all synchronisation is managed through the per-queue waitIndices associated with the resource.
        
        let descriptor = MTLTextureDescriptor(texture.descriptor, usage: MTLTextureUsage(texture.descriptor.usageHint), isAppleSiliconGPU: device.isAppleSiliconGPU)
        
        let mtlTexture : MTLTextureReference
        if let heap = texture.heap {
            guard let mtlTextureObj = heap.mtlHeap.makeTexture(descriptor: descriptor) else {
                return nil
            }
            mtlTexture = MTLTextureReference(texture: Unmanaged<MTLTexture>.passRetained(mtlTextureObj))
        } else {
            guard let mtlTextureObj = self.device.makeTexture(descriptor: descriptor) else {
                return nil
            }
            mtlTexture = MTLTextureReference(texture: Unmanaged<MTLTexture>.passRetained(mtlTextureObj))
        }
        
        if let label = texture.label {
            mtlTexture.texture.label = label
        }
        
        texture.backingResourcePointer = mtlTexture._texture.toOpaque()
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, *) {
            texture[\.gpuAddresses] = mtlTexture.texture.gpuResourceID._impl
        }
        
        return mtlTexture
    }
    
    @discardableResult
    public nonisolated func allocateBuffer(_ buffer: Buffer) -> MTLBufferReference? {
        precondition(buffer._usesPersistentRegistry)
        
        // NOTE: all synchronisation is managed through the per-queue waitIndices associated with the resource.
        
        let options = MTLResourceOptions(storageMode: buffer.descriptor.storageMode, cacheMode: buffer.descriptor.cacheMode, isAppleSiliconGPU: device.isAppleSiliconGPU)
        
        let mtlBuffer : MTLBufferReference
        
        if let heap = buffer.heap {
            guard let mtlBufferObj = heap.mtlHeap.makeBuffer(length: buffer.descriptor.length, options: options) else {
                return nil
            }
            mtlBuffer = MTLBufferReference(buffer: Unmanaged<MTLBuffer>.passRetained(mtlBufferObj), offset: 0)
        } else {
            guard let mtlBufferObj = self.device.makeBuffer(length: buffer.descriptor.length, options: options) else {
                return nil
            }
            mtlBuffer = MTLBufferReference(buffer: Unmanaged<MTLBuffer>.passRetained(mtlBufferObj), offset: 0)
        }
        
        if let label = buffer.label {
            mtlBuffer.buffer.label = label
        }
        
        buffer.backingResourcePointer = mtlBuffer._buffer.toOpaque()
        buffer[\.mappedContents] = buffer.storageMode == .private ? nil : mtlBuffer.buffer.contents().advanced(by: mtlBuffer.offset)
        
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, *) {
            buffer[\.gpuAddresses] = mtlBuffer.buffer.gpuAddress.advanced(by: mtlBuffer.offset)
        }
        
        return mtlBuffer
    }
    
    @discardableResult
    public nonisolated func allocateArgumentBuffer(_ argumentBuffer: ArgumentBuffer) -> MTLBufferReference? {
        precondition(argumentBuffer._usesPersistentRegistry)
        
        // NOTE: all synchronisation is managed through the per-queue waitIndices associated with the resource.
        
        let options: MTLResourceOptions = [.storageModeShared, .substrateTrackedHazards]
        
        let mtlBuffer : MTLBufferReference
        
        if let heap = argumentBuffer.heap {
            guard let mtlBufferObj = heap.mtlHeap.makeBuffer(length: argumentBuffer.descriptor.bufferLength, options: options) else {
                return nil
            }
            mtlBuffer = MTLBufferReference(buffer: Unmanaged<MTLBuffer>.passRetained(mtlBufferObj), offset: 0)
            argumentBuffer.usedHeaps.insert(heap.backingResourcePointer!)
        } else {
            guard let mtlBufferObj = self.device.makeBuffer(length: argumentBuffer.descriptor.bufferLength, options: options) else {
                return nil
            }
            mtlBuffer = MTLBufferReference(buffer: Unmanaged<MTLBuffer>.passRetained(mtlBufferObj), offset: 0)
            argumentBuffer.usedResources.insert(mtlBuffer._buffer.toOpaque())
        }
        
        if let label = argumentBuffer.label {
            mtlBuffer.buffer.label = label
        }
        
        argumentBuffer.backingResourcePointer = mtlBuffer._buffer.toOpaque()
        argumentBuffer[\.mappedContents] = argumentBuffer.storageMode == .private ? nil : mtlBuffer.buffer.contents().advanced(by: mtlBuffer.offset)
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, *) {
            argumentBuffer[\.gpuAddresses] = mtlBuffer.buffer.gpuAddress.advanced(by: mtlBuffer.offset)
        } else {
            argumentBuffer[\.encoders] = Unmanaged.passUnretained(self.stateCaches.argumentEncoderCache[argumentBuffer.descriptor])
        }
        
        return mtlBuffer
    }
    
    @discardableResult
    public nonisolated func allocateArgumentBufferArray(_ argumentBufferArray: ArgumentBufferArray) -> MTLBufferReference? {
        precondition(argumentBufferArray._usesPersistentRegistry)
        
        // NOTE: all synchronisation is managed through the per-queue waitIndices associated with the resource.
        
        let options: MTLResourceOptions = [.storageModeShared, .substrateTrackedHazards]
        
        let mtlBuffer : MTLBufferReference
        
        let stride = argumentBufferArray.descriptor.bufferLength
        
        if let heap = argumentBufferArray.heap {
            guard let mtlBufferObj = heap.mtlHeap.makeBuffer(length: stride * argumentBufferArray.arrayLength, options: options) else {
                return nil
            }
            mtlBuffer = MTLBufferReference(buffer: Unmanaged<MTLBuffer>.passRetained(mtlBufferObj), offset: 0)
        } else {
            guard let mtlBufferObj = self.device.makeBuffer(length: stride * argumentBufferArray.arrayLength, options: options) else {
                return nil
            }
            mtlBuffer = MTLBufferReference(buffer: Unmanaged<MTLBuffer>.passRetained(mtlBufferObj), offset: 0)
        }
        
        if let label = argumentBufferArray.label {
            mtlBuffer.buffer.label = label
        }
        
        argumentBufferArray.backingResourcePointer = mtlBuffer._buffer.toOpaque()
        
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, *) {
            let contents = argumentBufferArray.storageMode == .private ? nil : mtlBuffer.buffer.contents().advanced(by: mtlBuffer.offset)
            argumentBufferArray[\.gpuAddresses] = mtlBuffer.buffer.gpuAddress.advanced(by: mtlBuffer.offset)
            
            for (i, argumentBuffer) in argumentBufferArray.enumerated() {
                argumentBuffer[\.mappedContents] = contents?.advanced(by: i * stride)
            }
            for (i, argumentBuffer) in argumentBufferArray.enumerated() {
                argumentBuffer[\.gpuAddresses] = mtlBuffer.buffer.gpuAddress.advanced(by: mtlBuffer.offset + i * stride)
            }
        } else {
            let encoder = Unmanaged.passUnretained(self.stateCaches.argumentEncoderCache[argumentBufferArray.descriptor])
            for argumentBuffer in argumentBufferArray {
                argumentBuffer[\.encoders] = encoder
            }
        }
        
        return mtlBuffer
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    @discardableResult
    public nonisolated func allocateAccelerationStructure(_ structure: AccelerationStructure) -> MTLAccelerationStructure? {
        let mtlStructure = self.device.makeAccelerationStructure(size: structure.size)
        
        structure.backingResourcePointer = mtlStructure.map { Unmanaged.passRetained($0).toOpaque() }
        
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, *) {
            structure[\.gpuAddresses] = mtlStructure?.gpuResourceID._impl ?? 0
        }
        
        return mtlStructure
    }
    
    nonisolated func allocateVisibleFunctionTable(_ table: VisibleFunctionTable) -> MTLVisibleFunctionTable? {
        guard #available(macOS 11.0, iOS 14.0, *) else { return nil }
        
        let mtlDescriptor = MTLVisibleFunctionTableDescriptor()
        mtlDescriptor.functionCount = table.functions.count
        
        let mtlTable: MTLVisibleFunctionTable?
        let pipeline = Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(table.pipelineState.state)).takeUnretainedValue()
        if let renderPipeline = pipeline as? MTLRenderPipelineState {
            guard #available(macOS 12.0, iOS 15.0, *) else { return nil }
            mtlTable = renderPipeline.makeVisibleFunctionTable(descriptor: mtlDescriptor, stage: MTLRenderStages(table.descriptor.renderStage))
        } else {
            let computePipeline = pipeline as! MTLComputePipelineState
            mtlTable = computePipeline.makeVisibleFunctionTable(descriptor: mtlDescriptor)
        }
        guard let mtlTable = mtlTable else {
            print("MetalPesristentResourceRegistry: Failed to allocate visible function table \(table)")
            return nil
        }
        
        let tableRef = Unmanaged.passRetained(mtlTable)
        
        table.backingResourcePointer = tableRef.toOpaque()
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, *) {
            table[\.gpuAddresses] = mtlTable.gpuResourceID._impl
        }
        
        return mtlTable
    }
    
    nonisolated func allocateIntersectionFunctionTable(_ table: IntersectionFunctionTable) -> MTLIntersectionFunctionTable? {
        guard #available(macOS 11.0, iOS 14.0, *) else { return nil }
        
        let mtlDescriptor = MTLIntersectionFunctionTableDescriptor()
        mtlDescriptor.functionCount = table.descriptor.functions.count
        
        let mtlTable: MTLIntersectionFunctionTable?
        let pipeline = Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(table.pipelineState.state)).takeUnretainedValue()
        if let renderPipeline = pipeline as? MTLRenderPipelineState {
            guard #available(macOS 12.0, iOS 15.0, *) else { return nil }
            mtlTable = renderPipeline.makeIntersectionFunctionTable(descriptor: mtlDescriptor, stage: MTLRenderStages(table.descriptor.renderStage))
        } else {
            let computePipeline = pipeline as! MTLComputePipelineState
            mtlTable = computePipeline.makeIntersectionFunctionTable(descriptor: mtlDescriptor)
        }
        guard let mtlTable = mtlTable else {
            print("MetalPeristentResourceRegistry: Failed to allocate visible function table \(table)")
            return nil
        }
        
        table.backingResourcePointer = Unmanaged.passRetained(mtlTable).toOpaque()
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, *) {
            table[\.gpuAddresses] = mtlTable.gpuResourceID._impl
        }
        
        return mtlTable
    }
    
    public nonisolated func importExternalResource(_ resource: Resource, backingResource: Any) {
        precondition(resource.flags.contains(.persistent), "importExternalResource requires that resource be persistent")
        
        if let texture = Texture(resource) {
            let mtlTexture = backingResource as! MTLTexture
            
            texture.backingResourcePointer = Unmanaged.passRetained(mtlTexture).toOpaque()
            if #available(macOS 13.0, iOS 16.0, tvOS 16.0, *) {
                texture[\.gpuAddresses] = mtlTexture.gpuResourceID._impl
            }
        } else if let buffer = Buffer(resource) {
            let mtlBuffer = backingResource as! MTLBuffer
            
            buffer.backingResourcePointer = Unmanaged.passRetained(mtlBuffer).toOpaque()
            buffer[\.mappedContents] = mtlBuffer.storageMode == .private ? nil : mtlBuffer.contents()
            if #available(macOS 13.0, iOS 16.0, tvOS 16.0, *) {
                buffer[\.gpuAddresses] = mtlBuffer.gpuAddress
            }
        } else if let accelerationStructure = AccelerationStructure(resource) {
            let mtlAccelerationStructure = backingResource as! MTLAccelerationStructure
            
            accelerationStructure.backingResourcePointer = Unmanaged.passRetained(mtlAccelerationStructure).toOpaque()
            
            if #available(macOS 13.0, iOS 16.0, tvOS 16.0, *) {
                accelerationStructure[\.gpuAddresses] = mtlAccelerationStructure.gpuResourceID._impl
            }
        } else {
            preconditionFailure("Unhandled resource type \(resource.type)")
        }
    }
    
    public subscript(descriptor: SamplerDescriptor) -> SamplerState {
        get async {
            if let state = self.samplerReferences[descriptor] {
                return state
            }
            
            let mtlDescriptor = MTLSamplerDescriptor(descriptor, isAppleSiliconGPU: device.isAppleSiliconGPU)
            let mtlState = self.device.makeSamplerState(descriptor: mtlDescriptor)!
            let state = SamplerState(descriptor: descriptor, state: OpaquePointer(Unmanaged.passRetained(mtlState).toOpaque()))
            self.samplerReferences[descriptor] = state
            
            return state
        }
    }
    
    nonisolated func prepareMultiframeBuffer(_ buffer: Buffer, frameIndex: UInt64) {
        // No-op for Metal
    }
    
    nonisolated func prepareMultiframeTexture(_ texture: Texture, frameIndex: UInt64) {
        // No-op for Metal
    }


    nonisolated func dispose(resource: Resource) {
        switch resource.type {
        case .buffer:
            let buffer = Buffer(resource)!
            if let mtlBuffer = buffer.backingResourcePointer {
                if buffer.heap != nil { Unmanaged<MTLResource>.fromOpaque(mtlBuffer)._withUnsafeGuaranteedRef { $0.makeAliasable() } }
                CommandEndActionManager.enqueue(action: .release(Unmanaged.fromOpaque(mtlBuffer)))
            }
        case .texture:
            let texture = Texture(resource)!
            if let mtlTexture = texture.backingResourcePointer {
                if texture.flags.contains(.windowHandle) {
                    return
                }
                if texture.heap != nil { Unmanaged<MTLResource>.fromOpaque(mtlTexture)._withUnsafeGuaranteedRef { $0.makeAliasable() } }
                CommandEndActionManager.enqueue(action: .release(Unmanaged.fromOpaque(mtlTexture)))
            }
            
        case .heap:
            let heap = Heap(resource)!
            if let mtlHeap = heap.backingResourcePointer {
                CommandEndActionManager.enqueue(action: .release(Unmanaged.fromOpaque(mtlHeap)))
            }
            
        case .argumentBuffer:
            let buffer = ArgumentBuffer(resource)!
            if let mtlBuffer = buffer.backingResourcePointer {
                CommandEndActionManager.enqueue(action: .release(Unmanaged.fromOpaque(mtlBuffer)))
            }
        case .accelerationStructure:
            let structure = AccelerationStructure(resource)!
            if let mtlStructure = structure.backingResourcePointer {
                CommandEndActionManager.enqueue(action: .release(Unmanaged.fromOpaque(mtlStructure)))
            }
            
        case .visibleFunctionTable:
            let table = VisibleFunctionTable(resource)!
            if let mtlTable = table.backingResourcePointer {
                CommandEndActionManager.enqueue(action: .release(Unmanaged.fromOpaque(mtlTable)))
            }
            
        case .intersectionFunctionTable:
            let table = IntersectionFunctionTable(resource)!
            if let mtlTable = table.backingResourcePointer {
                CommandEndActionManager.enqueue(action: .release(Unmanaged.fromOpaque(mtlTable)))
            }
        default:
            preconditionFailure("dispose(resource:): Unhandled resource type \(resource.type)")
        }
    }
    
    nonisolated func cycleFrames() {
    }
    
}


final class MetalTransientResourceRegistry: BackendTransientResourceRegistry {
    
    typealias Backend = MetalBackend
    
    let device: MTLDevice
    let queue: Queue
    let persistentRegistry : MetalPersistentResourceRegistry
    var accessLock = SpinLock()
    
    var textureWaitEvents : TransientResourceMap<Texture, ContextWaitEvent>
    var bufferWaitEvents : TransientResourceMap<Buffer, ContextWaitEvent>
    var argumentBufferWaitEvents : TransientResourceMap<ArgumentBuffer, ContextWaitEvent>
    var historyBufferResourceWaitEvents = [Resource : ContextWaitEvent]() // since history buffers use the persistent (rather than transient) resource maps.
    
    private var heapResourceUsageFences = [Resource : [FenceDependency]]()
    private var heapResourceDisposalFences = [Resource : [FenceDependency]]()
    
    private let frameSharedBufferAllocator : MetalTemporaryBufferAllocator
    private let frameSharedWriteCombinedBufferAllocator : MetalTemporaryBufferAllocator
    
    #if os(macOS) || targetEnvironment(macCatalyst)
    private let frameManagedBufferAllocator : MetalTemporaryBufferAllocator?
    private let frameManagedWriteCombinedBufferAllocator : MetalTemporaryBufferAllocator?
    #endif
    
    private let historyBufferAllocator : MetalPoolResourceAllocator
    
    private let memorylessTextureAllocator : MetalPoolResourceAllocator?
    
    private let frameArgumentBufferAllocator : MetalTemporaryBufferAllocator
    
    private let stagingTextureAllocator : MetalPoolResourceAllocator
    private let privateAllocator : MetalHeapResourceAllocator
    
    private let colorRenderTargetAllocator : MetalHeapResourceAllocator
    private let depthRenderTargetAllocator : MetalHeapResourceAllocator
    
    var windowReferences = [Texture : Swapchain]()
    public private(set) var frameDrawables : [(Texture, Result<Drawable, RenderTargetTextureError>)] = []
    
    var isExecutingFrame: Bool = false
    
    public init(device: MTLDevice, inflightFrameCount: Int, queue: Queue, transientRegistryIndex: Int, persistentRegistry: MetalPersistentResourceRegistry) {
        self.device = device
        self.queue = queue
        self.persistentRegistry = persistentRegistry
        
        self.textureWaitEvents = .init(transientRegistryIndex: transientRegistryIndex)
        self.bufferWaitEvents = .init(transientRegistryIndex: transientRegistryIndex)
        self.argumentBufferWaitEvents = .init(transientRegistryIndex: transientRegistryIndex)
        
        self.stagingTextureAllocator = MetalPoolResourceAllocator(device: device, numFrames: inflightFrameCount)
        self.historyBufferAllocator = MetalPoolResourceAllocator(device: device, numFrames: 1)
        
        self.frameSharedBufferAllocator = MetalTemporaryBufferAllocator(device: device, numFrames: inflightFrameCount, blockSize: 256 * 1024, options: [.storageModeShared, .substrateTrackedHazards])
        self.frameSharedWriteCombinedBufferAllocator = MetalTemporaryBufferAllocator(device: device, numFrames: inflightFrameCount, blockSize: 2 * 1024 * 1024, options: [.storageModeShared, .cpuCacheModeWriteCombined, .substrateTrackedHazards])
        
        self.frameArgumentBufferAllocator = MetalTemporaryBufferAllocator(device: device, numFrames: inflightFrameCount, blockSize: 2 * 1024 * 1024, options: [.storageModeShared, .substrateTrackedHazards])
        
        #if os(macOS) || targetEnvironment(macCatalyst)
        if !device.isAppleSiliconGPU {
            self.frameManagedBufferAllocator = MetalTemporaryBufferAllocator(device: device, numFrames: inflightFrameCount, blockSize: 1024 * 1024, options: [.storageModeManaged, .substrateTrackedHazards])
            self.frameManagedWriteCombinedBufferAllocator = MetalTemporaryBufferAllocator(device: device, numFrames: inflightFrameCount, blockSize: 2 * 1024 * 1024, options: [.storageModeManaged, .cpuCacheModeWriteCombined, .substrateTrackedHazards])
        } else {
            self.frameManagedBufferAllocator = nil
            self.frameManagedWriteCombinedBufferAllocator = nil
        }
        #endif
        
        if device.isAppleSiliconGPU {
            self.memorylessTextureAllocator = MetalPoolResourceAllocator(device: device, numFrames: 1)
        } else {
            self.memorylessTextureAllocator = nil
        }
        
        self.privateAllocator = MetalHeapResourceAllocator(device: device, queue: queue, label: "Private Allocator for Queue \(queue.index)")
        self.depthRenderTargetAllocator = MetalHeapResourceAllocator(device: device, queue: queue, label: "Depth RT Allocator for Queue \(queue.index)")
        self.colorRenderTargetAllocator = MetalHeapResourceAllocator(device: device, queue: queue, label: "Color RT Allocator for Queue \(queue.index)")
    }
    
    deinit {
        self.textureWaitEvents.deinit()
        self.bufferWaitEvents.deinit()
        self.argumentBufferWaitEvents.deinit()
    }
    
    public func prepareFrame() {
        self.isExecutingFrame = true
        
        self.textureWaitEvents.prepareFrame()
        self.bufferWaitEvents.prepareFrame()
        self.argumentBufferWaitEvents.prepareFrame()
    }
    
    public func registerWindowTexture(for texture: Texture, swapchain: Swapchain) {
        self.windowReferences[texture] = swapchain
    }
    
    func allocatorForTexture(storageMode: MTLStorageMode, flags: ResourceFlags, textureParams: (PixelFormat, MTLTextureUsage)) -> MetalTextureAllocator {
        assert(!flags.contains(.persistent))
        
        if flags.contains(.historyBuffer) {
            assert(storageMode == .private)
            return self.historyBufferAllocator
        }
        
        if #available(macOS 11.0, macCatalyst 14.0, *), storageMode == .memoryless,
           let memorylessAllocator = self.memorylessTextureAllocator {
            return memorylessAllocator
        }
        
        if storageMode != .private {
            return self.stagingTextureAllocator
        } else {
            if textureParams.0.isDepth || textureParams.0.isStencil {
                return self.depthRenderTargetAllocator
            } else {
                return self.colorRenderTargetAllocator
            }
        }
    }
    
    func allocatorForBuffer(length: Int, storageMode: StorageMode, cacheMode: CPUCacheMode, flags: ResourceFlags) -> MetalBufferAllocator {
        assert(!flags.contains(.persistent))
        
        if flags.contains(.historyBuffer) {
            assert(storageMode == .private)
            return self.historyBufferAllocator
        }
        switch storageMode {
        case .private:
            return self.privateAllocator
        case .managed:
            #if os(macOS) || targetEnvironment(macCatalyst)
            if self.device.isAppleSiliconGPU {
                fallthrough
            } else {
                switch cacheMode {
                case .writeCombined:
                    return self.frameManagedWriteCombinedBufferAllocator!
                case .defaultCache:
                    return self.frameManagedBufferAllocator!
                }
            }
            #else
            fallthrough
            #endif
            
        case .shared:
            switch cacheMode {
            case .writeCombined:
                return self.frameSharedWriteCombinedBufferAllocator
            case .defaultCache:
                return self.frameSharedBufferAllocator
            }
        }
    }
    
    func allocatorForArgumentBuffer(flags: ResourceFlags) -> MetalBufferAllocator {
        assert(!flags.contains(.persistent))
        return self.frameArgumentBufferAllocator
    }
    
    static func isAliasedHeapResource(resource: Resource) -> Bool {
        let flags = resource.flags
        let storageMode : StorageMode = resource.storageMode
        
        if flags.contains(.windowHandle) {
            return false
        }
        
        if flags.intersection([.persistent, .historyBuffer]) != [] {
            return false
        }
        
        return storageMode == .private
    }
    
    func computeTextureUsage(_ texture: Texture, isStoredThisFrame: Bool) -> MTLTextureUsageProperties {
        var textureUsage : MTLTextureUsage = []
        
        for usage in texture.usages {
            if usage.type.contains(.shaderRead) {
                textureUsage.formUnion(.shaderRead)
            }
            if usage.type.contains(.shaderWrite) {
                textureUsage.formUnion(.shaderWrite)
            }
            if !usage.type.intersection([.colorAttachment, .depthStencilAttachment]).isEmpty {
                textureUsage.formUnion(.renderTarget)
            }
            if usage.type.contains(.inputAttachment) {
                if RenderBackend.requiresEmulatedInputAttachments {
                    textureUsage.formUnion(.shaderRead)
                } else {
                    textureUsage.formUnion(.renderTarget)
                }
            }
        }
        
        if texture.descriptor.usageHint.contains(.pixelFormatView) {
            textureUsage.formUnion(.pixelFormatView)
        }
        
        let canBeMemoryless = self.device.isAppleSiliconGPU &&
        (texture.flags.intersection([.persistent, .historyBuffer]) == [] || (texture.flags.contains(.persistent) && texture.descriptor.usageHint.isSubset(of: [.colorAttachment, .depthStencilAttachment, .inputAttachment]))) &&
            textureUsage == .renderTarget &&
            !isStoredThisFrame
        let properties = MTLTextureUsageProperties(usage: textureUsage, canBeMemoryless: canBeMemoryless)
        
        assert(properties.usage != [])
        
        return properties
    }
    
    @discardableResult
    public func allocateTexture(_ texture: Texture, forceGPUPrivate: Bool, isStoredThisFrame: Bool) async -> MTLTextureReference {
        let properties = self.computeTextureUsage(texture, isStoredThisFrame: isStoredThisFrame)
        
        if texture.flags.contains(.windowHandle) {
            // Reserve a slot in texture references so we can later insert the texture reference in a thread-safe way, but don't actually allocate anything yet.
            // We can only do this if the texture is only used as a render target.
            texture.backingResourcePointer = nil
            if !properties.usage.isEmpty, properties.usage != .renderTarget {
                // If we use the texture other than as a render target, we need to eagerly allocate it.
                do {
                    try await self.allocateWindowHandleTexture(texture)
                }
                catch {
                    print("Error allocating window handle texture: \(error)")
                }
            }
            return texture.backingResourcePointer.map { MTLTextureReference(texture: .fromOpaque($0)) } ?? MTLTextureReference(windowTexture: ())
        }
        
        let descriptor = MTLTextureDescriptor(texture.descriptor, usage: properties.usage, isAppleSiliconGPU: self.device.isAppleSiliconGPU)
        
        if properties.canBeMemoryless, #available(macOS 11.0, macCatalyst 14.0, *) {
            descriptor.storageMode = .memoryless
            descriptor.resourceOptions.formUnion(.storageModeMemoryless)
        }
        
        let allocator = self.allocatorForTexture(storageMode: descriptor.storageMode, flags: texture.flags, textureParams: (texture.descriptor.pixelFormat, properties.usage))
        let (mtlTexture, fences, waitEvent) = allocator.collectTextureWithDescriptor(descriptor)
        
        if let label = texture.label {
            mtlTexture.texture.label = label
        }
        
        texture.backingResourcePointer = mtlTexture._texture.toOpaque()
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, *) {
            texture[\.gpuAddresses] = mtlTexture.texture.gpuResourceID._impl
        }
        
        if texture._usesPersistentRegistry {
            precondition(texture.flags.contains(.historyBuffer))
            self.historyBufferResourceWaitEvents[Resource(texture)] = waitEvent
        } else {
            self.textureWaitEvents[texture] = waitEvent
        }
        
        
        if !fences.isEmpty {
            self.heapResourceUsageFences[Resource(texture)] = fences
        }
        
        return mtlTexture
    }
    
    @discardableResult
    public func allocateTextureView(_ texture: Texture) -> MTLTextureReference {
        assert(texture.flags.intersection([.persistent, .windowHandle, .externalOwnership]) == [])
        
        let mtlTexture : MTLTexture
        let properties = self.computeTextureUsage(texture, isStoredThisFrame: true) // We don't allow texture views to be memoryless.
        
        let baseResource = texture.baseResource!
        switch texture.textureViewBaseInfo! {
        case .buffer(let bufferInfo):
            let mtlBuffer = Buffer(baseResource)!.mtlBuffer!
            let descriptor = MTLTextureDescriptor(bufferInfo.descriptor, usage: properties.usage, isAppleSiliconGPU: device.isAppleSiliconGPU)
            mtlTexture = mtlBuffer.buffer.makeTexture(descriptor: descriptor, offset: bufferInfo.offset + mtlBuffer.offset, bytesPerRow: bufferInfo.bytesPerRow)!
        case .texture(let textureInfo):
            let baseTexture = Texture(baseResource)!.mtlTexture!
            if textureInfo.levels.lowerBound == -1 || textureInfo.slices.lowerBound == -1 {
                assert(textureInfo.levels.lowerBound == -1 && textureInfo.slices.lowerBound == -1)
                mtlTexture = baseTexture.makeTextureView(pixelFormat: MTLPixelFormat(textureInfo.pixelFormat))!
            } else {
                mtlTexture = baseTexture.makeTextureView(pixelFormat: MTLPixelFormat(textureInfo.pixelFormat), textureType: MTLTextureType(textureInfo.textureType), levels: textureInfo.levels, slices: textureInfo.slices)!
            }
        }
        
        let textureReference = MTLTextureReference(texture: Unmanaged.passRetained(mtlTexture))
        texture.backingResourcePointer = textureReference._texture.toOpaque()
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, *) {
            texture[\.gpuAddresses] = mtlTexture.gpuResourceID._impl
        }
        return textureReference
    }
    
    @discardableResult
    public func allocateWindowHandleTexture(_ texture: Texture) async throws -> MTLTextureReference {
        precondition(texture.flags.contains(.windowHandle))
        
        // The texture reference should always be present but the texture itself might not be.
        if texture.mtlTexture == nil {
            do {
                guard let windowReference = self.windowReferences.removeValue(forKey: texture) else {
                    throw RenderTargetTextureError.unableToRetrieveDrawable(texture, nil)
                }
                
                let mtlDrawable = try windowReference.nextDrawable()
                let drawableTexture = Unmanaged<MTLTexture>.fromOpaque(mtlDrawable.texture).takeUnretainedValue()
                if drawableTexture.width >= texture.descriptor.size.width && drawableTexture.height >= texture.descriptor.size.height {
                    self.frameDrawables.append((texture, .success(mtlDrawable)))
                    texture.backingResourcePointer = Unmanaged.passRetained(drawableTexture).toOpaque()
                    if #available(macOS 13.0, iOS 16.0, tvOS 16.0, *) {
                        texture[\.gpuAddresses] = drawableTexture.gpuResourceID._impl
                    }
                    
                    if let waitEvent = self.textureWaitEvents[texture] {
                        CommandEndActionManager.enqueue(action: .release(.fromOpaque(texture.backingResourcePointer!)), after: waitEvent.waitValue, on: self.queue)
                    }
                } else {
                    // The window was resized to be smaller than the texture size. We can't render directly to that, so instead
                    // throw an error.
                    throw RenderTargetTextureError.invalidSizeDrawable(texture, requestedSize: Size(width: texture.descriptor.width, height: texture.descriptor.height), drawableSize: Size(width: drawableTexture.width, height: drawableTexture.height))
                }
            } catch let error as RenderTargetTextureError {
                self.frameDrawables.append((texture, .failure(error)))
                throw error
            } catch let error {
                self.frameDrawables.append((texture, .failure(.unableToRetrieveDrawable(texture, error))))
                throw error
            }
        }
        
        return MTLTextureReference(texture: Unmanaged.fromOpaque(texture.backingResourcePointer!))
    }
    
    @discardableResult
    public func allocateBuffer(_ buffer: Buffer, forceGPUPrivate: Bool) -> MTLBufferReference? {
        var options = MTLResourceOptions(storageMode: buffer.descriptor.storageMode, cacheMode: buffer.descriptor.cacheMode, isAppleSiliconGPU: device.isAppleSiliconGPU)
        if buffer.descriptor.usageHint.contains(.textureView) {
            options.remove(.substrateTrackedHazards) // FIXME: workaround for a bug in Metal where setting hazardTrackingModeUntracked on a MTLTextureDescriptor doesn't stick
        }
        

        let allocator = self.allocatorForBuffer(length: buffer.descriptor.length, storageMode: buffer.descriptor.storageMode, cacheMode: buffer.descriptor.cacheMode, flags: buffer.flags)
        let (mtlBuffer, fences, waitEvent) = allocator.collectBufferWithLength(buffer.descriptor.length, options: options)
        
        if let label = buffer.label {
            if allocator is MetalTemporaryBufferAllocator {
                mtlBuffer.buffer.addDebugMarker(label, range: mtlBuffer.offset..<(mtlBuffer.offset + buffer.descriptor.length))
            } else {
                mtlBuffer.buffer.label = label
            }
        }
        
        buffer.backingResourcePointer = mtlBuffer._buffer.toOpaque()
        buffer[\.backingBufferOffsets] = mtlBuffer.offset
        buffer[\.mappedContents] = buffer.storageMode == .private ? nil : mtlBuffer.buffer.contents().advanced(by: mtlBuffer.offset)
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, *) {
            buffer[\.gpuAddresses] = mtlBuffer.buffer.gpuAddress.advanced(by: mtlBuffer.offset)
        }
        
        if buffer._usesPersistentRegistry {
            precondition(buffer.flags.contains(.historyBuffer))
            self.historyBufferResourceWaitEvents[Resource(buffer)] = waitEvent
        } else {
            self.bufferWaitEvents[buffer] = waitEvent
        }
        
        if !fences.isEmpty {
            self.heapResourceUsageFences[Resource(buffer)] = fences
        }
        
        return mtlBuffer
    }
    
    @discardableResult
    public func allocateBufferIfNeeded(_ buffer: Buffer, forceGPUPrivate: Bool) -> MTLBufferReference {
        if let mtlBuffer = buffer.backingResourcePointer {
            return MTLBufferReference(buffer: .fromOpaque(mtlBuffer), offset: buffer[\.backingBufferOffsets] ?? 0)
        }
        return self.allocateBuffer(buffer, forceGPUPrivate: forceGPUPrivate)!
    }
    
    
    @discardableResult
    public func allocateTextureIfNeeded(_ texture: Texture, forceGPUPrivate: Bool, isStoredThisFrame: Bool) async -> MTLTextureReference {
        if let mtlTexture = texture.backingResourcePointer {
            return MTLTextureReference(texture: .fromOpaque(mtlTexture))
        }
        return await self.allocateTexture(texture, forceGPUPrivate: forceGPUPrivate, isStoredThisFrame: isStoredThisFrame)
    }
    
    func allocateArgumentBufferStorage<A : ResourceProtocol>(for argumentBuffer: A, encodedLength: Int) -> (MTLBufferReference, [FenceDependency], ContextWaitEvent) {
//        #if os(macOS)
//        let options : MTLResourceOptions = [.storageModeManaged, .substrateTrackedHazards]
//        #else
        let options : MTLResourceOptions = [.storageModeShared, .substrateTrackedHazards]
//        #endif
        
        let allocator = self.allocatorForArgumentBuffer(flags: argumentBuffer.flags)
        return allocator.collectBufferWithLength(encodedLength, options: options)
    }
    
    @discardableResult
    func allocateArgumentBufferIfNeeded(_ argumentBuffer: ArgumentBuffer) -> MTLBufferReference {
        if let mtlArgumentBuffer = argumentBuffer.backingResourcePointer {
            return MTLBufferReference(buffer: .fromOpaque(mtlArgumentBuffer), offset: argumentBuffer[\.backingBufferOffsets]!)
        }
        
        let (storage, fences, waitEvent) = self.allocateArgumentBufferStorage(for: argumentBuffer, encodedLength: argumentBuffer.descriptor.bufferLength)
        assert(fences.isEmpty)
        
        argumentBuffer.backingResourcePointer = storage._buffer.toOpaque()
        argumentBuffer[\.backingBufferOffsets] = storage.offset
        argumentBuffer[\.mappedContents] = argumentBuffer.storageMode == .private ? nil : storage.buffer.contents().advanced(by: storage.offset)
    
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, *) {
            argumentBuffer[\.gpuAddresses] = storage.buffer.gpuAddress.advanced(by: storage.offset)
        } else {
            argumentBuffer[\.encoders] = Unmanaged.passUnretained(self.persistentRegistry.stateCaches.argumentEncoderCache[argumentBuffer.descriptor])
        }
        
        argumentBuffer.usedResources.insert(storage._buffer.toOpaque())
        
        self.argumentBufferWaitEvents[argumentBuffer] = waitEvent
        
        return storage
    }
    
    public func importExternalResource(_ resource: Resource, backingResource: Any) {
        if let texture = Texture(resource) {
            texture.backingResourcePointer = Unmanaged.passRetained(backingResource as! MTLTexture).toOpaque()
        } else if let buffer = Buffer(resource) {
            buffer.backingResourcePointer = Unmanaged.passRetained(backingResource as! MTLBuffer).toOpaque()
            buffer[\.backingBufferOffsets] = 0
        }
    }
    
    public func withHeapAliasingFencesIfPresent(for resourceHandle: Resource.Handle, perform: (inout [FenceDependency]) -> Void) {
        let resource = Resource(handle: resourceHandle)
        
        perform(&self.heapResourceUsageFences[resource, default: []])
    }
    
    func setDisposalFences(on resource: Resource, to fences: [FenceDependency]) {
        assert(Self.isAliasedHeapResource(resource: resource))
        self.heapResourceDisposalFences[resource] = fences
    }
    
    func disposeTexture(_ texture: Texture, waitEvent: ContextWaitEvent) {
        // We keep the reference around until the end of the frame since allocation/disposal is all processed ahead of time.
        
        if texture._usesPersistentRegistry {
            precondition(texture.flags.contains(.historyBuffer))
            _ = Unmanaged<MTLTexture>.fromOpaque(texture.backingResourcePointer!).retain() // since the persistent registry releases its resources unconditionally on dispose, but we want the allocator to have ownership of it.
        }
        
        if let mtlTexture = texture.backingResourcePointer {
            if texture.flags.contains(.windowHandle) || texture.isTextureView {
                CommandEndActionManager.enqueue(action: .release(.fromOpaque(mtlTexture)), after: waitEvent.waitValue, on: self.queue)
                return
            }
            
            var fences : [FenceDependency] = []
            if Self.isAliasedHeapResource(resource: Resource(texture)) {
                fences = self.heapResourceDisposalFences[Resource(texture)] ?? []
            }
            
            let allocator = self.allocatorForTexture(storageMode: texture.mtlTexture!.storageMode, flags: texture.flags, textureParams: (texture.descriptor.pixelFormat, texture.mtlTexture!.usage))
            allocator.depositTexture(MTLTextureReference(texture: .fromOpaque(mtlTexture)), fences: fences, waitEvent: waitEvent)
        } else if texture.flags.contains(.windowHandle) {
            self.textureWaitEvents[texture] = waitEvent
        }
    }
    
    func disposeBuffer(_ buffer: Buffer, waitEvent: ContextWaitEvent) {
        // We keep the reference around until the end of the frame since allocation/disposal is all processed ahead of time.
        
        if buffer._usesPersistentRegistry {
            precondition(buffer.flags.contains(.historyBuffer))
            _ = Unmanaged<MTLBuffer>.fromOpaque(buffer.backingResourcePointer!).retain() // since the persistent registry releases its resources unconditionally on dispose, but we want the allocator to have ownership of it.
        }
        
        if let mtlBuffer = buffer.mtlBuffer {
            var fences : [FenceDependency] = []
            if Self.isAliasedHeapResource(resource: Resource(buffer)) {
                fences = self.heapResourceDisposalFences[Resource(buffer)] ?? []
            }
            
            let allocator = self.allocatorForBuffer(length: buffer.descriptor.length, storageMode: buffer.descriptor.storageMode, cacheMode: buffer.descriptor.cacheMode, flags: buffer.flags)
            allocator.depositBuffer(MTLBufferReference(buffer: .fromOpaque(buffer.backingResourcePointer!), offset: mtlBuffer.offset), fences: fences, waitEvent: waitEvent)
        }
    }
    
    func disposeArgumentBuffer(_ buffer: ArgumentBuffer, waitEvent: ContextWaitEvent) {
        if let mtlBuffer = buffer.backingResourcePointer {
            let allocator = self.allocatorForArgumentBuffer(flags: buffer.flags)
            allocator.depositBuffer(MTLBufferReference(buffer: .fromOpaque(mtlBuffer), offset: buffer[\.backingBufferOffsets]!), fences: [], waitEvent: waitEvent)
        }
    }
    
    func clearDrawables() {
        self.frameDrawables.removeAll(keepingCapacity: true)
    }
    
    func makeTransientAllocatorsPurgeable() {
        if self.isExecutingFrame { return }
        
        self.stagingTextureAllocator.makePurgeable()
        self.privateAllocator.makePurgeable()
        self.historyBufferAllocator.makePurgeable()
        
        self.colorRenderTargetAllocator.makePurgeable()
        self.depthRenderTargetAllocator.makePurgeable()
        
        self.frameSharedBufferAllocator.makePurgeable()
        self.frameSharedWriteCombinedBufferAllocator.makePurgeable()
        
        #if os(macOS) || targetEnvironment(macCatalyst)
        self.frameManagedBufferAllocator?.makePurgeable()
        self.frameManagedWriteCombinedBufferAllocator?.makePurgeable()
        #endif
        
        self.frameArgumentBufferAllocator.makePurgeable()
    }
    
    func cycleFrames() {
        // Clear all transient resources at the end of the frame.
        
        self.heapResourceUsageFences.removeAll(keepingCapacity: true)
        self.heapResourceDisposalFences.removeAll(keepingCapacity: true)
        
        self.stagingTextureAllocator.cycleFrames()
        self.privateAllocator.cycleFrames()
        self.historyBufferAllocator.cycleFrames()
        
        self.colorRenderTargetAllocator.cycleFrames()
        self.depthRenderTargetAllocator.cycleFrames()
        
        self.frameSharedBufferAllocator.cycleFrames()
        self.frameSharedWriteCombinedBufferAllocator.cycleFrames()
        
        #if os(macOS) || targetEnvironment(macCatalyst)
        self.frameManagedBufferAllocator?.cycleFrames()
        self.frameManagedWriteCombinedBufferAllocator?.cycleFrames()
        #endif
        self.memorylessTextureAllocator?.cycleFrames()
        
        self.frameArgumentBufferAllocator.cycleFrames()
        
        self.isExecutingFrame = false
    }
}

#endif // canImport(Metal)
