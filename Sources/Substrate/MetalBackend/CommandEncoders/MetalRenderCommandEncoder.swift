//
//  File.swift
//  
//
//  Created by Thomas Roughton on 6/07/22.
//

#if canImport(Metal)
import Foundation
import Metal

final class MetalRenderCommandEncoder: RenderCommandEncoderImpl {
    let encoder: MTLRenderCommandEncoder
    let usedResources: Set<UnsafeMutableRawPointer>
    let isAppleSiliconGPU: Bool
    
    var inputAttachmentBarrierStages: (after: MTLRenderStages, before: MTLRenderStages)?
    
    private var baseBufferOffsets = [Int](repeating: 0, count: 31 * 5) // 31 vertex, 31 fragment, since that's the maximum number of entries in a buffer argument table (https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)
    
    init(passRecord: RenderPassRecord, encoder: MTLRenderCommandEncoder, usedResources: Set<UnsafeMutableRawPointer>, isAppleSiliconGPU: Bool) {
        self.encoder = encoder
        self.usedResources = usedResources
        self.isAppleSiliconGPU = isAppleSiliconGPU
        
        if isAppleSiliconGPU {
            self.inputAttachmentBarrierStages = nil
        } else {
            var stages: (after: RenderStages, before: RenderStages) = ([], [])
            
            for usage in passRecord.pass.resources {
                guard usage.type.contains(.inputAttachment),
                        let texture = Texture(usage.resource) else {
                    continue
                }
                
                if texture.descriptor.pixelFormat.isDepth || texture.descriptor.pixelFormat.isStencil {
                    stages.after.formUnion(.vertex)
                } else {
                    stages.after.formUnion(.fragment)
                }
                
                if usage.stages.isEmpty {
                    stages.before.formUnion(.vertex)
                } else {
                    stages.before.formUnion(usage.stages)
                }
            }
            if !stages.after.isEmpty {
                self.inputAttachmentBarrierStages = (MTLRenderStages(stages.after.last), MTLRenderStages(stages.before.first))
            } else {
                self.inputAttachmentBarrierStages = nil
            }
        }
    }
    
