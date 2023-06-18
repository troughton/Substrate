import WebGPU


extension WGPUAddressMode {
    init?(_ samplerMode: SamplerAddressMode) {
        switch samplerMode {
        case .clampToEdge:
            self = WGPUAddressMode_ClampToEdge
        case .repeat:
            self = WGPUAddressMode_Repeat
        case .mirrorRepeat:
            self = WGPUAddressMode_MirrorRepeat
        case .mirrorClampToEdge, .clampToZero, .clampToBorderColor:
            return nil
        }
    }
}

extension WGPUBlendFactor {
    init?(_ blendFactor: BlendFactor) {
        switch blendFactor {
        case .zero:
            self = WGPUBlendFactor_Zero
        case .one:
            self = WGPUBlendFactor_One
        case .sourceColor:
            self = WGPUBlendFactor_Src
        case .oneMinusSourceColor:
            self = WGPUBlendFactor_OneMinusSrc
        case .sourceAlpha:
            self = WGPUBlendFactor_SrcAlpha
        case .oneMinusSourceAlpha:
            self = WGPUBlendFactor_OneMinusSrcAlpha
        case .destinationColor:
            self = WGPUBlendFactor_Dst
        case .oneMinusDestinationColor:
            self = WGPUBlendFactor_OneMinusDst
        case .destinationAlpha:
            self = WGPUBlendFactor_DstAlpha
        case .oneMinusDestinationAlpha:
            self = WGPUBlendFactor_OneMinusDstAlpha
        case .sourceAlphaSaturated:
            self = WGPUBlendFactor_SrcAlphaSaturated
        case .blendColor, .blendAlpha:
            self = WGPUBlendFactor_Constant
        case .oneMinusBlendColor, .oneMinusBlendAlpha:
            self = WGPUBlendFactor_OneMinusConstant
        case .source1Color, .oneMinusSource1Color, .source1Alpha, .oneMinusSource1Alpha:
            return nil
        }
    }
}

extension WGPUBlendOperation {
    init(_ blendOperation: BlendOperation) {
        switch blendOperation {
        case .add:
            self = WGPUBlendOperation_Add
        case .subtract:
            self = WGPUBlendOperation_Subtract
        case .reverseSubtract:
            self = WGPUBlendOperation_ReverseSubtract
        case .min:
            self = WGPUBlendOperation_Min
        case .max:
            self = WGPUBlendOperation_Max
        }
    }
}

extension WGPUCompareFunction {
    init(_ compareFunction: CompareFunction) {
        switch compareFunction {
        case .never:
            self = WGPUCompareFunction_Undefined
        case .less:
            self = WGPUCompareFunction_Less
        case .equal:
            self = WGPUCompareFunction_Equal
        case .lessEqual:
            self = WGPUCompareFunction_LessEqual
        case .greater:
            self = WGPUCompareFunction_Greater
        case .notEqual:
            self = WGPUCompareFunction_NotEqual
        case .greaterEqual:
            self = WGPUCompareFunction_GreaterEqual
        case .always:
            self = WGPUCompareFunction_Always
        }
    }
}

extension WGPUCullMode {
    init(_ cullMode: CullMode) {
        switch cullMode {
        case .none:
            self = WGPUCullMode_None
        case .front:
            self = WGPUCullMode_Front
        case .back:
            self = WGPUCullMode_Back
        }
    }
}

extension WGPUFilterMode {
    init(_ filter: SamplerMinMagFilter) {
        switch filter {
        case .nearest:
            self = WGPUFilterMode_Nearest
        case .linear:
            self = WGPUFilterMode_Linear
        }
    }
}

extension WGPUFrontFace {
    init?(_ winding: Winding) {
        switch winding {
        case .clockwise:
            self = WGPUFrontFace_CW
        case .counterClockwise:
            self = WGPUFrontFace_CCW
        }
    }
}

extension WGPUIndexFormat {
    init?(_ indexType: IndexType) {
        switch indexType {
        case .uint16:
            self = WGPUIndexFormat_Uint16
        case .uint32:
            self = WGPUIndexFormat_Uint32
        }
    }
}

extension WGPULoadOp {
    init(_ clearOperation: some ClearOperation) {
        if clearOperation.isClear {
            self = WGPULoadOp_Clear
        } else if clearOperation.isKeep {
            self = WGPULoadOp_Load
        } else {
            self = WGPULoadOp_Undefined
        }
    }
}

