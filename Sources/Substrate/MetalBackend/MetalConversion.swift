//
//  Conversion.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 24/12/17.
//

#if canImport(Metal)

import Metal

//MARK: From Metal

extension ResourcePurgeableState {
    public init?(_ state: MTLPurgeableState) {
        switch state {
        case .keepCurrent:
            return nil
        case .empty:
            self = .discarded
        case .nonVolatile:
            self = .nonDiscardable
        case .volatile:
            self = .discardable
        @unknown default:
            fatalError()
        }
    }
}

extension Texture {
    public init(metalTexture: MTLTexture) {
        self = Texture(descriptor: TextureDescriptor(from: metalTexture), externalResource: metalTexture)
    }
}

extension TextureDescriptor {
    public init(from mtlTexture: MTLTexture) {
        self.init()
        
        self.textureType = TextureType(mtlTexture.textureType)
        self.pixelFormat = PixelFormat(mtlTexture.pixelFormat)
        self.width = mtlTexture.width
        self.height = mtlTexture.height
        self.depth = mtlTexture.depth
        self.mipmapLevelCount = mtlTexture.mipmapLevelCount
        self.sampleCount = mtlTexture.sampleCount
        self.arrayLength = mtlTexture.arrayLength
        self.storageMode = StorageMode(mtlTexture.storageMode)
        self.cacheMode = CPUCacheMode(mtlTexture.cpuCacheMode)
        self.usageHint = TextureUsage(mtlTexture.usage)
    }
}

extension TextureType {
    public init(_ type: MTLTextureType) {
        switch type {
        case .type1D:
            self = .type1D
        case .type1DArray:
            self = .type1DArray
        case .type2D:
            self = .type2D
        case .type2DArray:
            self = .type2DArray
        case .type2DMultisample:
            self = .type2DMultisample
        case .typeCube:
            self = .typeCube
        case .typeCubeArray:
            self = .typeCubeArray
        case .type3D:
            self = .type3D
        case .type2DMultisampleArray:
            self = .type2DMultisampleArray
        case .typeTextureBuffer:
            self = .typeTextureBuffer
        @unknown default:
            fatalError()
        }
    }
}

extension StorageMode {
    public init(_ mode: MTLStorageMode) {
        switch mode {
        case .shared:
            self = .shared
        case .managed:
            self = .managed
        case .private:
            self = .private
        case .memoryless:
            self = .private
        @unknown default:
            fatalError()
        }
    }
}

extension CPUCacheMode {
    public init(_ cacheMode: MTLCPUCacheMode) {
        switch cacheMode {
        case .defaultCache:
            self = .defaultCache
        case .writeCombined:
            self = .writeCombined
        @unknown default:
            self = .defaultCache
        }
    }
}

extension DataType {
    public init?(_ dataType: MTLDataType) {
        switch dataType {
        case .none:
            self = .none
        case .struct:
            self = .struct
        case .array:
            self = .array
        case .float:
            self = .float
        case .float2:
            self = .float2
        case .float3:
            self = .float3
        case .float4:
            self = .float4
        case .float2x2:
            self = .float2x2
        case .float2x3:
            self = .float2x3
        case .float2x4:
            self = .float2x4
        case .float3x2:
            self = .float3x2
        case .float3x3:
            self = .float3x3
        case .float3x4:
            self = .float3x4
        case .float4x2:
            self = .float4x2
        case .float4x3:
            self = .float4x3
        case .float4x4:
            self = .float4x4
        case .half:
            self = .half
        case .half2:
            self = .half2
        case .half3:
            self = .half3
        case .half4:
            self = .half4
        case .half2x2:
            self = .half2x2
        case .half2x3:
            self = .half2x3
        case .half2x4:
            self = .half2x4
        case .half3x2:
            self = .half3x2
        case .half3x3:
            self = .half3x3
        case .half3x4:
            self = .half3x4
        case .half4x2:
            self = .half4x2
        case .half4x3:
            self = .half4x3
        case .half4x4:
            self = .half4x4
        case .int:
            self = .int
        case .int2:
            self = .int2
        case .int3:
            self = .int3
        case .int4:
            self = .int4
        case .uint:
            self = .uint
        case .uint2:
            self = .uint2
        case .uint3:
            self = .uint3
        case .uint4:
            self = .uint4
        case .short:
            self = .short
        case .short2:
            self = .short2
        case .short3:
            self = .short3
        case .short4:
            self = .short4
        case .ushort:
            self = .ushort
        case .ushort2:
            self = .ushort2
        case .ushort3:
            self = .ushort3
        case .ushort4:
            self = .ushort4
        case .char:
            self = .char
        case .char2:
            self = .char2
        case .char3:
            self = .char3
        case .char4:
            self = .char4
        case .uchar:
            self = .uchar
        case .uchar2:
            self = .uchar2
        case .uchar3:
            self = .uchar3
        case .uchar4:
            self = .uchar4
        case .bool:
            self = .bool
        case .bool2:
            self = .bool2
        case .bool3:
            self = .bool3
        case .bool4:
            self = .bool4
        default:
            return nil
        }
    }
}

