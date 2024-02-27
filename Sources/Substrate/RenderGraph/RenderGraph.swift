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
    /// FIXME:  this documentation is out of date.
    @ResourceUsageListBuilder
    var resources : [ResourceUsage] { get }
}

extension RenderPass {
    public var name: String {
        return String(reflecting: type(of: self))
    }
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
    var renderTargetsDescriptor : RenderTargetsDescriptor { get }
    
    @available(*, deprecated, renamed: "renderTargetsDescriptor")
    var renderTargetDescriptor : RenderTargetDescriptor { get }
    
    /// `execute` is called by the render graph to allow a `DrawRenderPass` to encode GPU work for the render pass.
    /// It may be called concurrently with any other (non-CPU) render pass, but will be executed in submission order on the GPU.
    ///
    /// - Parameter renderCommandEncoder: A draw render pass uses the passed-in `RenderCommandEncoder`
    /// to set GPU state and enqueue rendering commands.
    ///
    /// - SeeAlso: `RenderCommandEncoder`
    func execute(renderCommandEncoder: RenderCommandEncoder) async
    
    /// The operation to perform on each render target attachment at the start of the render pass.
    ///
    /// - Parameter attachmentIndex: The index of the attachment (within the
    /// `renderTargetsDescriptor`'s `colorAttachments`array) to return the operation for.
    ///
    /// - Returns: The operation to perform on attachment `attachmentIndex` at the start
    /// of the render pass.
    func colorClearOperation(attachmentIndex: Int) -> ColorClearOperation
    
    /// The operation to perform on the depth attachment at the start of the render pass.
    /// Ignored if there is no depth attachment specified in the `renderTargetsDescriptor`.
    var depthClearOperation: DepthClearOperation { get }
    
    /// The operation to perform on the stencil attachment at the start of the render pass.
    /// Ignored if there is no depth attachment specified in the `renderTargetsDescriptor`.
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
    
    @inlinable
    public var renderTargetsDescriptor : RenderTargetDescriptor {
        return self.renderTargetDescriptor
    }
    
    @available(*, deprecated, renamed: "renderTargetsDescriptor")
    @inlinable
    public var renderTargetDescriptor : RenderTargetDescriptor {
        return self.renderTargetsDescriptor
    }
    
    public var resources: [ResourceUsage] {
        return []
    }
    
    public var inferredResources: [ResourceUsage] {
        let declaredResources = self.resources.lazy.compactMap { resource in
            (resource.resource, resource)
        }
        let resources = [Resource: ResourceUsage](declaredResources, uniquingKeysWith: { a, b in
            var result = a
            result.type.formUnion(b.type)
            result.subresources.append(contentsOf: b.subresources)
            return result
        })
        
        var inferredResources = resources
        
        let renderTargets = self.renderTargetsDescriptor
        for attachment in renderTargets.colorAttachments {
            if let attachment = attachment, resources[Resource(attachment.texture)] == nil {
                let subresource = TextureSubresourceRange(slice: attachment.slice, mipLevel: attachment.level)
                
                inferredResources[Resource(attachment.texture), default: attachment.texture.as(.colorAttachment, subresources: [], stages: .fragment)]
                    .subresources.append(.textureSlices(subresource))
            }
        }
        
        if let attachment = renderTargets.depthAttachment, resources[Resource(attachment.texture)] == nil {
            let subresource = TextureSubresourceRange(slice: attachment.slice, mipLevel: attachment.level)
            
            inferredResources[Resource(attachment.texture), default: attachment.texture.as(.depthStencilAttachment, subresources: [], stages: [.vertex, .fragment])]
                .subresources.append(.textureSlices(subresource))
        }
        
        if let attachment = renderTargets.stencilAttachment, resources[Resource(attachment.texture)] == nil {
            let subresource = TextureSubresourceRange(slice: attachment.slice, mipLevel: attachment.level)
            
            inferredResources[Resource(attachment.texture), default: attachment.texture.as(.depthStencilAttachment, subresources: [], stages: [.vertex, .fragment])]
                .subresources.append(.textureSlices(subresource))
        }
        return Array(inferredResources.values)
    }
    
