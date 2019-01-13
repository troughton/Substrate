//
//  VulkanCommandEncoder.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 17/01/18.
//

import CVkRenderer
import SwiftFrameGraph
import Dispatch

protocol VulkanCommandEncoder : class {
    
    var device : VulkanDevice { get }
    var queueFamily : QueueFamily { get }
    
    var commandBufferResources: CommandBufferResources { get }
    var resourceRegistry : ResourceRegistry { get }
}

extension VulkanCommandEncoder {

    var commandBuffer : VkCommandBuffer {
        return self.commandBufferResources.commandBuffer
    }
    
    var eventPool : VulkanEventPool.QueuePool {
        return self.device.eventPool.poolForQueue(self.queueFamily)
    }
    
    var semaphorePool : VulkanSemaphorePool {
        return self.device.semaphorePool
    }
    
    func executeResourceCommands(resourceCommands: inout [ResourceCommand], order: PerformOrder, commandIndex: Int) {
        while let resourceCommand = resourceCommands.last, resourceCommand.index == commandIndex, resourceCommand.order == order {
            defer { resourceCommands.removeLast() }
            
            switch resourceCommand.type {
            case let .materialiseBuffer(buffer, usage, sharingMode):
                let vkBuffer = self.resourceRegistry.allocateBufferIfNeeded(buffer, usage: usage, sharingMode: sharingMode)
                commandBufferResources.buffers.append(vkBuffer)
                
                if vkBuffer.hasBeenHostUpdated {
                    // Insert a pipeline barrier to read from host memory
                    // NOTE: not actually necessary most of the time since it's implicitly
                    // inserted by the queue submission operation.
                    vkBuffer.hasBeenHostUpdated = false
                }
                
                if let semaphore = vkBuffer.waitSemaphore {
                    self.commandBufferResources.waitSemaphores.append(semaphore)
                    vkBuffer.waitSemaphore = nil
                }

                buffer.applyDeferredSliceActions()
                
            case let .materialiseTexture(texture, usage, sharingMode, destinationMask, barrier):
                // Possible initial layouts are undefined and preinitialised. Since we never have data we're preinitialising it with, we always use undefined
                let vkTexture = self.resourceRegistry.allocateTextureIfNeeded(texture, usage: usage, sharingMode: sharingMode, initialLayout: VK_IMAGE_LAYOUT_UNDEFINED)
                commandBufferResources.images.append(vkTexture)

                // If both the old and new layouts are preinitialised (meaning it's a persistent resource that will first be used
                // as a render target), we shouldn't insert a barrier.
                // If the new layout is undefined, then it'll be transitioned as part of a render pass and we don't need to do anything.
                if vkTexture.layout != barrier.newLayout, barrier.newLayout != VK_IMAGE_LAYOUT_PREINITIALIZED, barrier.newLayout != VK_IMAGE_LAYOUT_UNDEFINED {
                    var barrier = barrier
                    
                    if barrier.oldLayout == VK_IMAGE_LAYOUT_PREINITIALIZED { // otherwise it's undefined and we can throw away the old contents.
                        barrier.oldLayout = vkTexture.layout
                    }
                    barrier.image = vkTexture.vkImage
                    
                    vkCmdPipelineBarrier(commandBufferResources.commandBuffer, VkPipelineStageFlags(VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT), VkPipelineStageFlags(destinationMask), 0, 0, nil, 0, nil, 1, &barrier)
                    
                    vkTexture.layout = barrier.newLayout
                }

                if let semaphore = vkTexture.waitSemaphore {
                    self.commandBufferResources.waitSemaphores.append(semaphore)
                    vkTexture.waitSemaphore = nil
                }
                
            case .disposeBuffer(let buffer):
                self.resourceRegistry.disposeBuffer(buffer)
                
            case .disposeTexture(let texture):
                self.resourceRegistry.disposeTexture(texture)
                
            case .signalEvent(let id, let afterStages):
                let event = self.eventPool.collectEvent(id: id)
                vkCmdSetEvent(self.commandBufferResources.commandBuffer, event, VkPipelineStageFlags(afterStages))
                
            case .waitForEvent(let id, let barrierInfo):
                var event = self.eventPool.depositEvent(id: id) as VkEvent?

                switch barrierInfo.barrier {
                case .texture(let textureHandle, var imageBarrier):
                    let texture = self.resourceRegistry[textureHandle]!
                    imageBarrier.image = texture.vkImage
                    vkCmdWaitEvents(self.commandBufferResources.commandBuffer, 1, &event, VkPipelineStageFlags(barrierInfo.sourceMask), VkPipelineStageFlags(barrierInfo.destinationMask), 0, nil, 0, nil, 1, &imageBarrier)
                    vkCmdResetEvent(self.commandBufferResources.commandBuffer, event, VkPipelineStageFlags(barrierInfo.destinationMask))
                    
                    texture.layout = imageBarrier.newLayout
                case .buffer(let bufferHandle, var bufferBarrier):
                    let buffer = self.resourceRegistry[bufferHandle]!
                    bufferBarrier.buffer = buffer.vkBuffer
                    vkCmdWaitEvents(self.commandBufferResources.commandBuffer, 1, &event, VkPipelineStageFlags(barrierInfo.sourceMask), VkPipelineStageFlags(barrierInfo.destinationMask), 0, nil, 1, &bufferBarrier, 0, nil)
                    vkCmdResetEvent(self.commandBufferResources.commandBuffer, event, VkPipelineStageFlags(barrierInfo.destinationMask))
                }
                
            case .signalSemaphore(let id, let afterStages):
                let semaphore = self.semaphorePool.allocateSemaphore(id: id)
                self.commandBufferResources.signalSemaphores.append(ResourceSemaphore(vkSemaphore: semaphore, stages: afterStages))
                
            case .waitForSemaphore(let id, let beforeStages):
                let semaphore = self.semaphorePool.collectSemaphore(id: id)
                self.commandBufferResources.waitSemaphores.append(ResourceSemaphore(vkSemaphore: semaphore, stages: beforeStages))

            case .pipelineBarrier(let barrier):
                
                switch barrier.barrier {
                case .buffer(let bufferHandle, var barrierInfo):
                    let buffer = self.resourceRegistry[bufferHandle]!
                    barrierInfo.buffer = buffer.vkBuffer
                    vkCmdPipelineBarrier(self.commandBufferResources.commandBuffer, VkPipelineStageFlags(barrier.sourceMask), VkPipelineStageFlags(barrier.destinationMask), 0, 0, nil, 1, &barrierInfo, 0, nil)
                    
                case .texture(let textureHandle, var barrierInfo):
                    let texture = self.resourceRegistry[textureHandle]!
                    barrierInfo.image = texture.vkImage
                    vkCmdPipelineBarrier(self.commandBufferResources.commandBuffer, VkPipelineStageFlags(barrier.sourceMask), VkPipelineStageFlags(barrier.destinationMask), 0, 0, nil, 0, nil, 1, &barrierInfo)
                    
                    texture.layout = barrierInfo.newLayout
                }
                
            case .storeResource(let resource, let finalLayout, let stages):
                resource.markAsInitialised()

                let semaphore = self.semaphorePool.allocateSemaphore()
                let resourceSemaphore = ResourceSemaphore(vkSemaphore: semaphore, stages: stages)
                self.commandBufferResources.signalSemaphores.append(resourceSemaphore)
                
                if let texture = resource.texture {
                    let vulkanTexture = self.resourceRegistry[texture]!
                    vulkanTexture.waitSemaphore = resourceSemaphore
                    if let finalLayout = finalLayout {
                        vulkanTexture.layout = finalLayout
                    }
                } else if let buffer = resource.buffer {
                    let vulkanBuffer = self.resourceRegistry[buffer]!
                    vulkanBuffer.waitSemaphore = resourceSemaphore
                } else {
                    fatalError()
                }
            }
        }
    }
    
