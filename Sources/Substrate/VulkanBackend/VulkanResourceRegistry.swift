//
//  ResourceRegistery.swift
//  SubstratePackageDescription
//
//  Created by Joseph Bennett on 1/01/18.
//

#if canImport(Vulkan)
import Vulkan
import SubstrateUtilities
import SubstrateCExtras
import Dispatch

class VulkanHeap {} // Just a stub for now.

struct VkBufferReference {
    let _buffer : Unmanaged<VulkanBuffer>
    let offset : Int
    
    var buffer : VulkanBuffer {
        return self._buffer.takeUnretainedValue()
    }
    
    var resource : VulkanBuffer {
        return self._buffer.takeUnretainedValue()
    }
    
    init(buffer: Unmanaged<VulkanBuffer>, offset: Int) {
        self._buffer = buffer
        self.offset = offset
    }
}

// Must be a POD type and trivially copyable/movable
struct VkImageReference {
    var _image : Unmanaged<VulkanImage>!
    
    var image : VulkanImage {
        return _image.takeUnretainedValue()
    }
    
    var resource : VulkanImage {
        return self.image
    }
    
    init(windowTexture: ()) {
        self._image = nil
    }
    
    init(image: Unmanaged<VulkanImage>) {
        self._image = image
    }
}

final actor VulkanPersistentResourceRegistry: BackendPersistentResourceRegistry {

    typealias Backend = VulkanBackend
    
    let device : VulkanDevice
    let vmaAllocator : VmaAllocator
    
    let descriptorPool: VulkanDescriptorPool
    
    let heapReferences = PersistentResourceMap<Heap, VulkanHeap>()
    let textureReferences = PersistentResourceMap<Texture, VkImageReference>()
    let bufferReferences = PersistentResourceMap<Buffer, VkBufferReference>()
    let argumentBufferReferences = PersistentResourceMap<ArgumentBuffer, VulkanArgumentBuffer>()
    let argumentBufferArrayReferences = PersistentResourceMap<ArgumentBufferArray, VulkanArgumentBuffer>()
    
    var samplers = [SamplerDescriptor: VkSampler]()
    
    public init(instance: VulkanInstance, device: VulkanDevice) {
        self.device = device
        
        var allocatorInfo = VmaAllocatorCreateInfo(flags: 0, physicalDevice: device.vkDevice, device: device.vkDevice, preferredLargeHeapBlockSize: 0, pAllocationCallbacks: nil, pDeviceMemoryCallbacks: nil, frameInUseCount: 0, pHeapSizeLimit: nil, pVulkanFunctions: nil, pRecordSettings: nil, instance: instance.instance,
                                                   vulkanApiVersion: VulkanVersion.apiVersion.value,
                                                   pTypeExternalMemoryHandleTypes: nil)
        allocatorInfo.device = device.vkDevice
        allocatorInfo.physicalDevice = device.physicalDevice.vkDevice

        var allocator : VmaAllocator? = nil
        vmaCreateAllocator(&allocatorInfo, &allocator).check()
        self.vmaAllocator = allocator!
        
        self.descriptorPool = VulkanDescriptorPool(device: device, incrementalRelease: true)
        
        VulkanEventRegistry.instance.device = self.device.vkDevice
    }
    
    deinit {
        self.textureReferences.deinit()
        self.bufferReferences.deinit()
        self.argumentBufferReferences.deinit()
        self.argumentBufferArrayReferences.deinit()
    }
    
    @discardableResult
    public nonisolated func allocateTexture(_ texture: Texture) -> VkImageReference? {
        precondition(texture._usesPersistentRegistry)
        
        if texture.flags.contains(.windowHandle) {
            // Reserve a slot in texture references so we can later insert the texture reference in a thread-safe way, but don't actually allocate anything yet
            self.textureReferences[texture] = VkImageReference(windowTexture: ())
            return nil
        }
        
        let usage = VkImageUsageFlagBits(texture.descriptor.usageHint, pixelFormat: texture.descriptor.pixelFormat)
        
        let initialLayout = texture.descriptor.storageMode != .private ? VK_IMAGE_LAYOUT_PREINITIALIZED : VK_IMAGE_LAYOUT_UNDEFINED
        let sharingMode = VulkanSharingMode(usage: usage, device: self.device) // FIXME: can we infer this?
        
        // NOTE: all synchronisation is managed through the per-queue waitIndices associated with the resource.
        
        let descriptor = VulkanImageDescriptor(texture.descriptor, usage: usage, sharingMode: sharingMode, initialLayout: initialLayout)
        

        var allocInfo = VmaAllocationCreateInfo(storageMode: texture.descriptor.storageMode, cacheMode: texture.descriptor.cacheMode)
        var image : VkImage? = nil
        var allocation : VmaAllocation? = nil
        descriptor.withImageCreateInfo(device: self.device) { (info) in
            var info = info
            vmaCreateImage(self.vmaAllocator, &info, &allocInfo, &image, &allocation, nil).check()
        }
        
        let vkImage = VulkanImage(device: self.device, image: image!, allocator: self.vmaAllocator, allocation: allocation!, descriptor: descriptor)
        
        if let label = texture.label {
            vkImage.label = label
        }
        
        assert(self.textureReferences[texture] == nil)
        let imageReference = VkImageReference(image: Unmanaged.passRetained(vkImage))
        self.textureReferences[texture] = imageReference
        
        return imageReference
    }
    
    @discardableResult
    public nonisolated func allocateBuffer(_ buffer: Buffer) -> VkBufferReference? {
        precondition(buffer._usesPersistentRegistry)
        
        let usage = VkBufferUsageFlagBits(buffer.descriptor.usageHint)
        
        let sharingMode = VulkanSharingMode(usage: usage, device: self.device) // FIXME: can we infer this?
        
        // NOTE: all synchronisation is managed through the per-queue waitIndices associated with the resource.
        let descriptor = VulkanBufferDescriptor(buffer.descriptor, usage: usage, sharingMode: sharingMode)
        
        var allocInfo = VmaAllocationCreateInfo(storageMode: buffer.descriptor.storageMode, cacheMode: buffer.descriptor.cacheMode)
        var vkBuffer : VkBuffer? = nil
        var allocation : VmaAllocation? = nil
        var allocationInfo = VmaAllocationInfo()
        descriptor.withBufferCreateInfo(device: self.device) { (info) in
            var info = info
            vmaCreateBuffer(self.vmaAllocator, &info, &allocInfo, &vkBuffer, &allocation, &allocationInfo).check()
        }
        
        let vulkanBuffer = VulkanBuffer(device: self.device, buffer: vkBuffer!, allocator: self.vmaAllocator, allocation: allocation!, allocationInfo: allocationInfo, descriptor: descriptor)
        
        let vkBufferReference = VkBufferReference(buffer: Unmanaged<VulkanBuffer>.passRetained(vulkanBuffer), offset: 0)
        
        if let label = buffer.label {
            vulkanBuffer.label = label
        }
        
        assert(self.bufferReferences[buffer] == nil)
        self.bufferReferences[buffer] = vkBufferReference
        
        return vkBufferReference
    }
    
    @discardableResult
    nonisolated func allocateArgumentBufferIfNeeded(_ argumentBuffer: ArgumentBuffer) -> VulkanArgumentBuffer {
        if let baseArray = argumentBuffer.sourceArray {
            _ = self.allocateArgumentBufferArrayIfNeeded(baseArray)
            return self.argumentBufferReferences[argumentBuffer]!
        }
        if let vkArgumentBuffer = self.argumentBufferReferences[argumentBuffer] {
            return vkArgumentBuffer
        }
        
        let setLayout = Unmanaged<VulkanDescriptorSetLayout>.fromOpaque(argumentBuffer.encoder!).takeUnretainedValue()
        let set = self.descriptorPool.allocateSet(layout: setLayout.vkLayout)
        
        let buffer = VulkanArgumentBuffer(device: self.device,
                                          layout: setLayout,
                                          descriptorSet: set)
        
        self.argumentBufferReferences[argumentBuffer] = buffer
        
        return buffer
    }
    
    @discardableResult
    nonisolated func allocateArgumentBufferArrayIfNeeded(_ argumentBufferArray: ArgumentBufferArray) -> VulkanArgumentBuffer {
        if let vkArgumentBuffer = self.argumentBufferArrayReferences[argumentBufferArray] {
            return vkArgumentBuffer
        }
        
        fatalError("Unimplemented")
    }
    
    public nonisolated func importExternalResource(_ resource: Resource, backingResource: Any) {
        if let texture = Texture(resource) {
            self.textureReferences[texture] = VkImageReference(image: Unmanaged.passRetained(backingResource as! VulkanImage))
        } else if let buffer = Buffer(resource) {
            self.bufferReferences[buffer] = VkBufferReference(buffer: Unmanaged.passRetained(backingResource as! VulkanBuffer), offset: 0)
        }
    }
    
    public nonisolated subscript(texture: Texture) -> VkImageReference? {
        return self.textureReferences[texture]
    }

    public nonisolated subscript(buffer: Buffer) -> VkBufferReference? {
        return self.bufferReferences[buffer]
    }

    public nonisolated subscript(argumentBuffer: ArgumentBuffer) -> VulkanArgumentBuffer? {
        return self.argumentBufferReferences[argumentBuffer]
    }

    public nonisolated subscript(argumentBufferArray: ArgumentBufferArray) -> VulkanArgumentBuffer? {
        return self.argumentBufferArrayReferences[argumentBufferArray]
    }

    public subscript(sampler: SamplerDescriptor) -> VkSampler {
        get async {
            if let vkSampler = self.samplers[sampler] {
                return vkSampler
            }
            
            var samplerCreateInfo = VkSamplerCreateInfo(descriptor: sampler)
            
            var vkSampler : VkSampler? = nil
            vkCreateSampler(self.device.vkDevice, &samplerCreateInfo, nil, &vkSampler)
            
            self.samplers[sampler] = vkSampler!
            
            return vkSampler!
        }
    }
    
    nonisolated func prepareMultiframeBuffer(_ buffer: Buffer, frameIndex: UInt64) {
        
    }
    
    nonisolated func prepareMultiframeTexture(_ texture: Texture, frameIndex: UInt64) {
        if let image = self[texture] {
            image.image.computeFrameLayouts(resource: Resource(texture), usages: texture.usages, preserveLastLayout: texture.stateFlags.contains(.initialised), frameIndex: frameIndex)
        }
    }
    
    nonisolated func dispose(resource: Resource) {
        switch resource.type {
        case .buffer:
            let buffer = Buffer(resource)!
            if let vkBuffer = self.bufferReferences.removeValue(forKey: buffer) {
                // TODO: Allow future allocations to alias against this resource, even if it may still be retained by a command buffer.
                CommandEndActionManager.enqueue(action: .release(Unmanaged.fromOpaque(vkBuffer._buffer.toOpaque())))
            }
        case .texture:
            let texture = Texture(resource)!
            if let vkTexture = self.textureReferences.removeValue(forKey: texture) {
                if texture.flags.contains(.windowHandle) {
                    return
                }
                // TODO: Allow future allocations to alias against this resource, even if it may still be retained by a command buffer.
                CommandEndActionManager.enqueue(action: .release(Unmanaged.fromOpaque(vkTexture._image.toOpaque())))
            }
            
        case .heap:
            let heap = Heap(resource)!
            if let vkHeap = self.heapReferences.removeValue(forKey: heap) {
                CommandEndActionManager.enqueue(action: .release(Unmanaged.passRetained(vkHeap)))
            }
            
        case .argumentBuffer:
            let buffer = ArgumentBuffer(resource)!
            assert(buffer.sourceArray == nil, "Persistent argument buffers from an argument buffer array should not be disposed individually; this needs to be fixed within the Vulkan RenderGraph backend.")
            if let vkBuffer = self.argumentBufferReferences.removeValue(forKey: buffer) {
                assert(buffer.sourceArray == nil, "Persistent argument buffers from an argument buffer array should not be disposed individually; this needs to be fixed within the Metal RenderGraph backend.")
                
                // TODO: Allow future allocations to alias against this resource, even if it may still be retained by a command buffer.
                CommandEndActionManager.enqueue(action: .release(Unmanaged.passRetained(vkBuffer)))
            }
            
        case .argumentBufferArray:
            let buffer = ArgumentBufferArray(resource)!
            if let vkBuffer = self.argumentBufferArrayReferences.removeValue(forKey: buffer) {
                // TODO: Allow future allocations to alias against this resource, even if it may still be retained by a command buffer.
                CommandEndActionManager.enqueue(action: .release(Unmanaged.passRetained(vkBuffer)))
            }
        default:
            preconditionFailure("dispose(resource:): Unhandled resource type \(resource.type)")
        }
    }
    
    nonisolated subscript(accelerationStructure: AccelerationStructure) -> AnyObject? {
        return nil
    }

    nonisolated subscript(visibleFunctionTable: VisibleFunctionTable) -> Void? {
        return nil
    }

    nonisolated subscript(intersectionFunctionTable: IntersectionFunctionTable) -> Void? {
        return nil
    }

    func allocateVisibleFunctionTableIfNeeded(_ table: VisibleFunctionTable) async -> Void? {
        return nil
    }

    func allocateIntersectionFunctionTableIfNeeded(_ table: IntersectionFunctionTable) async -> Void? {
        return nil
    }
    
    nonisolated func cycleFrames() {
        // TODO: we should dispose command buffer resources here.
    }
}

