//
//  TypedCommandRecorder.swift
//  SwiftFrameGraph
//
//  Created by Thomas Roughton on 6/06/19.
//

import Foundation

public protocol NoArgConstructable {
    init()
}

public protocol ShaderDescriptorSet : NoArgConstructable & ArgumentBufferEncodable {}

public struct NilFunctions : RawRepresentable {
    public typealias RawValue = String
    
    public init?(rawValue: Self.RawValue) {
        return nil
    }
    
    public var rawValue: String {
        fatalError()
    }
}

public struct NilSet : ShaderDescriptorSet {
    public static var activeStages: RenderStages = []
    
    public static var bindingIndex: Int {
        return -1
    }
    
    @inlinable
    public init() {}
    
    public func encode(into argBuffer: _ArgumentBuffer, setIndex: Int, bindingEncoder: ResourceBindingEncoder?) {
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
    
    associatedtype Set0 : ArgumentBufferEncodable & NoArgConstructable = NilSet
    associatedtype Set1 : ArgumentBufferEncodable & NoArgConstructable = NilSet
    associatedtype Set2 : ArgumentBufferEncodable & NoArgConstructable = NilSet
    associatedtype Set3 : ArgumentBufferEncodable & NoArgConstructable = NilSet
    associatedtype Set4 : ArgumentBufferEncodable & NoArgConstructable = NilSet
    associatedtype Set5 : ArgumentBufferEncodable & NoArgConstructable = NilSet
    associatedtype Set6 : ArgumentBufferEncodable & NoArgConstructable = NilSet
    associatedtype Set7 : ArgumentBufferEncodable & NoArgConstructable = NilSet
}

extension RenderPassReflection {
    @inlinable
    public static var attachmentCount : Int { 0 }
}

public final class TypedRenderCommandEncoder<R : RenderPassReflection> : AnyRenderCommandEncoder {
    @usableFromInline let encoder : RenderCommandEncoder
    
    var pipelineDescriptorChanged : Bool = false
    var depthStencilDescriptorChanged : Bool = false
    var hasSetPushConstants : Bool = false
    
    public var pipeline : TypedRenderPipelineDescriptor<R> {
        didSet {
            self.pipelineDescriptorChanged = true
        }
    }
    
    public var depthStencil : DepthStencilDescriptor {
        get {
            return self.encoder.depthStencilDescriptor.unsafelyUnwrapped
        }
        set {
            self.encoder.depthStencilDescriptor = newValue
            self.depthStencilDescriptorChanged = true
        }
    }
    
    var descriptorSetChangeMask : UInt8 = 0
    
    public var pushConstants : R.PushConstants {
        didSet {
            withUnsafeBytes(of: oldValue, { oldValue in
                withUnsafeBytes(of: self.pushConstants, { pushConstants in
                    if !hasSetPushConstants || memcmp(oldValue.baseAddress!, pushConstants.baseAddress!, pushConstants.count) != 0 {
                        self.encoder.setBytes(&self.pushConstants, length: MemoryLayout<R.PushConstants>.size, path: RenderBackend.pushConstantPath)
                        hasSetPushConstants = true
                    }
                })
            })
        }
    }
    
    public var set0 : R.Set0 {
        didSet {
            self.descriptorSetChangeMask |= 1 << 0
        }
    }
    
    public var set1 : R.Set1 {
        didSet {
            self.descriptorSetChangeMask |= 1 << 1
        }
    }
    
    public var set2 : R.Set2 {
        didSet {
            self.descriptorSetChangeMask |= 1 << 2
        }
    }
    
    public var set3 : R.Set3 {
        didSet {
            self.descriptorSetChangeMask |= 1 << 3
        }
    }
    
    public var set4 : R.Set4 {
        didSet {
            self.descriptorSetChangeMask |= 1 << 4
        }
    }
    
    public var set5 : R.Set5 {
        didSet {
            self.descriptorSetChangeMask |= 1 << 5
        }
    }
    
    public var set6 : R.Set6 {
        didSet {
            self.descriptorSetChangeMask |= 1 << 6
        }
    }
    
    public var set7 : R.Set7 {
        didSet {
            self.descriptorSetChangeMask |= 1 << 7
        }
    }
    
