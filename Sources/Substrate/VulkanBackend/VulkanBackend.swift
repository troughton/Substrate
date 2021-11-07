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
    @TaskLocal static var activeContext: RenderGraphContextImpl<VulkanBackend>? = nil
    
    static var activeContextTaskLocal: TaskLocal<RenderGraphContextImpl<VulkanBackend>?> { $activeContext }
    
    typealias BufferReference = VkBufferReference
    typealias TextureReference = VkImageReference
    typealias ArgumentBufferReference = VulkanArgumentBuffer
    typealias ArgumentBufferArrayReference = VulkanArgumentBuffer
    typealias SamplerReference = VkSampler
    
    typealias VisibleFunctionTableReference = Void
    typealias IntersectionFunctionTableReference = Void
    
    typealias TransientResourceRegistry = VulkanTransientResourceRegistry
    typealias PersistentResourceRegistry = VulkanPersistentResourceRegistry
    
    typealias RenderTargetDescriptor = VulkanRenderTargetDescriptor
    
    typealias CompactedResourceCommandType = VulkanCompactedResourceCommandType
    typealias Event = VkSemaphore
    typealias BackendQueue = VulkanQueue
    typealias InterEncoderDependencyType = FineDependency
    typealias CommandBuffer = VulkanCommandBuffer
    typealias QueueImpl = VulkanQueue
    
    public var api: RenderAPI {
        return .vulkan
    }
    
    public let vulkanInstance : VulkanInstance
    public let device : VulkanDevice
    
    let resourceRegistry : VulkanPersistentResourceRegistry
    let shaderLibrary : VulkanShaderLibrary
    let stateCaches : VulkanStateCaches
    let enableValidation : Bool
    let enableShaderHotReloading : Bool
    
    var activeContext : RenderGraphContextImpl<VulkanBackend>? = nil
    let activeContextLock = SpinLock()
    
    var queueSyncSemaphores = [VkSemaphore?](repeating: nil, count: QueueRegistry.maxQueues)
    
    public init(instance: VulkanInstance, shaderLibraryURL: URL, enableValidation: Bool = true, enableShaderHotReloading: Bool = true) {
        self.vulkanInstance = instance
        let physicalDevice = self.vulkanInstance.createSystemDefaultDevice()!
        
        self.device = VulkanDevice(physicalDevice: physicalDevice)!
        
        self.resourceRegistry = VulkanPersistentResourceRegistry(instance: instance, device: self.device)
        self.shaderLibrary = try! VulkanShaderLibrary(device: self.device, url: shaderLibraryURL)
        self.stateCaches = VulkanStateCaches(device: self.device, shaderLibrary: self.shaderLibrary)
        self.enableValidation = enableValidation
        self.enableShaderHotReloading = enableShaderHotReloading
        
        RenderBackend._backend = self
    }
    
    func reloadShaderLibraryIfNeeded() async {
        if self.enableShaderHotReloading {
            await self.stateCaches.checkForLibraryReload()
        }
    }
    
    public func materialisePersistentResource(_ resource: Resource) -> Bool {
        switch resource.type {
        case .texture:
            return self.resourceRegistry.allocateTexture(Texture(resource)!) != nil
        case .buffer:
            return self.resourceRegistry.allocateBuffer(Buffer(resource)!) != nil
        default:
            preconditionFailure("Unhandled resource type in materialisePersistentResource")
        }
    }
    
    public func bufferContents(for buffer: Buffer, range: Range<Int>) -> UnsafeMutableRawPointer? {
        let bufferReference = self.activeContext?.resourceMap.bufferForCPUAccess(buffer, needsLock: true) ?? resourceRegistry[buffer]!
        let buffer = bufferReference.buffer
        
        return buffer.contents(range: (range.lowerBound + bufferReference.offset)..<(range.upperBound + bufferReference.offset))
    }
    
    public func buffer(_ buffer: Buffer, didModifyRange range: Range<Int>) {
        if range.isEmpty { return }
        let bufferReference = self.activeContext?.resourceMap.bufferForCPUAccess(buffer, needsLock: true) ?? resourceRegistry[buffer]!
        let buffer = bufferReference.buffer
        buffer.didModifyRange((range.lowerBound + bufferReference.offset)..<(range.upperBound + bufferReference.offset))
    }
    
    public func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) async {
        await self.replaceTextureRegion(texture: texture, region: region, mipmapLevel: mipmapLevel, slice: 0, withBytes: bytes, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerRow * region.size.height * region.size.depth)
    }
    
    public func dispose(resource: Resource) {
        self.resourceRegistry.dispose(resource: resource)
    }
    
    public func backingResource(_ resource: Resource) -> Any? {
        if let buffer = Buffer(resource) {
            let bufferReference = resourceRegistry[buffer]
            return bufferReference?.buffer.vkBuffer
        } else if let texture = Texture(resource) {
            return resourceRegistry[texture]?.image.vkImage
        }
        return nil
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
    
    @usableFromInline func replaceBackingResource(for resource: Resource, with: Any?) -> Any? {
        fatalError("replaceBackingResource(for:with:) is unimplemented on Vulkan")
    }
    
    @usableFromInline
    func registerExternalResource(_ resource: Resource, backingResource: Any) {
        fatalError("registerExternalResource is unimplemented on Vulkan")
    }
    
    @usableFromInline
    func copyTextureBytes(from texture: Texture, to bytes: UnsafeMutableRawPointer, bytesPerRow: Int, region: Region, mipmapLevel: Int) {
        fatalError("copyTextureBytes is unimplemented on Vulkan")
    }
    
    
    public func sizeAndAlignment(for buffer: BufferDescriptor) -> (size: Int, alignment: Int) {
        fatalError("sizeAndAlignment(for:) is unimplemented on Vulkan")
    }
    
    public func sizeAndAlignment(for texture: TextureDescriptor) -> (size: Int, alignment: Int) {
        fatalError("sizeAndAlignment(for:) is unimplemented on Vulkan")
    }
    
    @usableFromInline func usedSize(for heap: Heap) -> Int {
        fatalError("usedSize(for:) is unimplemented on Vulkan")
    }
    
    @usableFromInline func currentAllocatedSize(for heap: Heap) -> Int {
        fatalError("currentAllocatedSize(for:) is unimplemented on Vulkan")
    }
    
    @usableFromInline func maxAvailableSize(forAlignment alignment: Int, in heap: Heap) -> Int {
        fatalError("maxAvailableSize(forAlignment:in:) is unimplemented on Vulkan")
    }
    
    
    @usableFromInline func accelerationStructureSizes(for descriptor: AccelerationStructureDescriptor) -> AccelerationStructureSizes {
        fatalError("accelerationStructureSizes(for:) is unimplemented on Vulkan")
    }
    
    @usableFromInline
    func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, slice: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int) async {
        
        let textureReference = await self.activeContext?.resourceMap.textureForCPUAccess(texture, needsLock: true) ?? resourceRegistry[texture]!
        let image = textureReference.image

        var data: UnsafeMutableRawPointer! = nil
        vmaMapMemory(image.allocator!, image.allocation!, &data)

        var subresource = VkImageSubresource()
        subresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT.flags
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
    func argumentBufferPath(at index: Int, stages: RenderStages) -> ResourceBindingPath {
        return ResourceBindingPath(argumentBuffer: UInt32(index))
    }
    
    // MARK: - SpecificRenderBackend conformance
    
    static var requiresResourceResidencyTracking: Bool {
        return false
    }

    static func fillArgumentBuffer(_ argumentBuffer: ArgumentBuffer, storage: VulkanArgumentBuffer, firstUseCommandIndex: Int, resourceMap: FrameResourceMap<VulkanBackend>) async {
        await storage.encodeArguments(from: argumentBuffer, commandIndex: firstUseCommandIndex, resourceMap: resourceMap)
    }
    
    static func fillArgumentBufferArray(_ argumentBufferArray: ArgumentBufferArray, storage: VulkanArgumentBuffer, firstUseCommandIndex: Int, resourceMap: FrameResourceMap<VulkanBackend>) {
        fatalError()
    }
    
    func fillVisibleFunctionTable(_ table: VisibleFunctionTable, storage: Void, firstUseCommandIndex: Int, resourceMap: FrameResourceMap<VulkanBackend>) async {
        preconditionFailure()
    }
    
    func fillIntersectionFunctionTable(_ table: IntersectionFunctionTable, storage: Void, firstUseCommandIndex: Int, resourceMap: FrameResourceMap<VulkanBackend>) async {
        preconditionFailure()
    }
    
    func makeTransientRegistry(index: Int, inflightFrameCount: Int, queue: Queue) -> VulkanTransientResourceRegistry {
        return VulkanTransientResourceRegistry(device: self.device, inflightFrameCount: inflightFrameCount, queue: queue, transientRegistryIndex: index, persistentRegistry: self.resourceRegistry)
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
    
    func didCompleteCommand(_ index: UInt64, queue: Queue, context: RenderGraphContextImpl<VulkanBackend>) {
        VulkanEventRegistry.instance.clearCompletedEvents()
    }
}

#else

@available(*, unavailable)
typealias VulkanBackend = UnavailableBackend

#endif // canImport(Vulkan)
