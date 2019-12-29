//
//  ResourceTypes.swift
//  SPIRV-Cross
//
//  Created by Thomas Roughton on 3/06/19.
//

import SPIRV_Cross
import SwiftFrameGraph

extension ResourceType {
    var frameGraphType : String {
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
            return "_ArgumentBuffer"
        case .argumentBufferArray:
            return "_ArgumentBufferArray"
        default:
            fatalError()
        }
    }
}

enum ResourceViewType {
    case uniformBuffer
    case storageBuffer
    case pushConstantBlock
    case texture
    case sampler
    
    var frameGraphType : String {
        switch self {
        case .uniformBuffer, .storageBuffer:
            return "Buffer"
        case .texture:
            return "Texture"
        case .sampler:
            return "SamplerDescriptor"
        default:
            fatalError()
        }
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
    
    init(type: SPIRVType, binding: Binding, name: String, stage: RenderStages, viewType: ResourceViewType) {
        self.type = type
        self.binding = binding
        self.name = name
        self.stages = stage
        self.viewType = viewType
    }
    
    init(compiler: SPIRVCompiler, resource: spvc_reflected_resource, type: ResourceType, stage: RenderStages, viewType: ResourceViewType) {
        var type = SPIRVType(compiler: compiler.compiler, typeId: resource.type_id)
        if case .struct(_, let members) = type, members.count == 1 {
            type = members.first!.type
        }
        
        let name = String(cString: spvc_compiler_get_name(compiler.compiler, resource.id)) // String(cString: resource.name)
        let set = Int(spvc_compiler_get_decoration(compiler.compiler, resource.id, SpvDecorationDescriptorSet))
        var binding = Int(spvc_compiler_get_decoration(compiler.compiler, resource.id, SpvDecorationBinding))
        
        if compiler.file.target == .macOSMetal || compiler.file.target == .iOSMetal {
            let assignedIndex = spvc_compiler_msl_get_automatic_resource_binding(compiler.compiler, resource.id)
            if assignedIndex != .max {
                binding = Int(assignedIndex)
            }
        }
        
        self.init(type: type, binding: Binding(set: set, index: binding, arrayLength: 1), name: name, stage: stage, viewType: viewType)
    }
    
    static func ==(lhs: Resource, rhs: Resource) -> Bool {
        return lhs.type == rhs.type && lhs.binding == rhs.binding && lhs.name == rhs.name
    }
}
