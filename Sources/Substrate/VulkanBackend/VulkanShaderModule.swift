//
//  PipelineReflection.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 13/01/18.
//

#if canImport(Vulkan)
import Vulkan
import SubstrateCExtras
import SubstrateUtilities
import Foundation
import SPIRV_Cross

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
    var name : String
    var type : spvc_resource_type
    var bindingPath : ResourceBindingPath
    var bindingRange : Range<UInt32>
    var arrayLength: Int
    var access : ResourceAccessType
    var accessedStages : VkShaderStageFlagBits
}

struct FunctionSpecialisation {
    var index : Int = 0
    var name : String = ""
}

extension String : CustomHashable {
    public var customHashValue: Int {
        return self.hashValue
    }
}

final class VulkanPipelineReflection : PipelineReflection {
    let device : VulkanDevice
    
    let resources : [ResourceBindingPath : ShaderResource]
    let specialisations : [FunctionSpecialisation]
    let activeStagesForSets : [UInt32 : RenderStages]
    let lastSet : UInt32?
    
    private var layouts = [UInt32 : VulkanDescriptorSetLayout]()
    
    let bindingPathCache : HashMap<String, ResourceBindingPath>
    
    let reflectionCacheCount : Int
    let reflectionCacheKeys : UnsafePointer<ResourceBindingPath>
    let reflectionCacheValues : UnsafePointer<ArgumentReflection>
    
    let threadExecutionWidth: Int = 32 // FIXME: retrieve from device via VkPhysicalDeviceSubgroupProperties.
    
    deinit {
        self.reflectionCacheKeys.deallocate()
        self.reflectionCacheValues.deallocate()
    }
    
