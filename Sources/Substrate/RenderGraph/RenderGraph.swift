//
//  RenderGraph.swift
//  Substrate
//
//  Created by Thomas Roughton on 17/03/17.
//
//

import Foundation
import SubstrateUtilities

/// A render pass is the fundamental unit of work within Substrate. All GPU commands are submitted by enqueuing
/// render passes on a `RenderGraph` and then executing that `RenderGraph`.
///
/// There are five sub-protocols of `RenderPass` that a render pass can conform to: `DrawRenderPass`,
/// `ComputeRenderPass`, `CPURenderPass`, `BlitRenderPass`, and `ExternalRenderPass`.
/// When implementing a render pass, you should declare a conformance to one of the subprotocols rather than to
/// `RenderPass` directly.
///
/// Render passes are executed in a deferred manner. When you add a render pass to a render graph (via `RenderGraph.addPass()`,
/// you are requesting that the render graph call the `execute` method on the render pass when `RenderGraph.execute`
/// is called on the render graph. Passes may execute concurrently in any order, with the exception of `CPURenderPass` passes, which are
/// always executed in the order they were submitted.
///
/// - SeeAlso: `RenderGraph`
/// - SeeAlso: `DrawRenderPass`
/// - SeeAlso: `ComputeRenderPass`
/// - SeeAlso: `BlitRenderPass`
/// - SeeAlso: `ExternalRenderPass`
/// - SeeAlso: `CPURenderPass`
///
public protocol RenderPass : AnyObject {
    /// The debug name for the pass.
    var name : String { get }
    
    /// Render passes can optionally declare a list of resources that are read and written by the pass.
    /// When `writtenResources` is non-empty, execution of the pass is delayed until it is determined
    /// that some other pass has a dependency on a resource within `writtenResources`. If no other pass
    /// reads from any of the resources this pass writes to, the pass' `execute` method will never be called.
    /// This is useful for conditionally avoiding CPU work performed within the `execute` method.
    ///
    /// A pass can implicitly declare dependencies on other passes by including resources written by those passes within
    /// its `readResources` list.
    ///
    /// If  `writtenResources` contains persistent or history-buffer resources, a pass that writes to them is never culled
    /// even if no other pass reads from them within the same render graph.
    ///
    /// `readResources` is ignored if `writtenResources` is empty.
    var readResources : [Resource] { get }
    
    /// Render passes can optionally declare a list of resources that are read and written by the pass.
    /// When `writtenResources` is non-empty, execution of the pass is delayed until it is determined
    /// that some other pass has a dependency on a resource within `writtenResources`. If no other pass
    /// reads from any of the resources this pass writes to, the pass' `execute` method will never be called.
    /// This is useful for conditionally avoiding CPU work performed within the `execute` method.
    ///
    /// If  `writtenResources` contains persistent or history-buffer resources, a pass that writes to them is never culled
    /// even if no other pass reads from them within the same render graph.
    var writtenResources : [Resource] { get }
}

extension RenderPass {
    public var name: String {
        return String(reflecting: type(of: self))
    }
    
    public var readResources : [Resource] { return [] }
    public var writtenResources : [Resource] { return [] }
}

/// A `DrawRenderPass` is any pass that uses the GPU's raster pipeline to draw to some number of render targets.
/// Typically, a `DrawRenderPass` would consist of setting a vertex and fragment shader, binding some number of shader resources,
/// and then drawing some primitives.
public protocol DrawRenderPass : RenderPass {
    /// A description of the render target to render to for this render pass.
    /// A render target consists of some number of colour attachments and zero or one depth and stencil attachments.
    /// Each attachment may additionally specify a _resolve_ attachment for use in MSAA resolve.
    ///
    /// Passes that share compatible render target descriptors (with no conflicting attachments) may be merged by the render graph
    /// to benefit performance, although this should have no observable change in behaviour.
    ///
    /// - SeeAlso: `RenderTargetDescriptor`
    var renderTargetDescriptor : RenderTargetDescriptor { get }
    
    /// `execute` is called by the render graph to allow a `DrawRenderPass` to encode GPU work for the render pass.
    /// It may be called concurrently with any other (non-CPU) render pass, but will be executed in submission order on the GPU.
    ///
    /// - Parameter renderCommandEncoder: A draw render pass uses the passed-in `RenderCommandEncoder`
    /// to set GPU state and enqueue rendering commands.
    ///
    /// - SeeAlso: `RenderCommandEncoder`
    func execute(renderCommandEncoder: RenderCommandEncoder)
    
    /// The operation to perform on each render target attachment at the start of the render pass.
    ///
    /// - Parameter attachmentIndex: The index of the attachment (within the
    /// `renderTargetDescriptor`'s `colorAttachments`array) to return the operation for.
    ///
    /// - Returns: The operation to perform on attachment `attachmentIndex` at the start
    /// of the render pass.
    func colorClearOperation(attachmentIndex: Int) -> ColorClearOperation
    
    /// The operation to perform on the depth attachment at the start of the render pass.
    /// Ignored if there is no depth attachment specified in the `renderTargetDescriptor`.
    var depthClearOperation: DepthClearOperation { get }
    
    /// The operation to perform on the stencil attachment at the start of the render pass.
    /// Ignored if there is no depth attachment specified in the `renderTargetDescriptor`.
    var stencilClearOperation: StencilClearOperation { get }
}