extension TextureUsage {
    public init(_ usage: MTLTextureUsage) {
        self.init()
        
        if usage.contains(.shaderRead) {
            self.formUnion(.shaderRead)
        }
        if usage.contains(.shaderWrite) {
            self.formUnion(.shaderWrite)
        }
        if usage.contains(.renderTarget) {
            self.formUnion([.colorAttachment, .depthStencilAttachment])
        }
        if usage.contains(.pixelFormatView) {
            self.formUnion(.pixelFormatView)
        }
    }
}

extension ResourceAccessType {
    public init(_ type: MTLArgumentAccess) {
        switch type {
        case .readOnly:
            self = .read
        case .readWrite:
            self = .readWrite
        case .writeOnly:
            self = .write
        @unknown default:
            fatalError()
        }
    }
}

extension ResourceType {
    public init(_ type: MTLArgumentType) {
        switch type {
        case .buffer:
            self = .buffer
        case .sampler:
            self = .sampler
        case .texture:
            self = .texture
        case .threadgroupMemory:
            self = .threadgroupMemory
        case .imageblockData:
            self = .imageblockData
        case .imageblock:
            self = .imageblock
        case .visibleFunctionTable:
            self = .visibleFunctionTable
        case .primitiveAccelerationStructure:
            self = .accelerationStructure
        case .instanceAccelerationStructure:
            self = .accelerationStructure
        case .intersectionFunctionTable:
            self = .intersectionFunctionTable
        @unknown default:
            fatalError()
        }
    }
    
    public init(_ type: MTLBindingType) {
        switch type {
        case .buffer:
            self = .buffer
        case .sampler:
            self = .sampler
        case .texture:
            self = .texture
        case .threadgroupMemory:
            self = .threadgroupMemory
        case .imageblockData:
            self = .imageblockData
        case .imageblock:
            self = .imageblock
        case .visibleFunctionTable:
            self = .visibleFunctionTable
        case .primitiveAccelerationStructure:
            self = .accelerationStructure
        case .instanceAccelerationStructure:
            self = .accelerationStructure
        case .intersectionFunctionTable:
            self = .intersectionFunctionTable
        case .objectPayload:
            self = .objectPayload
        @unknown default:
            fatalError()
        }
    }
}

extension ResourceUsageType {
    public init(_ access: MTLArgumentAccess) {
        switch access {
        case .readOnly:
            self = .shaderRead
        case .readWrite:
            self = .shaderReadWrite
        case .writeOnly:
            self = .shaderWrite
        @unknown default:
            fatalError()
        }
    }
}

extension RenderStages {
    public init(_ mtlStages: MTLRenderStages) {
        var stages = RenderStages(rawValue: 0) // Array literal causes problems for -Onone performance.
        if mtlStages == MTLRenderStages(rawValue: 0) {
            stages = .compute
        } else {
            if mtlStages.contains(.vertex) {
                stages.formUnion(.vertex)
            }
            if mtlStages.contains(.fragment) {
                stages.formUnion(.fragment)
            }
        }
        self = stages
    }
}

extension PixelFormat {
    public init(_ pixelFormat: MTLPixelFormat) {
        self.init(rawValue: UInt16(truncatingIfNeeded: pixelFormat.rawValue))!
    }
}

