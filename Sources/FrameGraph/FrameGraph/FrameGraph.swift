//
//  FrameGraph.swift
//  SwiftFrameGraph
//
//  Created by Thomas Roughton on 17/03/17.
//
//

import Foundation
import FrameGraphUtilities

public protocol RenderPass : class {
    var name : String { get }
    
    var readResources : [Resource] { get }
    var writtenResources : [Resource] { get }
    
    var passType : RenderPassType { get }
}

extension RenderPass {
    public var name: String {
        return String(reflecting: type(of: self))
    }
    
    public var readResources : [Resource] { return [] }
    public var writtenResources : [Resource] { return [] }
}

protocol ReflectableRenderPass {
    associatedtype Reflection : RenderPassReflection
}

public protocol DrawRenderPass : RenderPass {
    var renderTargetDescriptor : RenderTargetDescriptor { get }
    func execute(renderCommandEncoder: RenderCommandEncoder)
}

extension DrawRenderPass {
    public var passType : RenderPassType {
        return .draw
    }
}

public protocol ComputeRenderPass : RenderPass {
    func execute(computeCommandEncoder: ComputeCommandEncoder)
}

extension ComputeRenderPass {
    public var passType : RenderPassType {
        return .compute
    }
}

public protocol CPURenderPass : RenderPass {
    func execute()
}

extension CPURenderPass {
    public var passType : RenderPassType {
        return .cpu
    }
}

public protocol BlitRenderPass : RenderPass {
    func execute(blitCommandEncoder: BlitCommandEncoder)
}

extension BlitRenderPass {
    public var passType : RenderPassType {
        return .blit
    }
}

public protocol ExternalRenderPass : RenderPass {
    func execute(externalCommandEncoder: ExternalCommandEncoder)
}

extension ExternalRenderPass {
    public var passType : RenderPassType {
        return .external
    }
}

public protocol ReflectableDrawRenderPass : DrawRenderPass {
    
    associatedtype Reflection : RenderPassReflection
    func execute(renderCommandEncoder: TypedRenderCommandEncoder<Reflection>)
}

extension ReflectableDrawRenderPass {
    @inlinable
    public func execute(renderCommandEncoder: RenderCommandEncoder) {
        return self.execute(renderCommandEncoder: TypedRenderCommandEncoder(encoder: renderCommandEncoder))
    }
}

public protocol ReflectableComputeRenderPass : ComputeRenderPass {
    associatedtype Reflection : RenderPassReflection
    func execute(computeCommandEncoder: TypedComputeCommandEncoder<Reflection>)
}

extension ReflectableComputeRenderPass {
    @inlinable
    public func execute(computeCommandEncoder: ComputeCommandEncoder) {
        return self.execute(computeCommandEncoder: TypedComputeCommandEncoder(encoder: computeCommandEncoder))
    }
}

final class CallbackDrawRenderPass : DrawRenderPass {
    public let name : String
    public let renderTargetDescriptor: RenderTargetDescriptor
    public let executeFunc : (RenderCommandEncoder) -> Void
    
    public init(name: String, descriptor: RenderTargetDescriptor, execute: @escaping (RenderCommandEncoder) -> Void) {
        self.name = name
        self.renderTargetDescriptor = descriptor
        self.executeFunc = execute
    }
    
    public func execute(renderCommandEncoder: RenderCommandEncoder) {
        self.executeFunc(renderCommandEncoder)
    }
}

final class ReflectableCallbackDrawRenderPass<R : RenderPassReflection> : ReflectableDrawRenderPass {
    public let name : String
    public let renderTargetDescriptor: RenderTargetDescriptor
    public let executeFunc : (TypedRenderCommandEncoder<R>) -> Void
    
    public init(name: String, descriptor: RenderTargetDescriptor, reflection: R.Type, execute: @escaping (TypedRenderCommandEncoder<R>) -> Void) {
        self.name = name
        self.renderTargetDescriptor = descriptor
        self.executeFunc = execute
    }
    
    public func execute(renderCommandEncoder: TypedRenderCommandEncoder<R>) {
        self.executeFunc(renderCommandEncoder)
    }
}