    func processInputAttachmentUsages() {
        guard !self.isAppleSiliconGPU else { return }
        if let inputAttachmentBarrierStages = self.inputAttachmentBarrierStages, #available(iOS 16.0, *) {
            encoder.memoryBarrier(scope: .renderTargets, after: inputAttachmentBarrierStages.after, before: inputAttachmentBarrierStages.before)
        }
    }
    
    func pushDebugGroup(_ string: String) {
        encoder.pushDebugGroup(string)
    }
    
    func popDebugGroup() {
        encoder.popDebugGroup()
    }
    
    func insertDebugSignpost(_ string: String) {
        encoder.insertDebugSignpost(string)
    }
    
    func setLabel(_ label: String) {
        encoder.label = label
    }
    
    func setBytes(_ bytes: UnsafeRawPointer, length: Int, at path: ResourceBindingPath) {
        let index = path.index
        if path.stages.contains(.vertex) {
            encoder.setVertexBytes(bytes, length: length, index: index)
        }
        if path.stages.contains(.fragment) {
            encoder.setFragmentBytes(bytes, length: length, index: index)
        }
    }
    
    func setVertexBuffer(_ buffer: Buffer, offset: Int, index: Int) {
        guard let mtlBufferRef = buffer.mtlBuffer else { return }
        
        assert(index < 31, "The maximum number of buffers allowed in the buffer argument table for a single function is 31.")
        self.setBuffer(mtlBufferRef, offset: offset, at: 30 - index, stages: .vertex)
    }
    
    func setVertexBufferOffset(_ offset: Int, index: Int) {
        assert(index < 31, "The maximum number of buffers allowed in the buffer argument table for a single function is 31.")
        encoder.setVertexBufferOffset(offset, index: 30 - index)
    }
    
    func setArgumentBuffer(_ argumentBuffer: ArgumentBuffer, at index: Int, stages: RenderStages) {
        let bufferStorage = argumentBuffer.mtlBuffer!

        for resource in argumentBuffer.usedResources where !self.usedResources.contains(resource) {
            encoder.useResource(Unmanaged<MTLResource>.fromOpaque(resource).takeUnretainedValue(), usage: .read, stages: MTLRenderStages(stages))
        }
        
        for heap in argumentBuffer.usedHeaps {
            encoder.useHeap(Unmanaged<MTLHeap>.fromOpaque(heap).takeUnretainedValue(), stages: MTLRenderStages(stages))
        }
        
        let bindIndex = index + 1 // since buffer 0 is push constants
        self.setBuffer(bufferStorage, offset: 0, at: bindIndex, stages: MTLRenderStages(stages))
    }
    
    func setBuffer(_ mtlBufferRef: OffsetView<MTLBuffer>, offset: Int, at index: Int, stages: MTLRenderStages) {
        if stages.contains(.vertex) {
            encoder.setVertexBuffer(mtlBufferRef.buffer, offset: mtlBufferRef.offset + offset, index: index)
            self.baseBufferOffsets[index] = mtlBufferRef.offset
        }
        if stages.contains(.fragment) {
            encoder.setFragmentBuffer(mtlBufferRef.buffer, offset: mtlBufferRef.offset + offset, index: index)
            self.baseBufferOffsets[index + 31] = mtlBufferRef.offset
        }
        if #available(macOS 12.0, iOS 15.0, *), stages.contains(.tile) {
            encoder.setTileBuffer(mtlBufferRef.buffer, offset: mtlBufferRef.offset + offset, index: index)
            self.baseBufferOffsets[index + 2 * 31] = mtlBufferRef.offset
        }
        if #available(macOS 13.0, iOS 16.0, *), stages.contains(.object) {
            encoder.setObjectBuffer(mtlBufferRef.buffer, offset: mtlBufferRef.offset + offset, index: index)
            self.baseBufferOffsets[index + 3 * 31] = mtlBufferRef.offset
        }
        if #available(macOS 13.0, iOS 16.0, *), stages.contains(.mesh) {
            encoder.setMeshBuffer(mtlBufferRef.buffer, offset: mtlBufferRef.offset + offset, index: index)
            self.baseBufferOffsets[index + 3 * 31] = mtlBufferRef.offset
        }
    }
    
    func setBuffer(_ buffer: Buffer, offset: Int, at path: ResourceBindingPath) {
        guard let mtlBufferRef = buffer.mtlBuffer else { return }
        let index = path.index
        
        self.setBuffer(mtlBufferRef, offset: offset, at: index, stages: path.stages)
    }
    
    func setBufferOffset(_ offset: Int, at path: ResourceBindingPath) {
        let index = path.index
        if path.stages.contains(.vertex) {
            encoder.setVertexBufferOffset(self.baseBufferOffsets[index] + offset, index: index)
        }
        if path.stages.contains(.fragment) {
            encoder.setFragmentBufferOffset(self.baseBufferOffsets[index + 31] + offset, index: index)
        }
        if #available(macOS 12.0, iOS 15.0, *), path.stages.contains(.tile) {
            encoder.setTileBufferOffset(self.baseBufferOffsets[index + 2 * 31] + offset, index: index)
        }
        if #available(macOS 13.0, iOS 16.0, *), path.stages.contains(.object) {
            encoder.setObjectBufferOffset(self.baseBufferOffsets[index + 3 * 31] + offset, index: index)
        }
        if #available(macOS 13.0, iOS 16.0, *), path.stages.contains(.mesh) {
            encoder.setMeshBufferOffset(self.baseBufferOffsets[index + 4 * 31] + offset, index: index)
        }
    }
    
    func setTexture(_ texture: Texture, at path: ResourceBindingPath) {
        guard let mtlTexture = texture.mtlTexture else { return }
        let index = path.index
        if path.stages.contains(.vertex) {
            encoder.setVertexTexture(mtlTexture, index: index)
        }
        if path.stages.contains(.fragment) {
            encoder.setFragmentTexture(mtlTexture, index: index)
        }
        if #available(macOS 12.0, iOS 15.0, *), path.stages.contains(.tile) {
            encoder.setTileTexture(mtlTexture, index: index)
        }
        if #available(macOS 13.0, iOS 16.0, *), path.stages.contains(.object) {
            encoder.setObjectTexture(mtlTexture, index: index)
        }
        if #available(macOS 13.0, iOS 16.0, *), path.stages.contains(.mesh) {
            encoder.setMeshTexture(mtlTexture, index: index)
        }
    }
    
    func setSampler(_ state: SamplerState, at path: ResourceBindingPath) {
        let index = path.index
        Unmanaged<MTLSamplerState>.fromOpaque(UnsafeRawPointer(state.state))._withUnsafeGuaranteedRef { state in
            if path.stages.contains(.vertex) {
                encoder.setVertexSamplerState(state, index: index)
            }
            if path.stages.contains(.fragment) {
                encoder.setFragmentSamplerState(state, index: index)
            }
            if #available(macOS 12.0, iOS 15.0, *), path.stages.contains(.tile) {
                encoder.setTileSamplerState(state, index: index)
            }
            if #available(macOS 13.0, iOS 16.0, *), path.stages.contains(.object) {
                encoder.setObjectSamplerState(state, index: index)
            }
            if #available(macOS 13.0, iOS 16.0, *), path.stages.contains(.mesh) {
                encoder.setMeshSamplerState(state, index: index)
            }
        }
    }
    
    @available(macOS 12.0, iOS 15.0, *)
    func setVisibleFunctionTable(_ table: VisibleFunctionTable, at path: ResourceBindingPath) {
        let mtlTable = table.mtlVisibleFunctionTable
        let index = path.index
        if path.stages.contains(.vertex) {
            encoder.setVertexVisibleFunctionTable(mtlTable, bufferIndex: index)
        }
        if path.stages.contains(.fragment) {
            encoder.setFragmentVisibleFunctionTable(mtlTable, bufferIndex: index)
        }
        if path.stages.contains(.tile) {
            encoder.setTileVisibleFunctionTable(mtlTable, bufferIndex: index)
        }
    }
    
    @available(macOS 12.0, iOS 15.0, *)
    func setIntersectionFunctionTable(_ table: IntersectionFunctionTable, at path: ResourceBindingPath) {
        guard let mtlTable = table.mtlIntersectionFunctionTable else { return }
        let index = path.index
        if path.stages.contains(.vertex) {
            encoder.setVertexIntersectionFunctionTable(mtlTable, bufferIndex: index)
        }
        if path.stages.contains(.fragment) {
            encoder.setFragmentIntersectionFunctionTable(mtlTable, bufferIndex: index)
        }
        if path.stages.contains(.tile) {
            encoder.setTileIntersectionFunctionTable(mtlTable, bufferIndex: index)
        }
    }
    
    @available(macOS 12.0, iOS 15.0, *)
    func setAccelerationStructure(_ structure: AccelerationStructure, at path: ResourceBindingPath) {
        guard let mtlStructure = structure.mtlAccelerationStructure else { return }
        let index = path.index
        if path.stages.contains(.vertex) {
            encoder.setVertexAccelerationStructure(mtlStructure, bufferIndex: index)
        }
        if path.stages.contains(.fragment) {
            encoder.setFragmentAccelerationStructure(mtlStructure, bufferIndex: index)
        }
        if path.stages.contains(.tile) {
            encoder.setTileAccelerationStructure(mtlStructure, bufferIndex: index)
        }
    }
    
    func setViewport(_ viewport: Viewport) {
        encoder.setViewport(MTLViewport(viewport))
    }
    
    func setFrontFacing(_ winding: Winding) {
        encoder.setFrontFacing(MTLWinding(winding))
    }
    
    func setCullMode(_ cullMode: CullMode) {
        encoder.setCullMode(MTLCullMode(cullMode))
    }
    
    func setDepthBias(_ depthBias: Float, slopeScale: Float, clamp: Float) {
        encoder.setDepthBias(depthBias, slopeScale: slopeScale, clamp: clamp)
    }
    
    func setScissorRect(_ rect: ScissorRect) {
        encoder.setScissorRect(MTLScissorRect(rect))
    }
    
