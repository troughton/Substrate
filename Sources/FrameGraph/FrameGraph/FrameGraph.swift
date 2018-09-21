//
//  FrameGraph.swift
//  InterdimensionalLlama
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

public enum RenderPassType {
    case cpu
    case draw
    case compute
    case blit
}


public final class RenderPassRecord {
    public let pass : RenderPass
    public internal(set) var commandRange : Range<Int>?
    public internal(set) var passIndex : Int
    public internal(set) var isActive : Bool
    
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

public class FrameGraph {
    
    /// A debug setting to ensure that render passes are never culled, inactive resources are bound,
    /// and that all bound resources are used, making it potentially easier to find issues using debug tools.
    public static let debugMode = false
    
    static let resourceUsages = ResourceUsages()
    static let commandRecorder = FrameGraphCommandRecorder()
    
    static let completionSemaphore = DispatchSemaphore(value: RenderBackend.maxInflightFrames)
    
    private static var renderPasses : [RenderPassRecord] = []
    private static let renderPassQueue = DispatchQueue(label: "Render Pass Queue")
    
    private static var currentFrameIndex : UInt64 = 1 // starting at 0 causes issues for waits on the first frame.
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
    
    // When passes are added:
    // Check pass.writtenResources. If not empty, add the pass to the deferred queue and record its resource usages.
    // If it is empty, run the execute method eagerly and infer read/written resources from that.
    // Cull render passes using a reference counting floodfill method.
    // For any non-culled deferred passes, run the execute method and record the commands.
    // Pass off the full, joined command list, list of all resources used, and a list of active passes to the backend.
    // Backend will look over all resource usages and figure out necessary resource transitions and creation/destruction times (could be synced with command numbers e.g. before command 300, transition resource A to state X).
    // Then, it will execute the command list.

    static func executePass(_ passRecord: RenderPassRecord) -> Range<Int> {
        let startCommandIndex = self.commandRecorder.nextCommandIndex

        switch passRecord.pass {
        case let drawPass as DrawRenderPass:
            let rce = RenderCommandEncoder(commandRecorder: self.commandRecorder, resourceUsages: self.resourceUsages, renderPass: drawPass, passRecord: passRecord)
            drawPass.execute(renderCommandEncoder: rce)
            rce.endEncoding()
            
        case let computePass as ComputeRenderPass:
            let cce = ComputeCommandEncoder(commandRecorder: self.commandRecorder, resourceUsages: self.resourceUsages, renderPass: computePass, passRecord: passRecord)
            computePass.execute(computeCommandEncoder: cce)
            cce.endEncoding()
            
        case let blitPass as BlitRenderPass:
            let bce = BlitCommandEncoder(commandRecorder: self.commandRecorder, resourceUsages: self.resourceUsages, renderPass: blitPass, passRecord: passRecord)
            blitPass.execute(blitCommandEncoder: bce)
            bce.endEncoding()
            
        case let cpuPass as CPURenderPass:
            cpuPass.execute()
            
        default:
            fatalError("Unknown pass type for pass \(passRecord)")
        }
        
        self.commandRecorder.commmandEncoderTemporaryArena.reset()
        
        let endCommandIndex = self.commandRecorder.nextCommandIndex
        
        return startCommandIndex..<endCommandIndex
    }
    
    static func evaluateResourceUsages(renderPasses: [RenderPassRecord]) {
        for passRecord in renderPasses {
            if passRecord.pass.writtenResources.isEmpty {
                passRecord.commandRange = self.executePass(passRecord)
            } else {
                self.resourceUsages.addReadResources(passRecord.pass.readResources, for: Unmanaged.passUnretained(passRecord))
                self.resourceUsages.addWrittenResources(passRecord.pass.writtenResources, for: Unmanaged.passUnretained(passRecord))
            }
        }
    }
    
