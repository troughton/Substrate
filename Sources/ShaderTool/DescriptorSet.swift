//
//  DescriptorSet.swift
//  
//
//  Created by Thomas Roughton on 7/12/19.
//

import Foundation
import Substrate
import SPIRV_Cross

extension DataType {
    init?(_ spirvType: SPIRVType) {
        switch spirvType {
        case .void:
            self = .none
        case .bool:
            self = .bool
        case .int8:
            self = .char
        case .uint8:
            self = .uchar
        case .int16:
            self = .short
        case .uint16:
            self = .ushort
        case .int32:
            self = .int
        case .uint32:
            self = .uint
        case .int64:
            return nil
        case .uint64:
            return nil
        case .half:
            self = .half
        case .float:
            self = .float
        case .double:
            return nil
        case .atomicCounter:
            self = .uint
            
        case .vector(.float, 2):
            self = .float2
        case .vector(.float, 3):
            self = .float3
        case .vector(.float, 4):
            self = .float4
            
        case .vector(.half, 2):
            self = .half2
        case .vector(.half, 3):
            self = .half3
        case .vector(.half, 4):
            self = .half4
            
        case .vector(.int32, 2):
            self = .int2
        case .vector(.int32, 3):
            self = .int3
        case .vector(.int32, 4):
            self = .int4
            
        case .vector(.uint32, 2):
            self = .uint2
        case .vector(.uint32, 3):
            self = .uint3
        case .vector(.uint32, 4):
            self = .uint4
            
        case .vector(.int16, 2):
            self = .short2
        case .vector(.int16, 3):
            self = .short3
        case .vector(.int16, 4):
            self = .short4
            
        case .vector(.uint16, 2):
            self = .ushort2
        case .vector(.uint16, 3):
            self = .ushort3
        case .vector(.uint16, 4):
            self = .ushort4
            
        case .vector(.int8, 2):
            self = .char2
        case .vector(.int8, 3):
            self = .char3
        case .vector(.int8, 4):
            self = .char4
            
        case .vector(.uint8, 2):
            self = .uchar2
        case .vector(.uint8, 3):
            self = .uchar3
        case .vector(.uint8, 4):
            self = .uchar4
            
        case .vector(.bool, 2):
            self = .bool2
        case .vector(.bool, 3):
            self = .bool3
        case .vector(.bool, 4):
            self = .bool4
            
        case .packedVector(.float, 3):
            self = .float3
        case .packedVector(.half, 3):
            self = .half3
        case .packedVector(.int32, 3):
            self = .int3
        case .packedVector(.uint32, 3):
            self = .uint3
        case .packedVector(.int16, 3):
            self = .short3
        case .packedVector(.uint16, 3):
            self = .ushort3
        case .packedVector(.int8, 3):
            self = .char3
        case .packedVector(.uint8, 3):
            self = .uchar3
        case .packedVector(.bool, 3):
            self = .bool3
            
        case .matrix(.float, 2, 2):
            self = .float2x2
        case .matrix(.float, 2, 3):
            self = .float2x3
        case .matrix(.float, 2, 4):
            self = .float2x4
            
        case .matrix(.float, 3, 2):
            self = .float3x2
        case .matrix(.float, 3, 3):
            self = .float3x3
        case .matrix(.float, 3, 4):
            self = .float3x4
            
        case .matrix(.float, 4, 2):
            self = .float4x2
        case .matrix(.float, 4, 3):
            self = .float4x3
        case .matrix(.float, 4, 4):
            self = .float4x4
            
        case .matrix(.half, 2, 2):
            self = .half2x2
        case .matrix(.half, 2, 3):
            self = .half2x3
        case .matrix(.half, 2, 4):
            self = .half2x4
            
        case .matrix(.half, 3, 2):
            self = .half3x2
        case .matrix(.half, 3, 3):
            self = .half3x3
        case .matrix(.half, 3, 4):
            self = .half3x4
            
        case .matrix(.half, 4, 2):
            self = .half4x2
        case .matrix(.half, 4, 3):
            self = .half4x3
        case .matrix(.half, 4, 4):
            self = .half4x4
            
        case .array:
            self = .array
            
        case .struct:
            self = .struct
            
        default:
            return nil
        }
    }
}

final class DescriptorSet {
    static let setCount : Int = 8
    
    var passes : [RenderPass] = []
    var resources : [Resource] = [] // Sorted by construction
    var stages : RenderStages = []
    
    var name : String? = nil
    