    func endEncoding() {
        vkEndCommandBuffer(self.commandBufferResources.commandBuffer)
    }
}

protocol VulkanResourceBindingCommandEncoder : VulkanCommandEncoder {
    var bindPoint : VkPipelineBindPoint { get }
    var pipelineLayout : VkPipelineLayout { get }
    var pipelineReflection : VulkanPipelineReflection { get }
    var stateCaches : StateCaches { get }
}

final class EncoderManager {

    let device : VulkanDevice
    let frameGraph: VulkanFrameGraphBackend
    
    private var renderEncoder : VulkanRenderCommandEncoder? = nil
    private var computeEncoder : VulkanComputeCommandEncoder? = nil
    private var blitEncoder : VulkanBlitCommandEncoder? = nil
    
    var commandBufferResources = [CommandBufferResources]()
    
    init(frameGraph: VulkanFrameGraphBackend) {
        self.frameGraph = frameGraph
        self.device = frameGraph.device
    }
    
    func renderCommandEncoder(descriptor: VulkanRenderTargetDescriptor) -> VulkanRenderCommandEncoder {
        if descriptor === self.renderEncoder?.renderTarget, let renderEncoder = self.renderEncoder {
            return renderEncoder
        } else {
            self.resetEncoders()
            
            let commandBufferResources = frameGraph.resourceRegistry.commandPool.allocateCommandBufferResources(passType: .draw)
            let renderEncoder = VulkanRenderCommandEncoder(device: self.device, renderTarget: descriptor, commandBufferResources: commandBufferResources, shaderLibrary: frameGraph.shaderLibrary, caches: frameGraph.stateCaches, resourceRegistry: frameGraph.resourceRegistry)
            self.renderEncoder = renderEncoder
            return renderEncoder
        }
    }
    