    public init(functions: [(String, spvc_compiler, SpvExecutionModel_)], device: VulkanDevice) {
        self.device = device
        
        var bindingPathCache = HashMap<String, ResourceBindingPath>()
        var resources = [ResourceBindingPath : ShaderResource]()
        var functionSpecialisations = [FunctionSpecialisation]()
        
        var activeStagesForSets = [UInt32 : RenderStages]()
        var lastSet : UInt32? = nil
        
        for (functionName, compiler, executionModel) in functions {
            let renderStage: RenderStages
            switch executionModel {
            case SpvExecutionModelVertex:
                renderStage = .vertex
            case SpvExecutionModelFragment:
                renderStage = .fragment
            case SpvExecutionModelGLCompute:
                renderStage = .compute
            default:
                continue
            }

            spvc_compiler_set_entry_point(compiler, functionName, executionModel)
            let stage = VkShaderStageFlagBits(executionModel)!
            
            var spvcResources : spvc_resources! = nil
            spvc_compiler_create_shader_resources(compiler, &spvcResources)
            
            let types : [spvc_resource_type] = [.uniformBuffer, .storageBuffer, .sampledImage, .storageImage, .sampler, .pushConstantBuffer]
            
            for type in types {
                var resourceList : UnsafePointer<spvc_reflected_resource>! = nil
                var resourceCount = 0
                spvc_resources_get_resource_list_for_type(spvcResources, type, &resourceList, &resourceCount)

                let typeIsReadOnly: Bool
                switch type {
                case .uniformBuffer, .sampledImage, .sampler, .pushConstantBuffer:
                    typeIsReadOnly = true
                default:
                    typeIsReadOnly = false
                }

                for resource in UnsafeBufferPointer(start: resourceList, count: resourceCount) {

                    let resourceTypeHandle = spvc_compiler_get_type_handle(compiler, resource.type_id)

                    let set = spvc_compiler_get_decoration(compiler, resource.id, SpvDecorationDescriptorSet)
                    let binding = spvc_compiler_get_decoration(compiler, resource.id, SpvDecorationBinding)
                    let arrayLength = max(Int(spvc_type_get_array_dimension(resourceTypeHandle, 0)), 1)
                    let name = spvc_compiler_get_name(compiler, resource.id)
                    
                    var bufferRangesMin : Int = Int(UInt32.max)
                    var bufferRangesMax : Int = 0
                    
                    if type == .uniformBuffer || type == .storageBuffer || type == .pushConstantBuffer {
                    
                        var bufferRanges : UnsafePointer<spvc_buffer_range>! = nil
                        var bufferRangeCount = 0
                        spvc_compiler_get_active_buffer_ranges(compiler, resource.id, &bufferRanges, &bufferRangeCount)

                        for bufferRange in UnsafeBufferPointer(start: bufferRanges, count: bufferRangeCount) {
                            bufferRangesMin = min(bufferRange.offset, bufferRangesMin)
                            bufferRangesMax = max(bufferRange.offset + bufferRange.range, bufferRangesMax)
                        }
                    }

                    if bufferRangesMax < bufferRangesMin { bufferRangesMax = bufferRangesMin }
                    
                    let isReadOnly = typeIsReadOnly || spvc_compiler_get_member_decoration(compiler, resource.base_type_id, 0, SpvDecorationNonWritable) != 0
                    let isWriteOnly = spvc_compiler_get_member_decoration(compiler, resource.base_type_id, 0, SpvDecorationNonReadable) != 0
                    assert(!(typeIsReadOnly && isWriteOnly))
                    let access : ResourceAccessType = isReadOnly ? .read : (isWriteOnly ? .write : .readWrite)

                    let bindingPath = type == .pushConstantBuffer ? ResourceBindingPath.pushConstantPath : ResourceBindingPath(set: set, binding: binding, arrayIndex: 0)

                    let resourceName = String(cString: name!)
                    bindingPathCache[resourceName] = bindingPath
                    
                    resources[bindingPath, default:
                        ShaderResource(name: resourceName,
                                       type: type,
                                       bindingPath: bindingPath,
                                       bindingRange: UInt32(bufferRangesMin)..<UInt32(bufferRangesMax),
                                       arrayLength: arrayLength,
                                       access: access,
                                       accessedStages: stage)
                    ].accessedStages.formUnion(stage)

                    activeStagesForSets[bindingPath.set, default: []].formUnion(renderStage)
                    
                    if type != .pushConstantBuffer {
                        lastSet = max(lastSet ?? 0, bindingPath.set)
                    }
                }
            }
            
            var specialisationConstantCount = 0
            var specialisationConstants : UnsafePointer<spvc_specialization_constant>! = nil
            spvc_compiler_get_specialization_constants(compiler, &specialisationConstants, &specialisationConstantCount)
            for i in 0..<specialisationConstantCount {
                if !functionSpecialisations.contains(where: { $0.index == Int(specialisationConstants[i].constant_id) }) {
                    let name = spvc_compiler_get_name(compiler, specialisationConstants[i].id)!
                    functionSpecialisations.append(FunctionSpecialisation(index: Int(specialisationConstants[i].constant_id), name: String(cString: name)))
                }
            }
        }
        
        self.resources = resources
        self.specialisations = functionSpecialisations
        self.activeStagesForSets = activeStagesForSets
        self.lastSet = lastSet
        
        let sortedReflectionCache = resources.map { (path: $0, reflection: ArgumentReflection($1)!) }.sorted(by: { $0.path.value < $1.path.value })
        
        let reflectionCacheKeys = UnsafeMutablePointer<ResourceBindingPath>.allocate(capacity: sortedReflectionCache.count + 1)
        let reflectionCacheValues = UnsafeMutablePointer<ArgumentReflection>.allocate(capacity: sortedReflectionCache.count)
        
        for (i, pair) in sortedReflectionCache.enumerated() {
            reflectionCacheKeys[i] = pair.path
            reflectionCacheValues[i] = pair.reflection
        }
        
        reflectionCacheKeys[sortedReflectionCache.count] = ResourceBindingPath(value: .max) // Insert a sentinel to speed up the linear search; https://schani.wordpress.com/2010/04/30/linear-vs-binary-search/
        
        self.bindingPathCache = bindingPathCache
        self.reflectionCacheCount = sortedReflectionCache.count
        self.reflectionCacheKeys = UnsafePointer(reflectionCacheKeys)
        self.reflectionCacheValues = UnsafePointer(reflectionCacheValues)
        
    }
    
    subscript(bindingPath: ResourceBindingPath) -> ShaderResource {
        return self.resources[bindingPath]!
    }

    public func descriptorSetLayout(set: UInt32) -> VulkanDescriptorSetLayout {
        if let layout = self.layouts[set] {
            return layout
        }
        let descriptorResources : [ShaderResource] = resources.values.compactMap { resource in
            if resource.bindingPath.set == set, resource.type != .pushConstantBuffer {
                return resource
            }
            return nil
        }
        let activeStages = self.activeStagesForSets[set] ?? []
        
        let layout = VulkanDescriptorSetLayout(set: set, pipelineReflection: self, resources: descriptorResources, stages: VkShaderStageFlagBits(activeStages))
        self.layouts[set] = layout
        return layout
    }
    
    var vkDescriptorSetLayouts: [VkDescriptorSetLayout?] {
        guard let lastSet = self.lastSet else {
            return []
        } 

        var layouts = [VkDescriptorSetLayout?]()
        for set in 0...lastSet {
            let layout = self.descriptorSetLayout(set: set)
            layouts.append(layout.vkLayout)
        }
        return layouts
    }

