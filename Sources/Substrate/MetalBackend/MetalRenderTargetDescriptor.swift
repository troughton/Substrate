//
//  RenderTargetDescriptor.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 24/12/17.
//

#if canImport(Metal)

import Metal

final class MetalRenderTargetDescriptor: BackendRenderTargetDescriptor, @unchecked Sendable {
    var descriptor : RenderTargetsDescriptor
    private var renderPasses = [(pass: DrawRenderPass, passIndex: Int)]()
    
    var colorActions : [(MTLLoadAction, MTLStoreAction)] = []
    var depthActions : (MTLLoadAction, MTLStoreAction) = (.dontCare, .dontCare)
    var stencilActions : (MTLLoadAction, MTLStoreAction) = (.dontCare, .dontCare)
    
    var clearColors: [MTLClearColor] = []
    var clearDepth: Double = 0.0
    var clearStencil: UInt32 = 0
    
    init(renderPass: DrawRenderPass, passIndex: Int) {
        self.descriptor = renderPass.renderTargetsDescriptorForActiveAttachments(passIndex: passIndex)
        self.colorActions = .init(repeating: (.dontCare, .dontCare), count: self.descriptor.colorAttachments.count)
        self.updateClearValues(pass: renderPass, descriptor: self.descriptor)
        self.renderPasses.append((renderPass, passIndex))
    }
    
    convenience init(renderPass: RenderPassRecord) {
        self.init(renderPass: renderPass.pass as! DrawRenderPass, passIndex: renderPass.passIndex)
    }
    
    func tryUpdateDescriptor<D : RenderTargetAttachmentDescriptor>(_ desc: inout D?, with new: D?, clearOperation: ClearOperation) -> Bool {
        guard let descriptor = desc else {
            desc = new
            return true
        }
        
        guard let new = new else {
            return true
        }
        
        if clearOperation.isClear {
            // If descriptor was not nil, it must've already had and been using this attachment,
            // so we can't overwrite its load action.
            return false
        }
        
        return  descriptor.texture     == new.texture &&
                descriptor.level       == new.level &&
                descriptor.slice       == new.slice &&
                descriptor.depthPlane  == new.depthPlane
    }
    
    func updateClearValues(pass: DrawRenderPass, descriptor: RenderTargetsDescriptor) {
        // Update the clear values.
        self.clearColors.append(contentsOf: repeatElement(.init(), count: max(descriptor.colorAttachments.count - clearColors.count, 0)))
        self.colorActions.append(contentsOf: repeatElement((.dontCare, .dontCare), count: max(descriptor.colorAttachments.count - colorActions.count, 0)))
        
        for i in 0..<descriptor.colorAttachments.count {
            if descriptor.colorAttachments[i] != nil {
                switch (pass.colorClearOperation(attachmentIndex: i), self.colorActions[i].0) {
                case (.clear(let color), _):
                    self.clearColors[i] = MTLClearColor(color)
                    self.colorActions[i].0 = .clear
                case (.keep, .dontCare):
                    self.colorActions[i].0 = .load
                default:
                    break
                }
            }
        }
        
        if descriptor.depthAttachment != nil {
            switch (pass.depthClearOperation, self.depthActions.0) {
            case (.clear(let depth), _):
                self.clearDepth = depth
                self.depthActions.0 = .clear
            case (.keep, .dontCare):
                self.depthActions.0 = .load
            default:
                break
            }
        }
        
        if descriptor.stencilAttachment != nil {
            switch (pass.stencilClearOperation, self.stencilActions.0) {
            case (.clear(let stencil), _):
                self.clearStencil = stencil
                self.stencilActions.0 = .clear
            case (.keep, .dontCare):
                self.stencilActions.0 = .load
            default:
                break
            }
        }
    }
    