final class CallbackComputeRenderPass : ComputeRenderPass {
    public let name : String
    public let executeFunc : (ComputeCommandEncoder) -> Void
    
    public init(name: String, execute: @escaping (ComputeCommandEncoder) -> Void) {
        self.name = name
        self.executeFunc = execute
    }
    
    public func execute(computeCommandEncoder: ComputeCommandEncoder) {
        self.executeFunc(computeCommandEncoder)
    }
}

final class ReflectableCallbackComputeRenderPass<R : RenderPassReflection> : ReflectableComputeRenderPass {
    public let name : String
    public let executeFunc : (TypedComputeCommandEncoder<R>) -> Void
    
    public init(name: String, reflection: R.Type, execute: @escaping (TypedComputeCommandEncoder<R>) -> Void) {
        self.name = name
        self.executeFunc = execute
    }
    
    public func execute(computeCommandEncoder: TypedComputeCommandEncoder<R>) {
        self.executeFunc(computeCommandEncoder)
    }
}

final class CallbackCPURenderPass : CPURenderPass {
    public let name : String
    public let executeFunc : () -> Void
    
    public init(name: String, execute: @escaping () -> Void) {
        self.name = name
        self.executeFunc = execute
    }
    
    public func execute() {
        self.executeFunc()
    }
}

final class CallbackBlitRenderPass : BlitRenderPass {
    public let name : String
    public let executeFunc : (BlitCommandEncoder) -> Void
    
    public init(name: String, execute: @escaping (BlitCommandEncoder) -> Void) {
        self.name = name
        self.executeFunc = execute
    }
    
    public func execute(blitCommandEncoder: BlitCommandEncoder) {
        self.executeFunc(blitCommandEncoder)
    }
}

final class CallbackExternalRenderPass : ExternalRenderPass {
    public let name : String
    public let executeFunc : (ExternalCommandEncoder) -> Void
    
    public init(name: String, execute: @escaping (ExternalCommandEncoder) -> Void) {
        self.name = name
        self.executeFunc = execute
    }
    
    public func execute(externalCommandEncoder: ExternalCommandEncoder) {
        self.executeFunc(externalCommandEncoder)
    }
}

public enum RenderPassType {
    case cpu
    case draw
    case compute
    case blit
    case external // Using things like Metal Performance Shaders.
}

public final class RenderPassRecord {
    public let pass : RenderPass
    public var commands : ExpandingBuffer<FrameGraphCommand>! = nil
    public /* internal(set) */ var commandRange : Range<Int>?
    public /* internal(set) */ var passIndex : Int
    public /* internal(set) */ var isActive : Bool
    public /* internal(set) */ var usesWindowTexture : Bool = false
    
    init(pass: RenderPass, passIndex: Int) {
        self.pass = pass
        self.passIndex = passIndex
        self.commandRange = nil
        self.isActive = false
    }
}

public enum DependencyType {
    /// No dependency
    case none
    /// If the dependency is active, it must be executed first
    case ordering
    /// The dependency must always be executed
    case execution
    //    /// There is a transitive dependency by way of another pass
    //    case transitive
}

public protocol FrameGraphContext : class {
    
}

// _FrameGraphContext is an internal-only protocol to ensure dispatch gets optimised in whole-module optimisation mode.
protocol _FrameGraphContext : FrameGraphContext {
    var transientRegistryIndex : Int { get }
    var accessSemaphore : Semaphore { get }
    var frameGraphQueue: Queue { get }
    func beginFrameResourceAccess() // Access is ended when a frameGraph is submitted.
    func executeFrameGraph(passes: [RenderPassRecord], dependencyTable: DependencyTable<DependencyType>, resourceUsages: ResourceUsages, completion: @escaping () -> Void)
}

public enum FrameGraphTagType : UInt64 {
    static let frameGraphTag : UInt64 = 0xf9322463 // CRC-32 of "FrameGraph"
    
    /// Scratch data that exists only while a render pass is being executed.
    case renderPassExecution
    
