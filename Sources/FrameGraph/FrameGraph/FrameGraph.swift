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

public protocol FrameGraphBackend : class {
    
}

protocol _FrameGraphBackend : FrameGraphBackend, RenderBackendProtocol {
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

public class FrameGraph {
    
    public static var jobManager : FrameGraphJobManager = DefaultFrameGraphJobManager()

    private static var threadResourceUsages : [ResourceUsages] = []
    private static var threadUnmanagedReferences : [ExpandingBuffer<Releasable>]! = nil
    
    /// executionAllocator is used for allocations that last one execution of the FrameGraph.
    static var executionAllocator : TagAllocator! = nil
    
    /// resourceUsagesAllocator is used for resource usages, and lasts one execution of the FrameGraph.
    static var resourceUsagesAllocator : TagAllocator! = nil
    
    static var completionSemaphore = Semaphore(value: Int32(RenderBackend.maxInflightFrames))
    
    private static var renderPasses : [RenderPassRecord] = []
    private static var renderPassLock = SpinLock()
    
    public private(set) static var currentFrameIndex : UInt64 = 1 // starting at 0 causes issues for waits on the first frame.
    
    private static var previousFrameCompletionTime : UInt64 = 0
    
    public private(set) static var lastFrameRenderDuration = 1000.0 / 60.0
    
    static var submissionNotifyQueue = [() -> Void]()
    
    private init() {
    }
    
    public static func initialise() {
        FrameCompletion.initialise()
    }

    /// Useful for creating resources that may be used later in the frame.
    public static func insertEarlyBlitPass(name: String,
                                            execute: @escaping (BlitCommandEncoder) -> Void)  {
        self.renderPassLock.withLock {
            self.renderPasses.insert(RenderPassRecord(pass: CallbackBlitRenderPass(name: name, execute: execute),
                                                      passIndex: 0), at: 0)
        }
    }
    
    public static func insertEarlyBlitPass(_ pass: BlitRenderPass)  {
        self.renderPassLock.withLock {
            self.renderPasses.insert(RenderPassRecord(pass: pass,
                                                      passIndex: 0), at: 0)
        }
    }

    public static func addPass(_ renderPass: RenderPass)  {
        self.renderPassLock.withLock {
            self.renderPasses.append(RenderPassRecord(pass: renderPass, passIndex: self.renderPasses.count))
        }
    }
    
    public static func addBlitCallbackPass(name: String,
                                       execute: @escaping (BlitCommandEncoder) -> Void) {
        self.addPass(CallbackBlitRenderPass(name: name, execute: execute))
    }
    
    public static func addDrawCallbackPass(name: String,
                                    descriptor: RenderTargetDescriptor,
                                       execute: @escaping (RenderCommandEncoder) -> Void) {
        self.addPass(CallbackDrawRenderPass(name: name, descriptor: descriptor, execute: execute))
    }
    
    public static func addDrawCallbackPass<R>(name: String,
                                              descriptor: RenderTargetDescriptor,
                                              reflection: R.Type,
                                              execute: @escaping (TypedRenderCommandEncoder<R>) -> Void) {
        self.addPass(ReflectableCallbackDrawRenderPass(name: name, descriptor: descriptor, reflection: reflection, execute: execute))
    }
    
    public static func addComputeCallbackPass(name: String,
                                          execute: @escaping (ComputeCommandEncoder) -> Void) {
        self.addPass(CallbackComputeRenderPass(name: name, execute: execute))
    }
    
    public static func addComputeCallbackPass<R>(name: String,
                                                 reflection: R.Type,
                                              execute: @escaping (TypedComputeCommandEncoder<R>) -> Void) {
        self.addPass(ReflectableCallbackComputeRenderPass(name: name, reflection: reflection, execute: execute))
    }
    
    public static func addCPUCallbackPass(name: String,
                                      execute: @escaping () -> Void) {
        self.addPass(CallbackCPURenderPass(name: name, execute: execute))
    }
    
