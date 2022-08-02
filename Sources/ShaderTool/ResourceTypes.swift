//
//  ResourceTypes.swift
//  SPIRV-Cross
//
//  Created by Thomas Roughton on 3/06/19.
//

import SPIRV_Cross
import Substrate

extension ResourceType {
    var substrateType : String {
        switch self {
        case .buffer:
            return "Buffer"
        case .texture:
            return "Texture"
        case .sampler:
            return "SamplerDescriptor"
        case .heap:
            return "Heap"
        case .argumentBuffer:
            return "ArgumentBuffer"
        default:
            fatalError()
        }
    }
}

enum ResourceViewType {
    case uniformBuffer
    case storageBuffer
    case inlineUniformBlock
    case pushConstantBlock
    case image
    case storageImage
    case inputAttachment
    case sampler
    
    var substrateTypeName : String {
        switch self {
        case .uniformBuffer, .storageBuffer, .inlineUniformBlock:
            return "Buffer"
        case .image, .storageImage, .inputAttachment:
            return "Texture"
        case .sampler:
            return "SamplerDescriptor"
        default:
            fatalError()
        }
    }
    
    var baseType : ResourceType {
        switch self {
        case .uniformBuffer, .storageBuffer, .pushConstantBlock, .inlineUniformBlock:
            return .buffer
        case .image, .storageImage, .inputAttachment:
            return .texture
        case .sampler:
            return .sampler
        }
    }
    
    var spvcType : spvc_resource_type {
        switch self {
        case .uniformBuffer, .inlineUniformBlock:
            return SPVC_RESOURCE_TYPE_UNIFORM_BUFFER
        case .storageBuffer:
            return SPVC_RESOURCE_TYPE_STORAGE_BUFFER
        case .pushConstantBlock:
            return SPVC_RESOURCE_TYPE_PUSH_CONSTANT
        case .image:
            return SPVC_RESOURCE_TYPE_SEPARATE_IMAGE
        case .storageImage:
            return SPVC_RESOURCE_TYPE_STORAGE_IMAGE
        case .sampler:
            return SPVC_RESOURCE_TYPE_SEPARATE_SAMPLERS
        case .inputAttachment:
            return SPVC_RESOURCE_TYPE_SUBPASS_INPUT
        }
    }
    
    static var boundTypes : [ResourceViewType] {
        return [.uniformBuffer, .storageBuffer, .inlineUniformBlock, .image, .storageImage, .inputAttachment, .sampler]
    }
}

struct Binding : Equatable, Comparable {
    var set : Int
    var index : Int
    var arrayLength : Int
    
    static func <(lhs: Binding, rhs: Binding) -> Bool {
        if lhs.set < rhs.set { return true }
        if lhs.set == rhs.set && lhs.index < rhs.index { return true }
        return false
    }
    
    static func ==(lhs: Binding, rhs: Binding) -> Bool {
        return lhs.set == rhs.set && lhs.index == rhs.index // The array length doesn't have to match; we just take the max.
    }
}

struct PlatformBindings {
    var macOSMetalIndex: UInt32?
    var appleSiliconMetalIndex: UInt32?
    
    mutating func formUnion(_ other: PlatformBindings) {
        assert(self.macOSMetalIndex == nil || other.macOSMetalIndex == nil || self.macOSMetalIndex == other.macOSMetalIndex)
        self.macOSMetalIndex = self.macOSMetalIndex ?? other.macOSMetalIndex
        
        assert(self.appleSiliconMetalIndex == nil || other.appleSiliconMetalIndex == nil || self.appleSiliconMetalIndex == other.appleSiliconMetalIndex)
        self.appleSiliconMetalIndex = self.appleSiliconMetalIndex ?? other.appleSiliconMetalIndex
    }
}

extension RenderStages : CustomStringConvertible {
    
    public var description : String {
        var result = "[ "
        if self.contains(.vertex) {
            result += ".vertex, "
        }
        if self.contains(.fragment) {
            result += ".fragment, "
        }
        if self.contains(.compute) {
            result += ".compute, "
        }
        result += "]"
        return result
    }
}

struct Resource : Equatable {
    var type : SPIRVType
    var binding : Binding
    var name : String
    var stages : RenderStages
    var viewType : ResourceViewType
    var textureType : TextureType?
    var accessType : ResourceAccessType
    var platformBindings : PlatformBindings
    
    init(type: SPIRVType, binding: Binding, name: String, stage: RenderStages, viewType: ResourceViewType, textureType: TextureType?, accessType: ResourceAccessType, platformBindings: PlatformBindings) {
        self.type = type
        self.binding = binding
        self.name = name
        self.stages = stage
        self.viewType = viewType
        self.textureType = textureType
        self.accessType = accessType
        self.platformBindings = platformBindings
    }
    
