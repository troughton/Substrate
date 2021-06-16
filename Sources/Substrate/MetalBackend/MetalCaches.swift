//
//  Caches.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 24/12/17.
//

#if canImport(Metal)

import Metal
import SubstrateUtilities

final class MetalStateCaches {
    
    let device : MTLDevice
    var library : MTLLibrary
    
    var libraryURL : URL?
    var loadedLibraryModificationDate : Date = .distantPast
    
    struct FunctionCacheKey : Hashable {
        var name : String
        var constants : FunctionConstants?
    }
    
    struct RenderPipelineFunctionNames : Hashable {
        var vertexFunction : String
        var fragmentFunction : String
    }
    
    var functionCacheAccessLock = ReaderWriterLock()
    var renderPipelineAccessLock = ReaderWriterLock()
    var computePipelineAccessLock = ReaderWriterLock()
    
    private var functionCache = [FunctionDescriptor : MTLFunction]()
    private var computeStates = [String : [(ComputePipelineDescriptor, Bool, MTLComputePipelineState, MetalPipelineReflection)]]() // Bool meaning threadgroupSizeIsMultipleOfThreadExecutionWidth
    
    private var renderStates = [RenderPipelineFunctionNames : [(MetalRenderPipelineDescriptor, MTLRenderPipelineState, MetalPipelineReflection)]]()
    
    let defaultDepthState : MTLDepthStencilState
    private var depthStates = [(DepthStencilDescriptor, MTLDepthStencilState)]()
    
    private var visibleFunctionTables = [ObjectIdentifier : [([FunctionDescriptor?], MTLResource)]]() // [MTLComputePipelineState : [([FunctionDescriptor?], MTLVisibleFunctionTable)]]
    private var intersectionFunctionTables = [ObjectIdentifier : [(IntersectionFunctionTableDescriptor, MTLResource)]]() // [MTLComputePipelineState : [([FunctionDescriptor?], MTLVisibleFunctionTable)]]
    
    public init(device: MTLDevice, libraryPath: String?) {
        self.device = device
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
            
            self.library = try! device.makeLibrary(filepath: libraryURL.path)
            self.libraryURL = libraryURL
            self.loadedLibraryModificationDate = try! libraryURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!
        } else {
            self.library = device.makeDefaultLibrary()!
        }
        