    public static func addExternalCallbackPass(name: String,
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

    static func executePass(_ passRecord: RenderPassRecord, threadIndex: Int) {
        let resourceUsages = self.threadResourceUsages[threadIndex]
        let unmanagedReferences = self.threadUnmanagedReferences[threadIndex]
        
        let renderPassScratchTag = FrameGraphTagType.renderPassExecutionTag(passIndex: passRecord.passIndex)

        let commandRecorder = FrameGraphCommandRecorder(renderPassScratchAllocator: ThreadLocalTagAllocator(tag: renderPassScratchTag),
                                                        frameGraphExecutionAllocator: TagAllocator.ThreadView(allocator: self.executionAllocator, threadIndex: threadIndex),
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
    
    static func evaluateResourceUsages(renderPasses: [RenderPassRecord]) {
        let jobManager = self.jobManager
        
        for passRecord in renderPasses where passRecord.pass.passType == .cpu {
            if passRecord.pass.writtenResources.isEmpty {
                self.executePass(passRecord, threadIndex: jobManager.threadIndex)
            } else {
                self.threadResourceUsages[0].addReadResources(passRecord.pass.readResources, for: Unmanaged.passUnretained(passRecord))
                self.threadResourceUsages[0].addWrittenResources(passRecord.pass.writtenResources, for: Unmanaged.passUnretained(passRecord))
            }
        }
        
        for passRecord in renderPasses where passRecord.pass.passType != .cpu {
            jobManager.dispatchPassJob { [unowned(unsafe) jobManager] in
                let threadIndex = jobManager.threadIndex
                
                if passRecord.pass.writtenResources.isEmpty {
                    FrameGraph.executePass(passRecord, threadIndex: threadIndex)
                } else {
                    FrameGraph.threadResourceUsages[threadIndex].addReadResources(passRecord.pass.readResources, for: Unmanaged.passUnretained(passRecord))
                    FrameGraph.threadResourceUsages[threadIndex].addWrittenResources(passRecord.pass.writtenResources, for: Unmanaged.passUnretained(passRecord))
                }
            }
        }
        
        jobManager.waitForAllPassJobs()
    }
    
    static func markActive(passIndex i: Int, dependencyTable: DependencyTable<DependencyType>, renderPasses: [RenderPassRecord]) {
        if !renderPasses[i].isActive {
            renderPasses[i].isActive = true
            
            for j in (0..<i).reversed() where dependencyTable.dependency(from: i, on: j) == .execution {
                markActive(passIndex: j, dependencyTable: dependencyTable, renderPasses: renderPasses)
            }
        }
    }
    
    static func computeDependencyOrdering(passIndex i: Int, dependencyTable: DependencyTable<DependencyType>, renderPasses: [RenderPassRecord], addedToList: inout [Bool], activePasses: inout [RenderPassRecord]) {
        
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
    
    static func compile(renderPasses: [RenderPassRecord]) -> ([RenderPassRecord], DependencyTable<DependencyType>) {
        
        renderPasses.enumerated().forEach { $1.passIndex = $0 } // We may have inserted early blit passes, so we need to set the pass indices now.
        
        self.evaluateResourceUsages(renderPasses: renderPasses)
        
        var dependencyTable = DependencyTable<DependencyType>(capacity: renderPasses.count, defaultValue: .none)
        var passHasSideEffects = [Bool](repeating: false, count: renderPasses.count)
        
        var producingPasses = [Int]()
        var priorReads = [Int]()
        
        let expectedFrame = self.currentFrameIndex & 0xFF
            
        // Merge the resources from all other threads into the usages for the first thread.
        for resourceUsages in self.threadResourceUsages.dropFirst() {
            self.threadResourceUsages[0].resources.formUnion(resourceUsages.allResources)
        }
        
        // Note: we don't need to include argument buffers in this loop since the only allowed usage of an argument buffer by the GPU is a read.
        // We don't need to reverse the order of reads, either, since reads don't form data hazards.
        // FIXME: this assumption will no longer hold once we support read-write argument buffers.
        for resource in self.threadResourceUsages[0].resources where resource.type == .buffer || resource.type == .texture || resource.type == .argumentBuffer {
            if resource.isTextureView { continue } // Skip over the non-canonical versions of resources.
            
            resource.usagesPointer.reverse() // Since the usages list is constructed in reverse order.
            
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
    
    // Note: calling this on the same thread that execute is called on will cause deadlock.
    public static func waitForNextFrame() {
        FrameCompletion.waitForFrame(self.currentFrameIndex)
    }
    
    public static func waitForGPUSubmission(_ function: @escaping () -> Void) {
        self.submissionNotifyQueue.append(function)
    }
    
    public static func execute(backend: FrameGraphBackend, onSubmission: (() -> Void)? = nil, onGPUCompletion: (() -> Void)? = nil) {
        let backend = backend as! _FrameGraphBackend
        
        var renderPasses : [RenderPassRecord]! = nil
        let jobManager = self.jobManager
        
        self.renderPassLock.withLock {
            renderPasses = self.renderPasses
            self.renderPasses.removeAll(keepingCapacity: true)
        }
        
        jobManager.dispatchSyncFrameGraph {
            self.completionSemaphore.wait()
            
            let currentFrameIndex = self.currentFrameIndex
            
            self.resourceUsagesAllocator = TagAllocator(tag: FrameGraphTagType.resourceUsageNodes.tag, threadCount: jobManager.threadCount)
            self.executionAllocator = TagAllocator(tag: FrameGraphTagType.frameGraphExecution.tag, threadCount: jobManager.threadCount)
            
            let threadCount = jobManager.threadCount
            
            self.threadResourceUsages.reserveCapacity(threadCount)
            while self.threadResourceUsages.count < threadCount {
                self.threadResourceUsages.append(ResourceUsages())
            }
            
            self.threadUnmanagedReferences = (0..<threadCount).map { i in
                return ExpandingBuffer(allocator: AllocatorType(TagAllocator.ThreadView(allocator: self.executionAllocator, threadIndex: i)), initialCapacity: 0)
            }
            
            for (i, usages) in self.threadResourceUsages.enumerated() {
                usages.usageNodeAllocator = TagAllocator.ThreadView(allocator: self.resourceUsagesAllocator, threadIndex: i)
            }
            
            backend.beginFrameResourceAccess()
            
            let (passes, dependencyTable) = self.compile(renderPasses: renderPasses)
            
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
            
            for resource in self.threadResourceUsages[0].resources { // Since at this point (after compile) the resources from all threads have been merged into the resources for thread 0.
                
                if resource.flags.contains(.persistent) {
                    var isRead = false
                    var isWritten = false
                    for usage in resource.usages where usage.renderPassRecord.isActive {
                        if usage.isRead {
                            isRead = true
                        }
                        if usage.isWrite {
                            isWritten = true
                            break
                        }
                    }
                    if isRead {
                        resource.writeWaitFrame = currentFrameIndex // The CPU can't write to this resource until the GPU has finished reading from it.
                    }
                    if isWritten {
                        resource.readWaitFrame = currentFrameIndex // The CPU can't read from this resource until the GPU has finished writing to it.
                    }
                }
                //            assert(resource.storageMode != .private || (resource.usages.firstActiveUsage?.isWrite ?? true) || resource.stateFlags.contains(.initialised), "Resource \(resource) (type \(resource.type), label \(String(describing: resource.label))) is read from in pass \(resource.usages.firstActiveUsage!.renderPassRecord.pass.name) without being first written to.")
            }
            
            
            let completion = {
                assert(!FrameCompletion.frameIsComplete(currentFrameIndex))
                let completionTime = DispatchTime.now().uptimeNanoseconds
                let elapsed = completionTime - FrameGraph.previousFrameCompletionTime
                FrameGraph.previousFrameCompletionTime = completionTime
                self.lastFrameRenderDuration = Double(elapsed) * 1e-6
                //            print("Frame \(currentFrameIndex) completed in \(self.lastFrameRenderDuration)ms.")
                
                self.completionSemaphore.signal()
                FrameCompletion.markFrameComplete(frame: currentFrameIndex)
                onGPUCompletion?()
            }
            
            if !passes.isEmpty {
                backend.executeFrameGraph(passes: passes, dependencyTable: dependencyTable, resourceUsages: self.threadResourceUsages[0], completion: completion)
            } else {
                completion()
            }
            
            // Make sure the FrameGraphCommands buffers are deinitialised before the tags are freed.
            passes.forEach {
                $0.commands = nil
            }
            
            renderPasses.forEach {
                $0.commands = nil
            }
            
            onSubmission?()
            
            self.submissionNotifyQueue.forEach { $0() }
            self.submissionNotifyQueue.removeAll(keepingCapacity: true)
            
            self.reset()
            
            self.currentFrameIndex += 1
        }
    }
    
    private static func reset() {
        TransientBufferRegistry.instance.clear()
        TransientTextureRegistry.instance.clear()
        TransientArgumentBufferRegistry.instance.clear()
        TransientArgumentBufferArrayRegistry.instance.clear()
        
        PersistentTextureRegistry.instance.clear()
        PersistentBufferRegistry.instance.clear()
        PersistentArgumentBufferRegistry.instance.clear()
        PersistentArgumentBufferArrayRegistry.instance.clear()
        
        self.threadUnmanagedReferences.forEach { unmanagedReferences in
            for reference in unmanagedReferences {
                reference.release()
            }
            unmanagedReferences.removeAll()
        }
        self.threadUnmanagedReferences = nil
        
        self.threadResourceUsages.forEach { $0.reset() }
        
        self.executionAllocator = nil
        self.resourceUsagesAllocator = nil
        
        TaggedHeap.free(tag: FrameGraphTagType.frameGraphExecution.tag)
        TaggedHeap.free(tag: FrameGraphTagType.resourceUsageNodes.tag)
    }
}
