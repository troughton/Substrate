//
//  Conversion.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 24/12/17.
//

import SwiftFrameGraph
import Metal

//MARK: From Metal

extension ResourceType {
    init(_ type: MTLArgumentType) {
        switch type {
        case .buffer:
            self = .buffer
        case .sampler:
            self = .sampler
        case .texture:
            self = .texture
        case .threadgroupMemory:
            self = .threadgroupMemory
        }
    }
}

extension ResourceUsageType {
    init(_ access: MTLArgumentAccess) {
        switch access {
        case .readOnly:
            self = .read
        case .readWrite:
            self = .readWrite
        case .writeOnly:
            self = .write
        }
    }
}

extension RenderStages {
    init(_ mtlStages: MTLRenderStages) {
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

extension ArgumentReflection {
    init(_ argument: MTLArgument, bindingPath: MetalResourceBindingPath) {
        
        self.init(isActive: argument.isActive, type: ResourceType(argument.type), bindingPath: ResourceBindingPath(bindingPath), usageType: ResourceUsageType(argument.access), stages: RenderStages(bindingPath.stages))
    }
    
    
    init(member: MTLStructMember, argumentBuffer: MTLArgument, bindingPath: MetalResourceBindingPath) {
        let type : ResourceType
        let usageType : ResourceUsageType
        switch member.dataType {
        case .texture:
            type = .texture
            usageType = ResourceUsageType(member.textureReferenceType()!.access)
        case .sampler:
            type = .sampler
            usageType = .sampler
        default:
            type = .buffer
            usageType = ResourceUsageType(member.pointerType()?.access ?? .readOnly) // It might be POD, in which case the usage is read only.
        }
        
        self.init(isActive: argumentBuffer.isActive, type: type, bindingPath: ResourceBindingPath(bindingPath), usageType: usageType, stages: RenderStages(bindingPath.stages))
    }
    
    init?(array: MTLArrayType, argumentBuffer: MTLArgument, bindingPath: MetalResourceBindingPath) {
        let type : ResourceType
        let usageType : ResourceUsageType
        
        switch array.elementType {
        case .texture:
            type = .texture
            guard let textureReferenceType = array.elementTextureReferenceType() else { return nil }
            usageType = ResourceUsageType(textureReferenceType.access)
        case .sampler:
            type = .sampler
            usageType = .sampler
        default:
            type = .buffer
            guard let elementPointerType = array.elementPointerType() else { return nil }
            usageType = ResourceUsageType(elementPointerType.access)
        }
        
        self.init(isActive: argumentBuffer.isActive, type: type, bindingPath: ResourceBindingPath(bindingPath), usageType: usageType, stages: RenderStages(bindingPath.stages))
    }
    
    
}

//MARK: To Metal

extension MTLBlendFactor {
    init(_ blendFactor: BlendFactor) {
        self.init(rawValue: blendFactor.rawValue)!
    }
}

extension MTLBlendOperation {
    init(_ blendOperation: BlendOperation) {
        self.init(rawValue: blendOperation.rawValue)!
    }
}

extension MTLBlitOption {
    init(_ option: BlitOption) {
        self.init(rawValue: option.rawValue)
    }
}

extension MTLCompareFunction {
    init(_ compareFunction: CompareFunction) {
        self.init(rawValue: compareFunction.rawValue)!
    }
}

extension MTLClearColor {
    init(_ clearColor: ClearColor) {
        self.init(red: clearColor.red, green: clearColor.green, blue: clearColor.blue, alpha: clearColor.alpha)
    }
}

extension MTLColorWriteMask {
    init(_ colorWriteMask: ColorWriteMask) {
        self.init(rawValue: colorWriteMask.rawValue)
    }
}

extension MTLCPUCacheMode {
    init(_ mode: CPUCacheMode) {
        self.init(rawValue: mode.rawValue)!
    }
}

extension MTLCullMode {
    init(_ mode: CullMode) {
        self.init(rawValue: mode.rawValue)!
    }
}

extension MTLTriangleFillMode {
    init(_ mode: TriangleFillMode) {
        self.init(rawValue: mode.rawValue)!
    }
}

extension MTLDataType {
    init(_ dataType: DataType) {
        self.init(rawValue: dataType.rawValue)!
    }
}

extension MTLDepthClipMode {
    init(_ depthClipMode: DepthClipMode) {
        switch depthClipMode {
        case .clip:
            self = .clip
        case .clamp:
            self = .clamp
        }
    }
}

extension MTLFunctionConstantValues {
    convenience init(_ values: [String: FunctionConstantValue]) {
        self.init()
        
        for (key, constant) in values {
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
    init(_ type: IndexType) {
        self.init(rawValue: type.rawValue)!
    }
}

extension MTLOrigin {
    init(_ origin: Origin) {
        self.init(x: origin.x, y: origin.y, z: origin.z)
    }
}

extension MTLPrimitiveType {
    init(_ type: PrimitiveType) {
        self.init(rawValue: type.rawValue)!
    }
}


extension MTLPixelFormat {
    init(_ pixelFormat: PixelFormat) {
        self.init(rawValue: pixelFormat.rawValue)!
    }
}

extension MTLRegion {
    init(_ region: Region) {
        self.init(origin: MTLOrigin(region.origin), size: MTLSize(region.size))
    }
}

extension MTLRenderStages {
    init?(_ renderStages: RenderStages) {
        if renderStages.contains(.vertex) {
            self = .vertex
        } else if renderStages.contains(.fragment) {
            self = .fragment
        } else {
            return nil
        }
    }
}

extension MTLResourceOptions {
    public init(storageMode: StorageMode, cacheMode: CPUCacheMode) {
        self.init()
        
        switch storageMode {
        case .shared:
            self.formUnion(.storageModeShared)
        case .managed:
            self.formUnion(.storageModeManaged)
        case .private:
            self.formUnion(.storageModePrivate)
        }
        
        switch cacheMode {
        case .defaultCache:
            break
        case .writeCombined:
            self.formUnion(.cpuCacheModeWriteCombined)
        }
        
        self.formUnion(.hazardTrackingModeUntracked)
    }
}

extension MTLSamplerAddressMode {
    init(_ mode: SamplerAddressMode) {
        self.init(rawValue: mode.rawValue)!
    }
}

extension MTLSamplerBorderColor {
    init(_ color: SamplerBorderColor) {
        self.init(rawValue: color.rawValue)!
    }
}

extension MTLSamplerMinMagFilter {
    init(_ filter: SamplerMinMagFilter) {
        self.init(rawValue: filter.rawValue)!
    }
}

extension MTLSamplerMipFilter {
    init(_ filter: SamplerMipFilter) {
        self.init(rawValue: filter.rawValue)!
    }
}

extension MTLScissorRect {
    init(_ rect: ScissorRect) {
        self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}

extension MTLSize {
    init(_ size: Size) {
        self.init(width: size.width, height: size.height, depth: size.depth)
    }
}

extension MTLStencilOperation {
    init(_ stencilOperation: StencilOperation) {
        self.init(rawValue: stencilOperation.rawValue)!
    }
}

extension MTLStorageMode {
    init(_ mode: StorageMode) {
        switch mode {
        case .shared:
            self = .shared
        case .managed:
            self = .managed
        case .private:
            self = .private
        }
    }
}

extension MTLTextureType {
    init(_ type: TextureType) {
        self.init(rawValue: type.rawValue)!
    }
}

extension MTLTextureUsage {
    init(_ usage: TextureUsage) {
        self.init(rawValue: usage.rawValue & 0b11111) // Mask to only the bits Metal knows about.
    }
}

extension MTLViewport {
    init(_ viewport: Viewport) {
        self.init(originX: viewport.originX, originY: viewport.originY, width: viewport.width, height: viewport.height, znear: viewport.zNear, zfar: viewport.zFar)
    }
}

extension MTLVertexFormat {
    init(_ vertexFormat: VertexFormat) {
        self.init(rawValue: vertexFormat.rawValue)!
    }
}

extension MTLVertexStepFunction {
    init(_ stepFunction: VertexStepFunction) {
        self.init(rawValue: stepFunction.rawValue)!
    }
}

extension MTLWinding {
    init(_ winding: Winding) {
        self = winding == .clockwise ? .clockwise : .counterClockwise
    }
}
