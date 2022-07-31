//
//  File.swift
//  
//
//  Created by Thomas Roughton on 6/07/22.
//

#if canImport(Metal)
import Foundation
import Metal

final class MetalComputeCommandEncoder: ComputeCommandEncoderImpl {
    
    let encoder: MTLComputeCommandEncoder
    let resourceMap: FrameResourceMap<MetalBackend>
    let isAppleSiliconGPU: Bool
    
    private var baseBufferOffsets = [Int](repeating: 0, count: 31) // 31 vertex, 31 fragment, since that's the maximum number of entries in a buffer argument table (https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)
    
    init(encoder: MTLComputeCommandEncoder, resourceMap: FrameResourceMap<MetalBackend>, isAppleSiliconGPU: Bool) {
        self.encoder = encoder
        self.resourceMap = resourceMap
        self.isAppleSiliconGPU = isAppleSiliconGPU
    }
    
    func setLabel(_ label: String) {
        encoder.label = label
    }
    
    func pushDebugGroup(_ groupName: String) {
        encoder.pushDebugGroup(groupName)
    }
    
    func popDebugGroup() {
        encoder.popDebugGroup()
    }
    
    func insertDebugSignpost(_ string: String) {
        encoder.insertDebugSignpost(string)
    }
    
    func setArgumentBuffer(_ argumentBuffer: ArgumentBuffer, at index: Int, stages: RenderStages) {
        if !argumentBuffer.flags.contains(.persistent) {
            _ = resourceMap.transientRegistry!.allocateArgumentBufferIfNeeded(argumentBuffer)
        }
            
        let bufferStorage = resourceMap[argumentBuffer]
        if !argumentBuffer.stateFlags.contains(.initialised) {
            argumentBuffer.setArguments(storage: bufferStorage, resourceMap: self.resourceMap)
        }
        
        let bindIndex = index + 1 // since buffer 0 is push constants
        encoder.setBuffer(bufferStorage.buffer, offset: bufferStorage.offset, index: bindIndex)
        self.baseBufferOffsets[bindIndex] = bufferStorage.offset
    }
    
    func setArgumentBufferArray(_ argumentBufferArray: ArgumentBufferArray, at index: Int, stages: RenderStages) {
        if !argumentBufferArray.flags.contains(.persistent) {
            _ = resourceMap.transientRegistry!.allocateArgumentBufferArrayIfNeeded(argumentBufferArray)
        }
            
        let bufferStorage = resourceMap[argumentBufferArray]
        if !argumentBufferArray._bindings.contains(where: { !($0?.stateFlags ?? .initialised).contains(.initialised) }) {
            argumentBufferArray.setArguments(storage: bufferStorage, resourceMap: self.resourceMap)
        }
        
        let bindIndex = index + 1 // since buffer 0 is push constants
        encoder.setBuffer(bufferStorage.buffer, offset: bufferStorage.offset, index: bindIndex)
        self.baseBufferOffsets[bindIndex] = bufferStorage.offset
    }
    
    func setBytes(_ bytes: UnsafeRawPointer, length: Int, at path: ResourceBindingPath) {
        let index = path.index
        encoder.setBytes(bytes, length: length, index: index)
    }
    
    func setBuffer(_ buffer: Buffer, offset: Int, at path: ResourceBindingPath) {
        guard let mtlBufferRef = resourceMap[buffer] else { return }
        let index = path.index
        encoder.setBuffer(mtlBufferRef.buffer, offset: mtlBufferRef.offset + offset, index: index)
        self.baseBufferOffsets[index] = mtlBufferRef.offset
    }
    
    func setBufferOffset(_ offset: Int, at path: ResourceBindingPath) {
        let index = path.index
        encoder.setBufferOffset(self.baseBufferOffsets[index] + offset, index: index)
    }
    
    func setTexture(_ texture: Texture, at path: ResourceBindingPath) {
        guard let mtlTexture = self.resourceMap[texture] else { return }
        let index = path.index
        encoder.setTexture(mtlTexture.texture, index: index)
    }
    
