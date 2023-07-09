#if canImport(WebGPU)
import WebGPU

final class WebGPUComputeCommandEncoder: ComputeCommandEncoderImpl {
    let encoder: WGPUComputePassEncoder
    
    init(passRecord: RenderPassRecord, encoder: WGPUComputePassEncoder) {
        self.encoder = encoder
    }
    
    func pushDebugGroup(_ string: String) {
        wgpuComputePassEncoderPushDebugGroup(self.encoder, string)
    }
    
    func popDebugGroup() {
        wgpuComputePassEncoderPopDebugGroup(self.encoder)
    }
    
    func insertDebugSignpost(_ string: String) {
        wgpuRenderPassEncoderInsertDebugMarker(self.encoder, string)
    }
    
    func setLabel(_ label: String) {
        wgpuComputePassEncoderSetLabel(self.encoder, label)
    }
    
    func setVisibleFunctionTable(_ table: VisibleFunctionTable, at path: ResourceBindingPath) {
        unavailableFunction(.webGPU)
    }
    
    func setIntersectionFunctionTable(_ table: IntersectionFunctionTable, at path: ResourceBindingPath) {
        unavailableFunction(.webGPU)
    }
    
    func setAccelerationStructure(_ structure: AccelerationStructure, at path: ResourceBindingPath) {
        unavailableFunction(.webGPU)
    }
    
    func setComputePipelineState(_ pipelineState: ComputePipelineState) {
        wgpuComputePassEncoderSetPipeline(self.encoder, pipelineState.state)
    }
    
    func setStageInRegion(_ region: Region) {
        unavailableFunction(.webGPU)
    }
    
    func setThreadgroupMemoryLength(_ length: Int, at index: Int) {
        unavailableFunction(.webGPU)
    }
    
    func dispatchThreadgroups(_ threadgroupsPerGrid: Size, threadsPerThreadgroup: Size) {
        wgpuComputePassEncoderDispatchWorkgroups(self.encoder, UInt32(threadgroupsPerGrid.width), UInt32(threadgroupsPerGrid.height), UInt32(threadgroupsPerGrid.depth))
    }
    
    func dispatchThreadgroups(indirectBuffer: Buffer, indirectBufferOffset: Int, threadsPerThreadgroup: Size) {
        let bufferReference = indirectBuffer.wgpuBuffer!
        
        wgpuComputePassEncoderDispatchWorkgroupsIndirect(self.encoder, bufferReference.buffer, UInt64(bufferReference.offset + indirectBufferOffset))
    }
    
    func dispatchThreads(_ threadsPerGrid: Size, threadsPerThreadgroup: Size) {
        let width = (threadsPerGrid.width + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width
        let height = (threadsPerGrid.height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height
        let depth = (threadsPerGrid.depth + threadsPerThreadgroup.depth - 1) / threadsPerThreadgroup.depth
        
        wgpuComputePassEncoderDispatchWorkgroups(self.encoder, UInt32(width), UInt32(height), UInt32(depth))
    }
    
    func drawMeshThreadgroups(indirectBuffer: Buffer, indirectBufferOffset: Int, threadsPerThreadgroup: Size) {
        unavailableFunction(.webGPU)
    }
    
    func useResource(_ resource: Resource, usage: ResourceUsageType) {
        
    }
    
    func useHeap(_ heap: Heap) {
        
    }
    
    func memoryBarrier(scope: BarrierScope) {
        
    }
    
    func memoryBarrier(resources: [Resource]) {
        
    }
    
    func setBytes(_ bytes: UnsafeRawPointer, length: Int, at path: ResourceBindingPath) {
        unavailableFunction(.webGPU)
    }
    
    func setBuffer(_ buffer: Buffer, offset: Int, at path: ResourceBindingPath) {
        unavailableFunction(.webGPU)
    }
    
    func setBufferOffset(_ offset: Int, at path: ResourceBindingPath) {
        unavailableFunction(.webGPU)
    }
    
    func setTexture(_ texture: Texture, at path: ResourceBindingPath) {
        unavailableFunction(.webGPU)
    }
    
    func setSampler(_ state: SamplerState, at path: ResourceBindingPath) {
        unavailableFunction(.webGPU)
    }
    
    func setArgumentBuffer(_ argumentBuffer: ArgumentBuffer, at index: Int, stages: RenderStages) {
        let bindGroup = argumentBuffer.wgpuBindGroup!

        wgpuRenderPassEncoderSetBindGroup(self.encoder, UInt32(index), bindGroup, 0, nil)
    }
}

#endif // canImport(WebGPU)
