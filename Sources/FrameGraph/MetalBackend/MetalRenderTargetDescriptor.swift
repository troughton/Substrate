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
    
    var clearColors: [MTLClearColor] = []
    var clearDepth: Double = 0.0
    var clearStencil: UInt32 = 0
    
    init(renderPass: DrawRenderPass) {
        self.descriptor = renderPass.renderTargetDescriptor
        self.colorActions = .init(repeating: (.dontCare, .dontCare), count: self.descriptor.colorAttachments.count)
        self.updateClearValues(pass: renderPass)
        self.renderPasses.append(renderPass)
    }
    
    convenience init(renderPass: RenderPassRecord) {
        self.init(renderPass: renderPass.pass as! DrawRenderPass)
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
    
    func updateClearValues(pass: DrawRenderPass) {
        let descriptor = pass.renderTargetDescriptor
        
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
    
    func tryMerge(withPass pass: DrawRenderPass) -> Bool {
        if pass.renderTargetDescriptor.size != self.descriptor.size {
            return false // The render targets must be the same size.
        }
        
        var newDescriptor = descriptor
        newDescriptor.colorAttachments.append(contentsOf: repeatElement(nil, count: max(pass.renderTargetDescriptor.colorAttachments.count - descriptor.colorAttachments.count, 0)))
        
        for i in 0..<min(newDescriptor.colorAttachments.count, pass.renderTargetDescriptor.colorAttachments.count) {
            if !self.tryUpdateDescriptor(&newDescriptor.colorAttachments[i], with: pass.renderTargetDescriptor.colorAttachments[i], clearOperation: pass.colorClearOperation(attachmentIndex: i)) {
                return false
            }
        }
        
        if !self.tryUpdateDescriptor(&newDescriptor.depthAttachment, with: pass.renderTargetDescriptor.depthAttachment, clearOperation: pass.depthClearOperation) {
            return false
        }
        
        if !self.tryUpdateDescriptor(&newDescriptor.stencilAttachment, with: pass.renderTargetDescriptor.stencilAttachment, clearOperation: pass.stencilClearOperation) {
            return false
        }
        
        if newDescriptor.visibilityResultBuffer != nil && pass.renderTargetDescriptor.visibilityResultBuffer != newDescriptor.visibilityResultBuffer {
            return false
        } else {
            newDescriptor.visibilityResultBuffer = pass.renderTargetDescriptor.visibilityResultBuffer
        }
        
        self.updateClearValues(pass: pass)
        
        newDescriptor.renderTargetArrayLength = max(newDescriptor.renderTargetArrayLength, pass.renderTargetDescriptor.renderTargetArrayLength)
        
        self.descriptor = newDescriptor
        self.renderPasses.append(pass)
        
        return true
    }
    
    func descriptorMergedWithPass(_ pass: RenderPassRecord, storedTextures: inout [Texture]) -> MetalRenderTargetDescriptor {
        return self.descriptorMergedWithPass(pass.pass as! DrawRenderPass, storedTextures: &storedTextures)
     }
    
    func descriptorMergedWithPass(_ pass: DrawRenderPass, storedTextures: inout [Texture]) -> MetalRenderTargetDescriptor {
        if self.tryMerge(withPass: pass) {
            return self
        } else {
            self.finalise(storedTextures: &storedTextures)
            return MetalRenderTargetDescriptor(renderPass: pass)
        }
    }
    
    private func loadAndStoreActions(for attachment: RenderTargetAttachmentDescriptor, loadAction: MTLLoadAction, storedTextures: inout [Texture]) -> (MTLLoadAction, MTLStoreAction) {
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
        
        var loadAction = loadAction
        if isFirstUsage, loadAction == .load {
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
    
    func finalise(storedTextures: inout [Texture]) {
        // Compute load and store actions for all attachments.
        for (i, attachment) in self.descriptor.colorAttachments.enumerated() {
            guard let attachment = attachment else {
                self.colorActions[i] = (.dontCare, .dontCare)
                continue
            }
            self.colorActions[i] = self.loadAndStoreActions(for: attachment, loadAction: self.colorActions[i].0, storedTextures: &storedTextures)
        }
        
        if let depthAttachment = self.descriptor.depthAttachment {
            self.depthActions = self.loadAndStoreActions(for: depthAttachment, loadAction: self.depthActions.0, storedTextures: &storedTextures)
        } else {
            self.depthActions = (.dontCare, .dontCare)
        }
        
        if let stencilAttachment = self.descriptor.stencilAttachment {
            self.stencilActions = self.loadAndStoreActions(for: stencilAttachment, loadAction: self.stencilActions.0, storedTextures: &storedTextures)
        } else {
            self.stencilActions = (.dontCare, .dontCare)
        }
    }
}

#endif // canImport(Metal)
