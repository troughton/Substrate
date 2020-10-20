//
//  Conversion.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 8/01/18.
//

#if canImport(Vulkan)
import Vulkan
import SubstrateCExtras
import SubstrateUtilities
import SPIRV_Cross

// MARK: - SPIRV-Cross

extension VkShaderStageFlagBits {
    init?(_ executionModel: SpvExecutionModel) {
        switch executionModel {
        case SpvExecutionModelVertex:
            self = VK_SHADER_STAGE_VERTEX_BIT
        case SpvExecutionModelFragment:
            self = VK_SHADER_STAGE_FRAGMENT_BIT
        case SpvExecutionModelGLCompute:
            self = VK_SHADER_STAGE_COMPUTE_BIT
        default:
            return nil
        }
    }
}

// MARK: - RenderGraph Types

extension VmaMemoryUsage {
    init(storageMode: StorageMode, cacheMode: CPUCacheMode) {
        switch (storageMode, cacheMode) {
        case (.private, _):
            self = VMA_MEMORY_USAGE_GPU_ONLY
        case (.shared, .defaultCache):
            self = VMA_MEMORY_USAGE_CPU_ONLY
        case (.shared, .writeCombined):
            self = VMA_MEMORY_USAGE_CPU_TO_GPU
        case (.managed, .defaultCache):
            self = VMA_MEMORY_USAGE_GPU_TO_CPU
        case (.managed, .writeCombined):
            self = VMA_MEMORY_USAGE_CPU_TO_GPU
        }
    }
}

//MARK: Flag bits to flags

extension VkAccessFlags {
    init(_ flagBits: VkAccessFlagBits) {
        self.init(flagBits.rawValue)
    }
}

extension VkBufferCreateFlags {
    init(_ flagBits: VkBufferCreateFlagBits) {
        self.init(flagBits.rawValue)
    }
}

extension VkBufferUsageFlags {
    init(_ flagBits: VkBufferUsageFlagBits) {
        self.init(flagBits.rawValue)
    }
}


extension VkCommandPoolCreateFlags {
    init(_ flagBits: VkCommandPoolCreateFlagBits) {
        self.init(flagBits.rawValue)
    }
}

extension VkCommandPoolResetFlags {
    init(_ flagBits: VkCommandPoolResetFlagBits) {
        self.init(flagBits.rawValue)
    }
}


extension VkCommandBufferUsageFlags {
    init(_ flagBits: VkCommandBufferUsageFlagBits) {
        self.init(flagBits.rawValue)
    }
}

extension VkColorComponentFlags {
    init(_ flagBits: VkColorComponentFlagBits) {
        self.init(flagBits.rawValue)
    }
}

extension VkDependencyFlags {
    init(_ flagBits: VkDependencyFlagBits) {
        self.init(flagBits.rawValue)
    }
}

extension VkDescriptorPoolCreateFlags {
    init(_ flagBits: VkDescriptorPoolCreateFlagBits) {
        self.init(flagBits.rawValue)
    }
}

extension VkImageAspectFlags {
    init(_ flagBits: VkImageAspectFlagBits) {
        self.init(flagBits.rawValue)
    }
}

extension VkImageCreateFlags {
    init(_ flagBits: VkImageCreateFlagBits) {
        self.init(flagBits.rawValue)
    }
}

extension VkImageUsageFlags {
    init(_ flagBits: VkImageUsageFlagBits) {
        self.init(flagBits.rawValue)
    }
}

extension VkShaderStageFlags {
    init(_ flagBits: VkShaderStageFlagBits) {
        self.init(flagBits.rawValue)
    }
}

extension VkStencilFaceFlags {
    init(_ flagBits: VkStencilFaceFlagBits) {
        self.init(flagBits.rawValue)
    }
}

extension VkPipelineStageFlags {
    init(_ flagBits: VkPipelineStageFlagBits) {
        self.init(flagBits.rawValue)
    }
}

extension VkDescriptorSetLayoutCreateFlags {
    init(_ flagBits: VkDescriptorSetLayoutCreateFlagBits) {
        self.init(flagBits.rawValue)
    }
}

extension VkQueueFlagBits {
    init(_ flagBits: VkQueueFlags) {
        self.init(rawValue: VkQueueFlagBits.RawValue(flagBits))
    }
}

extension VkMemoryPropertyFlagBits {
    init(_ flags: VkMemoryPropertyFlags) {
        self.init(rawValue: VkMemoryPropertyFlagBits.RawValue(flags))
    }
}

//MARK: From Vulkan