extension WGPUMipmapFilterMode {
    init?(_ filter: SamplerMipFilter) {
        switch filter {
        case .notMipmapped:
            return nil
        case .nearest:
            self = WGPUMipmapFilterMode_Nearest
        case .linear:
            self = WGPUMipmapFilterMode_Linear
        }
    }
}

extension WGPUPrimitiveTopology {
    init(_ primitiveType: PrimitiveType) {
        switch primitiveType {
        case .point:
            self = WGPUPrimitiveTopology_PointList
        case .line:
            self = WGPUPrimitiveTopology_LineList
        case .lineStrip:
            self = WGPUPrimitiveTopology_LineStrip
        case .triangle:
            self = WGPUPrimitiveTopology_TriangleList
        case .triangleStrip:
            self = WGPUPrimitiveTopology_TriangleStrip
        }
    }
}

extension WGPUStencilOperation {
    init(_ operation: StencilOperation) {
        switch operation {
        case .keep:
            self = WGPUStencilOperation_Keep
        case .zero:
            self = WGPUStencilOperation_Zero
        case .replace:
            self = WGPUStencilOperation_Replace
        case .incrementClamp:
            self = WGPUStencilOperation_IncrementClamp
        case .decrementClamp:
            self = WGPUStencilOperation_DecrementClamp
        case .invert:
            self = WGPUStencilOperation_Invert
        case .incrementWrap:
            self = WGPUStencilOperation_IncrementWrap
        case .decrementWrap:
            self = WGPUStencilOperation_DecrementWrap
        }
    }
}