    /// Data that exists while the FrameGraph is being compiled.
    case frameGraphCompilation
    
    /// Data that exists until the FrameGraph has been executed on the backend.
    case frameGraphExecution
    
    /// Resource usage nodes – exists until the FrameGraph has been executed on the backend.
    case resourceUsageNodes
    
    public static func renderPassExecutionTag(passIndex: Int) -> TaggedHeap.Tag {
        return (FrameGraphTagType.frameGraphTag << 32) | (FrameGraphTagType.renderPassExecution.rawValue << 16) | TaggedHeap.Tag(passIndex)
    }
    
    public var tag : TaggedHeap.Tag {
        assert(self != .renderPassExecution)
        let tag = (FrameGraphTagType.frameGraphTag << 32) | (self.rawValue << 16)
        return tag
    }
}

public final class FrameGraph {
    
    public static var jobManager : FrameGraphJobManager = DefaultFrameGraphJobManager()
    
    static let activeFrameGraphSemaphore = DispatchSemaphore(value: 1)
    public private(set) static var activeFrameGraph : FrameGraph? = nil
    
    /// executionAllocator is used for allocations that last one execution of the FrameGraph.
    static var executionAllocator : TagAllocator! = nil
    
    /// resourceUsagesAllocator is used for resource usages, and lasts one execution of the FrameGraph.
    static var resourceUsagesAllocator : TagAllocator! = nil
    
    private static var threadResourceUsages : [ResourceUsages] = []
    private static var threadUnmanagedReferences : [ExpandingBuffer<Releasable>]! = nil
    
    private var renderPasses : [RenderPassRecord] = []
    
    public static private(set) var globalSubmissionIndex : UInt64 = 0
    private var previousFrameCompletionTime : UInt64 = 0
    public private(set) var lastFrameRenderDuration = 1000.0 / 60.0
    
    var submissionNotifyQueue = [() -> Void]()
    let context : _FrameGraphContext
    
    public let transientRegistryIndex : Int
    
    public init(inflightFrameCount: Int, transientBufferCapacity: Int = 16384, transientTextureCapacity: Int = 16384, transientArgumentBufferArrayCapacity: Int = 1024) {
        
        self.transientRegistryIndex = TransientRegistryManager.allocate()
        
        TransientBufferRegistry.instances[self.transientRegistryIndex].initialise(capacity: transientBufferCapacity)
        TransientTextureRegistry.instances[self.transientRegistryIndex].initialise(capacity: transientTextureCapacity)
        TransientArgumentBufferArrayRegistry.instances[self.transientRegistryIndex].initialise(capacity: transientArgumentBufferArrayCapacity)
        
        switch RenderBackend._backend.api {
#if canImport(Metal)
        case .metal:
            self.context = MetalFrameGraphContext(backend: RenderBackend._backend as! MetalBackend, inflightFrameCount: inflightFrameCount, transientRegistryIndex: transientRegistryIndex)
#endif
#if canImport(Vulkan)
        case .vulkan:
            fatalError()
#endif
        }
    }
    
    deinit {
        TransientRegistryManager.free(self.transientRegistryIndex)
    }
    
    public var queue: Queue {
        return self.context.frameGraphQueue
    }
    
    public static func initialise() {
        
    }
    
    /// Useful for creating resources that may be used later in the frame.
    public func insertEarlyBlitPass(name: String,
                                    execute: @escaping (BlitCommandEncoder) -> Void)  {
        self.renderPasses.insert(RenderPassRecord(pass: CallbackBlitRenderPass(name: name, execute: execute),
                                                  passIndex: 0), at: 0)
    }
    
    public func insertEarlyBlitPass(_ pass: BlitRenderPass)  {
        self.renderPasses.insert(RenderPassRecord(pass: pass,
                                                  passIndex: 0), at: 0)
    }
    
    public func addPass(_ renderPass: RenderPass)  {
        self.renderPasses.append(RenderPassRecord(pass: renderPass, passIndex: self.renderPasses.count))
    }
    
