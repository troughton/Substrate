//
//  Caches.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 24/12/17.
//

#if canImport(Metal)

@preconcurrency import Metal
import SubstrateUtilities

final actor MetalFunctionCache {
    let library: MTLLibrary
    private var functionCache = [FunctionDescriptor : MTLFunction]()
    
    init(library: MTLLibrary) {
        self.library = library
    }
    
    func function(for functionDescriptor: FunctionDescriptor) async -> MTLFunction? {
        if let function = self.functionCache[functionDescriptor] {
            return function
        }
        
        do {
            let function = try await self.library.makeFunction(name: functionDescriptor.name, constantValues: functionDescriptor.constants.map { MTLFunctionConstantValues($0) } ?? MTLFunctionConstantValues())
                       
            self.functionCache[functionDescriptor] = function
            return function
        } catch {
            print("MetalRenderGraph: Error creating function named \(functionDescriptor.name)\(functionDescriptor.constants.map { " with constants \($0)" } ?? ""): \(error)")
            return nil
        }
    }
}

final actor MetalRenderPipelineCache {
    struct RenderPipelineFunctionNames : Hashable {
        var vertexFunction : String
        var fragmentFunction : String
    }
    
    let device: MTLDevice
    let functionCache: MetalFunctionCache
    private var renderStates = [RenderPipelineFunctionNames : [(MetalRenderPipelineDescriptor, MTLRenderPipelineState, MetalPipelineReflection)]]()
    
    init(device: MTLDevice, functionCache: MetalFunctionCache) {
        self.device = device
        self.functionCache = functionCache
    }
    
    public subscript(descriptor: RenderPipelineDescriptor, renderTarget renderTarget: RenderTargetDescriptor) -> MTLRenderPipelineState? {
        get async {
            let metalDescriptor = MetalRenderPipelineDescriptor(descriptor, renderTargetsDescriptor: renderTarget)
            
            let lookupKey = RenderPipelineFunctionNames(vertexFunction: descriptor.vertexFunction.name, fragmentFunction: descriptor.fragmentFunction.name)
            
            if let possibleMatches = self.renderStates[lookupKey] {
                for (testDescriptor, state, _) in possibleMatches {
                    if testDescriptor == metalDescriptor {
                        return state
                    }
                }
            }
            
            guard let mtlDescriptor = await MTLRenderPipelineDescriptor(metalDescriptor, functionCache: self.functionCache) else {
                return nil
            }
            
            do {
                let (state, reflection) = try await self.device.makeRenderPipelineState(descriptor: mtlDescriptor, options: [.bufferTypeInfo])
                
                // TODO: can we retrieve the thread execution width for render pipelines?
                let pipelineReflection = MetalPipelineReflection(threadExecutionWidth: 4, vertexFunction: mtlDescriptor.vertexFunction!, fragmentFunction: mtlDescriptor.fragmentFunction, renderState: state, renderReflection: reflection!)
                
                self.renderStates[lookupKey, default: []].append((metalDescriptor, state, pipelineReflection))
                
                return state
            } catch {
                print("MetalRenderGraph: Error creating render pipeline state for descriptor \(descriptor): \(error)")
                return nil
            }
        }
    }
    
    public func reflection(descriptor pipelineDescriptor: RenderPipelineDescriptor, renderTarget: RenderTargetDescriptor) async -> MetalPipelineReflection? {
        let lookupKey = RenderPipelineFunctionNames(vertexFunction: pipelineDescriptor.vertexFunction.name, fragmentFunction: pipelineDescriptor.fragmentFunction.name)
        
        if let possibleMatches = self.renderStates[lookupKey] {
            for (testDescriptor, _, reflection) in possibleMatches {
                if testDescriptor.descriptor == pipelineDescriptor {
                    return reflection
                }
            }
        }
        
        guard await self[pipelineDescriptor, renderTarget: renderTarget] != nil else {
            return nil
        }
        
        return await self.reflection(descriptor: pipelineDescriptor, renderTarget: renderTarget)
    }
    
}

