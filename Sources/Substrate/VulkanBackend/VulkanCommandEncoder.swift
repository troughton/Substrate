//
//  VulkanCommandEncoder.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 17/01/18.
//

#if canImport(Vulkan)
import Vulkan
import SubstrateCExtras
import Dispatch

protocol VulkanCommandEncoder : AnyObject {
    
    var device : VulkanDevice { get }
    var queueFamily : QueueFamily { get }
    
    var commandBufferResources: VulkanCommandBuffer { get }
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
}

protocol VulkanResourceBindingCommandEncoder : VulkanCommandEncoder {
    var bindPoint : VkPipelineBindPoint { get }
    var pipelineLayout : VkPipelineLayout { get }
    var pipelineReflection : VulkanPipelineReflection { get }
    var stateCaches : VulkanStateCaches { get }
}

#endif // canImport(Vulkan)