    init(compiler: SPIRVCompiler, resource: spvc_reflected_resource, type: ResourceType, stage: RenderStages, viewType: ResourceViewType) {
        var type = SPIRVType(compiler: compiler.compiler, typeId: resource.type_id)
        if case .struct(let structName, let members, let size) = type,
            members.count == 1,
            !members[0].type.isKnownSwiftType {
            if members[0].type.size == size {
                type = members[0].type
            } else {
                var member = members[0]
                if member.name.isEmpty {
                    member.name = "value"
                }
                type = .struct(name: structName, members: [member], size: size)
            }
        }
        
        
        let resourceTypeHandle = spvc_compiler_get_type_handle(compiler.compiler, resource.type_id)
        
        let name = String(cString: spvc_compiler_get_name(compiler.compiler, resource.id)) // String(cString: resource.name)
        let set = Int(spvc_compiler_get_decoration(compiler.compiler, resource.id, SpvDecorationDescriptorSet))
        let binding = Int(spvc_compiler_get_decoration(compiler.compiler, resource.id, SpvDecorationBinding))
        let arrayLength = Int(spvc_type_get_array_dimension(resourceTypeHandle, 0))
        
        var viewType = viewType
        if compiler.file.inlineUniformBlocks.contains(.init(set: set, binding: binding)) {
            switch viewType {
            case .uniformBuffer, .inlineUniformBlock, .pushConstantBlock:
                viewType = .inlineUniformBlock
            default:
                print("Warning: Resource \(name) at binding (binding = \(binding), set = \(set)) is not a valid candidate for an inline uniform block.")
            }
        }
        
        var textureType: TextureType? = nil
        let accessType: ResourceAccessType
        switch viewType {
        case .uniformBuffer, .pushConstantBlock, .inlineUniformBlock:
            accessType = .read
        case .storageBuffer:
            var decorationCount = 0
            var decorations: UnsafePointer<SpvDecoration>? = nil
            spvc_compiler_get_buffer_block_decorations(compiler.compiler, resource.id, &decorations, &decorationCount)
            
            let decorationsBuffer = UnsafeBufferPointer(start: decorations, count: decorationCount)
            
            let isNonReadable = decorationsBuffer.contains(SpvDecorationNonReadable)
            let isNonWritable = decorationsBuffer.contains(SpvDecorationNonWritable)
            
            var access = ResourceAccessType.readWrite
            if isNonReadable { access.remove(.read) }
            if isNonWritable { access.remove(.write) }
            accessType = access
        case .image, .storageImage, .inputAttachment:
            let accessQualifier = spvc_type_get_image_access_qualifier(resourceTypeHandle)
            if viewType != .storageImage || accessQualifier == SpvAccessQualifierReadOnly {
                accessType = .read
            } else if accessQualifier == SpvAccessQualifierWriteOnly {
                accessType = .write
            } else {
                accessType = .readWrite
            }
            
            let dimension = spvc_type_get_image_dimension(resourceTypeHandle)
            let isArray = spvc_type_get_image_arrayed(resourceTypeHandle) == SPVC_TRUE
            let isMultisampled = spvc_type_get_image_multisampled(resourceTypeHandle) == SPVC_TRUE
            switch dimension {
            case SpvDim1D:
                textureType = isArray ? .type1DArray : .type1D
            case SpvDim2D:
                if isMultisampled {
                    textureType = isArray ? .type2DMultisampleArray : .type2DMultisample
                } else {
                    textureType = isArray ? .type2DArray : .type2D
                }
            case SpvDim3D:
                textureType = .type3D
            case SpvDimCube:
                textureType = isArray ? .typeCubeArray : .typeCube
            case SpvDimBuffer:
                textureType = .typeTextureBuffer
            default:
                break
            }
            
        case .sampler:
            accessType = .read
        }
        
        var platformBindings = PlatformBindings()
        
        if compiler.file.target.isMetal {
            var assignedIndex = spvc_compiler_msl_get_automatic_resource_binding(compiler.compiler, resource.id)
            if assignedIndex == .max {
                assignedIndex = UInt32(binding)
            }
            if compiler.file.target.isAppleSilicon {
                platformBindings.appleSiliconMetalIndex = assignedIndex
            } else {
                platformBindings.macOSMetalIndex = assignedIndex
            }
        }
        
        self.init(type: type, binding: Binding(set: set, index: binding, arrayLength: arrayLength), name: name, stage: stage, viewType: viewType, textureType: textureType, accessType: accessType, platformBindings: platformBindings)
    }
    
    static func ==(lhs: Resource, rhs: Resource) -> Bool {
        var typesEqual = lhs.type == rhs.type
        
        if !typesEqual, case .array(let elementA, _) = lhs.type, case .array(let elementB, _) = rhs.type, elementA == elementB {
            // Count arrays of differing lengths as being equal.
            typesEqual = true
        }
        
        return typesEqual && lhs.binding == rhs.binding && lhs.name == rhs.name
    }
}