extension WGPUTextureFormat {
    init?(_ pixelFormat: PixelFormat) {
        switch pixelFormat {
        case .invalid:
            self = WGPUTextureFormat_Undefined
        case .a8Unorm:
            self = 
        case .r8Unorm:
            self = WGPUTextureFormat_R8Unorm
        case .r8Unorm_sRGB:
            self = 
        case .r8Snorm:
            self = WGPUTextureFormat_R8Snorm
        case .r8Uint:
            self = WGPUTextureFormat_R8Uint
        case .r8Sint:
            self = WGPUTextureFormat_R8Sint
        case .r16Unorm:
            self = 
        case .r16Snorm:
            self = 
        case .r16Uint:
            self = WGPUTextureFormat_R16Uint
        case .r16Sint:
            self = WGPUTextureFormat_R16Sint
        case .r16Float:
            self = WGPUTextureFormat_R16Float
        case .rg8Unorm:
            self = WGPUTextureFormat_RG8Unorm
        case .rg8Unorm_sRGB:
            self = 
        case .rg8Snorm:
            self = WGPUTextureFormat_RG8Snorm
        case .rg8Uint:
            self = WGPUTextureFormat_RG8Uint
        case .rg8Sint:
            self = WGPUTextureFormat_RG8Sint
        case .b5g6r5Unorm:
            self = 
        case .a1bgr5Unorm:
            self = 
        case .abgr4Unorm:
            self = 
        case .bgr5a1Unorm:
            self = 
        case .r32Uint:
            self = WGPUTextureFormat_R32Uint
        case .r32Sint:
            self = WGPUTextureFormat_R32Sint
        case .r32Float:
            self = WGPUTextureFormat_R32Float
        case .rg16Unorm:
            self = 
        case .rg16Snorm:
            self = 
        case .rg16Uint:
            self = WGPUTextureFormat_RG16Uint
        case .rg16Sint:
            self = WGPUTextureFormat_RG16Sint
        case .rg16Float:
            self = WGPUTextureFormat_RG16Float
        case .rgba8Unorm:
            self = WGPUTextureFormat_RGBA8Unorm
        case .rgba8Unorm_sRGB:
            self = WGPUTextureFormat_RGBA8UnormSrgb
        case .rgba8Snorm:
            self = WGPUTextureFormat_RGBA8Snorm
        case .rgba8Uint:
            self = WGPUTextureFormat_RGBA8Uint
        case .rgba8Sint:
            self = WGPUTextureFormat_RGBA8Sint
        case .bgra8Unorm:
            self = WGPUTextureFormat_BGRA8Unorm
        case .bgra8Unorm_sRGB:
            self = WGPUTextureFormat_BGRA8UnormSrgb
        case .rgb10a2Unorm:
            self = WGPUTextureFormat_RGB10A2Unorm
        case .rgb10a2Uint:
            return nil
        case .rg11b10Float:
            self = WGPUTextureFormat_RG11B10Ufloat
        case .rgb9e5Float:
            self = WGPUTextureFormat_RGB9E5Ufloat
        case .bgr10a2Unorm:
            return nil
        case .bgr10_xr, .bgr10_xr_sRGB:
            return nil
        case .rg32Uint:
            self = WGPUTextureFormat_RG32Uint
        case .rg32Sint:
            self = WGPUTextureFormat_RG32Sint
        case .rg32Float:
            self = WGPUTextureFormat_RG32Float
        case .rgba16Unorm, .rgba16Snorm:
            return nil
        case .rgba16Uint:
            self = WGPUTextureFormat_RGBA16Uint
        case .rgba16Sint:
            self = WGPUTextureFormat_RGBA16Sint
        case .rgba16Float:
            self = WGPUTextureFormat_RGBA16Float
        case .bgra10_xr, .bgra10_xr_sRGB:
            return nil
        case .rgba32Uint:
            self = WGPUTextureFormat_RGBA32Uint
        case .rgba32Sint:
            self = WGPUTextureFormat_RGBA32Sint
        case .rgba32Float:
            self = WGPUTextureFormat_RGBA32Float
        case .bc1_rgba:
            self = WGPUTextureFormat_BC1RGBAUnorm
        case .bc1_rgba_sRGB:
            self = WGPUTextureFormat_BC1RGBAUnormSrgb
        case .bc2_rgba:
            self = WGPUTextureFormat_BC2RGBAUnorm
        case .bc2_rgba_sRGB:
            self = WGPUTextureFormat_BC2RGBAUnormSrgb
        case .bc3_rgba:
            self = WGPUTextureFormat_BC3RGBAUnorm
        case .bc3_rgba_sRGB:
            self = WGPUTextureFormat_BC3RGBAUnormSrgb
        case .bc4_rUnorm:
            self = WGPUTextureFormat_BC4RUnorm
        case .bc4_rSnorm:
            self = WGPUTextureFormat_BC4RSnorm
        case .bc5_rgUnorm:
            self = WGPUTextureFormat_BC5RGUnorm
        case .bc5_rgSnorm:
            self = WGPUTextureFormat_BC5RGSnorm
        case .bc6H_rgbFloat:
            self = WGPUTextureFormat_BC6HRGBFloat
        case .bc6H_rgbuFloat:
            self = WGPUTextureFormat_BC6HRGBUfloat
        case .bc7_rgbaUnorm:
            self = WGPUTextureFormat_BC7RGBAUnorm
        case .bc7_rgbaUnorm_sRGB:
            self = WGPUTextureFormat_BC7RGBAUnormSrgb
        case .gbgr422, .bgrg422:
            return nil
        case .depth16Unorm:
            self = WGPUTextureFormat_Depth16Unorm
        case .depth32Float:
            self = WGPUTextureFormat_Depth32Float
        case .stencil8:
            self = WGPUTextureFormat_Stencil8
        case .depth24Unorm_stencil8:
            self = WGPUTextureFormat_Depth24PlusStencil8
        case .depth32Float_stencil8:
            self = WGPUTextureFormat_Depth32FloatStencil8
        case .x32_stencil8, .x24_stencil8:
            return nil
        case .astc_4x4_ldr:
            self = WGPUTextureFormat_ASTC4x4Unorm
        case .astc_4x4_sRGB:
            self = WGPUTextureFormat_ASTC4x4UnormSrgb
        case .astc_5x4_ldr:
            self = WGPUTextureFormat_ASTC5x4Unorm
        case .astc_5x4_sRGB:
            self = WGPUTextureFormat_ASTC5x4UnormSrgb
        case .astc_5x5_ldr:
            self = WGPUTextureFormat_ASTC5x5Unorm
        case .astc_5x5_sRGB:
            self = WGPUTextureFormat_ASTC5x5UnormSrgb
        case .astc_6x5_ldr:
            self = WGPUTextureFormat_ASTC6x5Unorm
        case .astc_6x5_sRGB:
            self = WGPUTextureFormat_ASTC6x5UnormSrgb
        case .astc_6x6_ldr:
            self = WGPUTextureFormat_ASTC6x6Unorm
        case .astc_6x6_sRGB:
            self = WGPUTextureFormat_ASTC6x6UnormSrgb
        case .astc_8x5_ldr:
            self = WGPUTextureFormat_ASTC8x5Unorm
        case .astc_8x5_sRGB:
            self = WGPUTextureFormat_ASTC8x5UnormSrgb
        case .astc_8x6_ldr:
            self = WGPUTextureFormat_ASTC8x6Unorm
        case .astc_8x6_sRGB:
            self = WGPUTextureFormat_ASTC8x6UnormSrgb
        case .astc_8x8_ldr:
            self = WGPUTextureFormat_ASTC8x8Unorm
        case .astc_8x8_sRGB:
            self = WGPUTextureFormat_ASTC8x8UnormSrgb
        case .astc_10x5_ldr:
            self = WGPUTextureFormat_ASTC10x5Unorm
        case .astc_10x5_sRGB:
            self = WGPUTextureFormat_ASTC10x5UnormSrgb
        case .astc_10x6_ldr:
            self = WGPUTextureFormat_ASTC10x6Unorm
        case .astc_10x6_sRGB:
            self = WGPUTextureFormat_ASTC10x6UnormSrgb
        case .astc_10x8_ldr:
            self = WGPUTextureFormat_ASTC10x8Unorm
        case .astc_10x8_sRGB:
            self = WGPUTextureFormat_ASTC10x8UnormSrgb
        case .astc_10x10_ldr:
            self = WGPUTextureFormat_ASTC10x10Unorm
        case .astc_12x10_ldr:
            self = WGPUTextureFormat_ASTC12x10UnormSrgb
        case .astc_12x10_sRGB:
            self = WGPUTextureFormat_ASTC12x10UnormSrgb
        case .astc_12x12_ldr:
            self = WGPUTextureFormat_ASTC12x12UnormSrgb
        case .astc_12x12_sRGB:
            self = WGPUTextureFormat_ASTC12x12UnormSrgb
        }
    }
}

