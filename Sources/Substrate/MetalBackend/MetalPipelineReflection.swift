//
//  PipelineReflection.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 28/06/18.
//

#if canImport(Metal)

@preconcurrency import Metal
import SubstrateUtilities

final class MetalPipelineReflection : PipelineReflection {
    
    struct BindingPathCacheKey : Hashable, CustomHashable {
        var argumentName: String
        var argumentBufferIndex: Int?
        
        public var customHashValue: Int {
            return self.hashValue
        }
    }
    
    let _pipelineState: AnyObject
    var pipelineState: UnsafeRawPointer? { return UnsafeRawPointer(Unmanaged.passUnretained(self._pipelineState).toOpaque()) }
    
    let bindingPathCache : HashMap<BindingPathCacheKey, ResourceBindingPath>
    
    let reflectionCacheCount : Int
    let reflectionCacheKeys : UnsafePointer<ResourceBindingPath>
    let reflectionCacheValues : UnsafePointer<ArgumentReflection>
    let argumentBufferDescriptors: [ResourceBindingPath: ArgumentBufferDescriptor]
    
    let threadExecutionWidth: Int
    
    deinit {
        self.bindingPathCache.deinit()
        
        self.reflectionCacheKeys.deallocate()
        self.reflectionCacheValues.deallocate()
    }
    
    init(pipelineState: AnyObject, threadExecutionWidth: Int, bindingPathCache: HashMap<BindingPathCacheKey, ResourceBindingPath>, reflectionCache: [ResourceBindingPath : ArgumentReflection], argumentBufferDescriptors: [ResourceBindingPath: ArgumentBufferDescriptor]) {
        self._pipelineState = pipelineState
        self.threadExecutionWidth = threadExecutionWidth
        self.bindingPathCache = bindingPathCache
        
        let sortedReflectionCache = reflectionCache.sorted(by: { $0.key.value < $1.key.value })
        let reflectionCacheKeys = UnsafeMutablePointer<ResourceBindingPath>.allocate(capacity: sortedReflectionCache.count + 1)
        let reflectionCacheValues = UnsafeMutablePointer<ArgumentReflection>.allocate(capacity: sortedReflectionCache.count)
        
        for (i, pair) in sortedReflectionCache.enumerated() {
            reflectionCacheKeys[i] = pair.key
            reflectionCacheValues[i] = pair.value
        }
        
        reflectionCacheKeys[sortedReflectionCache.count] = .nil // Insert a sentinel to speed up the linear search; https://schani.wordpress.com/2010/04/30/linear-vs-binary-search/
        
        self.reflectionCacheCount = sortedReflectionCache.count
        self.reflectionCacheKeys = UnsafePointer(reflectionCacheKeys)
        self.reflectionCacheValues = UnsafePointer(reflectionCacheValues)
        
        self.argumentBufferDescriptors = argumentBufferDescriptors
    }
    