    func tryMerge(withPass pass: DrawRenderPass, passIndex: Int) -> Bool {
        if pass.renderTargetsDescriptor.size != self.descriptor.size {
            return false // The render targets must be the same size.
        }
        
        let passDescriptor = pass.renderTargetsDescriptorForActiveAttachments(passIndex: passIndex)
        
        var newDescriptor = descriptor
        
        for i in 0..<min(newDescriptor.colorAttachments.count, passDescriptor.colorAttachments.count) {
            if !self.tryUpdateDescriptor(&newDescriptor.colorAttachments[i], with: passDescriptor.colorAttachments[i], clearOperation: pass.colorClearOperation(attachmentIndex: i)) {
                return false
            }
        }
        
        if !self.tryUpdateDescriptor(&newDescriptor.depthAttachment, with: passDescriptor.depthAttachment, clearOperation: pass.depthClearOperation) {
            return false
        }
        
        if !self.tryUpdateDescriptor(&newDescriptor.stencilAttachment, with: passDescriptor.stencilAttachment, clearOperation: pass.stencilClearOperation) {
            return false
        }
        
        if newDescriptor.visibilityResultBuffer != nil && passDescriptor.visibilityResultBuffer != newDescriptor.visibilityResultBuffer {
            return false
        } else {
            newDescriptor.visibilityResultBuffer = passDescriptor.visibilityResultBuffer
        }
        
        self.updateClearValues(pass: pass, descriptor: passDescriptor)
        
        newDescriptor.renderTargetArrayLength = max(newDescriptor.renderTargetArrayLength, passDescriptor.renderTargetArrayLength)
        
        self.descriptor = newDescriptor
        self.renderPasses.append((pass, passIndex))
        
        return true
    }
    
    func descriptorMergedWithPass(_ pass: RenderPassRecord, allRenderPasses: [RenderPassRecord], storedTextures: inout [Texture]) -> MetalRenderTargetDescriptor {
        return self.descriptorMergedWithPass(pass.pass as! DrawRenderPass, passIndex: pass.passIndex, allRenderPasses: allRenderPasses, storedTextures: &storedTextures)
     }
    
    func descriptorMergedWithPass(_ pass: DrawRenderPass, passIndex: Int, allRenderPasses: [RenderPassRecord], storedTextures: inout [Texture]) -> MetalRenderTargetDescriptor {
        if self.tryMerge(withPass: pass, passIndex: passIndex) {
            return self
        } else {
            self.finalise(allRenderPasses: allRenderPasses, storedTextures: &storedTextures)
            return MetalRenderTargetDescriptor(renderPass: pass, passIndex: passIndex)
        }
    }
    
