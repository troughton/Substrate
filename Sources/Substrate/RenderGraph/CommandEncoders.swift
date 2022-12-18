//
//  CommandEncoders.swift
//  Substrate
//
//  Created by Thomas Roughton on 30/08/20.
//

import SubstrateUtilities

#if canImport(Metal)
@preconcurrency import Metal
#endif

#if canImport(MetalPerformanceShaders)
@preconcurrency import MetalPerformanceShaders
#endif

#if canImport(Vulkan)
import Vulkan
#endif

@usableFromInline
protocol CommandEncoder : AnyObject {
    var passRecord : RenderPassRecord { get }
    
    func pushDebugGroup(_ groupName: String)
    func popDebugGroup()
    
    func endEncoding()
}

// Performance: avoid slow range initialiser until https://github.com/apple/swift/pull/40871 makes it into a release branch.
extension Range where Bound: Strideable, Bound.Stride: SignedInteger {
  /// Creates an instance equivalent to the given `ClosedRange`.
  ///
  /// - Parameter other: A closed range to convert to a `Range` instance.
  ///
  /// An equivalent range must be representable as an instance of Range<Bound>.
  /// For example, passing a closed range with an upper bound of `Int.max`
  /// triggers a runtime error, because the resulting half-open range would
  /// require an upper bound of `Int.max + 1`, which is not representable as
  /// an `Int`.
  @inlinable // trivial-implementation
  public init(_ other: ClosedRange<Bound>) {
    let upperBound = other.upperBound.advanced(by: 1)
    self.init(uncheckedBounds: (lower: other.lowerBound, upper: upperBound))
  }
}

extension CommandEncoder {
    @inlinable
    public var renderPass : RenderPass {
        return self.passRecord.pass
    }
}

extension CommandEncoder {
    @inlinable
    public func debugGroup<T>(_ groupName: String, perform: () throws -> T) rethrows -> T {
        self.pushDebugGroup(groupName)
        let result = try perform()
        self.popDebugGroup()
        return result
    }
}

/*
 
 ** Resource Binding Algorithm-of-sorts **
 
 When the user binds a resource for a key, record the association between that key and that resource.
 
 When the user submits a draw call, look at all key-resource pairs and bind them. Do this by retrieving the resource binding path from the backend, along with how the resource is used. Record the first usage of the resource;  the ‘first use command index’ is the first index for all of the bindings. Keep a handle to allow updating of the applicable command range. If a resource is not used, then it is not an active binding and its update handle is not retained.
 
 After the pipeline state is changed, we need to query all resources given their keys on the next draw call. If they are an active binding and the resource binding path has not changed and the usage type has not changed, then we do not need to make any changes; however, if any of the above change we need to end the applicable command range at the index of the last draw call and register a new resource binding path and update handle.
 
 We can bypass the per-draw-call checks iff the pipeline state has not changed and there have been no changes to bound resources.
 
 For buffers, we also need to track a 32-bit offset. If the offset changes but not the main resource binding path, then we submit a update-offset command instead rather than a ‘bind’ command. The update-offset command includes the ObjectIdentifier for the resource.
 
 When encoding has finished, update the applicable command range for all active bindings to continue through to the last draw call made within the encoder.
 
 
 A requirement for resource binding is that subsequently bound pipeline states are compatible with the pipeline state bound at the time of the first draw call.
 */


protocol CommandEncoderImpl {
    func setLabel(_ label: String)
    func pushDebugGroup(_ groupName: String)
    func popDebugGroup()
    func insertDebugSignpost(_ string: String)
}

protocol ResourceBindingEncoderImpl: CommandEncoderImpl {
    func setLabel(_ label: String)
    func pushDebugGroup(_ groupName: String)
    func popDebugGroup()
    func insertDebugSignpost(_ string: String)
    
    func setBytes(_ bytes: UnsafeRawPointer, length: Int, at path: ResourceBindingPath)
    func setBuffer(_ buffer: Buffer, offset: Int, at path: ResourceBindingPath)
    func setBufferOffset(_ offset: Int, at path: ResourceBindingPath)
    func setTexture(_ texture: Texture, at path: ResourceBindingPath)
    func setSampler(_ state: SamplerState, at path: ResourceBindingPath)
    
    @available(macOS 12.0, iOS 15.0, *)
    func setVisibleFunctionTable(_ table: VisibleFunctionTable, at path: ResourceBindingPath)
    
    @available(macOS 12.0, iOS 15.0, *)
    func setIntersectionFunctionTable(_ table: IntersectionFunctionTable, at path: ResourceBindingPath)
    
    @available(macOS 12.0, iOS 15.0, *)
    func setAccelerationStructure(_ structure: AccelerationStructure, at path: ResourceBindingPath)
    
    /// Bind `argumentBuffer` to the binding index `index`, corresponding to a `[[buffer(setIndex + 1)]]` binding for Metal or the
    /// descriptor set at `setIndex` for Vulkan, and mark it as active in render stages `stages`.
    func setArgumentBuffer(_ argumentBuffer: ArgumentBuffer, at index: Int, stages: RenderStages)
}

/// `ResourceBindingEncoder` is the common superclass `CommandEncoder` for all command encoders that can bind resources.
/// You never instantiate a `ResourceBindingEncoder` directly; instead, you are provided with one of its concrete subclasses in a render pass' `execute` method.
public class ResourceBindingEncoder : CommandEncoder {
    @usableFromInline let passRecord: RenderPassRecord
    let bindingEncoderImpl: ResourceBindingEncoderImpl
    