    func computeCommandEncoder() -> VulkanComputeCommandEncoder {
        self.resetEncoders()
            
        let commandBufferResources = frameGraph.resourceRegistry.commandPool.allocateCommandBufferResources(passType: .compute)
        let computeEncoder = VulkanComputeCommandEncoder(device: frameGraph.device, commandBuffer: commandBufferResources, shaderLibrary: frameGraph.shaderLibrary, caches: frameGraph.stateCaches, resourceRegistry: frameGraph.resourceRegistry)
        self.computeEncoder = computeEncoder
         return computeEncoder
    }
    
    func blitCommandEncoder() -> VulkanBlitCommandEncoder {
        self.resetEncoders()
            
        let commandBufferResources = frameGraph.resourceRegistry.commandPool.allocateCommandBufferResources(passType: .blit)
        let blitEncoder = VulkanBlitCommandEncoder(device: self.device, commandBuffer: commandBufferResources, resourceRegistry: frameGraph.resourceRegistry)
        self.blitEncoder = blitEncoder
        return blitEncoder
    }
    
    func resetEncoders() {
        self.endEncoding(for: self.renderEncoder)
        self.renderEncoder = nil
        
        self.endEncoding(for: self.computeEncoder)
        self.computeEncoder = nil
        
        self.endEncoding(for: self.blitEncoder)
        self.blitEncoder = nil
    }
    
    func endEncoding(for encoder: VulkanCommandEncoder?) {
        if let encoder = encoder {
            encoder.endEncoding()
            let queue = self.device.queueForFamily(encoder.queueFamily)
            queue.addCommandBuffer(resources: encoder.commandBufferResources)
            self.commandBufferResources.append(encoder.commandBufferResources)
        }
    }
    
    func endEncoding(completion: @escaping () -> Void) {
        self.endEncoding(for: self.renderEncoder)
        self.endEncoding(for: self.computeEncoder)
        self.endEncoding(for: self.blitEncoder)
        
        for queue in self.device.queues {
            let fence = self.device.fencePool.allocateFence()
            self.commandBufferResources[0].fences.append(fence)
            queue.submit(fence: fence)
        }
        
        let device = frameGraph.device.vkDevice

        let fences = self.commandBufferResources[0].fences

        DispatchQueue.global().async {
            fences.withUnsafeBufferPointer { fences in
                vkWaitForFences(device, UInt32(fences.count), fences.baseAddress, true, UInt64.max).check()
            }
            // DispatchQueue.main.async { 
                // FIXME: re-entrancy to the main thread seems broken in Windows Dispatch.
                // However, 'completion' is safe since it's only a semaphore signal.
                completion()
            // }

            self.frameGraph.markCommandBufferResourcesCompleted(self.commandBufferResources)
        }
    }
}