extension PixelFormat {
    init(_ format: VkFormat) {
        switch format {
        case VK_FORMAT_B8G8R8A8_UNORM:
            self = .bgra8Unorm
        case VK_FORMAT_B8G8R8A8_SRGB:
            self = .bgra8Unorm_sRGB
        default:
            fatalError("Unimplemented format conversion for VkFormat \(format).")
        }
    }
}

//MARK: To Vulkan

extension VkIndexType {
    init(_ indexType: IndexType) {
        switch indexType {
        case .uint16:
            self = VK_INDEX_TYPE_UINT16
        case .uint32:
            self = VK_INDEX_TYPE_UINT32
        }
    }
}

extension VkExtent3D {
    init(_ size: Size) {
        self.init(width: UInt32(size.width), height: UInt32(size.height), depth: UInt32(size.depth))
    }
}

extension VkOffset3D {
    init(_ origin: Origin) {
        self.init(x: Int32(origin.x), y: Int32(origin.y), z: Int32(origin.z))
    }
}

extension VkRect2D {
    init(_ scissor: ScissorRect) {
        self.init(offset: VkOffset2D(x: Int32(UInt32(scissor.x)), y: Int32(scissor.y)), extent: VkExtent2D(width: UInt32(scissor.width), height: UInt32(scissor.height)))
    }
}

extension VkViewport {
    init(_ viewport: Viewport) {
        // Flip the Y coordinate to match Metal.
        self.init(x: Float(viewport.originX), y: Float(viewport.height) - Float(viewport.originY), width: Float(viewport.width), height: -Float(viewport.height), minDepth: Float(viewport.zNear), maxDepth: Float(viewport.zFar))
    }
}

extension PixelFormat {
    var aspectFlags : VkImageAspectFlags {
        var flags : VkImageAspectFlagBits = []
        if self.isDepth { flags.formUnion(VK_IMAGE_ASPECT_DEPTH_BIT) }
        if self.isStencil { flags.formUnion(VK_IMAGE_ASPECT_STENCIL_BIT) }
        if !self.isDepth && !self.isStencil { flags.formUnion(VK_IMAGE_ASPECT_COLOR_BIT) }
        return VkImageAspectFlags(flags)
    }
}

extension VkImageType {
    public init(_ type: TextureType) {
        switch type {
        case .type1D, .type1DArray, .typeTextureBuffer:
            self = VK_IMAGE_TYPE_1D
        case .type2D, .type2DArray, .type2DMultisample, .typeCube, .typeCubeArray, .type2DMultisampleArray:
            self = VK_IMAGE_TYPE_2D
        case .type3D:
            self = VK_IMAGE_TYPE_3D
        }
    }
}

extension VkImageViewType {
    init(_ textureType: TextureType) {
        switch textureType {
        case .type1D:
            self = VK_IMAGE_VIEW_TYPE_1D
        case .type1DArray:
            self = VK_IMAGE_VIEW_TYPE_1D_ARRAY
        case .type2D, .type2DMultisample:
            self = VK_IMAGE_VIEW_TYPE_2D
        case .type2DArray, .type2DMultisampleArray:
            self = VK_IMAGE_VIEW_TYPE_2D_ARRAY
        case .type3D:
            self = VK_IMAGE_VIEW_TYPE_3D
        case .typeCube:
            self = VK_IMAGE_VIEW_TYPE_CUBE
        case .typeCubeArray:
            self = VK_IMAGE_VIEW_TYPE_CUBE_ARRAY
        case .typeTextureBuffer:
            self = VK_IMAGE_VIEW_TYPE_1D
}
    }
}

extension VkBlendFactor {
    public init(_ blendFactor: BlendFactor) {
        switch blendFactor {
        case .zero:
            self = VK_BLEND_FACTOR_ZERO
        case .one:
            self = VK_BLEND_FACTOR_ONE
        case .sourceColor:
            self = VK_BLEND_FACTOR_SRC_COLOR
        case .oneMinusSourceColor:
            self = VK_BLEND_FACTOR_ONE_MINUS_SRC_COLOR
        case .destinationColor:
            self = VK_BLEND_FACTOR_DST_COLOR
        case .oneMinusDestinationColor:
            self = VK_BLEND_FACTOR_ONE_MINUS_DST_COLOR
        case .sourceAlpha:
            self = VK_BLEND_FACTOR_SRC_ALPHA
        case .oneMinusSourceAlpha:
            self = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
        case .destinationAlpha:
            self = VK_BLEND_FACTOR_DST_ALPHA
        case .oneMinusDestinationAlpha:
            self = VK_BLEND_FACTOR_ONE_MINUS_DST_ALPHA
        case .blendColor:
            self = VK_BLEND_FACTOR_CONSTANT_COLOR
        case .oneMinusBlendColor:
            self = VK_BLEND_FACTOR_ONE_MINUS_CONSTANT_COLOR
        case .sourceAlphaSaturated:
            self = VK_BLEND_FACTOR_SRC_ALPHA_SATURATE
        case .source1Color:
            self = VK_BLEND_FACTOR_SRC1_COLOR
        case .oneMinusSource1Color:
            self = VK_BLEND_FACTOR_ONE_MINUS_SRC1_COLOR
        case .source1Alpha:
            self = VK_BLEND_FACTOR_SRC1_ALPHA
        case .oneMinusSource1Alpha:
            self = VK_BLEND_FACTOR_ONE_MINUS_SRC1_ALPHA
        case .blendAlpha:
            self = VK_BLEND_FACTOR_CONSTANT_ALPHA
        case .oneMinusBlendAlpha:
            self = VK_BLEND_FACTOR_ONE_MINUS_CONSTANT_ALPHA
        }
    }
}

