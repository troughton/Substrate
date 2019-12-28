//
//  DescriptorSet.swift
//  
//
//  Created by Thomas Roughton on 7/12/19.
//

import Foundation
import SwiftFrameGraph
import SPIRV_Cross

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
                if self.resources[i].binding.arrayLength != resources[j].binding.arrayLength ||
                    self.resources[i].name != resources[j].name ||
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
    
    func printStruct(to stream: inout ReflectionPrinter, typeLookup: TypeLookup, setIndex: Int) {
        if self.resources.isEmpty {
            return
        }
        
        stream.print("public struct \(self.name ?? "Set\(setIndex)") : ShaderDescriptorSet {")
                
        assert(!self.stages.isEmpty)
        stream.print("public static let activeStages : RenderStages = \(self.stages)")
        stream.newLine()
        
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
            if resource.viewType == .uniformBuffer {
                stream.print("@BufferBacked public var \(resource.name) : \(resource.type.name)? = nil")
            } else {
                let wrapperType = resource.viewType == .uniformBuffer || resource.viewType == .storageBuffer ? "@OffsetView " : ""
                stream.print("\(wrapperType)public var \(resource.name) : \(resource.viewType.frameGraphType)? = nil")
            }
        }
        
        stream.newLine()
        
        stream.print("public func encode(into argBuffer: _ArgumentBuffer, setIndex: Int) {")

        // Metal 
        do {
            stream.print("#if canImport(Metal)")
            stream.print("if RenderBackend.api == .metal {")
            defer { 
                stream.print("}")
                stream.print("#endif // canImport(Metal)")
            }

            for resource in self.resources where resource.stages != [] {
                if resource.viewType == .uniformBuffer {
                    // @BufferBacked property
                    
                    stream.print("if let resource = self.$\(resource.name).buffer {")
                                    
                    stream.print("argBuffer.bindings.append(")
                    stream.print("(ResourceBindingPath(set: setIndex, index: \(resource.binding.index), type: .buffer), .buffer(resource.wrappedValue, offset: resource.offset))")
                    
                    stream.print(")")
                    stream.print("}")
                    
                    continue
                }
                
                stream.print("if let resource = self.\(resource.name) {")
                            
                stream.print("argBuffer.bindings.append(")
                        
                
                switch resource.type {
                case .texture:
                    stream.print("(ResourceBindingPath(descriptorSet: setIndex, index: \(resource.binding.index), type: .texture), .texture(resource))")
                case .sampler:
                    stream.print("(ResourceBindingPath(descriptorSet: setIndex, index: \(resource.binding.index), type: .sampler), .sampler(resource))")
                default:
                    stream.print("(ResourceBindingPath(descriptorSet: setIndex, index: \(resource.binding.index), type: .buffer), .buffer(resource, offset: self.$\(resource.name).offset))")
                }
                stream.print(")")
                stream.print("}")
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

            for resource in self.resources where resource.stages != [] {
                if resource.viewType == .uniformBuffer {
                    // @BufferBacked property
                    
                    stream.print("if let resource = self.$\(resource.name).buffer {")
                                    
                    stream.print("assert(resource.binding.set == setIndex)")

                    stream.print("argBuffer.bindings.append(")
                    stream.print("(ResourceBindingPath(set: setIndex, index: \(resource.binding.index), arrayIndex: 0), .buffer(resource.wrappedValue, offset: resource.offset))")
                    
                    stream.print(")")
                    stream.print("}")
                    
                    continue
                }
                
                stream.print("if let resource = self.\(resource.name) {")
                stream.print("assert(resource.binding.set == setIndex)")
                            
                stream.print("argBuffer.bindings.append(")
                
                switch resource.type {
                case .texture:
                    stream.print("(ResourceBindingPath(set: setIndex, index: \(resource.binding.index), arrayIndex: 0), .texture(resource))")
                case .sampler:
                    stream.print("(ResourceBindingPath(set: setIndex, index: \(resource.binding.index), arrayIndex: 0), .sampler(resource))")
                default:
                    stream.print("(ResourceBindingPath(set: setIndex, index: \(resource.binding.index), arrayIndex: 0), .buffer(resource, offset: self.$\(resource.name).offset))")
                }
                
                stream.print(")")
                stream.print("}")
            }
        }
        
        stream.print("}")
        stream.print("}")
        stream.newLine()
    }
}