    private func loadAndStoreActions<Attachment: RenderTargetAttachmentDescriptor>(for attachment: Attachment, loadAction: MTLLoadAction, allRenderPasses: [RenderPassRecord], storedTextures: inout [Texture]) -> (MTLLoadAction, MTLStoreAction) {
        let usages = attachment.texture.usages
        
        var isFirstUsage: Bool? = nil
        var isReadAfterPass : Bool? = nil // nil = as yet unknown
        var isProcessingUsagesAfterEncoder = false
        
        for usage in usages {
            if usage.gpuType.isEmpty || !usage.activeRange.intersects(textureSlice: attachment.slice, level: attachment.level, descriptor: attachment.texture.descriptor) { continue }
            
            let isUsageInEncoder = usage.type.isRenderTarget && self.renderPasses.contains(where: { $0.passIndex == usage.passIndex })
            
            if isFirstUsage == nil {
                if !attachment.texture.stateFlags.contains(.initialised), isUsageInEncoder {
                    isFirstUsage = true
                } else {
                    isFirstUsage = false
                }
            }
            
            isProcessingUsagesAfterEncoder = isUsageInEncoder || isProcessingUsagesAfterEncoder
            
            if isUsageInEncoder || !isProcessingUsagesAfterEncoder { continue }
            
            switch usage.gpuType {
            case []:
                continue
            case _ where !usage.gpuType.intersection([.colorAttachment, .depthStencilAttachment]).isEmpty:
                guard let renderPass = allRenderPasses[usage.passIndex].pass as? DrawRenderPass else { fatalError() }
                let descriptor = renderPass.renderTargetsDescriptor
                if let depthAttachment = descriptor.depthAttachment,
                    depthAttachment.texture == attachment.texture,
                    depthAttachment.slice == attachment.slice,
                    depthAttachment.depthPlane == attachment.depthPlane,
                    depthAttachment.level == attachment.level {
                    isReadAfterPass = renderPass.depthClearOperation.isKeep
                }
                
                if let stencilAttachment = descriptor.stencilAttachment,
                    stencilAttachment.texture == attachment.texture,
                    stencilAttachment.slice == attachment.slice,
                    stencilAttachment.depthPlane == attachment.depthPlane,
                    stencilAttachment.level == attachment.level {
                    isReadAfterPass = renderPass.stencilClearOperation.isKeep
                }
                
                for (i, a) in descriptor.colorAttachments.enumerated() {
                    if let colorAttachment = a, colorAttachment.texture == attachment.texture {
                        if colorAttachment.slice == attachment.slice,
                            colorAttachment.depthPlane == attachment.depthPlane,
                            colorAttachment.level == attachment.level {
                            isReadAfterPass = renderPass.colorClearOperation(attachmentIndex: i).isKeep
                        } else {
                            break
                        }
                        
                    }
                }
            case _ where usage.type.isRead:
                isReadAfterPass = true
            case _ where usage.type.isWrite:
                continue // We need to be conservative here; it's possible something else may write to the texture but only partially overwrite our data.
            default:
                fatalError()
            }
            
            if isReadAfterPass != nil { break }
        }
        
        if isReadAfterPass == nil {
            isReadAfterPass = attachment.texture.flags.intersection([.persistent, .windowHandle, .externalOwnership]) != [] ||
                              (attachment.texture.flags.contains(.historyBuffer) && !attachment.texture.stateFlags.contains(.initialised))
        }
        
        var loadAction = loadAction
        if isFirstUsage ?? true, loadAction == .load {
            loadAction = .dontCare
        }
        
        var storeAction : MTLStoreAction = isReadAfterPass! ? .store : .dontCare
        if let resolveTexture = attachment.resolveTexture {
            storeAction = (storeAction == .store) ? .storeAndMultisampleResolve : .multisampleResolve
            storedTextures.append(resolveTexture)
        }
        
        if storeAction == .store || storeAction == .storeAndMultisampleResolve {
            storedTextures.append(attachment.texture)
        }
        
        return (loadAction, storeAction)
    }
    
    func finalise(allRenderPasses: [RenderPassRecord], storedTextures: inout [Texture]) {
        // Compute load and store actions for all attachments.
        for (i, attachment) in self.descriptor.colorAttachments.enumerated() {
            guard let attachment = attachment else {
                self.colorActions[i] = (.dontCare, .dontCare)
                continue
            }
            self.colorActions[i] = self.loadAndStoreActions(for: attachment, loadAction: self.colorActions[i].0, allRenderPasses: allRenderPasses, storedTextures: &storedTextures)
        }
        
        if let depthAttachment = self.descriptor.depthAttachment {
            self.depthActions = self.loadAndStoreActions(for: depthAttachment, loadAction: self.depthActions.0, allRenderPasses: allRenderPasses, storedTextures: &storedTextures)
        } else {
            self.depthActions = (.dontCare, .dontCare)
        }
        
        if let stencilAttachment = self.descriptor.stencilAttachment {
            self.stencilActions = self.loadAndStoreActions(for: stencilAttachment, loadAction: self.stencilActions.0, allRenderPasses: allRenderPasses, storedTextures: &storedTextures)
        } else {
            self.stencilActions = (.dontCare, .dontCare)
        }
        
        self.renderPasses.removeAll()
    }
}

#endif // canImport(Metal)
