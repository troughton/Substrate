//
//  ResourceRegistery.swift
//  SwiftFrameGraphPackageDescription
//
//  Created by Joseph Bennett on 1/01/18.
//

#if canImport(Vulkan)
import Vulkan
import FrameGraphUtilities
import FrameGraphCExtras
import Dispatch

/// The value to wait for on the semaphore associated with this FrameGraph context.
struct VulkanContextWaitSemaphore {
    var waitValue : UInt64 = 0
}

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

struct VulkanFrameResourceMap {
    let persistentRegistry : VulkanPersistentResourceRegistry
    let transientRegistry : VulkanTransientResourceRegistry
    
    subscript(buffer: Buffer) -> VkBufferReference {
        if buffer._usesPersistentRegistry {
            return persistentRegistry[buffer]!
        } else {
            return transientRegistry[buffer]!
        }
    }
    
    subscript(texture: Texture) -> VulkanImage {
        if texture._usesPersistentRegistry {
            return persistentRegistry[texture]!
        } else {
            return transientRegistry[texture]!
        }
    }
    
    subscript(buffer: _ArgumentBuffer) -> VulkanArgumentBuffer {
        if buffer._usesPersistentRegistry {
            return persistentRegistry[buffer]!
        } else {
            return transientRegistry[buffer]!
        }
    }
    
    subscript(buffer: _ArgumentBufferArray) -> VulkanArgumentBuffer {
        if buffer._usesPersistentRegistry {
            return persistentRegistry[buffer]!
        } else {
            return transientRegistry[buffer]!
        }
    }
    
    func bufferForCPUAccess(_ buffer: Buffer) -> VkBufferReference {
        if buffer._usesPersistentRegistry {
            return persistentRegistry[buffer]!
        } else {
            return transientRegistry.accessLock.withLock { transientRegistry.allocateBufferIfNeeded(buffer, usage: VkBufferUsageFlagBits(buffer.descriptor.usageHint)) }
        }
    }
    
    func textureForCPUAccess(_ texture: Texture) -> VulkanImage {
        if texture._usesPersistentRegistry {
            return persistentRegistry[texture]!
        } else {
            return transientRegistry.accessLock.withLock { transientRegistry.allocateTextureIfNeeded(texture, usage: VkImageUsageFlagBits(texture.descriptor.usageHint, pixelFormat: texture.descriptor.pixelFormat), initialLayout: VK_IMAGE_LAYOUT_PREINITIALIZED)! }
        }
    }
    
    func renderTargetTexture(_ texture: Texture) throws -> VulkanImage {
        if texture.flags.contains(.windowHandle) {
            return try self.transientRegistry.allocateWindowHandleTexture(texture, usage: VkImageUsageFlagBits(texture.descriptor.usageHint, pixelFormat: texture.descriptor.pixelFormat), persistentRegistry: persistentRegistry)
        }
        return self[texture]
    }
}

final class VulkanPersistentResourceRegistry {
    var accessLock = ReaderWriterLock()
    
    let device : VulkanDevice
    let vmaAllocator : VmaAllocator
    
    var heapReferences = PersistentResourceMap<Heap, VulkanHeap>()
    var textureReferences = PersistentResourceMap<Texture, VkImageReference>()
    var bufferReferences = PersistentResourceMap<Buffer, VkBufferReference>()
    var argumentBufferReferences = PersistentResourceMap<_ArgumentBuffer, VulkanArgumentBuffer>()
    var argumentBufferArrayReferences = PersistentResourceMap<_ArgumentBufferArray, VulkanArgumentBuffer>()
    
    var windowReferences = [Texture : VulkanSwapChain]()
    
    public init(device: VulkanDevice) {
        self.device = device
        
        var allocatorInfo = VmaAllocatorCreateInfo()
        allocatorInfo.device = device.vkDevice
        allocatorInfo.physicalDevice = device.physicalDevice.vkDevice

        var allocator : VmaAllocator? = nil
        vmaCreateAllocator(&allocatorInfo, &allocator)
        self.vmaAllocator = allocator!
        
        self.prepareFrame()
        VulkanEventRegistry.instance.device = self.device.vkDevice
    }
    
    deinit {
        self.textureReferences.deinit()
        self.bufferReferences.deinit()
        self.argumentBufferReferences.deinit()
        self.argumentBufferArrayReferences.deinit()
    }
    
    public func prepareFrame() {
        VulkanEventRegistry.instance.clearCompletedEvents()
    }
    
