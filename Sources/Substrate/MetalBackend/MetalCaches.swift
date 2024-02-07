//
//  Caches.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 24/12/17.
//

#if canImport(Metal)

import Metal
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
    
    func function(for functionDescriptor: FunctionDescriptor) async throws -> MTLFunction {
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
            throw error
        }
    }
}

final class MetalRenderPipelineState: RenderPipelineState {
    let mtlState: MTLRenderPipelineState
    
    init(descriptor: RenderPipelineDescriptor, state: MTLRenderPipelineState, argumentBufferDescriptors: [ ResourceBindingPath: ArgumentBufferDescriptor]) {
        self.mtlState = state
        super.init(descriptor: descriptor, state: OpaquePointer(Unmanaged.passUnretained(state).toOpaque()), argumentBufferDescriptors: argumentBufferDescriptors)
    }
}

final class MetalComputePipelineState: ComputePipelineState {
    let mtlState: MTLComputePipelineState
    
    init(descriptor: ComputePipelineDescriptor, state: MTLComputePipelineState, argumentBufferDescriptors: [ ResourceBindingPath: ArgumentBufferDescriptor]) {
        self.mtlState = state
        super.init(descriptor: descriptor, state: OpaquePointer(Unmanaged.passUnretained(state).toOpaque()), argumentBufferDescriptors: argumentBufferDescriptors, threadExecutionWidth: state.threadExecutionWidth)
    }
}

final class MetalDepthStencilState: DepthStencilState {
    let mtlState: MTLDepthStencilState
    
    init(descriptor: DepthStencilDescriptor, state: MTLDepthStencilState) {
        self.mtlState = state
        super.init(descriptor: descriptor, state: OpaquePointer(Unmanaged.passUnretained(state).toOpaque()))
    }
}

final actor MetalRenderPipelineCache {
    let device: MTLDevice
    let functionCache: MetalFunctionCache
    private var renderStates = [RenderPipelineDescriptor : MetalRenderPipelineState]()
    private var renderReflection = [RenderPipelineDescriptor: MetalPipelineReflection]()
    private var renderStateTasks = [RenderPipelineDescriptor : Task<Void, Error>]()
    
    init(device: MTLDevice, functionCache: MetalFunctionCache) {
        self.device = device
        self.functionCache = functionCache
    }
    
    private func setState(_ state: MTLRenderPipelineState, reflection: MetalPipelineReflection, for descriptor: RenderPipelineDescriptor) {
        self.renderStates[descriptor] = MetalRenderPipelineState(descriptor: descriptor, state: state, argumentBufferDescriptors: reflection.argumentBufferDescriptors)
        if self.renderReflection[descriptor] == nil {
            self.renderReflection[descriptor] = reflection
        }
    }
    
    public func state(descriptor: RenderPipelineDescriptor) async throws -> RenderPipelineState {
        if let state = self.renderStates[descriptor] {
            return state
        }
        
        let renderStateTask: Task<Void, Error>
        if let task = self.renderStateTasks[descriptor] {
            renderStateTask = task
        } else {
            renderStateTask = Task.detached {
                switch descriptor._vertexProcessingDescriptor {
                case .vertex(let vertexPipelineDescriptor):
                    let mtlDescriptor = try await MTLRenderPipelineDescriptor(descriptor, vertexPipelineDescriptor: vertexPipelineDescriptor, functionCache: self.functionCache)
                    let (state, reflection) = try await self.device.makeRenderPipelineState(descriptor: mtlDescriptor, options: [.bufferTypeInfo])
                    
                    // TODO: can we retrieve the thread execution width for render pipelines?
                    let pipelineReflection = MetalPipelineReflection(threadExecutionWidth: 4, vertexFunction: mtlDescriptor.vertexFunction!, fragmentFunction: mtlDescriptor.fragmentFunction, renderState: state, renderReflection: reflection!)
                    await self.setState(state, reflection: pipelineReflection, for: descriptor)
                case .mesh(let meshPipelineDescriptor):
                    if #available(macOS 13.0, iOS 15.0, *) {
                        let mtlDescriptor = try await MTLMeshRenderPipelineDescriptor(descriptor, meshPipelineDescriptor: meshPipelineDescriptor, functionCache: self.functionCache)
                        let (state, reflection) = try await self.device.makeRenderPipelineState(descriptor: mtlDescriptor, options: [.bufferTypeInfo])
                        
                        // TODO: can we retrieve the thread execution width for render pipelines?
                        let pipelineReflection = MetalPipelineReflection(threadExecutionWidth: 4, objectFunction: mtlDescriptor.objectFunction!, meshFunction: mtlDescriptor.meshFunction!, fragmentFunction: mtlDescriptor.fragmentFunction, renderState: state, renderReflection: reflection!)
                        await self.setState(state, reflection: pipelineReflection, for: descriptor)
                    }
                }
            }
            
            self.renderStateTasks[descriptor] = renderStateTask
        }
        
        do {
            _ = try await renderStateTask.value
            return self.renderStates[descriptor]!
        } catch {
            print("MetalRenderGraph: Error creating render pipeline state for descriptor \(descriptor): \(error)")
            throw error
        }
    }
    
    public func reflection(descriptor pipelineDescriptor: RenderPipelineDescriptor) async -> MetalPipelineReflection? {
        if let reflection = self.renderReflection[pipelineDescriptor] {
            return reflection
        }
        
        do {
            let _ = try await self.state(descriptor: pipelineDescriptor)
            return await self.reflection(descriptor: pipelineDescriptor)
        } catch {
            return nil
        }
    }
    
}