    public func addBlitCallbackPass(name: String,
                                    execute: @escaping (BlitCommandEncoder) -> Void) {
        self.addPass(CallbackBlitRenderPass(name: name, execute: execute))
    }
    
    public func addDrawCallbackPass(name: String,
                                    descriptor: RenderTargetDescriptor,
                                    execute: @escaping (RenderCommandEncoder) -> Void) {
        self.addPass(CallbackDrawRenderPass(name: name, descriptor: descriptor, execute: execute))
    }
    
    public func addDrawCallbackPass<R>(name: String,
                                       descriptor: RenderTargetDescriptor,
                                       reflection: R.Type,
                                       execute: @escaping (TypedRenderCommandEncoder<R>) -> Void) {
        self.addPass(ReflectableCallbackDrawRenderPass(name: name, descriptor: descriptor, reflection: reflection, execute: execute))
    }
    
    public func addComputeCallbackPass(name: String,
                                       execute: @escaping (ComputeCommandEncoder) -> Void) {
        self.addPass(CallbackComputeRenderPass(name: name, execute: execute))
    }
    
    public func addComputeCallbackPass<R>(name: String,
                                          reflection: R.Type,
                                          execute: @escaping (TypedComputeCommandEncoder<R>) -> Void) {
        self.addPass(ReflectableCallbackComputeRenderPass(name: name, reflection: reflection, execute: execute))
    }
    
    public func addCPUCallbackPass(name: String,
                                   execute: @escaping () -> Void) {
        self.addPass(CallbackCPURenderPass(name: name, execute: execute))
    }
    
    public func addExternalCallbackPass(name: String,
                                        execute: @escaping (ExternalCommandEncoder) -> Void) {
        self.addPass(CallbackExternalRenderPass(name: name, execute: execute))
    }
    
    // When passes are added:
    // Check pass.writtenResources. If not empty, add the pass to the deferred queue and record its resource usages.
    // If it is empty, run the execute method eagerly and infer read/written resources from that.
    // Cull render passes using a reference counting floodfill method.
    // For any non-culled deferred passes, run the execute method and record the commands.
    // Pass off the full, joined command list, list of all resources used, and a list of active passes to the backend.
    // Backend will look over all resource usages and figure out necessary resource transitions and creation/destruction times (could be synced with command numbers e.g. before command 300, transition resource A to state X).
    // Then, it will execute the command list.
    
    func executePass(_ passRecord: RenderPassRecord, threadIndex: Int) {
        let resourceUsages = FrameGraph.threadResourceUsages[threadIndex]
        let unmanagedReferences = FrameGraph.threadUnmanagedReferences[threadIndex]
        
        let renderPassScratchTag = FrameGraphTagType.renderPassExecutionTag(passIndex: passRecord.passIndex)
        
        let commandRecorder = FrameGraphCommandRecorder(renderPassScratchAllocator: ThreadLocalTagAllocator(tag: renderPassScratchTag),
                                                        frameGraphExecutionAllocator: TagAllocator.ThreadView(allocator: FrameGraph.executionAllocator, threadIndex: threadIndex),
                                                        unmanagedReferences: unmanagedReferences)
        
        
        
        switch passRecord.pass {
        case let drawPass as DrawRenderPass:
            let rce = RenderCommandEncoder(commandRecorder: commandRecorder, resourceUsages: resourceUsages, renderPass: drawPass, passRecord: passRecord)
            drawPass.execute(renderCommandEncoder: rce)
            rce.endEncoding()
            
        case let computePass as ComputeRenderPass:
            let cce = ComputeCommandEncoder(commandRecorder: commandRecorder, resourceUsages: resourceUsages, renderPass: computePass, passRecord: passRecord)
            computePass.execute(computeCommandEncoder: cce)
            cce.endEncoding()
            
        case let blitPass as BlitRenderPass:
            let bce = BlitCommandEncoder(commandRecorder: commandRecorder, resourceUsages: resourceUsages, renderPass: blitPass, passRecord: passRecord)
            blitPass.execute(blitCommandEncoder: bce)
            bce.endEncoding()
            
        case let externalPass as ExternalRenderPass:
            let ece = ExternalCommandEncoder(commandRecorder: commandRecorder, resourceUsages: resourceUsages, renderPass: externalPass, passRecord: passRecord)
            externalPass.execute(externalCommandEncoder: ece)
            ece.endEncoding()
            
        case let cpuPass as CPURenderPass:
            cpuPass.execute()
            
        default:
            fatalError("Unknown pass type for pass \(passRecord)")
        }
        
        passRecord.commands = commandRecorder.commands
        passRecord.commandRange = 0..<passRecord.commands.count
        
        TaggedHeap.free(tag: renderPassScratchTag)
    }
    
