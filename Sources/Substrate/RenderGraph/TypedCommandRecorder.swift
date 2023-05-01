//
//  TypedCommandRecorder.swift
//  Substrate
//
//  Created by Thomas Roughton on 6/06/19.
//

import Foundation

public protocol NoArgConstructable {
    init()
}

public protocol ShaderResourceSet : NoArgConstructable & ArgumentBufferEncodable {
    /// Used for binding any resources that must be directly bound to an encoder (e.g. UAV textures on Apple Silicon GPUs).
    mutating func bindDirectArguments(encoder: ResourceBindingEncoder, setIndex: Int) async
}

public struct NilFunctions : RawRepresentable {
    public typealias RawValue = String
    
    public init?(rawValue: Self.RawValue) {
        return nil
    }
    
    public var rawValue: String {
        fatalError()
    }
}

public struct NilSet : ShaderResourceSet {
    public static var activeStages: RenderStages = []
    
    public static var bindingIndex: Int {
        return -1
    }
    
    @inlinable
    public init() {}
    
    public mutating func encode(into argBuffer: ArgumentBuffer) {
    }
    
    public mutating func bindDirectArguments(encoder: ResourceBindingEncoder, setIndex: Int) async {
    }
    
    public static var argumentBufferDescriptor: ArgumentBufferDescriptor {
        return .init(arguments: [])
    }
}

public struct NilPushConstants : NoArgConstructable {
    @inlinable
    public init() {}
}

public struct NilFunctionConstants : FunctionConstantEncodable & NoArgConstructable {
    @inlinable
    public init() {}
    
    public func encode(into constants: inout FunctionConstants) {
        
    }
}

public protocol RenderPassReflection {
    
    static var attachmentCount : Int { get }
    
    associatedtype VertexFunction : RawRepresentable = NilFunctions where VertexFunction.RawValue == String
    associatedtype FragmentFunction : RawRepresentable = NilFunctions where FragmentFunction.RawValue == String
    associatedtype ComputeFunction : RawRepresentable = NilFunctions where ComputeFunction.RawValue == String
    
    associatedtype FunctionConstants : FunctionConstantEncodable & NoArgConstructable = NilFunctionConstants
    
    associatedtype PushConstants : NoArgConstructable = NilPushConstants
    
    associatedtype Set0 : ShaderResourceSet & NoArgConstructable = NilSet
    associatedtype Set1 : ShaderResourceSet & NoArgConstructable = NilSet
    associatedtype Set2 : ShaderResourceSet & NoArgConstructable = NilSet
    associatedtype Set3 : ShaderResourceSet & NoArgConstructable = NilSet
    associatedtype Set4 : ShaderResourceSet & NoArgConstructable = NilSet
    associatedtype Set5 : ShaderResourceSet & NoArgConstructable = NilSet
    associatedtype Set6 : ShaderResourceSet & NoArgConstructable = NilSet
    associatedtype Set7 : ShaderResourceSet & NoArgConstructable = NilSet
}

extension RenderPassReflection {
    @inlinable
    public static var attachmentCount : Int { 0 }
}

public final class TypedRenderCommandEncoder<R : RenderPassReflection> : AnyRenderCommandEncoder {
    @usableFromInline let encoder : RenderCommandEncoder
    
    var pipelineDescriptorChanged : Bool = false
    var depthStencilDescriptorChanged : Bool = false
    @usableFromInline var hasSetPushConstants : Bool = false
    
    @StateBacked
    public var pipeline : TypedRenderPipelineDescriptor<R> {
        didSet {
            self.pipelineDescriptorChanged = true
        }
    }
    
    public var depthStencil : DepthStencilDescriptor = .init() {
        didSet {
            self.depthStencilDescriptorChanged = true
        }
    }
    
    var resourceSetChangeMask : UInt8 = 0
    
    @usableFromInline var _pushConstants : R.PushConstants
    
