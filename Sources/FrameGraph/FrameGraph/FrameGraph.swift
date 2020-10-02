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
    
    func colorClearOperation(attachmentIndex: Int) -> ColorClearOperation
    var depthClearOperation: DepthClearOperation { get }
    var stencilClearOperation: StencilClearOperation { get }
}

extension DrawRenderPass {
    @inlinable
    public var passType : RenderPassType {
        return .draw
    }
    
    @inlinable
    public func colorClearOperation(attachmentIndex: Int) -> ColorClearOperation {
        return .keep
    }
    
    @inlinable
    public var depthClearOperation : DepthClearOperation {
        return .keep
    }
    
    @inlinable
    public var stencilClearOperation : StencilClearOperation {
        return .keep
    }
    
    var renderTargetDescriptorForActiveAttachments: RenderTargetDescriptor {
        // Filter out any unused attachments.
        var descriptor = self.renderTargetDescriptor
        
        let isUsedAttachment: (Texture) -> Bool = { attachment in
            return attachment.usages.contains(where: {
                return $0.renderPassRecord.pass === self && $0.type.isRenderTarget && $0.type != .unusedRenderTarget
            })
        }
        
        for (i, colorAttachment) in descriptor.colorAttachments.enumerated() {
            if let attachment = colorAttachment?.texture, case .keep = self.colorClearOperation(attachmentIndex: i), !isUsedAttachment(attachment) {
                descriptor.colorAttachments[i] = nil
            }
        }
        
        if let attachment = descriptor.depthAttachment?.texture, case .keep = self.depthClearOperation, !isUsedAttachment(attachment) {
            descriptor.depthAttachment = nil
        }
        
        if let attachment = descriptor.stencilAttachment?.texture, case .keep = self.stencilClearOperation, !isUsedAttachment(attachment) {
            descriptor.stencilAttachment = nil
        }
        
        return descriptor
    }
}

public protocol ComputeRenderPass : RenderPass {
    func execute(computeCommandEncoder: ComputeCommandEncoder)
}

extension ComputeRenderPass {
    @inlinable
    public var passType : RenderPassType {
        return .compute
    }
}

public protocol CPURenderPass : RenderPass {
    func execute()
}

extension CPURenderPass {
    @inlinable
    public var passType : RenderPassType {
        return .cpu
    }
}

public protocol BlitRenderPass : RenderPass {
    func execute(blitCommandEncoder: BlitCommandEncoder)
}

extension BlitRenderPass {
    @inlinable
    public var passType : RenderPassType {
        return .blit
    }
}

public protocol ExternalRenderPass : RenderPass {
    func execute(externalCommandEncoder: ExternalCommandEncoder)
}

extension ExternalRenderPass {
    @inlinable
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
    public let colorClearOperations: [ColorClearOperation]
    public let depthClearOperation: DepthClearOperation
    public let stencilClearOperation: StencilClearOperation
    public let executeFunc : (RenderCommandEncoder) -> Void
    
    public init(name: String, descriptor: RenderTargetDescriptor,
                colorClearOperations: [ColorClearOperation],
                depthClearOperation: DepthClearOperation,
                stencilClearOperation: StencilClearOperation,
                execute: @escaping (RenderCommandEncoder) -> Void) {
        self.name = name
        self.renderTargetDescriptor = descriptor
        self.colorClearOperations = colorClearOperations
        self.depthClearOperation = depthClearOperation
        self.stencilClearOperation = stencilClearOperation
        self.executeFunc = execute
    }
    
    public func colorClearOperation(attachmentIndex: Int) -> ColorClearOperation {
        if attachmentIndex < self.colorClearOperations.count {
            return self.colorClearOperations[attachmentIndex]
        }
        return .keep
    }
    
    public func execute(renderCommandEncoder: RenderCommandEncoder) {
        self.executeFunc(renderCommandEncoder)
    }
}

final class ReflectableCallbackDrawRenderPass<R : RenderPassReflection> : ReflectableDrawRenderPass {
    public let name : String
    public let renderTargetDescriptor: RenderTargetDescriptor
    public let colorClearOperations: [ColorClearOperation]
    public let depthClearOperation: DepthClearOperation
    public let stencilClearOperation: StencilClearOperation
    public let executeFunc : (TypedRenderCommandEncoder<R>) -> Void
    
