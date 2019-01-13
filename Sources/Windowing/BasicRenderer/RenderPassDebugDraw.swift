//
//  RenderPassDebugDraw.swift
//  InterdimensionalLlama
//
//  Created by Joseph Bennett on 8/04/17.
//
//

import SwiftFrameGraph
import SwiftFrameGraph
import DrawTools
import SwiftMath
import CDebugDrawTools
import Utilities


final class DebugDrawPass : DrawRenderPass {
    
    static let vertexDescriptor : VertexDescriptor = {
        var descriptor = VertexDescriptor()
        
        // position
        descriptor.attributes[0].bufferIndex = 0
        descriptor.attributes[0].offset = 0
        descriptor.attributes[0].format = .float3
        
        // colour
        descriptor.attributes[1].bufferIndex = 0
        descriptor.attributes[1].offset = 12
        descriptor.attributes[1].format = .uchar4Normalized
        
        descriptor.layouts[0].stepFunction = .perVertex
        descriptor.layouts[0].stepRate = 1
        descriptor.layouts[0].stride = MemoryLayout<DebugDraw.DebugVertex>.size
        
        return descriptor
    }()
    
    static let vertexDescriptorPoint : VertexDescriptor = {
        var descriptor = DebugDrawPass.vertexDescriptor
        
        // size
        descriptor.attributes[2].bufferIndex = 1
        descriptor.attributes[2].offset = 0
        descriptor.attributes[2].format = .float
        
        descriptor.layouts[1].stepFunction = .perVertex
        descriptor.layouts[1].stepRate = 1
        descriptor.layouts[1].stride = MemoryLayout<Float>.size
        
        return descriptor
    }()
    
    static let depthStencilNoDepth : DepthStencilDescriptor = {
        var depthStencilDescriptor = DepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .always
        depthStencilDescriptor.isDepthWriteEnabled = false
        return depthStencilDescriptor
    }()
    
    static let depthStencilWithDepth : DepthStencilDescriptor = {
        var depthStencilDescriptor = DepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .greater
        depthStencilDescriptor.isDepthWriteEnabled = true
        return depthStencilDescriptor
    }()
    
    static let pipelineDescriptor : RenderPipelineDescriptor = {
        var descriptor = RenderPipelineDescriptor(identifier: DisplayRenderTargetIndex.self)
        
        var blendDescriptor = BlendDescriptor()
        
        blendDescriptor.alphaBlendOperation = .add
        blendDescriptor.rgbBlendOperation = .add
        blendDescriptor.sourceRGBBlendFactor = .sourceAlpha
        blendDescriptor.sourceAlphaBlendFactor = .sourceAlpha
        blendDescriptor.destinationRGBBlendFactor = .oneMinusSourceAlpha
        blendDescriptor.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        descriptor[blendStateFor: DisplayRenderTargetIndex.display] = blendDescriptor
        
        descriptor.vertexDescriptor = DebugDrawPass.vertexDescriptor
        
        descriptor.vertexFunction = "debugDrawVertex"
        descriptor.fragmentFunction = "debugDrawFragment"
        
        return descriptor
    }()
    
    
    let renderTargetDescriptor: RenderTargetDescriptor
    
    var name: String = "Debug Draw"
    
    let drawData : DebugDraw.DrawData
    let projectionMatrix: Matrix4x4f
    
    init(drawData: DebugDraw.DrawData, projectionMatrix: Matrix4x4f, renderTargetDescriptor: RenderTargetDescriptor) {
        self.drawData = drawData
        self.projectionMatrix = projectionMatrix
        self.renderTargetDescriptor = renderTargetDescriptor
    }
    