extension VkBlendOp {
    public init(_ blendOperation: BlendOperation)  {
        switch blendOperation {
        case .add:
            self = VK_BLEND_OP_ADD
        case .subtract:
            self = VK_BLEND_OP_SUBTRACT
        case .reverseSubtract:
            self = VK_BLEND_OP_REVERSE_SUBTRACT
        case .min:
            self = VK_BLEND_OP_MIN
        case .max:
            self = VK_BLEND_OP_MAX
        }
    }
}

extension VkColorComponentFlagBits : OptionSet {
    public init(_ mask: ColorWriteMask) {
        self = []
        if mask.contains(.red) { self.formUnion(VK_COLOR_COMPONENT_R_BIT) }
        if mask.contains(.green) { self.formUnion(VK_COLOR_COMPONENT_G_BIT) }
        if mask.contains(.blue) { self.formUnion(VK_COLOR_COMPONENT_B_BIT) }
        if mask.contains(.alpha) { self.formUnion(VK_COLOR_COMPONENT_A_BIT) }
        
    }
}

extension VkPolygonMode {
    public init(_ fillMode: TriangleFillMode) {
        switch fillMode {
        case .fill:
            self = VK_POLYGON_MODE_FILL
        case .lines:
            self = VK_POLYGON_MODE_LINE
        }
    }
}

extension VkCullModeFlags {
    public init(_ cullMode: CullMode) {
        switch cullMode {
        case .none:
            self.init(VK_CULL_MODE_NONE.rawValue)
        case .front:
            self.init(VK_CULL_MODE_FRONT_BIT.rawValue)
        case .back:
            self.init(VK_CULL_MODE_BACK_BIT.rawValue)
        }
    }
}

extension VkCompareOp {
    public init(_ compareFunction: CompareFunction)  {
        switch compareFunction {
        case .always:
            self = VK_COMPARE_OP_ALWAYS
        case .never:
            self = VK_COMPARE_OP_NEVER
        case .less:
            self = VK_COMPARE_OP_LESS
        case .lessEqual:
            self = VK_COMPARE_OP_LESS_OR_EQUAL
        case .equal:
            self = VK_COMPARE_OP_EQUAL
        case .greater:
            self = VK_COMPARE_OP_GREATER
        case .notEqual:
            self = VK_COMPARE_OP_NOT_EQUAL
        case .greaterEqual:
            self = VK_COMPARE_OP_GREATER_OR_EQUAL
        }
    }
}

extension VkStencilOp {
    public init(_ stencilOperation: StencilOperation) {
        switch stencilOperation {
        case .keep:
            self = VK_STENCIL_OP_KEEP
        case .zero:
            self = VK_STENCIL_OP_ZERO
        case .replace:
            self = VK_STENCIL_OP_REPLACE
        case .incrementWrap:
            self = VK_STENCIL_OP_INCREMENT_AND_WRAP
        case .incrementClamp:
            self = VK_STENCIL_OP_INCREMENT_AND_CLAMP
        case .decrementWrap:
            self = VK_STENCIL_OP_DECREMENT_AND_WRAP
        case .decrementClamp:
            self = VK_STENCIL_OP_DECREMENT_AND_CLAMP
        case .invert:
            self = VK_STENCIL_OP_INVERT
        }
    }
}

extension VkStencilOpState {
    public init(descriptor: StencilDescriptor, referenceValue: UInt32) {
        self.init()
        self.failOp = VkStencilOp(descriptor.stencilFailureOperation)
        self.passOp = VkStencilOp(descriptor.depthStencilPassOperation)
        self.depthFailOp = VkStencilOp(descriptor.depthFailureOperation)
        self.compareOp = VkCompareOp(descriptor.stencilCompareFunction)
        self.compareMask = descriptor.readMask
        self.writeMask = descriptor.writeMask
        self.reference = referenceValue
    }
}