    public convenience init(threadExecutionWidth: Int, vertexFunction: MTLFunction, fragmentFunction: MTLFunction?, renderState: MTLRenderPipelineState, renderReflection: MTLRenderPipelineReflection) {
        var bindingPathCache = HashMap<BindingPathCacheKey, ResourceBindingPath>()
        var reflectionCache = [ResourceBindingPath : ArgumentReflection]()
        var argumentDescriptorCache = [ResourceBindingPath: ArgumentBufferDescriptor]()
        
        renderReflection.vertexArguments?.forEach { arg in
            MetalPipelineReflection.fillCaches(function: vertexFunction, argument: arg, stages: .vertex, bindingPathCache: &bindingPathCache, reflectionCache: &reflectionCache, argumentBufferDescriptorCache: &argumentDescriptorCache)
        }
        
        renderReflection.fragmentArguments?.forEach { arg in
            MetalPipelineReflection.fillCaches(function: fragmentFunction!, argument: arg, stages: .fragment, bindingPathCache: &bindingPathCache, reflectionCache: &reflectionCache, argumentBufferDescriptorCache: &argumentDescriptorCache)
        }
        
        self.init(pipelineState: renderState, threadExecutionWidth: threadExecutionWidth, bindingPathCache: bindingPathCache, reflectionCache: reflectionCache, argumentBufferDescriptors: argumentDescriptorCache)
    }
    
    
    @available(macOS 13.0, *)
    public convenience init(threadExecutionWidth: Int, objectFunction: MTLFunction, meshFunction: MTLFunction, fragmentFunction: MTLFunction?, renderState: MTLRenderPipelineState, renderReflection: MTLRenderPipelineReflection) {
        var bindingPathCache = HashMap<BindingPathCacheKey, ResourceBindingPath>()
        var reflectionCache = [ResourceBindingPath : ArgumentReflection]()
        var argumentDescriptorCache = [ResourceBindingPath: ArgumentBufferDescriptor]()
        
        renderReflection.objectBindings.forEach { binding in
            MetalPipelineReflection.fillCaches(function: objectFunction, binding: binding, stages: .object, bindingPathCache: &bindingPathCache, reflectionCache: &reflectionCache, argumentBufferDescriptorCache: &argumentDescriptorCache)
        }
        
        renderReflection.meshBindings.forEach { binding in
            MetalPipelineReflection.fillCaches(function: meshFunction, binding: binding, stages: .mesh, bindingPathCache: &bindingPathCache, reflectionCache: &reflectionCache, argumentBufferDescriptorCache: &argumentDescriptorCache)
        }
        
        renderReflection.fragmentBindings.forEach { binding in
            MetalPipelineReflection.fillCaches(function: fragmentFunction!, binding: binding, stages: .fragment, bindingPathCache: &bindingPathCache, reflectionCache: &reflectionCache, argumentBufferDescriptorCache: &argumentDescriptorCache)
        }
        
        self.init(pipelineState: renderState, threadExecutionWidth: threadExecutionWidth, bindingPathCache: bindingPathCache, reflectionCache: reflectionCache, argumentBufferDescriptors: argumentDescriptorCache)
    }
    
    public convenience init(threadExecutionWidth: Int, function: MTLFunction, computeState: MTLComputePipelineState, computeReflection: MTLComputePipelineReflection) {
        var bindingPathCache = HashMap<BindingPathCacheKey, ResourceBindingPath>()
        var reflectionCache = [ResourceBindingPath : ArgumentReflection]()
        var argumentDescriptorCache = [ResourceBindingPath: ArgumentBufferDescriptor]()
        
        computeReflection.arguments.forEach { arg in
            MetalPipelineReflection.fillCaches(function: function, argument: arg, stages: .compute, bindingPathCache: &bindingPathCache, reflectionCache: &reflectionCache, argumentBufferDescriptorCache: &argumentDescriptorCache)
        }
        self.init(pipelineState: computeState, threadExecutionWidth: threadExecutionWidth, bindingPathCache: bindingPathCache, reflectionCache: reflectionCache, argumentBufferDescriptors: argumentDescriptorCache)
    }
    