    public func registerWindowTexture(texture: Texture, context: Any) {
        self.windowReferences[texture] = (context as! VulkanSwapChain)
    }
    
    @discardableResult
    public func allocateTexture(_ texture: Texture, usage: VkImageUsageFlagBits, sharingMode: VulkanSharingMode, initialLayout: VkImageLayout) -> VulkanImage? {
        precondition(texture._usesPersistentRegistry)
        
        if texture.flags.contains(.windowHandle) {
            // Reserve a slot in texture references so we can later insert the texture reference in a thread-safe way, but don't actually allocate anything yet
            self.textureReferences[texture] = VkImageReference(windowTexture: ())
            return nil
        }
        
        // NOTE: all synchronisation is managed through the per-queue waitIndices associated with the resource.
        
        let descriptor = VulkanImageDescriptor(texture.descriptor, usage: usage, sharingMode: sharingMode, initialLayout: initialLayout)
        

        var allocInfo = VmaAllocationCreateInfo()
        allocInfo.usage = VmaMemoryUsage(storageMode: texture.descriptor.storageMode, cacheMode: texture.descriptor.cacheMode)
        var image : VkImage? = nil
        var allocation : VmaAllocation? = nil
        descriptor.withImageCreateInfo(device: self.device) { (info) in
            var info = info
            vmaCreateImage(self.vmaAllocator, &info, &allocInfo, &image, &allocation, nil)
        }
        
        let vkImage = VulkanImage(device: self.device, image: image!, allocator: self.vmaAllocator, allocation: allocation!, descriptor: descriptor)
        
        if let label = texture.label {
            vkImage.label = label
        }
        
        assert(self.textureReferences[texture] == nil)
        self.textureReferences[texture] = VkImageReference(image: Unmanaged.passRetained(vkImage))
        
        return vkImage
    }
    