    func execute(renderCommandEncoder rce: RenderCommandEncoder) {
        rce.setTriangleFillMode(.fill)
        rce.setCullMode(.none)
        
        rce.setRenderPipelineDescriptor(DebugDrawPass.pipelineDescriptor)
        
        rce.setValue(projectionMatrix, key: "debugDrawUniforms")
        
        let bufferSize = self.drawData.depthDisabledData.requiredBufferCapacity + self.drawData.depthEnabledData.requiredBufferCapacity
        let buffer = Buffer(length: bufferSize)
        let bufferSlice = buffer[buffer.range]
        defer { bufferSlice.forceFlush() }
        
        var pipelineDescriptor = DebugDrawPass.pipelineDescriptor
        rce.setRenderPipelineDescriptor(pipelineDescriptor)
        
        rce.setVertexBuffer(buffer, offset: 0, index: 0)
        rce.setVertexBuffer(buffer, offset: 0, index: 1)
        
        var bufferOffset = 0
        // Non-points
        do {
            rce.setDepthStencilDescriptor(DebugDrawPass.depthStencilWithDepth)
            self.drawData.depthEnabledData.drawNonPoints(encoder: rce, buffer: bufferSlice, bufferOffset: &bufferOffset)
            
            rce.setDepthStencilDescriptor(DebugDrawPass.depthStencilNoDepth)
            self.drawData.depthDisabledData.drawNonPoints(encoder: rce, buffer: bufferSlice, bufferOffset: &bufferOffset)
        }
        
        // Points
        do {
            pipelineDescriptor.vertexFunction = "debugDrawPoint"
            pipelineDescriptor.fragmentFunction = "debugDrawFragmentPoint"
            
            pipelineDescriptor.vertexDescriptor = DebugDrawPass.vertexDescriptorPoint
            rce.setRenderPipelineDescriptor(pipelineDescriptor)
            
            rce.setDepthStencilDescriptor(DebugDrawPass.depthStencilWithDepth)
            self.drawData.depthEnabledData.drawPoints(encoder: rce, buffer: bufferSlice, bufferOffset: &bufferOffset)
            
            rce.setDepthStencilDescriptor(DebugDrawPass.depthStencilNoDepth)
            self.drawData.depthDisabledData.drawPoints(encoder: rce, buffer: bufferSlice, bufferOffset: &bufferOffset)
        }
    }
}

extension DebugDraw.DebugDrawData {
    var requiredBufferCapacity : Int {
        return MemoryLayout<DebugDraw.DebugVertex>.size * (self.points.count + self.lines.count + self.wireframeTriangles.count + self.filledTriangles.count) + MemoryLayout<Float>.size * self.pointSizes.count
    }
    
    func drawPoints(encoder: RenderCommandEncoder, buffer: RawBufferSlice, bufferOffset: inout Int) {
        let pointsSize = self.points.count * MemoryLayout<DebugDraw.DebugVertex>.size
        if pointsSize > 0 {
            buffer.withContents { $0.advanced(by: bufferOffset).copyMemory(from: self.points.buffer, byteCount: self.points.count * MemoryLayout<DebugDraw.DebugVertex>.size) }
            encoder.setVertexBufferOffset(bufferOffset, index: 0)
            bufferOffset += pointsSize
            
            let pointSizesSize = self.pointSizes.count * MemoryLayout<Float>.size
            buffer.withContents { $0.advanced(by: bufferOffset).copyMemory(from: self.pointSizes.buffer, byteCount: pointSizesSize) }
            encoder.setVertexBufferOffset(bufferOffset, index: 1)
            bufferOffset += pointSizesSize
            
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: self.points.count)
        }
    }
    
    func drawNonPoints(encoder: RenderCommandEncoder, buffer: RawBufferSlice, bufferOffset: inout Int) {
        let linesSize = self.lines.count * MemoryLayout<DebugDraw.DebugVertex>.size
        if linesSize > 0 {
            buffer.withContents { $0.advanced(by: bufferOffset).copyMemory(from: self.lines.buffer, byteCount: self.lines.count * MemoryLayout<DebugDraw.DebugVertex>.size) }
            encoder.setVertexBufferOffset(bufferOffset, index: 0)
            bufferOffset += linesSize
            
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: self.lines.count)
        }
        
        let filledTrianglesSize = self.filledTriangles.count * MemoryLayout<DebugDraw.DebugVertex>.size
        if filledTrianglesSize > 0 {
            encoder.setTriangleFillMode(.fill)
            
            buffer.withContents { $0.advanced(by: bufferOffset).copyMemory(from: self.filledTriangles.buffer, byteCount: self.filledTriangles.count * MemoryLayout<DebugDraw.DebugVertex>.size) }
            encoder.setVertexBufferOffset(bufferOffset, index: 0)
            bufferOffset += filledTrianglesSize
            
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: self.filledTriangles.count)
        }
        
        let wireframeTrianglesSize = self.wireframeTriangles.count * MemoryLayout<DebugDraw.DebugVertex>.size
        if wireframeTrianglesSize > 0 {
            encoder.setTriangleFillMode(.lines)
            
            buffer.withContents { $0.advanced(by: bufferOffset).copyMemory(from: self.wireframeTriangles.buffer, byteCount: self.wireframeTriangles.count * MemoryLayout<DebugDraw.DebugVertex>.size) }
            encoder.setVertexBufferOffset(bufferOffset, index: 0)
            bufferOffset += wireframeTrianglesSize
            
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: self.wireframeTriangles.count)
        }
    }
}
