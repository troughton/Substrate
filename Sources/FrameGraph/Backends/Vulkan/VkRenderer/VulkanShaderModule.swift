//
//  PipelineReflection.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 13/01/18.
//

import CVkRenderer
import SwiftFrameGraph
import Utilities
import Foundation

public struct BitSet : OptionSet, Hashable {
    public var rawValue : UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public init(element: Int) {
        assert(element < 64)
        self.rawValue = 1 << element
    }
}

struct ShaderResource {
    var type : ShaderResourceType
    var bindingPath : VulkanResourceBindingPath
    var name : String
    var access : AccessQualifier
    var bindingRange : BindingRange
    var accessedStages : VkShaderStageFlagBits
}

struct FunctionSpecialisation {
    var index : Int = 0
    var name : String = ""
}

struct DescriptorSetLayoutKey : Hashable {
    var set : UInt32
    var dynamicBuffers : BitSet
}

final class VulkanPipelineReflection : PipelineReflection {
    let device : VulkanDevice
    
    let resources : [VulkanResourceBindingPath : ShaderResource]
    let specialisations : [FunctionSpecialisation]
    let activeStagesForSets : [UInt32 : VkShaderStageFlagBits]
    let lastSet : UInt32?
    
    private var layouts = [DescriptorSetLayoutKey : VulkanDescriptorSetLayout]()
    
    let reflectionCacheCount : Int
    let reflectionCacheKeys : UnsafePointer<VulkanResourceBindingPath>
    let reflectionCacheValues : UnsafePointer<ArgumentReflection>
    
    deinit {
        self.reflectionCacheKeys.deallocate()
        self.reflectionCacheValues.deallocate()
    }
    
    public init(functions: [(String, VkReflectionContext, VkShaderStageFlagBits)], device: VulkanDevice) {
        self.device = device
        var resources = [VulkanResourceBindingPath : ShaderResource]()
        var functionSpecialisations = [FunctionSpecialisation]()
        
        var activeStagesForSets = [UInt32 : VkShaderStageFlagBits]()
        var lastSet : UInt32? = nil
        
        for (functionName, reflectionContext, stage) in functions {
            functionName.withCString {
                VkReflectionContextSetEntryPoint(reflectionContext, $0)
            }
            
            VkReflectionContextEnumerateResources(reflectionContext) { (type, bindingIndex, bindingRange, name, access)  in
                let bindingPath = VulkanResourceBindingPath(set: bindingIndex.set, binding: bindingIndex.binding, arrayIndex: 0)

                resources[bindingPath, default:
                    ShaderResource(type: type, bindingPath: bindingPath, name: String(cString: name!), access: access, bindingRange: bindingRange, accessedStages: stage)
                    ].accessedStages.formUnion(stage)
                activeStagesForSets[bindingPath.set, default: []].formUnion(stage)

                if bindingPath.set != BindingIndexSetPushConstant {
                    lastSet = max(lastSet ?? 0, bindingPath.set)
                }
            }
            
            VkReflectionContextEnumerateSpecialisationConstants(reflectionContext) { (index, constantIndex, name) in
                if !functionSpecialisations.contains(where: { $0.index == Int(constantIndex) }) {
                    functionSpecialisations.append(FunctionSpecialisation(index: Int(constantIndex), name: String(cString: name!)))
                }
            }
        }
        
        self.resources = resources
        self.specialisations = functionSpecialisations
        self.activeStagesForSets = activeStagesForSets
        self.lastSet = lastSet
        
        let sortedReflectionCache = resources.map { (path: $0, reflection: ArgumentReflection($1)!) }.sorted(by: { $0.path.value < $1.path.value })
        
        let reflectionCacheKeys = UnsafeMutablePointer<VulkanResourceBindingPath>.allocate(capacity: sortedReflectionCache.count + 1)
        let reflectionCacheValues = UnsafeMutablePointer<ArgumentReflection>.allocate(capacity: sortedReflectionCache.count)
        
        for (i, pair) in sortedReflectionCache.enumerated() {
            reflectionCacheKeys[i] = pair.path
            reflectionCacheValues[i] = pair.reflection
        }
        
        reflectionCacheKeys[sortedReflectionCache.count] = VulkanResourceBindingPath(ResourceBindingPath(value: .max)) // Insert a sentinel to speed up the linear search; https://schani.wordpress.com/2010/04/30/linear-vs-binary-search/
        
        self.reflectionCacheCount = sortedReflectionCache.count
        self.reflectionCacheKeys = UnsafePointer(reflectionCacheKeys)
        self.reflectionCacheValues = UnsafePointer(reflectionCacheValues)
        
    }
    