    public init(name: String, descriptor: RenderTargetDescriptor,
                colorClearOperations: [ColorClearOperation],
                depthClearOperation: DepthClearOperation,
                stencilClearOperation: StencilClearOperation,
                reflection: R.Type, execute: @escaping (TypedRenderCommandEncoder<R>) -> Void) {
        self.name = name
        self.renderTargetDescriptor = descriptor
        self.colorClearOperations = colorClearOperations
        self.depthClearOperation = depthClearOperation
        self.stencilClearOperation = stencilClearOperation
        self.executeFunc = execute
    }
    
    public func colorClearOperation(attachmentIndex: Int) -> ColorClearOperation {
        if attachmentIndex < self.colorClearOperations.count {
            return self.colorClearOperations[attachmentIndex]
        }
        return .keep
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

@usableFromInline
final class RenderPassRecord {
    @usableFromInline var pass : RenderPass!
    @usableFromInline var commands : ChunkArray<FrameGraphCommand>! = nil
    @usableFromInline var readResources : HashSet<Resource>! = nil
    @usableFromInline var writtenResources : HashSet<Resource>! = nil
    @usableFromInline var resourceUsages : ChunkArray<(Resource, ResourceUsage)>! = nil
    @usableFromInline /* internal(set) */ var commandRange : Range<Int>?
    @usableFromInline /* internal(set) */ var passIndex : Int
    @usableFromInline /* internal(set) */ var isActive : Bool
    @usableFromInline /* internal(set) */ var usesWindowTexture : Bool = false
    @usableFromInline /* internal(set) */ var hasSideEffects : Bool = false
    
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
    var accessSemaphore : DispatchSemaphore { get }
    var frameGraphQueue: Queue { get }
    func beginFrameResourceAccess() // Access is ended when a frameGraph is submitted.
    func executeFrameGraph(passes: [RenderPassRecord], usedResources: Set<Resource>, dependencyTable: DependencyTable<DependencyType>, completion: @escaping (_ gpuTime: Double) -> Void)
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
    
    private static var threadUnmanagedReferences : [ExpandingBuffer<Releasable>]! = nil
    
    private var renderPasses : [RenderPassRecord] = []
    private var usedResources : Set<Resource> = []
    
    public static private(set) var globalSubmissionIndex : UInt64 = 0
    private var previousFrameCompletionTime : UInt64 = 0
    public private(set) var lastFrameRenderDuration = 1000.0 / 60.0
    public private(set) var lastFrameGPUTime = 1000.0 / 60.0
    
    var submissionNotifyQueue = [() -> Void]()
    var completionNotifyQueue = [() -> Void]()
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
            self.context = FrameGraphContextImpl<MetalBackend>(backend: RenderBackend._backend as! MetalBackend, inflightFrameCount: inflightFrameCount, transientRegistryIndex: transientRegistryIndex)
#endif
#if canImport(Vulkan)
        case .vulkan:
            self.context = FrameGraphContextImpl<VulkanBackend>(backend: RenderBackend._backend as! VulkanBackend, inflightFrameCount: inflightFrameCount, transientRegistryIndex: transientRegistryIndex)
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
    
    public var hasEnqueuedPasses: Bool {
        return !self.renderPasses.isEmpty
    }
    
    /// Useful for creating resources that may be used later in the frame.
    public func insertEarlyBlitPass(name: String,
                                    _ execute: @escaping (BlitCommandEncoder) -> Void)  {
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
    
    public func addBlitCallbackPass(file: String = #file, line: Int = #line,
                                    _ execute: @escaping (BlitCommandEncoder) -> Void) {
        self.addPass(CallbackBlitRenderPass(name: "Anonymous Blit Pass at \(file):\(line)", execute: execute))
    }
    
    public func addBlitCallbackPass(name: String,
                                    _ execute: @escaping (BlitCommandEncoder) -> Void) {
        self.addPass(CallbackBlitRenderPass(name: name, execute: execute))
    }
    
    public func addClearPass(file: String = #file, line: Int = #line,
                             renderTarget: RenderTargetDescriptor,
                             colorClearOperations: [ColorClearOperation] = [],
                             depthClearOperation: DepthClearOperation = .keep,
                             stencilClearOperation: StencilClearOperation = .keep) {
        self.addPass(CallbackDrawRenderPass(name: "Clear Pass at \(file):\(line)", descriptor: renderTarget,
                                            colorClearOperations: colorClearOperations, depthClearOperation: depthClearOperation, stencilClearOperation: stencilClearOperation,
                                            execute: { _ in }))
    }
    
    public func addDrawCallbackPass(file: String = #file, line: Int = #line,
                                    descriptor: RenderTargetDescriptor,
                                    colorClearOperations: [ColorClearOperation] = [],
                                    depthClearOperation: DepthClearOperation = .keep,
                                    stencilClearOperation: StencilClearOperation = .keep,
                                    _ execute: @escaping (RenderCommandEncoder) -> Void) {
        self.addPass(CallbackDrawRenderPass(name: "Anonymous Draw Pass at \(file):\(line)", descriptor: descriptor,
                                            colorClearOperations: colorClearOperations, depthClearOperation: depthClearOperation, stencilClearOperation: stencilClearOperation,
                                            execute: execute))
    }
    
    public func addDrawCallbackPass(name: String,
                                    descriptor: RenderTargetDescriptor,
                                    colorClearOperations: [ColorClearOperation] = [],
                                    depthClearOperation: DepthClearOperation = .keep,
                                    stencilClearOperation: StencilClearOperation = .keep,
                                    _ execute: @escaping (RenderCommandEncoder) -> Void) {
        self.addPass(CallbackDrawRenderPass(name: name, descriptor: descriptor,
                                            colorClearOperations: colorClearOperations, depthClearOperation: depthClearOperation, stencilClearOperation: stencilClearOperation,
                                            execute: execute))
    }
    
    public func addDrawCallbackPass<R>(file: String = #file, line: Int = #line,
                                       descriptor: RenderTargetDescriptor,
                                       colorClearOperations: [ColorClearOperation] = [],
                                       depthClearOperation: DepthClearOperation = .keep,
                                       stencilClearOperation: StencilClearOperation = .keep,
                                       reflection: R.Type,
                                       _ execute: @escaping (TypedRenderCommandEncoder<R>) -> Void) {
        self.addPass(ReflectableCallbackDrawRenderPass(name: "Anonymous Draw Pass at \(file):\(line)", descriptor: descriptor,
                                                       colorClearOperations: colorClearOperations, depthClearOperation: depthClearOperation, stencilClearOperation: stencilClearOperation,
                                                       reflection: reflection, execute: execute))
    }
    
    public func addDrawCallbackPass<R>(name: String,
                                       descriptor: RenderTargetDescriptor,
                                       colorClearOperations: [ColorClearOperation] = [],
                                       depthClearOperation: DepthClearOperation = .keep,
                                       stencilClearOperation: StencilClearOperation = .keep,
                                       reflection: R.Type,
                                       _ execute: @escaping (TypedRenderCommandEncoder<R>) -> Void) {
        self.addPass(ReflectableCallbackDrawRenderPass(name: name, descriptor: descriptor,
        colorClearOperations: colorClearOperations, depthClearOperation: depthClearOperation, stencilClearOperation: stencilClearOperation,
        reflection: reflection, execute: execute))
    }

    public func addComputeCallbackPass(file: String = #file, line: Int = #line,
                                       _ execute: @escaping (ComputeCommandEncoder) -> Void) {
        self.addPass(CallbackComputeRenderPass(name: "Anonymous Compute Pass at \(file):\(line)", execute: execute))
    }
    
    public func addComputeCallbackPass(name: String,
                                       _ execute: @escaping (ComputeCommandEncoder) -> Void) {
        self.addPass(CallbackComputeRenderPass(name: name, execute: execute))
    }

    public func addComputeCallbackPass<R>(file: String = #file, line: Int = #line,
                                          reflection: R.Type,
                                          _ execute: @escaping (TypedComputeCommandEncoder<R>) -> Void) {
        self.addPass(ReflectableCallbackComputeRenderPass(name: "Anonymous Compute Pass at \(file):\(line)", reflection: reflection, execute: execute))
    }
    
    public func addComputeCallbackPass<R>(name: String,
                                          reflection: R.Type,
                                          _ execute: @escaping (TypedComputeCommandEncoder<R>) -> Void) {
        self.addPass(ReflectableCallbackComputeRenderPass(name: name, reflection: reflection, execute: execute))
    }
    
    public func addCPUCallbackPass(file: String = #file, line: Int = #line,
                                   _ execute: @escaping () -> Void) {
        self.addPass(CallbackCPURenderPass(name: "Anonymous CPU Pass at \(file):\(line)", execute: execute))
    }
    
    public func addCPUCallbackPass(name: String,
                                   _ execute: @escaping () -> Void) {
        self.addPass(CallbackCPURenderPass(name: name, execute: execute))
    }
    
    public func addExternalCallbackPass(file: String = #file, line: Int = #line,
                                        _ execute: @escaping (ExternalCommandEncoder) -> Void) {
        self.addPass(CallbackExternalRenderPass(name: "Anonymous External Encoder Pass at \(file):\(line)", execute: execute))
    }
    
    public func addExternalCallbackPass(name: String,
                                        _ execute: @escaping (ExternalCommandEncoder) -> Void) {
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
        let unmanagedReferences = FrameGraph.threadUnmanagedReferences[threadIndex]
        
        let renderPassScratchTag = FrameGraphTagType.renderPassExecutionTag(passIndex: passRecord.passIndex)
        
        let commandRecorder = FrameGraphCommandRecorder(frameGraphTransientRegistryIndex: self.transientRegistryIndex,
                                                        frameGraphQueue: self.queue,
                                                        renderPassScratchAllocator: ThreadLocalTagAllocator(tag: renderPassScratchTag),
                                                        frameGraphExecutionAllocator: TagAllocator.ThreadView(allocator: FrameGraph.executionAllocator, threadIndex: threadIndex),
                                                        resourceUsageAllocator: TagAllocator.ThreadView(allocator: FrameGraph.resourceUsagesAllocator, threadIndex: threadIndex),
                                                        unmanagedReferences: unmanagedReferences)
        
        
        
        switch passRecord.pass {
        case let drawPass as DrawRenderPass:
            let rce = RenderCommandEncoder(commandRecorder: commandRecorder, renderPass: drawPass, passRecord: passRecord)
            drawPass.execute(renderCommandEncoder: rce)
            rce.endEncoding()
            
        case let computePass as ComputeRenderPass:
            let cce = ComputeCommandEncoder(commandRecorder: commandRecorder, renderPass: computePass, passRecord: passRecord)
            computePass.execute(computeCommandEncoder: cce)
            cce.endEncoding()
            
        case let blitPass as BlitRenderPass:
            let bce = BlitCommandEncoder(commandRecorder: commandRecorder, renderPass: blitPass, passRecord: passRecord)
            blitPass.execute(blitCommandEncoder: bce)
            bce.endEncoding()
            
        case let externalPass as ExternalRenderPass:
            let ece = ExternalCommandEncoder(commandRecorder: commandRecorder, renderPass: externalPass, passRecord: passRecord)
            externalPass.execute(externalCommandEncoder: ece)
            ece.endEncoding()
            
        case let cpuPass as CPURenderPass:
            cpuPass.execute()
            
        default:
            fatalError("Unknown pass type for pass \(passRecord)")
        }
        
        passRecord.commands = commandRecorder.commands
        passRecord.commandRange = 0..<passRecord.commands.count
        passRecord.readResources = commandRecorder.readResources
        passRecord.writtenResources = commandRecorder.writtenResources
        passRecord.resourceUsages = commandRecorder.resourceUsages
        
        TaggedHeap.free(tag: renderPassScratchTag)
    }
    
    func fillUsedResourcesFromPass(passRecord: RenderPassRecord, threadIndex: Int) {
        let usageAllocator = TagAllocator.ThreadView(allocator: FrameGraph.resourceUsagesAllocator, threadIndex: threadIndex)
        
        passRecord.readResources = .init(allocator: .tagThreadView(usageAllocator))
        passRecord.writtenResources = .init(allocator: .tagThreadView(usageAllocator))
        
        for resource in passRecord.pass.writtenResources {
            resource._markAsUsed(frameGraphIndexMask: 1 << self.queue.index)
            passRecord.writtenResources.insert(resource)
        }
        for resource in passRecord.pass.readResources {
            resource._markAsUsed(frameGraphIndexMask: 1 << self.queue.index)
            passRecord.readResources.insert(resource)
        }
    }
    
    func evaluateResourceUsages(renderPasses: [RenderPassRecord]) {
        let jobManager = FrameGraph.jobManager
        
        for passRecord in renderPasses where passRecord.pass.passType == .cpu {
            if passRecord.pass.writtenResources.isEmpty {
                self.executePass(passRecord, threadIndex: jobManager.threadIndex)
            } else {
                let threadIndex = jobManager.threadIndex
                self.fillUsedResourcesFromPass(passRecord: passRecord, threadIndex: threadIndex)
            }
        }
        
        for passRecord in renderPasses where passRecord.pass.passType != .cpu {
            jobManager.dispatchPassJob { [unowned(unsafe) jobManager] in
                let threadIndex = jobManager.threadIndex
                
                if passRecord.pass.writtenResources.isEmpty {
                    self.executePass(passRecord, threadIndex: threadIndex)
                } else {
                    let threadIndex = jobManager.threadIndex
                    self.fillUsedResourcesFromPass(passRecord: passRecord, threadIndex: threadIndex)
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
            
            if let targetPass = renderPasses[i].pass as? DrawRenderPass {
                // First process all passes that can't share the same render target...
                for j in (0..<i).reversed() where dependencyTable.dependency(from: i, on: j) != .none {
                    if let otherPass = renderPasses[j].pass as? DrawRenderPass, RenderTargetDescriptor.descriptorsAreMergeable(passA: otherPass, passB: targetPass) {
                    } else {
                        computeDependencyOrdering(passIndex: j, dependencyTable: dependencyTable, renderPasses: renderPasses, addedToList: &addedToList, activePasses: &activePasses)
                    }
                }
                
                // ... and then process those which can.
                for j in (0..<i).reversed() where dependencyTable.dependency(from: i, on: j) != .none {
                    if let otherPass = renderPasses[j].pass as? DrawRenderPass, RenderTargetDescriptor.descriptorsAreMergeable(passA: otherPass, passB: targetPass) {
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
        
        for (i, pass) in renderPasses.enumerated() {
            for resource in pass.writtenResources {
                assert(resource._usesPersistentRegistry || resource.transientRegistryIndex == self.transientRegistryIndex, "Transient resource \(resource) associated with another FrameGraph is being used in this FrameGraph.")
                assert(resource.isValid, "Resource \(resource) is invalid but is used in the current frame.")
                
                if resource.flags.intersection([.persistent, .windowHandle, .historyBuffer, .externalOwnership]) != [] {
                    passHasSideEffects[i] = true
                }
                
                if resource.flags.contains(.windowHandle) {
                    pass.usesWindowTexture = true
                }
                
                for (j, otherPass) in renderPasses.enumerated().dropFirst(i + 1) {
                    if otherPass.readResources.contains(resource) {
                        dependencyTable.setDependency(from: j, on: i, to: .execution)
                    }
                    if otherPass.writtenResources.contains(resource), dependencyTable.dependency(from: j, on: i) != .execution {
                        dependencyTable.setDependency(from: j, on: i, to: .ordering) // since the relative ordering of writes matters
                    }
                }
            }
            
            for resource in pass.readResources {
                assert(resource._usesPersistentRegistry || resource.transientRegistryIndex == self.transientRegistryIndex, "Transient resource \(resource) associated with another FrameGraph is being used in this FrameGraph.")
                assert(resource.isValid, "Resource \(resource) is invalid but is used in the current frame.")
            }
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
        
        let allocator = TagAllocator.ThreadView(allocator: FrameGraph.resourceUsagesAllocator, threadIndex: 0)
        
        // Index the commands for each pass in a sequential manner for the entire frame.
        var commandCount = 0
        for (i, passRecord) in activePasses.enumerated() {
            precondition(passRecord.isActive)
            
            let startCommandIndex = commandCount
            commandCount += passRecord.commands.count
            
            passRecord.passIndex = i
            passRecord.commandRange = startCommandIndex..<commandCount
            assert(passRecord.commandRange!.count > 0)
            
            for (resource, resourceUsage) in passRecord.resourceUsages where resourceUsage.stages != .cpuBeforeRender {
                assert(resource.isValid)
                self.usedResources.insert(resource)
                
                var resourceUsage = resourceUsage
                resourceUsage.commandRange = Range(uncheckedBounds: (resourceUsage.commandRange.lowerBound + startCommandIndex, resourceUsage.commandRange.upperBound + startCommandIndex))
                resource.usages.mergeOrAppendUsage(resourceUsage, resource: resource, allocator: allocator)
            }
            
            passRecord.resourceUsages = nil
        }
        
        // Compilation is finished, so reset that tag.
        TaggedHeap.free(tag: FrameGraphTagType.frameGraphCompilation.tag)
        
        return (activePasses, activePassDependencies)
    }

    @available(*, deprecated, renamed: "onSubmission")
    public func waitForGPUSubmission(_ function: @escaping () -> Void) {
        self.submissionNotifyQueue.append(function)
    }
    
    public func onSubmission(_ function: @escaping () -> Void) {
        self.submissionNotifyQueue.append(function)
    }
    
    public func onGPUCompletion(_ function: @escaping () -> Void) {
        self.completionNotifyQueue.append(function)
    }
    
    public func execute(onSubmission: (() -> Void)? = nil, onGPUCompletion: (() -> Void)? = nil) {
        if GPUResourceUploader.frameGraph !== self {
            GPUResourceUploader.flush() // Ensure all GPU resources have been uploaded.
        }
        
        guard !self.renderPasses.isEmpty else {
            onSubmission?()
            onGPUCompletion?()
            
            self.submissionNotifyQueue.forEach { $0() }
            self.submissionNotifyQueue.removeAll(keepingCapacity: true)
            
            self.completionNotifyQueue.forEach { $0() }
            self.completionNotifyQueue.removeAll(keepingCapacity: true)
            
            return
        }
        
        FrameGraph.activeFrameGraphSemaphore.wait()
        FrameGraph.activeFrameGraph = self
        defer {
            FrameGraph.activeFrameGraph = nil
            FrameGraph.activeFrameGraphSemaphore.signal()
        }
        
        let jobManager = FrameGraph.jobManager
        
        self.context.accessSemaphore.wait()
        
        FrameGraph.resourceUsagesAllocator = TagAllocator(tag: FrameGraphTagType.resourceUsageNodes.tag, threadCount: jobManager.threadCount)
        FrameGraph.executionAllocator = TagAllocator(tag: FrameGraphTagType.frameGraphExecution.tag, threadCount: jobManager.threadCount)
        
        let threadCount = jobManager.threadCount
        
        FrameGraph.threadUnmanagedReferences = (0..<threadCount).map { i in
            return ExpandingBuffer(allocator: AllocatorType(TagAllocator.ThreadView(allocator: FrameGraph.executionAllocator, threadIndex: i)), initialCapacity: 0)
        }
        
        self.context.beginFrameResourceAccess()
        
        let (passes, dependencyTable) = self.compile(renderPasses: self.renderPasses)
        
        let completionQueue = self.completionNotifyQueue
        let completion: (Double) -> Void = { gpuTime in
            self.lastFrameGPUTime = gpuTime
            
            let completionTime = DispatchTime.now().uptimeNanoseconds
            let elapsed = completionTime - self.previousFrameCompletionTime
            self.previousFrameCompletionTime = completionTime
            self.lastFrameRenderDuration = Double(elapsed) * 1e-6
            //            print("Frame \(currentFrameIndex) completed in \(self.lastFrameRenderDuration)ms.")
            
            onGPUCompletion?()
            completionQueue.forEach { $0() }
        }
        
        self.context.executeFrameGraph(passes: passes, usedResources: self.usedResources, dependencyTable: dependencyTable, completion: completion)
        
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
        self.completionNotifyQueue.removeAll(keepingCapacity: true)
        
        self.reset()
        
        FrameGraph.globalSubmissionIndex += 1
    }
    
    private func reset() {
        TransientBufferRegistry.instances[transientRegistryIndex].clear()
        TransientTextureRegistry.instances[transientRegistryIndex].clear()
        TransientArgumentBufferRegistry.instances[transientRegistryIndex].clear()
        TransientArgumentBufferArrayRegistry.instances[transientRegistryIndex].clear()
        
        PersistentTextureRegistry.instance.clear(afterFrameGraph: self)
        PersistentBufferRegistry.instance.clear(afterFrameGraph: self)
        PersistentArgumentBufferRegistry.instance.clear(afterFrameGraph: self)
        PersistentArgumentBufferArrayRegistry.instance.clear()
        
        FrameGraph.threadUnmanagedReferences.forEach { unmanagedReferences in
            for reference in unmanagedReferences {
                reference.release()
            }
            unmanagedReferences.removeAll()
        }
        FrameGraph.threadUnmanagedReferences = nil
        
        self.renderPasses.removeAll(keepingCapacity: true)
        self.usedResources.removeAll(keepingCapacity: true)
        
        FrameGraph.executionAllocator = nil
        FrameGraph.resourceUsagesAllocator = nil
        
        TaggedHeap.free(tag: FrameGraphTagType.frameGraphExecution.tag)
        TaggedHeap.free(tag: FrameGraphTagType.resourceUsageNodes.tag)
    }
}
