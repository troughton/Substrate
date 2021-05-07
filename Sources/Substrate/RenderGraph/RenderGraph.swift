//
//  RenderGraph.swift
//  Substrate
//
//  Created by Thomas Roughton on 17/03/17.
//
//

import Foundation
import SubstrateUtilities
import Atomics

struct EmptyResult: Sendable {}

public protocol RenderPass : AnyObject {
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
    func execute(renderCommandEncoder: RenderCommandEncoder) async
    
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
    func execute(computeCommandEncoder: ComputeCommandEncoder) async
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
    func execute(blitCommandEncoder: BlitCommandEncoder) async
}

extension BlitRenderPass {
    @inlinable
    public var passType : RenderPassType {
        return .blit
    }
}

public protocol ExternalRenderPass : RenderPass {
    func execute(externalCommandEncoder: ExternalCommandEncoder) async
}

extension ExternalRenderPass {
    @inlinable
    public var passType : RenderPassType {
        return .external
    }
}

public protocol ReflectableDrawRenderPass : DrawRenderPass {
    
    associatedtype Reflection : RenderPassReflection
    func execute(renderCommandEncoder: TypedRenderCommandEncoder<Reflection>) async
}

extension ReflectableDrawRenderPass {
    @inlinable
    public func execute(renderCommandEncoder: RenderCommandEncoder) async {
        return await self.execute(renderCommandEncoder: TypedRenderCommandEncoder(encoder: renderCommandEncoder))
    }
}

public protocol ReflectableComputeRenderPass : ComputeRenderPass {
    associatedtype Reflection : RenderPassReflection
    func execute(computeCommandEncoder: TypedComputeCommandEncoder<Reflection>) async
}

extension ReflectableComputeRenderPass {
    @inlinable
    public func execute(computeCommandEncoder: ComputeCommandEncoder) async {
        return await self.execute(computeCommandEncoder: TypedComputeCommandEncoder(encoder: computeCommandEncoder))
    }
}

final class CallbackDrawRenderPass : DrawRenderPass {
    public let name : String
    public let renderTargetDescriptor: RenderTargetDescriptor
    public let colorClearOperations: [ColorClearOperation]
    public let depthClearOperation: DepthClearOperation
    public let stencilClearOperation: StencilClearOperation
    public let executeFunc : (RenderCommandEncoder) async -> Void
    
    public init(name: String, descriptor: RenderTargetDescriptor,
                colorClearOperations: [ColorClearOperation],
                depthClearOperation: DepthClearOperation,
                stencilClearOperation: StencilClearOperation,
                execute: @escaping (RenderCommandEncoder) async -> Void) {
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
    
    public func execute(renderCommandEncoder: RenderCommandEncoder) async {
        await self.executeFunc(renderCommandEncoder)
    }
}

final class ReflectableCallbackDrawRenderPass<R : RenderPassReflection> : ReflectableDrawRenderPass {
    public let name : String
    public let renderTargetDescriptor: RenderTargetDescriptor
    public let colorClearOperations: [ColorClearOperation]
    public let depthClearOperation: DepthClearOperation
    public let stencilClearOperation: StencilClearOperation
    public let executeFunc : (TypedRenderCommandEncoder<R>) async -> Void
    
    public init(name: String, descriptor: RenderTargetDescriptor,
                colorClearOperations: [ColorClearOperation],
                depthClearOperation: DepthClearOperation,
                stencilClearOperation: StencilClearOperation,
                reflection: R.Type, execute: @escaping (TypedRenderCommandEncoder<R>) async -> Void) {
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
    
    public func execute(renderCommandEncoder: TypedRenderCommandEncoder<R>) async {
        await self.executeFunc(renderCommandEncoder)
    }
}

final class CallbackComputeRenderPass : ComputeRenderPass {
    public let name : String
    public let executeFunc : (ComputeCommandEncoder) async -> Void
    
    public init(name: String, execute: @escaping (ComputeCommandEncoder) async -> Void) {
        self.name = name
        self.executeFunc = execute
    }
    
    public func execute(computeCommandEncoder: ComputeCommandEncoder) async {
        await self.executeFunc(computeCommandEncoder)
    }
}

final class ReflectableCallbackComputeRenderPass<R : RenderPassReflection> : ReflectableComputeRenderPass {
    public let name : String
    public let executeFunc : (TypedComputeCommandEncoder<R>) async -> Void
    
