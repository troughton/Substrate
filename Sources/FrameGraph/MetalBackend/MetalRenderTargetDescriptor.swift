//
//  RenderTargetDescriptor.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 24/12/17.
//

#if canImport(Metal)

import Metal

final class MetalRenderTargetDescriptor: BackendRenderTargetDescriptor {
    var descriptor : RenderTargetDescriptor
    var renderPasses = [DrawRenderPass]()
    
    var colorActions : [(MTLLoadAction, MTLStoreAction)] = []
    
    var depthActions : (MTLLoadAction, MTLStoreAction) = (.dontCare, .dontCare)
    
    var stencilActions : (MTLLoadAction, MTLStoreAction) = (.dontCare, .dontCare)
    
    init(renderPass: DrawRenderPass) {
        self.descriptor = renderPass.renderTargetDescriptor
        self.renderPasses.append(renderPass)
    }
    
    convenience init(renderPass: RenderPassRecord) {
        self.init(renderPass: renderPass.pass as! DrawRenderPass)
    }
    
    func tryUpdateDescriptor<D : RenderTargetAttachmentDescriptor>(_ desc: inout D?, with new: D?) -> Bool {
        guard let descriptor = desc else {
            desc = new
            return true
        }
        
        guard let new = new else {
            return true
        }
        
        if new.wantsClear && descriptor.wantsClear {
            // We can't clear twice within a render pass.
            // If descriptor was not nil, it must've already had and been using this attachment,
            // so we can't overwrite its load action.
            return false
        }
        
        return  descriptor.texture     == new.texture &&
                descriptor.level       == new.level &&
                descriptor.slice       == new.slice &&
                descriptor.depthPlane  == new.depthPlane
    }
    
    func tryMerge(withPass pass: DrawRenderPass) -> Bool {
        if pass.renderTargetDescriptor.size != self.descriptor.size {
            return false // The render targets must be the same size.
        }
        
        var newDescriptor = descriptor
        
        for i in 0..<min(newDescriptor.colorAttachments.count, pass.renderTargetDescriptor.colorAttachments.count) {
            if !self.tryUpdateDescriptor(&newDescriptor.colorAttachments[i], with: pass.renderTargetDescriptor.colorAttachments[i]) {
                return false
            }
        }
        
        if !self.tryUpdateDescriptor(&newDescriptor.depthAttachment, with: pass.renderTargetDescriptor.depthAttachment) {
            return false
        }
        
        if !self.tryUpdateDescriptor(&newDescriptor.stencilAttachment, with: pass.renderTargetDescriptor.stencilAttachment) {
            return false
        }
        
        if newDescriptor.visibilityResultBuffer != nil && pass.renderTargetDescriptor.visibilityResultBuffer != newDescriptor.visibilityResultBuffer {
            return false
        } else {
            newDescriptor.visibilityResultBuffer = pass.renderTargetDescriptor.visibilityResultBuffer
        }
        
        newDescriptor.renderTargetArrayLength = max(newDescriptor.renderTargetArrayLength, pass.renderTargetDescriptor.renderTargetArrayLength)
        
        self.descriptor = newDescriptor
        self.renderPasses.append(pass)
        
        return true
    }
    
    func descriptorMergedWithPass(_ pass: RenderPassRecord, resourceUsages: ResourceUsages, storedTextures: inout [Texture]) -> MetalRenderTargetDescriptor {
        return self.descriptorMergedWithPass(pass.pass as! DrawRenderPass, resourceUsages: resourceUsages, storedTextures: &storedTextures)
     }
    
    func descriptorMergedWithPass(_ pass: DrawRenderPass, resourceUsages: ResourceUsages, storedTextures: inout [Texture]) -> MetalRenderTargetDescriptor {
        if self.tryMerge(withPass: pass) {
            return self
        } else {
            self.finalise(resourceUsages: resourceUsages, storedTextures: &storedTextures)
            return MetalRenderTargetDescriptor(renderPass: pass)
        }
    }
    
