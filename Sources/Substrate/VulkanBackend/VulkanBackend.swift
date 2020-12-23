//
//  VKRenderer.swift
//  VKRenderer
//
//  Created by Joseph Bennett on 1/1/18.
//
//

#if canImport(Vulkan)
import Vulkan
import SubstrateCExtras
import SubstrateUtilities
import Foundation

public final class VulkanBackend : SpecificRenderBackend {
    typealias BufferReference = VkBufferReference
    typealias TextureReference = VkImageReference
    typealias ArgumentBufferReference = VulkanArgumentBuffer
    typealias ArgumentBufferArrayReference = VulkanArgumentBuffer
    typealias SamplerReference = VkSampler
    
    typealias TransientResourceRegistry = VulkanTransientResourceRegistry
    typealias PersistentResourceRegistry = VulkanPersistentResourceRegistry
    
    typealias RenderTargetDescriptor = VulkanRenderTargetDescriptor
    
    typealias CompactedResourceCommandType = VulkanCompactedResourceCommandType
    typealias Event = VkSemaphore
    typealias BackendQueue = VulkanQueue
    typealias InterEncoderDependencyType = FineDependency
    typealias CommandBuffer = VulkanCommandBuffer
    
    public var api: RenderAPI {
        return .vulkan
    }
    
    public let vulkanInstance : VulkanInstance
    public let device : VulkanDevice
    
    let resourceRegistry : VulkanPersistentResourceRegistry
    let shaderLibrary : VulkanShaderLibrary
    let stateCaches : VulkanStateCaches
    
    var activeContext : RenderGraphContextImpl<VulkanBackend>? = nil
    let activeContextLock = SpinLock()
    
    var queueSyncSemaphores = [VkSemaphore?](repeating: nil, count: QueueRegistry.maxQueues)
    
    public init(instance: VulkanInstance, shaderLibraryURL: URL) {
        self.vulkanInstance = instance
        let physicalDevice = self.vulkanInstance.createSystemDefaultDevice()!
        
        self.device = VulkanDevice(physicalDevice: physicalDevice)!
        
        self.resourceRegistry = VulkanPersistentResourceRegistry(instance: instance, device: self.device)
        self.shaderLibrary = try! VulkanShaderLibrary(device: self.device, url: shaderLibraryURL)
        self.stateCaches = VulkanStateCaches(device: self.device, shaderLibrary: self.shaderLibrary)
        
        RenderBackend._backend = self
    }
    
    public func registerWindowTexture(texture: Texture, context: Any) {
        self.resourceRegistry.registerWindowTexture(texture: texture, context: context)
    }
    
    func setActiveContext(_ context: RenderGraphContextImpl<VulkanBackend>?) {
        if context != nil {
            self.activeContextLock.lock()
            assert(self.activeContext == nil)
            self.activeContext = context
        } else {
            assert(self.activeContext != nil)
            self.activeContext = nil
            self.activeContextLock.unlock()
        }
    }
    
    public func materialisePersistentTexture(_ texture: Texture) -> Bool {
        return resourceRegistry.accessLock.withWriteLock {
            return self.resourceRegistry.allocateTexture(texture) != nil
        }
    }
    
    public func materialisePersistentBuffer(_ buffer: Buffer) -> Bool {
        return resourceRegistry.accessLock.withWriteLock {
            return self.resourceRegistry.allocateBuffer(buffer) != nil
        }
    }
    
    public func bufferContents(for buffer: Buffer, range: Range<Int>) -> UnsafeMutableRawPointer {
        let bufferReference = self.activeContext?.resourceMap.bufferForCPUAccess(buffer) ?? resourceRegistry.accessLock.withReadLock { resourceRegistry[buffer]! }
        let buffer = bufferReference.buffer
        
        return buffer.contents(range: (range.lowerBound + bufferReference.offset)..<(range.upperBound + bufferReference.offset))
    }
    