extension ArgumentReflection {
    init(_ argument: MTLArgument, bindingPath: ResourceBindingPath, stages: RenderStages) {
        var activeRange: ActiveResourceRange = argument.isActive ? .fullResource : .inactive
        if case .buffer = argument.type {
            activeRange = .buffer(0..<argument.bufferDataSize)
        }
        self.init(type: ResourceType(argument.type), bindingPath: bindingPath, arrayLength: argument.arrayLength, usageType: ResourceUsageType(argument.access), activeStages: argument.isActive ? stages : [], activeRange: activeRange)
    }
    
    @available(macOS 13.0, iOS 16.0, *)
    init(_ binding: MTLBinding, bindingPath: ResourceBindingPath, stages: RenderStages) {
        var activeRange: ActiveResourceRange = binding.isUsed ? .fullResource : .inactive
        if let bufferBinding = binding as? MTLBufferBinding {
            activeRange = .buffer(0..<bufferBinding.bufferDataSize)
        }
        self.init(type: ResourceType(binding.type), bindingPath: bindingPath, arrayLength: (binding as? MTLTextureBinding)?.arrayLength ?? 1, usageType: ResourceUsageType(binding.access), activeStages: binding.isUsed ? stages : [], activeRange: activeRange)
    }
    
    init(member: MTLStructMember, argumentBuffer: MTLArgument, bindingPath: ResourceBindingPath, stages: RenderStages) {
        let type : ResourceType
        let usageType : ResourceUsageType
        
        var activeRange: ActiveResourceRange = argumentBuffer.isActive ? .fullResource : .inactive
        
        switch member.dataType {
        case .texture:
            type = .texture
            usageType = ResourceUsageType(member.textureReferenceType()!.access)
        case .sampler:
            type = .sampler
            usageType = []
        default:
            type = .buffer
            if let arrayType = member.arrayType() {
                activeRange = .buffer(0..<arrayType.arrayLength * arrayType.stride)
            } else if let pointerType = member.pointerType() {
                activeRange = .buffer(0..<pointerType.dataSize)
            }
            usageType = ResourceUsageType(member.pointerType()?.access ?? .readOnly) // It might be POD, in which case the usage is read only.
        }
        
        self.init(type: type, bindingPath: bindingPath, arrayLength: member.arrayType()?.arrayLength ?? 1, usageType: usageType, activeStages: argumentBuffer.isActive ? stages : [], activeRange: activeRange)
    }
    
    @available(macOS 13.0, iOS 16.0, *)
    init(member: MTLStructMember, argumentBuffer: MTLBinding, bindingPath: ResourceBindingPath, stages: RenderStages) {
        let type : ResourceType
        let usageType : ResourceUsageType
        
        var activeRange: ActiveResourceRange = argumentBuffer.isUsed ? .fullResource : .inactive
        
        switch member.dataType {
        case .texture:
            type = .texture
            usageType = ResourceUsageType(member.textureReferenceType()!.access)
        case .sampler:
            type = .sampler
            usageType = []
        default:
            type = .buffer
            if let arrayType = member.arrayType() {
                activeRange = .buffer(0..<arrayType.arrayLength * arrayType.stride)
            } else if let pointerType = member.pointerType() {
                activeRange = .buffer(0..<pointerType.dataSize)
            }
            usageType = ResourceUsageType(member.pointerType()?.access ?? .readOnly) // It might be POD, in which case the usage is read only.
        }
        
        self.init(type: type, bindingPath: bindingPath, arrayLength: member.arrayType()?.arrayLength ?? 1, usageType: usageType, activeStages: argumentBuffer.isUsed ? stages : [], activeRange: activeRange)
    }
    
    init?(array: MTLArrayType, argumentBuffer: MTLArgument, bindingPath: ResourceBindingPath, stages: RenderStages) {
        let type : ResourceType
        let usageType : ResourceUsageType
        
        var activeRange: ActiveResourceRange = argumentBuffer.isActive ? .fullResource : .inactive
        
        switch array.elementType {
        case .texture:
            type = .texture
            guard let textureReferenceType = array.elementTextureReferenceType() else { return nil }
            usageType = ResourceUsageType(textureReferenceType.access)
        case .sampler:
            type = .sampler
            usageType = []
        default:
            type = .buffer
            guard let elementPointerType = array.elementPointerType() else { return nil }
            usageType = ResourceUsageType(elementPointerType.access)
            activeRange = .buffer(0..<elementPointerType.dataSize)
        }
        
        self.init(type: type, bindingPath: bindingPath, arrayLength: array.arrayLength, usageType: usageType, activeStages: argumentBuffer.isActive ? stages : [], activeRange: activeRange)
    }
    