extension VkBool32 : ExpressibleByBooleanLiteral {
    public init(_ value: Bool) {
        self = value ? VkBool32(VK_TRUE) : VkBool32(VK_FALSE)
    }
    
    public init(booleanLiteral value: Bool) {
        self.init(value)
    }
}

extension VkPipelineDepthStencilStateCreateInfo {
    init(descriptor: DepthStencilDescriptor, referenceValue: UInt32) {
        self.init()
        self.sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
        self.depthTestEnable = VkBool32(!(descriptor.depthCompareFunction == .always && !descriptor.isDepthWriteEnabled))
        self.depthWriteEnable = VkBool32(descriptor.isDepthWriteEnabled)
        self.depthCompareOp = VkCompareOp(descriptor.depthCompareFunction)
        self.stencilTestEnable = VkBool32((descriptor.frontFaceStencil.stencilCompareFunction != .always) || (descriptor.backFaceStencil.stencilCompareFunction != .always))
        self.front = VkStencilOpState(descriptor: descriptor.frontFaceStencil, referenceValue: referenceValue)
        self.back = VkStencilOpState(descriptor: descriptor.backFaceStencil, referenceValue: referenceValue)
        self.depthBoundsTestEnable = false
    }
}

extension VkVertexInputRate {
    public init(_ vertexStepFunction: VertexStepFunction) {
        switch vertexStepFunction {
        case .perVertex:
            self = VK_VERTEX_INPUT_RATE_VERTEX
        case .perInstance:
            self = VK_VERTEX_INPUT_RATE_INSTANCE
        default:
            fatalError("Unsupported vertex step function \(vertexStepFunction) for Vulkan.")
        }
    }
}

extension VkFormat {
    public init(vertexFormat: VertexFormat) {
        switch vertexFormat {
        case .invalid:
            self = VK_FORMAT_UNDEFINED
        case .uchar2:
            self = VK_FORMAT_R8G8_UINT
        case .uchar3:
            self = VK_FORMAT_R8G8B8_UINT
        case .uchar4:
            self = VK_FORMAT_R8G8B8A8_UINT
        case .char2:
            self = VK_FORMAT_R8G8_SINT
        case .char3:
            self = VK_FORMAT_R8G8B8_SINT
        case .char4:
            self = VK_FORMAT_R8G8B8A8_SINT
        case .uchar2Normalized:
            self = VK_FORMAT_R8G8_UNORM
        case .uchar3Normalized:
            self = VK_FORMAT_R8G8B8_UNORM
        case .uchar4Normalized:
            self = VK_FORMAT_R8G8B8A8_UNORM
        case .char2Normalized:
            self = VK_FORMAT_R8G8_SNORM
        case .char3Normalized:
            self = VK_FORMAT_R8G8B8_SNORM
        case .char4Normalized:
            self = VK_FORMAT_R8G8B8A8_SNORM
        case .ushort2:
            self = VK_FORMAT_R16G16_UINT
        case .ushort3:
            self = VK_FORMAT_R16G16B16_UINT
        case .ushort4:
            self = VK_FORMAT_R16G16B16A16_UINT
        case .short2:
            self = VK_FORMAT_R16G16_SINT
        case .short3:
            self = VK_FORMAT_R16G16B16_SINT
        case .short4:
            self = VK_FORMAT_R16G16B16A16_SINT
        case .ushort2Normalized:
            self = VK_FORMAT_R16G16_UNORM
        case .ushort3Normalized:
            self = VK_FORMAT_R16G16B16_UNORM
        case .ushort4Normalized:
            self = VK_FORMAT_R16G16B16A16_UNORM
        case .short2Normalized:
            self = VK_FORMAT_R16G16_SNORM
        case .short3Normalized:
            self = VK_FORMAT_R16G16B16_SNORM
        case .short4Normalized:
            self = VK_FORMAT_R16G16B16A16_SNORM
        case .half2:
            self = VK_FORMAT_R16G16_SFLOAT
        case .half3:
            self = VK_FORMAT_R16G16B16_SFLOAT
        case .half4:
            self = VK_FORMAT_R16G16B16A16_SFLOAT
        case .float:
            self = VK_FORMAT_R32_SFLOAT
        case .float2:
            self = VK_FORMAT_R32G32_SFLOAT
        case .float3:
            self = VK_FORMAT_R32G32B32_SFLOAT
        case .float4:
            self = VK_FORMAT_R32G32B32A32_SFLOAT
        case .int:
            self = VK_FORMAT_R32_SINT
        case .int2:
            self = VK_FORMAT_R32G32_SINT
        case .int3:
            self = VK_FORMAT_R32G32B32_SINT
        case .int4:
            self = VK_FORMAT_R32G32B32A32_SINT
        case .uint:
            self = VK_FORMAT_R32_UINT
        case .uint2:
            self = VK_FORMAT_R32G32_UINT
        case .uint3:
            self = VK_FORMAT_R32G32B32_UINT
        case .uint4:
            self = VK_FORMAT_R32G32B32A32_UINT
        case .int1010102Normalized:
            self = VK_FORMAT_A2B10G10R10_SINT_PACK32
            print("Warning: byte order might be different on Vulkan for VertexFormat.int1010102Normalized.")
        case .uint1010102Normalized:
            self = VK_FORMAT_A2B10G10R10_UINT_PACK32
            print("Warning: byte order might be different on Vulkan for VertexFormat.uint1010102Normalized.")
        }
    }
}

