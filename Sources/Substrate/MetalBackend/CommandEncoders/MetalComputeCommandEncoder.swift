//
//  File.swift
//  
//
//  Created by Thomas Roughton on 6/07/22.
//

import Foundation
import Metal

final class MetalComputeCommandEncoder: ComputeCommandEncoder {
    let encoder: MTLComputeCommandEncoder
    let resourceMap: FrameResourceMap<MetalBackend>
    
    private var baseBufferOffsets = [Int](repeating: 0, count: 31) // 31 vertex, 31 fragment, since that's the maximum number of entries in a buffer argument table (https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)
    
    init(encoder: MTLComputeCommandEncoder, resourceMap: FrameResourceMap<MetalBackend>) {
        self.encoder = encoder
        self.resourceMap = resourceMap
    }
    
    override func setLabel(_ label: String) {
        encoder.label = label
    }
    
    override func popDebugGroup() {
        encoder.popDebugGroup()
    }
    
    override func insertDebugSignpost(_ string: String) {
        encoder.insertDebugSignpost(string)
    }
    
    override func setBytes(_ bytes: UnsafeRawPointer, length: Int, path: ResourceBindingPath) {
        let index = path.index
        encoder.setBytes(bytes, length: length, index: index)
    }
    
    override func setBuffer(_ buffer: Buffer?, offset: Int, path: ResourceBindingPath) {
        guard let buffer = buffer,
              let mtlBufferRef = resourceMap[buffer] else { return }
        let index = path.index
        encoder.setBuffer(mtlBufferRef.buffer, offset: mtlBufferRef.offset + offset, index: index)
        self.baseBufferOffsets[index] = mtlBufferRef.offset
    }
    
    override func setBufferOffset(_ offset: Int, path: ResourceBindingPath) {
        let index = path.index
        encoder.setBufferOffset(self.baseBufferOffsets[index] + offset, index: index)
    }
    
    override func setTexture(_ texture: Texture?, path: ResourceBindingPath) {
        guard let texture = texture,
              let mtlTexture = self.resourceMap[texture] else { return }
        let index = path.index
        encoder.setTexture(mtlTexture.texture, index: index)
    }
    
    override func setSamplerState(_ state: SamplerState?, path: ResourceBindingPath) {
        guard let state = state else { return }
        
        let index = path.index
        Unmanaged<MTLSamplerState>.fromOpaque(UnsafeRawPointer(state.state))._withUnsafeGuaranteedRef { state in
            encoder.setSamplerState(state, index: index)
        }
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    override func setVisibleFunctionTable(_ table: VisibleFunctionTable?, path: ResourceBindingPath) {
        guard let table = table,
              let mtlTable = self.resourceMap[table] else { return }
        let index = path.index
        encoder.setVisibleFunctionTable(mtlTable.table, bufferIndex: index)
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    override func setIntersectionFunctionTable(_ table: IntersectionFunctionTable?, path: ResourceBindingPath) {
        guard let table = table,
              let mtlTable = self.resourceMap[table] else { return }
        let index = path.index
        encoder.setIntersectionFunctionTable(mtlTable.table, bufferIndex: index)
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    override func setAccelerationStructure(_ structure: AccelerationStructure?, path: ResourceBindingPath) {
        guard let structure = structure,
              let mtlStructure = self.resourceMap[structure] as! MTLAccelerationStructure? else { return }
        let index = path.index
        encoder.setAccelerationStructure(mtlStructure, bufferIndex: index)
    }
    
    override func setComputePipelineState(_ pipelineState: ComputePipelineState) {
        Unmanaged<MTLComputePipelineState>.fromOpaque(UnsafeRawPointer(pipelineState.state))._withUnsafeGuaranteedRef {
            encoder.setComputePipelineState($0)
        }
    }
    
    override func setThreadgroupMemoryLength(_ length: Int, path: ResourceBindingPath) {
        let index = path.index
        encoder.setThreadgroupMemoryLength(length, index: index)
    }
    
    override func dispatchThreadgroups(_ threadgroupsPerGrid: Size, threadsPerThreadgroup: Size) {
        super.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.dispatchThreadgroups(MTLSize(threadgroupsPerGrid), threadsPerThreadgroup: MTLSize(threadsPerThreadgroup))
    }
    
    override func dispatchThreads(_ threadsPerGrid: Size, threadsPerThreadgroup: Size) {
        super.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.dispatchThreads(MTLSize(threadsPerGrid), threadsPerThreadgroup: MTLSize(threadsPerThreadgroup))
    }
    
    override func drawMeshThreadgroups(indirectBuffer: Buffer, indirectBufferOffset: Int, threadsPerThreadgroup: Size) {
        let mtlBuffer = resourceMap[indirectBuffer]!
        encoder.dispatchThreadgroups(indirectBuffer: mtlBuffer.buffer, indirectBufferOffset: mtlBuffer.offset + indirectBufferOffset, threadsPerThreadgroup: MTLSize(threadsPerThreadgroup))
    }
    
    override func useResource(_ resource: Resource, usage: ResourceUsageType, ) {
        encoder.useResource(resourceMap[resource], usage: MTLResourceUsage(usage))
    }
    
    override func useHeap(_ heap: Heap) {
        encoder.useHeap(resourceMap.persistentRegistry[heap]!)
    }
    
    override func memoryBarrier(scope: BarrierScope) {
        encoder.memoryBarrier(scope: MTLBarrierScope(scope))
    }
    
    override func memoryBarrier(resources: [Resource]) {
        let mtlResources = resources.map { resourceMap[$0]! }
        encoder.memoryBarrier(resources: mtlResources)
    }
}