    static func fillCaches(function: MTLFunction, argument: MTLArgument, stages: RenderStages, bindingPathCache: inout HashMap<BindingPathCacheKey, ResourceBindingPath>, reflectionCache: inout [ResourceBindingPath : ArgumentReflection], argumentBufferDescriptorCache: inout [ResourceBindingPath: ArgumentBufferDescriptor]) {
        guard argument.type != .threadgroupMemory else { return }
        
        let mtlStages = MTLRenderStages(stages)
        
        let cacheKey = BindingPathCacheKey(argumentName: argument.name, argumentBufferIndex: nil)
        
        var rootPath = ResourceBindingPath(type: argument.type, index: argument.index, argumentBufferIndex: nil, stages: mtlStages)
        var reflection = ArgumentReflection(argument, bindingPath: rootPath, stages: stages)
        
        if let existingMatch = bindingPathCache[BindingPathCacheKey(argumentName: argument.name, argumentBufferIndex: nil)] {
            assert(existingMatch.index == rootPath.index && existingMatch.type == rootPath.type, "A variable with the same name is bound at different indices or with different types in the vertex and fragment shader.")
            
            rootPath.stages = existingMatch.stages
            let existingReflection = reflectionCache[rootPath]!
            rootPath.stages.formUnion(mtlStages)
            
            reflection.activeStages.formUnion(existingReflection.activeStages)
            reflection.bindingPath = rootPath
            reflection.usageType.formUnion(existingReflection.usageType)
        }
        bindingPathCache[cacheKey] = rootPath
        reflectionCache[rootPath] = reflection
        
        if let elementStruct = argument.bufferPointerType?.elementStructType() {
            let isArgumentBuffer = elementStruct.members.contains(where: { member in
                if member.offset < 0 { return true } // Only applies for macOS versions earlier than 13.0 (Ventura)
                return member.argumentIndex > 0
            })
            var argumentBufferBindings = [ArgumentDescriptor]()
            var argumentBufferBindingCount = 0
            var argumentBufferMaxBinding = 0
            
            let metalArgBufferPath = rootPath
            for member in elementStruct.members {
                if isArgumentBuffer {
                    let arrayLength = member.arrayType()?.arrayLength ?? 1
                    argumentBufferBindingCount += arrayLength
                    argumentBufferMaxBinding = max(member.argumentIndex + arrayLength - 1, argumentBufferMaxBinding)
                }

                // Ignore pipeline stages for resources contained within argument buffers.
                let dataType: MTLDataType
                if let arrayType = member.arrayType() {
                    dataType = arrayType.elementType // Handle arrays of textures
                } else {
                    dataType = member.dataType
                }
                
                let subPath = ResourceBindingPath(type: dataType, index: member.argumentIndex, argumentBufferIndex: metalArgBufferPath.index, stages: [])
                
                let memberReflection : ArgumentReflection?
                if let arrayType = member.arrayType() {
                    memberReflection = ArgumentReflection(array: arrayType, argumentBuffer: argument, bindingPath: subPath, stages: reflection.activeStages)
                    
                    if isArgumentBuffer {
                        switch arrayType.elementType {
                        case .pointer:
                            let pointerType = arrayType.elementPointerType()!
                            argumentBufferBindings.append(ArgumentDescriptor(resourceType: .storageBuffer, index: member.argumentIndex, arrayLength: arrayType.arrayLength, accessType: ResourceAccessType(pointerType.access)))
                        case .sampler:
                            argumentBufferBindings.append(ArgumentDescriptor(resourceType: .sampler, index: member.argumentIndex, arrayLength: arrayType.arrayLength, accessType: .read))
                        case .texture:
                            let textureType = arrayType.elementTextureReferenceType()!
                            argumentBufferBindings.append(ArgumentDescriptor(resourceType: .texture(type: TextureType(textureType.textureType)), index: member.argumentIndex, arrayLength: arrayType.arrayLength, accessType: ResourceAccessType(textureType.access)))
                            
                        case .primitiveAccelerationStructure, .instanceAccelerationStructure:
                            argumentBufferBindings.append(ArgumentDescriptor(resourceType: .accelerationStructure, index: member.argumentIndex, arrayLength: arrayType.arrayLength, accessType: .read))
                            
                        default:
                            print("MetalPipelineReflection: warning: unhandled argument at index \(member.argumentIndex)")
                            break
                        }
                    }
                    
                } else {
                    memberReflection = ArgumentReflection(member: member, argumentBuffer: argument, bindingPath: subPath, stages: reflection.activeStages)
                    
                    if isArgumentBuffer {
                        switch dataType {
                        case .pointer:
                            let pointerType = member.pointerType()!
                            let isConstantBuffer = pointerType.alignment >= 16 && pointerType.access == .readOnly
                            
                            argumentBufferBindings.append(ArgumentDescriptor(resourceType: isConstantBuffer ? .constantBuffer(alignment: pointerType.alignment) : .storageBuffer, index: member.argumentIndex, arrayLength: 1, accessType: ResourceAccessType(pointerType.access)))
                        case .sampler:
                            argumentBufferBindings.append(ArgumentDescriptor(resourceType: .sampler, index: member.argumentIndex, arrayLength: 1, accessType: .read))
                        case .texture:
                            let textureType = member.textureReferenceType()!
                            argumentBufferBindings.append(ArgumentDescriptor(resourceType: .texture(type: TextureType(textureType.textureType)), index: member.argumentIndex, arrayLength: 1, accessType: ResourceAccessType(textureType.access)))
                            
                        case .primitiveAccelerationStructure, .instanceAccelerationStructure:
                            argumentBufferBindings.append(ArgumentDescriptor(resourceType: .accelerationStructure, index: member.argumentIndex, arrayLength: 1, accessType: .read))
                            
                        default:
                            print("MetalPipelineReflection: warning: unhandled argument at index \(member.argumentIndex)")
                            break
                        }
                    }
                }
                
                if let memberReflection = memberReflection {
                    assert(ResourceType(subPath.type) == memberReflection.type)
                    
                    if var existingReflection = reflectionCache[subPath] {
                        existingReflection.activeStages.formUnion(memberReflection.activeStages)
                        if !memberReflection.activeStages.isEmpty {
                            existingReflection.activeRange = .fullResource
                        }
                        assert(existingReflection.type == memberReflection.type)
                        assert(existingReflection.usageType == memberReflection.usageType)
                        reflectionCache[subPath] = existingReflection
                    } else {
                        reflectionCache[subPath] = memberReflection
                    }
                    bindingPathCache[BindingPathCacheKey(argumentName: member.name, argumentBufferIndex: argument.index)] = subPath
                }
            }
            
            if isArgumentBuffer {
                argumentBufferDescriptorCache[rootPath] = ArgumentBufferDescriptor(arguments: argumentBufferBindings)
            }
        }
    }
    