    @usableFromInline
    var depthStencilStateChanged = false
    
    init(passRecord: RenderPassRecord, impl: ResourceBindingEncoderImpl) {
        self.passRecord = passRecord
        self.bindingEncoderImpl = impl
#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
        self.pushDebugGroup(passRecord.name)
#endif
    }
    
    public var label: String = "" {
        didSet {
            bindingEncoderImpl.setLabel(label)
        }
    }
    
    public func pushDebugGroup(_ groupName: String) {
        bindingEncoderImpl.pushDebugGroup(groupName)
    }
    
    public func popDebugGroup() {
        bindingEncoderImpl.popDebugGroup()
    }
    
    public func insertDebugSignpost(_ string: String) {
        bindingEncoderImpl.insertDebugSignpost(string)
    }
    
    public func setBytes(_ bytes: UnsafeRawPointer, length: Int, at path: ResourceBindingPath) {
        bindingEncoderImpl.setBytes(bytes, length: length, at: path)
    }
    
    public func setBuffer(_ buffer: Buffer?, offset: Int, at path: ResourceBindingPath) {
        guard let buffer = buffer else { return }
        bindingEncoderImpl.setBuffer(buffer, offset: offset, at: path)
    }
    
    public func setBufferOffset(_ offset: Int, at path: ResourceBindingPath) {
        bindingEncoderImpl.setBufferOffset(offset, at: path)
    }
    
    public func setTexture(_ texture: Texture?, at path: ResourceBindingPath) {
        guard let texture = texture else { return }
        bindingEncoderImpl.setTexture(texture, at: path)
    }
    
    public func setSampler(_ descriptor: SamplerDescriptor?, at path: ResourceBindingPath) async {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    public func setSampler(_ state: SamplerState?, at path: ResourceBindingPath) {
        guard let state = state else { return }
        bindingEncoderImpl.setSampler(state, at: path)
    }
    
    @available(macOS 12.0, iOS 15.0, *)
    public func setVisibleFunctionTable(_ table: VisibleFunctionTable?, at path: ResourceBindingPath) {
        guard let table = table else { return }
        bindingEncoderImpl.setVisibleFunctionTable(table, at: path)
    }
    
    @available(macOS 12.0, iOS 15.0, *)
    public func setIntersectionFunctionTable(_ table: IntersectionFunctionTable?, at path: ResourceBindingPath) {
        guard let table = table else { return }
        bindingEncoderImpl.setIntersectionFunctionTable(table, at: path)
    }
    
    @available(macOS 12.0, iOS 15.0, *)
    public func setAccelerationStructure(_ structure: AccelerationStructure?, at path: ResourceBindingPath) {
        guard let structure = structure else { return }
        bindingEncoderImpl.setAccelerationStructure(structure, at: path)
    }
    
    /// Construct an `ArgumentBuffer` specified by the `ArgumentBufferEncodable` value `arguments`
    /// and bind it to the binding index `setIndex`, corresponding to a `[[buffer(setIndex + 1)]]` binding for Metal or the
    /// descriptor set at `setIndex` for Vulkan.
    public func setArguments<A : ArgumentBufferEncodable>(_ arguments: inout A, at setIndex: Int) async {
        if A.self == NilSet.self {
            return
        }
        
        let argumentBuffer = ArgumentBuffer(descriptor: A.argumentBufferDescriptor)
        assert(argumentBuffer.bindings.isEmpty)
        await arguments.encode(into: argumentBuffer, setIndex: setIndex, bindingEncoder: self)
     
#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
        argumentBuffer.label = "Descriptor Set for \(String(reflecting: A.self))"
#endif
        
        if _isDebugAssertConfiguration() {
            
            for binding in argumentBuffer.bindings {
                switch binding.1 {
                case .buffer(let buffer, _):
                    assert(buffer.type == .buffer)
                case .texture(let texture):
                    assert(texture.type == .texture)
                default:
                    break
                }
            }
        }

        self.setArgumentBuffer(argumentBuffer, at: setIndex, stages: A.activeStages)
    }
    
    /// Bind `argumentBuffer` to the binding index `index`, corresponding to a `[[buffer(setIndex + 1)]]` binding for Metal or the
    /// descriptor set at `setIndex` for Vulkan, and mark it as active in render stages `stages`.
    public func setArgumentBuffer(_ argumentBuffer: ArgumentBuffer?, at index: Int, stages: RenderStages) {
        guard let argumentBuffer = argumentBuffer else { return }
        
        let bindingPath = RenderBackend.argumentBufferPath(at: index, stages: stages)
        bindingEncoderImpl.setArgumentBuffer(argumentBuffer, at: index, stages: stages)
    }
    
    @usableFromInline func endEncoding() {
#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
        self.popDebugGroup() // Pass Name
#endif
    }
}

extension ResourceBindingEncoder {
    
    @inlinable
    public func setValue<T : ResourceProtocol>(_ value: T, at path: ResourceBindingPath) {
        preconditionFailure("setValue should not be used with resources; use setBuffer, setTexture, or setArgumentBuffer instead.")
    }
    
