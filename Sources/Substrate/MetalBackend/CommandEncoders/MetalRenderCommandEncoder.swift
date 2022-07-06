//
//  File.swift
//  
//
//  Created by Thomas Roughton on 6/07/22.
//

import Foundation
import Metal

final class MetalRenderCommandEncoder: RenderCommandEncoder {
    let encoder: MTLRenderCommandEncoder
    let resourceMap: FrameResourceMap<MetalBackend>
    
    private var baseBufferOffsets = [Int](repeating: 0, count: 31 * 5) // 31 vertex, 31 fragment, since that's the maximum number of entries in a buffer argument table (https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)
    
    init(encoder: MTLRenderCommandEncoder, resourceMap: FrameResourceMap<MetalBackend>) {
        self.encoder = encoder
        self.resourceMap = resourceMap
    }
    
    override func setBytes(_ bytes: UnsafeRawPointer, length: Int, path: ResourceBindingPath) {
        let index = path.index
        if path.stages.contains(.vertex) {
            encoder.setVertexBytes(bytes, length: length, index: index)
        }
        if path.stages.contains(.fragment) {
            encoder.setFragmentBytes(bytes, length: length, index: index)
        }
    }
    
    override func setVertexBuffer(_ buffer: Buffer?, offset: Int, index: Int) {
        guard let buffer = buffer,
              let mtlBufferRef = resourceMap[buffer] else { return }
        encoder.setVertexBuffer(mtlBufferRef.buffer, offset: mtlBufferRef.offset + offset, index: index)
    }
    
    override func setVertexBufferOffset(_ offset: Int, index: Int) {
        encoder.setVertexBufferOffset(offset, index: index)
    }
    
