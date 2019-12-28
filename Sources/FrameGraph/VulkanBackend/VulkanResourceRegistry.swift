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

public final class ResourceRegistry {

    let accessQueue = DispatchQueue(label: "Resource Registry Access")

    let commandPool : VulkanCommandPool
    
    var cpuDataCache = MemoryArena()
    private var frameCPUBufferContents = [Buffer : UnsafeMutableRawPointer]()
    
    private(set) var windowReferences = [Texture : VulkanSwapChain]()
    private var argumentBufferReferences = [Resource.Handle : VulkanArgumentBuffer]()

    private var textureReferences = [Texture : VulkanImage]()
    private var bufferReferences = [Buffer : VulkanBuffer]()
    
    private let device : VulkanDevice
    private let vmaAllocator : VmaAllocator
    
    private var frameArgumentBuffers = [Resource.Handle]()
    
    private let uploadResourceAllocator : PoolResourceAllocator
    private let privateResourceAllocator : PoolResourceAllocator
    
    let temporaryBufferAllocator : TemporaryBufferAllocator

    public var frameGraphHasResourceAccess = false
    
    public init(device: VulkanDevice, inflightFrameCount: Int) {
        self.device = device
        self.commandPool = VulkanCommandPool(device: device, inflightFrameCount: inflightFrameCount)
        
        var allocatorInfo = VmaAllocatorCreateInfo()
        allocatorInfo.device = device.vkDevice
        allocatorInfo.physicalDevice = device.physicalDevice.vkDevice
        
        var allocator : VmaAllocator? = nil
        vmaCreateAllocator(&allocatorInfo, &allocator)
        self.vmaAllocator = allocator!
        
        self.uploadResourceAllocator = PoolResourceAllocator(device: device, allocator: self.vmaAllocator, memoryUsage: VMA_MEMORY_USAGE_CPU_TO_GPU, numFrames: inflightFrameCount)
        self.privateResourceAllocator = PoolResourceAllocator(device: device, allocator: self.vmaAllocator, memoryUsage: VMA_MEMORY_USAGE_GPU_ONLY, numFrames: 1)
        self.temporaryBufferAllocator = TemporaryBufferAllocator(numFrames: inflightFrameCount, allocator: self.vmaAllocator, device: device)
    }
    
    deinit {
        vmaDestroyAllocator(self.vmaAllocator)
    }
    
    public func registerWindowTexture(texture: Texture, context: Any) {
        self.windowReferences[texture] = (context as! VulkanSwapChain)
    }
    
    func allocatorForResource(storageMode: StorageMode, flags: ResourceFlags) -> ResourceAllocator {
        switch storageMode {
        case .managed, .shared:
            return self.uploadResourceAllocator
        case .private:
            return self.privateResourceAllocator
        }
    }
    
    @discardableResult
    func allocateTexture(_ texture: Texture, descriptor: TextureDescriptor, flags: ResourceFlags, usage: VkImageUsageFlagBits, sharingMode: VulkanSharingMode, initialLayout: VkImageLayout) -> VulkanImage {
        let vkImage : VulkanImage

        if flags.contains(.windowHandle) {
            vkImage = self.windowReferences[texture]!.nextImage(descriptor: descriptor)
        } else {
            let allocator = self.allocatorForResource(storageMode: descriptor.storageMode, flags: flags)
            vkImage = allocator.collectImage(descriptor: VulkanImageDescriptor(descriptor, usage: usage, sharingMode: sharingMode, initialLayout: initialLayout))
        }
        
        assert(self.textureReferences[texture] == nil)
        self.textureReferences[texture] = vkImage
        return vkImage
    }
    
    @discardableResult
    func allocateBuffer(_ buffer: Buffer, usage: VkBufferUsageFlagBits, sharingMode: VulkanSharingMode) -> VulkanBuffer {
        let allocator = self.allocatorForResource(storageMode: buffer.descriptor.storageMode, flags: buffer.flags)
        let vkBuffer = allocator.collectBuffer(descriptor: VulkanBufferDescriptor(buffer.descriptor, usage: usage, sharingMode: sharingMode))

        assert(self.bufferReferences[buffer] == nil)
        self.bufferReferences[buffer] = vkBuffer

        return vkBuffer
    }
    
    @discardableResult
    func allocateBufferIfNeeded(_ buffer: Buffer, usage: VkBufferUsageFlagBits, sharingMode: VulkanSharingMode) -> VulkanBuffer {
        if let vkBuffer = self.bufferReferences[buffer] {
            assert(vkBuffer.descriptor.size >= buffer.descriptor.length)
            return vkBuffer
        }
        return self.allocateBuffer(buffer, usage: usage, sharingMode: sharingMode)
    }
    
    @discardableResult
    func allocateTextureIfNeeded(_ texture: Texture, usage: VkImageUsageFlagBits, sharingMode: VulkanSharingMode, initialLayout: VkImageLayout) -> VulkanImage {
        if let vkTexture = self.textureReferences[texture] {
            return vkTexture
        }
        return self.allocateTexture(texture, descriptor: texture.descriptor, flags: texture.flags, usage: usage, sharingMode: sharingMode, initialLayout: initialLayout)
    }

    func allocateArgumentBufferIfNeeded(_ argumentBuffer: _ArgumentBuffer, bindingPath: ResourceBindingPath, commandBufferResources: CommandBufferResources, pipelineReflection: VulkanPipelineReflection, stateCaches: StateCaches) -> VulkanArgumentBuffer {
        if let vulkanArgumentBuffer = self.argumentBufferReferences[argumentBuffer.handle] {
            return vulkanArgumentBuffer
        }
        
        let buffer = VulkanArgumentBuffer(arguments: argumentBuffer, 
                                          bindingPath: bindingPath, 
                                          commandBufferResources: commandBufferResources,
                                          pipelineReflection: pipelineReflection, 
                                          resourceRegistry: self, 
                                          stateCaches: stateCaches)

        self.argumentBufferReferences[argumentBuffer.handle] = buffer
        if !argumentBuffer.flags.contains(.persistent) {
            self.frameArgumentBuffers.append(argumentBuffer.handle)
        }
        
        return buffer
    }
    