    // returnNearest: if there is no reflection for this path, return the reflection for the next lowest path (i.e. with the next lowest id).
    func reflectionCacheLinearSearch(_ path: ResourceBindingPath, returnNearest: Bool) -> ArgumentReflection? {
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
    func reflectionCacheBinarySearch(_ path: ResourceBindingPath, returnNearest: Bool) -> ArgumentReflection? {
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
        if path.isArgumentBuffer {
            return ArgumentReflection(type: .argumentBuffer, bindingPath: path, usageType: .read, activeStages: self.activeStagesForSets[path.set] ?? [], activeRange: .fullResource)
        }
        return reflectionCacheLinearSearch(path, returnNearest: false)
    }
    
    public func bindingPath(argumentName: String, arrayIndex: Int, argumentBufferPath: ResourceBindingPath?) -> ResourceBindingPath? {
        for resource in self.resources.values {
            if resource.name == argumentName {
                var bindingPath = resource.bindingPath
                bindingPath.arrayIndexVulkan = UInt32(arrayIndex)
                
                if let argumentBufferPath = argumentBufferPath {
                    assert(bindingPath.set == argumentBufferPath.set)
                }
                
                return bindingPath
            }
        }
        return nil
    }
    
    public func bindingPath(argumentBuffer: _ArgumentBuffer, argumentName: String, arrayIndex: Int) -> ResourceBindingPath? {
        
        // TODO: handle the arrayIndex parameter for argument buffer arrays.
        
        // NOTE: There's currently no error checking that the argument buffer contents
        // aren't spread across multiple sets.
        
        if let (firstBoundPath, _) = argumentBuffer.bindings.first {
            return ResourceBindingPath(argumentBuffer: firstBoundPath.set)
        }
        
        for (pendingKey, _, _) in argumentBuffer.enqueuedBindings {
            if let path = pendingKey.computedBindingPath(pipelineReflection: self) {
                return ResourceBindingPath(argumentBuffer: path.set)
            }
        }
        
        return nil
    }
    
    public func bindingPath(pathInOriginalArgumentBuffer: ResourceBindingPath, newArgumentBufferPath: ResourceBindingPath) -> ResourceBindingPath {
        var modifiedPath = pathInOriginalArgumentBuffer
        modifiedPath.set = newArgumentBufferPath.set
        return modifiedPath
    }
    
    func remapArgumentBufferPathForActiveStages(_ path: ResourceBindingPath) -> ResourceBindingPath {
        return path // Paths don't differ by stage on Vulkan
    }

    func argumentBufferEncoder(at path: ResourceBindingPath, currentEncoder: UnsafeRawPointer?) -> UnsafeRawPointer? {
        let currentLayout = currentEncoder.map { Unmanaged<VulkanDescriptorSetLayout>.fromOpaque($0) }
        let newLayout = self.descriptorSetLayout(set: path.set)

        // Choose the more-specific layout.
        if newLayout.bindingCount > currentLayout?._withUnsafeGuaranteedRef({ $0.bindingCount }) ?? 0 {
            return UnsafeRawPointer(Unmanaged.passUnretained(newLayout).toOpaque())
        } else {
            return currentEncoder
        }
    }
}

extension ArgumentReflection {
    init?(_ resource: ShaderResource) {
        let resourceType : ResourceType
        switch resource.type {
        case .storageBuffer, .uniformBuffer, .pushConstantBuffer:
            resourceType = .buffer
        case .sampler:
            resourceType = .sampler
        case .sampledImage, .storageImage, .subpassInput:
            resourceType = .texture
        default:
            fatalError("Unsupported resource type \(resource.type)")
        }
        
        let usageType : ResourceUsageType
        switch (resource.access, resource.type) {
        case (_, .uniformBuffer):
            usageType = .constantBuffer
        case (_, .sampledImage):
            usageType = .read
        case (_, .sampler):
            usageType = .sampler
        case (_, .subpassInput):
            usageType = .inputAttachment
        case (.read, _):
            usageType = .read
        case (.readWrite, _):
            usageType = .readWrite
        case (.write, _):
            usageType = .write
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

        let activeBufferRange = Int(resource.bindingRange.lowerBound)..<Int(resource.bindingRange.upperBound)
        let activeRange: ActiveResourceRange = resourceType == .buffer ? .buffer(activeBufferRange) : .fullResource
        
        self.init(type: resourceType, bindingPath: resource.bindingPath, usageType: usageType, activeStages: renderAPIStages, activeRange: activeRange)
    }
}

extension VkDescriptorType {
    init?(_ resourceType: spvc_resource_type, dynamic: Bool) {
        switch resourceType {
        case .pushConstantBuffer:
            return nil
        case .sampledImage:
            self = VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE
        case .combinedImageSampler:
            self = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER
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
        default:
            fatalError()
        }
    }
}

extension VkDescriptorSetLayoutBinding {
    init?(resource: ShaderResource, stages: VkShaderStageFlagBits) {
        guard let descriptorType = VkDescriptorType(resource.type, dynamic: false) else {
            return nil
        }
        
        self.init()
        
        self.binding = resource.bindingPath.binding
        self.descriptorType = descriptorType
        self.stageFlags = VkShaderStageFlags(stages)
        self.descriptorCount = UInt32(resource.arrayLength)
    }
}

public class VulkanDescriptorSetLayout {
    unowned(unsafe) let pipelineReflection: VulkanPipelineReflection
    let vkLayout : VkDescriptorSetLayout
    let set : UInt32
    let bindingCount: Int
    