    subscript(bindingPath: VulkanResourceBindingPath) -> ShaderResource {
        return self.resources[bindingPath]!
    }

    public func descriptorSetLayout(set: UInt32, dynamicBuffers: BitSet) -> VulkanDescriptorSetLayout {
        let key = DescriptorSetLayoutKey(set: set, dynamicBuffers: dynamicBuffers)
        if let layout = self.layouts[key] {
            return layout
        }
        let descriptorResources : [ShaderResource] = resources.values.compactMap { resource in
            if resource.bindingPath.set == set, resource.type != .pushConstantBuffer {
                return resource
            }
            return nil
        }
        let activeStages = self.activeStagesForSets[set] ?? []
        
        let layout = VulkanDescriptorSetLayout(set: set, device: self.device, resources: descriptorResources, stages: activeStages, dynamicBuffers: dynamicBuffers)
        self.layouts[key] = layout
        return layout
    }
    
    func vkDescriptorSetLayouts(bindingManager: ResourceBindingManager) -> [VkDescriptorSetLayout?] {
        guard let lastSet = self.lastSet else {
            return []
        } 

        var layouts = [VkDescriptorSetLayout?]()
        for set in 0...lastSet {
            let layout = self.descriptorSetLayout(set: set, dynamicBuffers: bindingManager.existingManagerForSet(set)?.dynamicBuffers ?? [])
            layouts.append(layout.vkLayout)
        }
        return layouts
    }
    
    // returnNearest: if there is no reflection for this path, return the reflection for the next lowest path (i.e. with the next lowest id).
    func reflectionCacheLinearSearch(_ path: VulkanResourceBindingPath, returnNearest: Bool) -> ArgumentReflection? {
        var i = 0
        while true { // We're guaranteed to always exit this loop since there's a sentinel value with UInt64.max at the end of reflectionCacheKeys
            if self.reflectionCacheKeys[i].value >= path.value {
                break
            }
            i += 1
        }
        
        if i < self.reflectionCacheCount, self.reflectionCacheKeys[i] == path {
            return self.reflectionCacheValues[i]
        } else if returnNearest, i - 1 > 0, i - 1 < self.reflectionCacheCount { // Check for the next lowest binding path.
            return self.reflectionCacheValues[i - 1]
        }
        return nil
    }
    
    // returnNearest: if there is no reflection for this path, return the reflection for the next lowest path (i.e. with the next lowest id).
    func reflectionCacheBinarySearch(_ path: VulkanResourceBindingPath, returnNearest: Bool) -> ArgumentReflection? {
        var low = 0
        var high = self.reflectionCacheCount
        
        while low != high {
            let mid = low &+ (high &- low) >> 1
            let testVal = self.reflectionCacheKeys[mid].value
            
            low = testVal < path.value ? (mid &+ 1) : low
            high = testVal >= path.value ? mid : high
        }
        
        if low < self.reflectionCacheCount, self.reflectionCacheKeys[low] == path {
            return self.reflectionCacheValues[low]
        } else if returnNearest, low - 1 > 0, low - 1 < self.reflectionCacheCount { // Check for the next lowest binding path.
            return self.reflectionCacheValues[low - 1]
        }
        return nil
    }
    
    public func argumentReflection(at path: ResourceBindingPath) -> ArgumentReflection? {
        let path = VulkanResourceBindingPath(path)
        return reflectionCacheLinearSearch(path, returnNearest: false)
    }
    
    public func bindingPath(argumentName: String, arrayIndex: Int, argumentBufferPath: ResourceBindingPath?) -> ResourceBindingPath? {
        for resource in self.resources.values {
            if resource.name == argumentName {
                var bindingPath = resource.bindingPath
                bindingPath.arrayIndex = UInt32(arrayIndex)
                
                if let argumentBufferPath = argumentBufferPath {
                    assert(bindingPath.set == VulkanResourceBindingPath(argumentBufferPath).set)
                }
                
                return ResourceBindingPath(bindingPath)
            }
        }
        return nil
    }
    