    @inlinable
    public func setValue<T>(_ value: T, at path: ResourceBindingPath) {
        assert(!(T.self is AnyObject.Type), "setValue should only be used with value types.")
        
        var value = value
        withUnsafeBytes(of: &value) { bytes in
            self.setBytes(bytes.baseAddress!, length: bytes.count, at: path)
        }
    }
}

public protocol AnyRenderCommandEncoder {
    func setArgumentBuffer(_ argumentBuffer: ArgumentBuffer?, at index: Int, stages: RenderStages)
    
    func setVertexBuffer(_ buffer: Buffer?, offset: Int, index: Int)
    
    func setVertexBufferOffset(_ offset: Int, index: Int)
    
    func setViewport(_ viewport: Viewport)
    
    func setFrontFacing(_ frontFacingWinding: Winding)
    
    func setCullMode(_ cullMode: CullMode)

    func setScissorRect(_ rect: ScissorRect)
    
    func setDepthBias(_ depthBias: Float, slopeScale: Float, clamp: Float)
    
    func setStencilReferenceValue(_ referenceValue: UInt32)
    
    func setStencilReferenceValues(front frontReferenceValue: UInt32, back backReferenceValue: UInt32)
    
    func drawPrimitives(type primitiveType: PrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int, baseInstance: Int) async
    
    func drawIndexedPrimitives(type primitiveType: PrimitiveType, indexCount: Int, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: Int, instanceCount: Int, baseVertex: Int, baseInstance: Int)  async
}

protocol RenderCommandEncoderImpl: ResourceBindingEncoderImpl {
    func setVertexBuffer(_ buffer: Buffer, offset: Int, index: Int)
    func setVertexBufferOffset(_ offset: Int, index: Int)
    
    func setViewport(_ viewport: Viewport)
    func setFrontFacing(_ winding: Winding)
    func setCullMode(_ cullMode: CullMode)
    func setDepthBias(_ depthBias: Float, slopeScale: Float, clamp: Float)
    func setScissorRect(_ rect: ScissorRect)
    func setRenderPipelineState(_ pipelineState: RenderPipelineState)
    func setDepthStencilState(_ depthStencilState: DepthStencilState)
    func setStencilReferenceValue(_ referenceValue: UInt32)
    func setStencilReferenceValues(front frontReferenceValue: UInt32, back backReferenceValue: UInt32)
    
    @available(macOS 12.0, iOS 15.0, *)
    func setThreadgroupMemoryLength(_ length: Int, at path: ResourceBindingPath)
    
    func drawPrimitives(type primitiveType: PrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int , baseInstance: Int)
    func drawPrimitives(type primitiveType: PrimitiveType, indirectBuffer: Buffer, indirectBufferOffset: Int)
    func drawIndexedPrimitives(type primitiveType: PrimitiveType, indexCount: Int, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: Int, instanceCount: Int, baseVertex: Int, baseInstance: Int)
    func drawIndexedPrimitives(type primitiveType: PrimitiveType, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: Int, indirectBuffer: Buffer, indirectBufferOffset: Int)
    
    @available(macOS 13.0, iOS 16.0, *)
    func drawMeshThreadgroups(_ threadgroupsPerGrid: Size, threadsPerObjectThreadgroup: Size, threadsPerMeshThreadgroup: Size)
    
    @available(macOS 13.0, iOS 16.0, *)
    func drawMeshThreads(_ threadsPerGrid: Size, threadsPerObjectThreadgroup: Size, threadsPerMeshThreadgroup: Size)
    
    @available(macOS 13.0, iOS 16.0, *)
    func drawMeshThreadgroups(indirectBuffer: Buffer, indirectBufferOffset: Int, threadsPerObjectThreadgroup: Size, threadsPerMeshThreadgroup: Size)
    
    func dispatchThreadsPerTile(_ threadsPerTile: Size)
    
    func useResource(_ resource: Resource, usage: ResourceUsageType, stages: RenderStages)
    func useHeap(_ heap: Heap, stages: RenderStages)
    
    func memoryBarrier(scope: BarrierScope, after: RenderStages, before: RenderStages)
    func memoryBarrier(resources: [Resource], after: RenderStages, before: RenderStages)
}

/// `RenderCommandEncoder` allows you to encode rendering commands to be executed by the GPU within a single `DrawRenderPass`.
public class RenderCommandEncoder : ResourceBindingEncoder, AnyRenderCommandEncoder {
    
    @usableFromInline
    enum Attachment : Hashable, CustomHashable {
        case color(Int)
        case depth
        case stencil
        
        public var customHashValue: Int {
            switch self {
            case .depth:
                return 1 << 0
            case .stencil:
                return 1 << 1
            case .color(let index):
                return 1 << 2 &+ index
            }
        }
    }
    
    struct DrawDynamicState: OptionSet {
        let rawValue: Int
        
        init(rawValue: Int) {
            self.rawValue = rawValue
        }
        
        static let viewport = DrawDynamicState(rawValue: 1 << 0)
        static let scissorRect = DrawDynamicState(rawValue: 1 << 1)
        static let frontFacing = DrawDynamicState(rawValue: 1 << 2)
        static let cullMode = DrawDynamicState(rawValue: 1 << 3)
        static let triangleFillMode = DrawDynamicState(rawValue: 1 << 4)
        static let depthBias = DrawDynamicState(rawValue: 1 << 5)
        static let stencilReferenceValue = DrawDynamicState(rawValue: 1 << 6)
    }
    