final class VulkanTransientResourceRegistry: BackendTransientResourceRegistry {
    typealias Backend = VulkanBackend
    
    let persistentRegistry : VulkanPersistentResourceRegistry
    let transientRegistryIndex: Int
    var accessLock = SpinLock()
    
    private var textureReferences : TransientResourceMap<Texture, VkImageReference>
    private var bufferReferences : TransientResourceMap<Buffer, VkBufferReference>
    private var argumentBufferReferences : TransientResourceMap<ArgumentBuffer, VulkanArgumentBuffer>
    private var argumentBufferArrayReferences : TransientResourceMap<ArgumentBufferArray, VulkanArgumentBuffer>
    
    var textureWaitEvents: TransientResourceMap<Texture, ContextWaitEvent>
    var bufferWaitEvents: TransientResourceMap<Buffer, ContextWaitEvent>
    var historyBufferResourceWaitEvents = [Resource : ContextWaitEvent]()
    
    private var heapResourceUsageFences = [Resource : [FenceDependency]]()
    private var heapResourceDisposalFences = [Resource : [FenceDependency]]()
    
    private let frameSharedBufferAllocator : VulkanTemporaryBufferAllocator
    private let frameSharedWriteCombinedBufferAllocator : VulkanTemporaryBufferAllocator
    