    public func bindingPath(argumentBuffer: ArgumentBuffer, argumentName: String, arrayIndex: Int) -> ResourceBindingPath? {
        
        // TODO: handle the arrayIndex parameter for argument buffer arrays.
        
        // NOTE: There's currently no error checking that the argument buffer contents
        // aren't spread across multiple sets.
        
        if let (firstBoundPath, _) = argumentBuffer.bindings.first {
            let vulkanPath = VulkanResourceBindingPath(firstBoundPath)
            return ResourceBindingPath(
                VulkanResourceBindingPath(argumentBuffer: vulkanPath.set)
            )
        }
        
        for (pendingKey, _, _) in argumentBuffer.enqueuedBindings {
            if let path = pendingKey.computedBindingPath(pipelineReflection: self) {
                let vulkanPath = VulkanResourceBindingPath(path)
                return ResourceBindingPath(
                    VulkanResourceBindingPath(argumentBuffer: vulkanPath.set)
                )
            }
        }
        
        return nil
    }
    
    public func bindingPath(pathInOriginalArgumentBuffer: ResourceBindingPath, newArgumentBufferPath: ResourceBindingPath) -> ResourceBindingPath {
        let newParentPath = VulkanResourceBindingPath(newArgumentBufferPath)
        
        var modifiedPath = VulkanResourceBindingPath(pathInOriginalArgumentBuffer)
        modifiedPath.set = newParentPath.set
        return ResourceBindingPath(modifiedPath)
    }
}

extension ArgumentReflection {
    init?(_ resource: ShaderResource) {
        let resourceType : ResourceType
        switch resource.type {
        case .storageBuffer, .storageTexelBuffer, .uniformBuffer, .uniformTexelBuffer, .pushConstantBuffer:
            resourceType = .buffer
        case .sampler:
            resourceType = .sampler
        case .sampledImage, .storageImage, .subpassInput:
            resourceType = .texture
        default:
            fatalError()
        }
        
        let usageType : ResourceUsageType
        switch (resource.access, resource.type) {
        case (_, .uniformBuffer):
            usageType = .constantBuffer
        case (_, .subpassInput):
            usageType = .inputAttachment
        case (.readOnly, _):
            usageType = .read
        case (.readWrite, _):
            usageType = .readWrite
        case (.writeOnly, _):
            usageType = .write
        case (_, .sampler):
            usageType = .sampler
        default:
            return nil
        }

        var renderAPIStages : RenderStages = []
        if resource.accessedStages.contains(VK_SHADER_STAGE_COMPUTE_BIT) {
            renderAPIStages.formUnion(.compute)
        }
        if resource.accessedStages.contains(VK_SHADER_STAGE_VERTEX_BIT) {
            renderAPIStages.formUnion(.vertex)
        }
        if resource.accessedStages.contains(VK_SHADER_STAGE_FRAGMENT_BIT) {
            renderAPIStages.formUnion(.fragment)
        }

        self.init(isActive: true, type: resourceType, bindingPath: ResourceBindingPath(resource.bindingPath), usageType: usageType, stages: renderAPIStages)
    }
}

extension VkDescriptorType {
    init?(_ resourceType: ShaderResourceType, dynamic: Bool) {
        switch resourceType {
        case .pushConstantBuffer:
            return nil
        case .sampledImage:
            self = VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE
        case .sampler:
            self = VK_DESCRIPTOR_TYPE_SAMPLER
        case .storageBuffer:
            self = dynamic ? VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC : VK_DESCRIPTOR_TYPE_STORAGE_BUFFER
        case .storageImage:
            self = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE
        case .subpassInput:
            self = VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT
        case .uniformBuffer:
            self = dynamic ? VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC : VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER
        case .uniformTexelBuffer:
            self = VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER
        case .storageTexelBuffer:
            self = VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER
        #if os(Windows)
        default:
            fatalError()
        #endif
        }
    }
}