    static func markActive(passIndex i: Int, dependencyTable: DependencyTable<Bool>, renderPasses: [RenderPassRecord]) {
        if !renderPasses[i].isActive {
            renderPasses[i].isActive = true
            for j in 0..<i {
                if dependencyTable.dependency(from: i, on: j), !renderPasses[j].isActive {
                    markActive(passIndex: j, dependencyTable: dependencyTable, renderPasses: renderPasses)
                }
            }
        }
    }
    
    static func compile(renderPasses: [RenderPassRecord]) {
        renderPasses.enumerated().forEach { $1.passIndex = $0 } // We may have inserted early blit passes, so we need to se the pass indices now.
        
        self.evaluateResourceUsages(renderPasses: renderPasses)
        
        var dependencyTable = DependencyTable<Bool>(capacity: renderPasses.count, defaultValue: false)
        var passHasSideEffects = [Bool](repeating: false, count: renderPasses.count)
        
        var producingPasses = [Int]()
        
        for resource in resourceUsages.resources {
            let usages = resource.usages
            guard !usages.isEmpty else {
                continue
            }
            
//            assert(resource.flags.contains(.initialised) || usages.first.isWrite, "Resource read by pass \(usages.first.renderPass.pass.name) without being written to.")
            
            for usage in usages {
                if usage.isRead {
                    for producingPass in producingPasses where usage.renderPass.passIndex != producingPass {
                        dependencyTable.setDependency(from: usage.renderPass.passIndex, on: producingPass, to: true)
                    }
                }
                if usage.isWrite {
                    producingPasses.append(usage.renderPass.passIndex)
                }
            }
            
            if resource.flags.intersection([.persistent, .windowHandle, .historyBuffer]) != [] {
                for pass in producingPasses {
                    passHasSideEffects[pass] = true
                }
            }
            
            producingPasses.removeAll(keepingCapacity: true)
        }
        
        for i in (0..<renderPasses.count).reversed() where passHasSideEffects[i] || FrameGraph.debugMode {
            self.markActive(passIndex: i, dependencyTable: dependencyTable, renderPasses: renderPasses)
        }
        
        for passRecord in renderPasses where passRecord.isActive {
            // FIXME: this doesn't interact correctly with the ResourceUsagesLists – we need to insert new nodes in place there.
            // This issue also means those passes don't get culled, since we can't iterate through the usages list and decrement the producer reference count.
            // We should ideally be executing passes in parallel, and then merging the resource usage lists from each pass together at the end.
            if passRecord.commandRange == nil {
                passRecord.commandRange = self.executePass(passRecord)
            }
            if passRecord.pass.passType == .cpu {
                passRecord.isActive = false // We've definitely executed the pass now, so there's no more work to be done on it by the GPU backends.
            }
        }
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

        self.compile(renderPasses: renderPasses)
        
        // Ideally, we should reorder the passes into an optimal order according to some heuristics.
        // For example:
        // - Draw render passes that can share a render target should be placed alongside each other
        // - We should try to minimise the number of resource transitions
        // - Try to maximise the space between e.g. an updateFence and a waitForFence call.
        //
        // For now, we just send the passes through in the order we received them.
        
        var passes = [RenderPassRecord]()
        
        var commands = [FrameGraphCommand]()
        commands.reserveCapacity(self.commandRecorder.commands.count)
        
        for passRecord in renderPasses where passRecord.isActive {
            let startCommandIndex = commands.count
            commands.append(contentsOf: self.commandRecorder.commands[passRecord.commandRange!])
            let endCommandIndex = commands.count
            
            passRecord.passIndex = passes.count
            passRecord.commandRange = startCommandIndex..<endCommandIndex
            passes.append(passRecord)
        }
        
        for resource in resourceUsages.allResources where resource.flags.contains(.persistent) {
            var isRead = false
            var isWritten = false
            for usage in resource.usages where usage.renderPass.isActive {
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
        
        backend.executeFrameGraph(passes: passes, resourceUsages: self.resourceUsages, commands: commands, completion: {
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
        
        self.commandRecorder.reset()
        self.resourceUsages.reset()
    }
}