    @discardableResult
    public func allocateBuffer(_ buffer: Buffer, usage: VkBufferUsageFlagBits, sharingMode: VulkanSharingMode) -> VkBufferReference {
        precondition(buffer._usesPersistentRegistry)
        
        // NOTE: all synchronisation is managed through the per-queue waitIndices associated with the resource.
        let descriptor = VulkanBufferDescriptor(buffer.descriptor, usage: usage, sharingMode: sharingMode)
        
        var allocInfo = VmaAllocationCreateInfo()
        allocInfo.usage = VmaMemoryUsage(storageMode: buffer.descriptor.storageMode, cacheMode: buffer.descriptor.cacheMode)
        var vkBuffer : VkBuffer? = nil
        var allocation : VmaAllocation? = nil
        var allocationInfo = VmaAllocationInfo()
        descriptor.withBufferCreateInfo(device: self.device) { (info) in
            var info = info
            vmaCreateBuffer(self.vmaAllocator, &info, &allocInfo, &vkBuffer, &allocation, &allocationInfo)
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
    func allocateArgumentBufferIfNeeded(_ argumentBuffer: _ArgumentBuffer, bindingPath: ResourceBindingPath, commandBufferResources: CommandBufferResources, pipelineReflection: VulkanPipelineReflection, stateCaches: VulkanStateCaches) -> VulkanArgumentBuffer {
        if let baseArray = argumentBuffer.sourceArray {
            _ = self.allocateArgumentBufferArrayIfNeeded(baseArray)
            return self.argumentBufferReferences[argumentBuffer]!
        }
        if let vkArgumentBuffer = self.argumentBufferReferences[argumentBuffer] {
            return vkArgumentBuffer
        }
        
        let buffer = VulkanArgumentBuffer(arguments: argumentBuffer,
                                          bindingPath: bindingPath,
                                          commandBufferResources: commandBufferResources,
                                          pipelineReflection: pipelineReflection,
                                          stateCaches: stateCaches)

        self.argumentBufferReferences[argumentBuffer] = buffer
        
        return buffer
    }
    
    @discardableResult
    func allocateArgumentBufferArrayIfNeeded(_ argumentBufferArray: _ArgumentBufferArray) -> VulkanArgumentBuffer {
        if let vkArgumentBuffer = self.argumentBufferArrayReferences[argumentBufferArray] {
            return vkArgumentBuffer
        }
        
        fatalError("Unimplemented")
    }
    
    public func importExternalResource(_ resource: Resource, backingResource: Any) {
        self.prepareFrame()
        if let texture = resource.texture {
            self.textureReferences[texture] = VkImageReference(image: Unmanaged.passRetained(backingResource as! VulkanImage))
        } else if let buffer = resource.buffer {
            self.bufferReferences[buffer] = VkBufferReference(buffer: Unmanaged.passRetained(backingResource as! VulkanBuffer), offset: 0)
        }
    }
    
    public subscript(texture: Texture) -> VulkanImage? {
        return self.textureReferences[texture]?.image
    }

    public subscript(texture texture: Texture.Handle) -> VulkanImage? {
        return self.textureReferences[Texture(handle: texture)]!.image
    }

    public subscript(textureReference texture: Texture) -> VkImageReference? {
        return self.textureReferences[texture]!
    }

    public subscript(textureReference texture: Texture.Handle) -> VkImageReference? {
        return self.textureReferences[Texture(handle: texture)]!
    }

    public subscript(buffer: Buffer) -> VkBufferReference? {
        return self.bufferReferences[buffer]
    }

    public subscript(buffer buffer: Buffer.Handle) -> VkBufferReference? {
        return self.bufferReferences[Buffer(handle: buffer)]
    }

    public subscript(argumentBuffer: _ArgumentBuffer) -> VulkanArgumentBuffer? {
        return self.argumentBufferReferences[argumentBuffer]
    }

    public subscript(argumentBufferArray: _ArgumentBufferArray) -> VulkanArgumentBuffer? {
        return self.argumentBufferArrayReferences[argumentBufferArray]
    }

    func disposeHeap(_ heap: Heap) {
        self.heapReferences.removeValue(forKey: heap)
    }
    
    func disposeTexture(_ texture: Texture) {
        if let vkTexture = self.textureReferences.removeValue(forKey: texture) {
            if texture.flags.contains(.windowHandle) {
                return
            }
            
            vkTexture._image.release()
        }
    }
    
    func disposeBuffer(_ buffer: Buffer) {
        if let vkBuffer = self.bufferReferences.removeValue(forKey: buffer) {
            vkBuffer._buffer.release()
        }
    }
    
    func disposeArgumentBuffer(_ buffer: _ArgumentBuffer) {
        if let vkBuffer = self.argumentBufferReferences.removeValue(forKey: buffer) {
            assert(buffer.sourceArray == nil, "Persistent argument buffers from an argument buffer array should not be disposed individually; this needs to be fixed within the Vulkan FrameGraph backend.")
            _ = vkBuffer
        }
    }
    
    func disposeArgumentBufferArray(_ buffer: _ArgumentBufferArray) {
        if let vkBuffer = self.argumentBufferArrayReferences.removeValue(forKey: buffer) {
            _ = vkBuffer
        }
    }
}


final class VulkanTransientResourceRegistry {
    let persistentRegistry : VulkanPersistentResourceRegistry
    var accessLock = SpinLock()
    
    private var textureReferences : TransientResourceMap<Texture, VkImageReference>
    private var bufferReferences : TransientResourceMap<Buffer, VkBufferReference>
    private var argumentBufferReferences : TransientResourceMap<_ArgumentBuffer, VulkanArgumentBuffer>
    private var argumentBufferArrayReferences : TransientResourceMap<_ArgumentBufferArray, VulkanArgumentBuffer>
    
    var textureWaitSemaphores : TransientResourceMap<Texture, VulkanContextWaitSemaphore>
    var bufferWaitSemaphores : TransientResourceMap<Buffer, VulkanContextWaitSemaphore>
    var argumentBufferWaitSemaphores : TransientResourceMap<_ArgumentBuffer, VulkanContextWaitSemaphore>
    var argumentBufferArrayWaitSemaphores : TransientResourceMap<_ArgumentBufferArray, VulkanContextWaitSemaphore>
    var historyBufferResourceWaitSemaphores = [Resource : VulkanContextWaitSemaphore]() // since history buffers use the persistent (rather than transient) resource maps.
    
    private var heapResourceUsageEvents = [Resource : [VulkanEventHandle]]()
    private var heapResourceDisposalEvents = [Resource : [VulkanEventHandle]]()
    
    private let uploadResourceAllocator : VulkanPoolResourceAllocator
    private let privateResourceAllocator : VulkanPoolResourceAllocator
    private let temporaryBufferAllocator : VulkanTemporaryBufferAllocator
    
    public private(set) var frameSwapChains : [VulkanSwapChain] = []
    
    public init(device: VulkanDevice, inflightFrameCount: Int, transientRegistryIndex: Int, persistentRegistry: VulkanPersistentResourceRegistry) {
        self.persistentRegistry = persistentRegistry
        
        self.textureReferences = .init(transientRegistryIndex: transientRegistryIndex)
        self.bufferReferences = .init(transientRegistryIndex: transientRegistryIndex)
        self.argumentBufferReferences = .init(transientRegistryIndex: transientRegistryIndex)
        self.argumentBufferArrayReferences = .init(transientRegistryIndex: transientRegistryIndex)
        
        self.textureWaitSemaphores = .init(transientRegistryIndex: transientRegistryIndex)
        self.bufferWaitSemaphores = .init(transientRegistryIndex: transientRegistryIndex)
        self.argumentBufferWaitSemaphores = .init(transientRegistryIndex: transientRegistryIndex)
        self.argumentBufferArrayWaitSemaphores = .init(transientRegistryIndex: transientRegistryIndex)
        
        self.uploadResourceAllocator = VulkanPoolResourceAllocator(device: device, allocator: persistentRegistry.vmaAllocator, memoryUsage: VMA_MEMORY_USAGE_CPU_TO_GPU, numFrames: inflightFrameCount)
        self.privateResourceAllocator = VulkanPoolResourceAllocator(device: device, allocator: persistentRegistry.vmaAllocator, memoryUsage: VMA_MEMORY_USAGE_GPU_ONLY, numFrames: 1)
        self.temporaryBufferAllocator = VulkanTemporaryBufferAllocator(numFrames: inflightFrameCount, allocator: persistentRegistry.vmaAllocator, device: device)
        
        self.prepareFrame()
    }
    
    deinit {
        self.textureReferences.deinit()
        self.bufferReferences.deinit()
        self.argumentBufferReferences.deinit()
        self.argumentBufferArrayReferences.deinit()
        
        self.textureWaitSemaphores.deinit()
        self.bufferWaitSemaphores.deinit()
    }
    
    public func prepareFrame() {
        VulkanEventRegistry.instance.clearCompletedEvents()

        self.textureReferences.prepareFrame()
        self.bufferReferences.prepareFrame()
        self.argumentBufferReferences.prepareFrame()
        self.argumentBufferArrayReferences.prepareFrame()
        
        self.textureWaitSemaphores.prepareFrame()
        self.bufferWaitSemaphores.prepareFrame()
    }

    func allocatorForBuffer(storageMode: StorageMode, flags: ResourceFlags) -> VulkanBufferAllocator {
        switch storageMode {
        case .managed, .shared:
            return self.uploadResourceAllocator
        case .private:
            return self.privateResourceAllocator
        }
    }
    
    func allocatorForImage(storageMode: StorageMode, flags: ResourceFlags) -> VulkanImageAllocator {
        switch storageMode {
        case .managed, .shared:
            return self.uploadResourceAllocator
        case .private:
            return self.privateResourceAllocator
        }
    }
    
    func isAliasedHeapResource(resource: Resource) -> Bool {
        return false
    }
    
    @discardableResult
    public func allocateTexture(_ texture: Texture, usage: VkImageUsageFlagBits, initialLayout: VkImageLayout) -> VulkanImage? {
        let descriptor = texture.descriptor
        let flags = texture.flags
        
        let vkImage : VkImageReference
        let events : [VulkanEventHandle]
        let waitSemaphore : VulkanContextWaitSemaphore
        if texture.flags.contains(.windowHandle) {
            self.textureReferences[texture] = VkImageReference(windowTexture: ())
            return nil
        } else {
            let allocator = self.allocatorForImage(storageMode: descriptor.storageMode, flags: flags)
            (vkImage, events, waitSemaphore) = allocator.collectImage(descriptor: VulkanImageDescriptor(descriptor, usage: usage, sharingMode: .exclusive, initialLayout: initialLayout))
        }
        
        if let label = texture.label {
            vkImage.image.label = label
        }
        
        if texture._usesPersistentRegistry {
            precondition(texture.flags.contains(.historyBuffer))
            self.persistentRegistry.textureReferences[texture] = vkImage
            self.historyBufferResourceWaitSemaphores[Resource(texture)] = waitSemaphore
        } else {
            precondition(self.textureReferences[texture] == nil)
            self.textureReferences[texture] = vkImage
            self.textureWaitSemaphores[texture] = waitSemaphore
        }
        
        if !events.isEmpty {
            self.heapResourceUsageEvents[Resource(texture)] = events
        }
        
        return vkImage.image
    }
    
    @discardableResult
    public func allocateTextureView(_ texture: Texture, usage: VkImageUsageFlagBits) -> VulkanImage? {
        fatalError("Unimplemented")
    }
    
    @discardableResult
    public func allocateWindowHandleTexture(_ texture: Texture, usage: VkImageUsageFlagBits, persistentRegistry: VulkanPersistentResourceRegistry) throws -> VulkanImage {
        precondition(texture.flags.contains(.windowHandle))
        
        let (image, semaphore) = self.persistentRegistry.windowReferences[texture]!.nextImage(descriptor: texture.descriptor)
        fatalError()
    }
    
    @discardableResult
    public func allocateBuffer(_ buffer: Buffer, usage: VkBufferUsageFlagBits) -> VkBufferReference {
        let allocator = self.allocatorForBuffer(storageMode: buffer.descriptor.storageMode, flags: buffer.flags)
        let (vkBuffer, events, waitSemaphore) = allocator.collectBuffer(descriptor: VulkanBufferDescriptor(buffer.descriptor, usage: usage, sharingMode: .exclusive))
        
        if let label = buffer.label {
            vkBuffer.buffer.label = label
        }
        
        if buffer._usesPersistentRegistry {
            precondition(buffer.flags.contains(.historyBuffer))
            self.persistentRegistry.bufferReferences[buffer] = vkBuffer
            self.historyBufferResourceWaitSemaphores[Resource(buffer)] = waitSemaphore
        } else {
            precondition(self.bufferReferences[buffer] == nil)
            self.bufferReferences[buffer] = vkBuffer
            self.bufferWaitSemaphores[buffer] = waitSemaphore
        }
        
        if !events.isEmpty {
            self.heapResourceUsageEvents[Resource(buffer)] = events
        }
        
        return vkBuffer
    }
    
    @discardableResult
    public func allocateBufferIfNeeded(_ buffer: Buffer, usage: VkBufferUsageFlagBits) -> VkBufferReference {
        if let vkBuffer = self.bufferReferences[buffer] {
            return vkBuffer
        }
        return self.allocateBuffer(buffer, usage: usage)
    }
    
    @discardableResult
    public func allocateTextureIfNeeded(_ texture: Texture, usage: VkImageUsageFlagBits, initialLayout: VkImageLayout) -> VulkanImage? {
        if let vkTexture = self.textureReferences[texture]?.image {
            return vkTexture
        }
        return self.allocateTexture(texture, usage: usage, initialLayout: initialLayout)
    }
    
    @discardableResult
    func allocateArgumentBufferIfNeeded(_ argumentBuffer: _ArgumentBuffer, bindingPath: ResourceBindingPath, commandBufferResources: CommandBufferResources, pipelineReflection: VulkanPipelineReflection, stateCaches: VulkanStateCaches) -> VulkanArgumentBuffer {
        if let baseArray = argumentBuffer.sourceArray {
            _ = self.allocateArgumentBufferArrayIfNeeded(baseArray)
            return self.argumentBufferReferences[argumentBuffer]!
        }
        if let vkArgumentBuffer = self.argumentBufferReferences[argumentBuffer] {
            return vkArgumentBuffer
        }
        
        let layout = VkDescriptorSetLayout(argumentBuffer.encoder!)
        let argumentBuffer = VulkanArgumentBuffer(arguments: argumentBuffer, bindingPath: bindingPath, commandBufferResources: commandBufferResources, pipelineReflection: pipelineReflection, stateCaches: stateCaches)
        
        return argumentBuffer
    }
    
    @discardableResult
    func allocateArgumentBufferArrayIfNeeded(_ argumentBufferArray: _ArgumentBufferArray) -> VulkanArgumentBuffer {
        if let vkArgumentBuffer = self.argumentBufferArrayReferences[argumentBufferArray] {
            return vkArgumentBuffer
        }
        
        let layout = VkDescriptorSetLayout(argumentBufferArray._bindings.first(where: { $0?.encoder != nil })!!.encoder!)
       
        fatalError("Argument buffer arrays are currently unsupported on Vulkan.")
    }
    
    public func importExternalResource(_ resource: Resource, backingResource: Any) {
        self.prepareFrame()
        if let texture = resource.texture {
            self.textureReferences[texture] = VkImageReference(image: Unmanaged.passRetained(backingResource as! VulkanImage))
        } else if let buffer = resource.buffer {
            self.bufferReferences[buffer] = VkBufferReference(buffer: Unmanaged.passRetained(backingResource as! VulkanBuffer), offset: 0)
        }
    }
    
    public subscript(texture: Texture) -> VulkanImage? {
        return self.textureReferences[texture]?.image
    }

    public subscript(texture texture: Texture.Handle) -> VulkanImage? {
        return self.textureReferences[Texture(handle: texture)]!.image
    }

    public subscript(textureReference texture: Texture) -> VkImageReference? {
        return self.textureReferences[texture]!
    }

    public subscript(textureReference texture: Texture.Handle) -> VkImageReference? {
        return self.textureReferences[Texture(handle: texture)]!
    }

    public subscript(buffer: Buffer) -> VkBufferReference? {
        return self.bufferReferences[buffer]
    }

    public subscript(buffer buffer: Buffer.Handle) -> VkBufferReference? {
        return self.bufferReferences[Buffer(handle: buffer)]
    }

    public subscript(argumentBuffer: _ArgumentBuffer) -> VulkanArgumentBuffer? {
        return self.argumentBufferReferences[argumentBuffer]
    }

    public subscript(argumentBufferArray: _ArgumentBufferArray) -> VulkanArgumentBuffer? {
        return self.argumentBufferArrayReferences[argumentBufferArray]
    }
    
    public func withHeapAliasingFencesIfPresent(for resourceHandle: Resource.Handle, perform: (inout [VulkanEventHandle]) -> Void) {
        let resource = Resource(handle: resourceHandle)
        
        perform(&self.heapResourceUsageEvents[resource, default: []])
    }
    
    func setDisposalFences<R : ResourceProtocol>(on resource: R, to events: [VulkanEventHandle]) {
        assert(self.isAliasedHeapResource(resource: Resource(resource)))
        self.heapResourceDisposalEvents[Resource(resource)] = events
    }
    
    func disposeTexture(_ texture: Texture, waitSemaphore: VulkanContextWaitSemaphore) {
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
            
            var events : [VulkanEventHandle] = []
            if self.isAliasedHeapResource(resource: Resource(texture)) {
                events = self.heapResourceDisposalEvents[Resource(texture)] ?? []
            }
            
            let allocator = self.allocatorForImage(storageMode: texture.storageMode, flags: texture.flags)
            allocator.depositImage(vkTexture, events: events, waitSemaphore: waitSemaphore)
        }
    }
    
    func disposeBuffer(_ buffer: Buffer, waitSemaphore: VulkanContextWaitSemaphore) {
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
            var events : [VulkanEventHandle] = []
            if self.isAliasedHeapResource(resource: Resource(buffer)) {
                events = self.heapResourceDisposalEvents[Resource(buffer)] ?? []
            }
            
            let allocator = self.allocatorForBuffer(storageMode: buffer.descriptor.storageMode, flags: buffer.flags)
            allocator.depositBuffer(vkBuffer, events: events, waitSemaphore: waitSemaphore)
        }
    }
    
