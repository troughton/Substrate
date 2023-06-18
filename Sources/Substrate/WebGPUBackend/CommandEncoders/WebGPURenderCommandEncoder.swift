#if canImport(WebGPU)
import WebGPU

struct WebGPUBufferReference {
    let buffer: WGPUBuffer
    let offset: Int
}

extension Buffer {
    var wgpuBuffer: WebGPUBufferReference? {
        preconditionFailure()
    }
}

extension ArgumentBuffer {
    var wgpuBindGroup: WGPUBindGroup? {
        preconditionFailure()
    }
}

final class WebGPURenderCommandEncoder: RenderCommandEncoderImpl {
    let encoder: WGPURenderPassEncoder
    
    private var boundVertexBuffers = [(buffer: WebGPUBufferReference, length: Int)?](repeating: nil, count: 31)
    
    init(passRecord: RenderPassRecord, encoder: WGPURenderPassEncoder) {
        self.encoder = encoder
    }
    
    func pushDebugGroup(_ string: String) {
        wgpuRenderPassEncoderPushDebugGroup(self.encoder, string)
    }
    
    func popDebugGroup() {
        wgpuRenderPassEncoderPopDebugGroup(self.encoder)
    }
    
    func insertDebugSignpost(_ string: String) {
        wgpuRenderPassEncoderInsertDebugMarker(self.encoder, string)
    }
    
    func setLabel(_ label: String) {
        wgpuRenderPassEncoderSetLabel(self.encoder, label)
    }
    
    func setBytes(_ bytes: UnsafeRawPointer, length: Int, at path: ResourceBindingPath) {
        preconditionFailure("setBytes is unsupported on WebGPU")
    }
    
    func setVertexBuffer(_ buffer: Buffer, offset: Int, index: Int) {
        guard let bufferRef = buffer.wgpuBuffer else { return }
        
        let bindOffset = bufferRef.offset + offset
        wgpuRenderPassEncoderSetVertexBuffer(self.encoder, UInt32(index), bufferRef.buffer, UInt64(bindOffset), UInt64(buffer.length - offset))
        self.boundVertexBuffers[index] = (bufferRef, buffer.length)
    }
    
    func setVertexBufferOffset(_ offset: Int, index: Int) {
        assert(index < 31, "The maximum number of buffers allowed in the buffer argument table for a single function is 31.")
        
        guard let (bufferRef, bufferLength) = self.boundVertexBuffers[index] else { return }
        
        let bindOffset = bufferRef.offset + offset
        wgpuRenderPassEncoderSetVertexBuffer(self.encoder, UInt32(index), bufferRef.buffer, UInt64(bindOffset), UInt64(bufferLength - offset))
    }
    
    func setArgumentBuffer(_ argumentBuffer: ArgumentBuffer, at index: Int, stages: RenderStages) {
        let bindGroup = argumentBuffer.wgpuBindGroup!

        wgpuRenderPassEncoderSetBindGroup(self.encoder, UInt32(index), bindGroup, 0, nil)
    }
    
    func setBuffer(_ buffer: Buffer, offset: Int, at path: ResourceBindingPath) {
        preconditionFailure("setBuffer is unsupported on WebGPU")
    }
    
    func setBufferOffset(_ offset: Int, at path: ResourceBindingPath) {
        preconditionFailure("setBufferOffset is unsupported on WebGPU")
    }
    
    func setTexture(_ texture: Texture, at path: ResourceBindingPath) {
        preconditionFailure("setTexture is unsupported on WebGPU")
    }
    
    func setSampler(_ state: SamplerState, at path: ResourceBindingPath) {
        preconditionFailure("setTexture is unsupported on WebGPU")
    }
    
    @available(macOS 12.0, iOS 15.0, *)
    func setVisibleFunctionTable(_ table: VisibleFunctionTable, at path: ResourceBindingPath) {
        preconditionFailure("setVisibleFunctionTable is unsupported on WebGPU")
    }
    
    @available(macOS 12.0, iOS 15.0, *)
    func setIntersectionFunctionTable(_ table: IntersectionFunctionTable, at path: ResourceBindingPath) {
        preconditionFailure("setIntersectionFunctionTable is unsupported on WebGPU")
    }
    
    @available(macOS 12.0, iOS 15.0, *)
    func setAccelerationStructure(_ structure: AccelerationStructure, at path: ResourceBindingPath) {
        preconditionFailure("setAccelerationStructure is unsupported on WebGPU")
    }
    
    func setViewport(_ viewport: Viewport) {
        wgpuRenderPassEncoderSetViewport(self.encoder, Float(viewport.originX), Float(viewport.originY), Float(viewport.width), Float(viewport.width), Float(viewport.zNear), Float(viewport.zFar))
    }
    
    func setFrontFacing(_ winding: Winding) {
        wgpuRenderPassEncoderSet
    }
    
    func setCullMode(_ cullMode: CullMode) {
        encoder.setCullMode(MTLCullMode(cullMode))
    }
    
    func setDepthBias(_ depthBias: Float, slopeScale: Float, clamp: Float) {
        encoder.setDepthBias(depthBias, slopeScale: slopeScale, clamp: clamp)
    }
    
    func setScissorRect(_ rect: ScissorRect) {
        wgpuRenderPassEncoderSetScissorRect(self.encoder, UInt32(rect.x), UInt32(rect.y), UInt32(rect.width), UInt32(rect.height))
    }
    
    func setBlendColor(red: Float, green: Float, blue: Float, alpha: Float) {
        var color = WGPUColor(r: Double(red), g: Double(green), b: Double(blue), a: Double(alpha))
        withUnsafePointer(to: color) { color in
            wgpuRenderPassEncoderSetBlendConstant(self.encoder, color)
        }
    }
    