    private let frameManagedBufferAllocator : VulkanTemporaryBufferAllocator
    private let frameManagedWriteCombinedBufferAllocator : VulkanTemporaryBufferAllocator

    private let stagingTextureAllocator : VulkanPoolResourceAllocator
    private let historyBufferAllocator : VulkanPoolResourceAllocator
    private let privateAllocator : VulkanPoolResourceAllocator
    
    private let descriptorPools: [VulkanDescriptorPool]
    
    public let inflightFrameCount: Int
    private var descriptorPoolIndex: Int = 0
    private var frameIndex: UInt64 = 0
    
    var windowReferences = [Texture : VulkanSwapChain]()
    public private(set) var frameSwapChains : [VulkanSwapChain] = []
    
    public init(device: VulkanDevice, inflightFrameCount: Int, transientRegistryIndex: Int, persistentRegistry: VulkanPersistentResourceRegistry) {
        self.inflightFrameCount = inflightFrameCount
        self.transientRegistryIndex = transientRegistryIndex
        self.persistentRegistry = persistentRegistry
        
        self.textureReferences = .init(transientRegistryIndex: transientRegistryIndex)
        self.bufferReferences = .init(transientRegistryIndex: transientRegistryIndex)
        self.argumentBufferReferences = .init(transientRegistryIndex: transientRegistryIndex)
        self.argumentBufferArrayReferences = .init(transientRegistryIndex: transientRegistryIndex)
        
        self.textureWaitEvents = .init(transientRegistryIndex: transientRegistryIndex)
        self.bufferWaitEvents = .init(transientRegistryIndex: transientRegistryIndex)
        
        self.frameSharedBufferAllocator = VulkanTemporaryBufferAllocator(device: device, allocator: persistentRegistry.vmaAllocator, storageMode: .shared, cacheMode: .defaultCache, inflightFrameCount: inflightFrameCount)
        self.frameSharedWriteCombinedBufferAllocator = VulkanTemporaryBufferAllocator(device: device, allocator: persistentRegistry.vmaAllocator, storageMode: .shared, cacheMode: .writeCombined, inflightFrameCount: inflightFrameCount)
               
        self.frameManagedBufferAllocator = VulkanTemporaryBufferAllocator(device: device, allocator: persistentRegistry.vmaAllocator, storageMode: .managed, cacheMode: .defaultCache, inflightFrameCount: inflightFrameCount)
        self.frameManagedWriteCombinedBufferAllocator = VulkanTemporaryBufferAllocator(device: device, allocator: persistentRegistry.vmaAllocator, storageMode: .managed, cacheMode: .writeCombined, inflightFrameCount: inflightFrameCount)
        
        self.stagingTextureAllocator = VulkanPoolResourceAllocator(device: device, allocator: persistentRegistry.vmaAllocator, numFrames: inflightFrameCount)
        self.historyBufferAllocator = VulkanPoolResourceAllocator(device: device, allocator: persistentRegistry.vmaAllocator, numFrames: 1)
        self.privateAllocator = VulkanPoolResourceAllocator(device: device, allocator: persistentRegistry.vmaAllocator, numFrames: 1)
        
        self.descriptorPools = (0..<inflightFrameCount).map { _ in VulkanDescriptorPool(device: device, incrementalRelease: false) }
        
        self.prepareFrame()
    }
    