    func disposeArgumentBuffer(_ buffer: _ArgumentBuffer, waitSemaphore: VulkanContextWaitSemaphore) {
        // No-op; this should be managed by resetting the descriptor set pool.
        // FIXME: should we manage individual descriptor sets instead?
    }
    
    func disposeArgumentBufferArray(_ buffer: _ArgumentBufferArray, waitSemaphore: VulkanContextWaitSemaphore) {
        // No-op; this should be managed by resetting the descriptor set pool.
        // FIXME: should we manage individual descriptor sets instead?
    }
    
    func registerInitialisedHistoryBufferForDisposal(resource: Resource) {
        assert(resource.flags.contains(.historyBuffer) && resource.stateFlags.contains(.initialised))
        resource.dispose() // This will dispose it in the FrameGraph persistent allocator, which will in turn call dispose here at the end of the frame.
    }
    
    func clearSwapChains() {
        self.frameSwapChains.removeAll(keepingCapacity: true)
    }
    
    func cycleFrames() {
        // Clear all transient resources at the end of the frame.
        
        self.textureReferences.removeAll()
        self.bufferReferences.removeAll()
        self.argumentBufferReferences.removeAll()
        self.argumentBufferArrayReferences.removeAll()
        
        self.heapResourceUsageEvents.removeAll(keepingCapacity: true)
        self.heapResourceDisposalEvents.removeAll(keepingCapacity: true)
        
        self.uploadResourceAllocator.cycleFrames()
        self.privateResourceAllocator.cycleFrames()
        self.temporaryBufferAllocator.cycleFrames()
    }
}

