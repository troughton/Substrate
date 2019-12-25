//
//  VKRenderer.swift
//  VKRenderer
//
//  Created by Joseph Bennett on 1/1/18.
//
//

#if canImport(Vulkan)
import Vulkan
import FrameGraphCExtras
import FrameGraphUtilities
import Foundation

public final class VkBackend : RenderBackendProtocol, FrameGraphContext {
    public let vulkanInstance : VulkanInstance
    public let device : VulkanDevice
    public let maxInflightFrames : Int
    
    let resourceRegistry : ResourceRegistry
    let shaderLibrary : VulkanShaderLibrary
    let frameGraph : VulkanFrameGraphContext
    
    public init(instance: VulkanInstance, surface: VkSurfaceKHR, shaderLibraryURL: URL, inflightFrameCount: Int) {
        self.vulkanInstance = instance
        self.maxInflightFrames = inflightFrameCount
        let physicalDevice = self.vulkanInstance.createSystemDefaultDevice(surface: surface)!
        
        self.device = VulkanDevice(physicalDevice: physicalDevice)
        
        self.resourceRegistry = ResourceRegistry(device: self.device, inflightFrameCount: inflightFrameCount)
        
        self.shaderLibrary = try! VulkanShaderLibrary(device: self.device, url: shaderLibraryURL)
        
        self.frameGraph = VulkanFrameGraphContext(device: self.device, resourceRegistry: resourceRegistry, shaderLibrary: self.shaderLibrary)
        
        RenderBackend._backend = self
    }

    public func beginFrameResourceAccess() {
        self.frameGraph.beginFrameResourceAccess()
    }
    
    public func registerWindowTexture(texture: Texture, context: Any) {
        self.resourceRegistry.registerWindowTexture(texture: texture, context: context)
    }
    
    public func materialisePersistentTexture(_ texture: Texture) {
        let usage = VkImageUsageFlagBits(texture.descriptor.usageHint, pixelFormat: texture.descriptor.pixelFormat)
        self.resourceRegistry.allocateTextureIfNeeded(texture, usage: usage, sharingMode: VulkanSharingMode(usage: usage, queueIndices: self.device.physicalDevice.queueFamilyIndices), initialLayout: VK_IMAGE_LAYOUT_UNDEFINED)
    }
    
    public func materialisePersistentBuffer(_ buffer: Buffer) {
        let usage = VkBufferUsageFlagBits(buffer.descriptor.usageHint)
        self.resourceRegistry.allocateBufferIfNeeded(buffer, usage: usage, sharingMode: VulkanSharingMode(usage: usage, queueIndices: self.device.physicalDevice.queueFamilyIndices))
    }
    
    public func bufferContents(for buffer: Buffer, range: Range<Int>) -> UnsafeMutableRawPointer {
        return self.resourceRegistry.bufferContents(for: buffer, range: range)
    }
    
    public func buffer(_ buffer: Buffer, didModifyRange range: Range<Int>) {
        self.resourceRegistry.buffer(buffer, didModifyRange: range)
    }
    
    public func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) {
        fatalError()
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
        return resourceRegistry.accessQueue.sync {
            if let buffer = resource.buffer {
                let bufferReference = resourceRegistry[buffer]
                return bufferReference?.vkBuffer
            } else if let texture = resource.texture {
                return resourceRegistry[texture]?.vkImage
            }
            return nil
        }
    }
    
    public var isDepth24Stencil8PixelFormatSupported: Bool = false // TODO: query device capabilities for this
    
    public var threadExecutionWidth : Int = 32 // TODO: Actually retrieve this from the device.

    public var renderDevice: Any {
        return self.device
    }
    
    public func executeFrameGraph(passes: [RenderPassRecord], resourceUsages: ResourceUsages, commands: [FrameGraphCommand], completion: @escaping () -> Void) {
        self.frameGraph.executeFrameGraph(passes: passes, resourceUsages: resourceUsages, commands: commands, completion: completion)
    }
    
    public func renderPipelineReflection(descriptor: RenderPipelineDescriptor, renderTarget: RenderTargetDescriptor) -> PipelineReflection {
        return self.frameGraph.stateCaches.reflection(for: descriptor, renderTarget: renderTarget)
    }
    
    public func computePipelineReflection(descriptor: ComputePipelineDescriptor) -> PipelineReflection {
        return self.frameGraph.stateCaches.reflection(for: descriptor)
    }
}

#endif // canImport(Vulkan)