    let drawRenderPass : DrawRenderPass
    let impl: RenderCommandEncoderImpl
    
    var nonDefaultDynamicState: DrawDynamicState = []

    init(renderPass: DrawRenderPass, passRecord: RenderPassRecord, impl: RenderCommandEncoderImpl) {
        self.drawRenderPass = renderPass
        self.impl = impl
        super.init(passRecord: passRecord, impl: impl)
        
        assert(passRecord.pass === renderPass)
    }
    
    public func setRenderPipelineDescriptor(_ descriptor: RenderPipelineDescriptor, retainExistingBindings: Bool = true) async {
        var descriptor = descriptor
        descriptor.setPixelFormatsAndSampleCount(from: self.drawRenderPass.renderTargetsDescriptor)
        self.setRenderPipelineState(await RenderBackend._backend.renderPipelineState(for: descriptor))
    }
    
    public func setRenderPipelineState(_ pipelineState: RenderPipelineState) {
        impl.setRenderPipelineState(pipelineState)
    }
    
    public func setVertexBuffer(_ buffer: Buffer?, offset: Int, index: Int) {
        guard let buffer = buffer else { return }
        impl.setVertexBuffer(buffer, offset: offset, index: index)
    }
    
    public func setVertexBufferOffset(_ offset: Int, index: Int) {
        impl.setVertexBufferOffset(offset, index: index)
    }

    public func setViewport(_ viewport: Viewport) {
        self.nonDefaultDynamicState.formUnion(.viewport)
        impl.setViewport(viewport)
    }
    
    public func setFrontFacing(_ frontFacingWinding: Winding) {
        self.nonDefaultDynamicState.formUnion(.frontFacing)
        impl.setFrontFacing(frontFacingWinding)
    }
    
    public func setCullMode(_ cullMode: CullMode) {
        self.nonDefaultDynamicState.formUnion(.cullMode)
        impl.setCullMode(cullMode)
    }
    
    public func setDepthStencilDescriptor(_ descriptor: DepthStencilDescriptor?) async {
        guard self.drawRenderPass.renderTargetsDescriptor.depthAttachment != nil ||
            self.drawRenderPass.renderTargetsDescriptor.stencilAttachment != nil else {
                return
        }
        
        var descriptor = descriptor ?? DepthStencilDescriptor()
        if self.drawRenderPass.renderTargetsDescriptor.depthAttachment == nil {
            descriptor.depthCompareFunction = .always
            descriptor.isDepthWriteEnabled = false
        }
        if self.drawRenderPass.renderTargetsDescriptor.stencilAttachment == nil {
            descriptor.frontFaceStencil = .init()
            descriptor.backFaceStencil = .init()
        }
        
        self.setDepthStencilState(await RenderBackend._backend.depthStencilState(for: descriptor))
    }
    
    public func setDepthStencilState(_ depthStencilState: DepthStencilState) {
        impl.setDepthStencilState(depthStencilState)
    }
    
//    @inlinable
    public func setScissorRect(_ rect: ScissorRect) {
        self.nonDefaultDynamicState.formUnion(.scissorRect)
        impl.setScissorRect(rect)
    }
    
    public func setDepthBias(_ depthBias: Float, slopeScale: Float, clamp: Float) {
        self.nonDefaultDynamicState.formUnion(.depthBias)
        impl.setDepthBias(depthBias, slopeScale: slopeScale, clamp: clamp)
    }
    
    public func setStencilReferenceValue(_ referenceValue: UInt32) {
        self.nonDefaultDynamicState.formUnion(.stencilReferenceValue)
        impl.setStencilReferenceValue(referenceValue)
    }
    
    public func setStencilReferenceValues(front frontReferenceValue: UInt32, back backReferenceValue: UInt32) {
        self.nonDefaultDynamicState.formUnion(.stencilReferenceValue)
        impl.setStencilReferenceValues(front: frontReferenceValue, back: backReferenceValue)
    }
    
    @available(macOS 12.0, iOS 15.0, *)
    public func setThreadgroupMemoryLength(_ length: Int, at path: ResourceBindingPath) {
        impl.setThreadgroupMemoryLength(length, at: path)
    }
    
    public func drawPrimitives(type primitiveType: PrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int = 1, baseInstance: Int = 0) {
        assert(instanceCount > 0, "instanceCount(\(instanceCount)) must be non-zero.")
        
        impl.drawPrimitives(type: primitiveType, vertexStart: vertexStart, vertexCount: vertexCount, instanceCount: instanceCount, baseInstance: baseInstance)
    }
    
    public func drawPrimitives(type primitiveType: PrimitiveType, indirectBuffer: Buffer, indirectBufferOffset: Int) {
        impl.drawPrimitives(type: primitiveType, indirectBuffer: indirectBuffer, indirectBufferOffset: indirectBufferOffset)
    }
    
    public func drawIndexedPrimitives(type primitiveType: PrimitiveType, indexCount: Int, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: Int, instanceCount: Int = 1, baseVertex: Int = 0, baseInstance: Int = 0) {
        assert(instanceCount > 0, "instanceCount(\(instanceCount)) must be non-zero.")
        
        impl.drawIndexedPrimitives(type: primitiveType, indexCount: indexCount, indexType: indexType, indexBuffer: indexBuffer, indexBufferOffset: indexBufferOffset, instanceCount: instanceCount, baseVertex: baseVertex, baseInstance: baseInstance)
    }
    