    @available(macOS 13.0, *)
    static func fillCaches(function: MTLFunction, binding: MTLBinding, stages: RenderStages, bindingPathCache: inout HashMap<BindingPathCacheKey, ResourceBindingPath>, reflectionCache: inout [ResourceBindingPath : ArgumentReflection], argumentBufferDescriptorCache: inout [ResourceBindingPath: ArgumentBufferDescriptor]) {
        guard binding.type != .threadgroupMemory else { return }
        
        let mtlStages = MTLRenderStages(stages)
        
        let cacheKey = BindingPathCacheKey(argumentName: binding.name, argumentBufferIndex: nil)
        
        var rootPath = ResourceBindingPath(type: binding.type, index: binding.index, argumentBufferIndex: nil, stages: mtlStages)
        var reflection = ArgumentReflection(binding, bindingPath: rootPath, stages: stages)
        
        if let existingMatch = bindingPathCache[BindingPathCacheKey(argumentName: binding.name, argumentBufferIndex: nil)] {
            assert(existingMatch.index == rootPath.index && existingMatch.type == rootPath.type, "A variable with the same name is bound at different indices or with different types in the vertex and fragment shader.")
            
            rootPath.stages = existingMatch.stages
            let existingReflection = reflectionCache[rootPath]!
            rootPath.stages.formUnion(mtlStages)
            
            reflection.activeStages.formUnion(existingReflection.activeStages)
            reflection.bindingPath = rootPath
            reflection.usageType.formUnion(existingReflection.usageType)
        }
        bindingPathCache[cacheKey] = rootPath
        reflectionCache[rootPath] = reflection
        
        if let elementStruct = (binding as? MTLBufferBinding)?.bufferPointerType?.elementStructType() {
            let isArgumentBuffer = elementStruct.members.contains(where: { member in
                if member.offset < 0 { return true } // Only applies for macOS versions earlier than 13.0 (Ventura)
                return member.argumentIndex > 0
            })
            var argumentBufferBindings = [ArgumentDescriptor]()
            var argumentBufferBindingCount = 0
            var argumentBufferMaxBinding = 0
            
            let metalArgBufferPath = rootPath
            for member in elementStruct.members {
                if isArgumentBuffer {
                    let arrayLength = member.arrayType()?.arrayLength ?? 1
                    argumentBufferBindingCount += arrayLength
                    argumentBufferMaxBinding = max(member.argumentIndex + arrayLength - 1, argumentBufferMaxBinding)
                }

                // Ignore pipeline stages for resources contained within argument buffers.
                let dataType: MTLDataType
                if let arrayType = member.arrayType() {
                    dataType = arrayType.elementType // Handle arrays of textures
                } else {
                    dataType = member.dataType
                }
                
                let subPath = ResourceBindingPath(type: dataType, index: member.argumentIndex, argumentBufferIndex: metalArgBufferPath.index, stages: [])
                
                let memberReflection : ArgumentReflection?
                if let arrayType = member.arrayType() {
                    memberReflection = ArgumentReflection(array: arrayType, argumentBuffer: binding, bindingPath: subPath, stages: reflection.activeStages)
                    
                    if isArgumentBuffer {
                        switch arrayType.elementType {
                        case .pointer:
                            let pointerType = arrayType.elementPointerType()!
                            argumentBufferBindings.append(ArgumentDescriptor(resourceType: .storageBuffer, index: member.argumentIndex, arrayLength: arrayType.arrayLength, accessType: ResourceAccessType(pointerType.access)))
                        case .sampler:
                            argumentBufferBindings.append(ArgumentDescriptor(resourceType: .sampler, index: member.argumentIndex, arrayLength: arrayType.arrayLength, accessType: .read))
                        case .texture:
                            let textureType = arrayType.elementTextureReferenceType()!
                            argumentBufferBindings.append(ArgumentDescriptor(resourceType: .texture(type: TextureType(textureType.textureType)), index: member.argumentIndex, arrayLength: arrayType.arrayLength, accessType: ResourceAccessType(textureType.access)))
                            
                        case .primitiveAccelerationStructure, .instanceAccelerationStructure:
                            argumentBufferBindings.append(ArgumentDescriptor(resourceType: .accelerationStructure, index: member.argumentIndex, arrayLength: arrayType.arrayLength, accessType: .read))
                            
                        default:
                            print("MetalPipelineReflection: warning: unhandled argument at index \(member.argumentIndex)")
                            break
                        }
                    }
                    
                } else {
                    memberReflection = ArgumentReflection(member: member, argumentBuffer: binding, bindingPath: subPath, stages: reflection.activeStages)
                    
                    if isArgumentBuffer {
                        switch dataType {
                        case .pointer:
                            let pointerType = member.pointerType()!
                            let isConstantBuffer = pointerType.alignment >= 16 && pointerType.access == .readOnly
                            
                            argumentBufferBindings.append(ArgumentDescriptor(resourceType: isConstantBuffer ? .constantBuffer(alignment: pointerType.alignment) : .storageBuffer, index: member.argumentIndex, arrayLength: 1, accessType: ResourceAccessType(pointerType.access)))
                        case .sampler:
                            argumentBufferBindings.append(ArgumentDescriptor(resourceType: .sampler, index: member.argumentIndex, arrayLength: 1, accessType: .read))
                        case .texture:
                            let textureType = member.textureReferenceType()!
                            argumentBufferBindings.append(ArgumentDescriptor(resourceType: .texture(type: TextureType(textureType.textureType)), index: member.argumentIndex, arrayLength: 1, accessType: ResourceAccessType(textureType.access)))
                            
                        case .primitiveAccelerationStructure, .instanceAccelerationStructure:
                            argumentBufferBindings.append(ArgumentDescriptor(resourceType: .accelerationStructure, index: member.argumentIndex, arrayLength: 1, accessType: .read))
                            
                        default:
                            print("MetalPipelineReflection: warning: unhandled argument at index \(member.argumentIndex)")
                            break
                        }
                    }
                }
                
                if let memberReflection = memberReflection {
                    assert(ResourceType(subPath.type) == memberReflection.type)
                    
                    if var existingReflection = reflectionCache[subPath] {
                        existingReflection.activeStages.formUnion(memberReflection.activeStages)
                        if !memberReflection.activeStages.isEmpty {
                            existingReflection.activeRange = .fullResource
                        }
                        assert(existingReflection.type == memberReflection.type)
                        assert(existingReflection.usageType == memberReflection.usageType)
                        reflectionCache[subPath] = existingReflection
                    } else {
                        reflectionCache[subPath] = memberReflection
                    }
                    bindingPathCache[BindingPathCacheKey(argumentName: member.name, argumentBufferIndex: binding.index)] = subPath
                }
            }
            
            if isArgumentBuffer {
                argumentBufferDescriptorCache[rootPath] = ArgumentBufferDescriptor(arguments: argumentBufferBindings)
            }
        }
    }
    