    deinit {
        self.textureReferences.deinit()
        self.bufferReferences.deinit()
        self.argumentBufferReferences.deinit()
        self.argumentBufferArrayReferences.deinit()
        
        self.textureWaitEvents.deinit()
        self.bufferWaitEvents.deinit()
    }
    
    public func prepareFrame() {
        VulkanEventRegistry.instance.clearCompletedEvents()
        
        self.textureReferences.prepareFrame()
        self.bufferReferences.prepareFrame()
        self.argumentBufferReferences.prepareFrame()
        self.argumentBufferArrayReferences.prepareFrame()
        
        self.textureWaitEvents.prepareFrame()
        self.bufferWaitEvents.prepareFrame()
        
        self.descriptorPools[self.descriptorPoolIndex].resetDescriptorPool()
    }
    
    public func registerWindowTexture(for texture: Texture, swapchain: Any) {
        self.windowReferences[texture] = (swapchain as! VulkanSwapChain)
    }
    

    func allocatorForBuffer(storageMode: StorageMode, cacheMode: CPUCacheMode, flags: ResourceFlags) -> VulkanBufferAllocator {
        assert(!flags.contains(.persistent))
        
        if flags.contains(.historyBuffer) {
            assert(storageMode == .private)
            return self.historyBufferAllocator
        }
        switch storageMode {
        case .private:
            return self.privateAllocator
        case .managed:
            switch cacheMode {
            case .writeCombined:
                return self.frameManagedWriteCombinedBufferAllocator
            case .defaultCache:
                return self.frameManagedBufferAllocator
            }
            
        case .shared:
            switch cacheMode {
            case .writeCombined:
                return self.frameSharedWriteCombinedBufferAllocator
            case .defaultCache:
                return self.frameSharedBufferAllocator
            }
        }
    }
    
