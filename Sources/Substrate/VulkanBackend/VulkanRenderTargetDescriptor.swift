//
//  CreateInfo.swift
//  VkRenderer
//
//  Created by Joseph Bennett on 2/01/18.
//

#if canImport(Vulkan)
import Vulkan
import SubstrateCExtras

enum MergeResult {
    case incompatible
    case compatible
    case identical
}

enum RenderTargetAttachmentIndex : Hashable {
    case depthStencil
    case color(Int)
    case colorResolve(Int)
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

// TODO: merge this with the MetalRenderTargetDescriptor class since most of the functionality is identical.
final class VulkanRenderTargetDescriptor: BackendRenderTargetDescriptor {
    var descriptor : RenderTargetDescriptor
    var renderPasses = [RenderPassRecord]()
    
    var colorActions : [(VkAttachmentLoadOp, VkAttachmentStoreOp)] = []
    var depthActions : (VkAttachmentLoadOp, VkAttachmentStoreOp) = (VK_ATTACHMENT_LOAD_OP_DONT_CARE, VK_ATTACHMENT_STORE_OP_DONT_CARE)
    var stencilActions : (VkAttachmentLoadOp, VkAttachmentStoreOp) = (VK_ATTACHMENT_LOAD_OP_DONT_CARE, VK_ATTACHMENT_STORE_OP_DONT_CARE)
    var colorPreviousAndNextUsageCommands : [(previous: Int, next: Int)] = []
    var colorResolvePreviousAndNextUsageCommands : [(previous: Int, next: Int)] = []
    var depthPreviousAndNextUsageCommands = (previous: -1, next: -1)
    var stencilPreviousAndNextUsageCommands = (previous: -1, next: -1)

    var clearColors: [VkClearColorValue] = []
    var clearDepth: Double = 0.0
    var clearStencil: UInt32 = 0

    var subpasses = [VulkanSubpass]()
    private(set) var dependencies = [VkSubpassDependency]()
    
    init(renderPass: RenderPassRecord) {
        let drawRenderPass = renderPass.pass as! DrawRenderPass
        self.descriptor = drawRenderPass.renderTargetDescriptorForActiveAttachments
        self.renderPasses.append(renderPass)
        self.updateClearValues(pass: drawRenderPass, descriptor: self.descriptor)

        self.subpasses.append(VulkanSubpass(descriptor: drawRenderPass.renderTargetDescriptor, index: 0))
    }

    func updateClearValues(pass: DrawRenderPass, descriptor: RenderTargetDescriptor) {
        // Update the clear values.
        let attachmentsToAddCount = max(descriptor.colorAttachments.count - clearColors.count, 0)
        self.clearColors.append(contentsOf: repeatElement(.init(float32: (0, 0, 0, 0)), count: attachmentsToAddCount))
        self.colorActions.append(contentsOf: repeatElement((VK_ATTACHMENT_LOAD_OP_DONT_CARE, VK_ATTACHMENT_STORE_OP_DONT_CARE), count: attachmentsToAddCount))
        
        for i in 0..<descriptor.colorAttachments.count {
            if let attachment = descriptor.colorAttachments[i] {
                switch (pass.colorClearOperation(attachmentIndex: i), self.colorActions[i].0) {
                case (.clear(let color), _):
                    let pixelFormat = attachment.texture.descriptor.pixelFormat
                    if pixelFormat.isUnnormalisedUInt {
                        self.clearColors[i] = VkClearColorValue(uint32: 
                            (UInt32(color.red), 
                            UInt32(color.green), 
                            UInt32(color.blue), 
                            UInt32(color.alpha))
                        )
                    } else if pixelFormat.isUnnormalisedSInt {
                        self.clearColors[i] = VkClearColorValue(int32: 
                            (Int32(color.red), 
                            Int32(color.green), 
                            Int32(color.blue), 
                            Int32(color.alpha))
                        )
                    } else {
                        self.clearColors[i] = VkClearColorValue(float32: 
                            (Float(color.red), 
                            Float(color.green), 
                            Float(color.blue), 
                            Float(color.alpha))
                        )
                    }
                    self.colorActions[i].0 = VK_ATTACHMENT_LOAD_OP_CLEAR
                case (.keep, VK_ATTACHMENT_LOAD_OP_DONT_CARE):
                    self.colorActions[i].0 = VK_ATTACHMENT_LOAD_OP_LOAD
                default:
                    break
                }
            }
        }
        
        if descriptor.depthAttachment != nil {
            switch (pass.depthClearOperation, self.depthActions.0) {
            case (.clear(let depth), _):
                self.clearDepth = depth
                self.depthActions.0 = VK_ATTACHMENT_LOAD_OP_CLEAR
            case (.keep, VK_ATTACHMENT_LOAD_OP_DONT_CARE):
                self.depthActions.0 = VK_ATTACHMENT_LOAD_OP_LOAD
            default:
                break
            }
        }
        
        if descriptor.stencilAttachment != nil {
            switch (pass.stencilClearOperation, self.stencilActions.0) {
            case (.clear(let stencil), _):
                self.clearStencil = stencil
                self.stencilActions.0 = VK_ATTACHMENT_LOAD_OP_CLEAR
            case (.keep, VK_ATTACHMENT_LOAD_OP_DONT_CARE):
                self.stencilActions.0 = VK_ATTACHMENT_LOAD_OP_LOAD
            default:
                break
            }
        }
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
                self.dependencies[i].dstSubpass == dependency.dstSubpass,
                self.dependencies[i].dependencyFlags == dependency.dependencyFlags {
                
                self.dependencies[i].srcStageMask |= dependency.srcStageMask
                self.dependencies[i].dstStageMask |= dependency.dstStageMask
                self.dependencies[i].srcAccessMask |= dependency.srcAccessMask
                self.dependencies[i].dstAccessMask |= dependency.dstAccessMask
                return
            }
        }
        
