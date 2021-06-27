//
//  Descriptors.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 24/12/17.
//

#if canImport(Metal)

import Metal
import SubstrateUtilities

enum RenderTargetTextureError : Error {
    case invalidSizeDrawable(Texture, requestedSize: Size, drawableSize: Size)
    case unableToRetrieveDrawable(Texture)
}

extension MTLHeapDescriptor {
    convenience init(_ descriptor: HeapDescriptor, isAppleSiliconGPU: Bool) {
        self.init()
        
        self.size = descriptor.size
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, *) {
            switch descriptor.type {
            case .automaticPlacement:
                self.type = .automatic
            case .sparseTexture:
                if isAppleSiliconGPU, #available(macOS 11.0, macCatalyst 14.0, *) {
                    self.type = .sparse
                } else {
                    self.type = .automatic
                }
            }
        }
        self.storageMode = MTLStorageMode(descriptor.storageMode, isAppleSiliconGPU: isAppleSiliconGPU)
        self.cpuCacheMode = MTLCPUCacheMode(descriptor.cacheMode)
        
        if #available(OSX 10.15, iOS 13.0, tvOS 13.0, *) {
            self.hazardTrackingMode = .substrateTrackedHazards
        }
    }
}

extension MTLStencilDescriptor {
    convenience init(_ descriptor: StencilDescriptor) {
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
    convenience init(_ descriptor: DepthStencilDescriptor) {
        self.init()
        
        if descriptor.backFaceStencil == descriptor.frontFaceStencil {
            let stencilDescriptor = MTLStencilDescriptor(descriptor.backFaceStencil)
            self.backFaceStencil = stencilDescriptor
            self.frontFaceStencil = stencilDescriptor
        } else {
            self.backFaceStencil = MTLStencilDescriptor(descriptor.backFaceStencil)
            self.frontFaceStencil = MTLStencilDescriptor(descriptor.frontFaceStencil)
        }
        
        self.depthCompareFunction = MTLCompareFunction(descriptor.depthCompareFunction)
        self.isDepthWriteEnabled = descriptor.isDepthWriteEnabled
    }
}

extension MTLSamplerDescriptor {
    convenience init(_ descriptor: SamplerDescriptor, isAppleSiliconGPU: Bool) {
        self.init()
        
        self.minFilter = MTLSamplerMinMagFilter(descriptor.minFilter)
        self.magFilter = MTLSamplerMinMagFilter(descriptor.magFilter)
        self.mipFilter = MTLSamplerMipFilter(descriptor.mipFilter)
        self.maxAnisotropy = descriptor.maxAnisotropy
        self.sAddressMode = MTLSamplerAddressMode(descriptor.sAddressMode)
        self.tAddressMode = MTLSamplerAddressMode(descriptor.tAddressMode)
        self.rAddressMode = MTLSamplerAddressMode(descriptor.rAddressMode)
        #if os(macOS)
        if !isAppleSiliconGPU {
            self.borderColor = MTLSamplerBorderColor(descriptor.borderColor)
        }
        #endif
        self.normalizedCoordinates = descriptor.normalizedCoordinates
        self.lodMinClamp = descriptor.lodMinClamp
        self.lodMaxClamp = descriptor.lodMaxClamp
        self.compareFunction = MTLCompareFunction(descriptor.compareFunction)
        
        self.supportArgumentBuffers = true
    }
}


extension MTLRenderPassAttachmentDescriptor {
    func fill(from descriptor: RenderTargetAttachmentDescriptor, actions: (MTLLoadAction, MTLStoreAction), resourceMap: FrameResourceMap<MetalBackend>) throws {
        
        let texture = descriptor.texture
        self.texture = try resourceMap.renderTargetTexture(texture).texture
        self.level = descriptor.level
        self.slice = descriptor.slice
        self.depthPlane = descriptor.depthPlane
        
        self.resolveTexture = try descriptor.resolveTexture.map { try resourceMap.renderTargetTexture($0).texture }
        self.resolveLevel = descriptor.resolveLevel
        self.resolveSlice = descriptor.resolveSlice
        self.resolveDepthPlane = descriptor.resolveDepthPlane
        
        self.loadAction = actions.0
        self.storeAction = actions.1
    }
}

extension MTLRenderPassColorAttachmentDescriptor {
    convenience init(_ descriptor: RenderTargetColorAttachmentDescriptor, clearColor: MTLClearColor, actions: (MTLLoadAction, MTLStoreAction), resourceMap: FrameResourceMap<MetalBackend>) throws {
        self.init()
        try self.fill(from: descriptor, actions: actions, resourceMap: resourceMap)
        self.clearColor = clearColor
    }
}

extension MTLRenderPassDepthAttachmentDescriptor {
    convenience init(_ descriptor: RenderTargetDepthAttachmentDescriptor, clearDepth: Double, actions: (MTLLoadAction, MTLStoreAction), resourceMap: FrameResourceMap<MetalBackend>) throws {
        self.init()
        try self.fill(from: descriptor, actions: actions, resourceMap: resourceMap)
        self.clearDepth = clearDepth
        
    }
}

extension MTLRenderPassStencilAttachmentDescriptor {
    convenience init(_ descriptor: RenderTargetStencilAttachmentDescriptor, clearStencil: UInt32, actions: (MTLLoadAction, MTLStoreAction), resourceMap: FrameResourceMap<MetalBackend>) throws {
        self.init()
        try self.fill(from: descriptor, actions: actions, resourceMap: resourceMap)
        
        switch self.texture!.pixelFormat {
        case .stencil8, .x24_stencil8, .x32_stencil8, .depth24Unorm_stencil8, .depth32Float_stencil8:
            self.clearStencil = clearStencil & 0xFF // NVIDIA drivers crash when clearStencil is non-representable by the stencil buffer's bit depth.
        default:
            self.clearStencil = clearStencil
            break
        }
    }
}

extension MTLRenderPassDescriptor {
    convenience init(_ descriptorWrapper: MetalRenderTargetDescriptor, resourceMap: FrameResourceMap<MetalBackend>) throws {
        self.init()
        let descriptor = descriptorWrapper.descriptor
        
        for (i, attachment) in descriptor.colorAttachments.enumerated() {
            guard let attachment = attachment else { continue }
            self.colorAttachments[i] = try MTLRenderPassColorAttachmentDescriptor(attachment, clearColor: descriptorWrapper.clearColors[i], actions: descriptorWrapper.colorActions[i], resourceMap: resourceMap)
        }
        
        if let depthAttachment = descriptor.depthAttachment {
            self.depthAttachment = try MTLRenderPassDepthAttachmentDescriptor(depthAttachment, clearDepth: descriptorWrapper.clearDepth, actions: descriptorWrapper.depthActions, resourceMap: resourceMap)
        }
        
        if let stencilAttachment = descriptor.stencilAttachment {
            self.stencilAttachment = try MTLRenderPassStencilAttachmentDescriptor(stencilAttachment, clearStencil: descriptorWrapper.clearStencil, actions: descriptorWrapper.stencilActions, resourceMap: resourceMap)
        }
        
        if let visibilityBuffer = descriptor.visibilityResultBuffer, let buffer = resourceMap[visibilityBuffer] {
            precondition(buffer.offset == 0, "TODO: Non-zero offsets need to be passed to the MTLRenderCommandEncoder via setVisibilityResultMode()")
            self.visibilityResultBuffer = buffer.buffer
        }
        
        self.renderTargetArrayLength = descriptor.renderTargetArrayLength
    }
}

extension MTLRenderPipelineColorAttachmentDescriptor {
    convenience init(blendDescriptor: BlendDescriptor?, writeMask: ColorWriteMask, pixelFormat: MTLPixelFormat) {
        self.init()
        
        self.pixelFormat = pixelFormat
        self.writeMask = pixelFormat == .invalid ? [] : MTLColorWriteMask(writeMask)
        
        if let blendDescriptor = blendDescriptor, pixelFormat != .invalid {
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
    convenience init?(_ descriptor: MetalRenderPipelineDescriptor, stateCaches: MetalStateCaches) async {
        self.init()
        if let label = descriptor.descriptor.label {
            self.label = label
        }
        
        guard let vertexFunction = await stateCaches.function(named: descriptor.descriptor.vertexFunction!, functionConstants: descriptor.descriptor.functionConstants) else {
            return nil
        }
        self.vertexFunction = vertexFunction
        
        if let fragmentFunction = descriptor.descriptor.fragmentFunction {
            guard let function = await stateCaches.function(named: fragmentFunction, functionConstants: descriptor.descriptor.functionConstants) else {
                return nil
            }
            self.fragmentFunction = function
        }
        
        if let vertexDescriptor = descriptor.descriptor.vertexDescriptor {
            self.vertexDescriptor = MTLVertexDescriptor(vertexDescriptor)
        }
        
        self.isAlphaToCoverageEnabled = descriptor.descriptor.isAlphaToCoverageEnabled
        self.isAlphaToOneEnabled = descriptor.descriptor.isAlphaToOneEnabled
        
        self.isRasterizationEnabled = descriptor.descriptor.isRasterizationEnabled
        
        self.depthAttachmentPixelFormat = descriptor.depthAttachmentFormat
        self.stencilAttachmentPixelFormat = descriptor.stencilAttachmentFormat
        
        var sampleCount = 0
        if let depthSampleCount = descriptor.depthSampleCount {
            sampleCount = depthSampleCount
        }
        if let stencilSampleCount = descriptor.stencilSampleCount {
            assert(sampleCount == 0 || sampleCount == stencilSampleCount)
            sampleCount = stencilSampleCount
        }
        
        for i in 0..<descriptor.colorAttachmentFormats.count {
            self.colorAttachments[i] = MTLRenderPipelineColorAttachmentDescriptor(blendDescriptor: descriptor.descriptor.blendStates[i, default: nil], writeMask: descriptor.descriptor.writeMasks[i, default: []], pixelFormat: descriptor.colorAttachmentFormats[i, default: .invalid])
            
            if let attachmentSampleCount = descriptor.colorAttachmentSampleCounts[i] {
                assert(sampleCount == 0 || sampleCount == attachmentSampleCount)
                sampleCount = attachmentSampleCount
            }
        }
        
        self.rasterSampleCount = sampleCount
    }
}

extension MTLTextureDescriptor {
    public convenience init(_ descriptor: TextureDescriptor, usage: MTLTextureUsage, isAppleSiliconGPU: Bool) {
        self.init()
        
        self.textureType = MTLTextureType(descriptor.textureType)
        self.pixelFormat = MTLPixelFormat(descriptor.pixelFormat)
        self.width = descriptor.width
        self.height = descriptor.height
        self.depth = descriptor.depth
        self.mipmapLevelCount = descriptor.mipmapLevelCount
        self.sampleCount = descriptor.sampleCount
        self.arrayLength = descriptor.arrayLength
        
        self.cpuCacheMode = MTLCPUCacheMode(descriptor.cacheMode)
        self.storageMode = MTLStorageMode(descriptor.storageMode, isAppleSiliconGPU: isAppleSiliconGPU)
        self.usage = usage
        
        self.resourceOptions = MTLResourceOptions(storageMode: descriptor.storageMode, cacheMode: descriptor.cacheMode, isAppleSiliconGPU: isAppleSiliconGPU)
    }
}


extension MTLVertexBufferLayoutDescriptor {
    convenience init(_ descriptor: VertexBufferLayoutDescriptor) {
        self.init()
        
        self.stride = descriptor.stride
        self.stepFunction = MTLVertexStepFunction(descriptor.stepFunction)
        self.stepRate = descriptor.stepRate
    }
}

extension MTLVertexAttributeDescriptor {
    convenience init(_ descriptor: VertexAttributeDescriptor) {
        self.init()
        
        // For vertex buffers, index the bindings backwards from the maximum (30) to allow argument buffers and push constants to go first.
        self.format = MTLVertexFormat(descriptor.format)
        self.offset = descriptor.offset
        self.bufferIndex = 30 - descriptor.bufferIndex
    }
}

extension MTLVertexDescriptor {
    convenience init(_ descriptor : VertexDescriptor) {
        self.init()
        
        // For vertex buffers, index the bindings backwards from the maximum (30) to allow argument buffers and push constants to go first.
        for (i, layout) in descriptor.layouts.enumerated() {
            self.layouts[30 - i] = MTLVertexBufferLayoutDescriptor(layout)
        }
        
        for (i, attribute) in descriptor.attributes.enumerated() {
            self.attributes[i] = MTLVertexAttributeDescriptor(attribute)
        }
    }
}

#endif // canImport(Metal)
