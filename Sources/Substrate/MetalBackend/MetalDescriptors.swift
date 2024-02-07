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
    case unableToRetrieveDrawable(Texture, Error?)
}


@available(iOS 14.0, macOS 11.0, *)
extension AccelerationStructureDescriptor.TriangleGeometryDescriptor {
    func metalDescriptor() -> MTLAccelerationStructureTriangleGeometryDescriptor {
        let mtlTriangleDescriptor = MTLAccelerationStructureTriangleGeometryDescriptor()
        mtlTriangleDescriptor.triangleCount = self.triangleCount
        
        let indexBuffer = self.indexBuffer.map { $0.mtlBuffer! }
        mtlTriangleDescriptor.indexBuffer = indexBuffer?.buffer
        mtlTriangleDescriptor.indexBufferOffset = (indexBuffer?.offset ?? 0) + self.indexBufferOffset
        mtlTriangleDescriptor.indexType = MTLIndexType(self.indexType)
        
        let vertexBuffer = self.vertexBuffer.mtlBuffer!
        mtlTriangleDescriptor.vertexBuffer = vertexBuffer.buffer
        mtlTriangleDescriptor.vertexBufferOffset = vertexBuffer.offset + self.vertexBufferOffset
        mtlTriangleDescriptor.vertexStride = self.vertexStride
        
        return mtlTriangleDescriptor
    }
}

@available(iOS 14.0, macOS 11.0, *)
extension AccelerationStructureDescriptor.BoundingBoxGeometryDescriptor {
    func metalDescriptor() -> MTLAccelerationStructureBoundingBoxGeometryDescriptor {
        let mtlBoundingBoxDescriptor = MTLAccelerationStructureBoundingBoxGeometryDescriptor()
        mtlBoundingBoxDescriptor.boundingBoxCount = self.boundingBoxCount
        
        let buffer = self.boundingBoxBuffer.mtlBuffer!
        mtlBoundingBoxDescriptor.boundingBoxBuffer = buffer.buffer
        mtlBoundingBoxDescriptor.boundingBoxBufferOffset = buffer.offset + self.boundingBoxBufferOffset
        mtlBoundingBoxDescriptor.boundingBoxStride = self.boundingBoxStride
        
        return mtlBoundingBoxDescriptor
    }
}

@available(iOS 14.0, macOS 11.0, *)
extension AccelerationStructureDescriptor.GeometryDescriptor {
    func metalDescriptor() -> MTLAccelerationStructureGeometryDescriptor {
        let mtlGeometryDescriptor: MTLAccelerationStructureGeometryDescriptor
        switch self.geometry {
        case .boundingBox(let boundingBox):
            mtlGeometryDescriptor = boundingBox.metalDescriptor()
        case .triangle(let triangle):
            mtlGeometryDescriptor = triangle.metalDescriptor()
        }
        
        mtlGeometryDescriptor.intersectionFunctionTableOffset = self.intersectionFunctionTableOffset
        mtlGeometryDescriptor.opaque = self.isOpaque
        mtlGeometryDescriptor.allowDuplicateIntersectionFunctionInvocation = self.canInvokeIntersectionFunctionsMultipleTimesPerIntersection
        
        return mtlGeometryDescriptor
    }
}

@available(iOS 14.0, macOS 11.0, *)
extension Array where Element == AccelerationStructureDescriptor.GeometryDescriptor {
    func metalDescriptor() -> MTLPrimitiveAccelerationStructureDescriptor {
        let mtlPrimitiveDescriptor = MTLPrimitiveAccelerationStructureDescriptor()
        mtlPrimitiveDescriptor.geometryDescriptors =
            self.map { $0.metalDescriptor() }
        
        return mtlPrimitiveDescriptor
    }
}

@available(iOS 14.0, macOS 11.0, *)
extension AccelerationStructureDescriptor.InstanceStructureDescriptor {
    func metalDescriptor() -> MTLInstanceAccelerationStructureDescriptor {
        let mtlInstanceDescriptor = MTLInstanceAccelerationStructureDescriptor()
        mtlInstanceDescriptor.instanceCount = self.instanceCount
        
        let instanceDescriptorBuffer = self.instanceDescriptorBuffer.mtlBuffer!
        mtlInstanceDescriptor.instanceDescriptorBuffer = instanceDescriptorBuffer.buffer
        mtlInstanceDescriptor.instanceDescriptorBufferOffset = instanceDescriptorBuffer.offset + self.instanceDescriptorBufferOffset
        mtlInstanceDescriptor.instanceDescriptorStride = self.instanceDescriptorStride
        
        mtlInstanceDescriptor.instancedAccelerationStructures = self.primitiveStructures.map { $0.mtlAccelerationStructure! }
        
        return mtlInstanceDescriptor
    }
}

