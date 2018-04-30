//
//  Caches.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 24/12/17.
//

import RenderAPI
import Metal

final class StateCaches {
    
    let device : MTLDevice
    let library : MTLLibrary
    
    struct FunctionCacheKey : Hashable {
        var name : String
        var constants : AnyFunctionConstants?
    }
    
    struct ArgumentEncoderCacheKey : Hashable {
        var function : FunctionCacheKey
        var index : Int
    }
    
    struct BindingPathCacheKey : Hashable {
        var argumentName: String
        var argumentBufferPath: ResourceBindingPath?
    }
    
    private var functionCache = [FunctionCacheKey : MTLFunction]()
    private var bindingPathCache = [BindingPathCacheKey : MetalResourceBindingPath]()
    
    private var computeStates = [ComputePipelineDescriptor : MTLComputePipelineState]()
    private var computeReflection = [ComputePipelineDescriptor : MTLComputePipelineReflection]()
    private var currentComputeReflection : MTLComputePipelineReflection? = nil
    
    private var renderStates = [MetalRenderPipelineDescriptor : MTLRenderPipelineState]()
    private var renderReflection = [RenderPipelineDescriptor : MTLRenderPipelineReflection]()
    private var currentRenderReflection : MTLRenderPipelineReflection? = nil
    
    private var depthStates = [DepthStencilDescriptor : MTLDepthStencilState]()
    private var samplerStates = [SamplerDescriptor : MTLSamplerState]()
    
    private var argumentEncoders = [ArgumentEncoderCacheKey : MTLArgumentEncoder]()
    
    public init(device: MTLDevice) {
        self.device = device
        self.library = device.makeDefaultLibrary()!
    }
    
    func function(named name: String, functionConstants: AnyFunctionConstants?) -> MTLFunction {
        let cacheKey = FunctionCacheKey(name: name, constants: functionConstants)
        if let function = self.functionCache[cacheKey] {
            return function
        }
        let function : MTLFunction
        
        if let functionConstants = functionConstants {
            let fcEncoder = FunctionConstantEncoder()
            let functionConstantsDict = try! fcEncoder.encodeToDict(functionConstants)
            function = try! self.library.makeFunction(name: name, constantValues: MTLFunctionConstantValues(functionConstantsDict))
        } else {
            function = self.library.makeFunction(name: name)!
        }
        
        self.functionCache[cacheKey] = function
        return function
    }
    
    func argumentEncoder(atIndex index: Int, functionName: String, functionConstants: AnyFunctionConstants?) -> MTLArgumentEncoder {
        let cacheKey = ArgumentEncoderCacheKey(function: StateCaches.FunctionCacheKey(name: functionName, constants: functionConstants), index: index)
        if let encoder = self.argumentEncoders[cacheKey] {
            return encoder
        }
        let function = self.function(named: functionName, functionConstants: functionConstants)
        let encoder = function.makeArgumentEncoder(bufferIndex: index)
        self.argumentEncoders[cacheKey] = encoder
        
        return encoder
    }
    
    public subscript(descriptor: RenderPipelineDescriptor, renderTarget renderTarget: RenderTargetDescriptor) -> MTLRenderPipelineState {
        let metalDescriptor = MetalRenderPipelineDescriptor(descriptor, renderTargetDescriptor: renderTarget)
        
        if let state = self.renderStates[metalDescriptor] {
            return state
        }
        
        let mtlDescriptor = MTLRenderPipelineDescriptor(metalDescriptor, stateCaches: self)
        
        var reflection : MTLRenderPipelineReflection? = nil
        let state = try! self.device.makeRenderPipelineState(descriptor: mtlDescriptor, options: [.argumentInfo, .bufferTypeInfo], reflection: &reflection)
        
        self.renderStates[metalDescriptor] = state
        self.renderReflection[descriptor] = reflection
        
        return state
        
    }
    