    func evaluateResourceUsages(renderPasses: [RenderPassRecord]) {
        let jobManager = FrameGraph.jobManager
        
        for passRecord in renderPasses where passRecord.pass.passType == .cpu {
            if passRecord.pass.writtenResources.isEmpty {
                self.executePass(passRecord, threadIndex: jobManager.threadIndex)
            } else {
                FrameGraph.threadResourceUsages[0].addReadResources(passRecord.pass.readResources, for: Unmanaged.passUnretained(passRecord))
                FrameGraph.threadResourceUsages[0].addWrittenResources(passRecord.pass.writtenResources, for: Unmanaged.passUnretained(passRecord))
            }
        }
        
        for passRecord in renderPasses where passRecord.pass.passType != .cpu {
            jobManager.dispatchPassJob { [unowned(unsafe) jobManager] in
                let threadIndex = jobManager.threadIndex
                
                if passRecord.pass.writtenResources.isEmpty {
                    self.executePass(passRecord, threadIndex: threadIndex)
                } else {
                    FrameGraph.threadResourceUsages[threadIndex].addReadResources(passRecord.pass.readResources, for: Unmanaged.passUnretained(passRecord))
                    FrameGraph.threadResourceUsages[threadIndex].addWrittenResources(passRecord.pass.writtenResources, for: Unmanaged.passUnretained(passRecord))
                }
            }
        }
        
        jobManager.waitForAllPassJobs()
    }
    
    func markActive(passIndex i: Int, dependencyTable: DependencyTable<DependencyType>, renderPasses: [RenderPassRecord]) {
        if !renderPasses[i].isActive {
            renderPasses[i].isActive = true
            
            for j in (0..<i).reversed() where dependencyTable.dependency(from: i, on: j) == .execution {
                markActive(passIndex: j, dependencyTable: dependencyTable, renderPasses: renderPasses)
            }
        }
    }
    
    func computeDependencyOrdering(passIndex i: Int, dependencyTable: DependencyTable<DependencyType>, renderPasses: [RenderPassRecord], addedToList: inout [Bool], activePasses: inout [RenderPassRecord]) {
        
        // Ideally, we should reorder the passes into an optimal order according to some heuristics.
        // For example:
        // - Draw render passes that can share a render target should be placed alongside each other
        // - We should try to minimise the number of resource transitions
        // - Try to maximise the space between e.g. an updateFence and a waitForFence call.
        //
        // For now, only try to address the draw render pass issue
        
        if renderPasses[i].isActive, !addedToList[i] {
            addedToList[i] = true
            
            if let targetRenderTargetDescriptor = (renderPasses[i].pass as? DrawRenderPass)?.renderTargetDescriptor {
                // First process all passes that can't share the same render target...
                for j in (0..<i).reversed() where dependencyTable.dependency(from: i, on: j) != .none {
                    if let otherRenderTargetDescriptor = (renderPasses[j].pass as? DrawRenderPass)?.renderTargetDescriptor,RenderTargetDescriptor.areMergeable(otherRenderTargetDescriptor, targetRenderTargetDescriptor) {
                    } else {
                        computeDependencyOrdering(passIndex: j, dependencyTable: dependencyTable, renderPasses: renderPasses, addedToList: &addedToList, activePasses: &activePasses)
                    }
                }
                
                // ... and then process those which can.
                for j in (0..<i).reversed() where dependencyTable.dependency(from: i, on: j) != .none {
                    if let otherRenderTargetDescriptor = (renderPasses[j].pass as? DrawRenderPass)?.renderTargetDescriptor,RenderTargetDescriptor.areMergeable(otherRenderTargetDescriptor, targetRenderTargetDescriptor) {
                        computeDependencyOrdering(passIndex: j, dependencyTable: dependencyTable, renderPasses: renderPasses, addedToList: &addedToList, activePasses: &activePasses)
                    }
                }
                
            } else {
                for j in (0..<i).reversed() where dependencyTable.dependency(from: i, on: j) != .none {
                    computeDependencyOrdering(passIndex: j, dependencyTable: dependencyTable, renderPasses: renderPasses, addedToList: &addedToList, activePasses: &activePasses)
                }
            }
            
            activePasses.append(renderPasses[i])
        }
    }
    