    public init(encoder: RenderCommandEncoder) {
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
        
        self.pipeline = TypedRenderPipelineDescriptor(attachmentCount: R.attachmentCount)
        self.encoder.depthStencilDescriptor = DepthStencilDescriptor()
    }
    
    func updateEncoderState() {
        defer {
            self.pipelineDescriptorChanged = false
            self.depthStencilDescriptorChanged = false
            self.descriptorSetChangeMask = 0
        }
        
        if self.depthStencilDescriptorChanged {
            self.encoder.setDepthStencilDescriptor(self.depthStencil)
        }
        
        if self.pipelineDescriptorChanged {
            self.pipeline.flushConstants()
            self.encoder.setRenderPipelineDescriptor(self.pipeline.descriptor)
        }
        
        if self.descriptorSetChangeMask != 0 {
            if (self.descriptorSetChangeMask & (1 << 0)) != 0 {
                self.encoder.setArguments(self.set0, at: 0)
            }
            if (self.descriptorSetChangeMask & (1 << 1)) != 0 {
                self.encoder.setArguments(self.set1, at: 1)
            }
            if (self.descriptorSetChangeMask & (1 << 2)) != 0 {
                self.encoder.setArguments(self.set2, at: 2)
            }
            if (self.descriptorSetChangeMask & (1 << 3)) != 0 {
                self.encoder.setArguments(self.set3, at: 3)
            }
            if (self.descriptorSetChangeMask & (1 << 4)) != 0 {
                self.encoder.setArguments(self.set4, at: 4)
            }
            if (self.descriptorSetChangeMask & (1 << 5)) != 0 {
                self.encoder.setArguments(self.set5, at: 5)
            }
            if (self.descriptorSetChangeMask & (1 << 6)) != 0 {
                self.encoder.setArguments(self.set6, at: 6)
            }
            if (self.descriptorSetChangeMask & (1 << 7)) != 0 {
                self.encoder.setArguments(self.set7, at: 7)
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
    
    public func setArgumentBuffer<K>(_ argumentBuffer: ArgumentBuffer<K>?, at index: Int, stages: RenderStages) {
        self.encoder.setArgumentBuffer(argumentBuffer, at: index, stages: stages)
    }
    
    public func setArgumentBufferArray<K>(_ argumentBufferArray: ArgumentBufferArray<K>?, at index: Int, stages: RenderStages, assumeConsistentUsage: Bool = false) {
        self.encoder.setArgumentBufferArray(argumentBufferArray, at: index, stages: stages, assumeConsistentUsage: assumeConsistentUsage)
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
    
    public func setTriangleFillMode(_ fillMode: TriangleFillMode) {
        self.encoder.setTriangleFillMode(fillMode)
    }
    
    //    @inlinable
    public func setScissorRect(_ rect: ScissorRect) {
        self.encoder.setScissorRect(rect)
    }
    
    public func setDepthClipMode(_ depthClipMode: DepthClipMode) {
        self.encoder.setDepthClipMode(depthClipMode)
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
    
    public func drawPrimitives(type primitiveType: PrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int = 1, baseInstance: Int = 0) {
        self.updateEncoderState()
        self.encoder.drawPrimitives(type: primitiveType, vertexStart: vertexStart, vertexCount: vertexCount, instanceCount: instanceCount, baseInstance: baseInstance)
    }
    
    public func drawIndexedPrimitives(type primitiveType: PrimitiveType, indexCount: Int, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: Int, instanceCount: Int = 1, baseVertex: Int = 0, baseInstance: Int = 0) {
        self.updateEncoderState()
        self.encoder.drawIndexedPrimitives(type: primitiveType, indexCount: indexCount, indexType: indexType, indexBuffer: indexBuffer, indexBufferOffset: indexBufferOffset, instanceCount: instanceCount, baseVertex: baseVertex, baseInstance: baseInstance)
    }
}


public final class TypedComputeCommandEncoder<R : RenderPassReflection> {
    @usableFromInline let encoder : ComputeCommandEncoder
    
    var pipelineDescriptorChanged : Bool = false
    var hasSetPushConstants : Bool = false
    
    var descriptorSetChangeMask : UInt8 = 0
    
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
                        self.encoder.setBytes(&self.pushConstants, length: MemoryLayout<R.PushConstants>.size, path: RenderBackend.pushConstantPath)
                        hasSetPushConstants = true
                    }
                })
            })
        }
    }
    
    public var set0 : R.Set0 {
        didSet {
            self.descriptorSetChangeMask |= 1 << 0
        }
    }
    
    public var set1 : R.Set1 {
        didSet {
            self.descriptorSetChangeMask |= 1 << 1
        }
    }
    
    public var set2 : R.Set2 {
        didSet {
            self.descriptorSetChangeMask |= 1 << 2
        }
    }
    
    public var set3 : R.Set3 {
        didSet {
            self.descriptorSetChangeMask |= 1 << 3
        }
    }
    
    public var set4 : R.Set4 {
        didSet {
            self.descriptorSetChangeMask |= 1 << 4
        }
    }
    
    public var set5 : R.Set5 {
        didSet {
            self.descriptorSetChangeMask |= 1 << 5
        }
    }
    
    public var set6 : R.Set6 {
        didSet {
            self.descriptorSetChangeMask |= 1 << 6
        }
    }
    
    public var set7 : R.Set7 {
        didSet {
            self.descriptorSetChangeMask |= 1 << 7
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
    
    func updateEncoderState() {
        defer {
            self.pipelineDescriptorChanged = false
            self.descriptorSetChangeMask = 0
        }
        
        if self.pipelineDescriptorChanged {
            self.pipeline.flushConstants()
            self.encoder.setComputePipelineDescriptor(self.pipeline.descriptor)
        }
        
        if self.descriptorSetChangeMask != 0 {
            if (self.descriptorSetChangeMask & (1 << 0)) != 0 {
                self.encoder.setArguments(self.set0, at: 0)
            }
            if (self.descriptorSetChangeMask & (1 << 1)) != 0 {
                self.encoder.setArguments(self.set1, at: 1)
            }
            if (self.descriptorSetChangeMask & (1 << 2)) != 0 {
                self.encoder.setArguments(self.set2, at: 2)
            }
            if (self.descriptorSetChangeMask & (1 << 3)) != 0 {
                self.encoder.setArguments(self.set3, at: 3)
            }
            if (self.descriptorSetChangeMask & (1 << 4)) != 0 {
                self.encoder.setArguments(self.set4, at: 4)
            }
            if (self.descriptorSetChangeMask & (1 << 5)) != 0 {
                self.encoder.setArguments(self.set5, at: 5)
            }
            if (self.descriptorSetChangeMask & (1 << 6)) != 0 {
                self.encoder.setArguments(self.set6, at: 6)
            }
            if (self.descriptorSetChangeMask & (1 << 7)) != 0 {
                self.encoder.setArguments(self.set7, at: 7)
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
    
    public func setStageInRegion(_ region: Region) {
        self.encoder.setStageInRegion(region)
    }
    
    public func setThreadgroupMemoryLength(_ length: Int, index: Int) {
        self.encoder.setThreadgroupMemoryLength(length, index: index)
    }
    
    public func dispatchThreads(_ threadsPerGrid: Size, threadsPerThreadgroup: Size) {
        self.updateEncoderState()
        self.encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    }
    
    public func dispatchThreadgroups(_ threadgroupsPerGrid: Size, threadsPerThreadgroup: Size) {
        self.updateEncoderState()
        self.encoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
    }
    
    public func dispatchThreadgroups(indirectBuffer: Buffer, indirectBufferOffset: Int, threadsPerThreadgroup: Size) {
        self.updateEncoderState()
        self.encoder.dispatchThreadgroups(indirectBuffer: indirectBuffer, indirectBufferOffset: indirectBufferOffset, threadsPerThreadgroup: threadsPerThreadgroup)
    }
}

extension TypedComputeCommandEncoder : CommandEncoder {
    public var passRecord: RenderPassRecord {
        return self.encoder.passRecord
    }
    
    public var commandRecorder: FrameGraphCommandRecorder {
        return self.encoder.commandRecorder
    }
    
    public var startCommandIndex: Int {
        return self.encoder.startCommandIndex
    }
    
    public func endEncoding() {
        self.encoder.endEncoding()
    }
}