    // These subscript methods should only be called after 'allocate' has been called.
    // If you hit an error here, check if you forgot to make a resource persistent.
    subscript(texture: Texture) -> VulkanImage? {
        return self.textureReferences[texture]
    }
    
    subscript(texture handle: Texture.Handle) -> VulkanImage? {
        let texture = Texture(existingHandle: handle)
        if self.textureReferences[texture] == nil {
            fatalError("Texture \(texture) is not in registry.")
        }
        return self.textureReferences[texture]!
    }
    
    subscript(buffer: Buffer) -> VulkanBuffer? {
        return self.bufferReferences[buffer]
    }
    
    subscript(buffer buffer: Buffer.Handle) -> VulkanBuffer? {
        return self.bufferReferences[Buffer(existingHandle: buffer)]
    }
    
    public func disposeTexture(_ texture: Texture) {
        if let vkTexture = self.textureReferences.removeValue(forKey: texture), !texture.flags.contains(.windowHandle) {
            // assert(vkTexture.waitSemaphore == nil, "Texture \(texture.handle) with flags \(texture.flags), pixelFormat \(texture.descriptor.pixelFormat) is being disposed with an active waitSemaphore.")
            let allocator = self.allocatorForResource(storageMode: texture.descriptor.storageMode, flags: texture.flags)
            allocator.depositImage(vkTexture)
        }
    }
    
    public func disposeBuffer(_ buffer: Buffer) {
        if let vkBuffer = self.bufferReferences.removeValue(forKey: buffer) {
            assert(vkBuffer.waitSemaphore == nil)
            let allocator = self.allocatorForResource(storageMode: buffer.descriptor.storageMode, flags: buffer.flags)
            allocator.depositBuffer(vkBuffer)
        }
    }

    public func disposeArgumentBuffer(_ buffer: ArgumentBuffer) {
        // Only called if the buffer isn't persistent.
        self.argumentBufferReferences.removeValue(forKey: buffer.handle)
    }

    public func disposeArgumentBufferArray(_ buffer: ArgumentBufferArray) {
        // Only called if the buffer isn't persistent.
        self.argumentBufferReferences.removeValue(forKey: buffer.handle)
    }
    
    public func bufferContents(for buffer: Buffer, range: Range<Int>) -> UnsafeMutableRawPointer {
        assert(self[buffer] == nil || self.frameGraphHasResourceAccess, "Frame GPU memory for a pre-existing buffer may not be accessed outside of a FrameGraph RenderPass.")

        if let vkBuffer = self[buffer] {
            return vkBuffer.map(range: range)
        } else {
            if let memory = self.frameCPUBufferContents[buffer] {
                return memory + range.lowerBound
            } else {
                let memory = self.cpuDataCache.allocate(bytes: buffer.descriptor.length, alignedTo: 64)
                self.frameCPUBufferContents[buffer] = memory
                return memory + range.lowerBound
            }
        }
    }

    public func buffer(_ buffer: Buffer, didModifyRange range: Range<Int>) {
        if let vkBuffer = self[buffer] {
//        if buffer.descriptor.storageMode == .managed {
//            var memoryRange = VkMappedMemoryRange()
//            memoryRange.sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE
//            memoryRange.memory = vkBuffer.memory
//            memoryRange.size = VkDeviceSize(range.count)
//            memoryRange.offset = VkDeviceSize(range.lowerBound)
//            
//            vkFlushMappedMemoryRanges(self.device.vkDevice, 1, &memoryRange)
//        }

            vkBuffer.unmapMemory(range: range)
        } else {
            let memory = self.frameCPUBufferContents[buffer]!
            buffer.withDeferredSlice(range: range) { (slice : RawBufferSlice) in
                slice.withContents {
                    $0.copyMemory(from: memory + range.lowerBound, byteCount: range.count)
                }
            }
        }
    }
    
    public func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) {
        assert(self[texture] == nil || self.frameGraphHasResourceAccess, "Frame GPU memory for a pre-existing texture may not be accessed outside of a FrameGraph RenderPass.")

        let usage = VkImageUsageFlagBits(texture.descriptor.usageHint, pixelFormat: texture.descriptor.pixelFormat)
        let texture = self.allocateTextureIfNeeded(texture, usage: usage, sharingMode: VulkanSharingMode(usage: usage, queueIndices: self.device.physicalDevice.queueFamilyIndices), initialLayout: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL)
        
        fatalError("replaceTextureRegion is unimplemented on Vulkan (texture \(texture).")
        //texture.replace(region: VkExtent3D(region), mipmapLevel: mipmapLevel, withBytes: bytes, bytesPerRow: bytesPerRow)
    }
    
    public func cycleFrames() {
        self.commandPool.cycleFrames()
        
        self.cpuDataCache.reset()
        self.frameCPUBufferContents.removeAll(keepingCapacity: true)

        while let argBuffer = self.frameArgumentBuffers.popLast() {
            self.argumentBufferReferences.removeValue(forKey: argBuffer)
        }
        
        self.uploadResourceAllocator.cycleFrames()
        self.privateResourceAllocator.cycleFrames()
        self.temporaryBufferAllocator.cycleFrames()
        self.windowReferences.removeAll(keepingCapacity: true)
    }
}

#endif // canImport(Vulkan)