    override func setBuffer(_ buffer: Buffer?, offset: Int, path: ResourceBindingPath) {
        guard let buffer = buffer,
              let mtlBufferRef = resourceMap[buffer] else { return }
        let index = path.index
        if path.stages.contains(.vertex) {
            encoder.setVertexBuffer(mtlBufferRef.buffer, offset: mtlBufferRef.offset + offset, index: index)
            self.baseBufferOffsets[index] = mtlBufferRef.offset
        }
        if path.stages.contains(.fragment) {
            encoder.setFragmentBuffer(mtlBufferRef.buffer, offset: mtlBufferRef.offset + offset, index: index)
            self.baseBufferOffsets[index + 31] = mtlBufferRef.offset
        }
        if #available(macOS 12.0, iOS 15.0, *), path.stages.contains(.tile) {
            encoder.setTileBuffer(mtlBufferRef.buffer, offset: mtlBufferRef.offset + offset, index: index)
            self.baseBufferOffsets[index + 2 * 31] = mtlBufferRef.offset
        }
        if #available(macOS 13.0, iOS 16.0, *), path.stages.contains(.object) {
            encoder.setObjectBuffer(mtlBufferRef.buffer, offset: mtlBufferRef.offset + offset, index: index)
            self.baseBufferOffsets[index + 3 * 31] = mtlBufferRef.offset
        }
        if #available(macOS 13.0, iOS 16.0, *), path.stages.contains(.mesh) {
            encoder.setMeshBuffer(mtlBufferRef.buffer, offset: mtlBufferRef.offset + offset, index: index)
            self.baseBufferOffsets[index + 3 * 31] = mtlBufferRef.offset
        }
    }
    
    override func setBufferOffset(_ offset: Int, path: ResourceBindingPath) {
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
    
    override func setTexture(_ texture: Texture?, path: ResourceBindingPath) {
        guard let texture = texture,
              let mtlTexture = self.resourceMap[texture] else { return }
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
    
    override func setSamplerState(_ state: SamplerState?, path: ResourceBindingPath) {
        guard let state = state else { return }
        
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
    override func setVisibleFunctionTable(_ table: VisibleFunctionTable?, path: ResourceBindingPath) {
        guard let table = table,
              let mtlTable = self.resourceMap[table] else { return }
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
    override func setIntersectionFunctionTable(_ table: IntersectionFunctionTable?, path: ResourceBindingPath) {
        guard let table = table,
              let mtlTable = self.resourceMap[table] else { return }
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
    override func setAccelerationStructure(_ structure: AccelerationStructure?, path: ResourceBindingPath) {
        guard let structure = structure,
              let mtlStructure = self.resourceMap[structure] as! MTLAccelerationStructure? else { return }
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
    
    
    override func setViewport(_ viewport: Viewport) {
        encoder.setViewport(MTLViewport(viewport))
    }
    
    override func setFrontFacing(_ winding: Winding) {
        encoder.setFrontFacing(MTLWinding(winding))
    }
    
    override func setCullMode(_ cullMode: CullMode) {
        encoder.setCullMode(MTLCullMode(cullMode))
    }
    
    override func setDepthClipMode(_ depthClipMode: DepthClipMode) {
        encoder.setDepthClipMode(MTLDepthClipMode(depthClipMode))
    }
    
    override func setDepthBias(_ depthBias: Float, slopeScale: Float, clamp: Float) {
        encoder.setDepthBias(depthBias, slopeScale: slopeScale, clamp: clamp)
    }
    
    override func setScissorRect(_ rect: ScissorRect) {
        encoder.setScissorRect(MTLScissorRect(rect))
    }
    
    override func setTriangleFillMode(_ fillMode: TriangleFillMode) {
        encoder.setTriangleFillMode(MTLTriangleFillMode(fillMode))
    }
    
    override func setBlendColor(red: Float, green: Float, blue: Float, alpha: Float) {
        encoder.setBlendColor(red: red, green: green, blue: blue, alpha: alpha)
    }
    
    override func setRenderPipelineState(_ pipelineState: RenderPipelineState) {
        Unmanaged<MTLRenderPipelineState>.fromOpaque(UnsafeRawPointer(pipelineState.state))._withUnsafeGuaranteedRef {
            encoder.setRenderPipelineState($0)
        }
    }
    
    override func setDepthStencilState(_ depthStencilState: DepthStencilState) {
        Unmanaged<MTLDepthStencilState>.fromOpaque(UnsafeRawPointer(depthStencilState.state))._withUnsafeGuaranteedRef {
            encoder.setDepthStencilState($0)
        }
    }
    
    override func setStencilReferenceValue(_ referenceValue: UInt32) {
        encoder.setStencilReferenceValue(referenceValue)
    }
    
    override func setStencilReferenceValues(front frontReferenceValue: UInt32, back backReferenceValue: UInt32) {
        encoder.setStencilReferenceValues(front: frontReferenceValue, back: backReferenceValue)
    }
    
    @available(macOS 12.0, iOS 15.0, *)
    override func setThreadgroupMemoryLength(_ length: Int, path: ResourceBindingPath) {
        let index = path.index
        if path.stages.contains(.tile) {
            encoder.setThreadgroupMemoryLength(length, offset: 0, index: index)
        }
        if #available(macOS 13.0, iOS 16.0, *), path.stages.contains(.object) {
            encoder.setObjectThreadgroupMemoryLength(length, index: index)
        }
    }
    
    override func drawPrimitives(type primitiveType: PrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int = 1, baseInstance: Int = 0) {
        encoder.drawPrimitives(type: MTLPrimitiveType(type), vertexStart: vertexStart, vertexCount: vertexCount, instanceCount: instanceCount, baseInstance: baseInstance)
    }
    
    override func drawPrimitives(type primitiveType: PrimitiveType, indirectBuffer: Buffer, indirectBufferOffset: Int) {
        let mtlBuffer = resourceMap[indirectBuffer]!
        
        encoder.drawPrimitives(type: MTLPrimitiveType(type), indirectBuffer: mtlBuffer, indirectBufferOffset: mtlBuffer.offset + indirectBufferOffset)
    }
    
    override func drawIndexedPrimitives(type primitiveType: PrimitiveType, indexCount: Int, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: Int, instanceCount: Int = 1, baseVertex: Int = 0, baseInstance: Int = 0) {
        let mtlBuffer = resourceMap[indexBuffer]!
        
        encoder.drawIndexedPrimitives(type: MTLPrimitiveType(primitiveType), indexCount: indexCount, indexType: MTLIndexType(indexType), indexBuffer: mtlBuffer.buffer, indexBufferOffset: mtlBuffer.offset + indexBufferOffset, instanceCount: instanceCount, baseVertex: baseVertex, baseInstance: baseInstance)
    }
    
    
    override func drawIndexedPrimitives(type primitiveType: PrimitiveType, indexCount: Int, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: Int, indirectBuffer: Buffer, indirectBufferOffset: Int) {
        
        let mtlIndexBuffer = resourceMap[indexBuffer]!
        let mtlIndirectBuffer = resourceMap[indirectBuffer]!
        
        encoder.drawIndexedPrimitives(type: MTLPrimitiveType(primitiveType), indexCount: indexCount, indexType: MTLIndexType(indexType), indexBuffer: mtlIndexBuffer.buffer, indexBufferOffset: mtlIndexBuffer.offset + indexBufferOffset, indirectBuffer: mtlIndirectBuffer.buffer, indirectBufferOffset: mtlIndirectBuffer.offset + indirectBufferOffset)
    }
    
    
    @available(macOS 13.0, iOS 16.0, *)
    override func drawMeshThreadgroups(_ threadgroupsPerGrid: Size, threadsPerObjectThreadgroup: Size, threadsPerMeshThreadgroup: Size) {
        encoder.drawMeshThreadgroups(MTLSize(threadgroupsPerGrid), threadsPerObjectThreadgroup: MTLSize(threadsPerObjectThreadgroup), threadsPerMeshThreadgroup: MTLSize(threadsPerMeshThreadgroup))
    }
    
    @available(macOS 13.0, iOS 16.0, *)
    override func drawMeshThreads(_ threadsPerGrid: Size, threadsPerObjectThreadgroup: Size, threadsPerMeshThreadgroup: Size) {
        encoder.drawMeshThreadgroups(MTLSize(threadgroupsPerGrid), threadsPerObjectThreadgroup: MTLSize(threadsPerObjectThreadgroup), threadsPerMeshThreadgroup: MTLSize(threadsPerMeshThreadgroup))
    }
    
    @available(macOS 13.0, iOS 16.0, *)
    override func drawMeshThreadgroups(indirectBuffer: Buffer, indirectBufferOffset: Int, threadsPerObjectThreadgroup: Size, threadsPerMeshThreadgroup: Size) {
        let mtlBuffer = resourceMap[indirectBuffer]!
        encoder.drawMeshThreadgroups(indirectBuffer: mtlBuffer.buffer, indirectBufferOffset: mtlBuffer.offset + indirectBufferOffset, threadsPerObjectThreadgroup: MTLSize(threadsPerObjectThreadgroup), threadsPerMeshThreadgroup: MTLSize(threadsPerMeshThreadgroup))
    }
    
    override func dispatchThreadsPerTile(_ threadsPerTile: Size) {
        encoder.dispatchThreadsPerTile(MTLSize(threadsPerTile))
    }
    
    override func useResource(_ resource: Resource, usage: ResourceUsageType, stages: RenderStages) {
        encoder.useResource(resourceMap[resource], usage: MTLResourceUsage(usage), stages: MTLRenderStages(stages))
    }
    
    override func useHeap(_ heap: Heap, stages: RenderStages) {
        encoder.useHeap(resourceMap[heap], stages: MTLRenderStages(stages))
    }
    
    override func memoryBarrier(scope: BarrierScope, after: RenderStages, before: RenderStages) {
        encoder.memoryBarrier(scope: MTLBarrierScope(scope), after: MTLRenderStages(after), before: MTLRenderStages(before))
    }
    
    override func memoryBarrier(resources: [Resource], after: RenderStages, before: RenderStages) {
        let mtlResources = resources.map { resourceMap[$0]! }
        encoder.memoryBarrier(resources: mtlResources, after: MTLRenderStages(after), before: MTLRenderStages(before))
    }
}
