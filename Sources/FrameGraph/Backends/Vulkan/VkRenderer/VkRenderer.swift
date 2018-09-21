//
//  VKRenderer.swift
//  VKRenderer
//
//  Created by Joseph Bennett on 1/1/18.
//
//

import FrameGraph
import RenderAPI
import CVkRenderer
import Utilities
import Foundation
import LlamaIO

public final class VkBackend : RenderBackendProtocol, FrameGraphBackend {
    
    public let vulkanInstance : VulkanInstance
    public let device : VulkanDevice
    public let maxInflightFrames : Int
    
    let resourceRegistry : ResourceRegistry
    let shaderLibrary : VulkanShaderLibrary
    let frameGraph : VulkanFrameGraphBackend
    
    public init(instance: VulkanInstance, surface: VkSurfaceKHR, numInflightFrames: Int) {
        self.vulkanInstance = instance
        self.maxInflightFrames = numInflightFrames
        let physicalDevice = self.vulkanInstance.createSystemDefaultDevice(surface: surface)!
        
        self.device = VulkanDevice(physicalDevice: physicalDevice)
        
        self.resourceRegistry = ResourceRegistry(device: self.device, numInflightFrames: numInflightFrames)
        
        self.shaderLibrary = try! VulkanShaderLibrary(device: self.device, url: AssetLoader.baseURL(forCatalogue: .engine).appendingPathComponent("\\Shaders\\Vulkan"))
        
        self.frameGraph = VulkanFrameGraphBackend(device: self.device, resourceRegistry: resourceRegistry, shaderLibrary: self.shaderLibrary)
        
        RenderBackend.backend = self
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
    
    public var isDepth24Stencil8PixelFormatSupported: Bool = false // TODO: query device capabilities for this
    
    public var threadExecutionWidth : Int = 32 // TODO: Actually retrieve this from the device.

    public var renderDevice: Any {
        return self.device
    }
    
    public func executeFrameGraph(passes: [RenderPassRecord], resourceUsages: ResourceUsages, commands: [FrameGraphCommand], completion: @escaping () -> Void) {
        self.frameGraph.executeFrameGraph(passes: passes, resourceUsages: resourceUsages, commands: commands, completion: completion)
    }
    
    public func setReflectionRenderPipeline(descriptor: RenderPipelineDescriptor, renderTarget: RenderTargetDescriptor) {
        self.frameGraph.stateCaches.setReflectionRenderPipeline(descriptor: descriptor, renderTarget: renderTarget)
    }
    
    public func setReflectionComputePipeline(descriptor: ComputePipelineDescriptor) {
        self.frameGraph.stateCaches.setReflectionComputePipeline(descriptor: descriptor)
    }
    
    public func bindingPath(argumentName: String, arrayIndex: Int, argumentBufferPath: ResourceBindingPath?) -> ResourceBindingPath? {
        return self.frameGraph.stateCaches.bindingPath(argumentName: argumentName, arrayIndex: arrayIndex)
    }

    public func bindingPath(argumentBuffer: ArgumentBuffer, argumentName: String) -> ResourceBindingPath? {
        return self.frameGraph.stateCaches.bindingPath(argumentBuffer: argumentBuffer, argumentName: argumentName)
    }

    public func bindingPath(pathInOriginalArgumentBuffer: ResourceBindingPath, newArgumentBufferPath: ResourceBindingPath) -> ResourceBindingPath {
        let newParentPath = VulkanResourceBindingPath(newArgumentBufferPath)
        
        var modifiedPath = VulkanResourceBindingPath(pathInOriginalArgumentBuffer)
        modifiedPath.set = newParentPath.set
        return ResourceBindingPath(modifiedPath)
    }
    
    public func argumentReflection(at path: ResourceBindingPath) -> ArgumentReflection? {
        return self.frameGraph.stateCaches.argumentReflection(at: path)
    }
    
    public func bindingIsActive(at path: ResourceBindingPath) -> Bool {
        return self.argumentReflection(at: path)?.isActive ?? false
    }
}