    public func bindingPath(argumentName: String, arrayIndex: Int, argumentBufferPath: ResourceBindingPath?) -> ResourceBindingPath? {
        let argumentBufferIndex : Int?
        if let argumentBufferPath = argumentBufferPath {
            argumentBufferIndex = argumentBufferPath.index
        } else {
            argumentBufferIndex = nil
        }
        
        let key = BindingPathCacheKey(argumentName: argumentName, argumentBufferIndex: argumentBufferIndex)
        if var path = self.bindingPathCache[key] {
            if argumentBufferIndex != nil { // If it's within an argument buffer
                path.index += arrayIndex
            } else {
                path.arrayIndexMetal = arrayIndex
            }
            return path
        } else {
            return nil
        }
    }
    
    // returnNearest: if there is no reflection for this path, return the reflection for the next lowest path (i.e. with the next lowest id).
    func pathInCache(_ path: ResourceBindingPath) -> Bool {
        var i = 0
        while true { // We're guaranteed to always exit this loop since there's a sentinel value with UInt64.max at the end of reflectionCacheKeys
            if self.reflectionCacheKeys[i].value >= path.value {
                break
            }
            i += 1
        }
        
        if i < self.reflectionCacheCount, self.reflectionCacheKeys[i] == path {
            return true
        } else {
            return false
        }
    }