extension VkDescriptorSetLayoutBinding {
    init?(resource: ShaderResource, stages: VkShaderStageFlagBits, isDynamic: Bool) {
        guard let descriptorType = VkDescriptorType(resource.type, dynamic: isDynamic) else {
            return nil
        }
        
        self.init()
        
        self.binding = resource.bindingPath.binding
        self.descriptorType = descriptorType
        self.stageFlags = VkShaderStageFlags(stages)
        self.descriptorCount = 1 // FIXME: shouldn't be hard-coded, but instead should equal the number of elements in the array.
    }
}

public class VulkanDescriptorSetLayout {
    let device : VulkanDevice
    let vkLayout : VkDescriptorSetLayout
    let set : UInt32
    
    init(set: UInt32, device: VulkanDevice, resources: [ShaderResource], stages: VkShaderStageFlagBits, dynamicBuffers: BitSet) {
        self.device = device
        self.set = set
        
        var layoutCreateInfo = VkDescriptorSetLayoutCreateInfo()
        layoutCreateInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO
        layoutCreateInfo.flags = 0
        
        let bindings = resources.enumerated().compactMap { (i, resource) in 
            VkDescriptorSetLayoutBinding(resource: resource, stages: stages, isDynamic: dynamicBuffers.contains(BitSet(element: i))) 
        }

        layoutCreateInfo.bindingCount = UInt32(bindings.count)
        
        self.vkLayout = bindings.withUnsafeBufferPointer { bindings in
            layoutCreateInfo.pBindings = bindings.baseAddress
            
            var layout : VkDescriptorSetLayout?
            vkCreateDescriptorSetLayout(device.vkDevice, &layoutCreateInfo, nil, &layout)
            return layout!
        }
        
    }
    
    deinit {
        vkDestroyDescriptorSetLayout(self.device.vkDevice, self.vkLayout, nil)
    }
}

public enum PipelineLayoutKey : Hashable {
    case graphics(vertexShader: String, fragmentShader: String?)
    case compute(String)
}


public class VulkanShaderModule {
    let device: VulkanDevice
    let vkModule : VkShaderModule
    let reflectionContext : VkReflectionContext
    let data : Data
    let usesGLSLMainEntryPoint : Bool
    
    private var reflectionCache = [PipelineLayoutKey : PipelineReflection]()
    private var pipelineLayoutCache = [PipelineLayoutKey : VkPipelineLayout]()
    
    public init(device: VulkanDevice, data: Data) {
        self.device = device
        self.data = data

        let codePointer : UnsafePointer<UInt32> = data.withUnsafeBytes { return $0 }

        let wordCount = (data.count + MemoryLayout<UInt32>.size - 1) / MemoryLayout<UInt32>.size
        let reflectionContext = VkReflectionContextCreate(codePointer, wordCount)!
        self.reflectionContext = reflectionContext

        var createInfo = VkShaderModuleCreateInfo()
        createInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO
        createInfo.pCode = codePointer
        createInfo.codeSize = data.count
        
        var shaderModule : VkShaderModule? = nil
        vkCreateShaderModule(device.vkDevice, &createInfo, nil, &shaderModule).check()
        
        self.vkModule = shaderModule!

        var usesGLSLMainEntryPoint = false

        VkReflectionContextEnumerateEntryPoints(reflectionContext) { entryPoint in
            if strncmp("main", entryPoint, 4) == 0 {
                usesGLSLMainEntryPoint = true
            }
        }
        self.usesGLSLMainEntryPoint = usesGLSLMainEntryPoint
    }

    func entryPointForFunction(named functionName: String) -> String {
        return self.usesGLSLMainEntryPoint ? "main" : functionName
    }

    public var entryPoints : [String] {
        var entryPoints = [String]()
        VkReflectionContextEnumerateEntryPoints(self.reflectionContext) { entryPoint in
            entryPoints.append(String(cString: entryPoint!))
        }
        return entryPoints
    }
    
    deinit {
        vkDestroyShaderModule(self.device.vkDevice, self.vkModule, nil)
        VkReflectionContextDestroy(self.reflectionContext)
    }
}

public class VulkanShaderLibrary {
    let device: VulkanDevice
    let url : URL
    let modules : [VulkanShaderModule]
    private let functionsToModules : [String : VulkanShaderModule]
    