final actor MetalComputePipelineCache {
    let device: MTLDevice
    let functionCache: MetalFunctionCache
    private var computeStates = [ComputePipelineDescriptor: MetalComputePipelineState]()
    private var computeReflection = [ComputePipelineDescriptor: MetalPipelineReflection]()
    private var computeStateTasks = [ComputePipelineDescriptor : Task<Void, Error>]()
    
    init(device: MTLDevice, functionCache: MetalFunctionCache) {
        self.device = device
        self.functionCache = functionCache
    }
    
    private func reflectionDescriptor(_ descriptor: ComputePipelineDescriptor) -> ComputePipelineDescriptor {
        var reflectionDescriptor = descriptor
        reflectionDescriptor.threadgroupSizeIsMultipleOfThreadExecutionWidth = false
        return reflectionDescriptor
    }
    
    private func setState(_ state: MTLComputePipelineState, reflection: MetalPipelineReflection, for descriptor: ComputePipelineDescriptor) {
        self.computeStates[descriptor] = MetalComputePipelineState(descriptor: descriptor, state: state, argumentBufferDescriptors: reflection.argumentBufferDescriptors)
        
        let reflectionDescriptor = self.reflectionDescriptor(descriptor)
        if self.computeReflection[reflectionDescriptor] == nil {
            self.computeReflection[reflectionDescriptor] = reflection
        }
    }
    
    nonisolated func createComputeState(descriptor: ComputePipelineDescriptor) async throws {
        let function = try await self.functionCache.function(for: descriptor.function)
        
        let mtlDescriptor = MTLComputePipelineDescriptor()
        mtlDescriptor.computeFunction = function
        mtlDescriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = descriptor.threadgroupSizeIsMultipleOfThreadExecutionWidth
        
        if !descriptor.linkedFunctions.isEmpty, #available(iOS 14.0, macOS 11.0, *) {
            var functions = [MTLFunction]()
            for functionDescriptor in descriptor.linkedFunctions {
                let function = try await self.functionCache.function(for: functionDescriptor)
                functions.append(function)
            }
            let linkedFunctions = MTLLinkedFunctions()
            linkedFunctions.functions = functions
            mtlDescriptor.linkedFunctions = linkedFunctions
        }
        
        var reflection: MTLAutoreleasedComputePipelineReflection? = nil
        let state = try self.device.makeComputePipelineState(descriptor: mtlDescriptor, options: [.bufferTypeInfo], reflection: &reflection)
        
        let pipelineReflection = MetalPipelineReflection(threadExecutionWidth: state.threadExecutionWidth, function: mtlDescriptor.computeFunction!, computeState: state, computeReflection: reflection!)
        await self.setState(state, reflection: pipelineReflection, for: descriptor)
    }
    
    public func state(descriptor: ComputePipelineDescriptor) async throws -> MetalComputePipelineState {
        if let state = self.computeStates[descriptor] {
            return state
        }
        
        let computeStateTask: Task<Void, Error>
        if let task = self.computeStateTasks[descriptor] {
            computeStateTask = task
        } else {
            computeStateTask = Task.detached {
                try await self.createComputeState(descriptor: descriptor)
            }
            self.computeStateTasks[descriptor] = computeStateTask
        }
        
        do {
            _ = try await computeStateTask.value
            return self.computeStates[descriptor]!
        } catch {
            print("MetalRenderGraph: Error creating compute pipeline state for descriptor \(descriptor): \(error)")
            throw error
        }
    }
    
    public func reflection(for pipelineDescriptor: ComputePipelineDescriptor) async -> MetalPipelineReflection? {
        let reflectionDescriptor = self.reflectionDescriptor(pipelineDescriptor)
        if let reflection = self.computeReflection[reflectionDescriptor] {
            return reflection
        }
        
        do {
            _ = try await self.state(descriptor: pipelineDescriptor)
            return await self.reflection(for: pipelineDescriptor)
        } catch {
            return nil
        }
    }
}