    @inlinable // Use a computed property rather than a stored property + didSet so the set can be inlined.
    public var pushConstants : R.PushConstants {
        @inline(__always) get {
            self._pushConstants
        }
        @inline(__always) set {
            let oldValue = self._pushConstants
            self._pushConstants = newValue
            withUnsafeBytes(of: oldValue, { oldValue in
                withUnsafeBytes(of: self._pushConstants, { pushConstants in
                    if !hasSetPushConstants || memcmp(oldValue.baseAddress!, pushConstants.baseAddress!, pushConstants.count) != 0 {
                        self.encoder.setBytes(pushConstants.baseAddress!, length: pushConstants.count, at: RenderBackend.pushConstantPath)
                        hasSetPushConstants = true
                    }
                })
            })
        }
    }
    
    public var set0 : R.Set0 {
        didSet {
            self.resourceSetChangeMask |= 1 << 0
        }
    }
    
    public var set1 : R.Set1 {
        didSet {
            self.resourceSetChangeMask |= 1 << 1
        }
    }
    
    public var set2 : R.Set2 {
        didSet {
            self.resourceSetChangeMask |= 1 << 2
        }
    }
    
    public var set3 : R.Set3 {
        didSet {
            self.resourceSetChangeMask |= 1 << 3
        }
    }
    
    public var set4 : R.Set4 {
        didSet {
            self.resourceSetChangeMask |= 1 << 4
        }
    }
    
    public var set5 : R.Set5 {
        didSet {
            self.resourceSetChangeMask |= 1 << 5
        }
    }
    
    public var set6 : R.Set6 {
        didSet {
            self.resourceSetChangeMask |= 1 << 6
        }
    }
    
    public var set7 : R.Set7 {
        didSet {
            self.resourceSetChangeMask |= 1 << 7
        }
    }
    
    public init(encoder: RenderCommandEncoder) {
        self.encoder = encoder
        
        self._pushConstants = R.PushConstants()
        
        self.set0 = R.Set0()
        self.set1 = R.Set1()
        self.set2 = R.Set2()
        self.set3 = R.Set3()
        self.set4 = R.Set4()
        self.set5 = R.Set5()
        self.set6 = R.Set6()
        self.set7 = R.Set7()
        
        self.pipeline = TypedRenderPipelineDescriptor()
        self.pipeline.descriptor.setPixelFormatsAndSampleCount(from: encoder.renderTargetsDescriptor)
    }
    
    func updateEncoderState() async {
        defer {
            self.pipelineDescriptorChanged = false
            self.depthStencilDescriptorChanged = false
            self.resourceSetChangeMask = 0
        }
        
        if self.depthStencilDescriptorChanged {
            await self.encoder.setDepthStencilDescriptor(self.depthStencil)
        }
        
        if self.pipelineDescriptorChanged {
            self.pipeline.flushConstants()
            self.encoder.setRenderPipelineState(await self.$pipeline.state)
        }
        
        if self.resourceSetChangeMask != 0 {
            if (self.resourceSetChangeMask & (1 << 0)) != 0 {
                await self.encoder.setArguments(&self.set0, at: 0)
            }
            if (self.resourceSetChangeMask & (1 << 1)) != 0 {
                await self.encoder.setArguments(&self.set1, at: 1)
            }
            if (self.resourceSetChangeMask & (1 << 2)) != 0 {
                await self.encoder.setArguments(&self.set2, at: 2)
            }
            if (self.resourceSetChangeMask & (1 << 3)) != 0 {
                await self.encoder.setArguments(&self.set3, at: 3)
            }
            if (self.resourceSetChangeMask & (1 << 4)) != 0 {
                await self.encoder.setArguments(&self.set4, at: 4)
            }
            if (self.resourceSetChangeMask & (1 << 5)) != 0 {
                await self.encoder.setArguments(&self.set5, at: 5)
            }
            if (self.resourceSetChangeMask & (1 << 6)) != 0 {
                await self.encoder.setArguments(&self.set6, at: 6)
            }
            if (self.resourceSetChangeMask & (1 << 7)) != 0 {
                await self.encoder.setArguments(&self.set7, at: 7)
            }
        }
    }
    
    public func pushDebugGroup(_ string: String) {
        self.encoder.pushDebugGroup(string)
    }
    
    public func popDebugGroup() {
        self.encoder.popDebugGroup()
    }
    
    @inlinable
    public func debugGroup<T>(_ groupName: String, perform: () throws -> T) rethrows -> T {
        try self.encoder.debugGroup(groupName, perform: perform)
    }
    
