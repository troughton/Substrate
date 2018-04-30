//
//  Descriptors.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 24/12/17.
//

import RenderAPI
import FrameGraph
import Metal


extension MTLStencilDescriptor {
    convenience init(_ descriptor : StencilDescriptor) {
        self.init()
        
        self.stencilCompareFunction = MTLCompareFunction(descriptor.stencilCompareFunction)
        self.stencilFailureOperation = MTLStencilOperation(descriptor.stencilFailureOperation)
        self.depthFailureOperation = MTLStencilOperation(descriptor.depthFailureOperation)
        self.depthStencilPassOperation = MTLStencilOperation(descriptor.depthStencilPassOperation)
        self.readMask = descriptor.readMask
        self.writeMask = descriptor.writeMask
    }
}

extension MTLDepthStencilDescriptor {
    convenience init(_ descriptor : DepthStencilDescriptor) {
        self.init()
        
        self.backFaceStencil = MTLStencilDescriptor(descriptor.backFaceStencil)
        self.frontFaceStencil = MTLStencilDescriptor(descriptor.frontFaceStencil)
        
        self.depthCompareFunction = MTLCompareFunction(descriptor.depthCompareFunction)
        self.isDepthWriteEnabled = descriptor.isDepthWriteEnabled
    }
}

extension MTLSamplerDescriptor {
    convenience init(_ descriptor: SamplerDescriptor) {
        self.init()
        
        self.minFilter = MTLSamplerMinMagFilter(descriptor.minFilter)
        self.magFilter = MTLSamplerMinMagFilter(descriptor.magFilter)
        self.mipFilter = MTLSamplerMipFilter(descriptor.mipFilter)
        self.maxAnisotropy = descriptor.maxAnisotropy
        self.sAddressMode = MTLSamplerAddressMode(descriptor.sAddressMode)
        self.tAddressMode = MTLSamplerAddressMode(descriptor.tAddressMode)
        self.rAddressMode = MTLSamplerAddressMode(descriptor.rAddressMode)
        self.borderColor = MTLSamplerBorderColor(descriptor.borderColor)
        self.normalizedCoordinates = descriptor.normalizedCoordinates
        self.lodMinClamp = descriptor.lodMinClamp
        self.lodMaxClamp = descriptor.lodMaxClamp
        self.compareFunction = MTLCompareFunction(descriptor.compareFunction)
    }
}


extension MTLRenderPassAttachmentDescriptor {
    func fill(from descriptor: RenderTargetAttachmentDescriptor, actions: (MTLLoadAction, MTLStoreAction), resourceRegistry: ResourceRegistry, textureUsages: [Texture : MTLTextureUsage]) {
        
        let texture = descriptor.texture
        self.texture = resourceRegistry.allocateTextureIfNeeded(texture, usage: textureUsages[texture] ?? MTLTextureUsage(texture.descriptor.usageHint))
        self.level = descriptor.level
        self.slice = descriptor.slice
        self.depthPlane = descriptor.depthPlane
        
        self.resolveTexture = nil
        self.resolveLevel = 0
        self.resolveSlice = 0
        self.resolveDepthPlane = 0
        
        self.loadAction = actions.0
        self.storeAction = actions.1
    }
}

extension MTLRenderPassColorAttachmentDescriptor {
    convenience init(_ descriptor: RenderTargetColorAttachmentDescriptor, actions: (MTLLoadAction, MTLStoreAction), resourceRegistry: ResourceRegistry, textureUsages: [Texture : MTLTextureUsage]) {
        self.init()
        self.fill(from: descriptor, actions: actions, resourceRegistry: resourceRegistry, textureUsages: textureUsages)
        
        if let clearColor = descriptor.clearColor {
            self.clearColor = MTLClearColor(clearColor)
        }
    }
}

extension MTLRenderPassDepthAttachmentDescriptor {
    convenience init(_ descriptor: RenderTargetDepthAttachmentDescriptor, actions: (MTLLoadAction, MTLStoreAction), resourceRegistry: ResourceRegistry, textureUsages: [Texture : MTLTextureUsage]) {
        self.init()
        self.fill(from: descriptor, actions: actions, resourceRegistry: resourceRegistry, textureUsages: textureUsages)
        
        if let clearDepth = descriptor.clearDepth {
            self.clearDepth = clearDepth
        }
        
    }
}

extension MTLRenderPassStencilAttachmentDescriptor {
    convenience init(_ descriptor: RenderTargetStencilAttachmentDescriptor, actions: (MTLLoadAction, MTLStoreAction), resourceRegistry: ResourceRegistry, textureUsages: [Texture : MTLTextureUsage]) {
        self.init()
        self.fill(from: descriptor, actions: actions, resourceRegistry: resourceRegistry, textureUsages: textureUsages)
        
        if let clearStencil = descriptor.clearStencil {
            self.clearStencil = clearStencil
        }
    }
}