        self.dependencies.append(dependency)
    }
    
    func tryUpdateDescriptor<D : RenderTargetAttachmentDescriptor>(_ inDescriptor: inout D?, with new: D?, clearOperation: ClearOperation) -> MergeResult {
        guard let descriptor = inDescriptor else {
            inDescriptor = new
            return new == nil ? .identical : .compatible
        }
        
        guard let new = new else {
            return .compatible
        }
        
        if clearOperation.isClear {
            // If descriptor was not nil, it must've already had and been using this attachment,
            // so we can't overwrite its load action.
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
        
        if pass.renderTargetDescriptor.size != self.descriptor.size {
            return false // The render targets must be the same size.
        }
        let passDescriptor = pass.renderTargetDescriptorForActiveAttachments
        
        var newDescriptor = descriptor
        newDescriptor.colorAttachments.append(contentsOf: repeatElement(nil, count: max(passDescriptor.colorAttachments.count - descriptor.colorAttachments.count, 0)))
        
        var mergeResult = MergeResult.identical
        
        for i in 0..<min(newDescriptor.colorAttachments.count, passDescriptor.colorAttachments.count) {
            switch self.tryUpdateDescriptor(&newDescriptor.colorAttachments[i], with: passDescriptor.colorAttachments[i], clearOperation: pass.colorClearOperation(attachmentIndex: i)) {
            case .identical:
                break
            case .incompatible:
                return false
            case .compatible:
                mergeResult = .compatible
            }
        }
        
        if newDescriptor.colorAttachments.count != passDescriptor.colorAttachments.count {
            mergeResult = .compatible
        }
        
        switch self.tryUpdateDescriptor(&newDescriptor.depthAttachment, with: passDescriptor.depthAttachment, clearOperation: pass.depthClearOperation) {
        case .identical:
            break
        case .incompatible:
            return false
        case .compatible:
            mergeResult = .compatible
        }
        
        switch self.tryUpdateDescriptor(&newDescriptor.stencilAttachment, with: passDescriptor.stencilAttachment, clearOperation: pass.stencilClearOperation) {
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
            let lastSubpassIndex = self.subpasses.last!.index
            self.subpasses.append(VulkanSubpass(descriptor: newDescriptor, index: lastSubpassIndex + 1))
            // We'll add the dependencies later.
        }
        
        if newDescriptor.visibilityResultBuffer != nil && passDescriptor.visibilityResultBuffer != newDescriptor.visibilityResultBuffer {
            return false
        } else {
            newDescriptor.visibilityResultBuffer = passDescriptor.visibilityResultBuffer
        }
        
        self.updateClearValues(pass: pass, descriptor: passDescriptor)

        newDescriptor.renderTargetArrayLength = max(newDescriptor.renderTargetArrayLength, passDescriptor.renderTargetArrayLength)
        
        self.descriptor = newDescriptor
        self.renderPasses.append(passRecord)
        
        return true
    }
    
    func descriptorMergedWithPass(_ pass: RenderPassRecord, storedTextures: inout [Texture]) -> VulkanRenderTargetDescriptor {
        if self.tryMerge(withPass: pass) {
            return self
        } else {
            self.finalise(storedTextures: &storedTextures)
            return VulkanRenderTargetDescriptor(renderPass: pass)
        }
    }
    
    private func processLoadAndStoreActions(for attachment: RenderTargetAttachmentDescriptor, attachmentIndex: RenderTargetAttachmentIndex, loadAction: VkAttachmentLoadOp, storedTextures: inout [Texture]) {
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
        
        let texture: Texture
        let slice: Int
        let level: Int
        
        if case .colorResolve = attachmentIndex {
            guard let resolveTexture = attachment.resolveTexture else { return }
            texture = resolveTexture
            slice = attachment.resolveSlice
            level = attachment.resolveLevel
        } else {
            texture = attachment.texture
            slice = attachment.slice
            level = attachment.level
        }
        
        let isDepthStencil = .depthStencil ~= attachmentIndex
        
        let renderPassRange = Range(self.renderPasses.first!.passIndex...self.renderPasses.last!.passIndex)
        assert(renderPassRange.count == self.renderPasses.count)

        let usages = texture.usages
        var usageIterator = usages.makeIterator()
        var isFirstUsage = !texture.stateFlags.contains(.initialised)
        var isLastUsage = texture.flags.intersection([.persistent, .windowHandle]) == [] &&
                          !(texture.flags.contains(.historyBuffer) && !texture.stateFlags.contains(.initialised))
        var currentRenderPassIndex = renderPassRange.lowerBound
        
        var isFirstLocalUsage = true

        var lastUsageBeforeCommandIndex = -1
        var firstUsageAfterCommandIndex = -1
        
        var previousWrite: ResourceUsage? = nil
        var previousWriteSubpass: Int = -1
        
        while let usage = usageIterator.next() {
            if !usage.renderPassRecord.isActive || !usage.activeRange.intersects(textureSlice: slice, level: level, descriptor: texture.descriptor) { continue }
            
            if usage.renderPassRecord.passIndex < renderPassRange.lowerBound {
                isFirstUsage = false
                lastUsageBeforeCommandIndex = usage.commandRange.last!
                continue
            }
            if usage.renderPassRecord.passIndex >= renderPassRange.upperBound {
                if firstUsageAfterCommandIndex < 0 {
                    firstUsageAfterCommandIndex = usage.commandRange.first!
                }
                if usage.isRead || (usage.type.isRenderTarget && isDepthStencil) {
                    // Using a depth texture as an attachment also implies reading from it.
                    isLastUsage = false
                    break
                } else {
                    continue
                }
            }
            
            let usageSubpass = self.subpassForPassIndex(usage.renderPassRecord.passIndex)!

            while self.subpassForPassIndex(currentRenderPassIndex)!.index < usageSubpass.index {
                if isFirstLocalUsage {
                    currentRenderPassIndex = usage.renderPassRecord.passIndex
                    isFirstLocalUsage = false
                } else {
                    self.subpasses[currentRenderPassIndex - renderPassRange.lowerBound].preserve(attachmentIndex: attachmentIndex)
                    currentRenderPassIndex += 1
                }
            }
            
            assert(usageSubpass.index == self.subpassForPassIndex(currentRenderPassIndex)!.index)
            
            if usage.type == .read || usage.type == .inputAttachment || usage.type == .readWrite {
                if usage.type == .readWrite {
                    print("Warning: reading from a storage image that is also a render target attachment.")
                }
                self.subpasses[usage.renderPassRecord.passIndex - renderPassRange.lowerBound].readFrom(attachmentIndex: attachmentIndex)
            }
            
            if let previousWrite = previousWrite {
                var dependency = VkSubpassDependency()
                dependency.dependencyFlags = VK_DEPENDENCY_BY_REGION_BIT.rawValue
                dependency.srcSubpass = UInt32(previousWriteSubpass)
                dependency.dstSubpass = UInt32(usageSubpass.index)
                dependency.srcStageMask = previousWrite.type.shaderStageMask(isDepthOrStencil: isDepthStencil, stages: previousWrite.stages).rawValue
                dependency.srcAccessMask = previousWrite.type.accessMask(isDepthOrStencil: isDepthStencil).rawValue
                dependency.dstStageMask = usage.type.shaderStageMask(isDepthOrStencil: isDepthStencil, stages: usage.stages).rawValue
                dependency.dstAccessMask = usage.type.accessMask(isDepthOrStencil: isDepthStencil).rawValue
                self.addDependency(dependency)
            }

            if usage.type.isWrite {
                previousWrite = usage
                previousWriteSubpass = usageSubpass.index
            }
        }

        var loadAction = loadAction
        if isFirstUsage, loadAction == VK_ATTACHMENT_LOAD_OP_LOAD {
            loadAction = VK_ATTACHMENT_LOAD_OP_DONT_CARE
        }
        
        let storeAction : VkAttachmentStoreOp = isLastUsage ? VK_ATTACHMENT_STORE_OP_DONT_CARE : VK_ATTACHMENT_STORE_OP_STORE
        
        if storeAction == VK_ATTACHMENT_STORE_OP_STORE {
            storedTextures.append(attachment.texture)
        }
        
        switch attachmentIndex {
        case .color(let index):
            self.colorActions[index] = (loadAction, storeAction)
            self.colorPreviousAndNextUsageCommands[index] = (lastUsageBeforeCommandIndex, firstUsageAfterCommandIndex)
        case .colorResolve(let index):
            self.colorResolvePreviousAndNextUsageCommands[index] = (lastUsageBeforeCommandIndex, firstUsageAfterCommandIndex)
        case .depthStencil where attachment is DepthAttachmentDescriptor:
            self.depthActions = (loadAction, storeAction)
            self.depthPreviousAndNextUsageCommands = (lastUsageBeforeCommandIndex, firstUsageAfterCommandIndex)
        case .depthStencil:
            self.stencilActions = (loadAction, storeAction)
            self.stencilPreviousAndNextUsageCommands = (lastUsageBeforeCommandIndex, firstUsageAfterCommandIndex)
        }
    }
    
    func finalise(storedTextures: inout [Texture]) {
        self.dependencies.reserveCapacity(self.subpasses.count + 1) // One before each subpass and one after all of them.
        
        // Compute load and store actions for all attachments.
        self.colorPreviousAndNextUsageCommands = .init(repeating: (-1, -1), count: self.descriptor.colorAttachments.count)
        self.colorResolvePreviousAndNextUsageCommands = .init(repeating: (-1, -1), count: self.descriptor.colorAttachments.count)
        for (i, attachment) in self.descriptor.colorAttachments.enumerated() {
            guard let attachment = attachment else { continue }
            self.processLoadAndStoreActions(for: attachment, attachmentIndex: .color(i), loadAction: self.colorActions[i].0, storedTextures: &storedTextures)
            if attachment.resolveTexture != nil {
                self.processLoadAndStoreActions(for: attachment, attachmentIndex: .colorResolve(i), loadAction: VK_ATTACHMENT_LOAD_OP_DONT_CARE, storedTextures: &storedTextures)
            }
        }
        
        if let depthAttachment = self.descriptor.depthAttachment {
            self.processLoadAndStoreActions(for: depthAttachment, attachmentIndex: .depthStencil, loadAction: self.depthActions.0, storedTextures: &storedTextures)
        }
        
        if let stencilAttachment = self.descriptor.stencilAttachment {
            self.processLoadAndStoreActions(for: stencilAttachment, attachmentIndex: .depthStencil, loadAction: self.stencilActions.0, storedTextures: &storedTextures)
        }
    }
}


#endif // canImport(Vulkan)
