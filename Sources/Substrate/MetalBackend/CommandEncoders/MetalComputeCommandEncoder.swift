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
    let usedResources: Set<UnsafeMutableRawPointer>
    let usedHeaps: Set<UnsafeMutableRawPointer>
    let isAppleSiliconGPU: Bool
    
    private var baseBufferOffsets = [Int](repeating: 0, count: 31) // 31 vertex, 31 fragment, since that's the maximum number of entries in a buffer argument table (https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)
    
    init(encoder: MTLComputeCommandEncoder, usedResources: Set<UnsafeMutableRawPointer>, usedHeaps: Set<UnsafeMutableRawPointer>, isAppleSiliconGPU: Bool) {
        self.encoder = encoder
        self.usedResources = usedResources
        self.usedHeaps = usedHeaps
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
        let bufferStorage = argumentBuffer.mtlBuffer!
        
        argumentBuffer.encodedResourcesLock.withLock {
            MetalArgumentBufferImpl.computeUsedResources(for: argumentBuffer)
            for heap in argumentBuffer.usedHeaps where !self.usedHeaps.contains(heap) {
                encoder.useHeap(Unmanaged<MTLHeap>.fromOpaque(heap).takeUnretainedValue())
            }
            
            for resource in argumentBuffer.usedResources where !self.usedResources.contains(resource) {
                encoder.useResource(Unmanaged<MTLResource>.fromOpaque(resource).takeUnretainedValue(), usage: .read)
            }
        }
        
        let bindIndex = index + 1 // since buffer 0 is push constants
        encoder.setBuffer(bufferStorage.wrappedValue, offset: bufferStorage.offset, index: bindIndex)
        self.baseBufferOffsets[bindIndex] = bufferStorage.offset
    }
    
    func setArgumentBufferArray(_ argumentBuffer: ArgumentBufferArray, at index: Int, stages: RenderStages) {
        let bufferStorage = argumentBuffer[0].mtlBuffer!
        
        argumentBuffer.encodedResourcesLock.withLock {
            MetalArgumentBufferImpl.computeUsedResources(for: argumentBuffer)
            for heap in argumentBuffer.usedHeaps where !self.usedHeaps.contains(heap) {
                encoder.useHeap(Unmanaged<MTLHeap>.fromOpaque(heap).takeUnretainedValue())
            }
            
            for resource in argumentBuffer.usedResources where !self.usedResources.contains(resource) {
                encoder.useResource(Unmanaged<MTLResource>.fromOpaque(resource).takeUnretainedValue(), usage: .read)
            }
        }
        
        let bindIndex = index + 1 // since buffer 0 is push constants
        encoder.setBuffer(bufferStorage.wrappedValue, offset: bufferStorage.offset, index: bindIndex)
        self.baseBufferOffsets[bindIndex] = bufferStorage.offset
    }
    
    func setBytes(_ bytes: UnsafeRawPointer, length: Int, at path: ResourceBindingPath) {
        let index = path.index
        encoder.setBytes(bytes, length: length, index: index)
    }
    
    func setBuffer(_ buffer: Buffer, offset: Int, at path: ResourceBindingPath) {
        guard let mtlBufferRef = buffer.mtlBuffer else { return }
        let index = path.index
        encoder.setBuffer(mtlBufferRef.buffer, offset: mtlBufferRef.offset + offset, index: index)
        self.baseBufferOffsets[index] = mtlBufferRef.offset
    }
    
    func setBufferOffset(_ offset: Int, at path: ResourceBindingPath) {
        let index = path.index
        encoder.setBufferOffset(self.baseBufferOffsets[index] + offset, index: index)
    }
    
    func setTexture(_ texture: Texture, at path: ResourceBindingPath) {
        guard let mtlTexture = texture.mtlTexture else { return }
        let index = path.index
        encoder.setTexture(mtlTexture, index: index)
    }
    
    func setSampler(_ state: SamplerState, at path: ResourceBindingPath) {
        let index = path.index
        Unmanaged<MTLSamplerState>.fromOpaque(UnsafeRawPointer(state.state))._withUnsafeGuaranteedRef { state in
            encoder.setSamplerState(state, index: index)
        }
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    func setVisibleFunctionTable(_ table: VisibleFunctionTable, at path: ResourceBindingPath) {
        guard let mtlTable = table.mtlVisibleFunctionTable else { return }
        let index = path.index
        encoder.setVisibleFunctionTable(mtlTable, bufferIndex: index)
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    func setIntersectionFunctionTable(_ table: IntersectionFunctionTable, at path: ResourceBindingPath) {
        guard let mtlTable = table.mtlIntersectionFunctionTable else { return }
        let index = path.index
        encoder.setIntersectionFunctionTable(mtlTable, bufferIndex: index)
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    func setAccelerationStructure(_ structure: AccelerationStructure, at path: ResourceBindingPath) {
        guard let mtlStructure = structure.mtlAccelerationStructure else { return }
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
        let mtlBuffer = indirectBuffer.mtlBuffer!
        encoder.dispatchThreadgroups(indirectBuffer: mtlBuffer.buffer, indirectBufferOffset: mtlBuffer.offset + indirectBufferOffset, threadsPerThreadgroup: MTLSize(threadsPerThreadgroup))
    }
    
    func dispatchThreads(_ threadsPerGrid: Size, threadsPerThreadgroup: Size) {
        encoder.dispatchThreads(MTLSize(threadsPerGrid), threadsPerThreadgroup: MTLSize(threadsPerThreadgroup))
    }
    
    func drawMeshThreadgroups(indirectBuffer: Buffer, indirectBufferOffset: Int, threadsPerThreadgroup: Size) {
        let mtlBuffer = indirectBuffer.mtlBuffer!
        encoder.dispatchThreadgroups(indirectBuffer: mtlBuffer.buffer, indirectBufferOffset: mtlBuffer.offset + indirectBufferOffset, threadsPerThreadgroup: MTLSize(threadsPerThreadgroup))
    }
    
    func useResource(_ resource: Resource, usage: ResourceUsageType) {
        guard let mtlResource = resource.backingResourcePointer else {
            return
        }
        encoder.useResource(Unmanaged<MTLResource>.fromOpaque(mtlResource).takeUnretainedValue(), usage: MTLResourceUsage(usage, isAppleSiliconGPU: self.isAppleSiliconGPU))
    }
    
    func useHeap(_ heap: Heap) {
        encoder.useHeap(heap.mtlHeap)
    }
    
    func memoryBarrier(scope: BarrierScope) {
        encoder.memoryBarrier(scope: MTLBarrierScope(scope, isAppleSiliconGPU: self.isAppleSiliconGPU))
    }
    
    func memoryBarrier(resources: [Resource]) {
        let mtlResources = resources.map { Unmanaged<MTLResource>.fromOpaque($0.backingResourcePointer!).takeUnretainedValue() }
        encoder.memoryBarrier(resources: mtlResources)
    }
}

extension MTLComputeCommandEncoder {
    func executeResourceCommands(resourceCommandIndex: inout Int, resourceCommands: [CompactedResourceCommand<MetalCompactedResourceCommandType>],
                                 usedResources: inout Set<UnsafeMutableRawPointer>, // Unmanaged<MTLResource>
                                 usedHeaps: inout Set<UnsafeMutableRawPointer>, // Unmanaged<MTLResource>
                                 passIndex: Int, order: PerformOrder, isAppleSiliconGPU: Bool) {
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
                
                for i in resources.indices {
                    usedResources.insert(Unmanaged<MTLResource>.passUnretained(resources[i]).toOpaque())
                }
                
            case .useHeaps(let heaps):
                for heap in heaps {
                    self.useHeap(heap.resource.takeUnretainedValue())
                    usedHeaps.insert(heap.resource.toOpaque())
                }
            }
            
            resourceCommandIndex += 1
        }
    }
}

#endif // canImport(Metal)