struct ColorBlendStateCreateInfo {
    let attachmentStates : FixedSizeBuffer<VkPipelineColorBlendAttachmentState>
    var info : VkPipelineColorBlendStateCreateInfo
    
    init(descriptor: RenderPipelineDescriptor, renderTargetDescriptor: RenderTargetDescriptor, attachmentCount: Int) {
        var disabledAttachment = VkPipelineColorBlendAttachmentState()
        disabledAttachment.blendEnable = false
        disabledAttachment.colorWriteMask = 0

        self.attachmentStates = FixedSizeBuffer(capacity: attachmentCount, defaultValue: disabledAttachment)
        
        // Fill out attachment blend info
        for (i, attachment) in descriptor.blendStates.enumerated() {
            guard renderTargetDescriptor.colorAttachments[i] != nil else { continue }

            var state = VkPipelineColorBlendAttachmentState()

            if let attachment = attachment {
                state.blendEnable = true
                state.srcColorBlendFactor = VkBlendFactor(attachment.sourceRGBBlendFactor)
                state.dstColorBlendFactor = VkBlendFactor(attachment.destinationRGBBlendFactor)
                state.colorBlendOp = VkBlendOp(attachment.rgbBlendOperation)
                state.srcAlphaBlendFactor = VkBlendFactor(attachment.sourceAlphaBlendFactor)
                state.dstAlphaBlendFactor = VkBlendFactor(attachment.destinationAlphaBlendFactor)
                state.alphaBlendOp = VkBlendOp(attachment.alphaBlendOperation)
            } else {
                state.blendEnable = false
            }
            state.colorWriteMask = VkColorComponentFlags(VkColorComponentFlagBits(descriptor.writeMasks[i]))
            self.attachmentStates[i] = state
        }
        
        // Fill out create info
        self.info = VkPipelineColorBlendStateCreateInfo()
        self.info.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO
        self.info.logicOpEnable = false
        self.info.attachmentCount = UInt32(self.attachmentStates.capacity)
        self.info.pAttachments = UnsafePointer(self.attachmentStates.buffer)
    }
}

class VertexInputStateCreateInfo {
    
    let attribDescs = ExpandingBuffer<VkVertexInputAttributeDescription>()
    let bindingDescs = ExpandingBuffer<VkVertexInputBindingDescription>()
    var info = VkPipelineVertexInputStateCreateInfo()
    
    public init(descriptor: VertexDescriptor) {
        // Build Vertex input and binding info
        
        for (vbIndex, vertexBuffer) in descriptor.layouts.enumerated() where vertexBuffer.stride > 0 {
            var bindingDesc = VkVertexInputBindingDescription()
            bindingDesc.binding = UInt32(vbIndex)
            bindingDesc.stride = UInt32(vertexBuffer.stride)
            bindingDesc.inputRate = VkVertexInputRate(vertexBuffer.stepFunction)
            assert(vertexBuffer.stepRate <= 1)
            self.bindingDescs.append(bindingDesc)
        }
        
        for (index, attribute) in descriptor.attributes.enumerated() where attribute.format != .invalid {
            var attributeDesc = VkVertexInputAttributeDescription()
            attributeDesc.binding = UInt32(attribute.bufferIndex)
            attributeDesc.format = VkFormat(vertexFormat: attribute.format)
            attributeDesc.offset = UInt32(attribute.offset)
            attributeDesc.location = UInt32(index)
            self.attribDescs.append(attributeDesc)
        }
        
        // Now put together the actual layout create info
        self.info = VkPipelineVertexInputStateCreateInfo()
        self.info.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
        self.info.vertexBindingDescriptionCount = UInt32(self.bindingDescs.count)
        self.info.pVertexBindingDescriptions = UnsafePointer(self.bindingDescs.buffer)
        self.info.vertexAttributeDescriptionCount = UInt32(self.attribDescs.count)
        self.info.pVertexAttributeDescriptions = UnsafePointer(self.attribDescs.buffer)
    }
}

