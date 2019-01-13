//
//  Caches.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 24/12/17.
//

import SwiftFrameGraph
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
    
    struct RenderPipelineFunctionNames : Hashable {
        var vertexFunction : String
        var fragmentFunction : String?
    }
    
    let renderPipelineAccessQueue = DispatchQueue(label: "State Caches Render Access Queue")
    let computePipelineAccessQueue = DispatchQueue(label: "State Caches Compute Access Queue")
    
    private var functionCache = [FunctionCacheKey : MTLFunction]()
    private var computeStates = [String : [(ComputePipelineDescriptor, Bool, MTLComputePipelineState, MetalPipelineReflection)]]() // Bool meaning threadgroupSizeIsMultipleOfThreadExecutionWidth
    private(set) var currentThreadExecutionWidth : Int = 0
    
    private var renderStates = [RenderPipelineFunctionNames : [(MetalRenderPipelineDescriptor, MTLRenderPipelineState, MetalPipelineReflection)]]()
    
    private var depthStates = [(DepthStencilDescriptor, MTLDepthStencilState)]()
    private var samplerStates = [(SamplerDescriptor, MTLSamplerState)]()
    
    private var argumentEncoders = [ArgumentEncoderCacheKey : MTLArgumentEncoder]()
    
    public init(device: MTLDevice, libraryPath: String?) {
        self.device = device
        if let libraryPath = libraryPath {
            self.library = try! device.makeLibrary(filepath: libraryPath)
        } else {
            self.library = device.makeDefaultLibrary()!
        }
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
            guard let functionUnwrapped = self.library.makeFunction(name: name) else {
                fatalError("No Metal function exists with name \(name)")
            }
            function = functionUnwrapped
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
        
        let lookupKey = RenderPipelineFunctionNames(vertexFunction: descriptor.vertexFunction!, fragmentFunction: descriptor.fragmentFunction)
        
        if let possibleMatches = self.renderStates[lookupKey] {
            for (testDescriptor, state, _) in possibleMatches {
                if testDescriptor == metalDescriptor {
                    return state
                }
            }
        }
        
        let mtlDescriptor = MTLRenderPipelineDescriptor(metalDescriptor, stateCaches: self)
        
        var reflection : MTLRenderPipelineReflection? = nil
        let state = try! self.device.makeRenderPipelineState(descriptor: mtlDescriptor, options: [.argumentInfo, .bufferTypeInfo], reflection: &reflection)
        
        let pipelineReflection = MetalPipelineReflection(renderReflection: reflection!)
        
        self.renderStates[lookupKey, default: []].append((metalDescriptor, state, pipelineReflection))
        
        return state
        
    }
    
    public func reflection(for pipelineDescriptor: RenderPipelineDescriptor, renderTarget: RenderTargetDescriptor) -> MetalPipelineReflection {
        
        let lookupKey = RenderPipelineFunctionNames(vertexFunction: pipelineDescriptor.vertexFunction!, fragmentFunction: pipelineDescriptor.fragmentFunction)
        
        if let possibleMatches = self.renderStates[lookupKey] {
            for (testDescriptor, _, reflection) in possibleMatches {
                if testDescriptor.descriptor == pipelineDescriptor {
                    return reflection
                }
            }
        }
        
        let _ = self[pipelineDescriptor, renderTarget: renderTarget]
        return self.reflection(for: pipelineDescriptor, renderTarget: renderTarget)
    }
    
    public subscript(descriptor: ComputePipelineDescriptor, threadgroupSizeIsMultipleOfThreadExecutionWidth: Bool) -> MTLComputePipelineState {
        // Figure out whether the thread group size is always a multiple of the thread execution width and set the optimisation hint appropriately.
        
        if let possibleMatches = self.computeStates[descriptor.function] {
            for (testDescriptor, testThreadgroupMultiple, state, _) in possibleMatches {
                if testThreadgroupMultiple == threadgroupSizeIsMultipleOfThreadExecutionWidth && testDescriptor == descriptor {
                    return state
                }
            }
        }
        
        let mtlDescriptor = MTLComputePipelineDescriptor()
        mtlDescriptor.computeFunction = self.function(named: descriptor.function, functionConstants: descriptor.functionConstants)
        mtlDescriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = threadgroupSizeIsMultipleOfThreadExecutionWidth
        
        var reflection : MTLComputePipelineReflection? = nil
        let state = try! self.device.makeComputePipelineState(descriptor: mtlDescriptor, options: [.argumentInfo, .bufferTypeInfo], reflection: &reflection)
        
        let pipelineReflection = MetalPipelineReflection(computeReflection: reflection!)
        
        self.computeStates[descriptor.function, default: []].append((descriptor, threadgroupSizeIsMultipleOfThreadExecutionWidth, state, pipelineReflection))
        
        return state
    }
    
    public func reflection(for pipelineDescriptor: ComputePipelineDescriptor) -> (MetalPipelineReflection, Int) {
        if let possibleMatches = self.computeStates[pipelineDescriptor.function] {
            for (testDescriptor, _, state, reflection) in possibleMatches {
                if testDescriptor == pipelineDescriptor {
                    return (reflection, state.threadExecutionWidth)
                }
            }
        }
        
        let _ = self[pipelineDescriptor, false]
        return self.reflection(for: pipelineDescriptor)
    }
    
    public func renderPipelineReflection(descriptor: RenderPipelineDescriptor, renderTarget: RenderTargetDescriptor) -> MetalPipelineReflection {
        return self.reflection(for: descriptor, renderTarget: renderTarget)
    }
    
    public func computePipelineReflection(descriptor: ComputePipelineDescriptor) -> MetalPipelineReflection {
        let (reflection, currentThreadExecutionWidth) = self.reflection(for: descriptor)
        self.currentThreadExecutionWidth = currentThreadExecutionWidth
        return reflection
    }
    
    public subscript(descriptor: SamplerDescriptor) -> MTLSamplerState {
        if let (_, state) = self.samplerStates.first(where: { $0.0 == descriptor }) {
            return state
        }
        
        let mtlDescriptor = MTLSamplerDescriptor(descriptor)
        let state = self.device.makeSamplerState(descriptor: mtlDescriptor)!
        self.samplerStates.append((descriptor, state))
        
        return state
    }
    
    public subscript(descriptor: DepthStencilDescriptor) -> MTLDepthStencilState {
        if let (_, state) = self.depthStates.first(where: { $0.0 == descriptor }) {
            return state
        }
        
        let mtlDescriptor = MTLDepthStencilDescriptor(descriptor)
        let state = self.device.makeDepthStencilState(descriptor: mtlDescriptor)!
        self.depthStates.append((descriptor, state))
        
        return state
    }
}

