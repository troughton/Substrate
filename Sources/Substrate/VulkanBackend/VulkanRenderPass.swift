//
//  VulkanRenderPass.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 16/01/18.
//

#if canImport(Vulkan)
import Vulkan
import SubstrateCExtras
import SubstrateUtilities

class VulkanRenderPass {
    let device : VulkanDevice
    let vkPass : VkRenderPass
    let descriptor : VulkanRenderTargetDescriptor

    let attachmentCount: Int
    
    init(device: VulkanDevice, descriptor: VulkanRenderTargetDescriptor, resourceMap: FrameResourceMap<VulkanBackend>) async throws {
        self.device = device
        self.descriptor = descriptor
        
        let renderPassInfo = descriptor.compatibleRenderPass!
        
        var createInfo = VkRenderPassCreateInfo()
        createInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO
        
        var attachments = [VkAttachmentDescription]()
                
        // Depth-stencil attachments first, then colour.
        
        if let depthAttachment = descriptor.descriptor.depthAttachment {
            var attachmentDescription = VkAttachmentDescription(descriptor: depthAttachment.texture.descriptor, renderTargetsDescriptor: depthAttachment, depthActions: descriptor.depthActions, stencilActions: descriptor.stencilActions)
            let (previousCommandIndex, nextCommandIndex) = descriptor.depthPreviousAndNextUsageCommands
            let (initialLayout, finalLayout) = try await resourceMap.renderTargetTexture(depthAttachment.texture).image.renderPassLayouts(previousCommandIndex: previousCommandIndex, nextCommandIndex: nextCommandIndex, slice: depthAttachment.slice, level: depthAttachment.level, texture: depthAttachment.texture)
                 
            attachmentDescription.initialLayout = initialLayout
            attachmentDescription.finalLayout = finalLayout
            attachments.append(attachmentDescription)
        } else {
            assert(descriptor.descriptor.stencilAttachment == nil, "Stencil attachments without depth are currently unimplemented.")
        }
        
        for (i, (colorAttachment, actions)) in zip(descriptor.descriptor.colorAttachments, descriptor.colorActions).enumerated() {
            guard let colorAttachment = colorAttachment else { continue }
            var attachmentDescription = VkAttachmentDescription(descriptor: colorAttachment.texture.descriptor, renderTargetsDescriptor: colorAttachment, actions: actions)
            let (previousCommandIndex, nextCommandIndex) = descriptor.colorPreviousAndNextUsageCommands[i]
            let (initialLayout, finalLayout) = try await resourceMap.renderTargetTexture(colorAttachment.texture).image.renderPassLayouts(previousCommandIndex: previousCommandIndex, nextCommandIndex: nextCommandIndex, slice: colorAttachment.slice, level: colorAttachment.level, texture: colorAttachment.texture)

            attachmentDescription.initialLayout = initialLayout
            attachmentDescription.finalLayout = finalLayout
            attachments.append(attachmentDescription)
            
            if let resolveTexture = colorAttachment.resolveTexture {
                var attachmentDescription = VkAttachmentDescription(descriptor: resolveTexture.descriptor, renderTargetsDescriptor: colorAttachment, actions: (VK_ATTACHMENT_LOAD_OP_DONT_CARE, VK_ATTACHMENT_STORE_OP_STORE))
                let (previousCommandIndex, nextCommandIndex) = descriptor.colorResolvePreviousAndNextUsageCommands[i]
                let (initialLayout, finalLayout) = try await  resourceMap.renderTargetTexture(resolveTexture).image.renderPassLayouts(previousCommandIndex: previousCommandIndex, nextCommandIndex: nextCommandIndex, slice: colorAttachment.resolveSlice, level: colorAttachment.resolveLevel, texture: resolveTexture)

                attachmentDescription.initialLayout = initialLayout
                attachmentDescription.finalLayout = finalLayout
                attachments.append(attachmentDescription)
            }
        }
        
        assert(attachments.count == renderPassInfo.attachments.count)
        assert(zip(attachments, renderPassInfo.attachments).allSatisfy({ $0.format == VkFormat(pixelFormat: $1.format) && $0.samples.rawValue == $1.sampleCount }))
        
        var subpasses = [VkSubpassDescription]()
        
        // Compute the attachment count in advance so we don't resize the attachment reference buffers.
        var attachmentReferenceCount = 0
        var preserveAttachmentCount = 0
        var resolveAttachmentCount = 0

        do {
            var previousSubpass : VulkanSubpass? = nil
            for subpass in descriptor.subpasses {
                if subpass === previousSubpass { continue }
                defer { previousSubpass = subpass }

                attachmentReferenceCount += (subpass.descriptor.depthAttachment != nil || subpass.descriptor.stencilAttachment != nil) ? 1 : 0
                attachmentReferenceCount += subpass.descriptor.colorAttachments.count
                attachmentReferenceCount += subpass.inputAttachments.count
                preserveAttachmentCount += subpass.preserveAttachments.count
                resolveAttachmentCount += subpass.descriptor.colorAttachments.count
            }
        }

        let attachmentReferences = ExpandingBuffer<VkAttachmentReference>(initialCapacity: attachmentReferenceCount)
        let preserveAttachmentIndices = ExpandingBuffer<UInt32>(initialCapacity: preserveAttachmentCount)
        let resolveAttachmentReferences = ExpandingBuffer<VkAttachmentReference>(initialCapacity: resolveAttachmentCount)

        var previousSubpass : VulkanSubpass? = nil
        for subpass in descriptor.subpasses {
            if subpass === previousSubpass { continue }
            defer { previousSubpass = subpass }
            
            let referenceSubpass = renderPassInfo.subpasses[subpasses.count]
            
            var subpassDescription = VkSubpassDescription()
            subpassDescription.flags = referenceSubpass.flags
            subpassDescription.pipelineBindPoint = referenceSubpass.bindPoint

            if subpass.descriptor.depthAttachment != nil || subpass.descriptor.stencilAttachment != nil {
                let layout = subpass.inputAttachments.contains(.depthStencil) ? VK_IMAGE_LAYOUT_GENERAL : VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
                subpassDescription.pDepthStencilAttachment = UnsafePointer(attachmentReferences.buffer.advanced(by: attachmentReferences.count))
                attachmentReferences.append(VkAttachmentReference(attachment: referenceSubpass.depthStencilAttachmentIndex, layout: layout))
            }
            
            // TODO: handle depth resolve attachments using VK_KHR_depth_stencil_resolve: https://www.khronos.org/assets/uploads/developers/library/2019-gdc/Vulkan-Depth-Stencil-Resolve-GDC-Mar19.pdf
            
            subpassDescription.pColorAttachments = UnsafePointer(attachmentReferences.buffer.advanced(by: attachmentReferences.count))
            subpassDescription.pResolveAttachments = UnsafePointer(resolveAttachmentReferences.buffer?.advanced(by: resolveAttachmentReferences.count))

            for (i, colorAttachment) in subpass.descriptor.colorAttachments.enumerated() {
                if colorAttachment != nil {
                    let layout = subpass.inputAttachments.contains(.color(i)) ? VK_IMAGE_LAYOUT_GENERAL : VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
                    attachmentReferences.append(VkAttachmentReference(attachment: referenceSubpass.colorAttachmentIndices[i], layout: layout))
                } else {
                    attachmentReferences.append(VkAttachmentReference(attachment: VK_ATTACHMENT_UNUSED, layout: VK_IMAGE_LAYOUT_GENERAL))
                }
                resolveAttachmentReferences.append(VkAttachmentReference(attachment: referenceSubpass.resolveAttachmentIndices[i], layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL))
            }
            subpassDescription.colorAttachmentCount = UInt32(subpass.descriptor.colorAttachments.count)
            
            subpassDescription.pInputAttachments = UnsafePointer(attachmentReferences.buffer.advanced(by: attachmentReferences.count))
            for (i, inputAttachment) in subpass.inputAttachments.enumerated() {
                let layout : VkImageLayout
                switch inputAttachment {
                case .depthStencil:
                    layout = subpass.descriptor.depthAttachment != nil ? VK_IMAGE_LAYOUT_GENERAL : VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL
                case .color(let colorIndex):
                    layout = subpass.descriptor.colorAttachments[colorIndex] != nil ? VK_IMAGE_LAYOUT_GENERAL : VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
                case .colorResolve:
                    fatalError()
                }
                attachmentReferences.append(VkAttachmentReference(attachment: referenceSubpass.inputAttachmentIndices[i], layout: layout))
            }
            subpassDescription.inputAttachmentCount = UInt32(subpass.inputAttachments.count)
            
            subpassDescription.pPreserveAttachments = UnsafePointer(preserveAttachmentIndices.buffer?.advanced(by: preserveAttachmentIndices.count))
            for preserveAttachment in subpass.preserveAttachments {
                preserveAttachmentIndices.append(UInt32(descriptor.attachmentIndices[preserveAttachment]!))
            }
            subpassDescription.preserveAttachmentCount = UInt32(subpass.preserveAttachments.count)
            
            subpasses.append(subpassDescription)
        }
        assert(attachmentReferenceCount == attachmentReferences.count)
        assert(preserveAttachmentCount == preserveAttachmentIndices.count)
        
        self.attachmentCount = attachments.count
        
        var renderPass : VkRenderPass? = nil
        
        let args = (attachmentReferences, preserveAttachmentIndices)
        withExtendedLifetime(args) {
            subpasses.withUnsafeBufferPointer { subpasses in
                createInfo.pSubpasses = subpasses.baseAddress
                createInfo.subpassCount = UInt32(subpasses.count)
                
                attachments.withUnsafeBufferPointer { attachments in
                    createInfo.pAttachments = attachments.baseAddress
                    createInfo.attachmentCount = UInt32(attachments.count)

                    renderPassInfo.dependencies.withUnsafeBufferPointer { dependencies in
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

#endif // canImport(Vulkan)