extension VkSamplerMipmapMode {
    public init(_ samplerMipFilter: SamplerMipFilter) {
        switch samplerMipFilter {
        case .nearest, .notMipmapped:
            self = VK_SAMPLER_MIPMAP_MODE_NEAREST
        case .linear:
            self = VK_SAMPLER_MIPMAP_MODE_LINEAR
        }
    }
}

extension VkFilter {
    public init(_ samplerMinMapFilter: SamplerMinMagFilter) {
        switch samplerMinMapFilter {
        case .nearest:
            self = VK_FILTER_NEAREST
        case .linear:
            self = VK_FILTER_LINEAR
        }
    }
}

extension VkSamplerAddressMode {
    public init(_ addressMode: SamplerAddressMode) {
        switch addressMode {
        case .repeat:
            self = VK_SAMPLER_ADDRESS_MODE_REPEAT
        case .clampToBorderColor:
            self = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER
        case .clampToEdge:
            self = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE
        case .mirrorClampToEdge:
            self = VK_SAMPLER_ADDRESS_MODE_MIRROR_CLAMP_TO_EDGE
        case .mirrorRepeat:
            self = VK_SAMPLER_ADDRESS_MODE_MIRRORED_REPEAT
        default:
            fatalError("Unsupported sampler address mode \(addressMode) on Vulkan.")
        }
    }
}

extension VkBorderColor {
    public init(_ samplerBorderColor: SamplerBorderColor) {
        switch samplerBorderColor {
        case .opaqueBlack:
            self = VK_BORDER_COLOR_FLOAT_OPAQUE_BLACK
        case .opaqueWhite:
            self = VK_BORDER_COLOR_FLOAT_OPAQUE_WHITE
        case .transparentBlack:
            self = VK_BORDER_COLOR_FLOAT_TRANSPARENT_BLACK
        }
    }
}

extension VkSamplerCreateInfo {
    public init(descriptor: SamplerDescriptor) {
        self.init()
        self.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
        self.magFilter = VkFilter(descriptor.magFilter)
        self.minFilter = VkFilter(descriptor.minFilter)
        self.mipmapMode = VkSamplerMipmapMode(descriptor.mipFilter)
        self.addressModeU = VkSamplerAddressMode(descriptor.sAddressMode)
        self.addressModeV = VkSamplerAddressMode(descriptor.tAddressMode)
        self.addressModeW = VkSamplerAddressMode(descriptor.rAddressMode)
        self.mipLodBias = 0.0
        self.anisotropyEnable = VkBool32(descriptor.maxAnisotropy > 1)
        self.maxAnisotropy = Float(descriptor.maxAnisotropy)
        self.compareEnable = VkBool32(descriptor.compareFunction != .always)
        self.compareOp = VkCompareOp(descriptor.compareFunction)
        self.minLod = descriptor.lodMinClamp
        self.maxLod = descriptor.lodMaxClamp
        self.borderColor = VkBorderColor(descriptor.borderColor)
        self.unnormalizedCoordinates = VkBool32(!descriptor.normalizedCoordinates)
    }
}

extension VkPipelineMultisampleStateCreateInfo {
    public init(_ descriptor: RenderPipelineDescriptor, sampleCount: Int) {
        self.init()
        self.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
        self.rasterizationSamples = VkSampleCountFlagBits(rawValue: VkSampleCountFlagBits.RawValue(sampleCount))
        self.sampleShadingEnable = false
        self.minSampleShading = 1.0
        self.pSampleMask = nil
        self.alphaToCoverageEnable = VkBool32(descriptor.isAlphaToCoverageEnabled)
        self.alphaToOneEnable = VkBool32(descriptor.isAlphaToOneEnabled)
    }
}

extension VkPrimitiveTopology {
    public init(_ primitiveType: PrimitiveType) {
        switch primitiveType {
        case .point:
            self = VK_PRIMITIVE_TOPOLOGY_POINT_LIST
        case .line:
            self = VK_PRIMITIVE_TOPOLOGY_LINE_LIST
        case .triangle:
            self = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
        case .triangleStrip:
            self = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP
        case .lineStrip:
            self = VK_PRIMITIVE_TOPOLOGY_LINE_STRIP
        }
    }
}

extension VkAttachmentDescription {
    public init(descriptor: TextureDescriptor, renderTargetDescriptor: ColorAttachmentDescriptor, actions: (VkAttachmentLoadOp, VkAttachmentStoreOp)) {
        self.init()
        self.flags = 0
        self.format = VkFormat(pixelFormat: descriptor.pixelFormat)!
        self.samples = VkSampleCountFlagBits(rawValue: UInt32(descriptor.sampleCount))
        self.loadOp = actions.0
        self.storeOp = actions.1
        self.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE // This is a color attachment
        self.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE // This is a color attachment
        self.initialLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
        self.finalLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
    }
    
