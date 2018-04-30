//
//  FrameGraph.swift
//  InterdimensionalLlama
//
//  Created by Thomas Roughton on 17/03/17.
//
//

import Foundation
import RenderAPI
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
    public var commandRange : Range<Int>?
    public var passIndex : Int
    var refCount : Int
    
    init(pass: RenderPass, passIndex: Int) {
        self.pass = pass
        self.passIndex = passIndex
        self.commandRange = nil
        self.refCount = 0
    }
    
    public var isActive : Bool {
        return self.refCount > 0
    }
}

public protocol FrameGraphBackend {
    func beginFrameResourceAccess() // Access is ended when a frameGraph is submitted.
    func executeFrameGraph(passes: [RenderPassRecord], resourceUsages: ResourceUsages, commands: [FrameGraphCommand], completion: @escaping () -> Void)
}

public class FrameGraph {
    
    static let resourceUsages = ResourceUsages()
    static let commandRecorder = FrameGraphCommandRecorder()
    
    static let completionSemaphore = DispatchSemaphore(value: RenderBackend.maxInflightFrames)
    
    private static var renderPasses : [RenderPassRecord] = []
    private static let renderPassQueue = DispatchQueue(label: "Render Pass Queue")
    
    private init() {
    }

    /// Useful for creating resources that may be used later in the frame.
    public static func insertEarlyBlitPass(name: String,
                                            execute: @escaping (BlitCommandEncoder) -> Void)  {
        self.renderPassQueue.sync {
            self.renderPasses.insert(RenderPassRecord(pass: CallbackBlitRenderPass(name: name, execute: execute),
                                                      passIndex: self.renderPasses.count), at: 0)
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
        
        let endCommandIndex = self.commandRecorder.nextCommandIndex
        
        return startCommandIndex..<endCommandIndex
    }
    
    static func evaluateResourceUsages(renderPasses: [RenderPassRecord]) {
        for passRecord in renderPasses {

            if passRecord.pass.writtenResources.isEmpty {
                passRecord.commandRange = self.executePass(passRecord)
            } else {
                self.resourceUsages.addReadResources(passRecord.pass.readResources, for: passRecord.pass)
                self.resourceUsages.addWrittenResources(passRecord.pass.writtenResources, for: passRecord.pass)
            }
        }
    }
    
    static func compile(renderPasses: [RenderPassRecord]) {
        self.evaluateResourceUsages(renderPasses: renderPasses)
        
        //Simple graph flood-fill from unreferenced resources
        
        var resourceRefCounts = [ObjectIdentifier : UInt32]()
        
        //Compute initial resource and pass reference counts
        for passRecord in renderPasses {
            passRecord.refCount += self.resourceUsages.writtenResources(for: passRecord.pass).count
            
            for resource in self.resourceUsages.readResources(for: passRecord.pass) {
                resourceRefCounts[resource, default: 0] += 1
            }
        }
        
        var unusedResources = self.resourceUsages.usages.keys.filter { resourceIdentifier in
            // This resource isn't actually used; it only has usages as an argumentBufferUnused.
            guard let resource = resourceUsages[resourceIdentifier] else { return false }
    
            return (resourceRefCounts[resourceIdentifier] ?? 0) == 0 &&
                    resource.flags.intersection([.persistent, .windowHandle]) == [] 
        }
        
        while let resourceIdentifier = unusedResources.popLast() {
            let resource = self.resourceUsages[resourceIdentifier]!
            
            guard resource.flags.intersection([.persistent, .windowHandle]) == [] else {
                continue
            }
            
            for usage in self.resourceUsages[usagesFor: resource] where usage.isWrite {
                let producer = usage.renderPass
                producer.refCount -= 1
                if producer.refCount == 0 {
                    for resource in self.resourceUsages.readResources(for: producer.pass) {
                        resourceRefCounts[resource]! -= 1
                        if resourceRefCounts[resource] == 0 {
                            unusedResources.append(resource)
                        }
                    }
                }
            }
        }
        
        for passRecord in renderPasses where passRecord.commandRange == nil {
            passRecord.commandRange = self.executePass(passRecord)
        }
    }
    
    public static func execute(backend: FrameGraphBackend) {
        self.completionSemaphore.wait()
        
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
        
        backend.executeFrameGraph(passes: passes, resourceUsages: self.resourceUsages, commands: commands, completion: {
            self.completionSemaphore.signal()
        })
        
        self.reset()
        
    }
    
    private static func reset() {
        self.commandRecorder.reset()
        self.resourceUsages.reset()
    }
}