final actor MetalDepthStencilStateCache {
    struct RenderPipelineFunctionNames : Hashable {
        var vertexFunction : String
        var fragmentFunction : String
    }
    
    let device: MTLDevice
    let defaultDepthState : MTLDepthStencilState
    private var depthStates: [MetalDepthStencilState]
    
    init(device: MTLDevice) {
        self.device = device
        let defaultDepthDescriptor = DepthStencilDescriptor()
        let mtlDescriptor = MTLDepthStencilDescriptor(defaultDepthDescriptor)
        let defaultDepthState = self.device.makeDepthStencilState(descriptor: mtlDescriptor)!
        self.defaultDepthState = defaultDepthState
        self.depthStates = [.init(descriptor: defaultDepthDescriptor, state: defaultDepthState)]
    }
    
    public subscript(descriptor: DepthStencilDescriptor) -> DepthStencilState {
        if let state = self.depthStates.first(where: { $0.descriptor == descriptor }) {
            return state
        }
        
        let mtlDescriptor = MTLDepthStencilDescriptor(descriptor)
        let mtlState = self.device.makeDepthStencilState(descriptor: mtlDescriptor)!
        let state = MetalDepthStencilState(descriptor: descriptor, state: mtlState)
        self.depthStates.append(state)
        
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
        var descriptor = descriptor
        if descriptor.arguments.last?.arrayLength ?? 0 > 1 {
            descriptor.arguments[descriptor.arguments.count - 1].arrayLength = descriptor.arguments[descriptor.arguments.count - 1].arrayLength.roundedUpToPowerOfTwo // Reuse the same argument encoder for descriptors with various trailing array sizes.
        }
        return self.lock.withLock {
            if let encoder = self.cache[descriptor] {
                return encoder
            }
            
            let arguments = descriptor.argumentDescriptors
            let encoder = self.device.makeArgumentEncoder(arguments: arguments)!
            self.cache[descriptor] = encoder
            return encoder
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
                let defaultLibraryName: String
                #if os(macOS) || targetEnvironment(macCatalyst)
                defaultLibraryName = device.isAppleSiliconGPU ? "Library-macOSAppleSilicon.metallib" : "Library-macOS.metallib"
                #elseif os(iOS)
                #if targetEnvironment(simulator)
                defaultLibraryName = "Library-iOSSimulator.metallib"
                #else
                defaultLibraryName = "Library-iOS.metallib"
                #endif
                #elseif os(tvOS)
                #if targetEnvironment(simulator)
                defaultLibraryName = "Library-tvOSSimulator.metallib"
                #else
                defaultLibraryName = "Library-tvOS.metallib"
                #endif
                #elseif os(visionOS)
                #if targetEnvironment(simulator)
                defaultLibraryName = "Library-visionOSSimulator.metallib"
                #else
                defaultLibraryName = "Library-visionOS.metallib"
                #endif
                #endif
                libraryURL = libraryURL.appendingPathComponent(defaultLibraryName)
            }
            
            library = try! device.makeLibrary(URL: libraryURL)
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
    
    public func renderPipelineState(descriptor pipelineDescriptor: RenderPipelineDescriptor) async throws -> RenderPipelineState {
        return try await self.renderPipelineCache.state(descriptor: pipelineDescriptor)
    }
    
    public func computePipelineState(descriptor: ComputePipelineDescriptor) async throws -> ComputePipelineState {
        return try await self.computePipelineCache.state(descriptor: descriptor)
    }

    public func renderPipelineReflection(descriptor pipelineDescriptor: RenderPipelineDescriptor) async -> MetalPipelineReflection? {
        return await self.renderPipelineCache.reflection(descriptor: pipelineDescriptor)
    }
    
    public func computePipelineReflection(descriptor: ComputePipelineDescriptor) async -> MetalPipelineReflection? {
        return await self.computePipelineCache.reflection(for: descriptor)
    }
}

#endif // canImport(Metal)