extension WGPUTextureViewDimension {
    init?(_ textureType: TextureType) {
        switch textureType {
        case .type1D:
            self = WGPUTextureViewDimension_1D
        case .type1DArray:
            return nil
        case .type2D, .type2DMultisample:
            self = WGPUTextureViewDimension_2D
        case .type2DArray, .type2DMultisampleArray:
            self = WGPUTextureViewDimension_2DArray
        case .typeCube:
            self = WGPUTextureViewDimension_Cube
        case .typeCubeArray:
            self = WGPUTextureViewDimension_CubeArray
        case .type3D:
            self = WGPUTextureViewDimension_3D
        case .typeTextureBuffer:
            return nil
        }
    }
}

extension WGPUVertexFormat {
    init?(_ vertexFormat: VertexFormat) {
        switch vertexFormat {
        case .invalid:
            self = WGPUVertexFormat_Undefined
        case .uchar2:
            self = WGPUVertexFormat_Uint8x2
        case .uchar3:
            return nil
        case .uchar4:
            self = WGPUVertexFormat_Uint8x4
        case .char2:
            self = WGPUVertexFormat_Sint8x2
        case .char3:
            return nil
        case .char4:
            self = WGPUVertexFormat_Sint8x4
        case .uchar2Normalized:
            self = WGPUVertexFormat_Unorm8x2
        case .uchar3Normalized:
            return nil
        case .uchar4Normalized:
            self = WGPUVertexFormat_Unorm8x4
        case .char2Normalized:
            self = WGPUVertexFormat_Snorm8x2
        case .char3Normalized:
            return nil
        case .char4Normalized:
            self = WGPUVertexFormat_Snorm8x4
        case .ushort2:
            self = WGPUVertexFormat_Uint16x2
        case .ushort3:
            return nil
        case .ushort4:
            self = WGPUVertexFormat_Uint16x4
        case .short2:
            self = WGPUVertexFormat_Sint16x2
        case .short3:
            return nil
        case .short4:
            self = WGPUVertexFormat_Uint16x4
        case .ushort2Normalized:
            self = WGPUVertexFormat_Unorm16x2
        case .ushort3Normalized:
            return nil
        case .ushort4Normalized:
            self = WGPUVertexFormat_Unorm16x4
        case .short2Normalized:
            self = WGPUVertexFormat_Snorm16x2
        case .short3Normalized:
            return nil
        case .short4Normalized:
            self = WGPUVertexFormat_Unorm16x4
        case .half2:
            self = WGPUVertexFormat_Float16x2
        case .half3:
            return nil
        case .half4:
            self = WGPUVertexFormat_Float16x4
        case .float:
            self = WGPUVertexFormat_Float32
        case .float2:
            self = WGPUVertexFormat_Float32x2
        case .float3:
            self = WGPUVertexFormat_Float32x3
        case .float4:
            self = WGPUVertexFormat_Float32x4
        case .int:
            self = WGPUVertexFormat_Sint32
        case .int2:
            self = WGPUVertexFormat_Sint32x2
        case .int3:
            self = WGPUVertexFormat_Sint32x3
        case .int4:
            self = WGPUVertexFormat_Sint32x4
        case .uint:
            self = WGPUVertexFormat_Uint32
        case .uint2:
            self = WGPUVertexFormat_Uint32x2
        case .uint3:
            self = WGPUVertexFormat_Uint32x3
        case .uint4:
            self = WGPUVertexFormat_Uint32x4
        case .int1010102Normalized, .uint1010102Normalized:
            return nil
        }
    }
}