    func allocatorForImage(storageMode: StorageMode, cacheMode: CPUCacheMode, flags: ResourceFlags) -> VulkanImageAllocator {
        assert(!flags.contains(.persistent))
        
        if flags.contains(.historyBuffer) {
            assert(storageMode == .private)
            return self.historyBufferAllocator
        }
        
        if storageMode != .private {
            return self.stagingTextureAllocator
        } else {
            return self.privateAllocator
        }
    }
    
    static func isAliasedHeapResource(resource: Resource) -> Bool {
        return false
    }
    
    @discardableResult
    public func allocateTexture(_ texture: Texture, forceGPUPrivate: Bool) -> VkImageReference {
        if texture.flags.contains(.windowHandle) {    
            self.textureReferences[texture] = VkImageReference(windowTexture: ()) // We retrieve the swapchain image later.
            return VkImageReference(windowTexture: ())
        }

        var imageUsage : VkImageUsageFlagBits = []
        
        let canBeTransient = texture.usages.allSatisfy({ $0.type.isRenderTarget })
        if canBeTransient {
            imageUsage.formUnion(VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT)
        }
        let isDepthOrStencil = texture.descriptor.pixelFormat.isDepth || texture.descriptor.pixelFormat.isStencil
        
        for usage in texture.usages {
            switch usage.type {
            case .read:
                imageUsage.formUnion(VK_IMAGE_USAGE_SAMPLED_BIT)
            case .write, .readWrite:
                imageUsage.formUnion(VK_IMAGE_USAGE_STORAGE_BIT)
            case .readWriteRenderTarget, .writeOnlyRenderTarget:
                imageUsage.formUnion(isDepthOrStencil ? VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT : VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT)
            case .inputAttachment, .inputAttachmentRenderTarget:
                imageUsage.formUnion(VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT)
            case .blitSource:
                imageUsage.formUnion(VK_IMAGE_USAGE_TRANSFER_SRC_BIT)
            case .blitDestination:
                imageUsage.formUnion(VK_IMAGE_USAGE_TRANSFER_DST_BIT)
            default:
                break
            }
        }
        
        var descriptor = texture.descriptor
        let flags = texture.flags
        
        if forceGPUPrivate {
            descriptor.storageMode = .private
        }

        let allocator = self.allocatorForImage(storageMode: descriptor.storageMode, cacheMode: descriptor.cacheMode, flags: flags)
        let (vkImage, events, waitEvent) = allocator.collectImage(descriptor: VulkanImageDescriptor(descriptor, usage: imageUsage, sharingMode: .exclusive, initialLayout: VK_IMAGE_LAYOUT_UNDEFINED))
        
        if let label = texture.label {
            vkImage.image.label = label
        }
        
        if texture._usesPersistentRegistry {
            precondition(texture.flags.contains(.historyBuffer))
            self.persistentRegistry.textureReferences[texture] = vkImage
            self.historyBufferResourceWaitEvents[Resource(texture)] = waitEvent
        } else {
            precondition(self.textureReferences[texture] == nil)
            self.textureReferences[texture] = vkImage
            self.textureWaitEvents[texture] = waitEvent
        }
        
        if !events.isEmpty {
            self.heapResourceUsageFences[Resource(texture)] = events
        }
        
        vkImage.image.computeFrameLayouts(resource: Resource(texture), usages: texture.usages, preserveLastLayout: false, frameIndex: self.frameIndex)
        
        return vkImage
    }
    