    func setSampler(_ state: SamplerState, at path: ResourceBindingPath) {
        let index = path.index
        Unmanaged<MTLSamplerState>.fromOpaque(UnsafeRawPointer(state.state))._withUnsafeGuaranteedRef { state in
            encoder.setSamplerState(state, index: index)
        }
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    func setVisibleFunctionTable(_ table: VisibleFunctionTable, at path: ResourceBindingPath) {
        guard let mtlTable = self.resourceMap[table] else { return }
        let index = path.index
        encoder.setVisibleFunctionTable(mtlTable.table, bufferIndex: index)
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    func setIntersectionFunctionTable(_ table: IntersectionFunctionTable, at path: ResourceBindingPath) {
        guard let mtlTable = self.resourceMap[table] else { return }
        let index = path.index
        encoder.setIntersectionFunctionTable(mtlTable.table, bufferIndex: index)
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    func setAccelerationStructure(_ structure: AccelerationStructure, at path: ResourceBindingPath) {
        guard let mtlStructure = self.resourceMap[structure] as! MTLAccelerationStructure? else { return }
        let index = path.index
        encoder.setAccelerationStructure(mtlStructure, bufferIndex: index)
    }
    
    func setComputePipelineState(_ pipelineState: ComputePipelineState) {
        Unmanaged<MTLComputePipelineState>.fromOpaque(UnsafeRawPointer(pipelineState.state))._withUnsafeGuaranteedRef {
            encoder.setComputePipelineState($0)
        }
    }
    
    func setStageInRegion(_ region: Region) {
        encoder.setStageInRegion(MTLRegion(region))
    }
    
    func setThreadgroupMemoryLength(_ length: Int, at index: Int) {
        encoder.setThreadgroupMemoryLength(length, index: index)
    }
    
    func dispatchThreadgroups(_ threadgroupsPerGrid: Size, threadsPerThreadgroup: Size) {
        encoder.dispatchThreadgroups(MTLSize(threadgroupsPerGrid), threadsPerThreadgroup: MTLSize(threadsPerThreadgroup))
    }
    
    func dispatchThreadgroups(indirectBuffer: Buffer, indirectBufferOffset: Int, threadsPerThreadgroup: Size) {
        let mtlBuffer = resourceMap[indirectBuffer]!
        encoder.dispatchThreadgroups(indirectBuffer: mtlBuffer.buffer, indirectBufferOffset: mtlBuffer.offset + indirectBufferOffset, threadsPerThreadgroup: MTLSize(threadsPerThreadgroup))
    }
    
    func dispatchThreads(_ threadsPerGrid: Size, threadsPerThreadgroup: Size) {
        encoder.dispatchThreads(MTLSize(threadsPerGrid), threadsPerThreadgroup: MTLSize(threadsPerThreadgroup))
    }
    
    func drawMeshThreadgroups(indirectBuffer: Buffer, indirectBufferOffset: Int, threadsPerThreadgroup: Size) {
        let mtlBuffer = resourceMap[indirectBuffer]!
        encoder.dispatchThreadgroups(indirectBuffer: mtlBuffer.buffer, indirectBufferOffset: mtlBuffer.offset + indirectBufferOffset, threadsPerThreadgroup: MTLSize(threadsPerThreadgroup))
    }
    
    func useResource(_ resource: Resource, usage: ResourceUsageType) {
        guard let mtlResource = resourceMap[resource] else {
            return
        }
        encoder.useResource(mtlResource, usage: MTLResourceUsage(usage, isAppleSiliconGPU: self.isAppleSiliconGPU))
    }
    
    func useHeap(_ heap: Heap) {
        encoder.useHeap(resourceMap.persistentRegistry[heap]!)
    }
    
    func memoryBarrier(scope: BarrierScope) {
        encoder.memoryBarrier(scope: MTLBarrierScope(scope, isAppleSiliconGPU: self.isAppleSiliconGPU))
    }
    
    func memoryBarrier(resources: [Resource]) {
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