    // returnNearest: if there is no reflection for this path, return the reflection for the next lowest path (i.e. with the next lowest id).
    func reflectionCacheLinearSearch(_ path: ResourceBindingPath) -> ArgumentReflection? {
        var i = 0
        while true { // We're guaranteed to always exit this loop since there's a sentinel value with UInt64.max at the end of reflectionCacheKeys
            if self.reflectionCacheKeys[i].value >= path.value {
                break
            }
            i += 1
        }
        
        if i < self.reflectionCacheCount, self.reflectionCacheKeys[i] == path {
            return self.reflectionCacheValues[i]
        } else if i - 1 > 0, i - 1 < self.reflectionCacheCount { // Check for the next lowest binding path.
            let foundPath = self.reflectionCacheKeys[i - 1]
            if foundPath.stageTypeAndArgBufferMask == path.stageTypeAndArgBufferMask { // Only return this if the stages, argument buffer index, and type all match.
                let offset = path.bindIndex - foundPath.bindIndex
                let reflection = self.reflectionCacheValues[i - 1]
                return offset < reflection.arrayLength ? reflection : nil
            }
        }
        return nil
    }
    
    // returnNearest: if there is no reflection for this path, return the reflection for the next lowest path (i.e. with the next lowest id).
    func reflectionCacheBinarySearch(_ path: ResourceBindingPath) -> ArgumentReflection? {
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
        } else if low - 1 > 0, low - 1 < self.reflectionCacheCount { // Check for the next lowest binding path.
            let foundPath = self.reflectionCacheKeys[low - 1]
            if foundPath.stageTypeAndArgBufferMask == path.stageTypeAndArgBufferMask { // Only return this if the stages, argument buffer index, and type all match.
                let offset = path.bindIndex - foundPath.bindIndex
                let reflection = self.reflectionCacheValues[low - 1]
                return offset < reflection.arrayLength ? reflection : nil
            }
        }
        return nil
    }
    
    public func argumentReflection(at path: ResourceBindingPath) -> ArgumentReflection? {
        var path = path
        path.arrayIndexMetal = 0
        if path.argumentBufferIndex == nil {
            let path = self.remapArgumentBufferPathForActiveStages(path)
            return reflectionCacheLinearSearch(path)
        } else {
            // Resources inside argument buffers aren't separated by pipeline stage.
            path.stages = []
            return reflectionCacheLinearSearch(path) // If the path's in an argument buffer, the id might be higher than the id used for the reflection since array indices within argument buffers are represented as offsets to the id.
        }
    }
    
    public func bindingPath(argumentBuffer: ArgumentBuffer, argumentName: String, arrayIndex: Int) -> ResourceBindingPath? {
        return self.bindingPath(argumentName: argumentName, arrayIndex: arrayIndex, argumentBufferPath: nil)
    }
    
    public func bindingPath(pathInOriginalArgumentBuffer: ResourceBindingPath, newArgumentBufferPath: ResourceBindingPath) -> ResourceBindingPath {
        let newParentPath = newArgumentBufferPath
        
        var modifiedPath = pathInOriginalArgumentBuffer
        modifiedPath.argumentBufferIndex = newParentPath.index
        modifiedPath.arrayIndexMetal = newParentPath.arrayIndexMetal
        modifiedPath.stages = newParentPath.stages
        return modifiedPath
    }
    
    public func remapArgumentBufferPathForActiveStages(_ path: ResourceBindingPath) -> ResourceBindingPath {
        var testPath = path
        testPath.arrayIndexMetal = 0
        
        if self.pathInCache(testPath) { return path }

        if path.stages.contains([.vertex, .fragment]) {
            testPath.stages = .fragment
            if pathInCache(testPath) {
                var path = path
                path.stages = .fragment
                return path
            }
            testPath.stages = .vertex
            if pathInCache(testPath) {
                var path = path
                path.stages = .vertex
                return path
            }
        } else if path.stages.intersection([.vertex, .fragment]) != [] {
            testPath.stages = [.vertex, .fragment]
            if pathInCache(testPath) {
                var path = path
                path.stages = [.vertex, .fragment]
                return path
            }
        }
        
        testPath.stages = [] // Check to see if we have an active binding for that path within a compute shader.
        if pathInCache(testPath) {
            var path = path
            path.stages = []
            return path
        }
        
        return path
    }
}


extension MTLStructMember {
    var isNonPODMember: Bool {
        switch self.dataType {
        case .pointer, .texture, .sampler, .renderPipeline, .computePipeline, .indirectCommandBuffer, .primitiveAccelerationStructure, .instanceAccelerationStructure, .visibleFunctionTable, .intersectionFunctionTable:
            return true
        case .array:
            var array = self.arrayType()!
            repeat {
                if let structType = array.elementStructType() {
                    return structType.members.contains(where: { $0.isNonPODMember })
                } else if let arrayType = array.element() {
                    array = arrayType
                } else {
                    switch array.elementType {
                    case .pointer, .texture, .sampler, .renderPipeline, .computePipeline, .indirectCommandBuffer, .primitiveAccelerationStructure, .instanceAccelerationStructure, .visibleFunctionTable, .intersectionFunctionTable:
                        return true
                    default:
                        return false
                    }
                }
            } while true
        default:
            return false
        }
    }
}

#endif // canImport(Metal)