    @available(macOS 13.0, iOS 16.0, *)
    init?(array: MTLArrayType, argumentBuffer: MTLBinding, bindingPath: ResourceBindingPath, stages: RenderStages) {
        let type : ResourceType
        let usageType : ResourceUsageType
        
        var activeRange: ActiveResourceRange = argumentBuffer.isUsed ? .fullResource : .inactive
        
        switch array.elementType {
        case .texture:
            type = .texture
            guard let textureReferenceType = array.elementTextureReferenceType() else { return nil }
            usageType = ResourceUsageType(textureReferenceType.access)
        case .sampler:
            type = .sampler
            usageType = []
        default:
            type = .buffer
            guard let elementPointerType = array.elementPointerType() else { return nil }
            usageType = ResourceUsageType(elementPointerType.access)
            activeRange = .buffer(0..<elementPointerType.dataSize)
        }
        
        self.init(type: type, bindingPath: bindingPath, arrayLength: array.arrayLength, usageType: usageType, activeStages: argumentBuffer.isUsed ? stages : [], activeRange: activeRange)
    }
    
}

//MARK: To Metal

extension ArgumentBufferDescriptor {
    public var argumentDescriptors: [MTLArgumentDescriptor] {
        return self.arguments.map { argument in
            let result = MTLArgumentDescriptor()
            result.index = argument.index
            result.arrayLength = argument.arrayLength
            result.access = MTLArgumentAccess(argument.accessType)
            switch argument.resourceType {
            case .inlineData(let dataType):
                result.dataType = MTLDataType(dataType)
            case .constantBuffer(let alignment):
                result.dataType = .pointer
                result.constantBlockAlignment = alignment
            case .storageBuffer, .argumentBuffer:
                result.dataType = .pointer
            case .texture(let textureType):
                result.dataType = .texture
                result.textureType = MTLTextureType(textureType)
            case .sampler:
                result.dataType = .sampler
            case .accelerationStructure:
                result.dataType = .pointer
            }
            return result
        }
    }
}

extension MTLArgumentAccess {
    init(_ access: ResourceAccessType) {
        switch access {
        case .read:
            self = .readOnly
        case .readWrite:
            self = .readWrite
        case .write:
            self = .writeOnly
        default:
            preconditionFailure()
        }
    }
}

extension MTLBarrierScope {
    init(_ barrierScope: BarrierScope, isAppleSiliconGPU: Bool) {
        self = []
        if barrierScope.contains(.buffers) {
            self.formUnion(.buffers)
        }
        if barrierScope.contains(.textures) {
            self.formUnion(.textures)
        }
        #if os(macOS) || targetEnvironment(macCatalyst)
        if barrierScope.contains(.renderTargets), !isAppleSiliconGPU {
            self.formUnion(.renderTargets)
        }
        #endif
    }
}

extension MTLBlendFactor {
    public init(_ blendFactor: BlendFactor) {
        self.init(rawValue: UInt(blendFactor.rawValue))!
    }
}

extension MTLBlendOperation {
    public init(_ blendOperation: BlendOperation) {
        self.init(rawValue: UInt(blendOperation.rawValue))!
    }
}

extension MTLBlitOption {
    public init(_ option: BlitOption) {
        self.init(rawValue: option.rawValue)
    }
}

extension MTLCompareFunction {
    public init(_ compareFunction: CompareFunction) {
        self.init(rawValue: UInt(compareFunction.rawValue))!
    }
}

extension MTLClearColor {
    public init(_ clearColor: ClearColor) {
        self.init(red: clearColor.red, green: clearColor.green, blue: clearColor.blue, alpha: clearColor.alpha)
    }
}

extension MTLColorWriteMask {
    public init(_ colorWriteMask: ColorWriteMask) {
        self.init(rawValue: UInt(colorWriteMask.rawValue))
    }
}

extension MTLCPUCacheMode {
    public init(_ mode: CPUCacheMode) {
        self.init(rawValue: UInt(mode.rawValue))!
    }
}

extension MTLCullMode {
    public init(_ mode: CullMode) {
        self.init(rawValue: UInt(mode.rawValue))!
    }
}