    func renderTargetsDescriptorForActiveAttachments(passIndex: Int) -> RenderTargetsDescriptor {
        // Filter out any unused attachments.
        var descriptor = self.renderTargetsDescriptor
        
        let isUsedAttachment: (Texture) -> Bool = { attachment in
            return attachment.usages.contains(where: {
                return $0.passIndex == passIndex && $0.usage.type.isRenderTarget
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
    func execute(computeCommandEncoder: ComputeCommandEncoder) async
}

/// A `CPURenderPass` is a pass that does not encode any GPU work but may access GPU resources.
/// For example, a `CPURenderPass` might fill GPU-visible `Buffer`s with CPU-generated data.
public protocol CPURenderPass : RenderPass {
    /// `execute` is called by the render graph to allow a `CPURenderPass` to perform work that accesses GPU resources.
    /// It will be called in sequence order of the submission of `CPURenderPass` instances to the render graph.
    func execute() async
}

extension CPURenderPass {
    /// `CPURenderPass`s that don't declare any used resources are always executed.
    public var resources: [ResourceUsage] {
        []
    }
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
    func execute(blitCommandEncoder: BlitCommandEncoder) async
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
    func execute(externalCommandEncoder: ExternalCommandEncoder) async
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
    func execute(renderCommandEncoder: TypedRenderCommandEncoder<Reflection>) async
}

extension ReflectableDrawRenderPass {
    @inlinable
    public func execute(renderCommandEncoder: RenderCommandEncoder) async {
        return await self.execute(renderCommandEncoder: TypedRenderCommandEncoder(encoder: renderCommandEncoder))
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
    func execute(computeCommandEncoder: TypedComputeCommandEncoder<Reflection>) async
}

extension ReflectableComputeRenderPass {
    @inlinable
    public func execute(computeCommandEncoder: ComputeCommandEncoder) async {
        return await self.execute(computeCommandEncoder: TypedComputeCommandEncoder(encoder: computeCommandEncoder))
    }
}

@usableFromInline
final class CallbackDrawRenderPass : DrawRenderPass {
    public let name : String
    public let renderTargetsDescriptor: RenderTargetsDescriptor
    public let colorClearOperations: [ColorClearOperation]
    public let depthClearOperation: DepthClearOperation
    public let stencilClearOperation: StencilClearOperation
    public let resources: [ResourceUsage]
    public let executeFunc : (RenderCommandEncoder) async -> Void
    
    public init(name: String,
                renderTargets: RenderTargetsDescriptor,
                colorClearOperations: [ColorClearOperation],
                depthClearOperation: DepthClearOperation,
                stencilClearOperation: StencilClearOperation,
                resources: [ResourceUsage],
                execute: @escaping @Sendable (RenderCommandEncoder) async -> Void) {
        self.name = name
        self.renderTargetsDescriptor = renderTargets
        self.colorClearOperations = colorClearOperations
        self.depthClearOperation = depthClearOperation
        self.stencilClearOperation = stencilClearOperation
        self.resources = resources
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

@usableFromInline
final class ReflectableCallbackDrawRenderPass<R : RenderPassReflection> : ReflectableDrawRenderPass {
    public let name : String
    public let renderTargetsDescriptor: RenderTargetsDescriptor
    public let colorClearOperations: [ColorClearOperation]
    public let depthClearOperation: DepthClearOperation
    public let stencilClearOperation: StencilClearOperation
    public let resources: [ResourceUsage]
    public let executeFunc : (TypedRenderCommandEncoder<R>) async -> Void
    
    public init(name: String, renderTargets: RenderTargetsDescriptor,
                colorClearOperations: [ColorClearOperation],
                depthClearOperation: DepthClearOperation,
                stencilClearOperation: StencilClearOperation,
                resources: [ResourceUsage],
                reflection: R.Type, execute: @escaping @Sendable (TypedRenderCommandEncoder<R>) async -> Void) {
        self.name = name
        self.renderTargetsDescriptor = renderTargets
        self.colorClearOperations = colorClearOperations
        self.depthClearOperation = depthClearOperation
        self.stencilClearOperation = stencilClearOperation
        self.resources = resources
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

@usableFromInline
final class CallbackComputeRenderPass : ComputeRenderPass {
    public let name : String
    public let resources: [ResourceUsage]
    public let executeFunc : (ComputeCommandEncoder) async -> Void
    
    public init(name: String,
                resources: [ResourceUsage],
                execute: @escaping @Sendable (ComputeCommandEncoder) async -> Void) {
        self.name = name
        self.resources = resources
        self.executeFunc = execute
    }
    
    public func execute(computeCommandEncoder: ComputeCommandEncoder) async {
        await self.executeFunc(computeCommandEncoder)
    }
}

@usableFromInline
final class ReflectableCallbackComputeRenderPass<R : RenderPassReflection> : ReflectableComputeRenderPass {
    public let name : String
    public let resources: [ResourceUsage]
    public let executeFunc : (TypedComputeCommandEncoder<R>) async -> Void
    
    public init(name: String,
                resources: [ResourceUsage],
                reflection: R.Type,
                execute: @escaping @Sendable (TypedComputeCommandEncoder<R>) async -> Void) {
        self.name = name
        self.resources = resources
        self.executeFunc = execute
    }
    
    public func execute(computeCommandEncoder: TypedComputeCommandEncoder<R>) async {
        await self.executeFunc(computeCommandEncoder)
    }
}

@usableFromInline
final class CallbackCPURenderPass : CPURenderPass {
    public let name : String
    public let resources: [ResourceUsage]
    public let executeFunc : @Sendable () async -> Void
    
    public init(name: String,
                resources: [ResourceUsage],
                execute: @escaping @Sendable () async -> Void) {
        self.name = name
        self.resources = resources
        self.executeFunc = execute
    }
    
    public func execute() async {
        await self.executeFunc()
    }
}

@usableFromInline
final class CallbackBlitRenderPass : BlitRenderPass {
    public let name : String
    public let resources: [ResourceUsage]
    public let executeFunc : (BlitCommandEncoder) async -> Void
    
    public init(name: String,
                resources: [ResourceUsage],
                execute: @escaping @Sendable (BlitCommandEncoder) async -> Void) {
        self.name = name
        self.resources = resources
        self.executeFunc = execute
    }
    
    public func execute(blitCommandEncoder: BlitCommandEncoder) async {
        await self.executeFunc(blitCommandEncoder)
    }
}

@usableFromInline
final class CallbackExternalRenderPass : ExternalRenderPass {
    public let name : String
    public let resources: [ResourceUsage]
    public let executeFunc : (ExternalCommandEncoder) async -> Void
    
    public init(name: String,
                resources: [ResourceUsage],
                execute: @escaping @Sendable (ExternalCommandEncoder) async -> Void) {
        self.name = name
        self.resources = resources
        self.executeFunc = execute
    }
    
    public func execute(externalCommandEncoder: ExternalCommandEncoder) async {
        await self.executeFunc(externalCommandEncoder)
    }
}

@available(macOS 11.0, iOS 14.0, *)
final class CallbackAccelerationStructureRenderPass : AccelerationStructureRenderPass {
    public let name : String
    public let resources: [ResourceUsage]
    public let executeFunc : (AccelerationStructureCommandEncoder) -> Void
    
    public init(name: String,
                resources: [ResourceUsage],
                execute: @escaping @Sendable (AccelerationStructureCommandEncoder) -> Void) {
        self.name = name
        self.resources = resources
        self.executeFunc = execute
    }
    
    public func execute(accelerationStructureCommandEncoder: AccelerationStructureCommandEncoder) {
        self.executeFunc(accelerationStructureCommandEncoder)
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
    
    var allStages: RenderStages {
        switch self {
        case .cpu:
            return .cpuBeforeRender
        case .draw:
            return [.vertex, .fragment, .mesh, .tile, .object]
        case .compute:
            return .compute
        case .blit:
            return .blit
        case .accelerationStructure:
            return .compute
        case .external:
            return []
        }
    }
}

@usableFromInline
struct RenderPassRecordImpl {
#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
    @usableFromInline let name: String
#endif
    @usableFromInline var pass : RenderPass!
    @usableFromInline var readResources : HashSet<Resource>! = nil
    @usableFromInline var writtenResources : HashSet<Resource>! = nil
    @usableFromInline /* internal(set) */ var passIndex : Int
    @usableFromInline /* internal(set) */ var isActive : Bool
    @usableFromInline /* internal(set) */ var usesWindowTexture : Bool = false
    @usableFromInline /* internal(set) */ var hasSideEffects : Bool = false
}

@usableFromInline
struct RenderPassRecord: Equatable, @unchecked Sendable {
    @usableFromInline let type: RenderPassType
    @usableFromInline let storage: UnsafeMutablePointer<RenderPassRecordImpl>
    
    init(pass: RenderPass, passIndex: Int) {
        self.type = RenderPassType(pass: pass)!
        
        self.storage = .allocate(capacity: 1)
        
#if SUBSTRATE_DISABLE_AUTOMATIC_LABELS
        self.storage.initialize(to: .init(pass: pass, passIndex: passIndex, isActive: false))
#else
        self.storage.initialize(to: .init(name: pass.name, pass: pass, passIndex: passIndex, isActive: false))
#endif
    }
    
    @usableFromInline
    static func ==(lhs: RenderPassRecord, rhs: RenderPassRecord) -> Bool {
        return lhs.storage == rhs.storage
    }
    
    func dispose() {
        self.storage.deinitialize(count: 1)
        self.storage.deallocate()
    }
    
#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
    @usableFromInline var name : String {
        get {
            return self.storage.pointee.name
        }
    }
#endif
    
    @usableFromInline var pass : RenderPass! {
        get {
            return self.storage.pointee.pass
        }
        nonmutating set {
            self.storage.pointee.pass = newValue
        }
    }
    
    @usableFromInline var readResources : HashSet<Resource>! {
        get {
            return self.storage.pointee.readResources
        }
        nonmutating set {
            self.storage.pointee.readResources = newValue
        }
    }
    
    @usableFromInline var writtenResources : HashSet<Resource>! {
        get {
            return self.storage.pointee.writtenResources
        }
        nonmutating set {
            self.storage.pointee.writtenResources = newValue
        }
    }
    
    @usableFromInline /* internal(set) */ var passIndex : Int {
        get {
            return self.storage.pointee.passIndex
        }
        nonmutating set {
            self.storage.pointee.passIndex = newValue
        }
    }
    
    @usableFromInline /* internal(set) */ var isActive : Bool {
        get {
            return self.storage.pointee.isActive
        }
        nonmutating set {
            self.storage.pointee.isActive = newValue
        }
    }
    
    @usableFromInline /* internal(set) */ var usesWindowTexture : Bool {
        get {
            return self.storage.pointee.usesWindowTexture
        }
        nonmutating set {
            self.storage.pointee.usesWindowTexture = newValue
        }
    }
    
    @usableFromInline /* internal(set) */ var hasSideEffects : Bool {
        get {
            return self.storage.pointee.hasSideEffects
        }
        nonmutating set {
            self.storage.pointee.hasSideEffects = newValue
        }
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

public struct RenderGraphSubmissionWaitToken: Sendable {
    public let queue: Queue
    public let submissionIndex: UInt64
    
    public func wait() async {
        await self.queue.waitForCommandSubmission(self.submissionIndex)
    }
}

public struct RenderGraphExecutionWaitToken: Sendable {
    public var queue: Queue
    public var executionIndex: UInt64
    
    public init(queue: Queue, executionIndex: UInt64) {
        self.queue = queue
        self.executionIndex = executionIndex
    }
    
    public func wait() async {
        guard self.queue.index < QueueRegistry.maxQueues else {
            return
        }
        await self.queue.waitForCommandCompletion(self.executionIndex)
    }
}

// _RenderGraphContext is an internal-only protocol to ensure dispatch gets optimised in whole-module optimisation mode.
protocol _RenderGraphContext : Actor {
    nonisolated var transientRegistry: (any BackendTransientResourceRegistry)? { get }
    nonisolated var transientRegistryIndex : Int { get }
    nonisolated var renderGraphQueue: Queue { get }
    func executeRenderGraph(_ renderGraph: RenderGraph, renderPasses: [RenderPassRecord], waitingFor gpuQueueWaitIndices: QueueCommandIndices, onSwapchainPresented: RenderGraph.SwapchainPresentedCallback?, onCompletion: @Sendable @escaping (_ queueCommandRange: Range<UInt64>) -> Void) async -> RenderGraphExecutionWaitToken
    func registerWindowTexture(for texture: Texture, swapchain: Swapchain) async
    func acquireResourceAccess() async
}

@usableFromInline enum RenderGraphTagType : UInt64 {
    static let renderGraphTag : UInt64 = 0xf9322463 // CRC-32 of "RenderGraph"
    
    /// Data that exists until the RenderGraph has been executed on the backend.
    case renderGraphExecution
    
    /// Resource usage nodes – exists until the RenderGraph has been executed on the backend.
    case resourceUsageNodes
    
    public var tag : TaggedHeap.Tag {
        let tag = (RenderGraphTagType.renderGraphTag << 32) | (self.rawValue << 16)
        return tag
    }
}

/// Each RenderGraph executes on its own GPU queue, although executions are synchronised by submission order.
public final class RenderGraph {
    @TaskLocal public static var activeRenderGraph : RenderGraph? = nil
    
    private var renderPasses : [RenderPassRecord] = []
    private let renderPassLock = SpinLock()
    private var usedResources : Set<Resource> = []
    
    public static private(set) var globalSubmissionIndex : ManagedAtomic<UInt64> = .init(0)
    
    private let frameTimingLock = SpinLock()
    private var previousFrameCompletionTime : UInt64 = 0
    private var _lastGraphCPUTime: RenderDuration = .zero
    private var lastGraphFirstCommand: UInt64 = .max
    private var lastGraphLastCommand: UInt64 = .max
    
    var submissionNotifyQueue = [@Sendable () async -> Void]()
    var completionNotifyQueue = [@Sendable () async -> Void]()
    var presentationNotifyQueue = [SwapchainPresentedCallback]()
    let context : _RenderGraphContext
    let inflightFrameCount: Int
    let currentInflightFrameCount: ManagedAtomic<Int> = .init(0)
    
    public let transientRegistryIndex : Int
#if SUBSTRATE_ENABLE_SIGNPOSTER
    static let signposter: Signposter = Signposter(subsystem: "com.substrate.rendergraph", category: "RenderGraph")
#else
    static let signposter: Signposter = .disabled
#endif
    private(set) var signpostID: SignpostID
    
    static let executionStream = TaskStream()
    
    /// Creates a new RenderGraph instance. There may only be up to eight RenderGraph's at any given time.
    ///
    /// - Parameter inflightFrameCount: The maximum number of render graph submission that may be executing on the GPU at any given time; if there are `inflightFrameCount` submissions still pending or executing on the GPU at the time
    /// of a `RenderGraph.execute()` call, the CPU will wait until at least one of those submissions has completed.
    /// Commonly two (for double buffering) or three (for triple buffering).
    /// Note that each in-flight frame incurs a memory cost for any transient buffers that are shared with the CPU.
    /// `inflightFrameCount` can be zero, in which case transient resources are disallowed for this render graph.
    ///
    /// - Parameter transientTextureCapacity: The maximum number of transient `Texture`s that can be used in a single `RenderGraph` submission.
    ///
    /// - Parameter transientBufferCapacity: The maximum number of transient `Buffer`s that can be used in a single `RenderGraph` submission.
    ///
    public init(inflightFrameCount: Int, transientBufferCapacity: Int = 16384, transientTextureCapacity: Int = 16384) {
        // If inflightFrameCount is 0, no transient resources are allowed.
        self.transientRegistryIndex = inflightFrameCount > 0 ? TransientRegistryManager.allocate() : -1
        self.inflightFrameCount = max(inflightFrameCount, 1)
        precondition(inflightFrameCount <= QueueRegistry.bufferedSubmissionCount)
        
        if self.transientRegistryIndex >= 0 {
            TransientBufferRegistry.instances[self.transientRegistryIndex].initialise(capacity: transientBufferCapacity)
            TransientTextureRegistry.instances[self.transientRegistryIndex].initialise(capacity: transientTextureCapacity)
        }
        
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
        
        self.signpostID = .invalid
        self.signpostID = Self.signposter.makeSignpostID(from: self)
    }
    
    deinit {
        if self.transientRegistryIndex > 0 {
            TransientRegistryManager.free(self.transientRegistryIndex)
        }
        self.renderPassLock.deinit()
        self.frameTimingLock.deinit()
    }
    
    /// The logical command queue corresponding to this render graph.
    public nonisolated var queue: Queue {
        return self.context.renderGraphQueue
    }
    
    public nonisolated var activeRenderGraphMask: ActiveRenderGraphMask {
        return 1 << self.queue.index
    }
    
    /// - Returns: whether there are any passes scheduled for execution in the next `RenderGraph.execute` call.
    public var hasEnqueuedPasses: Bool {
        return !self.renderPasses.isEmpty
    }
    
    public func lastGraphDurations() -> (cpu: RenderDuration, gpu: RenderDuration) {
        return self.frameTimingLock.withLock {
            let gpuStartTime = self.queue.gpuStartTime(for: self.lastGraphFirstCommand) ?? .init(uptimeNanoseconds: 0)
            let gpuEndTime = self.queue.gpuEndTime(for: self.lastGraphLastCommand) ?? gpuStartTime
            return (cpu: self._lastGraphCPUTime, gpu: .init(nanoseconds: gpuEndTime.uptimeNanoseconds - gpuStartTime.uptimeNanoseconds))
        }
    }
    
    /// Enqueue `renderPass` for execution at the next `RenderGraph.execute` call on this render graph.
    /// Passes will be executed by the GPU in the order they are enqueued, but may be executed out-of-order on the CPU if they
    /// are not `CPURenderPass`es.
    ///
    /// - Parameter renderPass: The pass to enqueue.
    public func addPass(_ renderPass: RenderPass) {
        self.renderPassLock.withLock {
            self.renderPasses.append(RenderPassRecord(pass: renderPass, passIndex: self.renderPasses.count))
        }
    }
    
    /// Enqueue the blit operations performed in `execute` for execution at the next `RenderGraph.execute` call on this render graph.
    /// Passes will be executed by the GPU in the order they are enqueued, but may be executed out-of-order on the CPU.
    ///
    /// - Parameter execute: A closure to execute that will be passed a blit command encoder, where the caller can use the command
    /// encoder to encode GPU blit commands.
    @inlinable
    public func addBlitCallbackPass(file: String = #fileID, line: Int = #line,
                                    @ResourceUsageListBuilder using resources: () -> [ResourceUsage],
                                    execute: @escaping @Sendable (BlitCommandEncoder) async -> Void) {
        self.addPass(CallbackBlitRenderPass(name: "Anonymous Blit Pass at \(file):\(line)", resources: resources(), execute: execute))
    }
    
    /// Enqueue the blit operations performed in `execute` for execution at the next `RenderGraph.execute` call on this render graph.
    /// Passes will be executed by the GPU in the order they are enqueued, but may be executed out-of-order on the CPU.
    ///
    /// - Parameter name: The name of the pass.
    /// - Parameter execute: A closure to execute that will be passed a blit command encoder, where the caller can use the command
    /// encoder to encode GPU blit commands.
    public func addBlitCallbackPass(name: String,
                                    @ResourceUsageListBuilder using resources: () -> [ResourceUsage],
                                    execute: @escaping @Sendable (BlitCommandEncoder) async -> Void) {
        self.addPass(CallbackBlitRenderPass(name: name, resources: resources(), execute: execute))
    }
    
    /// Enqueue a draw render pass that does nothing other than clear the passed-in render target according to the specified operations.
    ///
    /// - Parameter renderTargets: The render target descriptor for the render targets to clear.
    /// - Parameter colorClearOperation: An array of color clear operations corresponding to the elements in `renderTarget`'s `colorAttachments` array.
    /// - Parameter depthClearOperation: The operation to perform on the render target's depth attachment, if present.
    /// - Parameter stencilClearOperation: The operation to perform on the render target's stencil attachment, if present.
    @inlinable
    public func addClearPass(file: String = #fileID, line: Int = #line,
                             renderTargets: RenderTargetsDescriptor,
                             colorClearOperations: [ColorClearOperation] = [],
                             depthClearOperation: DepthClearOperation = .keep,
                             stencilClearOperation: StencilClearOperation = .keep) {
        var resources = [ResourceUsage]()
        for clearOperation in colorClearOperations {
            if case .clear = clearOperation, let attachment = renderTargets.colorAttachments[0] {
                resources.append(
                    attachment.texture.as(.colorAttachmentWrite,
                                          slice: attachment.slice, mipLevel: attachment.level,
                                          stages: .fragment)
                )
            }
        }
        
        if case .clear = depthClearOperation, let attachment = renderTargets.depthAttachment {
            resources.append(
                attachment.texture.as(.depthStencilAttachmentWrite,
                                      slice: attachment.slice, mipLevel: attachment.level,
                                      stages: .fragment)
            )
        }
        
        if case .clear = stencilClearOperation, let attachment = renderTargets.stencilAttachment {
            resources.append(
                attachment.texture.as(.depthStencilAttachmentWrite,
                                      slice: attachment.slice, mipLevel: attachment.level,
                                      stages: .fragment)
            )
        }
        
        self.addPass(CallbackDrawRenderPass(name: "Clear Pass at \(file):\(line)", renderTargets: renderTargets,
                                            colorClearOperations: colorClearOperations, depthClearOperation: depthClearOperation, stencilClearOperation: stencilClearOperation,
                                            resources: resources,
                                            execute: { _ in }))
    }
    
    /// Enqueue a draw render pass comprised of the specified render operations in `execute` and the provided clear operations.
    ///
    /// - Parameter renderTargets: The render target descriptor for the render targets to clear.
    /// - Parameter colorClearOperation: An array of color clear operations corresponding to the elements in `renderTarget`'s `colorAttachments` array.
    /// - Parameter depthClearOperation: The operation to perform on the render target's depth attachment, if present.
    /// - Parameter stencilClearOperation: The operation to perform on the render target's stencil attachment, if present.
    /// - Parameter execute: A closure to execute that will be passed a render command encoder, where the caller can use the command
    /// encoder to encode GPU rendering commands.
    ///
    /// - SeeAlso: `addDrawCallbackPass(file:line:renderTarget:colorClearOperations:depthClearOperation:stencilClearOperation:reflection:execute:)`
    @inlinable
    public func addDrawCallbackPass(file: String = #fileID, line: Int = #line,
                                    renderTargets: RenderTargetsDescriptor,
                                    colorClearOperations: [ColorClearOperation] = [],
                                    depthClearOperation: DepthClearOperation = .keep,
                                    stencilClearOperation: StencilClearOperation = .keep,
                                    @ResourceUsageListBuilder using resources: () -> [ResourceUsage] = { [] },
                                    execute: @escaping @Sendable (RenderCommandEncoder) async -> Void) {
        self.addPass(CallbackDrawRenderPass(name: "Anonymous Draw Pass at \(file):\(line)", renderTargets: renderTargets,
                                            colorClearOperations: colorClearOperations, depthClearOperation: depthClearOperation, stencilClearOperation: stencilClearOperation,
                                            resources: resources(),
                                            execute: execute))
    }
    
    /// Enqueue a draw render pass comprised of the specified render operations in `execute` and the provided clear operations.
    ///
    /// - Parameter name: The name of the pass.
    /// - Parameter renderTargets: The render target descriptor for the render targets to clear.
    /// - Parameter colorClearOperation: An array of color clear operations corresponding to the elements in `renderTarget`'s `colorAttachments` array.
    /// - Parameter depthClearOperation: The operation to perform on the render target's depth attachment, if present.
    /// - Parameter stencilClearOperation: The operation to perform on the render target's stencil attachment, if present.
    /// - Parameter execute: A closure to execute that will be passed a render command encoder, where the caller can use the command
    /// encoder to encode GPU rendering commands.
    ///
    /// - SeeAlso: `addDrawCallbackPass(name:renderTarget:colorClearOperations:depthClearOperation:stencilClearOperation:reflection:execute:)`
    public func addDrawCallbackPass(name: String,
                                    renderTargets: RenderTargetsDescriptor,
                                    colorClearOperations: [ColorClearOperation] = [],
                                    depthClearOperation: DepthClearOperation = .keep,
                                    stencilClearOperation: StencilClearOperation = .keep,
                                    @ResourceUsageListBuilder using resources: () -> [ResourceUsage] = { [] },
                                    execute: @escaping @Sendable (RenderCommandEncoder) async -> Void) {
        self.addPass(CallbackDrawRenderPass(name: name, renderTargets: renderTargets,
                                            colorClearOperations: colorClearOperations, depthClearOperation: depthClearOperation, stencilClearOperation: stencilClearOperation,
                                            resources: resources(),
                                            execute: execute))
    }
    
    
    /// Enqueue a draw render pass comprised of the specified render operations in `execute` and the provided clear operations.
    ///
    /// - Parameter renderTargets: The render targets descriptor for the render targets to clear.
    /// - Parameter colorClearOperation: An array of color clear operations corresponding to the elements in `renderTarget`'s `colorAttachments` array.
    /// - Parameter depthClearOperation: The operation to perform on the render target's depth attachment, if present.
    /// - Parameter stencilClearOperation: The operation to perform on the render target's stencil attachment, if present.
    /// - Parameter execute: A closure to execute that will be passed a render command encoder, where the caller can use the command
    /// encoder to encode GPU rendering commands.
    @inlinable
    public func addDrawCallbackPass<R>(file: String = #fileID, line: Int = #line,
                                       renderTargets: RenderTargetsDescriptor,
                                       colorClearOperations: [ColorClearOperation] = [],
                                       depthClearOperation: DepthClearOperation = .keep,
                                       stencilClearOperation: StencilClearOperation = .keep,
                                       @ResourceUsageListBuilder using resources: () -> [ResourceUsage] = { [] },
                                       reflection: R.Type,
                                       execute: @escaping @Sendable (TypedRenderCommandEncoder<R>) async -> Void) {
        self.addPass(ReflectableCallbackDrawRenderPass(name: "Anonymous Draw Pass at \(file):\(line)", renderTargets: renderTargets,
                                                       colorClearOperations: colorClearOperations, depthClearOperation: depthClearOperation, stencilClearOperation: stencilClearOperation,
                                                       resources: resources(),
                                                       reflection: reflection, execute: execute))
    }
    
    /// Enqueue a draw render pass comprised of the specified render operations in `execute` and the provided clear operations, using the render pass reflection specified in `reflection`.
    ///
    /// - Parameter name: The name of the pass.
    /// - Parameter renderTargets: The render target descriptor for the render targets to clear.
    /// - Parameter colorClearOperation: An array of color clear operations corresponding to the elements in `renderTarget`'s `colorAttachments` array.
    /// - Parameter depthClearOperation: The operation to perform on the render target's depth attachment, if present.
    /// - Parameter stencilClearOperation: The operation to perform on the render target's stencil attachment, if present.
    /// - Parameter reflection: The generated shader reflection for this render pass.
    /// - Parameter execute: A closure to execute that will be passed a render command encoder, where the caller can use the command
    /// encoder to encode GPU rendering commands.
    ///
    /// - SeeAlso: `ReflectableDrawRenderPass`
    public func addDrawCallbackPass<R>(name: String,
                                       renderTargets: RenderTargetsDescriptor,
                                       colorClearOperations: [ColorClearOperation] = [],
                                       depthClearOperation: DepthClearOperation = .keep,
                                       stencilClearOperation: StencilClearOperation = .keep,
                                       @ResourceUsageListBuilder using resources: () -> [ResourceUsage] = { [] },
                                       reflection: R.Type,
                                       execute: @escaping @Sendable (TypedRenderCommandEncoder<R>) async -> Void) {
        self.addPass(ReflectableCallbackDrawRenderPass(name: name, renderTargets: renderTargets,
                                                       colorClearOperations: colorClearOperations, depthClearOperation: depthClearOperation, stencilClearOperation: stencilClearOperation,
                                                       resources: resources(),
                                                       reflection: reflection, execute: execute))
    }

    /// Enqueue a compute render pass comprised of the specified compute/dispatch operations in `execute`.
    ///
    /// - Parameter execute: A closure to execute that will be passed a compute command encoder, where the caller can use the command
    /// encoder to encode commands for the GPU's compute pipeline.
    ///
    /// - SeeAlso: `addComputeCallbackPass(reflection:_:)`
    @inlinable
    public func addComputeCallbackPass(file: String = #fileID, line: Int = #line,
                                       resources: [ResourceUsage],
                                       execute: @escaping @Sendable (ComputeCommandEncoder) async -> Void) {
        self.addPass(CallbackComputeRenderPass(name: "Anonymous Compute Pass at \(file):\(line)", resources: resources, execute: execute))
    }
    
    /// Enqueue a compute render pass comprised of the specified compute/dispatch operations in `execute`.
    ///
    /// - Parameter name: The name of the pass.
    /// - Parameter execute: A closure to execute that will be passed a compute command encoder, where the caller can use the command
    /// encoder to encode commands for the GPU's compute pipeline.
    ///
    /// - SeeAlso: `addComputeCallbackPass(name:reflection:_:)`
    public func addComputeCallbackPass(name: String,
                                       @ResourceUsageListBuilder using resources: () -> [ResourceUsage],
                                       execute: @escaping @Sendable (ComputeCommandEncoder) async -> Void) {
        self.addPass(CallbackComputeRenderPass(name: name, resources: resources(), execute: execute))
    }

    /// Enqueue a compute render pass comprised of the specified compute/dispatch operations in `execute`, using the render pass reflection specified in `reflection`.
    ///
    /// - Parameter reflection: The generated shader reflection for this render pass.
    /// - Parameter execute: A closure to execute that will be passed a compute command encoder, where the caller can use the command
    /// encoder to encode commands for the GPU's compute pipeline.
    ///
    /// - SeeAlso: `ReflectableComputeRenderPass`
    @inlinable
    public func addComputeCallbackPass<R>(file: String = #fileID, line: Int = #line,
                                          @ResourceUsageListBuilder using resources: () -> [ResourceUsage],
                                          reflection: R.Type,
                                          execute: @escaping @Sendable (TypedComputeCommandEncoder<R>) async -> Void) {
        self.addPass(ReflectableCallbackComputeRenderPass(name: "Anonymous Compute Pass at \(file):\(line)", resources: resources(), reflection: reflection, execute: execute))
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
                                          @ResourceUsageListBuilder using resources: () -> [ResourceUsage],
                                          reflection: R.Type,
                                          execute: @escaping @Sendable (TypedComputeCommandEncoder<R>) async -> Void) {
        self.addPass(ReflectableCallbackComputeRenderPass(name: name, resources: resources(), reflection: reflection, execute: execute))
    }
    
    /// Enqueue a CPU render pass comprised of the operations in `execute`.
    /// This enables you to access GPU resources such as transient buffers or textures associated with the render graph.
    ///
    /// - Parameter execute: A closure to execute during render graph execution.
    @inlinable
    public func addCPUCallbackPass(file: String = #fileID, line: Int = #line,
                                   @ResourceUsageListBuilder using resources: () -> [ResourceUsage] = { [] },
                                   execute: @escaping @Sendable () async -> Void) {
        self.addPass(CallbackCPURenderPass(name: "Anonymous CPU Pass at \(file):\(line)", resources: resources(), execute: execute))
    }
    
    /// Enqueue a CPU render pass comprised of the operations in `execute`.
    /// This enables you to access GPU resources such as transient buffers or textures associated with the render graph.
    ///
    /// - Parameter name: The name of the pass.
    /// - Parameter execute: A closure to execute during render graph execution.
    public func addCPUCallbackPass(name: String,
                                   @ResourceUsageListBuilder using resources: () -> [ResourceUsage] = { [] },
                                   execute: @escaping @Sendable () async -> Void) {
        self.addPass(CallbackCPURenderPass(name: name, resources: resources(), execute: execute))
    }
    
    /// Enqueue an external render pass comprised of the GPU operations in `execute`.
    /// External render passes allow you to directly encode commands to the underlying GPU command buffer.
    ///
    /// - Parameter execute: A closure to execute that will be passed a external command encoder, where the caller can use the command
    /// encoder to encode commands directly to an underlying GPU command buffer.
    @inlinable
    public func addExternalCallbackPass(file: String = #fileID, line: Int = #line,
                                        @ResourceUsageListBuilder using resources: () -> [ResourceUsage],
                                        execute: @escaping @Sendable (ExternalCommandEncoder) async -> Void) {
        self.addPass(CallbackExternalRenderPass(name: "Anonymous External Encoder Pass at \(file):\(line)", resources: resources(), execute: execute))
    }
    
    /// Enqueue an external render pass comprised of the GPU operations in `execute`.
    /// External render passes allow you to directly encode commands to the underlying GPU command buffer.
    ///
    /// - Parameter name: The name of the pass.
    /// - Parameter execute: A closure to execute that will be passed a external command encoder, where the caller can use the command
    /// encoder to encode commands directly to an underlying GPU command buffer.
    public func addExternalCallbackPass(name: String,
                                        @ResourceUsageListBuilder using resources: () -> [ResourceUsage],
                                        execute: @escaping @Sendable (ExternalCommandEncoder) async -> Void) {
        self.addPass(CallbackExternalRenderPass(name: name, resources: resources(), execute: execute))
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public func addAccelerationStructureCallbackPass(file: String = #fileID, line: Int = #line,
                                                     @ResourceUsageListBuilder using resources: () -> [ResourceUsage],
                                        execute: @escaping @Sendable (AccelerationStructureCommandEncoder) -> Void) {
        self.addPass(CallbackAccelerationStructureRenderPass(name: "Anonymous Acceleration Structure Encoder Pass at \(file):\(line)", resources: resources(), execute: execute))
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public func addAccelerationStructureCallbackPass(name: String,
                                                     @ResourceUsageListBuilder using resources: () -> [ResourceUsage],
                                        execute: @escaping @Sendable (AccelerationStructureCommandEncoder) -> Void) {
        self.addPass(CallbackAccelerationStructureRenderPass(name: name, resources: resources(), execute: execute))
    }
    
    // When passes are added:
    // Check pass.writtenResources. If not empty, add the pass to the deferred queue and record its resource usages.
    // If it is empty, run the execute method eagerly and infer read/written resources from that.
    // Cull render passes using a reference counting floodfill method.
    // For any non-culled deferred passes, run the execute method and record the commands.
    // Pass off the full, joined command list, list of all resources used, and a list of active passes to the backend.
    // Backend will look over all resource usages and figure out necessary resource transitions and creation/destruction times (could be synced with command numbers e.g. before command 300, transition resource A to state X).
    // Then, it will execute the command list.
    
    nonisolated func fillUsedResourcesFromPass(passRecord: RenderPassRecord, resourceUsageAllocator: TagAllocator) {
        let hasUnifiedMemory = RenderBackend.hasUnifiedMemory
        
        passRecord.readResources = .init(allocator: .tag(resourceUsageAllocator))
        passRecord.writtenResources = .init(allocator: .tag(resourceUsageAllocator))
        
        let resources = (passRecord.pass as? DrawRenderPass)?.inferredResources ?? passRecord.pass.resources
        
        for resourceUsage in resources {
            let resource = resourceUsage.resource
            resource.markAsUsed(activeRenderGraphMask: 1 << self.queue.index)
            if resourceUsage.type.isWrite {
                passRecord.writtenResources.insert(resource.resourceForUsageTracking)
            }
            if resourceUsage.type.isRead {
                passRecord.readResources.insert(resource.resourceForUsageTracking)
                
                // If we read a resource on the CPU in a pass,
                // treat that as a GPU write for tracking purposes.
                if resourceUsage.type.contains(.cpuRead),
                    resource.storageMode == .managed,
                   !hasUnifiedMemory {
                    passRecord.writtenResources.insert(resource.resourceForUsageTracking)
                }
            }
        }
    }
    
    func evaluateResourceUsages(renderPasses: [RenderPassRecord], executionAllocator: TagAllocator, resourceUsagesAllocator: TagAllocator) async {
        let signpostState = Self.signposter.beginInterval("Evaluate Resource Usages")
        defer { Self.signposter.endInterval("Evaluate Resource Usages", signpostState) }
        
        for passRecord in renderPasses {
            // CPU render passes are guaranteed to be executed in order, and we have to execute acceleration structure passes in order since they may modify the AccelerationStructure's descriptor property.
            // FIXME: This may actually cause issues if we update AccelerationStructures multiple times in a single RenderGraph and use it in between, since all other passes will depend only on the resources declared in the last-updated descriptor.
            self.fillUsedResourcesFromPass(passRecord: passRecord, resourceUsageAllocator: executionAllocator)
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
    
    func computePassRenderTargetIndices(passes: [DrawRenderPass?]) -> [Int] {
        var activeRenderTargets = [(index: Int, renderTargets: RenderTargetsDescriptor)]()
        
        var descriptorIndices = [Int](repeating: -1, count: passes.count)
        var nextDescriptorIndex = 0
        
        passLoop: for (passIndex, pass) in passes.enumerated() {
            guard let pass = pass else { continue }
            activeRenderTargets.reserveCapacity(passes.count)
            
            for i in activeRenderTargets.indices.reversed() {
                if activeRenderTargets[i].renderTargets.tryMerge(withPass: pass) {
                    descriptorIndices[passIndex] = activeRenderTargets[i].index
                    continue passLoop
                }
            }
            
            activeRenderTargets.append((nextDescriptorIndex, pass.renderTargetsDescriptor))
            descriptorIndices[passIndex] = nextDescriptorIndex
            nextDescriptorIndex += 1
        }
        
        return descriptorIndices
    }
    
    func computeDependencyOrdering(passIndex i: Int, dependencyTable: DependencyTable<DependencyType>, renderPasses: [RenderPassRecord], passRenderTargetIndices: [Int], addedToList: inout [Bool], activePasses: inout [RenderPassRecord], allocator: AllocatorType) {
        
        // Ideally, we should reorder the passes into an optimal order according to some heuristics.
        // For example:
        // - Draw render passes that can share a render target should be placed alongside each other
        // - We should try to minimise the number of resource transitions
        // - Try to maximise the space between e.g. an updateFence and a waitForFence call.
        //
        // For now, only try to address the draw render pass issue
        
        if renderPasses[i].isActive, !addedToList[i] {
            addedToList[i] = true
            
            if renderPasses[i].type == .draw {
                var sharedRenderTargetPasses = ChunkArray<Int>()
                
                // First process all passes that can't share the same render target...
                for j in (0..<i).reversed() where dependencyTable.dependency(from: i, on: j) != .none {
                    if passRenderTargetIndices[j] == passRenderTargetIndices[i] {
                        // If it _can_ share the same render target, add it to the sharedRenderTargetPasses list to process later...
                        sharedRenderTargetPasses.append(j, allocator: allocator)
                    } else {
                        computeDependencyOrdering(passIndex: j, dependencyTable: dependencyTable, renderPasses: renderPasses, passRenderTargetIndices: passRenderTargetIndices, addedToList: &addedToList, activePasses: &activePasses, allocator: allocator)
                    }
                }
                
                // ... and then process those which can.
                for j in sharedRenderTargetPasses {
                    computeDependencyOrdering(passIndex: j, dependencyTable: dependencyTable, renderPasses: renderPasses, passRenderTargetIndices: passRenderTargetIndices, addedToList: &addedToList, activePasses: &activePasses, allocator: allocator)
                }
                
            } else {
                for j in (0..<i).reversed() where dependencyTable.dependency(from: i, on: j) != .none {
                    computeDependencyOrdering(passIndex: j, dependencyTable: dependencyTable, renderPasses: renderPasses, passRenderTargetIndices: passRenderTargetIndices, addedToList: &addedToList, activePasses: &activePasses, allocator: allocator)
                }
            }
            
            activePasses.append(renderPasses[i])
        }
    }
    
    func compile(renderPasses: [RenderPassRecord]) async -> ([CPURenderPass], [RenderPassRecord], DependencyTable<DependencyType>, Set<Resource>) {
        let signpostState = Self.signposter.beginInterval("Compile RenderGraph")
        defer { Self.signposter.endInterval("Compile RenderGraph", signpostState) }
        
        let resourceUsagesAllocator = TagAllocator(tag: RenderGraphTagType.resourceUsageNodes.tag)
        let executionAllocator = TagAllocator(tag: RenderGraphTagType.renderGraphExecution.tag)
        
        for i in renderPasses.indices {
            renderPasses[i].passIndex = i  // We may have inserted early blit passes, so we need to set the pass indices now.
        }
        
        await self.evaluateResourceUsages(renderPasses: renderPasses, executionAllocator: executionAllocator, resourceUsagesAllocator: resourceUsagesAllocator)
        
        var dependencyTable = DependencyTable<DependencyType>(capacity: renderPasses.count, defaultValue: .none)
        let passHasSideEffects = SubstrateUtilities.BitSet(capacity: renderPasses.count)
        defer { passHasSideEffects.dispose() }

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
            
            if _isDebugAssertConfiguration() {
                for resource in pass.readResources {
                    assert(resource._usesPersistentRegistry || resource.transientRegistryIndex == self.transientRegistryIndex, "Transient resource \(resource) associated with another RenderGraph is being used in this RenderGraph.")
                    assert(resource.isValid, "Resource \(resource) is invalid but is used in the current frame.")
                }
            }
            
            if pass.type == .cpu, pass.pass.resources.isEmpty {
                passHasSideEffects[i] = true
            }
            
            if pass.type == .external {
                passHasSideEffects[i] = true
            }
        }
        
        for i in (0..<renderPasses.count).reversed() where passHasSideEffects[i] {
            self.markActive(passIndex: i, dependencyTable: dependencyTable, renderPasses: renderPasses)
        }
        
        let allocator = resourceUsagesAllocator
        
        var addedToList = [Bool](repeating: false, count: renderPasses.count)
        var activePasses = [RenderPassRecord]()
        let passRenderTargetIndices = self.computePassRenderTargetIndices(passes: renderPasses.map { $0.type == .draw ? ($0.pass! as! DrawRenderPass) : nil })
        for i in (0..<renderPasses.count).reversed() where passHasSideEffects[i] {
            self.computeDependencyOrdering(passIndex: i, dependencyTable: dependencyTable, renderPasses: renderPasses, passRenderTargetIndices: passRenderTargetIndices, addedToList: &addedToList, activePasses: &activePasses, allocator: AllocatorType(allocator))
        }
        
//        for i in (0..<renderPasses.count) {
//            if !renderPasses[i].isActive {
//                print("Pass \(renderPasses[i].name) is inactive")
//            }
//        }
        
        var cpuPasses = [CPURenderPass]()
        
        var i = 0
        while i < activePasses.count {
            let passRecord = activePasses[i]
            if passRecord.type == .cpu {
                cpuPasses.append(passRecord.pass as! CPURenderPass)
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
        
        // Index the commands for each pass in a sequential manner for the entire frame.
        for (i, passRecord) in activePasses.enumerated() {
            precondition(passRecord.isActive)
            
            passRecord.passIndex = i
            
            let resources = (passRecord.pass as? DrawRenderPass)?.inferredResources ?? passRecord.pass.resources
            for resourceUsage in resources where resourceUsage.stages != .cpuBeforeRender {
                assert(resourceUsage.resource.isValid)
                self.usedResources.insert(resourceUsage.resource)
                
                let recordedUsage = RecordedResourceUsage(passIndex: i, usage: resourceUsage, allocator: .tag(allocator), defaultStages: passRecord.type.allStages)
                resourceUsage.resource.usages.append(recordedUsage, allocator: AllocatorType(allocator))
            }
        }
        
        return (cpuPasses, activePasses, activePassDependencies, self.usedResources)
    }
    
    @available(*, deprecated, renamed: "onSubmission")
    public func waitForGPUSubmission(_ function: @Sendable @escaping () -> Void) {
        self.renderPassLock.withLock {
            self.submissionNotifyQueue.append(function)
        }
    }
    
    /// Enqueue `function` to be executed once the render graph is submitted to the GPU.
    public func onSubmission(_ function: @Sendable @escaping () async -> Void) {
        self.renderPassLock.withLock {
            self.submissionNotifyQueue.append(function)
        }
    }
    
    /// Enqueue `function` to be executed once the render graph has completed on the GPU.
    public func onGPUCompletion(_ function: @Sendable @escaping () async -> Void) {
        self.renderPassLock.withLock {
            self.completionNotifyQueue.append(function)
        }
    }
    
    public typealias SwapchainPresentedCallback = @Sendable (Texture?, Result<(any Drawable)?, Error>) -> Void
    
    /// Enqueue `function` to be executed once the render graph has completed on the GPU.
    public func onSwapchainPresented(_ function: @escaping SwapchainPresentedCallback) {
        self.renderPassLock.withLock {
            self.presentationNotifyQueue.append(function)
        }
    }
    
    /// Returns true if this RenderGraph already has the maximum number of GPU frames in-flight, and would have to wait
    /// for the ring buffers to become available before executing.
    public var hasMaximumFrameCountInFlight: Bool {
        return self.currentInflightFrameCount.load(ordering: .relaxed) >= self.inflightFrameCount
    }
    
    public var frameCountInFlight: Int {
        return self.currentInflightFrameCount.load(ordering: .relaxed)
    }
    
    private func didCompleteRender(queueCommandRange: Range<UInt64>) {
        self.currentInflightFrameCount.wrappingDecrement(ordering: .relaxed)
        
        self.frameTimingLock.withLock {
            let completionTime = DispatchTime.now().uptimeNanoseconds
            let elapsed = completionTime - min(self.previousFrameCompletionTime, completionTime)
            self.previousFrameCompletionTime = completionTime
            self._lastGraphCPUTime = .init(nanoseconds: elapsed)
            
            if !queueCommandRange.isEmpty {
                self.lastGraphFirstCommand = queueCommandRange.first!
                self.lastGraphLastCommand = queueCommandRange.last!
            } else {
                self.lastGraphFirstCommand = .max
                self.lastGraphLastCommand = .max
            }
        }
        
//        print("Frame executed in \(self.lastGraphDurations().gpuTime * 1000.0)ms")
    }
    
    public func withCPUResourceAccess<R>(perform: () async throws -> R) async rethrows -> R {
        await self.context.acquireResourceAccess()
        return try await Self.$activeRenderGraph.withValue(self) {
            return try await perform()
        }
    }
    
    public enum RenderGraphError: Error {
        case emptyRenderGraph
    }
    
    /// Process the render passes that have been enqueued on this render graph through calls to `addPass()` or similar by culling passes that don't produce
    /// any read resources, calling `execute` on each pass, then submitting the encoded commands to the GPU for execution.
    /// If there are any operations enqueued on the `GPUResourceUploader`, those will be processed before any passes in this render graph.
    /// Only one render graph will execute at any given time, and operations between render graphs are synchronised in submission order.
    ///
    /// - Parameter onSubmission: an optional closure to execute once the render graph has been submitted to the GPU.
    /// - Parameter onGPUCompletion: an optional closure to execute once the render graph has completed executing on the GPU.
    @discardableResult
    @_unsafeInheritExecutor // Don't force the RenderGraph to be executed on a global executor; submission should stay on the caller's executor. This means that execute() is effectively a synchronous method from an async context, which is what we want.
    public func execute(waitingFor gpuQueueWaitIndices: QueueCommandIndices = .zero) async -> RenderGraphExecutionWaitToken {
        precondition(Self.activeRenderGraph == nil, "Cannot call RenderGraph.execute() from within a render pass.")
        
        let signpostState = Self.signposter.beginInterval("Execute RenderGraph", id: self.signpostID)
        defer { Self.signposter.endInterval("Execute RenderGraph", signpostState) }
        
        await self.renderPassLock.lock()
        
        let renderPasses = self.renderPasses
        let submissionNotifyQueue = self.submissionNotifyQueue
        let completionNotifyQueue = self.completionNotifyQueue
        let presentationNotifyQueue = self.presentationNotifyQueue
        
        self.renderPasses.removeAll()
        self.completionNotifyQueue.removeAll()
        self.submissionNotifyQueue.removeAll()
        self.presentationNotifyQueue.removeAll()
        
        self.renderPassLock.unlock()
        
        defer {
            if !submissionNotifyQueue.isEmpty {
                Task.detached {
                    for item in submissionNotifyQueue {
                        await item()
                    }
                }
            }
        }
        
        guard !renderPasses.isEmpty else {
            let lastSubmittedCommand = self.queue.lastSubmittedCommand
            self.didCompleteRender(queueCommandRange: lastSubmittedCommand..<lastSubmittedCommand)
            Task.detached {
                for item in completionNotifyQueue {
                    await item()
                }
                for item in presentationNotifyQueue {
                    item(nil, .failure(RenderGraphError.emptyRenderGraph))
                }
            }
            return RenderGraphExecutionWaitToken(queue: self.queue, executionIndex: lastSubmittedCommand)
        }
        
        self.currentInflightFrameCount.wrappingIncrement(ordering: .relaxed)
        
        var onSwapchainPresented: (SwapchainPresentedCallback)? = nil
        if !presentationNotifyQueue.isEmpty {
            if presentationNotifyQueue.count == 1 {
                onSwapchainPresented = presentationNotifyQueue[0]
            } else {
                onSwapchainPresented = { (texture, swapchain) in
                    for item in presentationNotifyQueue {
                        item(texture, swapchain)
                    }
                }
            }
        }
        
        return await Self.executionStream.enqueueAndWait { [renderPasses, completionNotifyQueue, onSwapchainPresented] () -> RenderGraphExecutionWaitToken in // NOTE: if we decide not to have a global lock on RenderGraph execution, we need to handle resource usages on a per-render-graph basis.
            let signpostState = Self.signposter.beginInterval("Execute RenderGraph on Context", id: self.signpostID)
            let waitToken = await Self.$activeRenderGraph.withValue(self) {
                return await self.context.executeRenderGraph(self, renderPasses: renderPasses, waitingFor: gpuQueueWaitIndices, onSwapchainPresented: onSwapchainPresented, onCompletion: { queueCommandRange in
                    self.didCompleteRender(queueCommandRange: queueCommandRange)
                    
                    if !completionNotifyQueue.isEmpty {
                        Task.detached { [completionNotifyQueue] in
                            for item in completionNotifyQueue {
                                await item()
                            }
                        }
                    }
                })
            }
            
            Self.signposter.endInterval("Execute RenderGraph on Context", signpostState)
            
            // Make sure the RenderGraphCommands buffers are deinitialised before the tags are freed.
            renderPasses.forEach {
                $0.dispose()
            }
            
            self.reset()
            
            RenderGraph.globalSubmissionIndex.wrappingIncrement(ordering: .relaxed)
            
            return waitToken
        }
    }
    
    private func reset() {
        if transientRegistryIndex >= 0 {
            TransientBufferRegistry.instances[transientRegistryIndex].clear()
            TransientTextureRegistry.instances[transientRegistryIndex].clear()
            TransientArgumentBufferRegistry.instances[transientRegistryIndex].clear()
        }
            
        PersistentTextureRegistry.instance.clear(afterRenderGraph: self)
        PersistentBufferRegistry.instance.clear(afterRenderGraph: self)
        PersistentArgumentBufferRegistry.instance.clear(afterRenderGraph: self)
        HeapRegistry.instance.clear(afterRenderGraph: self)
        HazardTrackingGroupRegistry.instance.clear(afterRenderGraph: self)
        
        if #available(macOS 11.0, iOS 14.0, *) {
            AccelerationStructureRegistry.instance.clear(afterRenderGraph: self)
            VisibleFunctionTableRegistry.instance.clear(afterRenderGraph: self)
            IntersectionFunctionTableRegistry.instance.clear(afterRenderGraph: self)
        }
        
        self.usedResources.removeAll(keepingCapacity: true)
        
        TaggedHeap.free(tag: RenderGraphTagType.renderGraphExecution.tag)
        TaggedHeap.free(tag: RenderGraphTagType.resourceUsageNodes.tag)
    }
}
