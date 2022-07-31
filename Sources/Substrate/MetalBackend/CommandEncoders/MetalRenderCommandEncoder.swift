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
    let resourceMap: FrameResourceMap<MetalBackend>
    let isAppleSiliconGPU: Bool
    
    let inputAttachmentUsages: [(texture: MTLTexture, afterStages: MTLRenderStages)]
    
    private var baseBufferOffsets = [Int](repeating: 0, count: 31 * 5) // 31 vertex, 31 fragment, since that's the maximum number of entries in a buffer argument table (https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)
    
    init(passRecord: RenderPassRecord, encoder: MTLRenderCommandEncoder, resourceMap: FrameResourceMap<MetalBackend>, isAppleSiliconGPU: Bool) {
        self.encoder = encoder
        self.resourceMap = resourceMap
        self.isAppleSiliconGPU = isAppleSiliconGPU
        
        if isAppleSiliconGPU {
            self.inputAttachmentUsages = []
        } else {
            self.inputAttachmentUsages = passRecord.pass.resources.compactMap { (usage: ResourceUsage) -> (texture: MTLTexture, afterStages: MTLRenderStages)? in
                guard usage.type.contains(.inputAttachment),
                        let texture = Texture(usage.resource),
                let mtlTexture = resourceMap[texture]?.texture else {
                    return nil
                }
                let stages: MTLRenderStages = usage.type.contains(.depthStencilAttachmentWrite) ? .vertex : .fragment
                return (texture: mtlTexture, afterStages: stages)
            }
        }
    }
    
    func processInputAttachmentUsages() {
        for usage in self.inputAttachmentUsages {
            encoder.memoryBarrier(resources: [usage.texture], after: usage.afterStages, before: .fragment)
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
        guard let mtlBufferRef = resourceMap[buffer] else { return }
        
        assert(index < 31, "The maximum number of buffers allowed in the buffer argument table for a single function is 31.")
        self.setBuffer(mtlBufferRef, offset: offset, at: 30 - index, stages: .vertex)
    }
    
    func setVertexBufferOffset(_ offset: Int, index: Int) {
        assert(index < 31, "The maximum number of buffers allowed in the buffer argument table for a single function is 31.")
        encoder.setVertexBufferOffset(offset, index: 30 - index)
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
        self.setBuffer(bufferStorage, offset: 0, at: bindIndex, stages: MTLRenderStages(stages))
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
        self.setBuffer(bufferStorage, offset: 0, at: bindIndex, stages: MTLRenderStages(stages))
    }
    
    func setBuffer(_ mtlBufferRef: MTLBufferReference, offset: Int, at index: Int, stages: MTLRenderStages) {
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
        guard let mtlBufferRef = resourceMap[buffer] else { return }
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
        guard let mtlTexture = self.resourceMap[texture] else { return }
        let index = path.index
        if path.stages.contains(.vertex) {
            encoder.setVertexTexture(mtlTexture.texture, index: index)
        }
        if path.stages.contains(.fragment) {
            encoder.setFragmentTexture(mtlTexture.texture, index: index)
        }
        if #available(macOS 12.0, iOS 15.0, *), path.stages.contains(.tile) {
            encoder.setTileTexture(mtlTexture.texture, index: index)
        }
        if #available(macOS 13.0, iOS 16.0, *), path.stages.contains(.object) {
            encoder.setObjectTexture(mtlTexture.texture, index: index)
        }
        if #available(macOS 13.0, iOS 16.0, *), path.stages.contains(.mesh) {
            encoder.setMeshTexture(mtlTexture.texture, index: index)
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
        guard let mtlTable = self.resourceMap[table] else { return }
        let index = path.index
        if path.stages.contains(.vertex) {
            encoder.setVertexVisibleFunctionTable(mtlTable.table, bufferIndex: index)
        }
        if path.stages.contains(.fragment) {
            encoder.setFragmentVisibleFunctionTable(mtlTable.table, bufferIndex: index)
        }
        if path.stages.contains(.tile) {
            encoder.setTileVisibleFunctionTable(mtlTable.table, bufferIndex: index)
        }
    }
    
    @available(macOS 12.0, iOS 15.0, *)
    func setIntersectionFunctionTable(_ table: IntersectionFunctionTable, at path: ResourceBindingPath) {
        guard let mtlTable = self.resourceMap[table] else { return }
        let index = path.index
        if path.stages.contains(.vertex) {
            encoder.setVertexIntersectionFunctionTable(mtlTable.table, bufferIndex: index)
        }
        if path.stages.contains(.fragment) {
            encoder.setFragmentIntersectionFunctionTable(mtlTable.table, bufferIndex: index)
        }
        if path.stages.contains(.tile) {
            encoder.setTileIntersectionFunctionTable(mtlTable.table, bufferIndex: index)
        }
    }
    
    @available(macOS 12.0, iOS 15.0, *)
    func setAccelerationStructure(_ structure: AccelerationStructure, at path: ResourceBindingPath) {
        guard let mtlStructure = self.resourceMap[structure] as! MTLAccelerationStructure? else { return }
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
        
        let mtlBuffer = resourceMap[indirectBuffer]!
        
        encoder.drawPrimitives(type: MTLPrimitiveType(primitiveType), indirectBuffer: mtlBuffer.buffer, indirectBufferOffset: mtlBuffer.offset + indirectBufferOffset)
    }
    
    func drawIndexedPrimitives(type primitiveType: PrimitiveType, indexCount: Int, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: Int, instanceCount: Int = 1, baseVertex: Int = 0, baseInstance: Int = 0) {
        self.processInputAttachmentUsages()
        
        let mtlBuffer = resourceMap[indexBuffer]!
        
        encoder.drawIndexedPrimitives(type: MTLPrimitiveType(primitiveType), indexCount: indexCount, indexType: MTLIndexType(indexType), indexBuffer: mtlBuffer.buffer, indexBufferOffset: mtlBuffer.offset + indexBufferOffset, instanceCount: instanceCount, baseVertex: baseVertex, baseInstance: baseInstance)
    }
    
    
    func drawIndexedPrimitives(type primitiveType: PrimitiveType, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: Int, indirectBuffer: Buffer, indirectBufferOffset: Int) {
        self.processInputAttachmentUsages()
        
        let mtlIndexBuffer = resourceMap[indexBuffer]!
        let mtlIndirectBuffer = resourceMap[indirectBuffer]!
        
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
        let mtlBuffer = resourceMap[indirectBuffer]!
        encoder.drawMeshThreadgroups(indirectBuffer: mtlBuffer.buffer, indirectBufferOffset: mtlBuffer.offset + indirectBufferOffset, threadsPerObjectThreadgroup: MTLSize(threadsPerObjectThreadgroup), threadsPerMeshThreadgroup: MTLSize(threadsPerMeshThreadgroup))
    }
    
    func dispatchThreadsPerTile(_ threadsPerTile: Size) {
        encoder.dispatchThreadsPerTile(MTLSize(threadsPerTile))
    }
    
    func useResource(_ resource: Resource, usage: ResourceUsageType, stages: RenderStages) {
        guard let mtlResource = resourceMap[resource] else {
            return
        }
        encoder.useResource(mtlResource, usage: MTLResourceUsage(usage, isAppleSiliconGPU: self.isAppleSiliconGPU), stages: MTLRenderStages(stages))
    }
    
    func useHeap(_ heap: Heap, stages: RenderStages) {
        encoder.useHeap(resourceMap.persistentRegistry[heap]!, stages: MTLRenderStages(stages))
    }
    
    func memoryBarrier(scope: BarrierScope, after: RenderStages, before: RenderStages) {
        encoder.memoryBarrier(scope: MTLBarrierScope(scope, isAppleSiliconGPU: self.isAppleSiliconGPU), after: MTLRenderStages(after), before: MTLRenderStages(before))
    }
    
    func memoryBarrier(resources: [Resource], after: RenderStages, before: RenderStages) {
        let mtlResources = resources.map { resourceMap[$0]! }
        encoder.memoryBarrier(resources: mtlResources, after: MTLRenderStages(after), before: MTLRenderStages(before))
    }
}

extension MTLRenderCommandEncoder {
    func executeResourceCommands(resourceCommandIndex: inout Int, resourceCommands: [CompactedResourceCommand<MetalCompactedResourceCommandType>], passIndex: Int, order: PerformOrder, isAppleSiliconGPU: Bool) {
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
            }
            
            resourceCommandIndex += 1
        }
    }
}

#endif // canImport(Metal)