    func compile(renderPasses: [RenderPassRecord]) -> ([RenderPassRecord], DependencyTable<DependencyType>) {
        
        renderPasses.enumerated().forEach { $1.passIndex = $0 } // We may have inserted early blit passes, so we need to set the pass indices now.
        
        self.evaluateResourceUsages(renderPasses: renderPasses)
        
        var dependencyTable = DependencyTable<DependencyType>(capacity: renderPasses.count, defaultValue: .none)
        var passHasSideEffects = [Bool](repeating: false, count: renderPasses.count)
        
        var producingPasses = [Int]()
        var priorReads = [Int]()
        
        // Merge the resources from all other threads into the usages for the first thread.
        for resourceUsages in FrameGraph.threadResourceUsages.dropFirst() {
            FrameGraph.threadResourceUsages[0].resources.formUnion(resourceUsages.allResources)
        }
        
        // Note: we don't need to include argument buffers in this loop since the only allowed usage of an argument buffer by the GPU is a read.
        // We don't need to reverse the order of reads, either, since reads don't form data hazards.
        // FIXME: this assumption will no longer hold once we support read-write argument buffers.
        for resource in FrameGraph.threadResourceUsages[0].resources where resource.type == .buffer || resource.type == .texture || resource.type == .argumentBuffer {
            if resource.isTextureView { continue } // Skip over the non-canonical versions of resources.
            
            resource.usagesPointer.reverse() // Since the usages list is constructed in reverse order.
            
            assert(resource._usesPersistentRegistry || resource.transientRegistryIndex == self.transientRegistryIndex, "Transient resource \(resource) associated with another FrameGraph is being used in this FrameGraph.")
            assert(resource.isValid, "Resource \(resource) is invalid but is used in the current frame.")
            
            let usages = resource.usages
            guard !usages.isEmpty else {
                continue
            }
            
            //            assert(resource.flags.contains(.initialised) || usages.first.isWrite, "Resource read by pass \(usages.first.renderPass.pass.name) without being written to.")
            for usage in usages {
                
                let usagePassIndex = usage.renderPassRecord.passIndex
                
                if usage.isRead {
                    for producingPass in producingPasses where usagePassIndex != producingPass {
                        dependencyTable.setDependency(from: usagePassIndex, on: producingPass, to: .execution)
                    }
                    priorReads.append(usagePassIndex)
                }
                if usage.isWrite {
                    // Also set each producing pass to be dependent on all previous passes, since the relative ordering of writes matters.
                    // The producingPasses list is guaranteed to be ordered.
                    for priorRead in priorReads where usagePassIndex != priorRead {
                        if dependencyTable.dependency(from: usagePassIndex, on: priorRead) != .execution {
                            dependencyTable.setDependency(from: usagePassIndex, on: priorRead, to: .ordering)
                        }
                    }
                    
                    producingPasses.append(usagePassIndex)
                }
            }
            
            if resource.flags.intersection([.persistent, .windowHandle, .historyBuffer, .externalOwnership]) != [] {
                for pass in producingPasses {
                    passHasSideEffects[pass] = true
                }
            }
            
            if resource.flags.contains(.windowHandle) {
                for pass in producingPasses {
                    renderPasses[pass].usesWindowTexture = true
                }
            }
            
            // Also set each producing pass to be dependent on all previous passes, since the relative ordering of writes matters.
            // The producingPasses list is guaranteed to be ordered.
            for (i, pass) in producingPasses.enumerated() {
                for dependentPass in producingPasses[(i + 1)...] where dependentPass != pass {
                    if dependencyTable.dependency(from: dependentPass, on: pass) != .execution {
                        dependencyTable.setDependency(from: dependentPass, on: pass, to: .ordering)
                    }
                }
            }
            
            producingPasses.removeAll(keepingCapacity: true)
            priorReads.removeAll(keepingCapacity: true)
        }
        
        for i in (0..<renderPasses.count).reversed() where passHasSideEffects[i] {
            self.markActive(passIndex: i, dependencyTable: dependencyTable, renderPasses: renderPasses)
        }
        
        var addedToList = (0..<renderPasses.count).map { _ in false }
        var activePasses = [RenderPassRecord]()
        for i in (0..<renderPasses.count).reversed() where passHasSideEffects[i] {
            self.computeDependencyOrdering(passIndex: i, dependencyTable: dependencyTable, renderPasses: renderPasses, addedToList: &addedToList, activePasses: &activePasses)
        }
        
        var i = 0
        while i < activePasses.count {
            let passRecord = activePasses[i]
            if passRecord.commandRange == nil {
                self.executePass(passRecord, threadIndex: 0)
            }
            if passRecord.pass.passType == .cpu || passRecord.commandRange!.count == 0 {
                passRecord.isActive = false // We've definitely executed the pass now, so there's no more work to be done on it by the GPU backends.
                activePasses.remove(at: i)
            } else {
                i += 1
            }
        }
        
        var activePassDependencies = DependencyTable<DependencyType>(capacity: activePasses.count, defaultValue: .none)
        
        for pass in (0..<activePasses.count).reversed() {
            let passIndexOriginal = activePasses[pass].passIndex
            
            for possibleDependency in (0..<pass).reversed() {
                let possibleDependencyIndexOriginal = activePasses[possibleDependency].passIndex
                guard possibleDependencyIndexOriginal < passIndexOriginal else { continue }
                
                let dependency = dependencyTable.dependency(from: passIndexOriginal, on: possibleDependencyIndexOriginal)
                activePassDependencies.setDependency(from: pass, on: possibleDependency, to: dependency)
            }
        }
        
        // Transitive dependencies: everything that has a dependency on us also has a transitive dependency on everything we have a dependency on.
        //        for sourcePass in 1..<max(1, activePasses.count - 1) { // Nothing can depend on the last pass.
        //            for possibleDependentPass in (sourcePass + 1)..<activePasses.count {
        //                if activePassDependencies.dependency(from: possibleDependentPass, on: sourcePass) != .none {
        //                    // Introduce a transitive dependency.
        //                    for sourceDependency in 0..<sourcePass {
        //                        if activePassDependencies.dependency(from: sourcePass, on: sourceDependency) != .none, dependencyTable.dependency(from: sourcePass, on: sourceDependency) == .none {
        //                            activePassDependencies.setDependency(from: possibleDependentPass, on: sourceDependency, to: .transitive)
        //                        }
        //                    }
        //                }
        //            }
        //        }
        
        return (activePasses, activePassDependencies)
    }
    
