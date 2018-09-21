//
//  PipelineReflection.swift
//  MetalRenderer
//
//  Created by roughtthom on 28/06/18.
//

import SwiftFrameGraph
import Metal
import Utilities

final class MetalPipelineReflection : PipelineReflection {
    
    struct BindingPathCacheKey : Hashable, CustomHashable {
        var argumentName: String
        var argumentBufferIndex: Int?
        
        public var customHashValue: Int {
            return self.hashValue
        }
    }
    
    let bindingPathCache : HashMap<BindingPathCacheKey, MetalResourceBindingPath>
    
    let reflectionCacheCount : Int
    let reflectionCacheKeys : UnsafePointer<MetalResourceBindingPath>
    let reflectionCacheValues : UnsafePointer<ArgumentReflection>
    
    deinit {
        self.bindingPathCache.deinit()
        
        self.reflectionCacheKeys.deallocate()
        self.reflectionCacheValues.deallocate()
    }
    
    init(bindingPathCache: HashMap<BindingPathCacheKey, MetalResourceBindingPath>, reflectionCache: [MetalResourceBindingPath : ArgumentReflection]) {
        self.bindingPathCache = bindingPathCache
        
        let sortedReflectionCache = reflectionCache.sorted(by: { $0.key.value < $1.key.value })
        let reflectionCacheKeys = UnsafeMutablePointer<MetalResourceBindingPath>.allocate(capacity: sortedReflectionCache.count + 1)
        let reflectionCacheValues = UnsafeMutablePointer<ArgumentReflection>.allocate(capacity: sortedReflectionCache.count)
        
        for (i, pair) in sortedReflectionCache.enumerated() {
            reflectionCacheKeys[i] = pair.key
            reflectionCacheValues[i] = pair.value
        }
        
        reflectionCacheKeys[sortedReflectionCache.count] = MetalResourceBindingPath(ResourceBindingPath(value: .max)) // Insert a sentinel to speed up the linear search; https://schani.wordpress.com/2010/04/30/linear-vs-binary-search/
        
        self.reflectionCacheCount = sortedReflectionCache.count
        self.reflectionCacheKeys = UnsafePointer(reflectionCacheKeys)
        self.reflectionCacheValues = UnsafePointer(reflectionCacheValues)
    }
    
    public convenience init(renderReflection: MTLRenderPipelineReflection) {
        var bindingPathCache = HashMap<BindingPathCacheKey, MetalResourceBindingPath>()
        var reflectionCache = [MetalResourceBindingPath : ArgumentReflection]()
        
        renderReflection.vertexArguments?.forEach { arg in
            MetalPipelineReflection.fillCaches(argument: arg, stages: .vertex, bindingPathCache: &bindingPathCache, reflectionCache: &reflectionCache)
        }
        
        renderReflection.fragmentArguments?.forEach { arg in
            MetalPipelineReflection.fillCaches(argument: arg, stages: .fragment, bindingPathCache: &bindingPathCache, reflectionCache: &reflectionCache)
        }
        
        self.init(bindingPathCache: bindingPathCache, reflectionCache: reflectionCache)
        
    }
    
    public convenience init(computeReflection: MTLComputePipelineReflection) {
        var bindingPathCache = HashMap<BindingPathCacheKey, MetalResourceBindingPath>()
        var reflectionCache = [MetalResourceBindingPath : ArgumentReflection]()
        
        computeReflection.arguments.forEach { arg in
            MetalPipelineReflection.fillCaches(argument: arg, stages: [], bindingPathCache: &bindingPathCache, reflectionCache: &reflectionCache)
        }
        self.init(bindingPathCache: bindingPathCache, reflectionCache: reflectionCache)
    }
    
