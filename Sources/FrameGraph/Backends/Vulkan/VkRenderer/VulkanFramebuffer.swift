//
//  VulkanFramebuffer.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 14/01/18.
//

import RenderAPI
import CVkRenderer

public enum AttachmentIndex {
    case depth
    case stencil
    case color(Int)
}

public class VulkanFramebuffer {
    let device : VulkanDevice
    let framebuffer : VkFramebuffer
    
    let attachments : [(AttachmentIndex, VulkanImageView)]
    
    init(descriptor: VulkanRenderTargetDescriptor, renderPass: VkRenderPass, device: VulkanDevice, resourceRegistry: ResourceRegistry) {
        self.device = device
        
        let renderTargetSize = descriptor.descriptor.size
    
        var createInfo = VkFramebufferCreateInfo()
        createInfo.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO
        createInfo.renderPass = renderPass
        createInfo.width = UInt32(renderTargetSize.width)
        createInfo.height = UInt32(renderTargetSize.height)
        createInfo.layers = UInt32(max(descriptor.descriptor.renderTargetArrayLength, 1))
        
        var attachments = [(AttachmentIndex, VulkanImageView)]()
        if let depthAttachment = descriptor.descriptor.depthAttachment {
            let image = resourceRegistry[depthAttachment.texture]!
            attachments.append((.depth, image.viewForAttachment(descriptor: depthAttachment)))
        }
        
        if let stencilAttachment = descriptor.descriptor.stencilAttachment, stencilAttachment.texture != descriptor.descriptor.depthAttachment?.texture {
            let image = resourceRegistry[stencilAttachment.texture]!
            attachments.append((.stencil, image.viewForAttachment(descriptor: stencilAttachment)))
        }
        
        for (i, attachment) in descriptor.descriptor.colorAttachments.enumerated() {
            guard let attachment = attachment else { continue }
            
            let image = resourceRegistry[attachment.texture]!
            attachments.append((.color(i), image.viewForAttachment(descriptor: attachment)))
        }
        
        self.attachments = attachments
        
        var framebuffer : VkFramebuffer? = nil
        let imageViews = attachments.map { $0.1.vkView as VkImageView? }
        imageViews.withUnsafeBufferPointer { imageViews in
            createInfo.pAttachments = imageViews.baseAddress
            createInfo.attachmentCount = UInt32(imageViews.count)
            
            vkCreateFramebuffer(device.vkDevice, &createInfo, nil, &framebuffer)
        }
        
        self.framebuffer = framebuffer!
    }
    
    deinit {
        vkDestroyFramebuffer(self.device.vkDevice, self.framebuffer, nil)
    }
}
