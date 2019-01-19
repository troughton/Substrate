//
//  FrameGraph.swift
//  SwiftFrameGraph
//
//  Created by Thomas Roughton on 17/03/17.
//
//

import Foundation
import Utilities

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
    public internal(set) var commandRange : Range<Int>?
    public internal(set) var passIndex : Int
    public internal(set) var isActive : Bool
    
    internal(set) var commandRecorderIndex : Int = 0
    
    init(pass: RenderPass, passIndex: Int) {
        self.pass = pass
        self.passIndex = passIndex
        self.commandRange = nil
        self.isActive = false
    }
}

public protocol FrameGraphBackend {
    func beginFrameResourceAccess() // Access is ended when a frameGraph is submitted.
    func executeFrameGraph(passes: [RenderPassRecord], resourceUsages: ResourceUsages, commands: [FrameGraphCommand], completion: @escaping () -> Void)
}

@_fixed_layout
public class FrameGraph {
    
    /// A debug setting to ensure that render passes are never culled, inactive resources are bound,
    /// and that all bound resources are used, making it potentially easier to find issues using debug tools.
    public static let debugMode = false
    
    #if os(macOS)
    public static let executionThreads = ProcessInfo.processInfo.processorCount / 2
    #else
    public static let executionThreads = 1
    #endif
    
    static let threadResourceUsages = (0..<executionThreads).map { _ in ResourceUsages() }
    
    static let threadCommandRecorders = (0..<executionThreads).map { _ in FrameGraphCommandRecorder() }
    
    static let completionSemaphore = DispatchSemaphore(value: RenderBackend.maxInflightFrames)
    
    private static var renderPasses : [RenderPassRecord] = []
    private static let renderPassQueue = DispatchQueue(label: "Render Pass Queue")
    
    @usableFromInline
    private(set) static var currentFrameIndex : UInt64 = 1 // starting at 0 causes issues for waits on the first frame.
    
    private static var previousFrameCompletionTime : UInt64 = 0
    
    public private(set) static var lastFrameRenderDuration = 1000.0 / 60.0
    
    static var submissionNotifyQueue = [() -> Void]()
    
    private init() {
    }

    /// Useful for creating resources that may be used later in the frame.
    public static func insertEarlyBlitPass(name: String,
                                            execute: @escaping (BlitCommandEncoder) -> Void)  {
        self.renderPassQueue.sync {
            self.renderPasses.insert(RenderPassRecord(pass: CallbackBlitRenderPass(name: name, execute: execute),
                                                      passIndex: 0), at: 0)
        }
    }
    
    public static func insertEarlyBlitPass(_ pass: BlitRenderPass)  {
        self.renderPassQueue.sync {
            self.renderPasses.insert(RenderPassRecord(pass: pass,
                                                      passIndex: 0), at: 0)
        }
    }