    public func buffer(_ buffer: Buffer, didModifyRange range: Range<Int>) {
        if range.isEmpty { return }
        let bufferReference = self.activeContext?.resourceMap.bufferForCPUAccess(buffer) ?? resourceRegistry.accessLock.withReadLock { resourceRegistry[buffer]! }
        let buffer = bufferReference.buffer
        buffer.didModifyRange((range.lowerBound + bufferReference.offset)..<(range.upperBound + bufferReference.offset))
    }
    
    public func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) {
        self.replaceTextureRegion(texture: texture, region: region, mipmapLevel: mipmapLevel, slice: 0, withBytes: bytes, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerRow * region.size.height * region.size.depth)
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

    public func dispose(argumentBufferArray: ArgumentBufferArray) {
        self.resourceRegistry.disposeArgumentBufferArray(argumentBufferArray)
    }

    public func backingResource(_ resource: Resource) -> Any? {
        return resourceRegistry.accessLock.withReadLock {
            if let buffer = resource.buffer {
                let bufferReference = resourceRegistry[buffer]
                return bufferReference?.buffer.vkBuffer
            } else if let texture = resource.texture {
                return resourceRegistry[texture]?.image.vkImage
            }
            return nil
        }
    }
    
    public func supportsPixelFormat(_ pixelFormat: PixelFormat, usage: TextureUsage) -> Bool {
        return device.physicalDevice.supportsPixelFormat(pixelFormat, usage: usage)
    }
    
    public var hasUnifiedMemory: Bool {
        return false // TODO: Retrieve this from the device.
    }
    
    public var requiresEmulatedInputAttachments: Bool {
        return false
    }

    public var supportsMemorylessAttachments: Bool {
        return false
    }
    
    public var renderDevice: Any {
        return self.device
    }
    
    @usableFromInline
    func renderPipelineReflection(descriptor: RenderPipelineDescriptor, renderTarget: Substrate.RenderTargetDescriptor) -> PipelineReflection? {
        return self.stateCaches.reflection(for: descriptor, renderTarget: renderTarget)
    }
    
    @usableFromInline
    func computePipelineReflection(descriptor: ComputePipelineDescriptor) -> PipelineReflection? {
        return self.stateCaches.reflection(for: descriptor)
    }
    
    @usableFromInline
    var pushConstantPath: ResourceBindingPath {
        return ResourceBindingPath.pushConstantPath
    }
    
    @usableFromInline
    func materialiseHeap(_ heap: Heap) -> Bool {
        assertionFailure("Heaps are not implemented on Vulkan")
        return false
    }
    
    @usableFromInline
    func registerExternalResource(_ resource: Resource, backingResource: Any) {
        fatalError("registerExternalResource is unimplemented on Vulkan")
    }
    
    @usableFromInline
    func copyTextureBytes(from texture: Texture, to bytes: UnsafeMutableRawPointer, bytesPerRow: Int, region: Region, mipmapLevel: Int) {
        fatalError("copyTextureBytes is unimplemented on Vulkan")
    }
    
    @usableFromInline
    func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, slice: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int) {
        
        let textureReference = self.activeContext?.resourceMap.textureForCPUAccess(texture) ?? resourceRegistry.accessLock.withReadLock { resourceRegistry[texture]! }
        let image = textureReference.image

        var data: UnsafeMutableRawPointer! = nil
        vmaMapMemory(image.allocator!, image.allocation!, &data)

        var subresource = VkImageSubresource()
        subresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT.rawValue;
        subresource.mipLevel = UInt32(mipmapLevel)
        subresource.arrayLayer = UInt32(slice)

        var layout = VkSubresourceLayout()
        vkGetImageSubresourceLayout(self.device.vkDevice, image.vkImage, &subresource, &layout)

        data += Int(layout.offset)

        let bytesPerPixel = texture.descriptor.pixelFormat.bytesPerPixel

        var sourcePointer = bytes
        for z in region.origin.z..<region.origin.z + region.size.depth {
            let zSliceData = data + z * Int(layout.depthPitch)
            for row in region.origin.y..<region.origin.y + region.size.height {
                let offsetInRow = Int(exactly: bytesPerPixel * Double(region.origin.x))!
                let bytesInRow = Int(exactly: bytesPerPixel * Double(region.size.width))!
                assert(bytesInRow == bytesPerRow)

                (zSliceData + row * Int(layout.rowPitch) + offsetInRow).copyMemory(from: sourcePointer, byteCount: bytesInRow)
                sourcePointer += bytesPerRow
            }
        }

        vmaUnmapMemory(image.allocator!, image.allocation!)
    }
    
    @usableFromInline func updateLabel(on resource: Resource) {
        // TODO: implement.
    }
    
    @usableFromInline func updatePurgeableState(for resource: Resource, to newState: ResourcePurgeableState?) -> ResourcePurgeableState {
        return .nonDiscardable // TODO: implement.
    }
    
    @usableFromInline
    func dispose(heap: Heap) {
        fatalError("dispose(Heap) is unimplemented on Vulkan")
    }
    
    @usableFromInline
    func argumentBufferPath(at index: Int, stages: RenderStages) -> ResourceBindingPath {
        return ResourceBindingPath(argumentBuffer: UInt32(index))
    }
    
    // MARK: - SpecificRenderBackend conformance
    
    static var requiresResourceResidencyTracking: Bool {
        return false
    }

    static func fillArgumentBuffer(_ argumentBuffer: ArgumentBuffer, storage: VulkanArgumentBuffer, firstUseCommandIndex: Int, resourceMap: FrameResourceMap<VulkanBackend>) {
        storage.encodeArguments(from: argumentBuffer, commandIndex: firstUseCommandIndex, resourceMap: resourceMap)
    }
    
    static func fillArgumentBufferArray(_ argumentBufferArray: ArgumentBufferArray, storage: VulkanArgumentBuffer, firstUseCommandIndex: Int, resourceMap: FrameResourceMap<VulkanBackend>) {
        fatalError()
    }
    
    func makeTransientRegistry(index: Int, inflightFrameCount: Int) -> VulkanTransientResourceRegistry {
        return VulkanTransientResourceRegistry(device: self.device, inflightFrameCount: inflightFrameCount, transientRegistryIndex: index, persistentRegistry: self.resourceRegistry)
    }
    
    func makeQueue(renderGraphQueue: Queue) -> VulkanQueue {
        return VulkanQueue(backend: self, device: self.device)
    }
    
    func makeSyncEvent(for queue: Queue) -> Event {
        var semaphoreTypeCreateInfo = VkSemaphoreTypeCreateInfo()
        semaphoreTypeCreateInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO
        semaphoreTypeCreateInfo.initialValue = 0
        semaphoreTypeCreateInfo.semaphoreType = VK_SEMAPHORE_TYPE_TIMELINE
        
        var semaphore: VkSemaphore? = nil
        withUnsafePointer(to: semaphoreTypeCreateInfo) { semaphoreTypeCreateInfo in
            var semaphoreCreateInfo = VkSemaphoreCreateInfo()
            semaphoreCreateInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO
            semaphoreCreateInfo.pNext = UnsafeRawPointer(semaphoreTypeCreateInfo)
            vkCreateSemaphore(self.device.vkDevice, &semaphoreCreateInfo, nil, &semaphore)
        }
        self.queueSyncSemaphores[Int(queue.index)] = semaphore
        return semaphore!
    }
    
    func syncEvent(for queue: Queue) -> VkSemaphore? {
        return self.queueSyncSemaphores[Int(queue.index)]
    }
    
    func freeSyncEvent(for queue: Queue) {
        assert(self.queueSyncSemaphores[Int(queue.index)] != nil)
        vkDestroySemaphore(self.device.vkDevice, self.queueSyncSemaphores[Int(queue.index)], nil)
        self.queueSyncSemaphores[Int(queue.index)] = nil
    }
}

#endif // canImport(Vulkan)
