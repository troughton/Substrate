//
//  VulkanCommandEncoder.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 17/01/18.
//

#if canImport(Vulkan)
import Vulkan
import FrameGraphCExtras
import Dispatch

protocol VulkanCommandEncoder : class {
    
    var device : VulkanDevice { get }
    var queueFamily : QueueFamily { get }
    
    var commandBufferResources: CommandBufferResources { get }
    var resourceMap : VulkanFrameResourceMap { get }
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
    
    func checkResourceCommands(_ resourceCommands: [VulkanFrameResourceCommand], resourceCommandIndex: inout Int, phase: PerformOrder, commandIndex: Int) {
        while resourceCommandIndex < resourceCommands.count, commandIndex == resourceCommands[resourceCommandIndex].index, phase == resourceCommands[resourceCommandIndex].order {
            defer { resourceCommandIndex += 1 }
            
            switch resourceCommands[resourceCommandIndex].command {
            case .signalEvent(let event, let afterStages):
                vkCmdSetEvent(self.commandBufferResources.commandBuffer, event.event, VkPipelineStageFlags(afterStages))
                
            case .waitForEvent(let event, let barrierInfo):
                var vkEvent = event.event as VkEvent?
                
                switch barrierInfo.barrier {
                case .texture(let textureHandle, var imageBarrier):
                    let texture = self.resourceMap[textureHandle]
                    imageBarrier.image = texture.vkImage
                    vkCmdWaitEvents(self.commandBufferResources.commandBuffer, 1, &vkEvent, VkPipelineStageFlags(barrierInfo.sourceMask), VkPipelineStageFlags(barrierInfo.destinationMask), 0, nil, 0, nil, 1, &imageBarrier)
                    vkCmdResetEvent(self.commandBufferResources.commandBuffer, vkEvent, VkPipelineStageFlags(barrierInfo.destinationMask))
                    
                    texture.layout = imageBarrier.newLayout
                case .buffer(let bufferHandle, var bufferBarrier):
                    let buffer = self.resourceMap[bufferHandle]
                    bufferBarrier.buffer = buffer.buffer.vkBuffer
                    vkCmdWaitEvents(self.commandBufferResources.commandBuffer, 1, &vkEvent, VkPipelineStageFlags(barrierInfo.sourceMask), VkPipelineStageFlags(barrierInfo.destinationMask), 0, nil, 1, &bufferBarrier, 0, nil)
                    vkCmdResetEvent(self.commandBufferResources.commandBuffer, vkEvent, VkPipelineStageFlags(barrierInfo.destinationMask))
                }
                
            case .pipelineBarrier(let barrier):
                switch barrier.barrier {
                case .buffer(let bufferHandle, var barrierInfo):
                    let buffer = self.resourceMap[bufferHandle]
                    barrierInfo.buffer = buffer.buffer.vkBuffer
                    vkCmdPipelineBarrier(self.commandBufferResources.commandBuffer, VkPipelineStageFlags(barrier.sourceMask), VkPipelineStageFlags(barrier.destinationMask), 0, 0, nil, 1, &barrierInfo, 0, nil)
                    
                case .texture(let textureHandle, var barrierInfo):
                    let texture = self.resourceMap[textureHandle]
                    barrierInfo.image = texture.vkImage
                    vkCmdPipelineBarrier(self.commandBufferResources.commandBuffer, VkPipelineStageFlags(barrier.sourceMask), VkPipelineStageFlags(barrier.destinationMask), 0, 0, nil, 0, nil, 1, &barrierInfo)
                    
                    texture.layout = barrierInfo.newLayout
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
    var stateCaches : VulkanStateCaches { get }
}

final class EncoderManager {
    
    let device : VulkanDevice
    let frameGraph: VulkanFrameGraphContext
    
    private var renderEncoder : VulkanRenderCommandEncoder? = nil
    private var computeEncoder : VulkanComputeCommandEncoder? = nil
    private var blitEncoder : VulkanBlitCommandEncoder? = nil
    
    var commandBufferResources = [CommandBufferResources]()
    
    init(frameGraph: VulkanFrameGraphContext) {
        self.frameGraph = frameGraph
        self.device = frameGraph.backend.device
    }
    
    func renderCommandEncoder(descriptor: VulkanRenderTargetDescriptor) -> VulkanRenderCommandEncoder {
        if descriptor === self.renderEncoder?.renderTarget, let renderEncoder = self.renderEncoder {
            return renderEncoder
        } else {
            self.resetEncoders()
            
            let commandBufferResources = frameGraph.commandPool.allocateCommandBufferResources(passType: .draw)
            let renderEncoder = VulkanRenderCommandEncoder(device: self.device, renderTarget: descriptor, commandBufferResources: commandBufferResources, shaderLibrary: frameGraph.backend.shaderLibrary, caches: frameGraph.backend.stateCaches, resourceMap: frameGraph.resourceMap)
            self.renderEncoder = renderEncoder
            return renderEncoder
        }
    }
    
    func computeCommandEncoder() -> VulkanComputeCommandEncoder {
        self.resetEncoders()
        
        let commandBufferResources = frameGraph.commandPool.allocateCommandBufferResources(passType: .compute)
        let computeEncoder = VulkanComputeCommandEncoder(device: frameGraph.backend.device, commandBuffer: commandBufferResources, shaderLibrary: frameGraph.backend.shaderLibrary, caches: frameGraph.backend.stateCaches, resourceMap: frameGraph.resourceMap)
        self.computeEncoder = computeEncoder
        return computeEncoder
    }
    
    func blitCommandEncoder() -> VulkanBlitCommandEncoder {
        self.resetEncoders()
        
        let commandBufferResources = frameGraph.commandPool.allocateCommandBufferResources(passType: .blit)
        let blitEncoder = VulkanBlitCommandEncoder(device: self.device, commandBuffer: commandBufferResources, resourceMap: frameGraph.resourceMap)
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
        
        let device = frameGraph.backend.device.vkDevice
        
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

#endif // canImport(Vulkan)
