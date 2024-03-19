//
//  BlitCommandEncoder.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 8/01/18.
//

#if canImport(Vulkan)
import Vulkan
@_implementationOnly import SubstrateCExtras

class VulkanBlitCommandEncoder : VulkanCommandEncoder {
    let device: VulkanDevice
    
    let commandBufferResources: VulkanCommandBuffer
    let resourceMap: FrameResourceMap<VulkanBackend>
    
    public init(device: VulkanDevice, commandBuffer: VulkanCommandBuffer, resourceMap: FrameResourceMap<VulkanBackend>) {
        self.device = device
        self.commandBufferResources = commandBuffer
        self.resourceMap = resourceMap
    }
    
    var queueFamily: QueueFamily {
        return .copy
    }
    
    func executePass(_ pass: RenderPassRecord, resourceCommands: [CompactedResourceCommand<VulkanCompactedResourceCommandType>]) {
        var resourceCommandIndex = resourceCommands.binarySearch { $0.index < pass.commandRange!.lowerBound }
         
         for (i, command) in zip(pass.commandRange!, pass.commands) {
             self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .before, commandIndex: i)
             self.executeCommand(command, commandIndex: i)
             self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .after, commandIndex: i)
         }
    }
    
    func executeCommand(_ command: RenderGraphCommand, commandIndex: Int) {
        switch command {
        case .insertDebugSignpost(_):
            break
            
        case .setLabel(_):
            break
            
        case .pushDebugGroup(_):
            break
            
        case .popDebugGroup:
            break
            
        case .copyBufferToTexture(let args):
            let source = resourceMap[args.pointee.sourceBuffer]!
            let destination = resourceMap[args.pointee.destinationTexture]!.image

            let bytesPerPixel = args.pointee.destinationTexture.descriptor.pixelFormat.bytesPerPixel

            let possibleAspects = [VK_IMAGE_ASPECT_COLOR_BIT, VK_IMAGE_ASPECT_DEPTH_BIT, VK_IMAGE_ASPECT_STENCIL_BIT]
            let regions = possibleAspects.filter { destination.descriptor.allAspects.contains($0) }.map { aspect -> VkBufferImageCopy in
                let layers = VkImageSubresourceLayers(aspectMask: VkImageAspectFlags(aspect), mipLevel: args.pointee.destinationLevel, baseArrayLayer: args.pointee.destinationSlice, layerCount: 1)
                
                return VkBufferImageCopy(bufferOffset: VkDeviceSize(args.pointee.sourceOffset) + VkDeviceSize(source.offset),
                                         bufferRowLength: UInt32(Double(args.pointee.sourceBytesPerRow) / bytesPerPixel),
                                         bufferImageHeight: args.pointee.sourceBytesPerImage / args.pointee.sourceBytesPerRow,
                                         imageSubresource: layers,
                                         imageOffset: VkOffset3D(args.pointee.destinationOrigin),
                                         imageExtent: VkExtent3D(args.pointee.sourceSize))
                
            }
            
            regions.withUnsafeBufferPointer { regions in
                // NOTE: we can use .fullResource when querying the layout since the layout matching tests the intersection of the subresource ranges, and there's no possibility of overlapping uses with different layouts for a blit command index.
                vkCmdCopyBufferToImage(self.commandBufferResources.commandBuffer, source.buffer.vkBuffer, destination.vkImage, destination.layout(commandIndex: commandIndex, subresourceRange: .fullResource), UInt32(regions.count), regions.baseAddress)
            }
            
        case .copyBufferToBuffer(let args):
            let source = resourceMap[args.pointee.sourceBuffer]!
            let destination = resourceMap[args.pointee.destinationBuffer]!
            
            var region = VkBufferCopy(srcOffset: VkDeviceSize(args.pointee.sourceOffset) + VkDeviceSize(source.offset), dstOffset: VkDeviceSize(args.pointee.destinationOffset) + VkDeviceSize(destination.offset), size: VkDeviceSize(args.pointee.size))
            vkCmdCopyBuffer(self.commandBufferResources.commandBuffer, source.buffer.vkBuffer, destination.buffer.vkBuffer, 1, &region)
            
        case .copyTextureToBuffer(let args):
            fatalError("Unimplemented.")
            
        case .copyTextureToTexture(let args):
            let source = resourceMap[args.pointee.sourceTexture]!.image
            let destination = resourceMap[args.pointee.destinationTexture]!.image

            let bytesPerPixel = args.pointee.destinationTexture.descriptor.pixelFormat.bytesPerPixel

            let possibleAspects = [VK_IMAGE_ASPECT_COLOR_BIT, VK_IMAGE_ASPECT_DEPTH_BIT, VK_IMAGE_ASPECT_STENCIL_BIT]
            let regions = possibleAspects.filter { destination.descriptor.allAspects.contains($0) && source.descriptor.allAspects.contains($0) }.map { aspect -> VkImageCopy in
                let sourceLayers = VkImageSubresourceLayers(aspectMask: VkImageAspectFlags(aspect), mipLevel: args.pointee.sourceLevel, baseArrayLayer: args.pointee.sourceSlice, layerCount: 1)
                let destinationLayers = VkImageSubresourceLayers(aspectMask: VkImageAspectFlags(aspect), mipLevel: args.pointee.destinationLevel, baseArrayLayer: args.pointee.destinationSlice, layerCount: 1)
                
                return VkImageCopy(srcSubresource: sourceLayers,
                                    srcOffset: VkOffset3D(args.pointee.sourceOrigin),
                                    dstSubresource: destinationLayers,
                                    dstOffset: VkOffset3D(args.pointee.destinationOrigin),
                                    extent: VkExtent3D(args.pointee.sourceSize))
                
            }
            
            regions.withUnsafeBufferPointer { regions in
                // NOTE: we can use .fullResource when querying the layout since the layout matching tests the intersection of the subresource ranges, and there's no possibility of overlapping uses with different layouts for a blit command index.
                vkCmdCopyImage(
                    self.commandBufferResources.commandBuffer, 
                    source.vkImage, source.layout(commandIndex: commandIndex, subresourceRange: .fullResource),
                    destination.vkImage, destination.layout(commandIndex: commandIndex, subresourceRange: .fullResource),
                    UInt32(regions.count), regions.baseAddress
                )
            }
            
        case .fillBuffer(let args):
            let buffer = resourceMap[args.pointee.buffer]!
            let byteValue = UInt32(args.pointee.value)
            let intValue : UInt32 = (byteValue << 24) | (byteValue << 16) | (byteValue << 8) | byteValue
            vkCmdFillBuffer(self.commandBufferResources.commandBuffer, buffer.buffer.vkBuffer, VkDeviceSize(args.pointee.range.lowerBound) + VkDeviceSize(buffer.offset), VkDeviceSize(args.pointee.range.count), intValue)
            
        case .generateMipmaps(let texture):
            fatalError("Mipmap generation should be handled by a series of blits at the RenderGraph level")
            
        case .blitTextureToTexture(let args):
            let sourceImage = resourceMap[args.pointee.sourceTexture]!.image
            let destImage = resourceMap[args.pointee.destinationTexture]!.image
            let sourceLayout = sourceImage.layout(commandIndex: commandIndex, slice: Int(args.pointee.sourceSlice), level: Int(args.pointee.sourceLevel), descriptor: args.pointee.sourceTexture.descriptor)
            let destLayout = destImage.layout(commandIndex: commandIndex, slice: Int(args.pointee.destinationSlice), level: Int(args.pointee.destinationLevel), descriptor: args.pointee.destinationTexture.descriptor)
            var region = VkImageBlit()
            
            region.srcSubresource.aspectMask = VkImageAspectFlags(sourceImage.descriptor.allAspects)
            region.srcSubresource.mipLevel = args.pointee.sourceLevel
            region.srcSubresource.baseArrayLayer = args.pointee.sourceSlice
            region.srcSubresource.layerCount = 1
            region.srcOffsets.0.x = Int32(args.pointee.sourceOrigin.x)
            region.srcOffsets.0.y = Int32(args.pointee.sourceOrigin.y)
            region.srcOffsets.0.z = Int32(args.pointee.sourceOrigin.z)
            region.srcOffsets.1.x = Int32(args.pointee.sourceSize.width)
            region.srcOffsets.1.y = Int32(args.pointee.sourceSize.height)
            region.srcOffsets.1.z = Int32(args.pointee.sourceSize.depth)
            
            region.dstSubresource.aspectMask = VkImageAspectFlags(destImage.descriptor.allAspects)
            region.dstSubresource.mipLevel = args.pointee.destinationLevel
            region.dstSubresource.baseArrayLayer = args.pointee.destinationSlice
            region.dstSubresource.layerCount = 1
            region.dstOffsets.0.x = Int32(args.pointee.destinationOrigin.x)
            region.dstOffsets.0.y = Int32(args.pointee.destinationOrigin.y)
            region.dstOffsets.0.z = Int32(args.pointee.destinationOrigin.z)
            region.dstOffsets.1.x = Int32(args.pointee.destinationSize.width)
            region.dstOffsets.1.y = Int32(args.pointee.destinationSize.height)
            region.dstOffsets.1.z = Int32(args.pointee.destinationSize.depth)
            
            // Generate a mip level by copying and scaling the previous one.
            vkCmdBlitImage(self.commandBufferResources.commandBuffer, sourceImage.vkImage, sourceLayout, destImage.vkImage, destLayout, 1, &region, VkFilter(args.pointee.filter))
            
        case .synchroniseTexture(let textureHandle):
            fatalError("GPU to CPU synchronisation of managed resources is unimplemented on Vulkan.")
            
        case .synchroniseTextureSlice(let args):
            fatalError("GPU to CPU synchronisation of managed resources is unimplemented on Vulkan.")
            
        case .synchroniseBuffer(let buffer):
            fatalError("GPU to CPU synchronisation of managed resources is unimplemented on Vulkan.")
            
        default:
            fatalError()
        }
    }
}

#endif // canImport(Vulkan)