    public static func addPass(_ renderPass: RenderPass)  {
        self.renderPassQueue.sync {
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
    
    public static func addComputeCallbackPass(name: String,
                                          execute: @escaping (ComputeCommandEncoder) -> Void) {
        self.addPass(CallbackComputeRenderPass(name: name, execute: execute))
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
        let commandRecorder = self.threadCommandRecorders[threadIndex]
        let resourceUsages = self.threadResourceUsages[threadIndex]
        
        let startCommandIndex = commandRecorder.nextCommandIndex

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
        
        commandRecorder.commmandEncoderTemporaryArena.reset()
        
        let endCommandIndex = commandRecorder.nextCommandIndex
        
        passRecord.commandRange = startCommandIndex..<endCommandIndex
        passRecord.commandRecorderIndex = threadIndex
    }
    
    static func evaluateResourceUsages(renderPasses: [RenderPassRecord]) {
        
        for passRecord in renderPasses where passRecord.pass.passType == .cpu {
            if passRecord.pass.writtenResources.isEmpty {
                self.executePass(passRecord, threadIndex: 0)
            } else {
                self.threadResourceUsages[0].addReadResources(passRecord.pass.readResources, for: Unmanaged.passUnretained(passRecord))
                self.threadResourceUsages[0].addWrittenResources(passRecord.pass.writtenResources, for: Unmanaged.passUnretained(passRecord))
            }
        }
        
        DispatchQueue.concurrentPerform(iterations: self.executionThreads) { threadIndex in
            var passIndex = threadIndex

            while passIndex < renderPasses.count {
                defer { passIndex += self.executionThreads }

                let passRecord = renderPasses[passIndex]
                if passRecord.pass.passType == .cpu {
                    continue
                }

                if passRecord.pass.writtenResources.isEmpty {
                    self.executePass(passRecord, threadIndex: threadIndex)
                } else {
                    self.threadResourceUsages[threadIndex].addReadResources(passRecord.pass.readResources, for: Unmanaged.passUnretained(passRecord))
                    self.threadResourceUsages[threadIndex].addWrittenResources(passRecord.pass.writtenResources, for: Unmanaged.passUnretained(passRecord))
                }

            }
        }

    }
    
    enum DependencyType {
        /// No dependency
        case none
        /// If the dependency is active, it must be executed first
        case ordering
        /// The dependency must always be executed
        case execution
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
                    if let otherRenderTargetDescriptor = (renderPasses[j].pass as? DrawRenderPass)?.renderTargetDescriptor, RenderTargetDescriptor.areMergeable(otherRenderTargetDescriptor, targetRenderTargetDescriptor) {
                    } else {
                        computeDependencyOrdering(passIndex: j, dependencyTable: dependencyTable, renderPasses: renderPasses, addedToList: &addedToList, activePasses: &activePasses)
                    }
                }
                
                // ... and then process those which can.
                for j in (0..<i).reversed() where dependencyTable.dependency(from: i, on: j) != .none {
                    if let otherRenderTargetDescriptor = (renderPasses[j].pass as? DrawRenderPass)?.renderTargetDescriptor, RenderTargetDescriptor.areMergeable(otherRenderTargetDescriptor, targetRenderTargetDescriptor) {
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
    
//    static func testResourceUsagesListInsertion() {
//        var list = ResourceUsagesList()
//        
//        let arenas = (0..<10).map { _ in MemoryArena(blockSize: 1024) }
//        
//        DispatchQueue.concurrentPerform(iterations: 10, execute: { threadIndex in
//            for i in stride(from: threadIndex, to: 10000, by: 20) {
//                let renderPass = RenderPassRecord(pass: CallbackCPURenderPass(name: "", execute: {} ), passIndex: i)
//                list.append(ResourceUsage(type: .readWrite, stages: .cpuBeforeRender, inArgumentBuffer: false, firstCommandOffset: 0, renderPass: Unmanaged<RenderPassRecord>.passRetained(renderPass)), arena: arenas[threadIndex])
//            }
//        })
//        
//        var previousIndex = 0
//        for item in list {
//            assert(item.renderPassRecord.passIndex >= previousIndex)
//            previousIndex = item.renderPassRecord.passIndex
//            item._renderPass.release()
//        }
//    }
    
    static func compile(renderPasses: [RenderPassRecord]) -> [RenderPassRecord] {
        
        renderPasses.enumerated().forEach { $1.passIndex = $0 } // We may have inserted early blit passes, so we need to set the pass indices now.
        
        self.evaluateResourceUsages(renderPasses: renderPasses)
        
        var dependencyTable = DependencyTable<DependencyType>(capacity: renderPasses.count, defaultValue: .none)
        var passHasSideEffects = [Bool](repeating: false, count: renderPasses.count)
        
        var producingPasses = [Int]()
        var priorReads = [Int]()
        
        let expectedFrame = self.currentFrameIndex & 0b111
            
        // Merge the resources from all other threads into the usages for the first thread.
        for resourceUsages in self.threadResourceUsages.dropFirst() {
            self.threadResourceUsages[0].resources.formUnion(resourceUsages.allResources)
        }
        
        for resource in self.threadResourceUsages[0].resources where resource.type == .buffer || resource.type == .texture {
            resource.usagesPointer.reverse() // Since the usages list is constructed in reverse order.
            
            assert(resource._usesPersistentRegistry || (resource.handle >> 29) & 0b111 == expectedFrame, "Transient resource is being used in a frame after it was allocated.")
            
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
            
            if resource.flags.intersection([.persistent, .windowHandle, .historyBuffer]) != [] {
                for pass in producingPasses {
                    passHasSideEffects[pass] = true
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
        
        for i in (0..<renderPasses.count).reversed() where passHasSideEffects[i] || FrameGraph.debugMode {
            self.markActive(passIndex: i, dependencyTable: dependencyTable, renderPasses: renderPasses)
        }

        var addedToList = (0..<renderPasses.count).map { _ in false }
        var activePasses = [RenderPassRecord]()
        for i in (0..<renderPasses.count).reversed() where passHasSideEffects[i] || FrameGraph.debugMode {
            self.computeDependencyOrdering(passIndex: i, dependencyTable: dependencyTable, renderPasses: renderPasses, addedToList: &addedToList, activePasses: &activePasses)
        }
        
        var i = 0
        while i < activePasses.count {
            // FIXME: passes that explicitly specify their uses don't get culled, since we can't iterate through the usages list and decrement the producer reference count.
            // A better solution would be to insert an unknown 'read' or 'write' for each declared resource in these passes so they can participate in reference counting,
            // and then remove those usages once the pass has been executed.
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
        
        return activePasses
    }
    
    // Note: calling this on the same thread that execute is called on will cause deadlock.
    public static func waitForNextFrame() {
        FrameCompletion.waitForFrame(self.currentFrameIndex)
    }
    
    public static func waitForGPUSubmission(_ function: @escaping () -> Void) {
        self.submissionNotifyQueue.append(function)
    }
    
    public static func execute(backend: FrameGraphBackend, onGPUCompletion: (() -> Void)? = nil) {
        self.completionSemaphore.wait()
        let currentFrameIndex = self.currentFrameIndex
        
        backend.beginFrameResourceAccess()
        
        var renderPasses : [RenderPassRecord]! = nil
        self.renderPassQueue.sync {
            renderPasses = self.renderPasses
            self.renderPasses.removeAll(keepingCapacity: true)
        }

        let passes = self.compile(renderPasses: renderPasses)
        
        // The commands need to be re-ordered into a sequential manner
        var commands = [FrameGraphCommand]()
        commands.reserveCapacity(self.threadCommandRecorders[0].commands.count * self.executionThreads)
        
        for (i, passRecord) in passes.enumerated() {
            let startCommandIndex = commands.count
            commands.append(contentsOf: self.threadCommandRecorders[passRecord.commandRecorderIndex].commands[passRecord.commandRange!])
            let endCommandIndex = commands.count
            
            passRecord.passIndex = i
            passRecord.commandRange = startCommandIndex..<endCommandIndex
            assert(passRecord.commandRange!.count > 0)
        }
        
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
            
            assert(resource.storageMode != .private || (resource.usages.firstActiveUsage?.isWrite ?? true) || resource.stateFlags.contains(.initialised), "Resource \(resource) (type \(resource.type), label \(String(describing: resource.label))) is read from in pass \(resource.usages.firstActiveUsage!.renderPassRecord.pass.name) without being first written to.")
        }
        
        backend.executeFrameGraph(passes: passes, resourceUsages: self.threadResourceUsages[0], commands: commands, completion: {
            let completionTime = DispatchTime.now().uptimeNanoseconds
            let elapsed = completionTime - FrameGraph.previousFrameCompletionTime
            FrameGraph.previousFrameCompletionTime = completionTime
            self.lastFrameRenderDuration = Double(elapsed) * 1e-6
//            print("Frame completed in \(self.lastFrameRenderDuration)ms.")
            
            self.completionSemaphore.signal()
            FrameCompletion.markFrameComplete(frame: currentFrameIndex)
            onGPUCompletion?()
            
        })
        
        self.submissionNotifyQueue.forEach { $0() }
        self.submissionNotifyQueue.removeAll(keepingCapacity: true)
        
        self.reset()
        
        self.currentFrameIndex += 1
    }
    
    private static func reset() {
        TransientBufferRegistry.instance.clear()
        TransientTextureRegistry.instance.clear()
        TransientArgumentBufferRegistry.instance.clear()
        TransientArgumentBufferArrayRegistry.instance.clear()
        
        PersistentTextureRegistry.instance.clear()
        PersistentBufferRegistry.instance.clear()
        
        self.threadCommandRecorders.forEach { $0.reset() }
        self.threadResourceUsages.forEach { $0.reset() }
    }
}