    public func reflection(for pipelineDescriptor: RenderPipelineDescriptor, renderTarget: RenderTargetDescriptor) -> MTLRenderPipelineReflection {
        if let reflection = self.renderReflection[pipelineDescriptor] {
            return reflection
        }
        
        let _ = self[pipelineDescriptor, renderTarget: renderTarget]
        return self.reflection(for: pipelineDescriptor, renderTarget: renderTarget)
    }
    
    public subscript(descriptor: ComputePipelineDescriptor) -> MTLComputePipelineState {
        // Figure out whether the thread group size is always a multiple of the thread execution width and set the optimisation hint appropriately.
        
        if let state = self.computeStates[descriptor] {
            return state
        }
        
        let mtlDescriptor = MTLComputePipelineDescriptor()
        mtlDescriptor.computeFunction = self.function(named: descriptor.function, functionConstants: descriptor.functionConstants)
        mtlDescriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = descriptor.threadgroupSizeIsMultipleOfThreadExecutionWidth // TODO: can we infer this?
        
        var reflection : MTLComputePipelineReflection? = nil
        let state = try! self.device.makeComputePipelineState(descriptor: mtlDescriptor, options: [.argumentInfo, .bufferTypeInfo], reflection: &reflection)
        
        self.computeStates[descriptor] = state
        self.computeReflection[descriptor] = reflection
        
        return state
    }
    
    public func reflection(for pipelineDescriptor: ComputePipelineDescriptor) -> MTLComputePipelineReflection {
        if let reflection = self.computeReflection[pipelineDescriptor] {
            return reflection
        }
        
        let _ = self[pipelineDescriptor]
        return self.reflection(for: pipelineDescriptor)
    }
    
    public func setReflectionRenderPipeline(descriptor: RenderPipelineDescriptor, renderTarget: RenderTargetDescriptor) {
        self.currentComputeReflection = nil
        self.currentRenderReflection = self.reflection(for: descriptor, renderTarget: renderTarget)
        self.bindingPathCache.removeAll(keepingCapacity: true)
    }
    
    public func setReflectionComputePipeline(descriptor: ComputePipelineDescriptor) {
        self.currentRenderReflection = nil
        self.currentComputeReflection = self.reflection(for: descriptor)
        self.bindingPathCache.removeAll(keepingCapacity: true)
    }
    
    func bindingPathWithinArgumentBuffer(argumentName: String, argumentBufferPath: ResourceBindingPath) -> MetalResourceBindingPath? {
        let metalArgBufferPath = MetalResourceBindingPath(argumentBufferPath)
        assert(metalArgBufferPath.argumentBufferIndex == nil, "Nested argument buffers are unsupported.")
        
        // Look at the reflection information for the argument buffer within the currently bound function.
        // We can assume that the vertex and fragment functions will refer to the same argument buffer.
        let arguments : [MTLArgument]
        if metalArgBufferPath.stages.contains(.vertex) {
            arguments = self.currentRenderReflection!.vertexArguments!
        } else if metalArgBufferPath.stages.contains(.fragment) {
            arguments = self.currentRenderReflection!.fragmentArguments!
        } else {
            arguments = self.currentComputeReflection!.arguments
        }
        
        guard let argument = arguments.first(where: { $0.index == metalArgBufferPath.index }) else {
            return nil
        }
        
        guard let elementStruct = argument.bufferPointerType?.elementStructType() else {
            return nil
        }
        
        if let member = elementStruct.memberByName(argumentName) {
            return MetalResourceBindingPath(stages: metalArgBufferPath.stages, type: member.dataType, argumentBufferIndex: metalArgBufferPath.index, index: member.argumentIndex)
        }
        return nil
    }