    func isCompatible(with resources: ArraySlice<Resource>) -> Bool {
        // Heuristic: only say sets are compatible if they share at least two resources.
        var matchedResources = 0
        
        var i = 0
        var j = resources.startIndex
        
        while i < self.resources.count && j < resources.endIndex {
            if self.resources[i].binding.index < resources[j].binding.index {
                i += 1
            } else if self.resources[i].binding.index > resources[j].binding.index {
                j += 1
            } else {
                if self.resources[i].name != resources[j].name ||
                    self.resources[i].type != resources[j].type {
                    return false
                }
                
                matchedResources += 1
                
                i += 1
                j += 1
            }
        }
        
        return matchedResources >= 2
    }
    
    func addResources(_ resources: ArraySlice<Resource>) {
        var i = 0
        var j = resources.startIndex
        
        while i < self.resources.count && j < resources.endIndex {
            if self.resources[i].binding.index < resources[j].binding.index {
                i += 1
            } else if self.resources[i].binding.index > resources[j].binding.index {
                self.resources.insert(resources[j], at: i)
            } else {
                // The resources are the same.
                self.resources[i].binding.arrayLength = max(self.resources[i].binding.arrayLength, resources[j].binding.arrayLength)
                self.resources[i].stages.formUnion(resources[j].stages)
                self.stages.formUnion(resources[j].stages)
                
                i += 1
                j += 1
            }
        }
        
        self.resources.append(contentsOf: resources[j...])
        for resource in resources[j...] {
            self.stages.formUnion(resource.stages)
        }
    }
    
    func printArgumentBufferDescriptor(to stream: inout ReflectionPrinter, platformBindingPath: KeyPath<PlatformBindings, UInt32?>?) {
        stream.print("return ArgumentDescriptor(arguments: [")
        for resource in self.resources {
            let argumentResourceType: ArgumentDescriptor.ArgumentResourceType
            switch resource.viewType {
            case .uniformBuffer:
                argumentResourceType = .constantBuffer(alignment: 0)
            case .storageBuffer:
                argumentResourceType = .storageBuffer
            case .image, .storageImage:
                guard let textureType = resource.textureType else {
                    print("Warning: skipping resource '\(resource.name)' in argument buffer descriptor.")
                    continue
                }
                argumentResourceType = .texture(type: textureType)
            case .inputAttachment:
                argumentResourceType = .texture(type: .type2D)
            case .sampler:
                argumentResourceType = .sampler
            case .pushConstantBlock, .inlineUniformBlock:
                guard let dataType = DataType(resource.type) else {
                    print("Warning: skipping resource '\(resource.name)' in argument buffer descriptor.")
                    continue
                }
                argumentResourceType = .inlineData(type: dataType)
            }
            
            let accessTypeString: String
            switch resource.accessType {
            case .read:
                accessTypeString = ".read"
            case .write:
                accessTypeString = ".write"
            case .readWrite:
                accessTypeString = ".readWrite"
            default:
                accessTypeString = String(describing: resource.accessType)
            }
            
            if platformBindingPath == \.appleSiliconMetalIndex, resource.viewType == .storageImage {
                continue // Apple Silicon doesn't support read-write textures in argument buffers
            }
            
            var bindingIndex = resource.binding.index
            if let platformBindingPath = platformBindingPath {
                bindingIndex = resource.platformBindings[keyPath: platformBindingPath].map { Int($0) } ?? resource.binding.index
            }
            
            if resource.viewType == .storageImage { // Apple Silicon doesn't support read-write textures in argument buffers
                stream.print("#if !canImport(Metal) || (os(macOS) && (arch(i386) || arch(x86_64)))")
            }
            stream.print("ArgumentDescriptor(resource: .\(argumentResourceType), index: \(bindingIndex), arrayLength: \(max(resource.binding.arrayLength, 1)), accessType: \(accessTypeString)),")
            if resource.viewType == .storageImage {
                stream.print("#endif")
            }
        }
        stream.print("])")
    }
    
    func printArgumentBufferDescriptor(to stream: inout ReflectionPrinter) {
        stream.print("public static var argumentBufferDescriptor : ArgumentBufferDescriptor {")
        
        if self.resources.contains(where: { $0.platformBindings.macOSMetalIndex != UInt32($0.binding.index) || $0.platformBindings.macOSMetalIndex != $0.platformBindings.appleSiliconMetalIndex }) {
            stream.print("#if canImport(Metal)")
            stream.print("#if os(macOS) && (arch(i386) || arch(x86_64))")
            self.printArgumentBufferDescriptor(to: &stream, platformBindingPath: \.macOSMetalIndex)
            stream.print("#else")
            self.printArgumentBufferDescriptor(to: &stream, platformBindingPath: \.appleSiliconMetalIndex)
            stream.print("#endif")
            stream.print("#else")
            self.printArgumentBufferDescriptor(to: &stream, platformBindingPath: nil)
            stream.print("#endif")
        } else {
            self.printArgumentBufferDescriptor(to: &stream, platformBindingPath: nil)
        }
        stream.print("}")
        stream.newLine()
    }
    