    public func drawIndexedPrimitives(type primitiveType: PrimitiveType, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: Int, indirectBuffer: Buffer, indirectBufferOffset: Int) {
        impl.drawIndexedPrimitives(type: primitiveType, indexType: indexType, indexBuffer: indexBuffer, indexBufferOffset: indexBufferOffset, indirectBuffer: indirectBuffer, indirectBufferOffset: indirectBufferOffset)
    }
    
    @available(macOS 13.0, iOS 16.0, *)
    public func drawMeshThreadgroups(_ threadgroupsPerGrid: Size, threadsPerObjectThreadgroup: Size, threadsPerMeshThreadgroup: Size) {
        impl.drawMeshThreadgroups(threadgroupsPerGrid, threadsPerObjectThreadgroup: threadsPerObjectThreadgroup, threadsPerMeshThreadgroup: threadsPerMeshThreadgroup)
    }
    
    @available(macOS 13.0, iOS 16.0, *)
    public func drawMeshThreads(_ threadsPerGrid: Size, threadsPerObjectThreadgroup: Size, threadsPerMeshThreadgroup: Size) {
        impl.drawMeshThreads(threadsPerGrid, threadsPerObjectThreadgroup: threadsPerObjectThreadgroup, threadsPerMeshThreadgroup: threadsPerMeshThreadgroup)
    }
    
    @available(macOS 13.0, iOS 16.0, *)
    public func drawMeshThreadgroups(indirectBuffer: Buffer, indirectBufferOffset: Int, threadsPerObjectThreadgroup: Size, threadsPerMeshThreadgroup: Size) {
        impl.drawMeshThreadgroups(indirectBuffer: indirectBuffer, indirectBufferOffset: indirectBufferOffset, threadsPerObjectThreadgroup: threadsPerObjectThreadgroup, threadsPerMeshThreadgroup: threadsPerMeshThreadgroup)
    }
    
    public func dispatchThreadsPerTile(_ threadsPerTile: Size) {
        impl.dispatchThreadsPerTile(threadsPerTile)
    }
    
    public func useResource<R: ResourceProtocol>(_ resource: R, usage: ResourceUsageType, stages: RenderStages) {
        impl.useResource(Resource(resource), usage: usage, stages: stages)
    }
    
    public func useHeap(_ heap: Heap, stages: RenderStages) {
        impl.useHeap(heap, stages: stages)
    }
    
    public func memoryBarrier(scope: BarrierScope, after: RenderStages, before: RenderStages) {
        impl.memoryBarrier(scope: scope, after: after, before: before)
    }
    
    public func memoryBarrier(resources: [Resource], after: RenderStages, before: RenderStages) {
        impl.memoryBarrier(resources: resources, after: after, before: before)
    }
    
    @usableFromInline override func endEncoding() {
        // Reset any dynamic state to the defaults.
        let renderTargetSize = self.drawRenderPass.renderTargetsDescriptor.size
        if self.nonDefaultDynamicState.contains(.viewport) {
            self.setViewport(Viewport(originX: 0.0, originY: 0.0, width: Double(renderTargetSize.width), height: Double(renderTargetSize.height), zNear: 0.0, zFar: 1.0))
        }
        if self.nonDefaultDynamicState.contains(.scissorRect) {
            self.setScissorRect(ScissorRect(x: 0, y: 0, width: renderTargetSize.width, height: renderTargetSize.height))
        }
        if self.nonDefaultDynamicState.contains(.frontFacing) {
            self.setFrontFacing(.counterClockwise)
        }
        if self.nonDefaultDynamicState.contains(.cullMode) {
            self.setCullMode(.none)
        }
        if self.nonDefaultDynamicState.contains(.depthBias) {
            self.setDepthBias(0.0, slopeScale: 0.0, clamp: 0.0)
        }
        if self.nonDefaultDynamicState.contains(.stencilReferenceValue) {
            self.setStencilReferenceValue(0)
        }
        
        super.endEncoding()
    }
}

protocol ComputeCommandEncoderImpl: ResourceBindingEncoderImpl {
    @available(macOS 11.0, iOS 14.0, *)
    func setVisibleFunctionTable(_ table: VisibleFunctionTable, at path: ResourceBindingPath)
    
    @available(macOS 11.0, iOS 14.0, *)
    func setIntersectionFunctionTable(_ table: IntersectionFunctionTable, at path: ResourceBindingPath)
    
    @available(macOS 11.0, iOS 14.0, *)
    func setAccelerationStructure(_ structure: AccelerationStructure, at path: ResourceBindingPath)
    
    func setComputePipelineState(_ pipelineState: ComputePipelineState)
    
    func setStageInRegion(_ region: Region)
    func setThreadgroupMemoryLength(_ length: Int, at index: Int)
    
    func dispatchThreadgroups(_ threadgroupsPerGrid: Size, threadsPerThreadgroup: Size)
    func dispatchThreadgroups(indirectBuffer: Buffer, indirectBufferOffset: Int, threadsPerThreadgroup: Size)
    func dispatchThreads(_ threadsPerGrid: Size, threadsPerThreadgroup: Size)
    func drawMeshThreadgroups(indirectBuffer: Buffer, indirectBufferOffset: Int, threadsPerThreadgroup: Size)
    
