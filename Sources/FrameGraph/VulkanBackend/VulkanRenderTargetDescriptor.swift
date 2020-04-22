//
//  CreateInfo.swift
//  VkRenderer
//
//  Created by Joseph Bennett on 2/01/18.
//

#if canImport(Vulkan)
import Vulkan
import FrameGraphCExtras

enum MergeResult {
    case incompatible
    case compatible
    case identical
}

enum RenderTargetAttachmentIndex : Hashable {
    case depthStencil
    case color(Int)
}

final class VulkanSubpass {
    var descriptor : RenderTargetDescriptor
    var index : Int
    
    var inputAttachments = [RenderTargetAttachmentIndex]()
    var preserveAttachments = [RenderTargetAttachmentIndex]()
    
    init(descriptor: RenderTargetDescriptor, index: Int) {
        self.descriptor = descriptor
        self.index = index
    }
    
    func preserve(attachmentIndex: RenderTargetAttachmentIndex) {
        if !self.preserveAttachments.contains(attachmentIndex) {
            if case .depthStencil = attachmentIndex, self.descriptor.depthAttachment != nil || self.descriptor.stencilAttachment != nil {
                return
            }
            if case .color(let index) = attachmentIndex, self.descriptor.colorAttachments[index] != nil {
                return
            }

            self.preserveAttachments.append(attachmentIndex)
        }
    }
    
    func readFrom(attachmentIndex: RenderTargetAttachmentIndex) {
        if !self.inputAttachments.contains(attachmentIndex) {
            self.inputAttachments.append(attachmentIndex)
        }
    }
}

final class VulkanRenderTargetDescriptor: BackendRenderTargetDescriptor {
    var descriptor : RenderTargetDescriptor
    var renderPasses = [RenderPassRecord]()
    
    var colorActions : [(VkAttachmentLoadOp, VkAttachmentStoreOp)] = []

    var depthActions : (VkAttachmentLoadOp, VkAttachmentStoreOp) = (VK_ATTACHMENT_LOAD_OP_DONT_CARE, VK_ATTACHMENT_STORE_OP_DONT_CARE)
    
    var stencilActions : (VkAttachmentLoadOp, VkAttachmentStoreOp) = (VK_ATTACHMENT_LOAD_OP_DONT_CARE, VK_ATTACHMENT_STORE_OP_DONT_CARE)
    
    var subpasses = [VulkanSubpass]()
    private(set) var dependencies = [VkSubpassDependency]()
    
    var initialLayouts = [Texture : VkImageLayout]()
    var finalLayouts = [Texture : VkImageLayout]()
    
    init(renderPass: RenderPassRecord) {
        let drawRenderPass = renderPass.pass as! DrawRenderPass
        self.descriptor = drawRenderPass.renderTargetDescriptor
        self.renderPasses.append(renderPass)
        
        self.subpasses.append(VulkanSubpass(descriptor: drawRenderPass.renderTargetDescriptor, index: 0))
    }
    
    func subpassForPassIndex(_ passIndex: Int) -> VulkanSubpass? {
        if (self.renderPasses.first!.passIndex...self.renderPasses.last!.passIndex).contains(passIndex) {
            return self.subpasses[passIndex - self.renderPasses.first!.passIndex]
        }
        return nil
    }

    func addDependency(_ dependency: VkSubpassDependency) {
        var i = 0
        while i < self.dependencies.count {
            defer { i += 1 }
            if  self.dependencies[i].srcSubpass == dependency.srcSubpass, 
                self.dependencies[i].dstSubpass == dependency.dstSubpass {
                
                self.dependencies[i].srcStageMask |= dependency.srcStageMask
                self.dependencies[i].dstStageMask |= dependency.dstStageMask
                self.dependencies[i].srcAccessMask |= dependency.srcAccessMask
                self.dependencies[i].dstAccessMask |= dependency.dstAccessMask
                self.dependencies[i].dependencyFlags |= dependency.dependencyFlags
                return
            }
        }
        
        self.dependencies.append(dependency)
    }
    