final actor MetalComputePipelineCache {
    
    let device: MTLDevice
    let functionCache: MetalFunctionCache
    private var computeStates = [String : [(ComputePipelineDescriptor, Bool, MTLComputePipelineState, MetalPipelineReflection)]]() // Bool meaning threadgroupSizeIsMultipleOfThreadExecutionWidth
    
    init(device: MTLDevice, functionCache: MetalFunctionCache) {
        self.device = device
        self.functionCache = functionCache
    }
    
    public subscript(descriptor: ComputePipelineDescriptor, threadgroupSizeIsMultipleOfThreadExecutionWidth: Bool) -> MTLComputePipelineState? {
        get async {
            // Figure out whether the thread group size is always a multiple of the thread execution width and set the optimisation hint appropriately.
            
            if let possibleMatches = self.computeStates[descriptor.function.name] {
                for (testDescriptor, testThreadgroupMultiple, state, _) in possibleMatches {
                    if testThreadgroupMultiple == threadgroupSizeIsMultipleOfThreadExecutionWidth && testDescriptor == descriptor {
                        return state
                    }
                }
            }
            
            guard let function = await self.functionCache.function(for: descriptor.function) else {
                return nil
            }
            
            let mtlDescriptor = MTLComputePipelineDescriptor()
            mtlDescriptor.computeFunction = function
            mtlDescriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = threadgroupSizeIsMultipleOfThreadExecutionWidth
            
            if !descriptor.linkedFunctions.isEmpty, #available(iOS 14.0, macOS 11.0, *) {
                var functions = [MTLFunction]()
                for functionDescriptor in descriptor.linkedFunctions {
                    if let function = await self.functionCache.function(for: functionDescriptor) {
                        functions.append(function)
                    }
                }
                let linkedFunctions = MTLLinkedFunctions()
                linkedFunctions.functions = functions
                mtlDescriptor.linkedFunctions = linkedFunctions
            }
            
            do {
                let (state, reflection) = try await self.device.makeComputePipelineState(descriptor: mtlDescriptor, options: [.bufferTypeInfo])
                
                let pipelineReflection = MetalPipelineReflection(threadExecutionWidth: state.threadExecutionWidth, function: mtlDescriptor.computeFunction!, computeState: state, computeReflection: reflection!)
                
                self.computeStates[descriptor.function.name, default: []].append((descriptor, threadgroupSizeIsMultipleOfThreadExecutionWidth, state, pipelineReflection))
                
                return state
            } catch {
                print("MetalRenderGraph: Error creating compute pipeline state for descriptor \(descriptor): \(error)")
                return nil
            }
        }
    }
    
    public func reflection(for pipelineDescriptor: ComputePipelineDescriptor) async -> (MetalPipelineReflection, Int)? {
        if let possibleMatches = self.computeStates[pipelineDescriptor.function.name] {
            for (testDescriptor, _, state, reflection) in possibleMatches {
                if testDescriptor == pipelineDescriptor {
                    return (reflection, state.threadExecutionWidth)
                }
            }
        }
        
        guard await self[pipelineDescriptor, false] != nil else {
            return nil
        }
        return await self.reflection(for: pipelineDescriptor)
    }
}