    public init(descriptor: TextureDescriptor, renderTargetDescriptor: DepthAttachmentDescriptor, depthActions: (VkAttachmentLoadOp, VkAttachmentStoreOp), stencilActions: (VkAttachmentLoadOp, VkAttachmentStoreOp)) {
        self.init()
        self.flags = 0
        self.format = VkFormat(pixelFormat: descriptor.pixelFormat)!
        self.samples = VkSampleCountFlagBits(rawValue: UInt32(descriptor.sampleCount))
        self.loadOp = depthActions.0
        self.storeOp = depthActions.1
        self.stencilLoadOp = stencilActions.0
        self.stencilStoreOp = stencilActions.1
        self.initialLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
        self.finalLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
    }
}

extension VkFormat {
    init?(pixelFormat: PixelFormat) {
        switch pixelFormat {
        case .invalid:
            self = VK_FORMAT_UNDEFINED
            
        case .r8Unorm:
            self = VK_FORMAT_R8_UNORM
        case .r8Snorm:
            self = VK_FORMAT_R8_SNORM
        case .r16Unorm:
            self = VK_FORMAT_R16_UNORM
        case .r16Snorm:
            self = VK_FORMAT_R16_SNORM
        case .r16Float:
            self = VK_FORMAT_R16_SFLOAT
        case .r32Float:
            self = VK_FORMAT_R32_SFLOAT

        case .rg8Unorm:
            self = VK_FORMAT_R8G8_UNORM
        case .rg8Snorm:
            self = VK_FORMAT_R8G8_SNORM
        case .rg16Unorm:
            self = VK_FORMAT_R16G16_UNORM
        case .rg16Snorm:
            self = VK_FORMAT_R16G16_SNORM
        case .rg16Float:
            self = VK_FORMAT_R16G16_SFLOAT
        case .rg32Float:
            self = VK_FORMAT_R32G32_SFLOAT

        case .rgba8Unorm:
            self = VK_FORMAT_R8G8B8A8_UNORM
        case .rgba8Unorm_sRGB:
            self = VK_FORMAT_R8G8B8A8_SRGB
        case .rgba8Snorm:
            self = VK_FORMAT_R8G8B8A8_SNORM
        case .rgba16Unorm:
            self = VK_FORMAT_R16G16B16A16_UNORM
        case .rgba16Snorm:
            self = VK_FORMAT_R16G16B16A16_SNORM
        case .rgba16Float:
            self = VK_FORMAT_R16G16B16A16_SFLOAT
        case .rgba32Float:
            self = VK_FORMAT_R32G32B32A32_SFLOAT

        case .bgra8Unorm_sRGB:
            self = VK_FORMAT_B8G8R8A8_SRGB
        case .bgra8Unorm:
            self = VK_FORMAT_B8G8R8A8_UNORM
      
        case .depth16Unorm:
            self = VK_FORMAT_D16_UNORM
        case .depth32Float:
            self = VK_FORMAT_D32_SFLOAT
        case .depth24Unorm_stencil8:
            self = VK_FORMAT_D24_UNORM_S8_UINT
        case .depth32Float_stencil8:
            self = VK_FORMAT_D32_SFLOAT_S8_UINT
        default:
            return nil
        }
    }
}

extension VkFrontFace {
    init(_ winding: Winding) {
        switch winding {
        case .clockwise:
            self = VK_FRONT_FACE_CLOCKWISE
        case .counterClockwise:
            self = VK_FRONT_FACE_COUNTER_CLOCKWISE
        }
    }
}

final class SpecialisationInfo {
    let data = ExpandingBuffer<UInt8>()
    let mapEntries = ExpandingBuffer<VkSpecializationMapEntry>()
    var info : VkSpecializationInfo
    