    func tryUpdateDescriptor<D : RenderTargetAttachmentDescriptor>(_ inDescriptor: inout D?, with new: D?) -> MergeResult {
        guard let descriptor = inDescriptor else {
            inDescriptor = new
            return new == nil ? .identical : .compatible
        }
        
        guard let new = new else {
            return .compatible
        }
        
        if new.wantsClear && descriptor.wantsClear {
            return .incompatible
        }
        
        if  descriptor.texture     == new.texture &&
            descriptor.level       == new.level &&
            descriptor.slice       == new.slice &&
            descriptor.depthPlane  == new.depthPlane {
            return .identical
        }
        
        return .incompatible
    }
    
    func tryMerge(withPass passRecord: RenderPassRecord) -> Bool {
        let pass = passRecord.pass as! DrawRenderPass
        
        if pass.renderTargetDescriptor.colorAttachments.count != self.descriptor.colorAttachments.count {
            return false // The render targets must be using the same AttachmentIdentifier and therefore have the same maximum attachment count.
        }
        
        var newDescriptor = descriptor
        
        var mergeResult = MergeResult.identical
        
        for i in 0..<newDescriptor.colorAttachments.count {
            switch self.tryUpdateDescriptor(&newDescriptor.colorAttachments[i], with: pass.renderTargetDescriptor.colorAttachments[i]) {
            case .identical:
                break
            case .incompatible:
                return false
            case .compatible:
                mergeResult = .compatible
            }
        }
        
        switch self.tryUpdateDescriptor(&newDescriptor.depthAttachment, with: pass.renderTargetDescriptor.depthAttachment) {
        case .identical:
            break
        case .incompatible:
            return false
        case .compatible:
            mergeResult = .compatible
        }
        
        switch self.tryUpdateDescriptor(&newDescriptor.stencilAttachment, with: pass.renderTargetDescriptor.stencilAttachment) {
        case .identical:
            break
        case .incompatible:
            return false
        case .compatible:
            mergeResult = .compatible
        }
        
        switch mergeResult {
        case .identical:
            self.subpasses.append(self.subpasses.last!) // They can share the same subpass.
        case .incompatible:
            return false
        case .compatible:
            self.subpasses.append(VulkanSubpass(descriptor: newDescriptor, index: self.subpasses.last!.index + 1))
        }
        
        if newDescriptor.visibilityResultBuffer != nil && pass.renderTargetDescriptor.visibilityResultBuffer != newDescriptor.visibilityResultBuffer {
            return false
        } else {
            newDescriptor.visibilityResultBuffer = pass.renderTargetDescriptor.visibilityResultBuffer
        }
        
        newDescriptor.renderTargetArrayLength = max(newDescriptor.renderTargetArrayLength, pass.renderTargetDescriptor.renderTargetArrayLength)
        
        self.descriptor = newDescriptor
        self.renderPasses.append(passRecord)
        
        return true
    }
    
    func descriptorMergedWithPass(_ pass: RenderPassRecord, resourceUsages: ResourceUsages, storedTextures: inout [Texture]) -> VulkanRenderTargetDescriptor {
        if self.tryMerge(withPass: pass) {
            return self
        } else {
            self.finalise(resourceUsages: resourceUsages, storedTextures: &storedTextures)
            return VulkanRenderTargetDescriptor(renderPass: pass)
        }
    }
    