//    func setBlendColor(red: Float, green: Float, blue: Float, alpha: Float) {
//        encoder.setBlendColor(red: red, green: green, blue: blue, alpha: alpha)
//    }
    
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
        encoder.setStencilReferenceValue(referenceValue)
    }
    
    func setStencilReferenceValues(front frontReferenceValue: UInt32, back backReferenceValue: UInt32) {
        encoder.setStencilReferenceValues(front: frontReferenceValue, back: backReferenceValue)
    }
    
    @available(macOS 12.0, iOS 15.0, *)
    func setThreadgroupMemoryLength(_ length: Int, at path: ResourceBindingPath) {
        let index = path.index
        if path.stages.contains(.tile) {
            encoder.setThreadgroupMemoryLength(length, offset: 0, index: index)
        }
        if #available(macOS 13.0, iOS 16.0, *), path.stages.contains(.object) {
            encoder.setObjectThreadgroupMemoryLength(length, index: index)
        }
    }
    
    func drawPrimitives(type primitiveType: PrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int = 1, baseInstance: Int = 0) {
        self.processInputAttachmentUsages()
        
        encoder.drawPrimitives(type: MTLPrimitiveType(primitiveType), vertexStart: vertexStart, vertexCount: vertexCount, instanceCount: instanceCount, baseInstance: baseInstance)
    }
    
    func drawPrimitives(type primitiveType: PrimitiveType, indirectBuffer: Buffer, indirectBufferOffset: Int) {
        self.processInputAttachmentUsages()
        
        let mtlBuffer = indirectBuffer.mtlBuffer!
        
        encoder.drawPrimitives(type: MTLPrimitiveType(primitiveType), indirectBuffer: mtlBuffer.buffer, indirectBufferOffset: mtlBuffer.offset + indirectBufferOffset)
    }
    
    func drawIndexedPrimitives(type primitiveType: PrimitiveType, indexCount: Int, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: Int, instanceCount: Int = 1, baseVertex: Int = 0, baseInstance: Int = 0) {
        self.processInputAttachmentUsages()
        
        let mtlBuffer = indexBuffer.mtlBuffer!
        
        encoder.drawIndexedPrimitives(type: MTLPrimitiveType(primitiveType), indexCount: indexCount, indexType: MTLIndexType(indexType), indexBuffer: mtlBuffer.buffer, indexBufferOffset: mtlBuffer.offset + indexBufferOffset, instanceCount: instanceCount, baseVertex: baseVertex, baseInstance: baseInstance)
    }
    
    
    func drawIndexedPrimitives(type primitiveType: PrimitiveType, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: Int, indirectBuffer: Buffer, indirectBufferOffset: Int) {
        self.processInputAttachmentUsages()
        
        let mtlIndexBuffer = indexBuffer.mtlBuffer!
        let mtlIndirectBuffer = indirectBuffer.mtlBuffer!
        
        encoder.drawIndexedPrimitives(type: MTLPrimitiveType(primitiveType), indexType: MTLIndexType(indexType), indexBuffer: mtlIndexBuffer.buffer, indexBufferOffset: mtlIndexBuffer.offset + indexBufferOffset, indirectBuffer: mtlIndirectBuffer.buffer, indirectBufferOffset: mtlIndirectBuffer.offset + indirectBufferOffset)
    }
    
    
    @available(macOS 13.0, iOS 16.0, *)
    func drawMeshThreadgroups(_ threadgroupsPerGrid: Size, threadsPerObjectThreadgroup: Size, threadsPerMeshThreadgroup: Size) {
        encoder.drawMeshThreadgroups(MTLSize(threadgroupsPerGrid), threadsPerObjectThreadgroup: MTLSize(threadsPerObjectThreadgroup), threadsPerMeshThreadgroup: MTLSize(threadsPerMeshThreadgroup))
    }
    
    @available(macOS 13.0, iOS 16.0, *)
    func drawMeshThreads(_ threadsPerGrid: Size, threadsPerObjectThreadgroup: Size, threadsPerMeshThreadgroup: Size) {
        encoder.drawMeshThreadgroups(MTLSize(threadsPerGrid), threadsPerObjectThreadgroup: MTLSize(threadsPerObjectThreadgroup), threadsPerMeshThreadgroup: MTLSize(threadsPerMeshThreadgroup))
    }
    
    @available(macOS 13.0, iOS 16.0, *)
    func drawMeshThreadgroups(indirectBuffer: Buffer, indirectBufferOffset: Int, threadsPerObjectThreadgroup: Size, threadsPerMeshThreadgroup: Size) {
        let mtlBuffer = indirectBuffer.mtlBuffer!
        encoder.drawMeshThreadgroups(indirectBuffer: mtlBuffer.buffer, indirectBufferOffset: mtlBuffer.offset + indirectBufferOffset, threadsPerObjectThreadgroup: MTLSize(threadsPerObjectThreadgroup), threadsPerMeshThreadgroup: MTLSize(threadsPerMeshThreadgroup))
    }
    
    func dispatchThreadsPerTile(_ threadsPerTile: Size) {
        encoder.dispatchThreadsPerTile(MTLSize(threadsPerTile))
    }
    
    func useResource(_ resource: Resource, usage: ResourceUsageType, stages: RenderStages) {
        guard let mtlResource = resource.backingResourcePointer else {
            return
        }
        encoder.useResource(Unmanaged<MTLResource>.fromOpaque(mtlResource).takeUnretainedValue(), usage: MTLResourceUsage(usage, isAppleSiliconGPU: self.isAppleSiliconGPU), stages: MTLRenderStages(stages))
    }
    
    func useHeap(_ heap: Heap, stages: RenderStages) {
        encoder.useHeap(heap.mtlHeap, stages: MTLRenderStages(stages))
    }
    
    func memoryBarrier(scope: BarrierScope, after: RenderStages, before: RenderStages) {
        if #available(iOS 16.0, *) {
            encoder.memoryBarrier(scope: MTLBarrierScope(scope, isAppleSiliconGPU: self.isAppleSiliconGPU), after: MTLRenderStages(after), before: MTLRenderStages(before))
        } else {
            assertionFailure()
        }
    }
    
    func memoryBarrier(resources: [Resource], after: RenderStages, before: RenderStages) {
        if #available(iOS 16.0, *) {
            let mtlResources = resources.map { Unmanaged<MTLResource>.fromOpaque($0.backingResourcePointer!).takeUnretainedValue() }
            encoder.memoryBarrier(resources: mtlResources, after: MTLRenderStages(after), before: MTLRenderStages(before))
        } else {
            assertionFailure()
        }
    }
}

