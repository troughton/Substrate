//
//  File.swift
//  
//
//  Created by Thomas Roughton on 6/07/22.
//

#if canImport(Metal)
import Foundation
import Metal

final class MetalComputeCommandEncoder: ComputeCommandEncoder {
    let encoder: MTLComputeCommandEncoder
    let resourceMap: FrameResourceMap<MetalBackend>
    let isAppleSiliconGPU: Bool
    
    private var baseBufferOffsets = [Int](repeating: 0, count: 31) // 31 vertex, 31 fragment, since that's the maximum number of entries in a buffer argument table (https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)
    
    init(passRecord: RenderPassRecord, encoder: MTLComputeCommandEncoder, resourceMap: FrameResourceMap<MetalBackend>, isAppleSiliconGPU: Bool) {
        self.encoder = encoder
        self.resourceMap = resourceMap
        self.isAppleSiliconGPU = isAppleSiliconGPU
        super.init(renderPass: passRecord.pass as! ComputeRenderPass, passRecord: passRecord)
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
    
    override func setBytes(_ bytes: UnsafeRawPointer, length: Int, at path: ResourceBindingPath) {
        let index = path.index
        encoder.setBytes(bytes, length: length, index: index)
    }
    
    override func setBuffer(_ buffer: Buffer?, offset: Int, at path: ResourceBindingPath) {
        guard let buffer = buffer,
              let mtlBufferRef = resourceMap[buffer] else { return }
        let index = path.index
        encoder.setBuffer(mtlBufferRef.buffer, offset: mtlBufferRef.offset + offset, index: index)
        self.baseBufferOffsets[index] = mtlBufferRef.offset
    }
    
    override func setBufferOffset(_ offset: Int, at path: ResourceBindingPath) {
        let index = path.index
        encoder.setBufferOffset(self.baseBufferOffsets[index] + offset, index: index)
    }
    
    override func setTexture(_ texture: Texture?, at path: ResourceBindingPath) {
        guard let texture = texture,
              let mtlTexture = self.resourceMap[texture] else { return }
        let index = path.index
        encoder.setTexture(mtlTexture.texture, index: index)
    }
    
    
    override func setSampler(_ descriptor: SamplerDescriptor?, at path: ResourceBindingPath) async {
        guard let descriptor = descriptor else { return }
        let sampler = await self.resourceMap.persistentRegistry[descriptor]
        self.setSampler(SamplerState(descriptor: descriptor, state: OpaquePointer(Unmanaged.passUnretained(sampler).toOpaque())), at: path)
    }
    
    override func setSampler(_ state: SamplerState?, at path: ResourceBindingPath) {
        guard let state = state else { return }
        
        let index = path.index
        Unmanaged<MTLSamplerState>.fromOpaque(UnsafeRawPointer(state.state))._withUnsafeGuaranteedRef { state in
            encoder.setSamplerState(state, index: index)
        }
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    override func setVisibleFunctionTable(_ table: VisibleFunctionTable?, at path: ResourceBindingPath) {
        guard let table = table,
              let mtlTable = self.resourceMap[table] else { return }
        let index = path.index
        encoder.setVisibleFunctionTable(mtlTable.table, bufferIndex: index)
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    override func setIntersectionFunctionTable(_ table: IntersectionFunctionTable?, at path: ResourceBindingPath) {
        guard let table = table,
              let mtlTable = self.resourceMap[table] else { return }
        let index = path.index
        encoder.setIntersectionFunctionTable(mtlTable.table, bufferIndex: index)
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    override func setAccelerationStructure(_ structure: AccelerationStructure?, at path: ResourceBindingPath) {
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
    
    override func setThreadgroupMemoryLength(_ length: Int, at index: Int) {
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
    
    override func useResource(_ resource: Resource, usage: ResourceUsageType) {
        guard let mtlResource = resourceMap[resource] else {
            return
        }
        encoder.useResource(mtlResource, usage: MTLResourceUsage(usage, isAppleSiliconGPU: self.isAppleSiliconGPU))
    }
    
    override func useHeap(_ heap: Heap) {
        encoder.useHeap(resourceMap.persistentRegistry[heap]!)
    }
    
    override func memoryBarrier(scope: BarrierScope) {
        encoder.memoryBarrier(scope: MTLBarrierScope(scope, isAppleSiliconGPU: self.isAppleSiliconGPU))
    }
    
    override func memoryBarrier(resources: [Resource]) {
        let mtlResources = resources.map { resourceMap[$0]! }
        encoder.memoryBarrier(resources: mtlResources)
    }
}


extension MTLComputeCommandEncoder {
    func executeResourceCommands(resourceCommandIndex: inout Int, resourceCommands: [CompactedResourceCommand<MetalCompactedResourceCommandType>], passIndex: Int, order: PerformOrder, isAppleSiliconGPU: Bool) {
        while resourceCommandIndex < resourceCommands.count {
            let command = resourceCommands[resourceCommandIndex]
            
            guard command.index < passIndex || (command.index == passIndex && command.order == order) else {
                break
            }
            
            switch command.command {
            case .resourceMemoryBarrier(let resources, _, _):
                self.__memoryBarrier(resources: resources.baseAddress!, count: resources.count)

            case .scopedMemoryBarrier(let scope, _, _):
                self.memoryBarrier(scope: scope)
                
            case .updateFence(let fence, _):
                self.updateFence(fence.fence)
                
            case .waitForFence(let fence, _):
                self.waitForFence(fence.fence)
                
            case .useResources(let resources, let usage, _):
                self.__use(resources.baseAddress!, count: resources.count, usage: usage)
            }
            
            resourceCommandIndex += 1
        }
    }
}

#endif // canImport(Metal)
