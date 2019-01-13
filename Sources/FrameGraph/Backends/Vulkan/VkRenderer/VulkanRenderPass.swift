//
//  VulkanRenderPass.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 16/01/18.
//

import SwiftFrameGraph
import CVkRenderer
import Utilities

class VulkanRenderPass {
    let device : VulkanDevice
    let vkPass : VkRenderPass
    let descriptor : VulkanRenderTargetDescriptor
    
    init(device: VulkanDevice, descriptor: VulkanRenderTargetDescriptor) {
        self.device = device
        self.descriptor = descriptor
        
        var createInfo = VkRenderPassCreateInfo()
        createInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO
        
        var attachments = [VkAttachmentDescription]()
        
        var attachmentIndices = [RenderTargetAttachmentIndex : Int]()
        
        if let depthAttachment = descriptor.descriptor.depthAttachment {
            var attachmentDescription = VkAttachmentDescription(pixelFormat: depthAttachment.texture.descriptor.pixelFormat, renderTargetDescriptor: depthAttachment, depthActions: descriptor.depthActions, stencilActions: descriptor.stencilActions)
            attachmentDescription.initialLayout = descriptor.initialLayouts[depthAttachment.texture] ?? VK_IMAGE_LAYOUT_UNDEFINED
            attachmentDescription.finalLayout = descriptor.finalLayouts[depthAttachment.texture] ?? VK_IMAGE_LAYOUT_GENERAL // TODO: Can we do something smarter here than just a general layout?
            attachmentIndices[.depthStencil] = attachments.count
            attachments.append(attachmentDescription)
        } else {
            assert(descriptor.descriptor.stencilAttachment == nil, "Stencil attachments without depth are currently unimplemented.")
        }
        
        for (i, (colorAttachment, actions)) in zip(descriptor.descriptor.colorAttachments, descriptor.colorActions).enumerated() {
            guard let colorAttachment = colorAttachment else { continue }
            var attachmentDescription = VkAttachmentDescription(pixelFormat: colorAttachment.texture.descriptor.pixelFormat, renderTargetDescriptor: colorAttachment, actions: actions)
            attachmentDescription.initialLayout = descriptor.initialLayouts[colorAttachment.texture] ?? VK_IMAGE_LAYOUT_UNDEFINED
            attachmentDescription.finalLayout = descriptor.finalLayouts[colorAttachment.texture] ?? VK_IMAGE_LAYOUT_PRESENT_SRC_KHR // FIXME: is this generally correct?
            attachmentIndices[.color(i)] = attachments.count
            attachments.append(attachmentDescription)
        }
        
        var subpasses = [VkSubpassDescription]()
        let attachmentReferences = ExpandingBuffer<VkAttachmentReference>(initialCapacity: 24)
        let preserveAttachmentIndices = ExpandingBuffer<UInt32>()
        
        var previousSubpass : VulkanSubpass? = nil
        for subpass in descriptor.subpasses {
            if subpass === previousSubpass { continue }
            defer { previousSubpass = subpass }
            
            var subpassDescription = VkSubpassDescription()
            subpassDescription.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS
            
            if subpass.descriptor.depthAttachment != nil {
                let layout = subpass.inputAttachments.contains(.depthStencil) ? VK_IMAGE_LAYOUT_GENERAL : VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
                attachmentReferences.append(VkAttachmentReference(attachment: UInt32(attachmentIndices[.depthStencil]!), layout: layout))
            }
            
            for (i, colorAttachment) in subpass.descriptor.colorAttachments.enumerated() {
                if colorAttachment != nil {
                    let layout = subpass.inputAttachments.contains(.color(i)) ? VK_IMAGE_LAYOUT_GENERAL : VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
                    attachmentReferences.append(VkAttachmentReference(attachment: UInt32(attachmentIndices[.color(i)]!), layout: layout))
                } else {
                    attachmentReferences.append(VkAttachmentReference(attachment: VK_ATTACHMENT_UNUSED, layout: VK_IMAGE_LAYOUT_GENERAL))
                }
            }
            subpassDescription.colorAttachmentCount = UInt32(subpass.descriptor.colorAttachments.count)
            
            for inputAttachment in subpass.inputAttachments {
                let layout : VkImageLayout
                switch inputAttachment {
                case .depthStencil:
                    layout = subpass.descriptor.depthAttachment != nil ? VK_IMAGE_LAYOUT_GENERAL : VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL
                case .color(let colorIndex):
                    layout = subpass.descriptor.colorAttachments[colorIndex] != nil ? VK_IMAGE_LAYOUT_GENERAL : VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
                }
                attachmentReferences.append(VkAttachmentReference(attachment: UInt32(attachmentIndices[inputAttachment]!), layout: layout))
            }
            subpassDescription.inputAttachmentCount = UInt32(subpass.inputAttachments.count)
            
            for preserveAttachment in subpass.preserveAttachments {
                preserveAttachmentIndices.append(UInt32(attachmentIndices[preserveAttachment]!))
            }
            subpassDescription.preserveAttachmentCount = UInt32(subpass.preserveAttachments.count)
            
            subpasses.append(subpassDescription)
        }
        
        var attachmentReferencesIndex = 0
        var preserveAttachmentsIndex = 0
        for i in 0..<subpasses.count { // Need to do this in a second loop to ensure the ExpandingBuffers' backing storage doesn't get reallocated by a resize.
            // FIXME: All of the 'UnsafePointer(bitPattern: 0x4)'s are to work around a miscompile. They should be removed once the bug is fixed.

            if descriptor.subpasses[i].descriptor.depthAttachment != nil {
                subpasses[i].pDepthStencilAttachment = UnsafePointer(bitPattern: 0x4)
                subpasses[i].pDepthStencilAttachment = UnsafePointer(attachmentReferences.buffer.advanced(by: attachmentReferencesIndex))
                attachmentReferencesIndex += 1
            }
            
            subpasses[i].pColorAttachments = UnsafePointer(bitPattern: 0x4)
            subpasses[i].pColorAttachments = UnsafePointer(attachmentReferences.buffer.advanced(by: attachmentReferencesIndex))
            attachmentReferencesIndex += Int(subpasses[i].colorAttachmentCount)
            
            subpasses[i].pInputAttachments = UnsafePointer(bitPattern: 0x4)
            subpasses[i].pInputAttachments = UnsafePointer(attachmentReferences.buffer.advanced(by: attachmentReferencesIndex))
            attachmentReferencesIndex += Int(subpasses[i].inputAttachmentCount)
            
            subpasses[i].pPreserveAttachments = UnsafePointer(bitPattern: 0x4)
            subpasses[i].pPreserveAttachments = UnsafePointer(preserveAttachmentIndices.buffer.advanced(by: preserveAttachmentsIndex))
            preserveAttachmentsIndex += Int(subpasses[i].preserveAttachmentCount)
        }
        
        
        var renderPass : VkRenderPass? = nil
        
        let args = (attachmentReferences, preserveAttachmentIndices)
        withExtendedLifetime(args) {
            subpasses.withUnsafeBufferPointer { subpasses in
                createInfo.pSubpasses = subpasses.baseAddress
                createInfo.subpassCount = UInt32(subpasses.count)
                
                attachments.withUnsafeBufferPointer { attachments in
                    createInfo.pAttachments = attachments.baseAddress
                    createInfo.attachmentCount = UInt32(attachments.count)

                    descriptor.dependencies.withUnsafeBufferPointer { dependencies in
                        createInfo.pDependencies = dependencies.baseAddress
                        createInfo.dependencyCount = UInt32(dependencies.count)
                        
                        vkCreateRenderPass(device.vkDevice, &createInfo, nil, &renderPass)
                    }
                }
            }
        }
        
        self.vkPass = renderPass!
    }
    
    deinit {
        vkDestroyRenderPass(self.device.vkDevice, self.vkPass, nil)
    }
}