    public func waitForGPUSubmission(_ function: @escaping () -> Void) {
        self.submissionNotifyQueue.append(function)
    }
    
    public func execute(onSubmission: (() -> Void)? = nil, onGPUCompletion: (() -> Void)? = nil) {
        
        FrameGraph.activeFrameGraphSemaphore.wait()
        FrameGraph.activeFrameGraph = self
        defer {
            FrameGraph.activeFrameGraph = nil
            FrameGraph.activeFrameGraphSemaphore.signal()
        }
        
        let jobManager = FrameGraph.jobManager
        
        jobManager.dispatchSyncFrameGraph { [self] in
            self.context.accessSemaphore.wait()
            
            FrameGraph.resourceUsagesAllocator = TagAllocator(tag: FrameGraphTagType.resourceUsageNodes.tag, threadCount: jobManager.threadCount)
            FrameGraph.executionAllocator = TagAllocator(tag: FrameGraphTagType.frameGraphExecution.tag, threadCount: jobManager.threadCount)
            
            let threadCount = jobManager.threadCount
            
            FrameGraph.threadResourceUsages.reserveCapacity(threadCount)
            while FrameGraph.threadResourceUsages.count < threadCount {
                FrameGraph.threadResourceUsages.append(ResourceUsages())
            }
            
            FrameGraph.threadUnmanagedReferences = (0..<threadCount).map { i in
                return ExpandingBuffer(allocator: AllocatorType(TagAllocator.ThreadView(allocator: FrameGraph.executionAllocator, threadIndex: i)), initialCapacity: 0)
            }
            
            for (i, usages) in FrameGraph.threadResourceUsages.enumerated() {
                usages.usageNodeAllocator = TagAllocator.ThreadView(allocator: FrameGraph.resourceUsagesAllocator, threadIndex: i)
            }
            
            self.context.beginFrameResourceAccess()
            
            let (passes, dependencyTable) = self.compile(renderPasses: self.renderPasses)
            
            // Index the commands for each pass in a sequential manner for the entire frame.
            var commandCount = 0
            for (i, passRecord) in passes.enumerated() {
                let startCommandIndex = commandCount
                commandCount += passRecord.commands.count
                
                passRecord.passIndex = i
                passRecord.commandRange = startCommandIndex..<commandCount
                assert(passRecord.commandRange!.count > 0)
            }
            
            // Compilation is finished, so reset that tag.
            TaggedHeap.free(tag: FrameGraphTagType.frameGraphCompilation.tag)
            
            let completion = {
                let completionTime = DispatchTime.now().uptimeNanoseconds
                let elapsed = completionTime - self.previousFrameCompletionTime
                self.previousFrameCompletionTime = completionTime
                self.lastFrameRenderDuration = Double(elapsed) * 1e-6
                //            print("Frame \(currentFrameIndex) completed in \(self.lastFrameRenderDuration)ms.")
                
                onGPUCompletion?()
            }
            
            self.context.executeFrameGraph(passes: passes, dependencyTable: dependencyTable, resourceUsages: FrameGraph.threadResourceUsages[0], completion: completion)
            
            // Make sure the FrameGraphCommands buffers are deinitialised before the tags are freed.
            passes.forEach {
                $0.commands = nil
            }
            
            self.renderPasses.forEach {
                $0.commands = nil
            }
            
            onSubmission?()
            
            self.submissionNotifyQueue.forEach { $0() }
            self.submissionNotifyQueue.removeAll(keepingCapacity: true)
            
            self.reset()
            
            FrameGraph.globalSubmissionIndex += 1
        }
    }
    