@available(iOS 14.0, macOS 11.0, *)
extension AccelerationStructureDescriptor {
    
    func metalDescriptor() -> MTLAccelerationStructureDescriptor {
        let descriptor: MTLAccelerationStructureDescriptor
        switch self.type {
        case .bottomLevelPrimitive(let bottomLevelDescriptor):
            descriptor = bottomLevelDescriptor.metalDescriptor()
            
        case .topLevelInstance(let topLevelDescriptor):
            descriptor = topLevelDescriptor.metalDescriptor()
        }
        
        if self.flags.contains(.preferFastBuild) {
            descriptor.usage.formUnion(.preferFastBuild)
        }
        
        if self.flags.contains(.refittable) {
            descriptor.usage.formUnion(.refit)
        }
        
        return descriptor
    }
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
    func fill(from descriptor: RenderTargetAttachmentDescriptor, actions: (MTLLoadAction, MTLStoreAction), transientRegistry: MetalTransientResourceRegistry?) async throws {
        
        if descriptor.texture.flags.contains(.windowHandle) {
            try await transientRegistry!.allocateWindowHandleTexture(descriptor.texture)
        }
        
        if let resolveTexture = descriptor.resolveTexture, resolveTexture.flags.contains(.windowHandle) {
            try await transientRegistry!.allocateWindowHandleTexture(resolveTexture)
        }
        
        
        let texture = descriptor.texture
        self.texture = texture.mtlTexture
        self.level = descriptor.level
        self.slice = descriptor.slice
        self.depthPlane = descriptor.depthPlane
        
        self.resolveTexture = descriptor.resolveTexture?.mtlTexture
        self.resolveLevel = descriptor.resolveLevel
        self.resolveSlice = descriptor.resolveSlice
        self.resolveDepthPlane = descriptor.resolveDepthPlane
        
        self.loadAction = actions.0
        self.storeAction = actions.1
    }
}

extension MTLRenderPassColorAttachmentDescriptor {
    convenience init(_ descriptor: RenderTargetColorAttachmentDescriptor, clearColor: MTLClearColor, actions: (MTLLoadAction, MTLStoreAction), transientRegistry: MetalTransientResourceRegistry?) async throws {
        self.init()
        try await self.fill(from: descriptor, actions: actions, transientRegistry: transientRegistry)
        self.clearColor = clearColor
    }
}

extension MTLRenderPassDepthAttachmentDescriptor {
    convenience init(_ descriptor: RenderTargetDepthAttachmentDescriptor, clearDepth: Double, actions: (MTLLoadAction, MTLStoreAction), transientRegistry: MetalTransientResourceRegistry?) async throws {
        self.init()
        try await self.fill(from: descriptor, actions: actions, transientRegistry: transientRegistry)
        self.clearDepth = clearDepth
        
    }
}