extension DrawRenderPass {
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

/// A `ComputeRenderPass` is any pass that uses the GPU's compute pipeline to perform arbitrary work through a series of sized dispatches.
public protocol ComputeRenderPass : RenderPass {
    /// `execute` is called by the render graph to allow a `ComputeRenderPass` to encode GPU work for the render pass.
    /// It may be called concurrently with any other (non-CPU) render pass, but will be executed in submission order on the GPU.
    ///
    /// - Parameter computeCommandEncoder: A compute render pass uses the passed-in `ComputeCommandEncoder`
    /// to set GPU state and enqueue dispatches.
    ///
    /// - SeeAlso: `ComputeCommandEncoder`
    func execute(computeCommandEncoder: ComputeCommandEncoder)
}

/// A `CPURenderPass` is a pass that does not encode any GPU work but may access GPU resources.
/// For example, a `CPURenderPass` might fill GPU-visible `Buffer`s with CPU-generated data.
public protocol CPURenderPass : RenderPass {
    /// `execute` is called by the render graph to allow a `CPURenderPass` to perform work that accesses GPU resources.
    /// It will be called in sequence order of the submission of `CPURenderPass` instances to the render graph.
    func execute()
}

/// A `BlitRenderPass` is a pass that uses GPU's blit/copy pipeline to copy data between GPU resources.
public protocol BlitRenderPass : RenderPass {
    /// `execute` is called by the render graph to allow a `BlitRenderPass` to encode GPU work for the render pass.
    /// It may be called concurrently with any other (non-CPU) render pass, but will be executed in submission order on the GPU.
    ///
    /// - Parameter blitCommandEncoder: A blit render pass uses the passed-in `BlitCommandEncoder`
    /// to copy data between GPU resources.
    ///
    /// - SeeAlso: `BlitCommandEncoder`
    func execute(blitCommandEncoder: BlitCommandEncoder)
}

/// An `ExternalRenderPass` is a pass that bypasses Substrate to encode directly to an underlying GPU command buffer.
public protocol ExternalRenderPass : RenderPass {
    /// `execute` is called by the render graph to allow an `ExternalRenderPass` to encode arbitrary GPU work for the render pass.
    /// It may be called concurrently with any other (non-CPU) render pass, but will be executed in submission order on the GPU.
    ///
    /// - Parameter externalCommandEncoder: An external render pass uses the passed-in `ExternalCommandEncoder`
    /// to encode arbitrary GPU work.
    ///
    /// - SeeAlso: `ExternalCommandEncoder`
    func execute(externalCommandEncoder: ExternalCommandEncoder)
}

/// An `AccelerationRenderPass` is a pass that can encode commands to build or modify acceleration structures on hardware that
/// supports one of the GPU raytracing APIs.
@available(macOS 11.0, iOS 14.0, *)
public protocol AccelerationStructureRenderPass : RenderPass {
    /// `execute` is called by the render graph to allow an `AccelerationStructureRenderPAss` to encode arbitrary acceleration structure commands for the render pass.
    /// It may be called concurrently with any other (non-CPU) render pass, but will be executed in submission order on the GPU.
    ///
    /// - Parameter accelerationStructureCommandEncoder: An external render pass uses the passed-in `AccelerationStructureCommandEncoder`
    /// to encode GPU work that builds or modifies an acceleration structure.
    ///
    /// - SeeAlso: `ExternalCommandEncoder`
    func execute(accelerationStructureCommandEncoder: AccelerationStructureCommandEncoder)
}

/// A `ReflectableDrawRenderPass` is a `DrawRenderPass` that has an associated `RenderPassReflection` type.
/// `RenderPassReflection` represents the reflection data from a compiled shader, and defines the resources,
/// shader functions, and pipeline constants used by a particular render pass. Substrate's `ShaderTool` will automatically
/// generate `RenderPassReflection`-conforming types for any shaders compiled using it.
///
/// `ReflectableRenderPass` instances are usually easier to write since much of the data that would normally need
/// to be manually specified is instead inferred from the shader code. They're also less error-prone: for example, renaming a variable in a shader
/// and then regenerating the `RenderPassReflection` (e.g. using `ShaderTool`) will result in compile-time errors in the Swift code,
/// enabling you to easily find and correct the errors.
///
/// - SeeAlso: `DrawRenderPass`
public protocol ReflectableDrawRenderPass : DrawRenderPass {
    associatedtype Reflection : RenderPassReflection
    
    /// `execute` is called by the render graph to allow a `ReflectableDrawRenderPass` to encode GPU work for the render pass.
    /// It may be called concurrently with any other (non-CPU) render pass.
    /// For passes conforming to `ReflectableDrawRenderPass`, this method should be implemented instead
    /// of `execute(renderCommandEncoder: RenderCommandEncoder)`.
    ///
    /// - Parameter renderCommandEncoder: A draw render pass uses the passed-in `RenderCommandEncoder`
    /// to set GPU state and enqueue rendering commands, configured by the `ReflectableDrawRenderPass`' associated
    /// `Reflection` type.
    ///
    /// - SeeAlso: `TypedRenderCommandEncoder`
    /// - SeeAlso: `RenderPassReflection`
    func execute(renderCommandEncoder: TypedRenderCommandEncoder<Reflection>)
}

extension ReflectableDrawRenderPass {
    @inlinable
    public func execute(renderCommandEncoder: RenderCommandEncoder) {
        return self.execute(renderCommandEncoder: TypedRenderCommandEncoder(encoder: renderCommandEncoder))
    }
}

/// A `ReflectableComputeRenderPass` is a `ComputeRenderPass` that has an associated `RenderPassReflection` type.
/// `RenderPassReflection` represents the reflection data from a compiled shader, and defines the resources,
/// shader functions, and pipeline constants used by a particular render pass. Substrate's `ShaderTool` will automatically
/// generate `RenderPassReflection`-conforming types for any shaders compiled using it.
///
/// `ReflectableRenderPass` instances are usually easier to write since much of the data that would normally need
/// to be manually specified is instead inferred from the shader code. They're also less error-prone: for example, renaming a variable in a shader
/// and then regenerating the `RenderPassReflection` (e.g. using `ShaderTool`) will result in compile-time errors in the Swift code,
/// enabling you to easily find and correct the errors.
///
/// - SeeAlso: `ComputeRenderPass`
public protocol ReflectableComputeRenderPass : ComputeRenderPass {
    associatedtype Reflection : RenderPassReflection
    
    /// `execute` is called by the render graph to allow a `ReflectableDrawRenderPass` to encode GPU work for the render pass.
    /// It may be called concurrently with any other (non-CPU) render pass.
    /// For passes conforming to `ReflectableComputeRenderPass`, this method should be implemented instead
    /// of `execute(computeCommandEncoder: ComputeCommandEncoder)`.
    ///
    /// - Parameter computeCommandEncoder: A compute render pass uses the passed-in `ComputeCommandEncoder`
    /// to set GPU state and enqueue dispatches.
    ///
    /// - SeeAlso: `TypedComputeCommandEncoder`
    /// - SeeAlso: `RenderPassReflection`
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
    