    @inlinable
    public func insertDebugSignpost(_ string: String) {
        self.encoder.insertDebugSignpost(string)
    }
    
    public func setBytes(_ bytes: UnsafeRawPointer, length: Int, at path: ResourceBindingPath) {
        self.encoder.setBytes(bytes, length: length, at: path)
    }
    
    public func setBuffer(_ buffer: Buffer?, offset: Int, at path: ResourceBindingPath) {
        self.encoder.setBuffer(buffer, offset: offset, at: path)
    }
    
    public func setBufferOffset(_ offset: Int, at path: ResourceBindingPath) {
        self.encoder.setBufferOffset(offset, at: path)
    }
    
    public func setSampler(_ descriptor: SamplerDescriptor?, at path: ResourceBindingPath) async {
       await self.encoder.setSampler(descriptor, at: path)
    }
    
    public func setSampler(_ state: SamplerState?, at path: ResourceBindingPath) {
        self.encoder.setSampler(state, at: path)
    }
    
    public func setTexture(_ texture: Texture?, at path: ResourceBindingPath) {
        self.encoder.setTexture(texture, at: path)
    }
    
    public func setArgumentBuffer(_ argumentBuffer: ArgumentBuffer?, at index: Int, stages: RenderStages) {
        self.encoder.setArgumentBuffer(argumentBuffer, at: index, stages: stages)
    }
    
    public func setVertexBuffer(_ buffer: Buffer?, offset: Int, index: Int) {
       self.encoder.setVertexBuffer(buffer, offset: offset, index: index)
    }
    
    public func setVertexBufferOffset(_ offset: Int, index: Int) {
        self.encoder.setVertexBufferOffset(offset, index: index)
    }
    
    public func setViewport(_ viewport: Viewport) {
        self.encoder.setViewport(viewport)
    }
    
    public func setFrontFacing(_ frontFacingWinding: Winding) {
        self.encoder.setFrontFacing(frontFacingWinding)
    }
    
    public func setCullMode(_ cullMode: CullMode) {
        self.encoder.setCullMode(cullMode)
    }
    
    //    @inlinable
    public func setScissorRect(_ rect: ScissorRect) {
        self.encoder.setScissorRect(rect)
    }
    
    public func setDepthBias(_ depthBias: Float, slopeScale: Float, clamp: Float) {
        self.encoder.setDepthBias(depthBias, slopeScale: slopeScale, clamp: clamp)
    }
    
    public func setStencilReferenceValue(_ referenceValue: UInt32) {
        self.encoder.setStencilReferenceValue(referenceValue)
    }
    
    public func setStencilReferenceValues(front frontReferenceValue: UInt32, back backReferenceValue: UInt32) {
        self.encoder.setStencilReferenceValues(front: frontReferenceValue, back: backReferenceValue)
    }
    
    public func drawPrimitives(type primitiveType: PrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int = 1, baseInstance: Int = 0) async {
        await self.updateEncoderState()
        self.encoder.drawPrimitives(type: primitiveType, vertexStart: vertexStart, vertexCount: vertexCount, instanceCount: instanceCount, baseInstance: baseInstance)
    }
    
    public func drawIndexedPrimitives(type primitiveType: PrimitiveType, indexCount: Int, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: Int, instanceCount: Int = 1, baseVertex: Int = 0, baseInstance: Int = 0) async {
        await self.updateEncoderState()
        self.encoder.drawIndexedPrimitives(type: primitiveType, indexCount: indexCount, indexType: indexType, indexBuffer: indexBuffer, indexBufferOffset: indexBufferOffset, instanceCount: instanceCount, baseVertex: baseVertex, baseInstance: baseInstance)
    }
    
    public func useResource<R: ResourceProtocol>(_ resource: R, usage: ResourceUsageType, stages: RenderStages) {
        self.encoder.useResource(resource, usage: usage, stages: stages)
    }
    
    public func useHeap(_ heap: Heap, stages: RenderStages) {
        self.encoder.useHeap(heap, stages: stages)
    }
    
    public func memoryBarrier(scope: BarrierScope, after: RenderStages, before: RenderStages) {
        self.encoder.memoryBarrier(scope: scope, after: after, before: before)
    }
    
    public func memoryBarrier(resources: [Resource], after: RenderStages, before: RenderStages) {
        self.encoder.memoryBarrier(resources: resources, after: after, before: before)
    }
    