    static func fillCaches(argument: MTLArgument, stages: MTLRenderStages, bindingPathCache: inout HashMap<BindingPathCacheKey, MetalResourceBindingPath>, reflectionCache: inout [MetalResourceBindingPath : ArgumentReflection]) {
        guard argument.type == .buffer || argument.type == .texture || argument.type == .sampler else {
            return
        }
        
        let cacheKey = BindingPathCacheKey(argumentName: argument.name, argumentBufferIndex: nil)
        
        var rootPath = MetalResourceBindingPath(stages: stages, type: argument.type, argumentBufferIndex: nil, index: argument.index)
        var reflection = ArgumentReflection(argument, bindingPath: rootPath)
        
        if let existingMatch = bindingPathCache[BindingPathCacheKey(argumentName: argument.name, argumentBufferIndex: nil)] {
            assert(existingMatch.index == rootPath.index && existingMatch.type == rootPath.type, "A variable with the same name is bound at different indices or with different types in the vertex and fragment shader.")
            
            let existingReflection = reflectionCache[rootPath]!
            
            rootPath.stages.formUnion(existingMatch.stages)
            
            reflection.isActive = reflection.isActive || existingReflection.isActive
            reflection.stages = reflection.stages.union(existingReflection.stages)
            reflection.bindingPath = ResourceBindingPath(rootPath)
            switch existingReflection.usageType {
            case .readWrite:
                reflection.usageType = existingReflection.usageType
            case .write:
                reflection.usageType = reflection.usageType == .read ? .readWrite : existingReflection.usageType
            default:
                break
            }
        }
        bindingPathCache[cacheKey] = rootPath
        reflectionCache[rootPath] = reflection
        
        if let elementStruct = argument.bufferPointerType?.elementStructType() {
            
            let metalArgBufferPath = rootPath
            for member in elementStruct.members {
                let subPath = MetalResourceBindingPath(stages: metalArgBufferPath.stages, type: member.dataType, argumentBufferIndex: metalArgBufferPath.index, index: member.argumentIndex)
                
                let reflection : ArgumentReflection?
                if let arrayType = member.arrayType() {
                    reflection = ArgumentReflection(array: arrayType, argumentBuffer: argument, bindingPath: subPath)
                } else {
                    reflection = ArgumentReflection(member: member, argumentBuffer: argument, bindingPath: subPath)
                }
                
                if reflection != nil {
                    reflectionCache[subPath] = reflection
                    bindingPathCache[BindingPathCacheKey(argumentName: member.name, argumentBufferIndex: argument.index)] = subPath
                }
            }
        }
    }
    
    public func bindingPath(argumentName: String, arrayIndex: Int, argumentBufferPath: ResourceBindingPath?) -> ResourceBindingPath? {
        let argumentBufferIndex : Int?
        if let argumentBufferPath = argumentBufferPath {
            argumentBufferIndex = MetalResourceBindingPath(argumentBufferPath).index
        } else {
            argumentBufferIndex = nil
        }
        
        let key = BindingPathCacheKey(argumentName: argumentName, argumentBufferIndex: argumentBufferIndex)
        if var path = self.bindingPathCache[key] {
            if argumentBufferIndex != nil { // If it's within an argument buffer
                path.index += arrayIndex
            } else {
                path.arrayIndex = arrayIndex
            }
            return ResourceBindingPath(path)
        } else {
            return nil
        }
    }
    
    // returnNearest: if there is no reflection for this path, return the reflection for the next lowest path (i.e. with the next lowest id).
    func reflectionCacheLinearSearch(_ path: MetalResourceBindingPath, returnNearest: Bool) -> ArgumentReflection? {
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
    func reflectionCacheBinarySearch(_ path: MetalResourceBindingPath, returnNearest: Bool) -> ArgumentReflection? {
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
        var path = MetalResourceBindingPath(path)
        path.arrayIndex = 0
        return reflectionCacheLinearSearch(path, returnNearest: path.argumentBufferIndex != nil) // If the path's in an argument buffer, the id might be higher than the id used for the reflection since array indices within argument buffers are represented as offsets to the id.
    }
    
    public func bindingPath(argumentBuffer: ArgumentBuffer, argumentName: String, arrayIndex: Int) -> ResourceBindingPath? {
        return self.bindingPath(argumentName: argumentName, arrayIndex: arrayIndex, argumentBufferPath: nil)
    }
    
    public func bindingPath(pathInOriginalArgumentBuffer: ResourceBindingPath, newArgumentBufferPath: ResourceBindingPath) -> ResourceBindingPath {
        let newParentPath = MetalResourceBindingPath(newArgumentBufferPath)
        
        var modifiedPath = MetalResourceBindingPath(pathInOriginalArgumentBuffer)
        modifiedPath.argumentBufferIndex = newParentPath.index
        modifiedPath.arrayIndex = newParentPath.arrayIndex
        modifiedPath.stages = newParentPath.stages
        return ResourceBindingPath(modifiedPath)
    }
    
    public func bindingIsActive(at path: ResourceBindingPath) -> Bool {
        return self.argumentReflection(at: path)?.isActive ?? false
    }
}