extension MTLTriangleFillMode {
    public init(_ mode: TriangleFillMode) {
        self.init(rawValue: UInt(mode.rawValue))!
    }
}

extension MTLDataType {
    public init(_ dataType: DataType) {
        self.init(rawValue: UInt(dataType.rawValue))!
    }
}

extension MTLDepthClipMode {
    public init(_ depthClipMode: DepthClipMode) {
        switch depthClipMode {
        case .clip:
            self = .clip
        case .clamp:
            self = .clamp
        }
    }
}

extension MTLFunctionConstantValues {
    convenience init(_ constants: FunctionConstants) {
        self.init()
        
        for indexedConstant in constants.indexedConstants {
            switch indexedConstant.value {
            case .bool(var value):
                self.setConstantValue(&value, type: .bool, index: indexedConstant.index)
            case .float(var value):
                self.setConstantValue(&value, type: .float, index: indexedConstant.index)
            case .uint8(var value):
                self.setConstantValue(&value, type: .uchar, index: indexedConstant.index)
            case .uint16(var value):
                self.setConstantValue(&value, type: .ushort, index: indexedConstant.index)
            case .uint32(var value):
                self.setConstantValue(&value, type: .uint, index: indexedConstant.index)
            case .int8(var value):
                self.setConstantValue(&value, type: .char, index: indexedConstant.index)
            case .int16(var value):
                self.setConstantValue(&value, type: .short, index: indexedConstant.index)
            case .int32(var value):
                self.setConstantValue(&value, type: .int, index: indexedConstant.index)
            }
        }
        
        for (key, constant) in constants.namedConstants {
            switch constant {
            case .bool(var value):
                self.setConstantValue(&value, type: .bool, withName: key)
            case .float(var value):
                self.setConstantValue(&value, type: .float, withName: key)
            case .uint8(var value):
                self.setConstantValue(&value, type: .uchar, withName: key)
            case .uint16(var value):
                self.setConstantValue(&value, type: .ushort, withName: key)
            case .uint32(var value):
                self.setConstantValue(&value, type: .uint, withName: key)
            case .int8(var value):
                self.setConstantValue(&value, type: .char, withName: key)
            case .int16(var value):
                self.setConstantValue(&value, type: .short, withName: key)
            case .int32(var value):
                self.setConstantValue(&value, type: .int, withName: key)
            }
        }
    }
}

extension MTLIndexType {
    public init(_ type: IndexType) {
        self.init(rawValue: UInt(type.rawValue))!
    }
}

extension MTLOrigin {
    public init(_ origin: Origin) {
        self.init(x: origin.x, y: origin.y, z: origin.z)
    }
}

extension MTLPrimitiveType {
    public init(_ type: PrimitiveType) {
        self.init(rawValue: UInt(type.rawValue))!
    }
}


extension MTLPixelFormat {
    public init(_ pixelFormat: PixelFormat) {
        self.init(rawValue: UInt(pixelFormat.rawValue))!
    }
}

extension MTLPurgeableState {
    public init(_ state: ResourcePurgeableState?) {
        guard let state = state else {
            self = .keepCurrent
            return
        }
        switch state {
        case .discardable:
            self = .volatile
        case .nonDiscardable:
            self = .nonVolatile
        case .discarded:
            self = .empty
        }
    }
}


extension MTLRegion {
    public init(_ region: Region) {
        self.init(origin: MTLOrigin(region.origin), size: MTLSize(region.size))
    }
}

extension MTLRenderStages {
    public init(_ renderStages: RenderStages) {
        self = MTLRenderStages(rawValue: 0)
        
        if renderStages.contains(.vertex) {
            self.formUnion(.vertex)
        }
        if renderStages.contains(.fragment) {
            self.formUnion(.fragment)
        }
        if renderStages.contains(.tile), #available(macOS 12.0, iOS 15.0, *) {
            self.formUnion(.tile)
        }
        if renderStages.contains(.mesh), #available(macOS 13.0, iOS 16.0, *) {
            self.formUnion(.mesh)
        }
        if renderStages.contains(.object), #available(macOS 13.0, iOS 16.0, *) {
            self.formUnion(.object)
        }
    }
}