    @discardableResult
    public func allocateTextureView(_ texture: Texture, resourceMap: FrameResourceMap<VulkanBackend>) -> VkImageReference {
        fatalError("Unimplemented")
    }
    

    @MainActor
    private func createWindowHandleTexture(_ texture: Texture) {
        let swapChain = self.windowReferences.removeValue(forKey: texture)!
        self.frameSwapChains.append(swapChain)
        let image = swapChain.nextImage(descriptor: texture.descriptor)
        image.computeFrameLayouts(resource: Resource(texture), usages: texture.usages, preserveLastLayout: false, frameIndex: self.frameIndex)
        self.textureReferences[texture] = VkImageReference(image: Unmanaged.passUnretained(image))
    }

    @discardableResult
    public func allocateWindowHandleTexture(_ texture: Texture) async throws -> VkImageReference {
        precondition(texture.flags.contains(.windowHandle))
        
        if self.textureReferences[texture]!._image == nil {
            await self.createWindowHandleTexture(texture)
        }

        return self.textureReferences[texture]!
    }
    
    @discardableResult
    public func allocateBuffer(_ buffer: Buffer, forceGPUPrivate: Bool) -> VkBufferReference {
        // If this is a CPU-visible buffer, include the usage hints passed by the user.
        var bufferUsage: VkBufferUsageFlagBits = forceGPUPrivate ? [] : VkBufferUsageFlagBits(buffer.descriptor.usageHint)

        for usage in buffer.usages {
            switch usage.type {
            case .constantBuffer:
                bufferUsage.formUnion(VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT)
            case .read:
                bufferUsage.formUnion([VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT])
            case .write:
                bufferUsage.formUnion([VK_BUFFER_USAGE_STORAGE_BUFFER_BIT])
            case .readWrite:
                bufferUsage.formUnion([VK_BUFFER_USAGE_STORAGE_BUFFER_BIT])
            case .vertexBuffer:
                bufferUsage.formUnion(VK_BUFFER_USAGE_VERTEX_BUFFER_BIT)
            case .indexBuffer:
                bufferUsage.formUnion(VK_BUFFER_USAGE_INDEX_BUFFER_BIT)
            case .blitSource:
                bufferUsage.formUnion(VK_BUFFER_USAGE_TRANSFER_SRC_BIT)
            case .blitDestination:
                bufferUsage.formUnion(VK_BUFFER_USAGE_TRANSFER_DST_BIT)
            default:
                break
            }
        }
        if bufferUsage.isEmpty, !forceGPUPrivate {
            bufferUsage = [VK_BUFFER_USAGE_TRANSFER_SRC_BIT, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT]
        }

        var descriptor = buffer.descriptor
        
        if forceGPUPrivate {
            descriptor.storageMode = .private
        }
        
        let allocator = self.allocatorForBuffer(storageMode: forceGPUPrivate ? .private : buffer.descriptor.storageMode, cacheMode: buffer.descriptor.cacheMode, flags: buffer.flags)
        let (vkBuffer, events, waitSemaphore) = allocator.collectBuffer(descriptor: VulkanBufferDescriptor(descriptor, usage: bufferUsage, sharingMode: .exclusive))
        
        if let label = buffer.label {
            vkBuffer.buffer.label = label
        }
        
        if buffer._usesPersistentRegistry {
            precondition(buffer.flags.contains(.historyBuffer))
            self.persistentRegistry.bufferReferences[buffer] = vkBuffer
            self.historyBufferResourceWaitEvents[Resource(buffer)] = waitSemaphore
        } else {
            precondition(self.bufferReferences[buffer] == nil)
            self.bufferReferences[buffer] = vkBuffer
            self.bufferWaitEvents[buffer] = waitSemaphore
        }
        
        if !events.isEmpty {
            self.heapResourceUsageFences[Resource(buffer)] = events
        }
        
        return vkBuffer
    }
    