    private func loadAndStoreActions(for attachment: RenderTargetAttachmentDescriptor, resourceUsages: ResourceUsages, storedTextures: inout [Texture]) -> (MTLLoadAction, MTLStoreAction) {
        let usages = attachment.texture.usages
        
        // Are we the first usage?
        guard let firstActiveUsage = usages.firstActiveUsage else {
            return (.dontCare, .dontCare) // We need to have this texture as an attachment, but it's never actually read from or written to.
        }
        
        let isFirstUsage = !attachment.texture.stateFlags.contains(.initialised) && self.renderPasses.contains { $0 === firstActiveUsage.renderPassRecord.pass }
        
        // Is the texture read from after these passes?
        var ourLastUsageIndex = -1
        for (i, usage) in usages.enumerated().reversed() {
            if self.renderPasses.contains(where: { $0 === usage.renderPassRecord.pass }) {
                ourLastUsageIndex = i
                break
            }
        }
        
        assert(ourLastUsageIndex != -1)
        
        var isReadAfterPass : Bool? = nil // nil = as yet unknown
        
        for usage in usages.dropFirst(ourLastUsageIndex + 1) {
            if !usage.renderPassRecord.isActive || usage.stages == .cpuBeforeRender { continue }
            
            switch usage.type {
            case _ where usage.type.isRenderTarget:
                guard let renderPass = usage.renderPassRecord.pass as? DrawRenderPass else { fatalError() }
                let descriptor = renderPass.renderTargetDescriptor
                if let depthAttachment = descriptor.depthAttachment,
                    depthAttachment.texture == attachment.texture,
                    depthAttachment.slice == attachment.slice,
                    depthAttachment.depthPlane == attachment.depthPlane,
                    depthAttachment.level == attachment.level {
                    isReadAfterPass = descriptor.depthAttachment?.clearDepth == nil
                }
                
                if let stencilAttachment = descriptor.stencilAttachment,
                    stencilAttachment.texture == attachment.texture,
                    stencilAttachment.slice == attachment.slice,
                    stencilAttachment.depthPlane == attachment.depthPlane,
                    stencilAttachment.level == attachment.level {
                    isReadAfterPass = descriptor.stencilAttachment?.clearStencil == nil
                }
                
                for a in descriptor.colorAttachments {
                    if let colorAttachment = a, colorAttachment.texture == attachment.texture {
                        if colorAttachment.slice == attachment.slice,
                            colorAttachment.depthPlane == attachment.depthPlane,
                            colorAttachment.level == attachment.level {
                            isReadAfterPass = colorAttachment.clearColor == nil
                        } else {
                            break
                        }
                        
                    }
                }
            case _ where usage.isRead:
                isReadAfterPass = true
            case _ where usage.isWrite:
                continue // We need to be conservative here; it's possible something else may write to the texture but only partially overwrite our data.
            case .unusedArgumentBuffer, .unusedRenderTarget:
                continue
            default:
                fatalError()
            }
            
            if isReadAfterPass != nil { break }
        }
        
        if isReadAfterPass == nil {
            isReadAfterPass = attachment.texture.flags.intersection([.persistent, .windowHandle, .externalOwnership]) != [] ||
                              (attachment.texture.flags.contains(.historyBuffer) && !attachment.texture.stateFlags.contains(.initialised))
        }
        
        var loadAction : MTLLoadAction = .dontCare
        if attachment.wantsClear {
            loadAction = .clear
        } else if !isFirstUsage && !attachment.fullyOverwritesContents {
            loadAction = .load
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
    
    func finalise(resourceUsages: ResourceUsages, storedTextures: inout [Texture]) {
        // Compute load and store actions for all attachments.
        self.colorActions = self.descriptor.colorAttachments.map { attachment in
            guard let attachment = attachment else { return (.dontCare, .dontCare) }
            return self.loadAndStoreActions(for: attachment, resourceUsages: resourceUsages, storedTextures: &storedTextures)
        }
        
        if let depthAttachment = self.descriptor.depthAttachment {
            self.depthActions = self.loadAndStoreActions(for: depthAttachment, resourceUsages: resourceUsages, storedTextures: &storedTextures)
        }
        
        if let stencilAttachment = self.descriptor.stencilAttachment {
            self.stencilActions = self.loadAndStoreActions(for: stencilAttachment, resourceUsages: resourceUsages, storedTextures: &storedTextures)
        }
    }
}

#endif // canImport(Metal)