    public init(name: String, renderTarget: RenderTargetDescriptor,
                colorClearOperations: [ColorClearOperation],
                depthClearOperation: DepthClearOperation,
                stencilClearOperation: StencilClearOperation,
                execute: @escaping (RenderCommandEncoder) -> Void) {
        self.name = name
        self.renderTargetDescriptor = renderTarget
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
    
    public init(name: String, renderTarget: RenderTargetDescriptor,
                colorClearOperations: [ColorClearOperation],
                depthClearOperation: DepthClearOperation,
                stencilClearOperation: StencilClearOperation,
                reflection: R.Type, execute: @escaping (TypedRenderCommandEncoder<R>) -> Void) {
        self.name = name
        self.renderTargetDescriptor = renderTarget
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

@available(macOS 11.0, iOS 14.0, *)
final class CallbackAccelerationStructureRenderPass : AccelerationStructureRenderPass {
    public let name : String
    public let executeFunc : (AccelerationStructureCommandEncoder) -> Void
    
    public init(name: String, execute: @escaping (AccelerationStructureCommandEncoder) -> Void) {
        self.name = name
        self.executeFunc = execute
    }
    
    public func execute(accelerationStructureCommandEncoder: AccelerationStructureCommandEncoder) {
        self.executeFunc(accelerationStructureCommandEncoder)
    }
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

@usableFromInline enum RenderPassType {
    case cpu
    case draw
    case compute
    case blit
    case accelerationStructure
    case external // Using things like Metal Performance Shaders.
    
    init?(pass: RenderPass) {
        switch pass {
        case is DrawRenderPass:
            self = .draw
        case is ComputeRenderPass:
            self = .compute
        case is BlitRenderPass:
            self = .blit
        case is ExternalRenderPass:
            self = .external
        case is CPURenderPass:
            self = .cpu
        default:
            if #available(macOS 11.0, iOS 14.0, *), pass is AccelerationStructureRenderPass {
                self = .accelerationStructure
            } else {
                return nil
            }
        }
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
    @usableFromInline /* internal(set) */ var commandRange : Range<Int>?
    @usableFromInline /* internal(set) */ var passIndex : Int
    @usableFromInline /* internal(set) */ var isActive : Bool
    @usableFromInline /* internal(set) */ var usesWindowTexture : Bool = false
    @usableFromInline /* internal(set) */ var hasSideEffects : Bool = false
    
    init(pass: RenderPass, passIndex: Int) {
        self.name = pass.name
        self.type = RenderPassType(pass: pass)!
        self.pass = pass
        self.passIndex = passIndex
        self.commandRange = nil
        self.isActive = false
    }
}

@usableFromInline enum DependencyType {
    /// No dependency
    case none
    /// If the dependency is active, it must be executed first
    case ordering
    /// The dependency must always be executed
    case execution
    //    /// There is a transitive dependency by way of another pass
    //    case transitive
}

// _RenderGraphContext is an internal-only protocol to ensure dispatch gets optimised in whole-module optimisation mode.
protocol _RenderGraphContext : AnyObject {
    var queue: DispatchQueue { get }
    var transientRegistryIndex : Int { get }
    var accessSemaphore : DispatchSemaphore? { get }
    var renderGraphQueue: Queue { get }
    func beginFrameResourceAccess() // Access is ended when a renderGraph is submitted.
    func executeRenderGraph(passes: [RenderPassRecord], usedResources: Set<Resource>, dependencyTable: DependencyTable<DependencyType>, completion: @escaping (_ gpuTime: Double) -> Void)
}

@usableFromInline enum RenderGraphTagType : UInt64 {
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

public struct RenderGraphExecutionWaitToken {
    public let queue: Queue
    public let executionIndex: UInt64
    
    public func wait() {
        self.queue.waitForCommandCompletion(self.executionIndex)
    }
}

/// Each RenderGraph executes on its own GPU queue, although executions are synchronised by submission order.
public final class RenderGraph {
    
    public static var jobManager : RenderGraphJobManager = DefaultRenderGraphJobManager()
    
    static let activeRenderGraphSemaphore = DispatchSemaphore(value: 1)
    public private(set) static var activeRenderGraph : RenderGraph? = nil
    
    /// executionAllocator is used for allocations that last one execution of the RenderGraph.
    static var executionAllocator : TagAllocator! = nil
    
    /// resourceUsagesAllocator is used for resource usages, and lasts one execution of the RenderGraph.
    static var resourceUsagesAllocator : TagAllocator! = nil
    
    private static var threadUnmanagedReferences : [ExpandingBuffer<Unmanaged<AnyObject>>]! = nil
    
    private var renderPasses : [RenderPassRecord] = []
    private var usedResources : Set<Resource> = []
    
    public static private(set) var globalSubmissionIndex : UInt64 = 0
    private var previousFrameCompletionTime : UInt64 = 0
    public private(set) var lastGraphCPUTime = 1000.0 / 60.0
    public private(set) var lastGraphGPUTime = 1000.0 / 60.0
    
    var submissionNotifyQueue = [() -> Void]()
    var completionNotifyQueue = [() -> Void]()
    let context : _RenderGraphContext
    
    public let transientRegistryIndex : Int
    
    /// Creates a new RenderGraph instance. There may only be up to eight RenderGraph's at any given time.
    ///
    /// - Parameter inflightFrameCount: The maximum number of render graph submission that may be executing on the GPU at any given time; if there are `inflightFrameCount` submissions still pending or executing on the GPU at the time
    /// of a `RenderGraph.execute()` call, the CPU will wait until at least one of those submissions has completed.
    /// Commonly two (for double buffering) or three (for triple buffering).
    /// Note that each in-flight frame incurs a memory cost for any transient buffers that are shared with the CPU.
    ///
    /// - Parameter transientTextureCapacity: The maximum number of transient `Texture`s that can be used in a single `RenderGraph` submission.
    ///
    /// - Parameter transientBufferCapacity: The maximum number of transient `Buffer`s that can be used in a single `RenderGraph` submission.
    ///
    /// - Parameter transientArgumentBufferArrayCapacity: The maximum number of transient `ArgumentBufferArray`s that can be used in a single `RenderGraph` submission.
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
    }
    
    /// The logical command queue corresponding to this render graph.
    public var queue: Queue {
        return self.context.renderGraphQueue
    }
    
    public var activeRenderGraphMask: ActiveRenderGraphMask {
        return 1 << self.queue.index
    }
    
    @available(*, deprecated)
    public static func initialise() {
        
    }
    
    /// - Returns: whether there are any passes scheduled for execution in the next `RenderGraph.execute` call.
    public var hasEnqueuedPasses: Bool {
        return !self.renderPasses.isEmpty
    }
    
    /// Enqueue a blit render pass for execution before any other enqueued render passes.
    /// Useful for creating resources that may be used later in the frame.
    public func insertEarlyBlitPass(name: String,
                                    _ execute: @escaping (BlitCommandEncoder) -> Void)  {
        self.renderPasses.insert(RenderPassRecord(pass: CallbackBlitRenderPass(name: name, execute: execute),
                                                  passIndex: 0), at: 0)
    }
    
    /// Enqueue a blit render pass for execution before any other enqueued render passes.
    /// Useful for creating resources that may be used later in the frame.
    public func insertEarlyBlitPass(_ pass: BlitRenderPass)  {
        self.renderPasses.insert(RenderPassRecord(pass: pass,
                                                  passIndex: 0), at: 0)
    }
    
    /// Enqueue `renderPass` for execution at the next `RenderGraph.execute` call on this render graph.
    /// Passes will be executed by the GPU in the order they are enqueued, but may be executed out-of-order on the CPU if they
    /// are not `CPURenderPass`es.
    ///
    /// - Parameter renderPass: The pass to enqueue.
    public func addPass(_ renderPass: RenderPass)  {
        self.renderPasses.append(RenderPassRecord(pass: renderPass, passIndex: self.renderPasses.count))
    }
    
    /// Enqueue the blit operations performed in `execute` for execution at the next `RenderGraph.execute` call on this render graph.
    /// Passes will be executed by the GPU in the order they are enqueued, but may be executed out-of-order on the CPU.
    ///
    /// - Parameter execute: A closure to execute that will be passed a blit command encoder, where the caller can use the command
    /// encoder to encode GPU blit commands.
    public func addBlitCallbackPass(file: String = #fileID, line: Int = #line,
                                    _ execute: @escaping (BlitCommandEncoder) -> Void) {
        self.addPass(CallbackBlitRenderPass(name: "Anonymous Blit Pass at \(file):\(line)", execute: execute))
    }
    
    /// Enqueue the blit operations performed in `execute` for execution at the next `RenderGraph.execute` call on this render graph.
    /// Passes will be executed by the GPU in the order they are enqueued, but may be executed out-of-order on the CPU.
    ///
    /// - Parameter name: The name of the pass.
    /// - Parameter execute: A closure to execute that will be passed a blit command encoder, where the caller can use the command
    /// encoder to encode GPU blit commands.
    public func addBlitCallbackPass(name: String,
                                    _ execute: @escaping (BlitCommandEncoder) -> Void) {
        self.addPass(CallbackBlitRenderPass(name: name, execute: execute))
    }
    
    /// Enqueue a draw render pass that does nothing other than clear the passed-in render target according to the specified operations.
    ///
    /// - Parameter renderTarget: The render target descriptor for the render targets to clear.
    /// - Parameter colorClearOperation: An array of color clear operations corresponding to the elements in `renderTarget`'s `colorAttachments` array.
    /// - Parameter depthClearOperation: The operation to perform on the render target's depth attachment, if present.
    /// - Parameter stencilClearOperation: The operation to perform on the render target's stencil attachment, if present.
    public func addClearPass(file: String = #fileID, line: Int = #line,
                             renderTarget: RenderTargetDescriptor,
                             colorClearOperations: [ColorClearOperation] = [],
                             depthClearOperation: DepthClearOperation = .keep,
                             stencilClearOperation: StencilClearOperation = .keep) {
        self.addPass(CallbackDrawRenderPass(name: "Clear Pass at \(file):\(line)", renderTarget: renderTarget,
                                            colorClearOperations: colorClearOperations, depthClearOperation: depthClearOperation, stencilClearOperation: stencilClearOperation,
                                            execute: { _ in }))
    }
    
    /// Enqueue a draw render pass comprised of the specified render operations in `execute` and the provided clear operations.
    ///
    /// - Parameter renderTarget: The render target descriptor for the render targets to clear.
    /// - Parameter colorClearOperation: An array of color clear operations corresponding to the elements in `renderTarget`'s `colorAttachments` array.
    /// - Parameter depthClearOperation: The operation to perform on the render target's depth attachment, if present.
    /// - Parameter stencilClearOperation: The operation to perform on the render target's stencil attachment, if present.
    /// - Parameter execute: A closure to execute that will be passed a render command encoder, where the caller can use the command
    /// encoder to encode GPU rendering commands.
    ///
    /// - SeeAlso: `addDrawCallbackPass(file:line:renderTarget:colorClearOperations:depthClearOperation:stencilClearOperation:reflection:execute:)`
    public func addDrawCallbackPass(file: String = #fileID, line: Int = #line,
                                    renderTarget: RenderTargetDescriptor,
                                    colorClearOperations: [ColorClearOperation] = [],
                                    depthClearOperation: DepthClearOperation = .keep,
                                    stencilClearOperation: StencilClearOperation = .keep,
                                    _ execute: @escaping (RenderCommandEncoder) -> Void) {
        self.addPass(CallbackDrawRenderPass(name: "Anonymous Draw Pass at \(file):\(line)", renderTarget: renderTarget,
                                            colorClearOperations: colorClearOperations, depthClearOperation: depthClearOperation, stencilClearOperation: stencilClearOperation,
                                            execute: execute))
    }
    
    @available(*, deprecated, renamed:"addDrawCallbackPass(file:line:renderTarget:colorClearOperations:depthClearOperation:stencilClearOperation:execute:)")
    public func addDrawCallbackPass(file: String = #fileID, line: Int = #line,
                                    descriptor: RenderTargetDescriptor,
                                    colorClearOperations: [ColorClearOperation] = [],
                                    depthClearOperation: DepthClearOperation = .keep,
                                    stencilClearOperation: StencilClearOperation = .keep,
                                    _ execute: @escaping (RenderCommandEncoder) -> Void) {
        self.addDrawCallbackPass(file: file, line: line, renderTarget: descriptor, colorClearOperations: colorClearOperations, depthClearOperation: depthClearOperation, stencilClearOperation: stencilClearOperation, execute)
    }
    
    /// Enqueue a draw render pass comprised of the specified render operations in `execute` and the provided clear operations.
    ///
    /// - Parameter name: The name of the pass.
    /// - Parameter renderTarget: The render target descriptor for the render targets to clear.
    /// - Parameter colorClearOperation: An array of color clear operations corresponding to the elements in `renderTarget`'s `colorAttachments` array.
    /// - Parameter depthClearOperation: The operation to perform on the render target's depth attachment, if present.
    /// - Parameter stencilClearOperation: The operation to perform on the render target's stencil attachment, if present.
    /// - Parameter execute: A closure to execute that will be passed a render command encoder, where the caller can use the command
    /// encoder to encode GPU rendering commands.
    ///
    /// - SeeAlso: `addDrawCallbackPass(name:renderTarget:colorClearOperations:depthClearOperation:stencilClearOperation:reflection:execute:)`
    public func addDrawCallbackPass(name: String,
                                    renderTarget: RenderTargetDescriptor,
                                    colorClearOperations: [ColorClearOperation] = [],
                                    depthClearOperation: DepthClearOperation = .keep,
                                    stencilClearOperation: StencilClearOperation = .keep,
                                    _ execute: @escaping (RenderCommandEncoder) -> Void) {
        self.addPass(CallbackDrawRenderPass(name: name, renderTarget: renderTarget,
                                            colorClearOperations: colorClearOperations, depthClearOperation: depthClearOperation, stencilClearOperation: stencilClearOperation,
                                            execute: execute))
    }
    
    @available(*, deprecated, renamed:"addDrawCallbackPass(name:renderTarget:colorClearOperations:depthClearOperation:stencilClearOperation:execute:)")
    public func addDrawCallbackPass(name: String,
                                    descriptor: RenderTargetDescriptor,
                                    colorClearOperations: [ColorClearOperation] = [],
                                    depthClearOperation: DepthClearOperation = .keep,
                                    stencilClearOperation: StencilClearOperation = .keep,
                                    _ execute: @escaping (RenderCommandEncoder) -> Void) {
        self.addDrawCallbackPass(name: name, renderTarget: descriptor, colorClearOperations: colorClearOperations, depthClearOperation: depthClearOperation, stencilClearOperation: stencilClearOperation, execute)
    }
    
    
    /// Enqueue a draw render pass comprised of the specified render operations in `execute` and the provided clear operations.
    ///
    /// - Parameter renderTarget: The render target descriptor for the render targets to clear.
    /// - Parameter colorClearOperation: An array of color clear operations corresponding to the elements in `renderTarget`'s `colorAttachments` array.
    /// - Parameter depthClearOperation: The operation to perform on the render target's depth attachment, if present.
    /// - Parameter stencilClearOperation: The operation to perform on the render target's stencil attachment, if present.
    /// - Parameter execute: A closure to execute that will be passed a render command encoder, where the caller can use the command
    /// encoder to encode GPU rendering commands.
    public func addDrawCallbackPass<R>(file: String = #fileID, line: Int = #line,
                                       renderTarget: RenderTargetDescriptor,
                                       colorClearOperations: [ColorClearOperation] = [],
                                       depthClearOperation: DepthClearOperation = .keep,
                                       stencilClearOperation: StencilClearOperation = .keep,
                                       reflection: R.Type,
                                       _ execute: @escaping (TypedRenderCommandEncoder<R>) -> Void) {
        self.addPass(ReflectableCallbackDrawRenderPass(name: "Anonymous Draw Pass at \(file):\(line)", renderTarget: renderTarget,
                                                       colorClearOperations: colorClearOperations, depthClearOperation: depthClearOperation, stencilClearOperation: stencilClearOperation,
                                                       reflection: reflection, execute: execute))
    }
    
    @available(*, deprecated, renamed:"addDrawCallbackPass(file:line:renderTarget:colorClearOperations:depthClearOperation:stencilClearOperation:reflection:execute:)")
    public func addDrawCallbackPass<R>(file: String = #fileID, line: Int = #line,
                                       descriptor: RenderTargetDescriptor,
                                       colorClearOperations: [ColorClearOperation] = [],
                                       depthClearOperation: DepthClearOperation = .keep,
                                       stencilClearOperation: StencilClearOperation = .keep,
                                       reflection: R.Type,
                                       _ execute: @escaping (TypedRenderCommandEncoder<R>) -> Void) {
        self.addDrawCallbackPass(file: file, line: line, renderTarget: descriptor, colorClearOperations: colorClearOperations, depthClearOperation: depthClearOperation, stencilClearOperation: stencilClearOperation, reflection: reflection, execute)
    }
    
    /// Enqueue a draw render pass comprised of the specified render operations in `execute` and the provided clear operations, using the render pass reflection specified in `reflection`.
    ///
    /// - Parameter name: The name of the pass.
    /// - Parameter renderTarget: The render target descriptor for the render targets to clear.
    /// - Parameter colorClearOperation: An array of color clear operations corresponding to the elements in `renderTarget`'s `colorAttachments` array.
    /// - Parameter depthClearOperation: The operation to perform on the render target's depth attachment, if present.
    /// - Parameter stencilClearOperation: The operation to perform on the render target's stencil attachment, if present.
    /// - Parameter reflection: The generated shader reflection for this render pass.
    /// - Parameter execute: A closure to execute that will be passed a render command encoder, where the caller can use the command
    /// encoder to encode GPU rendering commands.
    ///
    /// - SeeAlso: `ReflectableDrawRenderPass`
    public func addDrawCallbackPass<R>(name: String,
                                       renderTarget: RenderTargetDescriptor,
                                       colorClearOperations: [ColorClearOperation] = [],
                                       depthClearOperation: DepthClearOperation = .keep,
                                       stencilClearOperation: StencilClearOperation = .keep,
                                       reflection: R.Type,
                                       _ execute: @escaping (TypedRenderCommandEncoder<R>) -> Void) {
        self.addPass(ReflectableCallbackDrawRenderPass(name: name, renderTarget: renderTarget,
                                                       colorClearOperations: colorClearOperations, depthClearOperation: depthClearOperation, stencilClearOperation: stencilClearOperation,
                                                       reflection: reflection, execute: execute))
    }
    
    @available(*, deprecated, renamed:"addDrawCallbackPass(name:renderTarget:colorClearOperations:depthClearOperation:stencilClearOperation:reflection:execute:)")
    public func addDrawCallbackPass<R>(name: String,
                                       descriptor: RenderTargetDescriptor,
                                       colorClearOperations: [ColorClearOperation] = [],
                                       depthClearOperation: DepthClearOperation = .keep,
                                       stencilClearOperation: StencilClearOperation = .keep,
                                       reflection: R.Type,
                                       _ execute: @escaping (TypedRenderCommandEncoder<R>) -> Void) {
        self.addDrawCallbackPass(name: name, renderTarget: descriptor, colorClearOperations: colorClearOperations, depthClearOperation: depthClearOperation, stencilClearOperation: stencilClearOperation, reflection: reflection, execute)
    }

    /// Enqueue a compute render pass comprised of the specified compute/dispatch operations in `execute`.
    ///
    /// - Parameter execute: A closure to execute that will be passed a compute command encoder, where the caller can use the command
    /// encoder to encode commands for the GPU's compute pipeline.
    ///
    /// - SeeAlso: `addComputeCallbackPass(reflection:_:)`
    public func addComputeCallbackPass(file: String = #fileID, line: Int = #line,
                                       _ execute: @escaping (ComputeCommandEncoder) -> Void) {
        self.addPass(CallbackComputeRenderPass(name: "Anonymous Compute Pass at \(file):\(line)", execute: execute))
    }
    
    /// Enqueue a compute render pass comprised of the specified compute/dispatch operations in `execute`.
    ///
    /// - Parameter name: The name of the pass.
    /// - Parameter execute: A closure to execute that will be passed a compute command encoder, where the caller can use the command
    /// encoder to encode commands for the GPU's compute pipeline.
    ///
    /// - SeeAlso: `addComputeCallbackPass(name:reflection:_:)`
    public func addComputeCallbackPass(name: String,
                                       _ execute: @escaping (ComputeCommandEncoder) -> Void) {
        self.addPass(CallbackComputeRenderPass(name: name, execute: execute))
    }

    /// Enqueue a compute render pass comprised of the specified compute/dispatch operations in `execute`, using the render pass reflection specified in `reflection`.
    ///
    /// - Parameter reflection: The generated shader reflection for this render pass.
    /// - Parameter execute: A closure to execute that will be passed a compute command encoder, where the caller can use the command
    /// encoder to encode commands for the GPU's compute pipeline.
    ///
    /// - SeeAlso: `ReflectableComputeRenderPass`
    public func addComputeCallbackPass<R>(file: String = #fileID, line: Int = #line,
                                          reflection: R.Type,
                                          _ execute: @escaping (TypedComputeCommandEncoder<R>) -> Void) {
        self.addPass(ReflectableCallbackComputeRenderPass(name: "Anonymous Compute Pass at \(file):\(line)", reflection: reflection, execute: execute))
    }
    
    /// Enqueue a compute render pass comprised of the specified compute/dispatch operations in `execute`, using the render pass reflection specified in `reflection`.
    ///
    /// - Parameter name: The name of the pass.
    /// - Parameter reflection: The generated shader reflection for this render pass.
    /// - Parameter execute: A closure to execute that will be passed a compute command encoder, where the caller can use the command
    /// encoder to encode commands for the GPU's compute pipeline.
    ///
    /// - SeeAlso: `ReflectableComputeRenderPass`
    public func addComputeCallbackPass<R>(name: String,
                                          reflection: R.Type,
                                          _ execute: @escaping (TypedComputeCommandEncoder<R>) -> Void) {
        self.addPass(ReflectableCallbackComputeRenderPass(name: name, reflection: reflection, execute: execute))
    }
    
    /// Enqueue a CPU render pass comprised of the operations in `execute`.
    /// This enables you to access GPU resources such as transient buffers or textures associated with the render graph.
    ///
    /// - Parameter execute: A closure to execute during render graph execution.
    public func addCPUCallbackPass(file: String = #fileID, line: Int = #line,
                                   _ execute: @escaping () -> Void) {
        self.addPass(CallbackCPURenderPass(name: "Anonymous CPU Pass at \(file):\(line)", execute: execute))
    }
    
    /// Enqueue a CPU render pass comprised of the operations in `execute`.
    /// This enables you to access GPU resources such as transient buffers or textures associated with the render graph.
    ///
    /// - Parameter name: The name of the pass.
    /// - Parameter execute: A closure to execute during render graph execution.
    public func addCPUCallbackPass(name: String,
                                   _ execute: @escaping () -> Void) {
        self.addPass(CallbackCPURenderPass(name: name, execute: execute))
    }
    
    /// Enqueue an external render pass comprised of the GPU operations in `execute`.
    /// External render passes allow you to directly encode commands to the underlying GPU command buffer.
    ///
    /// - Parameter execute: A closure to execute that will be passed a external command encoder, where the caller can use the command
    /// encoder to encode commands directly to an underlying GPU command buffer.
    public func addExternalCallbackPass(file: String = #fileID, line: Int = #line,
                                        _ execute: @escaping (ExternalCommandEncoder) -> Void) {
        self.addPass(CallbackExternalRenderPass(name: "Anonymous External Encoder Pass at \(file):\(line)", execute: execute))
    }
    
    /// Enqueue an external render pass comprised of the GPU operations in `execute`.
    /// External render passes allow you to directly encode commands to the underlying GPU command buffer.
    ///
    /// - Parameter name: The name of the pass.
    /// - Parameter execute: A closure to execute that will be passed a external command encoder, where the caller can use the command
    /// encoder to encode commands directly to an underlying GPU command buffer.
    public func addExternalCallbackPass(name: String,
                                        _ execute: @escaping (ExternalCommandEncoder) -> Void) {
        self.addPass(CallbackExternalRenderPass(name: name, execute: execute))
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public func addAccelerationStructureCallbackPass(file: String = #fileID, line: Int = #line,
                                        _ execute: @escaping (AccelerationStructureCommandEncoder) -> Void) {
        self.addPass(CallbackAccelerationStructureRenderPass(name: "Anonymous Acceleration Structure Encoder Pass at \(file):\(line)", execute: execute))
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public func addAccelerationStructureCallbackPass(name: String,
                                        _ execute: @escaping (AccelerationStructureCommandEncoder) -> Void) {
        self.addPass(CallbackAccelerationStructureRenderPass(name: name, execute: execute))
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
        let unmanagedReferences = RenderGraph.threadUnmanagedReferences[threadIndex]
        
        let renderPassScratchTag = RenderGraphTagType.renderPassExecutionTag(passIndex: passRecord.passIndex)
        
        let commandRecorder = RenderGraphCommandRecorder(renderGraphTransientRegistryIndex: self.transientRegistryIndex,
                                                        renderGraphQueue: self.queue,
                                                        renderPassScratchAllocator: ThreadLocalTagAllocator(tag: renderPassScratchTag),
                                                        renderGraphExecutionAllocator: TagAllocator.ThreadView(allocator: RenderGraph.executionAllocator, threadIndex: threadIndex),
                                                        resourceUsageAllocator: TagAllocator.ThreadView(allocator: RenderGraph.resourceUsagesAllocator, threadIndex: threadIndex),
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
            if #available(macOS 11.0, iOS 14.0, *), let accelerationStructurePass = passRecord.pass as? AccelerationStructureRenderPass {
                let asce = AccelerationStructureCommandEncoder(commandRecorder: commandRecorder, accelerationStructureRenderPass: accelerationStructurePass, passRecord: passRecord)
                accelerationStructurePass.execute(accelerationStructureCommandEncoder: asce)
                asce.endEncoding()
            } else {
                fatalError("Unknown pass type for pass \(passRecord)")
            }
        }
        
        passRecord.commands = commandRecorder.commands
        passRecord.commandRange = 0..<passRecord.commands.count
        passRecord.readResources = commandRecorder.readResources
        passRecord.writtenResources = commandRecorder.writtenResources
        passRecord.resourceUsages = commandRecorder.resourceUsages
        
        // Remove our reference to the render pass once we've executed it so it can
        // release any references to member variables.
        if passRecord.type == .draw {
            passRecord.pass = ProxyDrawRenderPass(passRecord.pass as! DrawRenderPass)
        } else {
            passRecord.pass = nil
        }
        
        TaggedHeap.free(tag: renderPassScratchTag)
    }
    
    func fillUsedResourcesFromPass(passRecord: RenderPassRecord, threadIndex: Int) {
        let usageAllocator = TagAllocator.ThreadView(allocator: RenderGraph.resourceUsagesAllocator, threadIndex: threadIndex)
        
        passRecord.readResources = .init(allocator: .tagThreadView(usageAllocator))
        passRecord.writtenResources = .init(allocator: .tagThreadView(usageAllocator))
        
        for resource in passRecord.pass.writtenResources {
            resource.markAsUsed(activeRenderGraphMask: 1 << self.queue.index)
            passRecord.writtenResources.insert(resource.baseResource ?? resource)
        }
        for resource in passRecord.pass.readResources {
            resource.markAsUsed(activeRenderGraphMask: 1 << self.queue.index)
            passRecord.readResources.insert(resource.baseResource ?? resource)
        }
    }
    
    func evaluateResourceUsages(renderPasses: [RenderPassRecord]) {
        let jobManager = RenderGraph.jobManager
        
        for passRecord in renderPasses where passRecord.type == .cpu || passRecord.type == .accelerationStructure {
            // CPU render passes are guaranteed to be executed in order, and we have to execute acceleration structure passes in order since they may modify the AccelerationStructure's descriptor property.
            // FIXME: This may actually cause issues if we update AccelerationStructures multiple times in a single RenderGraph and use it in between, since all other passes will depend only on the resources declared in the last-updated descriptor.
            if passRecord.pass.writtenResources.isEmpty {
                self.executePass(passRecord, threadIndex: jobManager.threadIndex)
            } else {
                let threadIndex = jobManager.threadIndex
                self.fillUsedResourcesFromPass(passRecord: passRecord, threadIndex: threadIndex)
            }
        }
        
        for passRecord in renderPasses where passRecord.type != .cpu && passRecord.type != .accelerationStructure {
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
            
            if pass.type == .external {
                passHasSideEffects[i] = true
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
        
        let allocator = TagAllocator.ThreadView(allocator: RenderGraph.resourceUsagesAllocator, threadIndex: 0)
        
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
        
        return (activePasses, activePassDependencies)
    }

    @available(*, deprecated, renamed: "onSubmission")
    public func waitForGPUSubmission(_ function: @escaping () -> Void) {
        self.submissionNotifyQueue.append(function)
    }
    
    /// Enqueue `function` to be executed once the render graph is submitted to the GPU.
    public func onSubmission(_ function: @escaping () -> Void) {
        self.submissionNotifyQueue.append(function)
    }
    
    /// Enqueue `function` to be executed once the render graph has completed on the GPU.
    public func onGPUCompletion(_ function: @escaping () -> Void) {
        self.completionNotifyQueue.append(function)
    }
    
    /// Returns true if this RenderGraph already has the maximum number of GPU frames in-flight, and would have to wait
    /// for the ring buffers to become available before executing.
    public var hasMaximumFrameCountInFlight: Bool {
        if self.context.accessSemaphore?.wait(timeout: .now()) ?? .success == .success {
            self.context.accessSemaphore?.signal()
            return false
        }
        return true
    }
    
    /// Process the render passes that have been enqueued on this render graph through calls to `addPass()` or similar by culling passes that don't produce
    /// any read resources, calling `execute` on each pass, then submitting the encoded commands to the GPU for execution.
    /// If there are any operations enqueued on the `GPUResourceUploader`, those will be processed before any passes in this render graph.
    /// Only one render graph will execute at any given time, and operations between render graphs are synchronised in submission order.
    ///
    /// - Parameter onSubmission: an optional closure to execute once the render graph has been submitted to the GPU.
    /// - Parameter onGPUCompletion: an optional closure to execute once the render graph has completed executing on the GPU.
    @discardableResult
    public func execute() -> RenderGraphExecutionWaitToken {
        guard !self.renderPasses.isEmpty else {
            self.submissionNotifyQueue.forEach { $0() }
            self.submissionNotifyQueue.removeAll(keepingCapacity: true)
            
            self.completionNotifyQueue.forEach { $0() }
            self.completionNotifyQueue.removeAll(keepingCapacity: true)
            
            return RenderGraphExecutionWaitToken(queue: self.queue, executionIndex: self.queue.lastSubmittedCommand)
        }
        
        self.context.accessSemaphore?.wait()
        
        RenderGraph.activeRenderGraphSemaphore.wait()
        RenderGraph.activeRenderGraph = self
        defer {
            RenderGraph.activeRenderGraph = nil
            RenderGraph.activeRenderGraphSemaphore.signal()
        }
        
        return self.context.queue.sync {
            return self._execute()
        }
    }
    
    private func _execute() -> RenderGraphExecutionWaitToken {

        let jobManager = RenderGraph.jobManager
        
        RenderGraph.resourceUsagesAllocator = TagAllocator(tag: RenderGraphTagType.resourceUsageNodes.tag, threadCount: jobManager.threadCount)
        RenderGraph.executionAllocator = TagAllocator(tag: RenderGraphTagType.renderGraphExecution.tag, threadCount: jobManager.threadCount)
        
        let threadCount = jobManager.threadCount
        
        RenderGraph.threadUnmanagedReferences = (0..<threadCount).map { i in
            return ExpandingBuffer(allocator: AllocatorType(TagAllocator.ThreadView(allocator: RenderGraph.executionAllocator, threadIndex: i)), initialCapacity: 0)
        }
        
        self.context.beginFrameResourceAccess()
        
        let (passes, dependencyTable) = self.compile(renderPasses: self.renderPasses)
        
        let completionQueue = self.completionNotifyQueue
        let completion: (Double) -> Void = { gpuTime in
            self.lastGraphGPUTime = gpuTime
//            print("Frame completed in \(gpuTime)")
            
            let completionTime = DispatchTime.now().uptimeNanoseconds
            let elapsed = completionTime - self.previousFrameCompletionTime
            self.previousFrameCompletionTime = completionTime
            self.lastGraphCPUTime = Double(elapsed) * 1e-6
            //            print("Frame \(currentFrameIndex) completed in \(self.lastGraphCPUTime)ms.")
            
            completionQueue.forEach { $0() }
        }
        
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        autoreleasepool {
            self.context.executeRenderGraph(passes: passes, usedResources: self.usedResources, dependencyTable: dependencyTable, completion: completion)
        }
        #else
        self.context.executeRenderGraph(passes: passes, usedResources: self.usedResources, dependencyTable: dependencyTable, completion: completion)
        #endif
        
        // Make sure the RenderGraphCommands buffers are deinitialised before the tags are freed.
        passes.forEach {
            $0.commands = nil
        }
        
        self.renderPasses.forEach {
            $0.commands = nil
        }
        
        self.submissionNotifyQueue.forEach { $0() }
        self.submissionNotifyQueue.removeAll(keepingCapacity: true)
        self.completionNotifyQueue.removeAll(keepingCapacity: true)
        
        self.reset()
        
        RenderGraph.globalSubmissionIndex += 1
        return RenderGraphExecutionWaitToken(queue: self.queue, executionIndex: self.queue.lastSubmittedCommand)
    }
    
    private func reset() {
        if transientRegistryIndex >= 0 {
            TransientBufferRegistry.instances[transientRegistryIndex].clear()
            TransientTextureRegistry.instances[transientRegistryIndex].clear()
            TransientArgumentBufferRegistry.instances[transientRegistryIndex].clear()
            TransientArgumentBufferArrayRegistry.instances[transientRegistryIndex].clear()
        }
            
        PersistentTextureRegistry.instance.clear(afterRenderGraph: self)
        PersistentBufferRegistry.instance.clear(afterRenderGraph: self)
        PersistentArgumentBufferRegistry.instance.clear(afterRenderGraph: self)
        PersistentArgumentBufferArrayRegistry.instance.clear(afterRenderGraph: self)
        HeapRegistry.instance.clear(afterRenderGraph: self)
        HazardTrackingGroupRegistry.instance.clear(afterRenderGraph: self)
        
        if #available(macOS 11.0, iOS 14.0, *) {
            AccelerationStructureRegistry.instance.clear(afterRenderGraph: self)
            VisibleFunctionTableRegistry.instance.clear(afterRenderGraph: self)
            IntersectionFunctionTableRegistry.instance.clear(afterRenderGraph: self)
        }
        
        RenderGraph.threadUnmanagedReferences.forEach { unmanagedReferences in
            for reference in unmanagedReferences {
                reference.release()
            }
            unmanagedReferences.removeAll()
        }
        RenderGraph.threadUnmanagedReferences = nil
        
        self.renderPasses.removeAll(keepingCapacity: true)
        self.usedResources.removeAll(keepingCapacity: true)
        
        RenderGraph.executionAllocator = nil
        RenderGraph.resourceUsagesAllocator = nil
        
        TaggedHeap.free(tag: RenderGraphTagType.renderGraphExecution.tag)
        TaggedHeap.free(tag: RenderGraphTagType.resourceUsageNodes.tag)
    }
}