    public init(name: String, reflection: R.Type, execute: @escaping (TypedComputeCommandEncoder<R>) async -> Void) {
        self.name = name
        self.executeFunc = execute
    }
    
    public func execute(computeCommandEncoder: TypedComputeCommandEncoder<R>) async {
        await self.executeFunc(computeCommandEncoder)
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
    public let executeFunc : (BlitCommandEncoder) async -> Void
    
    public init(name: String, execute: @escaping (BlitCommandEncoder) async -> Void) {
        self.name = name
        self.executeFunc = execute
    }
    
    public func execute(blitCommandEncoder: BlitCommandEncoder) async {
        await self.executeFunc(blitCommandEncoder)
    }
}

final class CallbackExternalRenderPass : ExternalRenderPass {
    public let name : String
    public let executeFunc : (ExternalCommandEncoder) async -> Void
    
    public init(name: String, execute: @escaping (ExternalCommandEncoder) async -> Void) {
        self.name = name
        self.executeFunc = execute
    }
    
    public func execute(externalCommandEncoder: ExternalCommandEncoder) async {
        await self.executeFunc(externalCommandEncoder)
    }
}

public enum RenderPassType {
    case cpu
    case draw
    case compute
    case blit
    case external // Using things like Metal Performance Shaders.
}

// A draw render pass that caches the properties of an actual DrawRenderPass
// but that doesn't retain any of the member variables.
@usableFromInline
final class ProxyDrawRenderPass: DrawRenderPass {
    @usableFromInline let name: String
    @usableFromInline let renderTargetDescriptor: RenderTargetDescriptor
    @usableFromInline let colorClearOperations: [ColorClearOperation]
    @usableFromInline let depthClearOperation: DepthClearOperation
    @usableFromInline let stencilClearOperation: StencilClearOperation
    
    init(_ renderPass: DrawRenderPass) {
        self.name = renderPass.name
        self.renderTargetDescriptor = renderPass.renderTargetDescriptor
        self.depthClearOperation = renderPass.depthClearOperation
        self.stencilClearOperation = renderPass.stencilClearOperation
        self.colorClearOperations = (0..<renderTargetDescriptor.colorAttachments.count).map {
            renderPass.colorClearOperation(attachmentIndex: $0)
        }
    }
    
    @usableFromInline func colorClearOperation(attachmentIndex: Int) -> ColorClearOperation {
        return self.colorClearOperations.dropFirst(attachmentIndex).first ?? .keep
    }
    
    @usableFromInline func execute(renderCommandEncoder: RenderCommandEncoder) {
        fatalError()
    }
}

@usableFromInline
final class RenderPassRecord {
    @usableFromInline let name: String
    @usableFromInline let type: RenderPassType
    @usableFromInline var pass : RenderPass!
    @usableFromInline var commands : ChunkArray<RenderGraphCommand>! = nil
    @usableFromInline var readResources : HashSet<Resource>! = nil
    @usableFromInline var writtenResources : HashSet<Resource>! = nil
    @usableFromInline var resourceUsages : ChunkArray<(Resource, ResourceUsage)>! = nil
    @usableFromInline var unmanagedReferences : ChunkArray<Unmanaged<AnyObject>>! = nil
    @usableFromInline /* internal(set) */ var commandRange : Range<Int>?
    @usableFromInline /* internal(set) */ var passIndex : Int
    @usableFromInline /* internal(set) */ var isActive : Bool
    @usableFromInline /* internal(set) */ var usesWindowTexture : Bool = false
    @usableFromInline /* internal(set) */ var hasSideEffects : Bool = false
    