extension MTLRenderCommandEncoder {
    func executeResourceCommands(resourceCommandIndex: inout Int, resourceCommands: [CompactedResourceCommand<MetalCompactedResourceCommandType>],
                                 usedResources: inout Set<UnsafeMutableRawPointer>, // Unmanaged<MTLResource>
                                 passIndex: Int, order: PerformOrder, isAppleSiliconGPU: Bool) {
        while resourceCommandIndex < resourceCommands.count {
            let command = resourceCommands[resourceCommandIndex]
            
            guard command.index < passIndex || (command.index == passIndex && command.order == order) else {
                break
            }
            
            switch command.command {
            case .resourceMemoryBarrier(let resources, let afterStages, let beforeStages):
                #if os(macOS) || targetEnvironment(macCatalyst)
                if !isAppleSiliconGPU {
                    self.__memoryBarrier(resources: resources.baseAddress!, count: resources.count, after: afterStages, before: beforeStages)
                }
                #else
                break
                #endif
                
            case .scopedMemoryBarrier(let scope, let afterStages, let beforeStages):
                #if os(macOS) || targetEnvironment(macCatalyst)
                if !isAppleSiliconGPU {
                    self.memoryBarrier(scope: scope, after: afterStages, before: beforeStages)
                }
                #else
                break
                #endif
                
            case .updateFence(let fence, let afterStages):
                self.updateFence(fence.fence, after: afterStages)
                
            case .waitForFence(let fence, let beforeStages):
                self.waitForFence(fence.fence, before: beforeStages)
                
            case .useResources(let resources, let usage, let stages):
                if #available(iOS 13.0, macOS 10.15, *) {
                    self.use(resources.baseAddress!, count: resources.count, usage: usage, stages: stages)
                } else {
                    self.__use(resources.baseAddress!, count: resources.count, usage: usage)
                }
                
                for i in resources.indices {
                    usedResources.insert(Unmanaged<MTLResource>.passUnretained(resources[i]).toOpaque())
                }
            }
            
            resourceCommandIndex += 1
        }
    }
}

#endif // canImport(Metal)