    init(set: UInt32, pipelineReflection: VulkanPipelineReflection, resources: [ShaderResource], stages: VkShaderStageFlagBits) {
        self.pipelineReflection = pipelineReflection
        self.set = set
        
        var layoutCreateInfo = VkDescriptorSetLayoutCreateInfo()
        layoutCreateInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO
        layoutCreateInfo.flags = 0
        
        let bindings = resources.enumerated().compactMap { (i, resource) in 
            VkDescriptorSetLayoutBinding(resource: resource, stages: stages) 
        }

        layoutCreateInfo.bindingCount = UInt32(bindings.count)
        self.bindingCount = bindings.count

        let bindingFlags = [VkDescriptorBindingFlags](repeating: VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT.rawValue, count: bindings.count)

        self.vkLayout = bindingFlags.withUnsafeBufferPointer { bindingFlags in
            var bindingFlagsCreateInfo = VkDescriptorSetLayoutBindingFlagsCreateInfo()
            bindingFlagsCreateInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO
            bindingFlagsCreateInfo.bindingCount = UInt32(bindingFlags.count)
            bindingFlagsCreateInfo.pBindingFlags = bindingFlags.baseAddress

            return withUnsafeBytes(of: bindingFlagsCreateInfo) { flagsCreateInfo in
                layoutCreateInfo.pNext = flagsCreateInfo.baseAddress
                return bindings.withUnsafeBufferPointer { bindings in
                    layoutCreateInfo.pBindings = bindings.baseAddress
                    
                    var layout : VkDescriptorSetLayout?
                    vkCreateDescriptorSetLayout(pipelineReflection.device.vkDevice, &layoutCreateInfo, nil, &layout)
                    return layout!
                }
            }
        }
    }
    
    deinit {
        vkDestroyDescriptorSetLayout(pipelineReflection.device.vkDevice, self.vkLayout, nil)
    }
}

public enum PipelineLayoutKey : Hashable {
    case graphics(vertexShader: String, fragmentShader: String?)
    case compute(String)
}

public class VulkanShaderModule {
    let device: VulkanDevice
    let vkModule : VkShaderModule
    let compiler : spvc_compiler
    let data : Data
    let usesGLSLMainEntryPoint : Bool
    
    private var reflectionCache = [PipelineLayoutKey : PipelineReflection]()
    private var pipelineLayoutCache = [PipelineLayoutKey : VkPipelineLayout]()
    
    public init(device: VulkanDevice, spvcContext: spvc_context, data: Data) {
        self.device = device
        self.data = data
        
        var shaderModule : VkShaderModule? = nil
        var parsedIR : spvc_parsed_ir? = nil
        
        data.withUnsafeBytes { codePointer in
            let spvCode = codePointer.bindMemory(to: SpvId.self)
            let result = spvc_context_parse_spirv(spvcContext, spvCode.baseAddress, spvCode.count, &parsedIR)
            if result != SPVC_SUCCESS {
                preconditionFailure("Error parsing shader module: \(result)")
            }
            
            var createInfo = VkShaderModuleCreateInfo()
            createInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO
            createInfo.pCode = spvCode.baseAddress
            createInfo.codeSize = spvCode.count * MemoryLayout<SpvId>.stride
            
            vkCreateShaderModule(device.vkDevice, &createInfo, nil, &shaderModule).check()
        }

        var compiler : spvc_compiler? = nil
        spvc_context_create_compiler(spvcContext, SPVC_BACKEND_NONE, parsedIR, SPVC_CAPTURE_MODE_TAKE_OWNERSHIP, &compiler)
        
        self.vkModule = shaderModule!
        self.compiler = compiler!

        var usesGLSLMainEntryPoint = false

        var entryPointCount = 0
        var entryPoints : UnsafePointer<spvc_entry_point>! = nil
        spvc_compiler_get_entry_points(self.compiler, &entryPoints, &entryPointCount)
        
        for i in 0..<entryPointCount {
            if String(cString: entryPoints[i].name) == "main" {
                usesGLSLMainEntryPoint = true
            }
        }
    
        self.usesGLSLMainEntryPoint = usesGLSLMainEntryPoint
    }
    