    init(pass: RenderPass, passIndex: Int) {
        self.name = pass.name
        self.type = pass.passType
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

public protocol RenderGraphContext : AnyObject {
    
}

struct RenderGraphExecutionResult {
    var gpuTime: Double
}

// _RenderGraphContext is an internal-only protocol to ensure dispatch gets optimised in whole-module optimisation mode.
protocol _RenderGraphContext : RenderGraphContext {
    var transientRegistryIndex : Int { get }
    var accessSemaphore : AsyncSemaphore { get }
    var renderGraphQueue: Queue { get }
    func beginFrameResourceAccess() async // Access is ended when a renderGraph is submitted.
    func executeRenderGraph(passes: [RenderPassRecord], usedResources: Set<Resource>, dependencyTable: DependencyTable<DependencyType>) async -> Task.Handle<RenderGraphExecutionResult, Never>
}

public enum RenderGraphTagType : UInt64 {
    static let renderGraphTag : UInt64 = 0xf9322463 // CRC-32 of "RenderGraph"
    
    /// Scratch data that exists only while a render pass is being executed.
    case renderPassExecution
    
    /// Data that exists while the RenderGraph is being compiled.
    case renderGraphCompilation
    
    /// Data that exists until the RenderGraph has been executed on the backend.
    case renderGraphExecution
    
    /// Resource usage nodes – exists until the RenderGraph has been executed on the backend.
    case resourceUsageNodes
    
    public static func renderPassExecutionTag(passIndex: Int) -> TaggedHeap.Tag {
        return (RenderGraphTagType.renderGraphTag << 32) | (RenderGraphTagType.renderPassExecution.rawValue << 16) | TaggedHeap.Tag(passIndex)
    }
    
    public var tag : TaggedHeap.Tag {
        assert(self != .renderPassExecution)
        let tag = (RenderGraphTagType.renderGraphTag << 32) | (self.rawValue << 16)
        return tag
    }
}

@globalActor
actor RenderGraphSharedActor {
    static let shared = RenderGraphSharedActor()
}

public final class RenderGraph {
    static let activeRenderGraphLock = AsyncSpinLock()
    public private(set) static var activeRenderGraph : RenderGraph? = nil
    
    private var renderPasses : [RenderPassRecord] = []
    private var renderPassLock = SpinLock()
    private var usedResources : Set<Resource> = []
    
    public static private(set) var globalSubmissionIndex : ManagedAtomic<UInt64> = .init(0)
    private var previousFrameCompletionTime : UInt64 = 0
    private var _lastGraphCPUTime = 1000.0 / 60.0
    private var _lastGraphGPUTime = 1000.0 / 60.0
    
    var submissionNotifyQueue = [() async -> Void]()
    var completionNotifyQueue = [() async -> Void]()
    let context : _RenderGraphContext
    
    public let transientRegistryIndex : Int
    
    public init(inflightFrameCount: Int, transientBufferCapacity: Int = 16384, transientTextureCapacity: Int = 16384, transientArgumentBufferArrayCapacity: Int = 1024) {
        
        self.transientRegistryIndex = TransientRegistryManager.allocate()
        
        TransientBufferRegistry.instances[self.transientRegistryIndex].initialise(capacity: transientBufferCapacity)
        TransientTextureRegistry.instances[self.transientRegistryIndex].initialise(capacity: transientTextureCapacity)
        TransientArgumentBufferArrayRegistry.instances[self.transientRegistryIndex].initialise(capacity: transientArgumentBufferArrayCapacity)
        
        switch RenderBackend._backend.api {
        #if canImport(Metal)
        case .metal:
            self.context = RenderGraphContextImpl<MetalBackend>(backend: RenderBackend._backend as! MetalBackend, inflightFrameCount: inflightFrameCount, transientRegistryIndex: transientRegistryIndex)
        #endif
        #if canImport(Vulkan)
        case .vulkan:
            self.context = RenderGraphContextImpl<VulkanBackend>(backend: RenderBackend._backend as! VulkanBackend, inflightFrameCount: inflightFrameCount, transientRegistryIndex: transientRegistryIndex)
        #endif
        }
    }
    
    deinit {
        TransientRegistryManager.free(self.transientRegistryIndex)
        self.renderPassLock.deinit()
    }
    
    @actorIndependent
    public var queue: Queue {
        return self.context.renderGraphQueue
    }
    
    @actorIndependent
    public var activeRenderGraphMask: ActiveRenderGraphMask {
        return 1 << self.queue.index
    }
    
    public var hasEnqueuedPasses: Bool {
        return !self.renderPasses.isEmpty
    }
    
    public func lastGraphDurations() async -> (cpuTime: Double, gpuTime: Double) {
        return (self._lastGraphCPUTime, self._lastGraphGPUTime)
    }
    
    /// Useful for creating resources that may be used later in the frame.
    public func insertEarlyBlitPass(name: String,
                                    _ execute: @escaping (BlitCommandEncoder) async -> Void) async {
        self.renderPassLock.withLock {
            self.renderPasses.insert(RenderPassRecord(pass: CallbackBlitRenderPass(name: name, execute: execute),
                                                      passIndex: 0), at: 0)
        }
    }
    
    public func insertEarlyBlitPass(_ pass: BlitRenderPass) {
        self.renderPassLock.withLock {
            self.renderPasses.insert(RenderPassRecord(pass: pass,
                                                      passIndex: 0), at: 0)
        }
    }
    
    public func addPass(_ renderPass: RenderPass) {
        self.renderPassLock.withLock {
            self.renderPasses.append(RenderPassRecord(pass: renderPass, passIndex: self.renderPasses.count))
        }
    }
    
    public func addBlitCallbackPass(file: String = #fileID, line: Int = #line,
                                    _ execute: @escaping (BlitCommandEncoder) async -> Void) {
        self.addPass(CallbackBlitRenderPass(name: "Anonymous Blit Pass at \(file):\(line)", execute: execute))
    }
    
    public func addBlitCallbackPass(name: String,
                                    _ execute: @escaping (BlitCommandEncoder) async -> Void) {
        self.addPass(CallbackBlitRenderPass(name: name, execute: execute))
    }
    
    public func addClearPass(file: String = #fileID, line: Int = #line,
                             renderTarget: RenderTargetDescriptor,
                             colorClearOperations: [ColorClearOperation] = [],
                             depthClearOperation: DepthClearOperation = .keep,
                             stencilClearOperation: StencilClearOperation = .keep) {
        self.addPass(CallbackDrawRenderPass(name: "Clear Pass at \(file):\(line)", descriptor: renderTarget,
                                            colorClearOperations: colorClearOperations, depthClearOperation: depthClearOperation, stencilClearOperation: stencilClearOperation,
                                            execute: { _ in }))
    }
    
    public func addDrawCallbackPass(file: String = #fileID, line: Int = #line,
                                    descriptor: RenderTargetDescriptor,
                                    colorClearOperations: [ColorClearOperation] = [],
                                    depthClearOperation: DepthClearOperation = .keep,
                                    stencilClearOperation: StencilClearOperation = .keep,
                                    _ execute: @escaping (RenderCommandEncoder) async -> Void) {
        self.addPass(CallbackDrawRenderPass(name: "Anonymous Draw Pass at \(file):\(line)", descriptor: descriptor,
                                            colorClearOperations: colorClearOperations, depthClearOperation: depthClearOperation, stencilClearOperation: stencilClearOperation,
                                            execute: execute))
    }
    
    public func addDrawCallbackPass(name: String,
                                    descriptor: RenderTargetDescriptor,
                                    colorClearOperations: [ColorClearOperation] = [],
                                    depthClearOperation: DepthClearOperation = .keep,
                                    stencilClearOperation: StencilClearOperation = .keep,
                                    _ execute: @escaping (RenderCommandEncoder) async -> Void) {
        self.addPass(CallbackDrawRenderPass(name: name, descriptor: descriptor,
                                            colorClearOperations: colorClearOperations, depthClearOperation: depthClearOperation, stencilClearOperation: stencilClearOperation,
                                            execute: execute))
    }
    
    public func addDrawCallbackPass<R>(file: String = #fileID, line: Int = #line,
                                       descriptor: RenderTargetDescriptor,
                                       colorClearOperations: [ColorClearOperation] = [],
                                       depthClearOperation: DepthClearOperation = .keep,
                                       stencilClearOperation: StencilClearOperation = .keep,
                                       reflection: R.Type,
                                       _ execute: @escaping (TypedRenderCommandEncoder<R>) async -> Void) {
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
                                       _ execute: @escaping (TypedRenderCommandEncoder<R>) async -> Void) {
        self.addPass(ReflectableCallbackDrawRenderPass(name: name, descriptor: descriptor,
                                                       colorClearOperations: colorClearOperations, depthClearOperation: depthClearOperation, stencilClearOperation: stencilClearOperation,
                                                       reflection: reflection, execute: execute))
    }
    
    public func addComputeCallbackPass(file: String = #fileID, line: Int = #line,
                                       _ execute: @escaping (ComputeCommandEncoder) async -> Void) {
        self.addPass(CallbackComputeRenderPass(name: "Anonymous Compute Pass at \(file):\(line)", execute: execute))
    }
    
    public func addComputeCallbackPass(name: String,
                                       _ execute: @escaping (ComputeCommandEncoder) async -> Void) {
        self.addPass(CallbackComputeRenderPass(name: name, execute: execute))
    }
    
    public func addComputeCallbackPass<R>(file: String = #fileID, line: Int = #line,
                                          reflection: R.Type,
                                          _ execute: @escaping (TypedComputeCommandEncoder<R>) async -> Void) {
        self.addPass(ReflectableCallbackComputeRenderPass(name: "Anonymous Compute Pass at \(file):\(line)", reflection: reflection, execute: execute))
    }
    
    public func addComputeCallbackPass<R>(name: String,
                                          reflection: R.Type,
                                          _ execute: @escaping (TypedComputeCommandEncoder<R>) async -> Void) {
        self.addPass(ReflectableCallbackComputeRenderPass(name: name, reflection: reflection, execute: execute))
    }
    
    public func addCPUCallbackPass(file: String = #fileID, line: Int = #line,
                                   _ execute: @escaping () -> Void) {
        self.addPass(CallbackCPURenderPass(name: "Anonymous CPU Pass at \(file):\(line)", execute: execute))
    }
    
    public func addCPUCallbackPass(name: String,
                                   _ execute: @escaping () -> Void) {
        self.addPass(CallbackCPURenderPass(name: name, execute: execute))
    }
    
    public func addExternalCallbackPass(file: String = #fileID, line: Int = #line,
                                        _ execute: @escaping (ExternalCommandEncoder) async -> Void) {
        self.addPass(CallbackExternalRenderPass(name: "Anonymous External Encoder Pass at \(file):\(line)", execute: execute))
    }
    
    public func addExternalCallbackPass(name: String,
                                        _ execute: @escaping (ExternalCommandEncoder) async -> Void) {
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
    
    func executePass(_ passRecord: RenderPassRecord, executionAllocator: TagAllocator, resourceUsageAllocator: TagAllocator) async {
        let renderPassScratchTag = RenderGraphTagType.renderPassExecutionTag(passIndex: passRecord.passIndex)
        
        let commandRecorder = RenderGraphCommandRecorder(renderGraphTransientRegistryIndex: self.transientRegistryIndex,
                                                         renderGraphQueue: self.queue,
                                                         renderPassScratchAllocator: ThreadLocalTagAllocator(tag: renderPassScratchTag),
                                                         renderGraphExecutionAllocator: executionAllocator,
                                                         resourceUsageAllocator: resourceUsageAllocator)
        
        
        
        switch passRecord.pass {
        case let drawPass as DrawRenderPass:
            let rce = RenderCommandEncoder(commandRecorder: commandRecorder, renderPass: drawPass, passRecord: passRecord)
            await drawPass.execute(renderCommandEncoder: rce)
            rce.endEncoding()
            
        case let computePass as ComputeRenderPass:
            let cce = ComputeCommandEncoder(commandRecorder: commandRecorder, renderPass: computePass, passRecord: passRecord)
            await computePass.execute(computeCommandEncoder: cce)
            cce.endEncoding()
            
        case let blitPass as BlitRenderPass:
            let bce = BlitCommandEncoder(commandRecorder: commandRecorder, renderPass: blitPass, passRecord: passRecord)
            await blitPass.execute(blitCommandEncoder: bce)
            bce.endEncoding()
            
        case let externalPass as ExternalRenderPass:
            let ece = ExternalCommandEncoder(commandRecorder: commandRecorder, renderPass: externalPass, passRecord: passRecord)
            await externalPass.execute(externalCommandEncoder: ece)
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
        passRecord.unmanagedReferences = commandRecorder.unmanagedReferences
        
        // Remove our reference to the render pass once we've executed it so it can
        // release any references to member variables.
        if passRecord.type == .draw {
            passRecord.pass = ProxyDrawRenderPass(passRecord.pass as! DrawRenderPass)
        } else {
            passRecord.pass = nil
        }
        
        TaggedHeap.free(tag: renderPassScratchTag)
    }
    
    @actorIndependent
    func fillUsedResourcesFromPass(passRecord: RenderPassRecord, resourceUsageAllocator: TagAllocator) {
        passRecord.readResources = .init(allocator: .tag(resourceUsageAllocator))
        passRecord.writtenResources = .init(allocator: .tag(resourceUsageAllocator))
        
        for resource in passRecord.pass.writtenResources {
            resource.markAsUsed(activeRenderGraphMask: 1 << self.queue.index)
            passRecord.writtenResources.insert(resource.baseResource ?? resource)
        }
        for resource in passRecord.pass.readResources {
            resource.markAsUsed(activeRenderGraphMask: 1 << self.queue.index)
            passRecord.readResources.insert(resource.baseResource ?? resource)
        }
    }
    
    @RenderGraphSharedActor
    func evaluateResourceUsages(renderPasses: [RenderPassRecord], executionAllocator: TagAllocator, resourceUsagesAllocator: TagAllocator) async {
        for passRecord in renderPasses where passRecord.pass.passType == .cpu {
            if passRecord.pass.writtenResources.isEmpty {
                await self.executePass(passRecord,
                                       executionAllocator: executionAllocator,
                                       resourceUsageAllocator: executionAllocator)
            } else {
                self.fillUsedResourcesFromPass(passRecord: passRecord, resourceUsageAllocator: executionAllocator)
            }
        }
        
        await withTaskGroup(of: EmptyResult.self) { group async -> Void in
            for passRecord in renderPasses where passRecord.type != .cpu {
                _ = await group.add { () async -> EmptyResult in
                    if passRecord.pass.writtenResources.isEmpty {
                        await self.executePass(passRecord,
                                               executionAllocator: executionAllocator,
                                               resourceUsageAllocator: executionAllocator)
                    } else {
                        self.fillUsedResourcesFromPass(passRecord: passRecord, resourceUsageAllocator: executionAllocator)
                    }
                    
                    return EmptyResult()
                }
            }
        }
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
    
    @RenderGraphSharedActor
    func compile() async -> ([RenderPassRecord], DependencyTable<DependencyType>, Set<Resource>) {
        let renderPasses = self.renderPasses
        
        let resourceUsagesAllocator = TagAllocator(tag: RenderGraphTagType.resourceUsageNodes.tag)
        let executionAllocator = TagAllocator(tag: RenderGraphTagType.renderGraphExecution.tag)
        
        renderPasses.enumerated().forEach { $1.passIndex = $0 } // We may have inserted early blit passes, so we need to set the pass indices now.
        
        await self.evaluateResourceUsages(renderPasses: renderPasses, executionAllocator: executionAllocator, resourceUsagesAllocator: resourceUsagesAllocator)
        
        var dependencyTable = DependencyTable<DependencyType>(capacity: renderPasses.count, defaultValue: .none)
        var passHasSideEffects = [Bool](repeating: false, count: renderPasses.count)
        
        
        for (i, pass) in renderPasses.enumerated() {
            for resource in pass.writtenResources {
                assert(resource._usesPersistentRegistry || resource.transientRegistryIndex == self.transientRegistryIndex, "Transient resource \(resource) associated with another RenderGraph is being used in this RenderGraph.")
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
                assert(resource._usesPersistentRegistry || resource.transientRegistryIndex == self.transientRegistryIndex, "Transient resource \(resource) associated with another RenderGraph is being used in this RenderGraph.")
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
                await self.executePass(passRecord,
                                       executionAllocator: executionAllocator,
                                       resourceUsageAllocator: executionAllocator)
            }
            if passRecord.type == .cpu || passRecord.commandRange!.count == 0 {
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
        
        let allocator = TagAllocator.ThreadView(allocator: resourceUsagesAllocator, threadIndex: 0)
        
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
                if let baseResource = resource.baseResource {
                    self.usedResources.insert(baseResource)
                }
                
                var resourceUsage = resourceUsage
                resourceUsage.commandRange = Range(uncheckedBounds: (resourceUsage.commandRange.lowerBound + startCommandIndex, resourceUsage.commandRange.upperBound + startCommandIndex))
                resource.usages.mergeOrAppendUsage(resourceUsage, resource: resource, allocator: allocator)
            }
            
            passRecord.resourceUsages = nil
        }
        
        // Compilation is finished, so reset that tag.
        TaggedHeap.free(tag: RenderGraphTagType.renderGraphCompilation.tag)
        
        return (activePasses, activePassDependencies, self.usedResources)
    }
    
    @available(*, deprecated, renamed: "onSubmission")
    public func waitForGPUSubmission(_ function: @escaping () -> Void) async {
        self.submissionNotifyQueue.append(function)
    }
    
    public func onSubmission(_ function: @escaping () async -> Void) async {
        self.submissionNotifyQueue.append(function)
    }
    
    public func onGPUCompletion(_ function: @escaping () async -> Void) async {
        self.completionNotifyQueue.append(function)
    }
    
    /// Returns true if this RenderGraph already has the maximum number of GPU frames in-flight, and would have to wait
    /// for the ring buffers to become available before executing.
    public var hasMaximumFrameCountInFlight: Bool {
        if self.context.accessSemaphore.currentValue > 0 {
            return false
        }
        return true
    }
    
    @RenderGraphSharedActor
    private func executeOnSharedActor() async -> Task.Handle<RenderGraphExecutionResult, Never> {
        await self.context.accessSemaphore.wait()
        await self.context.beginFrameResourceAccess()
        RenderGraph.activeRenderGraph = self // FIXME: we should use task local values instead.
        defer { RenderGraph.activeRenderGraph = nil }
        
        let (passes, dependencyTable, usedResources) = await self.compile()
        
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        //        return autoreleasepool {
        return await self.context.executeRenderGraph(passes: passes, usedResources: usedResources, dependencyTable: dependencyTable)
        //        }
        #else
        return await self.context.executeRenderGraph(passes: passes, usedResources: usedResources, dependencyTable: dependencyTable)
        #endif
    }
    
    private func didCompleteRender(_ result: RenderGraphExecutionResult) async {
        self._lastGraphGPUTime = result.gpuTime
        
        let completionTime = DispatchTime.now().uptimeNanoseconds
        let elapsed = completionTime - self.previousFrameCompletionTime
        self.previousFrameCompletionTime = completionTime
        self._lastGraphCPUTime = Double(elapsed) * 1e-6
        //            print("Frame \(currentFrameIndex) completed in \(self.lastGraphCPUTime)ms.")
        
        self.completionNotifyQueue.forEach { observer in _ = Task.runDetached { await observer() } }
    }
    
    @RenderGraphSharedActor
    public func execute(onSubmission: (() async -> Void)? = nil, onGPUCompletion: (() async -> Void)? = nil) async {
        if GPUResourceUploader.renderGraph !== self {
            await GPUResourceUploader.flush() // Ensure all GPU resources have been uploaded.
        }
        
        self.renderPassLock.lock()
        let renderPasses = self.renderPasses
        self.renderPassLock.unlock()
        
        guard !renderPasses.isEmpty else {
            await onSubmission?()
            await onGPUCompletion?()
            
            self.submissionNotifyQueue.forEach { observer in _ = Task.runDetached { await observer() } }
            self.submissionNotifyQueue.removeAll(keepingCapacity: true)
            
            self.completionNotifyQueue.forEach { observer in _ = Task.runDetached { await observer() } }
            self.completionNotifyQueue.removeAll(keepingCapacity: true)
            
            return
        }
        
        await Self.activeRenderGraphLock.lock()
        
        let onCompletion = await self.executeOnSharedActor()
        await onSubmission?()
        
        _ = Task.runDetached {
            let result = await onCompletion.get()
            await self.didCompleteRender(result)
            await onGPUCompletion?()
        }
        
        // Make sure the RenderGraphCommands buffers are deinitialised before the tags are freed.
        renderPasses.forEach {
            $0.commands = nil
            $0.unmanagedReferences?.forEach {
                $0.release()
            }
        }
        
        self.submissionNotifyQueue.forEach { observer in _ = Task.runDetached { await observer() } }
        self.submissionNotifyQueue.removeAll(keepingCapacity: true)
        self.completionNotifyQueue.removeAll(keepingCapacity: true)
        
        self.reset()
        
        Self.activeRenderGraphLock.unlock()
        RenderGraph.globalSubmissionIndex.wrappingIncrement(ordering: .relaxed)
    }
    
    private func reset() {
        TransientBufferRegistry.instances[transientRegistryIndex].clear()
        TransientTextureRegistry.instances[transientRegistryIndex].clear()
        TransientArgumentBufferRegistry.instances[transientRegistryIndex].clear()
        TransientArgumentBufferArrayRegistry.instances[transientRegistryIndex].clear()
        
        PersistentTextureRegistry.instance.clear(afterRenderGraph: self)
        PersistentBufferRegistry.instance.clear(afterRenderGraph: self)
        PersistentArgumentBufferRegistry.instance.clear(afterRenderGraph: self)
        PersistentArgumentBufferArrayRegistry.instance.clear(afterRenderGraph: self)
        
        self.renderPasses.removeAll(keepingCapacity: true)
        self.usedResources.removeAll(keepingCapacity: true)
        
        TaggedHeap.free(tag: RenderGraphTagType.renderGraphExecution.tag)
        TaggedHeap.free(tag: RenderGraphTagType.resourceUsageNodes.tag)
    }
}