    @discardableResult
    public func allocateBufferIfNeeded(_ buffer: Buffer, forceGPUPrivate: Bool) -> VkBufferReference {
        if let vkBuffer = self.bufferReferences[buffer] {
            return vkBuffer
        }
        return self.allocateBuffer(buffer, forceGPUPrivate: forceGPUPrivate)
    }
    
    @discardableResult
    public func allocateTextureIfNeeded(_ texture: Texture, forceGPUPrivate: Bool, isStoredThisFrame: Bool) -> VkImageReference {
        if let vkTexture = self.textureReferences[texture] {
            return vkTexture
        }
        return self.allocateTexture(texture, forceGPUPrivate: forceGPUPrivate)
    }
    
    @discardableResult
    func allocateArgumentBufferIfNeeded(_ argumentBuffer: ArgumentBuffer) -> VulkanArgumentBuffer {
        if let baseArray = argumentBuffer.sourceArray {
            _ = self.allocateArgumentBufferArrayIfNeeded(baseArray)
            return self.argumentBufferReferences[argumentBuffer]!
        }
        if let vkArgumentBuffer = self.argumentBufferReferences[argumentBuffer] {
            return vkArgumentBuffer
        }
        
        let layout = Unmanaged<VulkanDescriptorSetLayout>.fromOpaque(argumentBuffer.encoder!).takeUnretainedValue()
        let set = self.descriptorPools[self.descriptorPoolIndex].allocateSet(layout: layout.vkLayout)
        
        let vkArgumentBuffer = VulkanArgumentBuffer(device: self.persistentRegistry.device, layout: layout, descriptorSet: set)
        
        self.argumentBufferReferences[argumentBuffer] = vkArgumentBuffer

        return vkArgumentBuffer
    }
    
    @discardableResult
    func allocateArgumentBufferArrayIfNeeded(_ argumentBufferArray: ArgumentBufferArray) -> VulkanArgumentBuffer {
//        if let vkArgumentBuffer = self.argumentBufferArrayReferences[argumentBufferArray] {
//            return vkArgumentBuffer
//        }
//        
//        let layout = VkDescriptorSetLayout(argumentBufferArray._bindings.first(where: { $0?.encoder != nil })!!.encoder!)
       
        fatalError("Argument buffer arrays are currently unsupported on Vulkan.")
    }
    
    public func importExternalResource(_ resource: Resource, backingResource: Any) {
        self.prepareFrame()
        if let texture = Texture(resource) {
            self.textureReferences[texture] = VkImageReference(image: Unmanaged.passRetained(backingResource as! VulkanImage))
        } else if let buffer = Buffer(resource) {
            self.bufferReferences[buffer] = VkBufferReference(buffer: Unmanaged.passRetained(backingResource as! VulkanBuffer), offset: 0)
        }
    }
    
    public subscript(texture: Texture) -> VkImageReference? {
        return self.textureReferences[texture]
    }

    public subscript(buffer: Buffer) -> VkBufferReference? {
        return self.bufferReferences[buffer]
    }

    public subscript(argumentBuffer: ArgumentBuffer) -> VulkanArgumentBuffer? {
        return self.argumentBufferReferences[argumentBuffer]
    }

    public subscript(argumentBufferArray: ArgumentBufferArray) -> VulkanArgumentBuffer? {
        return self.argumentBufferArrayReferences[argumentBufferArray]
    }
    
    public func withHeapAliasingFencesIfPresent(for resourceHandle: Resource.Handle, perform: (inout [FenceDependency]) -> Void) {
        let resource = Resource(handle: resourceHandle)
        
        perform(&self.heapResourceUsageFences[resource, default: []])
    }
    
    func setDisposalFences(on resource: Resource, to events: [FenceDependency]) {
        assert(Self.isAliasedHeapResource(resource: Resource(resource)))
        self.heapResourceDisposalFences[Resource(resource)] = events
    }
    