    func setRenderPipelineState(_ pipelineState: RenderPipelineState) {
        Unmanaged<MTLRenderPipelineState>.fromOpaque(UnsafeRawPointer(pipelineState.state))._withUnsafeGuaranteedRef {
            encoder.setRenderPipelineState($0)
        }
        
        encoder.setTriangleFillMode(MTLTriangleFillMode(pipelineState.descriptor.fillMode))
    }
    
    func setDepthStencilState(_ depthStencilState: DepthStencilState) {
        Unmanaged<MTLDepthStencilState>.fromOpaque(UnsafeRawPointer(depthStencilState.state))._withUnsafeGuaranteedRef {
            encoder.setDepthStencilState($0)
        }
        encoder.setDepthClipMode(MTLDepthClipMode(depthStencilState.descriptor.depthClipMode))
    }
    
    func setStencilReferenceValue(_ referenceValue: UInt32) {
        wgpuRenderPassEncoderSetStencilReference(self.encoder, referenceValue)
    }
    
    func setStencilReferenceValues(front frontReferenceValue: UInt32, back backReferenceValue: UInt32) {
        guard frontReferenceValue == backReferenceValue else { preconditionFailure("Differing front and back reference values are unsupported on WebGPU") }
        wgpuRenderPassEncoderSetStencilReference(self.encoder, frontReferenceValue)
    }
    
    @available(macOS 12.0, iOS 15.0, *)
    func setThreadgroupMemoryLength(_ length: Int, at path: ResourceBindingPath) {
        preconditionFailure("setThreadgroupMemoryLength is unsupported on WebGPU")
    }
    
    func drawPrimitives(type primitiveType: PrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int = 1, baseInstance: Int = 0) {
        wgpuRenderPassEncoderDraw(self.encoder, UInt32(vertexCount), UInt32(instanceCount), UInt32(vertexStart), UInt32(baseInstance))
    }
    
    func drawPrimitives(type primitiveType: PrimitiveType, indirectBuffer: Buffer, indirectBufferOffset: Int) {
        let wgpuBuffer = indirectBuffer.wgpuBuffer!
        wgpuRenderPassEncoderDrawIndirect(self.encoder, wgpuBuffer.buffer, UInt64(wgpuBuffer.offset + indirectBufferOffset))
    }
    
    func drawIndexedPrimitives(type primitiveType: PrimitiveType, indexCount: Int, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: Int, instanceCount: Int = 1, baseVertex: Int = 0, baseInstance: Int = 0) {
        guard let indexFormat = WGPUIndexFormat(indexType) else { preconditionFailure("IndexType \(indexType) is unsupported on WebGPU") }
        
        let wgpuBuffer = indexBuffer.wgpuBuffer!
        let offset = indexBufferOffset + wgpuBuffer.offset
        wgpuRenderPassEncoderSetIndexBuffer(self.encoder, wgpuBuffer.buffer, indexFormat, UInt64(offset), UInt64(indexBuffer.length - indexBufferOffset))
        wgpuRenderPassEncoderDrawIndexed(self.encoder, UInt32(indexCount), UInt32(instanceCount), 0, Int32(baseVertex), UInt32(baseInstance))
    }
    
    
    func drawIndexedPrimitives(type primitiveType: PrimitiveType, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: Int, indirectBuffer: Buffer, indirectBufferOffset: Int) {
        guard let indexFormat = WGPUIndexFormat(indexType) else { preconditionFailure("IndexType \(indexType) is unsupported on WebGPU") }
        
        let wgpuBuffer = indexBuffer.wgpuBuffer!
        let offset = indexBufferOffset + wgpuBuffer.offset
        wgpuRenderPassEncoderSetIndexBuffer(self.encoder, wgpuBuffer.buffer, indexFormat, UInt64(offset), UInt64(indexBuffer.length - indexBufferOffset))
        
        let wgpuIndirectBuffer = indirectBuffer.wgpuBuffer!
        wgpuRenderPassEncoderDrawIndexedIndirect(self.encoder, wgpuIndirectBuffer.buffer, UInt64(wgpuIndirectBuffer.offset + indirectBufferOffset))
    }
    
    
    @available(macOS 13.0, iOS 16.0, *)
    func drawMeshThreadgroups(_ threadgroupsPerGrid: Size, threadsPerObjectThreadgroup: Size, threadsPerMeshThreadgroup: Size) {
        preconditionFailure("drawMeshThreadgroups is unsupported on WebGPU")
    }
    
    @available(macOS 13.0, iOS 16.0, *)
    func drawMeshThreads(_ threadsPerGrid: Size, threadsPerObjectThreadgroup: Size, threadsPerMeshThreadgroup: Size) {
        preconditionFailure("drawMeshThreads is unsupported on WebGPU")
    }
    
    @available(macOS 13.0, iOS 16.0, *)
    func drawMeshThreadgroups(indirectBuffer: Buffer, indirectBufferOffset: Int, threadsPerObjectThreadgroup: Size, threadsPerMeshThreadgroup: Size) {
        preconditionFailure("drawMeshThreadgroups is unsupported on WebGPU")
    }
    
    func dispatchThreadsPerTile(_ threadsPerTile: Size) {
        preconditionFailure("dispatchThreadsPerTile is unsupported on WebGPU")
    }
    
    func useResource(_ resource: Resource, usage: ResourceUsageType, stages: RenderStages) {
    }
    
    func useHeap(_ heap: Heap, stages: RenderStages) {
    }
    
    func memoryBarrier(scope: BarrierScope, after: RenderStages, before: RenderStages) {
    }
    
    func memoryBarrier(resources: [Resource], after: RenderStages, before: RenderStages) {
    }
}

#endif // canImport(WebGPU)