    @inlinable
    public func memoryBarrier(resources: [any ResourceProtocol], after: RenderStages, before: RenderStages) {
        self.memoryBarrier(resources: resources.map { Resource($0) }, after: after, before: before)
    }
}


public final class TypedComputeCommandEncoder<R : RenderPassReflection> {
    @usableFromInline let encoder : ComputeCommandEncoder
    
    var pipelineDescriptorChanged : Bool = false
    var hasSetPushConstants : Bool = false
    
    var resourceSetChangeMask : UInt8 = 0
    
    @StateBacked
    public var pipeline : TypedComputePipelineDescriptor<R> {
        didSet {
            self.pipelineDescriptorChanged = true
        }
    }
    
    public var pushConstants : R.PushConstants {
        didSet {
            withUnsafeBytes(of: oldValue, { oldValue in
                withUnsafeBytes(of: self.pushConstants, { pushConstants in
                    if !hasSetPushConstants || memcmp(oldValue.baseAddress!, pushConstants.baseAddress!, pushConstants.count) != 0 {
                        self.encoder.setBytes(&self.pushConstants, length: MemoryLayout<R.PushConstants>.size, at: RenderBackend.pushConstantPath)
                        hasSetPushConstants = true
                    }
                })
            })
        }
    }
    
    public var set0 : R.Set0 {
        didSet {
            self.resourceSetChangeMask |= 1 << 0
        }
    }
    
    public var set1 : R.Set1 {
        didSet {
            self.resourceSetChangeMask |= 1 << 1
        }
    }
    
    public var set2 : R.Set2 {
        didSet {
            self.resourceSetChangeMask |= 1 << 2
        }
    }
    
    public var set3 : R.Set3 {
        didSet {
            self.resourceSetChangeMask |= 1 << 3
        }
    }
    
    public var set4 : R.Set4 {
        didSet {
            self.resourceSetChangeMask |= 1 << 4
        }
    }
    
    public var set5 : R.Set5 {
        didSet {
            self.resourceSetChangeMask |= 1 << 5
        }
    }
    
    public var set6 : R.Set6 {
        didSet {
            self.resourceSetChangeMask |= 1 << 6
        }
    }
    
    public var set7 : R.Set7 {
        didSet {
            self.resourceSetChangeMask |= 1 << 7
        }
    }
    
    public init(encoder: ComputeCommandEncoder) {
        self.encoder = encoder
        
        self.pushConstants = R.PushConstants()
        
        self.set0 = R.Set0()
        self.set1 = R.Set1()
        self.set2 = R.Set2()
        self.set3 = R.Set3()
        self.set4 = R.Set4()
        self.set5 = R.Set5()
        self.set6 = R.Set6()
        self.set7 = R.Set7()
        
        self.pipeline = TypedComputePipelineDescriptor()
    }
    
    public var label : String {
        get {
            return self.encoder.label
        }
        set {
            self.encoder.label = newValue
        }
    }
    
    func updatePipelineState() async {
        if self.pipelineDescriptorChanged {
            self.pipeline.flushConstants()
            self.encoder.setComputePipelineState(await self.$pipeline.state)
            self.pipelineDescriptorChanged = false
        }
    }
    
    func updateEncoderState() async {
        defer {
            self.resourceSetChangeMask = 0
        }
        
        await self.updatePipelineState()
        
        if self.resourceSetChangeMask != 0 {
            if (self.resourceSetChangeMask & (1 << 0)) != 0 {
                await self.encoder.setArguments(&self.set0, at: 0)
            }
            if (self.resourceSetChangeMask & (1 << 1)) != 0 {
                await self.encoder.setArguments(&self.set1, at: 1)
            }
            if (self.resourceSetChangeMask & (1 << 2)) != 0 {
                await self.encoder.setArguments(&self.set2, at: 2)
            }
            if (self.resourceSetChangeMask & (1 << 3)) != 0 {
                await self.encoder.setArguments(&self.set3, at: 3)
            }
            if (self.resourceSetChangeMask & (1 << 4)) != 0 {
                await self.encoder.setArguments(&self.set4, at: 4)
            }
            if (self.resourceSetChangeMask & (1 << 5)) != 0 {
                await self.encoder.setArguments(&self.set5, at: 5)
            }
            if (self.resourceSetChangeMask & (1 << 6)) != 0 {
                await self.encoder.setArguments(&self.set6, at: 6)
            }
            if (self.resourceSetChangeMask & (1 << 7)) != 0 {
                await self.encoder.setArguments(&self.set7, at: 7)
            }
        }
    }
    