    func disposeTexture(_ texture: Texture, waitEvent: ContextWaitEvent) {
        // We keep the reference around until the end of the frame since allocation/disposal is all processed ahead of time.
        
        let textureRef : VkImageReference?
        if texture._usesPersistentRegistry {
            precondition(texture.flags.contains(.historyBuffer))
            textureRef = self.persistentRegistry.textureReferences[texture]
            _ = textureRef?._image.retain() // since the persistent registry releases its resources unconditionally on dispose, but we want the allocator to have ownership of it.
        } else {
            textureRef = self.textureReferences[texture]
        }
        
        if let vkTexture = textureRef {
            if texture.flags.contains(.windowHandle) {
                return
            }
            if texture.isTextureView {
                vkTexture._image.release()
            }
            
            var events : [FenceDependency] = []
            if Self.isAliasedHeapResource(resource: Resource(texture)) {
                events = self.heapResourceDisposalFences[Resource(texture)] ?? []
            }
            
            let allocator = self.allocatorForImage(storageMode: texture.descriptor.storageMode, cacheMode: texture.descriptor.cacheMode, flags: texture.flags)
            allocator.depositImage(vkTexture, events: events, waitSemaphore: waitEvent)
        }
    }
    
    func disposeBuffer(_ buffer: Buffer, waitEvent: ContextWaitEvent) {
        // We keep the reference around until the end of the frame since allocation/disposal is all processed ahead of time.
        
        let bufferRef : VkBufferReference?
        if buffer._usesPersistentRegistry {
            precondition(buffer.flags.contains(.historyBuffer))
            bufferRef = self.persistentRegistry.bufferReferences[buffer]
            _ = bufferRef?._buffer.retain() // since the persistent registry releases its resources unconditionally on dispose, but we want the allocator to have ownership of it.
        } else {
            bufferRef = self.bufferReferences[buffer]
        }
        
        if let vkBuffer = bufferRef {
            var events : [FenceDependency] = []
            if Self.isAliasedHeapResource(resource: Resource(buffer)) {
                events = self.heapResourceDisposalFences[Resource(buffer)] ?? []
            }
            
            let allocator = self.allocatorForBuffer(storageMode: buffer.descriptor.storageMode, cacheMode: buffer.descriptor.cacheMode, flags: buffer.flags)
            allocator.depositBuffer(vkBuffer, events: events, waitSemaphore: waitEvent)
        }
    }
    
    func disposeArgumentBuffer(_ buffer: ArgumentBuffer, waitEvent: ContextWaitEvent) {
        // No-op; this should be managed by resetting the descriptor set pool.
        // FIXME: should we manage individual descriptor sets instead?
    }
    
    func disposeArgumentBufferArray(_ buffer: ArgumentBufferArray, waitEvent: ContextWaitEvent) {
        // No-op; this should be managed by resetting the descriptor set pool.
        // FIXME: should we manage individual descriptor sets instead?
    }
    
    func registerInitialisedHistoryBufferForDisposal(resource: Resource) {
        assert(resource.flags.contains(.historyBuffer) && resource.stateFlags.contains(.initialised))
        resource.dispose() // This will dispose it in the RenderGraph persistent allocator, which will in turn call dispose here at the end of the frame.
    }
    
    func clearSwapChains() {
        self.frameSwapChains.removeAll(keepingCapacity: true)
    }
    
    func cycleFrames() {
        // Clear all transient resources at the end of the frame.
        self.bufferReferences.removeAll()
        self.argumentBufferReferences.removeAll()
        self.argumentBufferArrayReferences.removeAll()
        
        self.heapResourceUsageFences.removeAll(keepingCapacity: true)
        self.heapResourceDisposalFences.removeAll(keepingCapacity: true)
        
        self.frameSharedBufferAllocator.cycleFrames()
        self.frameSharedWriteCombinedBufferAllocator.cycleFrames()
               
        self.frameManagedBufferAllocator.cycleFrames()
        self.frameManagedWriteCombinedBufferAllocator.cycleFrames()
        
        self.stagingTextureAllocator.cycleFrames()
        self.historyBufferAllocator.cycleFrames()
        self.privateAllocator.cycleFrames()
        
        self.descriptorPoolIndex = (self.descriptorPoolIndex &+ 1) % self.inflightFrameCount
        self.frameIndex += 1
    }
}

#endif // canImport(Vulkan)