    func entryPointForFunction(named functionName: String) -> String {
        return self.usesGLSLMainEntryPoint ? "main" : functionName
    }

    public var entryPoints : [String] {
        var entryPointCount = 0
        var entryPoints : UnsafePointer<spvc_entry_point>! = nil
        spvc_compiler_get_entry_points(self.compiler, &entryPoints, &entryPointCount)
        
        return (0..<entryPointCount).map { String(cString: entryPoints[$0].name) }
    }
    
    deinit {
        vkDestroyShaderModule(self.device.vkDevice, self.vkModule, nil)
    }
}

public class VulkanShaderLibrary {
    let device: VulkanDevice
    let url : URL
    let modules : [VulkanShaderModule]
    private let functionsToModules : [String : VulkanShaderModule]
    
    let spvcContext : spvc_context
    private var reflectionCache = [PipelineLayoutKey : VulkanPipelineReflection]()
    private var pipelineLayoutCache = [PipelineLayoutKey : VkPipelineLayout]()
    
    public init(device: VulkanDevice, url: URL) throws {
        self.device = device
        self.url = url
        print("Loading shader library at url \(url.path)")

        var context : spvc_context? = nil
        spvc_context_create(&context)
        self.spvcContext = context!

        spvc_context_set_error_callback(context, { userData, error in
            print("Error in SPVC Context: \(String(cString: error!))")
        }, nil)
        
        let fileManager = FileManager.default
        let resources = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
        
        var modules = [VulkanShaderModule]()
        var functions = [String : VulkanShaderModule]()

        for file in resources {
            if file.pathExtension == "spv" {
                let shaderData = try Data(contentsOf: file, options: .mappedIfSafe)
        
                let module = VulkanShaderModule(device: device, spvcContext: self.spvcContext, data: shaderData)
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
    
    deinit {
        spvc_context_destroy(self.spvcContext)
    }
    
    func pipelineLayout(for key: PipelineLayoutKey) -> VkPipelineLayout {
        if let layout = self.pipelineLayoutCache[key] { // FIXME: we also need to take into account whether the /descriptor set layouts/ are identical.
            return layout
        }
        
        var createInfo = VkPipelineLayoutCreateInfo()
        createInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO
        
        let reflection = self.reflection(for: key)
        let setLayouts : [VkDescriptorSetLayout?] = reflection.vkDescriptorSetLayouts

        var pushConstantRanges = [VkPushConstantRange]()
        for resource in reflection.resources.values where resource.bindingPath.isPushConstant {
            pushConstantRanges.append(VkPushConstantRange(stageFlags: VkShaderStageFlags(resource.accessedStages), offset: resource.bindingRange.lowerBound, size: UInt32(resource.bindingRange.count)))
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
        
        var functions = [(String, spvc_compiler, SpvExecutionModel_)]()
        switch key {
        case .graphics(let vertexShader, let fragmentShader):
            guard let vertexModule = self.functionsToModules[vertexShader] else {
                fatalError("No shader entry point called \(vertexShader)")
            }
            functions.append((vertexModule.entryPointForFunction(named: vertexShader), vertexModule.compiler, SpvExecutionModelVertex))

            if let fragmentShader = fragmentShader {
                guard let fragmentModule = self.functionsToModules[fragmentShader] else {
                    fatalError("No shader entry point called \(fragmentShader)")
                }
                functions.append((fragmentModule.entryPointForFunction(named: fragmentShader), fragmentModule.compiler, SpvExecutionModelFragment))
            }
        case .compute(let computeShader):
            guard let module = self.functionsToModules[computeShader] else {
                fatalError("No shader entry point called \(computeShader)")
            }
            functions.append((module.entryPointForFunction(named: computeShader), module.compiler, SpvExecutionModelGLCompute))
        }

        let reflection = VulkanPipelineReflection(functions: functions, device: self.device)
        self.reflectionCache[key] = reflection
        return reflection
    }

    public func moduleForFunction(_ functionName: String) -> VulkanShaderModule? {
        return self.functionsToModules[functionName]
    }
    
}

#endif // canImport(Vulkan)