//
//public final class ResourceRegistry {
//
//    let accessQueue = DispatchQueue(label: "Resource Registry Access")
//
//    let commandPool : VulkanCommandPool
//    
//    var cpuDataCache = MemoryArena()
//    private var frameCPUBufferContents = [Buffer : UnsafeMutableRawPointer]()
//    
//    private(set) var windowReferences = [Texture : VulkanSwapChain]()
//    private var argumentBufferReferences = [Resource.Handle : VulkanArgumentBuffer]()
//
//    private var textureReferences = [Texture : VulkanImage]()
//    private var bufferReferences = [Buffer : VulkanBuffer]()
//    
//    private let device : VulkanDevice
//    private let vmaAllocator : VmaAllocator
//    
//    private var frameArgumentBuffers = [Resource.Handle]()
//    
//    private let uploadResourceAllocator : PoolResourceAllocator
//    private let privateResourceAllocator : PoolResourceAllocator
//    
//    let temporaryBufferAllocator : TemporaryBufferAllocator
//
//    public var frameGraphHasResourceAccess = false
//    
//    public init(device: VulkanDevice, inflightFrameCount: Int) {
//        self.device = device
//        self.commandPool = VulkanCommandPool(device: device, inflightFrameCount: inflightFrameCount)
//        
//        var allocatorInfo = VmaAllocatorCreateInfo()
//        allocatorInfo.device = device.vkDevice
//        allocatorInfo.physicalDevice = device.physicalDevice.vkDevice
//        
//        var allocator : VmaAllocator? = nil
//        vmaCreateAllocator(&allocatorInfo, &allocator)
//        self.vmaAllocator = allocator!
//        
//        self.uploadResourceAllocator = PoolResourceAllocator(device: device, allocator: self.vmaAllocator, memoryUsage: VMA_MEMORY_USAGE_CPU_TO_GPU, numFrames: inflightFrameCount)
//        self.privateResourceAllocator = PoolResourceAllocator(device: device, allocator: self.vmaAllocator, memoryUsage: VMA_MEMORY_USAGE_GPU_ONLY, numFrames: 1)
//        self.temporaryBufferAllocator = TemporaryBufferAllocator(numFrames: inflightFrameCount, allocator: self.vmaAllocator, device: device)
//    }
//    
//    deinit {
//        vmaDestroyAllocator(self.vmaAllocator)
//    }
//    
//    public func registerWindowTexture(texture: Texture, context: Any) {
//        self.windowReferences[texture] = (context as! VulkanSwapChain)
//    }
//    
//    func allocatorForResource(storageMode: StorageMode, flags: ResourceFlags) -> ResourceAllocator {
//        switch storageMode {
//        case .managed, .shared:
//            return self.uploadResourceAllocator
//        case .private:
//            return self.privateResourceAllocator
//        }
//    }
//    
//    @discardableResult
//    func allocateTexture(_ texture: Texture, descriptor: TextureDescriptor, flags: ResourceFlags, usage: VkImageUsageFlagBits, sharingMode: VulkanSharingMode, initialLayout: VkImageLayout) -> VulkanImage {
//        let vkImage : VulkanImage
//
//        if flags.contains(.windowHandle) {
//            vkImage = self.windowReferences[texture]!.nextImage(descriptor: descriptor)
//        } else {
//            let allocator = self.allocatorForResource(storageMode: descriptor.storageMode, flags: flags)
//            vkImage = allocator.collectImage(descriptor: VulkanImageDescriptor(descriptor, usage: usage, sharingMode: sharingMode, initialLayout: initialLayout))
//        }
//        
//        assert(self.textureReferences[texture] == nil)
//        self.textureReferences[texture] = vkImage
//        return vkImage
//    }
//    
//    @discardableResult
//    func allocateBuffer(_ buffer: Buffer, usage: VkBufferUsageFlagBits, sharingMode: VulkanSharingMode) -> VulkanBuffer {
//        let allocator = self.allocatorForResource(storageMode: buffer.descriptor.storageMode, flags: buffer.flags)
//        let vkBuffer = allocator.collectBuffer(descriptor: VulkanBufferDescriptor(buffer.descriptor, usage: usage, sharingMode: sharingMode))
//
//        assert(self.bufferReferences[buffer] == nil)
//        self.bufferReferences[buffer] = vkBuffer
//
//        return vkBuffer
//    }
//    
//    @discardableResult
//    func allocateBufferIfNeeded(_ buffer: Buffer, usage: VkBufferUsageFlagBits, sharingMode: VulkanSharingMode) -> VulkanBuffer {
//        if let vkBuffer = self.bufferReferences[buffer] {
//            assert(vkBuffer.descriptor.size >= buffer.descriptor.length)
//            return vkBuffer
//        }
//        return self.allocateBuffer(buffer, usage: usage, sharingMode: sharingMode)
//    }
//    
//    @discardableResult
//    func allocateTextureIfNeeded(_ texture: Texture, usage: VkImageUsageFlagBits, sharingMode: VulkanSharingMode, initialLayout: VkImageLayout) -> VulkanImage {
//        if let vkTexture = self.textureReferences[texture] {
//            return vkTexture
//        }
//        return self.allocateTexture(texture, descriptor: texture.descriptor, flags: texture.flags, usage: usage, sharingMode: sharingMode, initialLayout: initialLayout)
//    }
//
//    func allocateArgumentBufferIfNeeded(_ argumentBuffer: _ArgumentBuffer, bindingPath: ResourceBindingPath, commandBufferResources: CommandBufferResources, pipelineReflection: VulkanPipelineReflection, stateCaches: StateCaches) -> VulkanArgumentBuffer {
//        if let vulkanArgumentBuffer = self.argumentBufferReferences[argumentBuffer] {
//            return vulkanArgumentBuffer
//        }
//        
//        let buffer = VulkanArgumentBuffer(arguments: argumentBuffer, 
//                                          bindingPath: bindingPath, 
//                                          commandBufferResources: commandBufferResources,
//                                          pipelineReflection: pipelineReflection, 
//                                          resourceRegistry: self, 
//                                          stateCaches: stateCaches)
//
//        self.argumentBufferReferences[argumentBuffer] = buffer
//        if !argumentBuffer.flags.contains(.persistent) {
//            self.frameArgumentBuffers.append(argumentBuffer)
//        }
//        
//        return buffer
//    }
//    
//    // These subscript methods should only be called after 'allocate' has been called.
//    // If you hit an error here, check if you forgot to make a resource persistent.
//    subscript(texture: Texture) -> VulkanImage? {
//        return self.textureReferences[texture]
//    }
//    
//    subscript(texture handle: Texture.Handle) -> VulkanImage? {
//        let texture = Texture(existingHandle: handle)
//        if self.textureReferences[texture] == nil {
//            fatalError("Texture \(texture) is not in registry.")
//        }
//        return self.textureReferences[texture]!
//    }
//    
//    subscript(buffer: Buffer) -> VulkanBuffer? {
//        return self.bufferReferences[buffer]
//    }
//    
//    subscript(buffer buffer: Buffer.Handle) -> VulkanBuffer? {
//        return self.bufferReferences[Buffer(existingHandle: buffer)]
//    }
//    
//    public func disposeTexture(_ texture: Texture) {
//        if let vkTexture = self.textureReferences.removeValue(forKey: texture), !texture.flags.contains(.windowHandle) {
//            // assert(vkTexture.waitSemaphore == nil, "Texture \(texture.handle) with flags \(texture.flags), pixelFormat \(texture.descriptor.pixelFormat) is being disposed with an active waitSemaphore.")
//            let allocator = self.allocatorForResource(storageMode: texture.descriptor.storageMode, flags: texture.flags)
//            allocator.depositImage(vkTexture)
//        }
//    }
//    
//    public func disposeBuffer(_ buffer: Buffer) {
//        if let vkBuffer = self.bufferReferences.removeValue(forKey: buffer) {
//            assert(vkBuffer.waitSemaphore == nil)
//            let allocator = self.allocatorForResource(storageMode: buffer.descriptor.storageMode, flags: buffer.flags)
//            allocator.depositBuffer(vkBuffer)
//        }
//    }
//
//    public func disposeArgumentBuffer(_ buffer: _ArgumentBuffer) {
//        // Only called if the buffer isn't persistent.
//        self.argumentBufferReferences.removeValue(forKey: buffer)
//    }
//
//    public func disposeArgumentBufferArray(_ buffer: _ArgumentBufferArray) {
//        // Only called if the buffer isn't persistent.
//        self.argumentBufferReferences.removeValue(forKey: buffer)
//    }
//
//    
//    public func cycleFrames() {
//        self.commandPool.cycleFrames()
//        
//        self.cpuDataCache.reset()
//        self.frameCPUBufferContents.removeAll(keepingCapacity: true)
//
//        while let argBuffer = self.frameArgumentBuffers.popLast() {
//            self.argumentBufferReferences.removeValue(forKey: argBuffer)
//        }
//        
//        self.uploadResourceAllocator.cycleFrames()
//        self.privateResourceAllocator.cycleFrames()
//        self.temporaryBufferAllocator.cycleFrames()
//        self.windowReferences.removeAll(keepingCapacity: true)
//    }
//}

#endif // canImport(Vulkan)
