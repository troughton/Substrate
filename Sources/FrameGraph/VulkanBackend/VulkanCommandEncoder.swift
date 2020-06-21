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
    var resourceMap : FrameResourceMap<VulkanBackend> { get }
}

extension VulkanCommandEncoder {
    
    var commandBuffer : VkCommandBuffer {
        return self.commandBufferResources.commandBuffer
    }
    
    func checkResourceCommands(_ resourceCommands: [CompactedResourceCommand<VulkanCompactedResourceCommandType>], resourceCommandIndex: inout Int, phase: PerformOrder, commandIndex: Int) {
        while resourceCommandIndex < resourceCommands.count, commandIndex == resourceCommands[resourceCommandIndex].index, phase == resourceCommands[resourceCommandIndex].order {
            defer { resourceCommandIndex += 1 }
            
            switch resourceCommands[resourceCommandIndex].command {
            case .signalEvent(let event, let afterStages):
                vkCmdSetEvent(self.commandBufferResources.commandBuffer, event, VkPipelineStageFlags(afterStages))
                
            case .waitForEvents(let events, let sourceStages, let destinationStages, let memoryBarriers, let bufferMemoryBarriers, let imageMemoryBarriers):
                
                vkCmdWaitEvents(self.commandBuffer, UInt32(events.count), events.baseAddress, VkPipelineStageFlags(sourceStages), VkPipelineStageFlags(destinationStages), UInt32(memoryBarriers.count), memoryBarriers.baseAddress, UInt32(bufferMemoryBarriers.count), bufferMemoryBarriers.baseAddress, UInt32(imageMemoryBarriers.count), imageMemoryBarriers.baseAddress)
                
            case .pipelineBarrier(let sourceStages, let destinationStages, let dependencyFlags, let memoryBarriers, let bufferMemoryBarriers, let imageMemoryBarriers):
                vkCmdPipelineBarrier(self.commandBuffer, VkPipelineStageFlags(sourceStages), VkPipelineStageFlags(destinationStages), VkDependencyFlags(dependencyFlags), UInt32(memoryBarriers.count), memoryBarriers.baseAddress, UInt32(bufferMemoryBarriers.count), bufferMemoryBarriers.baseAddress, UInt32(imageMemoryBarriers.count), imageMemoryBarriers.baseAddress)
            }
        }
    }
    
    func endEncoding() {
        vkEndCommandBuffer(self.commandBuffer)
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
    
    func endEncoding() {
        self.endEncoding(for: self.renderEncoder)
        self.endEncoding(for: self.computeEncoder)
        self.endEncoding(for: self.blitEncoder)
        
        let device = frameGraph.backend.device.vkDevice

        print("Error: synchronisation for endEncoding \(#file):\(#line) is not implemented.")
        
//        for queue in self.device.queues {
//            let fence = self.device.fencePool.allocateFence()
//            self.commandBufferResources[0].fences.append(fence)
//            queue.submit(fence: fence)
//        }
//        
//        
//        let fences = self.commandBufferResources[0].fences
//        
//        DispatchQueue.global().async {
//            var waitInfo = VkSemaphoreWaitInfo()
//            waitInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO
//            waitInfo.semaphoreCount = 1
//            
//            vkWaitSemaphores(device, <#T##pWaitInfo: UnsafePointer<VkSemaphoreWaitInfo>!##UnsafePointer<VkSemaphoreWaitInfo>!#>, .max).check()
//            fences.withUnsafeBufferPointer { fences in
//                vkWaitForFences(device, UInt32(fences.count), fences.baseAddress, true, UInt64.max).check()
//            }
//            completion()
//            
//            self.frameGraph.markCommandBufferResourcesCompleted(self.commandBufferResources)
//        }
    }
}

#endif // canImport(Vulkan)