    public func bindingPath(argumentName: String, arrayIndex: Int, argumentBufferPath: ResourceBindingPath?) -> ResourceBindingPath? {
        
        let key = BindingPathCacheKey(argumentName: argumentName, argumentBufferPath: argumentBufferPath)
        var path : MetalResourceBindingPath? = self.bindingPathCache[key]
        
        if let argumentBufferPath = argumentBufferPath {
            path = self.bindingPathWithinArgumentBuffer(argumentName: argumentName, argumentBufferPath: argumentBufferPath)
        } else if path == nil {
            if let renderReflection = self.currentRenderReflection {
                for argument in renderReflection.vertexArguments! {
                    if argument.name == argumentName {
                        path = MetalResourceBindingPath(stages: .vertex, type: argument.type, argumentBufferIndex: nil, index: argument.index)
                        break
                    }
                }
                
                if let fragmentArgs = renderReflection.fragmentArguments {
                    for argument in fragmentArgs {
                        if argument.name == argumentName {
                            assert(path == nil || path!.index == argument.index, "A variable with the same name is bound at different indices in the vertex and fragment shader.")
                            if path != nil {
                                path!.stages.formUnion(.fragment)
                            } else {
                                path = MetalResourceBindingPath(stages: .fragment, type: argument.type, argumentBufferIndex: nil, index: argument.index)
                                break
                            }
                        }
                    }
                    
                }
                
            } else if let computeReflection = self.currentComputeReflection {
                for argument in computeReflection.arguments {
                    if argument.name == argumentName {
                        path = MetalResourceBindingPath(stages: [], type: argument.type, argumentBufferIndex: nil, index: argument.index)
                        break
                    }
                }
            }
        }
        
        if var path = path {
            self.bindingPathCache[key] = path
            
            path.arrayIndex = arrayIndex
            return ResourceBindingPath(path)
        } else {
            return nil
        }
    }
    
    func argumentBufferArgumentReflection(argumentBufferIndex: Int, path: MetalResourceBindingPath) -> ArgumentReflection? {
        let arguments : [MTLArgument]
        if path.stages.contains(.vertex) {
            arguments = self.currentRenderReflection!.vertexArguments!
        } else if path.stages.contains(.fragment) {
            arguments = self.currentRenderReflection!.fragmentArguments!
        } else {
            arguments = self.currentComputeReflection!.arguments
        }
        
        let argument = arguments.first(where: { $0.index == argumentBufferIndex })!
        
        let member = argument.bufferPointerType!.elementStructType()!.members[path.index]
        if let arrayType = member.arrayType() {
            return ArgumentReflection(array: arrayType, argumentBuffer: argument, bindingPath: path)
        }
        
        return ArgumentReflection(member: member, argumentBuffer: argument, bindingPath: path)
    }
    
    public func argumentReflection(at path: ResourceBindingPath) -> ArgumentReflection? {
        let mtlPath = MetalResourceBindingPath(path)
        
        if let argumentBufferIndex = mtlPath.argumentBufferIndex {
            return self.argumentBufferArgumentReflection(argumentBufferIndex: argumentBufferIndex, path: mtlPath)
        }
        
        let argumentArray : [MTLArgument]
        
        if mtlPath.stages.contains(.vertex) {
            guard let vertexArgs = self.currentRenderReflection!.vertexArguments else { return nil }
            argumentArray = vertexArgs
            
        } else if mtlPath.stages.contains(.fragment) {
            guard let fragmentArgs = self.currentRenderReflection!.fragmentArguments else { return nil }
            argumentArray = fragmentArgs
            
        } else {
            guard let computeArgs = self.currentComputeReflection?.arguments else { return nil }
            argumentArray = computeArgs
            
        }
        
        for arg in argumentArray {
            if arg.index == mtlPath.index {
                return ArgumentReflection(arg, bindingPath: mtlPath)
            }
        }
        
        return nil
    }
    
    public subscript(descriptor: SamplerDescriptor) -> MTLSamplerState {
        if let state = self.samplerStates[descriptor] {
            return state
        }
        
        let mtlDescriptor = MTLSamplerDescriptor(descriptor)
        let state = self.device.makeSamplerState(descriptor: mtlDescriptor)!
        self.samplerStates[descriptor] = state
        return state
    }
    
    public subscript(descriptor: DepthStencilDescriptor) -> MTLDepthStencilState {
        if let state = self.depthStates[descriptor] {
            return state
        }
        
        let mtlDescriptor = MTLDepthStencilDescriptor(descriptor)
        let state = self.device.makeDepthStencilState(descriptor: mtlDescriptor)!
        self.depthStates[descriptor] = state
        return state
    }
}