extension MTLResourceOptions {
    public init(storageMode: StorageMode, cacheMode: CPUCacheMode, isAppleSiliconGPU: Bool) {
        self.init()
        
        switch storageMode {
        case .shared:
            self.formUnion(.storageModeShared)
        case .managed:
            #if os(macOS) || targetEnvironment(macCatalyst)
            if !isAppleSiliconGPU {
                self.formUnion(.storageModeManaged)
            } else {
                self.formUnion(.storageModeShared)
            }
            #else
            self.formUnion(.storageModeShared)
            #endif
        case .private:
            self.formUnion(.storageModePrivate)
        }
        
        switch cacheMode {
        case .defaultCache:
            break
        case .writeCombined:
            self.formUnion(.cpuCacheModeWriteCombined)
        }
        
        self.formUnion(.substrateTrackedHazards)
    }
}

extension MTLResourceUsage {
    public init(_ usage: ResourceUsageType, isAppleSiliconGPU: Bool) {
        self.init(rawValue: 0)
        
        if !usage.intersection([.shaderRead, .vertexBuffer, .indexBuffer, .constantBuffer, .blitSource]).isEmpty {
            self.formUnion(.read)
        }
        if usage.contains(.inputAttachment), !isAppleSiliconGPU {
            self.formUnion(.read)
        }
        if usage.contains(.shaderWrite) {
            self.formUnion(.write)
        }
    }
}

extension MTLSamplerAddressMode {
    public init(_ mode: SamplerAddressMode) {
        self.init(rawValue: mode.rawValue)!
    }
}

#if os(macOS)
extension MTLSamplerBorderColor {
    public init(_ color: SamplerBorderColor) {
        self.init(rawValue: color.rawValue)!
    }
}
#endif

extension MTLSamplerMinMagFilter {
    public init(_ filter: SamplerMinMagFilter) {
        self.init(rawValue: filter.rawValue)!
    }
}

extension MTLSamplerMipFilter {
    public init(_ filter: SamplerMipFilter) {
        self.init(rawValue: filter.rawValue)!
    }
}

extension MTLScissorRect {
    public init(_ rect: ScissorRect) {
        self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}

extension MTLSize {
    public init(_ size: Size) {
        self.init(width: size.width, height: size.height, depth: size.depth)
    }
}

extension MTLStencilOperation {
    public init(_ stencilOperation: StencilOperation) {
        self.init(rawValue: UInt(stencilOperation.rawValue))!
    }
}

extension MTLStorageMode {
    public init(_ mode: StorageMode, isAppleSiliconGPU: Bool) {
        switch mode {
        case .shared:
            self = .shared
        case .managed:
        #if os(macOS) || targetEnvironment(macCatalyst)
        if !isAppleSiliconGPU {
            self = .managed
        } else {
            self = .shared
        }
        #else
            self = .shared
        #endif
        case .private:
            self = .private
        }
    }
}

extension MTLTextureType {
    public init(_ type: TextureType) {
        self.init(rawValue: type.rawValue)!
    }
}

extension MTLTextureUsage {
    public init(_ usage: TextureUsage) {
        self.init(rawValue: 0)
        if usage.contains(.shaderRead) {
            self.formUnion(.shaderRead)
        }
        if usage.contains(.shaderWrite) {
            self.formUnion(.shaderWrite)
        }
        if !usage.intersection([.colorAttachment, .depthStencilAttachment]).isEmpty {
            self.formUnion(.renderTarget)
        }
        if usage.contains(.pixelFormatView) {
            self.formUnion(.pixelFormatView)
        }
    }
}

extension MTLViewport {
    public init(_ viewport: Viewport) {
        self.init(originX: viewport.originX, originY: viewport.originY, width: viewport.width, height: viewport.height, znear: viewport.zNear, zfar: viewport.zFar)
    }
}

extension MTLVertexFormat {
    public init(_ vertexFormat: VertexFormat) {
        self.init(rawValue: UInt(vertexFormat.rawValue))!
    }
}

extension MTLVertexStepFunction {
    public init(_ stepFunction: VertexStepFunction) {
        self.init(rawValue: UInt(stepFunction.rawValue))!
    }
}

extension MTLWinding {
    public init(_ winding: Winding) {
        self = winding == .clockwise ? .clockwise : .counterClockwise
    }
}

#endif // canImport(Metal)