    func useResource(_ resource: Resource, usage: ResourceUsageType)
    func useHeap(_ heap: Heap)
    
    func memoryBarrier(scope: BarrierScope)
    func memoryBarrier(resources: [Resource])
}

public class ComputeCommandEncoder : ResourceBindingEncoder {
    
    let computeRenderPass : ComputeRenderPass
    let impl: ComputeCommandEncoderImpl
    var currentPipelineState: ComputePipelineState? = nil
    
    init(renderPass: ComputeRenderPass, passRecord: RenderPassRecord, impl: ComputeCommandEncoderImpl) {
        self.computeRenderPass = renderPass
        self.impl = impl
        super.init(passRecord: passRecord, impl: impl)
        
        assert(passRecord.pass === renderPass)
    }
    
    public func setComputePipelineDescriptor(_ descriptor: ComputePipelineDescriptor) async {
        self.setComputePipelineState(await RenderBackend._backend.computePipelineState(for: descriptor))
    }
    
    public func setComputePipelineState(_ pipelineState: ComputePipelineState) {
        self.currentPipelineState = pipelineState
        impl.setComputePipelineState(pipelineState)
    }
    
    /// The number of threads in a SIMD group/wave for the current pipeline state.
    public var currentThreadExecutionWidth: Int {
        return self.currentPipelineState?.threadExecutionWidth ?? 0
    }
    
    public func setStageInRegion(_ region: Region) {
        impl.setStageInRegion(region)
    }
    
    public func setThreadgroupMemoryLength(_ length: Int, at index: Int) {
        impl.setThreadgroupMemoryLength(length, at: index)
    }

    public func dispatchThreads(_ threadsPerGrid: Size, threadsPerThreadgroup: Size) {
        precondition(threadsPerGrid.width > 0 && threadsPerGrid.height > 0 && threadsPerGrid.depth > 0)
        precondition(threadsPerThreadgroup.width > 0 && threadsPerThreadgroup.height > 0 && threadsPerThreadgroup.depth > 0)
        
        impl.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    }
    
    public func dispatchThreadgroups(_ threadgroupsPerGrid: Size, threadsPerThreadgroup: Size) {
        precondition(threadgroupsPerGrid.width > 0 && threadgroupsPerGrid.height > 0 && threadgroupsPerGrid.depth > 0)
        precondition(threadsPerThreadgroup.width > 0 && threadsPerThreadgroup.height > 0 && threadsPerThreadgroup.depth > 0)
        
        impl.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    }
    
    public func dispatchThreadgroups(indirectBuffer: Buffer, indirectBufferOffset: Int, threadsPerThreadgroup: Size) {
        precondition(threadsPerThreadgroup.width > 0 && threadsPerThreadgroup.height > 0 && threadsPerThreadgroup.depth > 0)
        
        impl.dispatchThreadgroups(indirectBuffer: indirectBuffer, indirectBufferOffset: indirectBufferOffset, threadsPerThreadgroup: threadsPerThreadgroup)
    }
    
    public func drawMeshThreadgroups(indirectBuffer: Buffer, indirectBufferOffset: Int, threadsPerThreadgroup: Size) {
        impl.drawMeshThreadgroups(indirectBuffer: indirectBuffer, indirectBufferOffset: indirectBufferOffset, threadsPerThreadgroup: threadsPerThreadgroup)
    }
    
    public func useResource<R: ResourceProtocol>(_ resource: R, usage: ResourceUsageType) {
        impl.useResource(Resource(resource), usage: usage)
    }
    
    public func useHeap(_ heap: Heap) {
        impl.useHeap(heap)
    }
    
    public func memoryBarrier(scope: BarrierScope) {
        impl.memoryBarrier(scope: scope)
    }
    
    public func memoryBarrier(resources: [Resource]) {
        impl.memoryBarrier(resources: resources)
    }
}

protocol BlitCommandEncoderImpl: CommandEncoderImpl {
    func copy(from sourceBuffer: Buffer, sourceOffset: Int, sourceBytesPerRow: Int, sourceBytesPerImage: Int, sourceSize: Size, to destinationTexture: Texture, destinationSlice: Int, destinationLevel: Int, destinationOrigin: Origin, options: BlitOption)
    
    func copy(from sourceBuffer: Buffer, sourceOffset: Int, to destinationBuffer: Buffer, destinationOffset: Int, size: Int)
    
    func copy(from sourceTexture: Texture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: Origin, sourceSize: Size, to destinationBuffer: Buffer, destinationOffset: Int, destinationBytesPerRow: Int, destinationBytesPerImage: Int, options: BlitOption)
    
    func copy(from sourceTexture: Texture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: Origin, sourceSize: Size, to destinationTexture: Texture, destinationSlice: Int, destinationLevel: Int, destinationOrigin: Origin)
    
    func fill(buffer: Buffer, range: Range<Int>, value: UInt8)
    
    func generateMipmaps(for texture: Texture)
    
    func synchronize(buffer: Buffer)
    func synchronize(texture: Texture)
    func synchronize(texture: Texture, slice: Int, level: Int)
}

public class BlitCommandEncoder : CommandEncoder {

    @usableFromInline let passRecord: RenderPassRecord
    let blitRenderPass : BlitRenderPass
    let impl: BlitCommandEncoderImpl
    