    private var reflectionCache = [PipelineLayoutKey : VulkanPipelineReflection]()
    private var pipelineLayoutCache = [PipelineLayoutKey : VkPipelineLayout]()
    
    public init(device: VulkanDevice, url: URL) throws {
        self.device = device
        self.url = url

        let fileManager = FileManager.default
        let resources = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
        
        var modules = [VulkanShaderModule]()
        var functions = [String : VulkanShaderModule]()

        for file in resources {
            if file.pathExtension == ".spv" {
                let shaderData = try Data(contentsOf: file, options: .mappedIfSafe)
        
                let module = VulkanShaderModule(device: device, data: shaderData)
                modules.append(module)

                if module.usesGLSLMainEntryPoint {
                    functions[file.deletingPathExtension().lastPathComponent] = module
                } else {
                    for entryPoint in module.entryPoints {
                        functions[entryPoint] = module
                    }
                }
            }
        }

        self.modules = modules
        self.functionsToModules = functions
    }
    
    func pipelineLayout(for key: PipelineLayoutKey, bindingManager: ResourceBindingManager) -> VkPipelineLayout {
        if let layout = self.pipelineLayoutCache[key] { // FIXME: we also need to take into account whether the /descriptor set layouts/ are identical.
            return layout
        }
        
        var createInfo = VkPipelineLayoutCreateInfo()
        createInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO
        
        let reflection = self.reflection(for: key)
        let setLayouts : [VkDescriptorSetLayout?] = reflection.vkDescriptorSetLayouts(bindingManager: bindingManager)

        var pushConstantRanges = [VkPushConstantRange]()
        for resource in reflection.resources.values where resource.bindingPath.isPushConstant {
            pushConstantRanges.append(VkPushConstantRange(stageFlags: VkShaderStageFlags(resource.accessedStages), offset: resource.bindingRange.offset, size: resource.bindingRange.size))
        }
        
        var pipelineLayout : VkPipelineLayout? = nil
        setLayouts.withUnsafeBufferPointer { setLayouts in
            createInfo.setLayoutCount = UInt32(setLayouts.count)
            createInfo.pSetLayouts = setLayouts.baseAddress
            
            pushConstantRanges.withUnsafeBufferPointer { pushConstantRanges in
                createInfo.pushConstantRangeCount = UInt32(pushConstantRanges.count)
                createInfo.pPushConstantRanges = pushConstantRanges.baseAddress
                
                vkCreatePipelineLayout(self.device.vkDevice, &createInfo, nil, &pipelineLayout)
            }
        }
        self.pipelineLayoutCache[key] = pipelineLayout
        return pipelineLayout!
    }
    
    func reflection(for key: PipelineLayoutKey) -> VulkanPipelineReflection {
        if let reflection = self.reflectionCache[key] {
            return reflection
        }
        
        var functions = [(String, VkReflectionContext, VkShaderStageFlagBits)]()
        switch key {
        case .graphics(let vertexShader, let fragmentShader):
            guard let vertexModule = self.functionsToModules[vertexShader] else {
                fatalError("No shader entry point called \(vertexShader)")
            }
            functions.append((vertexModule.entryPointForFunction(named: vertexShader), vertexModule.reflectionContext, VK_SHADER_STAGE_VERTEX_BIT))

            if let fragmentShader = fragmentShader {
                guard let fragmentModule = self.functionsToModules[fragmentShader] else {
                    fatalError("No shader entry point called \(fragmentShader)")
                }
                functions.append((fragmentModule.entryPointForFunction(named: fragmentShader), fragmentModule.reflectionContext, VK_SHADER_STAGE_FRAGMENT_BIT))
            }
        case .compute(let computeShader):
            guard let module = self.functionsToModules[computeShader] else {
                fatalError("No shader entry point called \(computeShader)")
            }
            functions.append((module.entryPointForFunction(named: computeShader), module.reflectionContext, VK_SHADER_STAGE_COMPUTE_BIT))
        }

        let reflection = VulkanPipelineReflection(functions: functions, device: self.device)
        self.reflectionCache[key] = reflection
        return reflection
    }

    public func moduleForFunction(_ functionName: String) -> VulkanShaderModule? {
        return self.functionsToModules[functionName]
    }
    
}
