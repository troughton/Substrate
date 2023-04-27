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
    private var functionTasks = [FunctionDescriptor : Task<Void, Error>]()
    
    init(library: MTLLibrary) {
        self.library = library
    }
    
    private func setFunction(_ function: MTLFunction, for descriptor: FunctionDescriptor) {
        self.functionCache[descriptor] = function
    }
    
    func function(for functionDescriptor: FunctionDescriptor) async -> MTLFunction? {
        if let function = self.functionCache[functionDescriptor] {
            return function
        }
        
        let functionTask: Task<Void, Error>
        if let task = self.functionTasks[functionDescriptor] {
            functionTask = task
        } else {
            functionTask = Task.detached {
                let function = try await self.library.makeFunction(name: functionDescriptor.name, constantValues: functionDescriptor.constants.map { MTLFunctionConstantValues($0) } ?? MTLFunctionConstantValues())
                await self.setFunction(function, for: functionDescriptor)
            }
            self.functionTasks[functionDescriptor] = functionTask
        }
        
        do {
            _ = try await functionTask.value
            return self.functionCache[functionDescriptor]!
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
    private var renderStates = [MetalRenderPipelineDescriptor : MTLRenderPipelineState]()
    private var renderReflection = [RenderPipelineDescriptor: MetalPipelineReflection]()
    private var renderStateTasks = [MetalRenderPipelineDescriptor : Task<Void, Error>]()
    
    init(device: MTLDevice, functionCache: MetalFunctionCache) {
        self.device = device
        self.functionCache = functionCache
    }
    
    private func setState(_ state: MTLRenderPipelineState, reflection: MetalPipelineReflection, for descriptor: MetalRenderPipelineDescriptor) {
        self.renderStates[descriptor] = state
        if self.renderReflection[descriptor.descriptor] == nil {
            self.renderReflection[descriptor.descriptor] = reflection
        }
    }
    
    public func state(descriptor: RenderPipelineDescriptor, renderTarget renderTarget: RenderTargetDescriptor) async -> MTLRenderPipelineState? {
        let metalDescriptor = MetalRenderPipelineDescriptor(descriptor, renderTargetDescriptor: renderTarget)
        
        if let state = self.renderStates[metalDescriptor] {
            return state
        }
        
        guard let mtlDescriptor = await MTLRenderPipelineDescriptor(metalDescriptor, functionCache: self.functionCache) else {
            return nil
        }
        
        let renderStateTask: Task<Void, Error>
        if let task = self.renderStateTasks[metalDescriptor] {
            renderStateTask = task
        } else {
            renderStateTask = Task.detached {
                let (state, reflection) = try await self.device.makeRenderPipelineState(descriptor: mtlDescriptor, options: [.bufferTypeInfo])
                
                // TODO: can we retrieve the thread execution width for render pipelines?
                let pipelineReflection = MetalPipelineReflection(threadExecutionWidth: 4, vertexFunction: mtlDescriptor.vertexFunction!, fragmentFunction: mtlDescriptor.fragmentFunction, renderState: state, renderReflection: reflection!)
                await self.setState(state, reflection: pipelineReflection, for: metalDescriptor)
            }
            
            self.renderStateTasks[metalDescriptor] = renderStateTask
        }
        
        do {
            _ = try await renderStateTask.value
            return self.renderStates[metalDescriptor]
        } catch {
            print("MetalRenderGraph: Error creating render pipeline state for descriptor \(descriptor): \(error)")
            return nil
        }
    }
    
    public func reflection(descriptor pipelineDescriptor: RenderPipelineDescriptor, renderTarget: RenderTargetsDescriptor) async -> MetalPipelineReflection? {
        if let reflection = self.renderReflection[pipelineDescriptor] {
            return reflection
        }
        
        guard await self.state(descriptor: pipelineDescriptor, renderTarget: renderTarget) != nil else {
            return nil
        }
        
        return await self.reflection(descriptor: pipelineDescriptor, renderTarget: renderTarget)
    }
    
}

final actor MetalComputePipelineCache {
    struct CacheKey: Hashable {
        var descriptor: ComputePipelineDescriptor
        var threadgroupSizeIsMultipleOfThreadExecutionWidth: Bool
    }
    
    let device: MTLDevice
    let functionCache: MetalFunctionCache
    private var computeStates = [CacheKey: MTLComputePipelineState]()
    private var computeReflection = [ComputePipelineDescriptor: MetalPipelineReflection]()
    private var computeStateTasks = [CacheKey : Task<Void, Error>]()
    
    init(device: MTLDevice, functionCache: MetalFunctionCache) {
        self.device = device
        self.functionCache = functionCache
    }
    
    private func setState(_ state: MTLComputePipelineState, reflection: MetalPipelineReflection, for cacheKey: CacheKey) {
        self.computeStates[cacheKey] = state
        if self.computeReflection[cacheKey.descriptor] == nil {
            self.computeReflection[cacheKey.descriptor] = reflection
        }
    }
    
    @_optimize(none) @inline(never)
    nonisolated func createComputeState(cacheKey: CacheKey) async throws {
        let descriptor = cacheKey.descriptor
        guard let function = await self.functionCache.function(for: descriptor.function) else {
            return
        }
        
        let mtlDescriptor = MTLComputePipelineDescriptor()
        mtlDescriptor.computeFunction = function
        mtlDescriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = cacheKey.threadgroupSizeIsMultipleOfThreadExecutionWidth
        
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
        
        var reflection: MTLAutoreleasedComputePipelineReflection? = nil
        let state = try self.device.makeComputePipelineState(descriptor: mtlDescriptor, options: [.bufferTypeInfo], reflection: &reflection)
        
        let pipelineReflection = MetalPipelineReflection(threadExecutionWidth: state.threadExecutionWidth, function: mtlDescriptor.computeFunction!, computeState: state, computeReflection: reflection!)
        await self.setState(state, reflection: pipelineReflection, for: cacheKey)
    }
    
    public func state(descriptor: ComputePipelineDescriptor, threadgroupSizeIsMultipleOfThreadExecutionWidth: Bool = false) async -> MTLComputePipelineState? {
        // Figure out whether the thread group size is always a multiple of the thread execution width and set the optimisation hint appropriately.
        let cacheKey = CacheKey(descriptor: descriptor, threadgroupSizeIsMultipleOfThreadExecutionWidth: threadgroupSizeIsMultipleOfThreadExecutionWidth)
        
        if let state = self.computeStates[cacheKey] {
            return state
        }
        
        let computeStateTask: Task<Void, Error>
        if let task = self.computeStateTasks[cacheKey] {
            computeStateTask = task
        } else {
            computeStateTask = Task.detached {
                try await self.createComputeState(cacheKey: cacheKey)
            }
            self.computeStateTasks[cacheKey] = computeStateTask
        }
        
        do {
            _ = try await computeStateTask.value
            return self.computeStates[cacheKey]
        } catch {
            print("MetalRenderGraph: Error creating compute pipeline state for descriptor \(descriptor): \(error)")
            return nil
        }
    }
    
    public func reflection(for pipelineDescriptor: ComputePipelineDescriptor) async -> MetalPipelineReflection? {
        if let reflection = self.computeReflection[pipelineDescriptor] {
            return reflection
        }
        
        guard await self.state(descriptor: pipelineDescriptor) != nil else {
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
    private var cache: [ArgumentBufferDescriptor: MetalArgumentEncoder]
    let lock = SpinLock()
    
    init(device: MTLDevice) {
        self.device = device
        self.cache = [:]
    }
    
    deinit {
        self.lock.deinit()
    }
    
    public subscript(descriptor: ArgumentBufferDescriptor) -> MetalArgumentEncoder {
        var descriptor = descriptor
        if descriptor.arguments.last?.arrayLength ?? 0 > 1 {
            descriptor.arguments[descriptor.arguments.count - 1].arrayLength = descriptor.arguments[descriptor.arguments.count - 1].arrayLength.roundedUpToPowerOfTwo // Reuse the same argument encoder for descriptors with various trailing array sizes.
        }
        return self.lock.withLock {
            if let encoder = self.cache[descriptor] {
                return encoder
            }
            
            let arguments = descriptor.argumentDescriptors
            let encoder = self.device.makeArgumentEncoder(arguments: arguments)
            let bindingIndexCount = descriptor.arguments.reduce(0, { $0 + max($1.arrayLength, 1) })
            let maxBindingIndex = ((descriptor.arguments.last?.index ?? -1) + max(descriptor.arguments.last?.arrayLength ?? 1, 1)) - 1
            let wrappedEncoder = MetalArgumentEncoder(encoder: encoder!, bindingIndexCount: bindingIndexCount, maxBindingIndex: maxBindingIndex)
            self.cache[descriptor] = wrappedEncoder
            return wrappedEncoder
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

    public func renderPipelineReflection(descriptor pipelineDescriptor: RenderPipelineDescriptor, renderTarget: RenderTargetsDescriptor) async -> MetalPipelineReflection? {
        return await self.renderPipelineCache.reflection(descriptor: pipelineDescriptor, renderTarget: renderTarget)
    }
    
    public func computePipelineReflection(descriptor: ComputePipelineDescriptor) async -> MetalPipelineReflection? {
        return await self.computePipelineCache.reflection(for: descriptor)
    }
}

#endif // canImport(Metal)