    init(renderPass: BlitRenderPass, passRecord: RenderPassRecord, impl: BlitCommandEncoderImpl) {
        self.blitRenderPass = renderPass
        self.passRecord = passRecord
        self.impl = impl
        
        assert(passRecord.pass === renderPass)
        
#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
        self.pushDebugGroup(passRecord.name)
#endif
    }
    
    @usableFromInline func endEncoding() {
#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
        self.popDebugGroup() // Pass Name
#endif
    }
    
    public var label : String = "" {
        didSet {
            impl.setLabel(label)
        }
    }
    
    public func pushDebugGroup(_ groupName: String) {
        impl.pushDebugGroup(groupName)
    }
    
    public func popDebugGroup() {
        impl.popDebugGroup()
    }
    
    public func insertDebugSignpost(_ string: String) {
        impl.insertDebugSignpost(string)
    }
    
    public func copy(from sourceBuffer: Buffer, sourceOffset: Int, sourceBytesPerRow: Int, sourceBytesPerImage: Int, sourceSize: Size, to destinationTexture: Texture, destinationSlice: Int, destinationLevel: Int, destinationOrigin: Origin, options: BlitOption = []) {
        impl.copy(from: sourceBuffer, sourceOffset: sourceOffset, sourceBytesPerRow: sourceBytesPerRow, sourceBytesPerImage: sourceBytesPerImage, sourceSize: sourceSize, to: destinationTexture, destinationSlice: destinationSlice, destinationLevel: destinationLevel, destinationOrigin: destinationOrigin, options: options)
    }
    
    public func copy(from sourceBuffer: Buffer, sourceOffset: Int, to destinationBuffer: Buffer, destinationOffset: Int, size: Int) {
        impl.copy(from: sourceBuffer, sourceOffset: sourceOffset, to: destinationBuffer, destinationOffset: destinationOffset, size: size)
    }
    
    public func copy(from sourceTexture: Texture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: Origin, sourceSize: Size, to destinationBuffer: Buffer, destinationOffset: Int, destinationBytesPerRow: Int, destinationBytesPerImage: Int, options: BlitOption = []) {
        impl.copy(from: sourceTexture, sourceSlice: sourceSlice, sourceLevel: sourceLevel, sourceOrigin: sourceOrigin, sourceSize: sourceSize, to: destinationBuffer, destinationOffset: destinationOffset, destinationBytesPerRow: destinationBytesPerRow, destinationBytesPerImage: destinationBytesPerImage, options: options)
    }
    
    public func copy(from sourceTexture: Texture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: Origin, sourceSize: Size, to destinationTexture: Texture, destinationSlice: Int, destinationLevel: Int, destinationOrigin: Origin) {
        impl.copy(from: sourceTexture, sourceSlice: sourceSlice, sourceLevel: sourceLevel, sourceOrigin: sourceOrigin, sourceSize: sourceSize, to: destinationTexture, destinationSlice: destinationSlice, destinationLevel: destinationLevel, destinationOrigin: destinationOrigin)
    }
    
    public func fill(buffer: Buffer, range: Range<Int>, value: UInt8) {
        impl.fill(buffer: buffer, range: range, value: value)
    }
    
    public func generateMipmaps(for texture: Texture) {
        impl.generateMipmaps(for: texture)
    }
    
    public func synchronize(buffer: Buffer) {
        impl.synchronize(buffer: buffer)
    }
    
    public func synchronize(texture: Texture) {
        impl.synchronize(texture: texture)
    }
    
    public func synchronize(texture: Texture, slice: Int, level: Int) {
        impl.synchronize(texture: texture, slice: slice, level: level)
    }
}

protocol ExternalCommandEncoderImpl: CommandEncoderImpl {
    func encodeCommand(_ command: (_ commandBuffer: UnsafeRawPointer) -> Void)
}

public class ExternalCommandEncoder : CommandEncoder {
    @usableFromInline let passRecord: RenderPassRecord
    let impl: ExternalCommandEncoderImpl
    let externalRenderPass : ExternalRenderPass
    
    init(renderPass: ExternalRenderPass, passRecord: RenderPassRecord, impl: ExternalCommandEncoderImpl) {
        self.externalRenderPass = renderPass
        self.passRecord = passRecord
        self.impl = impl
        
        assert(passRecord.pass === renderPass)
        
#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
        self.pushDebugGroup(passRecord.name)
#endif
    }
    
    @usableFromInline func endEncoding() {
#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
        self.popDebugGroup() // Pass Name
#endif
    }
    
    public var label : String = "" {
        didSet {
            impl.setLabel(label)
        }
    }
    
    public func pushDebugGroup(_ groupName: String) {
        impl.pushDebugGroup(groupName)
    }
    
    public func popDebugGroup() {
        impl.popDebugGroup()
    }
    
    public func insertDebugSignpost(_ string: String) {
        impl.insertDebugSignpost(string)
    }
    
    func encodeCommand(_ command: (_ commandBuffer: UnsafeRawPointer) -> Void) {
        impl.encodeCommand(command)
    }
    
    #if canImport(Metal)
    
    public func encodeToMetalCommandBuffer(_ command: @escaping (_ commandBuffer: MTLCommandBuffer) -> Void) {
        self.encodeCommand({ (cmdBuffer) in
            Unmanaged<MTLCommandBuffer>.fromOpaque(cmdBuffer)._withUnsafeGuaranteedRef { command($0) }
        })
    }
    