    func printStruct(to stream: inout ReflectionPrinter, typeLookup: TypeLookup, setIndex: Int) {
        if self.resources.isEmpty {
            return
        }
        
        stream.print("public struct \(self.name ?? "Set\(setIndex)") : ShaderDescriptorSet {")
                
        stream.print("public static let activeStages : RenderStages = \(self.stages)")
        stream.newLine()
        
        self.printArgumentBufferDescriptor(to: &stream)
        
        stream.print("@inlinable")
        stream.print("public init() {}")
        stream.newLine()
        
        // Print struct definitions
        let structDefs = typeLookup.typeContexts.compactMap { (type, context) -> SPIRVType? in
            guard case .descriptorSet(let set) = context, set === self else { return nil }
            return type
        }.sorted(by: { $0.name < $1.name })
        
        for type in structDefs {
            stream.print(type.declaration)
            stream.newLine()
        }
        
        for resource in self.resources {
            if resource.viewType == .inlineUniformBlock {
                stream.print("public var \(resource.name): \(resource.type.name) = .init()")
            } else if resource.viewType == .uniformBuffer {
                stream.print("@BufferBacked public var \(resource.name): \(resource.type.name)? = nil")
            } else {
                let wrapperType = resource.viewType == .uniformBuffer || resource.viewType == .storageBuffer ? "@OffsetView " : ""
                if wrapperType.isEmpty, resource.binding.arrayLength > 1 { // FIXME: how do we handle this case for arrays which require property wrappers?
                    stream.print("\(wrapperType)public var \(resource.name): [\(resource.viewType.substrateTypeName)?] = .init(repeating: nil, count: \(resource.binding.arrayLength))")
                } else {
                    stream.print("\(wrapperType)public var \(resource.name): \(resource.viewType.substrateTypeName)? = nil")
                }
            }
        }
        
        stream.newLine()
        
        stream.print("public mutating func encode(into argBuffer: ArgumentBuffer, setIndex: Int, bindingEncoder: ResourceBindingEncoder? = nil) {")

        // Metal 
        do {
            stream.print("#if canImport(Metal)")
            stream.print("if RenderBackend.api == .metal {")
            if self.resources.contains(where: { $0.viewType == .storageImage || $0.platformBindings.macOSMetalIndex != $0.platformBindings.appleSiliconMetalIndex }) {
                stream.print("#if (os(iOS) || os(tvOS) || os(watchOS)) && !targetEnvironment(macCatalyst)")
                stream.print("let isAppleSiliconGPU = true")
                stream.print("#elseif arch(i386) || arch(x86_64)")
                stream.print("let isAppleSiliconGPU = false")
                stream.print("#else")
                stream.print("let isAppleSiliconGPU = (RenderBackend.renderDevice as! MTLDevice).isAppleSiliconGPU")
                stream.print("#endif")
            }
            defer { 
                stream.print("}")
                stream.print("#endif // canImport(Metal)")
            }

            for resource in self.resources {
                if resource.viewType == .inlineUniformBlock {
                    stream.print("argBuffer.setValue(self.\(resource.name), key: ResourceBindingPath(descriptorSet: setIndex, index: \(resource.binding.index), type: .buffer))")
                    continue
                } else if resource.viewType == .uniformBuffer {
                    // @BufferBacked property
                    
                    stream.print("if let resource = self.$\(resource.name).buffer {")
                                    
                    stream.print("argBuffer.bindings.append(")
                    stream.print("(ResourceBindingPath(descriptorSet: setIndex, index: \(resource.binding.index), type: .buffer), .buffer(resource.wrappedValue, offset: resource.offset))")
                    
                    stream.print(")")
                    stream.print("}")
                    
                    continue
                }
                
                let arrayIndexString : String
                if resource.binding.arrayLength > 1 {
                    arrayIndexString = " + i"
                    stream.print("for i in 0..<self.\(resource.name).count {")
                    stream.print("if let resource = self.\(resource.name)[i] {")
                } else {
                    arrayIndexString = ""
                    stream.print("if let resource = self.\(resource.name) {")
                }
                
                let addArgBufferBinding = { (stream: inout ReflectionPrinter, index: Int) in
                    stream.print("argBuffer.bindings.append(")
                    
                    var type = resource.type
                    if case .array(let elementType, let length) = type {
                        switch elementType {
                        case  .buffer, .texture, .sampler:
                            assert(length <= resource.binding.arrayLength)
                            type = elementType
                        default:
                            break
                        }
                    }
                    
                    switch type {
                    case .texture:
                        stream.print("(ResourceBindingPath(descriptorSet: setIndex, index: \(index)\(arrayIndexString), type: .texture), .texture(resource))")
                    case .sampler:
                        stream.print("(ResourceBindingPath(descriptorSet: setIndex, index: \(index)\(arrayIndexString), type: .sampler), .sampler(resource))")
                    default:
                        stream.print("(ResourceBindingPath(descriptorSet: setIndex, index: \(index)\(arrayIndexString), type: .buffer), .buffer(resource, offset: self.$\(resource.name).offset))")
                    }
                    
                    stream.print(")")
                }
                
                if resource.viewType == .storageImage || resource.platformBindings.macOSMetalIndex != resource.platformBindings.appleSiliconMetalIndex {
                    stream.print("if isAppleSiliconGPU {")
                    // Storage images (i.e. read-write textures) aren't permitted in argument buffers, so we need to bind directly on the encoder.
                    if resource.viewType == .storageImage, let index = resource.platformBindings.appleSiliconMetalIndex {
                        stream.print("if let bindingEncoder = bindingEncoder {")
                        stream.print("bindingEncoder.setTexture(resource, key: MetalIndexedFunctionArgument(type: .texture, index: \(index)\(arrayIndexString), stages: \(resource.stages)))")
                        stream.print("}")
                    } else {
                        if let index = resource.platformBindings.appleSiliconMetalIndex.map({ Int($0) }) {
                            addArgBufferBinding(&stream, index)
                        }
                    }
                    stream.print("} else {")
                    
                    let index = resource.platformBindings.macOSMetalIndex.map { Int($0) } ?? resource.binding.index
                    addArgBufferBinding(&stream, index)
                    
                    stream.print("}")
                    
                } else {
                    let index = resource.platformBindings.macOSMetalIndex.map { Int($0) } ?? resource.binding.index
                    addArgBufferBinding(&stream, index)
                }
               
                stream.print("}")
                
                if resource.binding.arrayLength > 1 {
                    stream.print("}")
                }
            }
        }

        stream.newLine()

        // Vulkan
        do {
            stream.print("#if canImport(Vulkan)")
            stream.print("if RenderBackend.api == .vulkan {")
            defer {
                stream.print("}")
                stream.print("#endif // canImport(Vulkan)")
            }

            for resource in self.resources {
                if resource.viewType == .inlineUniformBlock {
                    stream.print("argBuffer.setValue(self.\(resource.name), key: ResourceBindingPath(set: UInt32(setIndex), binding: \(resource.binding.index), arrayIndex: 0))")
                    continue
                } else if resource.viewType == .uniformBuffer {
                    // @BufferBacked property
                    
                    stream.print("if let resource = self.$\(resource.name).buffer {")
                    stream.print("argBuffer.bindings.append(")
                    stream.print("(ResourceBindingPath(set: UInt32(setIndex), binding: \(resource.binding.index), arrayIndex: 0), .buffer(resource.wrappedValue, offset: resource.offset))")
                    
                    stream.print(")")
                    stream.print("}")
                    
                    continue
                }
                
                var type = resource.type
                if case .array(let elementType, let length) = type {
                    switch elementType {
                    case  .buffer, .texture, .sampler:
                        assert(length <= resource.binding.arrayLength)
                        type = elementType
                    default:
                        break
                    }
                }
                
                let arrayIndexString : String
                if resource.binding.arrayLength > 1 {
                    arrayIndexString = "UInt32(i)"
                    stream.print("for i in 0..<self.\(resource.name).count {")
                    stream.print("if let resource = self.\(resource.name)[i] {")
                } else {
                    arrayIndexString = "0"
                    stream.print("if let resource = self.\(resource.name) {")
                }
                
                stream.print("argBuffer.bindings.append(")
                
                switch type {
                case .texture:
                    stream.print("(ResourceBindingPath(set: UInt32(setIndex), binding: \(resource.binding.index), arrayIndex: \(arrayIndexString)), .texture(resource))")
                case .sampler:
                    stream.print("(ResourceBindingPath(set: UInt32(setIndex), binding: \(resource.binding.index), arrayIndex: \(arrayIndexString)), .sampler(resource))")
                default:
                    stream.print("(ResourceBindingPath(set: UInt32(setIndex), binding: \(resource.binding.index), arrayIndex: \(arrayIndexString)), .buffer(resource, offset: self.$\(resource.name).offset))")
                }
                
                stream.print(")")
                stream.print("}")

                if resource.binding.arrayLength > 1 {
                    stream.print("}")
                }
            }
        }
        
        stream.print("}")
        stream.print("}")
        stream.newLine()
    }
}