final actor MetalDepthStencilStateCache {
    struct RenderPipelineFunctionNames : Hashable {
        var vertexFunction : String
        var fragmentFunction : String
    }
    
    let device: MTLDevice
    let defaultDepthState : MTLDepthStencilState
    private var depthStates: [(DepthStencilDescriptor, MTLDepthStencilState)]
    
    init(device: MTLDevice) {
        self.device = device
        let defaultDepthDescriptor = DepthStencilDescriptor()
        let mtlDescriptor = MTLDepthStencilDescriptor(defaultDepthDescriptor)
        let defaultDepthState = self.device.makeDepthStencilState(descriptor: mtlDescriptor)!
        self.defaultDepthState = defaultDepthState
        self.depthStates = [(defaultDepthDescriptor, defaultDepthState)]
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

final class MetalArgumentEncoderCache {
    let device: MTLDevice
    private var cache: [ArgumentBufferDescriptor: MTLArgumentEncoder]
    let lock = SpinLock()
    
    init(device: MTLDevice) {
        self.device = device
        self.cache = [:]
    }
    
    deinit {
        self.lock.deinit()
    }
    
    public subscript(descriptor: ArgumentBufferDescriptor) -> MTLArgumentEncoder {
        return self.lock.withLock {
            if let encoder = self.cache[descriptor] {
                return encoder
            }
            
            let arguments = descriptor.argumentDescriptors
            let encoder = self.device.makeArgumentEncoder(arguments: arguments)
            self.cache[descriptor] = encoder
            return encoder!
        }
    }
}

final class MetalStateCaches {
    let device : MTLDevice
    
    var libraryURL : URL?
    var loadedLibraryModificationDate : Date = .distantPast
    
    var functionCache: MetalFunctionCache
    var renderPipelineCache: MetalRenderPipelineCache
    var computePipelineCache: MetalComputePipelineCache
    let depthStencilCache: MetalDepthStencilStateCache
    let argumentEncoderCache: MetalArgumentEncoderCache
    
    public init(device: MTLDevice, libraryPath: String?) {
        self.device = device
        let library: MTLLibrary
        if let libraryPath = libraryPath {
            var libraryURL = URL(fileURLWithPath: libraryPath)
            
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: libraryPath, isDirectory: &isDirectory), isDirectory.boolValue {
                #if os(macOS) || targetEnvironment(macCatalyst)
                libraryURL = libraryURL.appendingPathComponent(device.isAppleSiliconGPU ? "Library-macOSAppleSilicon.metallib" : "Library-macOS.metallib")
                #else
                libraryURL = libraryURL.appendingPathComponent("Library-iOS.metallib")
                #endif
            }
            
            library = try! device.makeLibrary(filepath: libraryURL.path)
            self.libraryURL = libraryURL
            self.loadedLibraryModificationDate = try! libraryURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!
        } else {
            library = device.makeDefaultLibrary()!
        }
        
        self.functionCache = MetalFunctionCache(library: library)
        self.renderPipelineCache = .init(device: self.device, functionCache: functionCache)
        self.computePipelineCache = .init(device: self.device, functionCache: functionCache)
        self.depthStencilCache = .init(device: self.device)
        self.argumentEncoderCache = .init(device: self.device)
    }
    
    func checkForLibraryReload() async {
        self.libraryURL?.removeCachedResourceValue(forKey: .contentModificationDateKey)
        
        guard let libraryURL = self.libraryURL else { return }
        if FileManager.default.fileExists(atPath: libraryURL.path),
           let currentModificationDate = try? libraryURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           currentModificationDate > self.loadedLibraryModificationDate {
            
            for queue in QueueRegistry.allQueues {
                await queue.waitForCommandCompletion(queue.lastSubmittedCommand) // Wait for all commands to finish on all queues.
            }
            
            // Metal won't pick up the changes if we use the makeLibrary(filePath:) initialiser,
            // so we have to load into a DispatchData instead.
            guard let data = try? Data(contentsOf: libraryURL) else {
                return
            }
            
            guard let library = data.withUnsafeBytes({ bytes -> MTLLibrary? in
                let dispatchData = DispatchData(bytes: bytes)
                return try? device.makeLibrary(data: dispatchData as __DispatchData)
            }) else { return }
            
            
            self.functionCache = MetalFunctionCache(library: library)
            self.renderPipelineCache = .init(device: self.device, functionCache: functionCache)
            self.computePipelineCache = .init(device: self.device, functionCache: functionCache)
            
            VisibleFunctionTableRegistry.instance.markAllAsUninitialised()
            IntersectionFunctionTableRegistry.instance.markAllAsUninitialised()
            
            self.loadedLibraryModificationDate = currentModificationDate
        }
    }

    public func renderPipelineReflection(descriptor pipelineDescriptor: RenderPipelineDescriptor, renderTarget: RenderTargetDescriptor) async -> MetalPipelineReflection? {
        return await self.renderPipelineCache.reflection(descriptor: pipelineDescriptor, renderTarget: renderTarget)
    }
    
    public func computePipelineReflection(descriptor: ComputePipelineDescriptor) async -> MetalPipelineReflection? {
        return await self.computePipelineCache.reflection(for: descriptor)?.0
    }
}

#endif // canImport(Metal)