        let defaultDepthDescriptor = DepthStencilDescriptor()
        let mtlDescriptor = MTLDepthStencilDescriptor(defaultDepthDescriptor)
        self.defaultDepthState = self.device.makeDepthStencilState(descriptor: mtlDescriptor)!
        self.depthStates.append((defaultDepthDescriptor, defaultDepthState))
    }
    
    func checkForLibraryReload() {
        self.libraryURL?.removeCachedResourceValue(forKey: .contentModificationDateKey)
        
        guard let libraryURL = self.libraryURL else { return }
        if FileManager.default.fileExists(atPath: libraryURL.path),
           let currentModificationDate = try? libraryURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           currentModificationDate > self.loadedLibraryModificationDate {
            
            for queue in QueueRegistry.allQueues {
                queue.waitForCommand(queue.lastSubmittedCommand) // Wait for all commands to finish on all queues.
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
            
            self.renderPipelineAccessLock.acquireWriteAccess()
            defer { self.renderPipelineAccessLock.releaseWriteAccess() }
            self.computePipelineAccessLock.acquireWriteAccess()
            defer { self.computePipelineAccessLock.releaseWriteAccess() }
            
            self.library = library
            
            self.functionCache.removeAll(keepingCapacity: true)
            self.computeStates.removeAll(keepingCapacity: true)
            self.renderStates.removeAll(keepingCapacity: true)
            self.visibleFunctionTables.removeAll(keepingCapacity: true)
            
            self.loadedLibraryModificationDate = currentModificationDate
        }
    }
    
    func function(for functionDescriptor: FunctionDescriptor) -> MTLFunction? {
        self.functionCacheAccessLock.acquireReadAccess()
        if let function = self.functionCache[functionDescriptor] {
            self.functionCacheAccessLock.releaseReadAccess()
            return function
        }
        
        do {
            let function = try self.library.makeFunction(name: functionDescriptor.name, constantValues: functionDescriptor.constants.map { MTLFunctionConstantValues($0) } ?? MTLFunctionConstantValues())
                       
            self.functionCacheAccessLock.transformReadToWriteAccess()
            self.functionCache[functionDescriptor] = function
            self.functionCacheAccessLock.releaseWriteAccess()
            return function
        } catch {
            self.functionCacheAccessLock.releaseReadAccess()
            print("MetalRenderGraph: Error creating function named \(functionDescriptor.name)\(functionDescriptor.constants.map { " with constants \($0)" } ?? ""): \(error)")
            return nil
        }
    }
    
    public subscript(descriptor: RenderPipelineDescriptor, renderTarget renderTarget: RenderTargetDescriptor) -> MTLRenderPipelineState? {
        let metalDescriptor = MetalRenderPipelineDescriptor(descriptor, renderTargetDescriptor: renderTarget)
        
        let lookupKey = RenderPipelineFunctionNames(vertexFunction: descriptor.vertexFunction.name, fragmentFunction: descriptor.fragmentFunction.name)
        
        if let possibleMatches = self.renderStates[lookupKey] {
            for (testDescriptor, state, _) in possibleMatches {
                if testDescriptor == metalDescriptor {
                    return state
                }
            }
        }
        
        guard let mtlDescriptor = MTLRenderPipelineDescriptor(metalDescriptor, stateCaches: self) else {
            return nil
        }
        
        var reflection : MTLRenderPipelineReflection? = nil
        do {
            let state = try self.device.makeRenderPipelineState(descriptor: mtlDescriptor, options: [.argumentInfo, .bufferTypeInfo], reflection: &reflection)
            
            // TODO: can we retrieve the thread execution width for render pipelines?
            let pipelineReflection = MetalPipelineReflection(threadExecutionWidth: 4, vertexFunction: mtlDescriptor.vertexFunction!, fragmentFunction: mtlDescriptor.fragmentFunction, renderReflection: reflection!)
            
            self.renderStates[lookupKey, default: []].append((metalDescriptor, state, pipelineReflection))
            
            return state
        } catch {
            print("MetalRenderGraph: Error creating render pipeline state for descriptor \(descriptor): \(error)")
            return nil
        }
    }
    
    public func reflection(descriptor pipelineDescriptor: RenderPipelineDescriptor, renderTarget: RenderTargetDescriptor) -> MetalPipelineReflection? {
        
        let lookupKey = RenderPipelineFunctionNames(vertexFunction: pipelineDescriptor.vertexFunction.name, fragmentFunction: pipelineDescriptor.fragmentFunction.name)
        
        self.renderPipelineAccessLock.acquireReadAccess()
        if let possibleMatches = self.renderStates[lookupKey] {
            for (testDescriptor, _, reflection) in possibleMatches {
                if testDescriptor.descriptor == pipelineDescriptor {
                    self.renderPipelineAccessLock.releaseReadAccess()
                    return reflection
                }
            }
        }
        
        self.renderPipelineAccessLock.transformReadToWriteAccess()
        
        guard self[pipelineDescriptor, renderTarget: renderTarget] != nil else {
            self.renderPipelineAccessLock.releaseWriteAccess()
            return nil
        }
        
        self.renderPipelineAccessLock.releaseWriteAccess()
        return self.reflection(descriptor: pipelineDescriptor, renderTarget: renderTarget)
    }
    
    public subscript(descriptor: ComputePipelineDescriptor, threadgroupSizeIsMultipleOfThreadExecutionWidth: Bool) -> MTLComputePipelineState? {
        // Figure out whether the thread group size is always a multiple of the thread execution width and set the optimisation hint appropriately.
        
        if let possibleMatches = self.computeStates[descriptor.function.name] {
            for (testDescriptor, testThreadgroupMultiple, state, _) in possibleMatches {
                if testThreadgroupMultiple == threadgroupSizeIsMultipleOfThreadExecutionWidth && testDescriptor == descriptor {
                    return state
                }
            }
        }
        
        guard let function = self.function(for: descriptor.function) else {
            return nil
        }
        
        let mtlDescriptor = MTLComputePipelineDescriptor()
        mtlDescriptor.computeFunction = function
        mtlDescriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = threadgroupSizeIsMultipleOfThreadExecutionWidth
        
        if !descriptor.linkedFunctions.isEmpty, #available(iOS 14.0, macOS 11.0, *) {
            let linkedFunctions = MTLLinkedFunctions()
            linkedFunctions.functions = descriptor.linkedFunctions.compactMap { // We print an error in function(for:)
                self.function(for: $0)
            }
            mtlDescriptor.linkedFunctions = linkedFunctions
        }
        
        var reflection : MTLComputePipelineReflection? = nil
        do {
            let state = try self.device.makeComputePipelineState(descriptor: mtlDescriptor, options: [.argumentInfo, .bufferTypeInfo], reflection: &reflection)
            
            let pipelineReflection = MetalPipelineReflection(threadExecutionWidth: state.threadExecutionWidth, function: mtlDescriptor.computeFunction!, computeReflection: reflection!)
            
            self.computeStates[descriptor.function.name, default: []].append((descriptor, threadgroupSizeIsMultipleOfThreadExecutionWidth, state, pipelineReflection))
            
            return state
        } catch {
            print("MetalRenderGraph: Error creating compute pipeline state for descriptor \(descriptor): \(error)")
            return nil
        }
    }
    
    public func reflection(for pipelineDescriptor: ComputePipelineDescriptor) -> (MetalPipelineReflection, Int)? {
        self.computePipelineAccessLock.acquireReadAccess()
        if let possibleMatches = self.computeStates[pipelineDescriptor.function.name] {
            for (testDescriptor, _, state, reflection) in possibleMatches {
                if testDescriptor == pipelineDescriptor {
                    self.computePipelineAccessLock.releaseReadAccess()
                    return (reflection, state.threadExecutionWidth)
                }
            }
        }
        
        self.computePipelineAccessLock.transformReadToWriteAccess()
        guard self[pipelineDescriptor, false] != nil else {
            self.computePipelineAccessLock.releaseWriteAccess()
            return nil
        }
        self.computePipelineAccessLock.releaseWriteAccess()
        return self.reflection(for: pipelineDescriptor)
    }

    public func renderPipelineReflection(descriptor pipelineDescriptor: RenderPipelineDescriptor, renderTarget: RenderTargetDescriptor) -> MetalPipelineReflection? {
        return self.reflection(descriptor: pipelineDescriptor, renderTarget: renderTarget)
    }
    
    public func computePipelineReflection(descriptor: ComputePipelineDescriptor) -> MetalPipelineReflection? {
        return self.reflection(for: descriptor)?.0
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
    
    @available(macOS 11.0, iOS 14.0, *)
    public subscript(visibleFunctionTableFor functionTableDescriptor: [FunctionDescriptor?], computePipelineState computePipelineState: MTLComputePipelineState) -> MTLVisibleFunctionTable {
        if let table = self.visibleFunctionTables[ObjectIdentifier(computePipelineState)]?.first(where: { $0.0 == functionTableDescriptor })?.1 {
            return (table as! MTLVisibleFunctionTable)
        }
        
        let mtlDescriptor = MTLVisibleFunctionTableDescriptor()
        mtlDescriptor.functionCount = functionTableDescriptor.drop(while: { $0 == nil }).count
        
        let functionTable = computePipelineState.makeVisibleFunctionTable(descriptor: mtlDescriptor)!
        for i in 0..<mtlDescriptor.functionCount {
            guard let function = functionTableDescriptor[i], let mtlFunction = self.function(for: function) else { continue }
            functionTable.setFunction(computePipelineState.functionHandle(function: mtlFunction), index: i)
        }
        
        self.visibleFunctionTables[ObjectIdentifier(computePipelineState), default: []].append((functionTableDescriptor, functionTable))
        return functionTable
    }
}

#endif // canImport(Metal)