    init(_ constants: FunctionConstants, constantIndices: [FunctionSpecialisation]) {
        self.info = VkSpecializationInfo()
        
        for (constant, value) in constants.namedConstants {
            guard let index = constantIndices.first(where: { $0.name == constant })?.index else {
                // print("Warning: function constant \(constant) unused.")
                continue
            }
            
            var mapEntry = VkSpecializationMapEntry()
            defer { self.mapEntries.append(mapEntry) }
            
            mapEntry.constantID = UInt32(index)
            mapEntry.offset = UInt32(self.data.count)
            
            switch value {
            case .bool(let bool):
                let value = VkBool32(bool)
                self.data.append(value)
                mapEntry.size = MemoryLayout.size(ofValue: value)
            case .int8(let value):
                self.data.append(value)
                mapEntry.size = MemoryLayout.size(ofValue: value)
            case .int16(let value):
                self.data.append(value)
                mapEntry.size = MemoryLayout.size(ofValue: value)
            case .int32(let value):
                self.data.append(value)
                mapEntry.size = MemoryLayout.size(ofValue: value)
            case .uint8(let value):
                self.data.append(value)
                mapEntry.size = MemoryLayout.size(ofValue: value)
            case .uint16(let value):
                self.data.append(value)
                mapEntry.size = MemoryLayout.size(ofValue: value)
            case .uint32(let value):
                self.data.append(value)
                mapEntry.size = MemoryLayout.size(ofValue: value)
            case .float(let value):
                self.data.append(value)
                mapEntry.size = MemoryLayout.size(ofValue: value)
            }
        }
        
        for constant in constants.indexedConstants {
            var mapEntry = VkSpecializationMapEntry()
            defer { self.mapEntries.append(mapEntry) }
            
            mapEntry.constantID = UInt32(constant.index)
            mapEntry.offset = UInt32(self.data.count)
            
            switch constant.value {
            case .bool(let bool):
                let value = VkBool32(bool)
                self.data.append(value)
                mapEntry.size = MemoryLayout.size(ofValue: value)
            case .int8(let value):
                self.data.append(value)
                mapEntry.size = MemoryLayout.size(ofValue: value)
            case .int16(let value):
                self.data.append(value)
                mapEntry.size = MemoryLayout.size(ofValue: value)
            case .int32(let value):
                self.data.append(value)
                mapEntry.size = MemoryLayout.size(ofValue: value)
            case .uint8(let value):
                self.data.append(value)
                mapEntry.size = MemoryLayout.size(ofValue: value)
            case .uint16(let value):
                self.data.append(value)
                mapEntry.size = MemoryLayout.size(ofValue: value)
            case .uint32(let value):
                self.data.append(value)
                mapEntry.size = MemoryLayout.size(ofValue: value)
            case .float(let value):
                self.data.append(value)
                mapEntry.size = MemoryLayout.size(ofValue: value)
            }
        }
        
        self.info.pData = UnsafeRawPointer(self.data.buffer)
        self.info.dataSize = self.data.count
        self.info.mapEntryCount = UInt32(self.mapEntries.count)
        self.info.pMapEntries = UnsafePointer(self.mapEntries.buffer)
    }
}

extension VkShaderStageFlagBits : OptionSet {
    init(_ stages: RenderStages) {
        self.init()
        if stages.contains(.vertex) {
            self.formUnion(VK_SHADER_STAGE_VERTEX_BIT)
        }
        if stages.contains(.fragment) {
            self.formUnion(VK_SHADER_STAGE_FRAGMENT_BIT)
        }
        if stages.contains(.compute) {
            self.formUnion(VK_SHADER_STAGE_COMPUTE_BIT)
        }
    }
}

extension VkImageUsageFlagBits {
    init(_ usage: TextureUsage, pixelFormat: PixelFormat) {
        self.init()
        
        if usage.contains(.blitSource) {
            self.formUnion(.transferSource)
        }
        if usage.contains(.blitDestination) {
            self.formUnion(.transferDestination)
        }
        if usage.contains(.shaderRead) {
            self.formUnion(.sampled)
        }
        if usage.contains(.shaderWrite) {
            self.formUnion(.storage)
        }
        if usage.contains(.renderTarget) {
            if pixelFormat.isDepth {
                self.formUnion(.depthStencilAttachment)
            } else {
                self.formUnion(.colorAttachment)
            }
            
            self.formUnion(.inputAttachment)
        }
    }
}

extension VkBufferUsageFlagBits {
    init(_ usage: BufferUsage) {
        self.init()
        
        if usage.contains(.blitSource) {
            self.formUnion(.transferSource)
        }
        if usage.contains(.blitDestination) {
            self.formUnion(.transferDestination)
        }
        if usage.contains(.shaderRead) {
            self.formUnion([.uniformBuffer, .uniformTexelBuffer, .storageBuffer, .storageTexelBuffer])
        }
        if usage.contains(.shaderWrite) {
            self.formUnion([.storageBuffer, .storageTexelBuffer])
        }
        if usage.contains(.vertexBuffer) {
            self.formUnion(.vertexBuffer)
        }
        if usage.contains(.indexBuffer) {
            self.formUnion(.indexBuffer)
        }
        if usage.contains(.indirectBuffer) {
            self.formUnion(.indirectBuffer)
        }
    }
}

#endif // canImport(Vulkan)