    #endif
    
    #if canImport(MetalPerformanceShaders)
    
    @available(OSX 10.14, *)
    public func encodeRayIntersection(intersector: MPSRayIntersector, intersectionType: MPSIntersectionType, rayBuffer: Buffer, rayBufferOffset: Int, intersectionBuffer: Buffer, intersectionBufferOffset: Int, rayCount: Int, accelerationStructure: MPSAccelerationStructure) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    @available(OSX 10.14, *)
    public func encodeRayIntersection(intersector: MPSRayIntersector, intersectionType: MPSIntersectionType, rayBuffer: Buffer, rayBufferOffset: Int, intersectionBuffer: Buffer, intersectionBufferOffset: Int, rayCountBuffer: Buffer, rayCountBufferOffset: Int, accelerationStructure: MPSAccelerationStructure) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    #endif
}

protocol AccelerationStructureCommandEncoderImpl: CommandEncoderImpl {
    func build(accelerationStructure: AccelerationStructure, descriptor: AccelerationStructureDescriptor, scratchBuffer: Buffer, scratchBufferOffset: Int)
    
    func refit(sourceAccelerationStructure: AccelerationStructure, descriptor: AccelerationStructureDescriptor, destinationAccelerationStructure: AccelerationStructure?, scratchBuffer: Buffer, scratchBufferOffset: Int)
    
    func copy(sourceAccelerationStructure: AccelerationStructure, destinationAccelerationStructure: AccelerationStructure)

    func writeCompactedSize(of accelerationStructure: AccelerationStructure, to buffer: Buffer, offset: Int)
    
    func copyAndCompact(sourceAccelerationStructure: AccelerationStructure, destinationAccelerationStructure: AccelerationStructure)
}

@available(macOS 11.0, iOS 14.0, *)
public class AccelerationStructureCommandEncoder : CommandEncoder {
    
    @usableFromInline let passRecord: RenderPassRecord
    let accelerationStructureRenderPass : AccelerationStructureRenderPass
    let impl: AccelerationStructureCommandEncoderImpl
    
    init(accelerationStructureRenderPass: AccelerationStructureRenderPass, passRecord: RenderPassRecord, impl: AccelerationStructureCommandEncoderImpl) {
        self.accelerationStructureRenderPass = accelerationStructureRenderPass
        self.passRecord = passRecord
        self.impl = impl
        
        assert(passRecord.pass === renderPass)
        
        self.pushDebugGroup(passRecord.name)
    }
    
    @usableFromInline func endEncoding() {
        self.popDebugGroup() // Pass Name
    }
    
    public var label : String = "" {
        didSet {
            impl.setLabel(label)
        }
    }
    
    public func pushDebugGroup(_ groupName: String) {
        impl.pushDebugGroup(groupName)
    }
    
    public func popDebugGroup() {
        impl.popDebugGroup()
    }
    
    public func insertDebugSignpost(_ string: String) {
        impl.insertDebugSignpost(string)
    }
    
    public func build(accelerationStructure: AccelerationStructure, descriptor: AccelerationStructureDescriptor, scratchBuffer: Buffer, scratchBufferOffset: Int = 0) {
        
        impl.build(accelerationStructure: accelerationStructure, descriptor: descriptor, scratchBuffer: scratchBuffer, scratchBufferOffset: scratchBufferOffset)
        
        accelerationStructure.descriptor = descriptor
    }

    public func refit(sourceAccelerationStructure: AccelerationStructure, descriptor: AccelerationStructureDescriptor, destinationAccelerationStructure: AccelerationStructure?, scratchBuffer: Buffer, scratchBufferOffset: Int = 0) {
        
        impl.refit(sourceAccelerationStructure: sourceAccelerationStructure, descriptor: descriptor, destinationAccelerationStructure: destinationAccelerationStructure, scratchBuffer: scratchBuffer, scratchBufferOffset: scratchBufferOffset)
        
        if let destinationStructure = destinationAccelerationStructure {
            sourceAccelerationStructure.descriptor = nil
            destinationStructure.descriptor = descriptor
        } else {
            sourceAccelerationStructure.descriptor = descriptor
        }
    }
    
    public func copy(sourceAccelerationStructure: AccelerationStructure, destinationAccelerationStructure: AccelerationStructure) {
        impl.copy(sourceAccelerationStructure: sourceAccelerationStructure, destinationAccelerationStructure: destinationAccelerationStructure)
        destinationAccelerationStructure.descriptor = sourceAccelerationStructure.descriptor
    }

    // vkCmdWriteAccelerationStructuresPropertiesKHR
    public func writeCompactedSize(of accelerationStructure: AccelerationStructure, to buffer: Buffer, offset: Int) {
        impl.writeCompactedSize(of: accelerationStructure, to: buffer, offset: offset)
    }
    
    public func copyAndCompact(sourceAccelerationStructure: AccelerationStructure, destinationAccelerationStructure: AccelerationStructure) {
        impl.copyAndCompact(sourceAccelerationStructure: sourceAccelerationStructure, destinationAccelerationStructure: destinationAccelerationStructure)
        destinationAccelerationStructure.descriptor = sourceAccelerationStructure.descriptor
    }
}