extension MTLRenderPassDescriptor {
    convenience init(_ descriptorWrapper: MetalRenderTargetDescriptor, resourceRegistry: ResourceRegistry, textureUsages: [Texture : MTLTextureUsage]) {
        self.init()
        let descriptor = descriptorWrapper.descriptor
        
        for (i, attachment) in descriptor.colorAttachments.enumerated() {
            guard let attachment = attachment else { continue }
            self.colorAttachments[i] = MTLRenderPassColorAttachmentDescriptor(attachment, actions: descriptorWrapper.colorActions[i], resourceRegistry: resourceRegistry, textureUsages: textureUsages)
        }
        
        if let depthAttachment = descriptor.depthAttachment {
            self.depthAttachment = MTLRenderPassDepthAttachmentDescriptor(depthAttachment, actions: descriptorWrapper.depthActions, resourceRegistry: resourceRegistry, textureUsages: textureUsages)
        }
        
        if let stencilAttachment = descriptor.stencilAttachment {
            self.stencilAttachment = MTLRenderPassStencilAttachmentDescriptor(stencilAttachment,  actions: descriptorWrapper.stencilActions, resourceRegistry: resourceRegistry, textureUsages: textureUsages)
        }
        
        if let visibilityBuffer = descriptor.visibilityResultBuffer {
            let buffer = resourceRegistry.allocateBufferIfNeeded(visibilityBuffer)
            assert(buffer.offset == 0, "TODO: Non-zero offsets need to be passed to the MTLRenderCommandEncoder via setVisibilityResultMode()")
            self.visibilityResultBuffer = buffer.buffer
        }
        
        self.renderTargetArrayLength = descriptor.renderTargetArrayLength
    }
}

extension MTLRenderPipelineColorAttachmentDescriptor {
    convenience init(blendDescriptor: BlendDescriptor?, writeMask: ColorWriteMask, pixelFormat: MTLPixelFormat) {
        self.init()
        
        self.pixelFormat = pixelFormat
        self.writeMask = MTLColorWriteMask(writeMask)
        
        if let blendDescriptor = blendDescriptor {
            self.isBlendingEnabled = true
            self.sourceRGBBlendFactor = MTLBlendFactor(blendDescriptor.sourceRGBBlendFactor)
            self.destinationRGBBlendFactor = MTLBlendFactor(blendDescriptor.destinationRGBBlendFactor)
            self.rgbBlendOperation = MTLBlendOperation(blendDescriptor.rgbBlendOperation)
            self.sourceAlphaBlendFactor = MTLBlendFactor(blendDescriptor.sourceAlphaBlendFactor)
            self.destinationAlphaBlendFactor = MTLBlendFactor(blendDescriptor.destinationAlphaBlendFactor)
            self.alphaBlendOperation = MTLBlendOperation(blendDescriptor.alphaBlendOperation)
        } else {
            self.isBlendingEnabled = false
        }
    }
}

extension MTLRenderPipelineDescriptor {
    convenience init(_ descriptor: MetalRenderPipelineDescriptor, stateCaches: StateCaches) {
        self.init()
        if let label = descriptor.descriptor.label {
            self.label = label
        }
        
        self.vertexFunction = stateCaches.function(named: descriptor.descriptor.vertexFunction!, functionConstants: descriptor.descriptor.functionConstants)
        if let fragmentFunction = descriptor.descriptor.fragmentFunction {
            self.fragmentFunction = stateCaches.function(named: fragmentFunction, functionConstants: descriptor.descriptor.functionConstants)
        }
        
        if let vertexDescriptor = descriptor.descriptor.vertexDescriptor {
            self.vertexDescriptor = MTLVertexDescriptor(vertexDescriptor)
        }
        
        self.rasterSampleCount = descriptor.descriptor.sampleCount
        self.isAlphaToCoverageEnabled = descriptor.descriptor.isAlphaToCoverageEnabled
        self.isAlphaToOneEnabled = descriptor.descriptor.isAlphaToOneEnabled
        
        self.isRasterizationEnabled = descriptor.descriptor.isRasterizationEnabled
        
        self.depthAttachmentPixelFormat = descriptor.depthAttachmentFormat
        self.stencilAttachmentPixelFormat = descriptor.stencilAttachmentFormat
        
        for i in 0..<descriptor.descriptor.blendStates.count {
            self.colorAttachments[i] = MTLRenderPipelineColorAttachmentDescriptor(blendDescriptor: descriptor.descriptor.blendStates[i], writeMask: descriptor.descriptor.writeMasks[i], pixelFormat: descriptor.colorAttachmentFormats[i])
        }
    }
}

extension MTLTextureDescriptor {
    convenience init(_ descriptor: TextureDescriptor, usage: MTLTextureUsage) {
        self.init()
        
        self.textureType = MTLTextureType(descriptor.textureType)
        self.pixelFormat = MTLPixelFormat(descriptor.pixelFormat)
        self.width = descriptor.width
        self.height = descriptor.height
        self.depth = descriptor.depth
        self.mipmapLevelCount = descriptor.mipmapLevelCount
        self.sampleCount = descriptor.sampleCount
        self.arrayLength = descriptor.arrayLength
        
        self.resourceOptions = MTLResourceOptions(storageMode: descriptor.storageMode, cacheMode: descriptor.cacheMode)
        
        self.cpuCacheMode = MTLCPUCacheMode(descriptor.cacheMode)
        self.storageMode = MTLStorageMode(descriptor.storageMode)
        self.usage = usage
    }
}


extension MTLVertexBufferLayoutDescriptor {
    convenience init(_ descriptor : VertexBufferLayoutDescriptor) {
        self.init()
        
        self.stride = descriptor.stride
        self.stepFunction = MTLVertexStepFunction(descriptor.stepFunction)
        self.stepRate = descriptor.stepRate
    }
}

extension MTLVertexAttributeDescriptor {
    convenience init(_ descriptor : VertexAttributeDescriptor) {
        self.init()
        
        self.format = MTLVertexFormat(descriptor.format)
        self.offset = descriptor.offset
        self.bufferIndex = descriptor.bufferIndex
    }
}

extension MTLVertexDescriptor {
    convenience init(_ descriptor : VertexDescriptor) {
        self.init()
        
        for (i, layout) in descriptor.layouts.enumerated() {
            self.layouts[i] = MTLVertexBufferLayoutDescriptor(layout)
        }
        
        for (i, attribute) in descriptor.attributes.enumerated() {
            self.attributes[i] = MTLVertexAttributeDescriptor(attribute)
        }
    }
}