    private func reset() {
        TransientBufferRegistry.instances[transientRegistryIndex].clear()
        TransientTextureRegistry.instances[transientRegistryIndex].clear()
        TransientArgumentBufferRegistry.instances[transientRegistryIndex].clear()
        TransientArgumentBufferArrayRegistry.instances[transientRegistryIndex].clear()
        
        PersistentTextureRegistry.instance.clear()
        PersistentBufferRegistry.instance.clear()
        PersistentArgumentBufferRegistry.instance.clear()
        PersistentArgumentBufferArrayRegistry.instance.clear()
        
        FrameGraph.threadUnmanagedReferences.forEach { unmanagedReferences in
            for reference in unmanagedReferences {
                reference.release()
            }
            unmanagedReferences.removeAll()
        }
        FrameGraph.threadUnmanagedReferences = nil
        
        self.renderPasses.removeAll(keepingCapacity: true)
        FrameGraph.threadResourceUsages.forEach { $0.reset() }
        
        FrameGraph.executionAllocator = nil
        FrameGraph.resourceUsagesAllocator = nil
        
        TaggedHeap.free(tag: FrameGraphTagType.frameGraphExecution.tag)
        TaggedHeap.free(tag: FrameGraphTagType.resourceUsageNodes.tag)
    }
}