extension MTLRenderPassStencilAttachmentDescriptor {
    convenience init(_ descriptor: RenderTargetStencilAttachmentDescriptor, clearStencil: UInt32, actions: (MTLLoadAction, MTLStoreAction), transientRegistry: MetalTransientResourceRegistry?) async throws {
        self.init()
        try await self.fill(from: descriptor, actions: actions, transientRegistry: transientRegistry)
        
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
    convenience init(_ descriptorWrapper: MetalRenderTargetDescriptor, transientRegistry: MetalTransientResourceRegistry?) async throws {
        self.init()
        let descriptor = descriptorWrapper.descriptor
        
        for (i, attachment) in descriptor.colorAttachments.enumerated() {
            guard let attachment = attachment else { continue }
            self.colorAttachments[i] = try await MTLRenderPassColorAttachmentDescriptor(attachment, clearColor: descriptorWrapper.clearColors[i], actions: descriptorWrapper.colorActions[i], transientRegistry: transientRegistry)
        }
        
        if let depthAttachment = descriptor.depthAttachment {
            self.depthAttachment = try await MTLRenderPassDepthAttachmentDescriptor(depthAttachment, clearDepth: descriptorWrapper.clearDepth, actions: descriptorWrapper.depthActions, transientRegistry: transientRegistry)
        }
        
        if let stencilAttachment = descriptor.stencilAttachment {
            self.stencilAttachment = try await  MTLRenderPassStencilAttachmentDescriptor(stencilAttachment, clearStencil: descriptorWrapper.clearStencil, actions: descriptorWrapper.stencilActions, transientRegistry: transientRegistry)
        }
        
        if let visibilityBuffer = descriptor.visibilityResultBuffer, let buffer = visibilityBuffer.mtlBuffer {
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
    convenience init(_ descriptor: RenderPipelineDescriptor, vertexPipelineDescriptor: VertexRenderPipelineDescriptor, functionCache: MetalFunctionCache) async throws {
        self.init()
        if let label = descriptor.label {
            self.label = label
        }
        
        let vertexFunction = try await functionCache.function(for: vertexPipelineDescriptor.vertexFunction)
        self.vertexFunction = vertexFunction
        
        if !descriptor.fragmentFunction.name.isEmpty {
            let function = try await functionCache.function(for: descriptor.fragmentFunction)
            self.fragmentFunction = function
        }
        
        if let vertexDescriptor = vertexPipelineDescriptor.vertexDescriptor {
            self.vertexDescriptor = MTLVertexDescriptor(vertexDescriptor)
        }
        
        self.isAlphaToCoverageEnabled = descriptor.isAlphaToCoverageEnabled
        self.isAlphaToOneEnabled = descriptor.isAlphaToOneEnabled
        
        self.isRasterizationEnabled = descriptor.isRasterizationEnabled
        
        self.depthAttachmentPixelFormat = MTLPixelFormat(descriptor.depthAttachmentFormat)
        self.stencilAttachmentPixelFormat = MTLPixelFormat(descriptor.stencilAttachmentFormat)
        
        for i in 0..<descriptor.colorAttachmentFormats.count {
            self.colorAttachments[i] = MTLRenderPipelineColorAttachmentDescriptor(blendDescriptor: descriptor.blendStates[i, default: nil], writeMask: descriptor.writeMasks[i, default: []], pixelFormat: MTLPixelFormat(descriptor.colorAttachmentFormats[i, default: .invalid]))
        }
        
        self.rasterSampleCount = descriptor.rasterSampleCount
    }
}

@available(macOS 13.0, *)
extension MTLMeshRenderPipelineDescriptor {
    convenience init(_ descriptor: RenderPipelineDescriptor, meshPipelineDescriptor: MeshRenderPipelineDescriptor, functionCache: MetalFunctionCache) async throws {
        self.init()
        if let label = descriptor.label {
            self.label = label
        }
        
        let objectFunction = try await functionCache.function(for: meshPipelineDescriptor.objectFunction)
        self.objectFunction = objectFunction
        
        let meshFunction = try await functionCache.function(for: meshPipelineDescriptor.meshFunction)
        self.meshFunction = meshFunction
        
        if !descriptor.fragmentFunction.name.isEmpty {
            let function = try await functionCache.function(for: descriptor.fragmentFunction)
            self.fragmentFunction = function
        }
        
        self.maxTotalThreadsPerObjectThreadgroup = meshPipelineDescriptor.maxTotalThreadsPerObjectThreadgroup
        self.maxTotalThreadsPerMeshThreadgroup = meshPipelineDescriptor.maxTotalThreadsPerMeshThreadgroup
        
        self.objectThreadgroupSizeIsMultipleOfThreadExecutionWidth = meshPipelineDescriptor.objectThreadgroupSizeIsMultipleOfThreadExecutionWidth
        self.meshThreadgroupSizeIsMultipleOfThreadExecutionWidth = meshPipelineDescriptor.meshThreadgroupSizeIsMultipleOfThreadExecutionWidth
        
        self.payloadMemoryLength = meshPipelineDescriptor.payloadMemoryLength
        
        self.maxTotalThreadgroupsPerMeshGrid = meshPipelineDescriptor.maxTotalThreadgroupsPerMeshGrid
        
        self.isAlphaToCoverageEnabled = descriptor.isAlphaToCoverageEnabled
        self.isAlphaToOneEnabled = descriptor.isAlphaToOneEnabled
        
        self.isRasterizationEnabled = descriptor.isRasterizationEnabled
        
        self.depthAttachmentPixelFormat = MTLPixelFormat(descriptor.depthAttachmentFormat)
        self.stencilAttachmentPixelFormat = MTLPixelFormat(descriptor.stencilAttachmentFormat)
        
        for i in 0..<descriptor.colorAttachmentFormats.count {
            self.colorAttachments[i] = MTLRenderPipelineColorAttachmentDescriptor(blendDescriptor: descriptor.blendStates[i, default: nil], writeMask: descriptor.writeMasks[i, default: []], pixelFormat: MTLPixelFormat(descriptor.colorAttachmentFormats[i, default: .invalid]))
        }
        
        self.rasterSampleCount = descriptor.rasterSampleCount
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