extension WGPUVertexStepMode {
    init?(_ stepFunction: VertexStepFunction) {
        switch stepFunction {
        case .constant:
            self = WGPUVertexStepMode_VertexBufferNotUsed
        case .perVertex:
            self = WGPUVertexStepMode_Vertex
        case .perInstance:
            self = WGPUVertexStepMode_Instance
        case .perPatch, .perPatchControlPoint:
            return nil
        }
    }
}

extension WGPUBufferUsage: OptionSet {
    init(_ bufferUsage: BufferUsage) {
        self = WGPUBufferUsage_None
        if bufferUsage.contains(.cpuRead) { self.formUnion(WGPUBufferUsage_MapRead) }
        if bufferUsage.contains(.cpuWrite) { self.formUnion(WGPUBufferUsage_MapWrite) }
        if bufferUsage.contains(.blitSource) { self.formUnion(WGPUBufferUsage_CopySrc) }
        if bufferUsage.contains(.blitDestination) { self.formUnion(WGPUBufferUsage_CopyDst) }
        if bufferUsage.contains(.indexBuffer) { self.formUnion(WGPUBufferUsage_Index) }
        if bufferUsage.contains(.vertexBuffer) { self.formUnion(WGPUBufferUsage_Vertex) }
        if bufferUsage.contains(.shaderRead) { self.formUnion(WGPUBufferUsage_Uniform) }
        if bufferUsage.contains(.constantBuffer) { self.formUnion(WGPUBufferUsage_Uniform) }
        if bufferUsage.contains(.shaderWrite) { self.formUnion(WGPUBufferUsage_Storage) }
        if bufferUsage.contains(.indirectBuffer) { self.formUnion(WGPUBufferUsage_Indirect) }
    }
}

extension WGPUColorWriteMask: OptionSet {
    init(_ writeMask: ColorWriteMask) {
        self = WGPUColorWriteMask_None
        if writeMask.contains(.red) { self.formUnion(WGPUColorWriteMask_Red) }
        if writeMask.contains(.green) { self.formUnion(WGPUColorWriteMask_Green) }
        if writeMask.contains(.blue) { self.formUnion(WGPUColorWriteMask_Blue) }
        if writeMask.contains(.alpha) { self.formUnion(WGPUColorWriteMask_Alpha) }
    }
}

extension WGPUShaderStage: OptionSet {
    init?(_ shaderStages: RenderStages) {
        self = WGPUShaderStage_None
        
        if shaderStages.contains(.vertex) { self.formUnion(WGPUShaderStage_Vertex) }
        if shaderStages.contains(.fragment) { self.formUnion(WGPUShaderStage_Fragment) }
        if shaderStages.contains(.compute) { self.formUnion(WGPUShaderStage_Compute) }
    }
}

extension WGPUTextureUsage: OptionSet {
    init(_ textureUsage: TextureUsage) {
        self = WGPUTextureUsage_None
        if textureUsage.contains(.blitSource) { self.formUnion(WGPUTextureUsage_CopySrc) }
        if textureUsage.contains(.blitDestination) { self.formUnion(WGPUTextureUsage_CopyDst) }
        if textureUsage.contains(.shaderRead) {
            self.formUnion(WGPUTextureUsage_TextureBinding)
        }
        if textureUsage.contains(.shaderWrite) {
            self.formUnion(WGPUTextureUsage_StorageBinding)
        }
        if !textureUsage.intersection([.colorAttachment, .depthStencilAttachment, .inputAttachment]).isEmpty {
            self.formUnion(WGPUTextureUsage_RenderAttachment)
        }
    }
}