    private func loadAndStoreActions(for attachment: RenderTargetAttachmentDescriptor, attachmentIndex: RenderTargetAttachmentIndex, resourceUsages: ResourceUsages, storedTextures: inout [Texture]) -> (VkAttachmentLoadOp, VkAttachmentStoreOp) {
        // Logic for usages:
        //
        //
        // If we're not the first usage, we need an external -> internal dependency for the first subpass.
        //
        // If we're not the last usage (or if the texture's persistent), we need an internal -> external dependency for the last subpass.
        // Ideally, we should use a semaphore or event (as appropriate) rather than a barrier; we should therefore handle this in the resource commands.
        //
        // For any usages within our render pass:
        // Add it as a color/depth attachment (as appropriate) to the subpasses that use it.
        // Add it as an input attachment to subpasses that use it.
        // For any subpasses in between, add it as a preserved attachment.
        //
        // Then, figure out dependencies; self-dependency if it's used as both an input and output attachment (implying GENERAL layout),
        // or inter-pass dependencies otherwise.
        
        let isDepthStencil = (attachment is DepthAttachmentDescriptor) || (attachment is StencilAttachmentDescriptor)
        
        let renderPassRange = Range(self.renderPasses.first!.passIndex...self.renderPasses.last!.passIndex)
        assert(renderPassRange.count == self.renderPasses.count)

        let usages = attachment.texture.usages
        var usageIterator = usages.makeIterator()
        var isFirstUsage = !attachment.texture.stateFlags.contains(.initialised)
        var isLastUsage = attachment.texture.flags.intersection([.persistent, .windowHandle]) == [] && 
                          !(attachment.texture.flags.contains(.historyBuffer) && !attachment.texture.stateFlags.contains(.initialised))
        var currentRenderPassIndex = renderPassRange.lowerBound
        
        var isFirstLocalUsage = true
        
        while let usage = usageIterator.next() {
            if !usage.renderPassRecord.isActive { continue }
            
            if usage.renderPassRecord.passIndex < renderPassRange.lowerBound {
                isFirstUsage = false
                continue
            }
            if usage.renderPassRecord.passIndex >= renderPassRange.upperBound {
                if usage.isRead || (usage.type.isRenderTarget && isDepthStencil) {
                    // Using a depth texture as an attachment also implies reading from it.
                    isLastUsage = false
                    break
                } else {
                    continue
                }
            }
            
            let usageSubpass = self.subpassForPassIndex(usage.renderPassRecord.passIndex)

            while self.subpassForPassIndex(currentRenderPassIndex)!.index < usageSubpass!.index {
                if isFirstLocalUsage {
                    currentRenderPassIndex = usage.renderPassRecord.passIndex
                    isFirstLocalUsage = false
                } else {
                    self.subpasses[currentRenderPassIndex - renderPassRange.lowerBound].preserve(attachmentIndex: attachmentIndex)
                    currentRenderPassIndex += 1
                }
            }
            
            assert(usageSubpass!.index == self.subpassForPassIndex(currentRenderPassIndex)!.index)
            
            if usage.type == .read || usage.type == .inputAttachment || usage.type == .readWrite {
                if usage.type == .readWrite {
                    print("Warning: reading from a storage image that is also a render target attachment.")
                }
                self.subpasses[usage.renderPassRecord.passIndex - renderPassRange.lowerBound].readFrom(attachmentIndex: attachmentIndex)
            }

        }
        
        var loadAction : VkAttachmentLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE
        if attachment.wantsClear {
            loadAction = VK_ATTACHMENT_LOAD_OP_CLEAR
        } else if !isFirstUsage && !attachment.fullyOverwritesContents {
            loadAction = VK_ATTACHMENT_LOAD_OP_LOAD
        }
        
        let storeAction : VkAttachmentStoreOp = isLastUsage ? VK_ATTACHMENT_STORE_OP_DONT_CARE : VK_ATTACHMENT_STORE_OP_STORE
        
        if storeAction == VK_ATTACHMENT_STORE_OP_STORE {
            storedTextures.append(attachment.texture)
        }
        
        return (loadAction, storeAction)
    }
    
    func finalise(resourceUsages: ResourceUsages, storedTextures: inout [Texture]) {
        // Compute load and store actions for all attachments.
        self.colorActions = self.descriptor.colorAttachments.enumerated().map { (i, attachment) in
            guard let attachment = attachment else { return (VK_ATTACHMENT_LOAD_OP_DONT_CARE, VK_ATTACHMENT_STORE_OP_DONT_CARE) }
            return self.loadAndStoreActions(for: attachment, attachmentIndex: .color(i), resourceUsages: resourceUsages, storedTextures: &storedTextures)
        }
        
        if let depthAttachment = self.descriptor.depthAttachment {
            self.depthActions = self.loadAndStoreActions(for: depthAttachment, attachmentIndex: .depthStencil, resourceUsages: resourceUsages, storedTextures: &storedTextures)
        }
        
        if let stencilAttachment = self.descriptor.stencilAttachment {
            self.stencilActions = self.loadAndStoreActions(for: stencilAttachment, attachmentIndex: .depthStencil, resourceUsages: resourceUsages, storedTextures: &storedTextures)
        }
    }
}


#endif // canImport(Vulkan)