    /// The number of threads in a SIMD group/wave for the current pipeline state.
    public var currentThreadExecutionWidth: Int {
        get async {
            await self.updatePipelineState()
            return self.encoder.currentThreadExecutionWidth
        }
    }
    
    public func pushDebugGroup(_ string: String) {
        self.encoder.pushDebugGroup(string)
    }
    
    public func popDebugGroup() {
        self.encoder.popDebugGroup()
    }
    
    @inlinable
    public func debugGroup<T>(_ groupName: String, perform: () throws -> T) rethrows -> T {
        try self.encoder.debugGroup(groupName, perform: perform)
    }
    
    public func setStageInRegion(_ region: Region) {
        self.encoder.setStageInRegion(region)
    }
    
    public func setThreadgroupMemoryLength(_ length: Int, at index: Int) {
        self.encoder.setThreadgroupMemoryLength(length, at: index)
    }
    
    public func setBytes(_ bytes: UnsafeRawPointer, length: Int, at path: ResourceBindingPath) {
        self.encoder.setBytes(bytes, length: length, at: path)
    }
    
    public func setBuffer(_ buffer: Buffer?, offset: Int, at path: ResourceBindingPath) {
        self.encoder.setBuffer(buffer, offset: offset, at: path)
    }
    
    public func setBufferOffset(_ offset: Int, at path: ResourceBindingPath) {
        self.encoder.setBufferOffset(offset, at: path)
    }
    
    public func setSampler(_ descriptor: SamplerDescriptor?, at path: ResourceBindingPath) async {
        await self.encoder.setSampler(descriptor, at: path)
    }
    
    public func setSampler(_ state: SamplerState?, at path: ResourceBindingPath) {
        self.encoder.setSampler(state, at: path)
    }
    
    public func setTexture(_ texture: Texture?, at path: ResourceBindingPath) {
        self.encoder.setTexture(texture, at: path)
    }
    
    public func setArgumentBuffer(_ argumentBuffer: ArgumentBuffer?, at index: Int, stages: RenderStages) {
        self.encoder.setArgumentBuffer(argumentBuffer, at: index, stages: stages)
    }
    
    public func dispatchThreads(_ threadsPerGrid: Size, threadsPerThreadgroup: Size) async {
        await self.updateEncoderState()
        self.encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    }
    
    public func dispatchThreadgroups(_ threadgroupsPerGrid: Size, threadsPerThreadgroup: Size) async {
        await self.updateEncoderState()
        self.encoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    }
    
    public func dispatchThreadgroups(indirectBuffer: Buffer, indirectBufferOffset: Int, threadsPerThreadgroup: Size) async {
        await self.updateEncoderState()
        self.encoder.dispatchThreadgroups(indirectBuffer: indirectBuffer, indirectBufferOffset: indirectBufferOffset, threadsPerThreadgroup: threadsPerThreadgroup)
    }
    
    public func useResource<R: ResourceProtocol>(_ resource: R, usage: ResourceUsageType) {
        self.encoder.useResource(resource, usage: usage)
    }
    
    public func useHeap(_ heap: Heap) {
        self.encoder.useHeap(heap)
    }
    
    public func memoryBarrier(scope: BarrierScope) {
        self.encoder.memoryBarrier(scope: scope)
    }
    
    public func memoryBarrier(resources: [Resource]) {
        self.encoder.memoryBarrier(resources: resources)
    }
    
    @inlinable
    public func memoryBarrier(resources: [any ResourceProtocol]) {
        self.memoryBarrier(resources: resources.map { Resource($0) })
    }
}

extension TypedComputeCommandEncoder : CommandEncoder {
    @usableFromInline
    var passRecord: RenderPassRecord {
        return self.encoder.passRecord
    }
    
    @usableFromInline
    func endEncoding() {
        self.encoder.endEncoding()
    }
}
