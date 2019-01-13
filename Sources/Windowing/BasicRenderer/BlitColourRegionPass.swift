//
//  BlitColourRegionPass.swift
//  Windowing
//
//  Created by Thomas Roughton on 14/01/19.
//

import Foundation
import SwiftFrameGraph
import SwiftMath

extension Buffer {
    
    /// Precondition: the lifetime of 'bytes' must continue until after the next FrameGraph.execute call.
    public init(stagingBytes bytes: UnsafeRawPointer, length: Int, usage: BufferUsage = .unknown, flags: ResourceFlags, retainHandle: Any? = nil) {
        assert(!flags.contains(.persistent) || usage != .unknown, "A persistent buffer must have its usage specified.")
        
        let safeLength = ((length + 3) / 4) * 4 // Round up to be a multiple of four bytes.
        
        let stagingBuffer = Buffer(descriptor: BufferDescriptor(length: safeLength, storageMode: .shared, cacheMode: .writeCombined, usage: .blitSource))
        self.init(descriptor: BufferDescriptor(length: safeLength, storageMode: .private, usage: [usage, .blitDestination]), flags: flags)
        
        let target = self
        FrameGraph.insertEarlyBlitPass(name: "Staging Buffer Update", execute: { (blitEncoder) in
            if let retainHandle = retainHandle {
                withExtendedLifetime(retainHandle) {
                    stagingBuffer[stagingBuffer.range].withContents { $0.copyMemory(from: bytes, byteCount: length) }
                }
            } else {
                stagingBuffer[stagingBuffer.range].withContents { $0.copyMemory(from: bytes, byteCount: length) }
            }
            
            blitEncoder.copy(from: stagingBuffer, sourceOffset: 0, to: target, destinationOffset: 0, size: safeLength)
        })
    }
}

final class FullScreenTriangle {
    private let triangleVertices:[Float] =
        [
            -1.0, -1.0, 0.0, 1.0,
            -1.0,  3.0, 0.0, 1.0,
            3.0, -1.0, 0.0, 1.0
    ]
    
    private let buffer : Buffer
    
    static let tri = FullScreenTriangle()
    
    static func draw(renderEncoder: RenderCommandEncoder) {
        renderEncoder.setVertexBuffer(self.tri.buffer, offset: 0, index: 0)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3, instanceCount: 1)
    }
    
    init() {
        self.buffer = Buffer(stagingBytes: self.triangleVertices, length: MemoryLayout<Float>.size * triangleVertices.count, usage: .vertexBuffer, flags: [.persistent, .immutableOnceInitialised])
        //        self.buffer.label = "Full Screen Triangle"
    }
}


final class BlitColorRegionPass : DrawRenderPass {
    static let pipelineDescriptor : RenderPipelineDescriptor = {
        var pipelineDescriptor = RenderPipelineDescriptor(identifier: DisplayRenderTargetIndex.self)
        pipelineDescriptor.vertexDescriptor = nil
        pipelineDescriptor.vertexFunction = "passThroughVertex"
        pipelineDescriptor.fragmentFunction = "hdrResolveFragment"
        
        pipelineDescriptor.label = "HDR Tone Map"
        return pipelineDescriptor
    }()
    
    static let depthStencilDescriptor : DepthStencilDescriptor = {
        var depthStencilDescriptor = DepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .always
        depthStencilDescriptor.isDepthWriteEnabled = false
        return depthStencilDescriptor
    }()
    
    let name = "Blit Colour Region"
    
    let inputTexture : Texture
    let scissorRect : ScissorRect?
    let renderTargetDescriptor : RenderTargetDescriptor
    
    init(inputTexture: Texture, scissorRect: ScissorRect? = nil, renderTargetDescriptor: RenderTargetDescriptor) {
        self.inputTexture = inputTexture
        self.scissorRect = scissorRect
        self.renderTargetDescriptor = renderTargetDescriptor
    }
    
    func execute(renderCommandEncoder renderEncoder: RenderCommandEncoder) {
        if let scissorRect = self.scissorRect {
            renderEncoder.setViewport(Viewport(originX: Double(scissorRect.x), originY: Double(scissorRect.y), width: Double(scissorRect.width), height: Double(scissorRect.height), zNear: 0.0, zFar: 1.0))
            
            let viewportOrigin = Vector2f(scissorRect.x, scissorRect.y)
            renderEncoder.setValue(viewportOrigin, key: "viewportOrigin")
        } else {
            renderEncoder.setValue(Vector2f(0, 0), key: "viewportOrigin")
        }
        
        renderEncoder.setTexture(inputTexture, key: "inputTexture")
        renderEncoder.setCullMode(.none)
        
        if self.renderTargetDescriptor.depthAttachment != nil {
            renderEncoder.setDepthStencilDescriptor(BlitColorRegionPass.depthStencilDescriptor)
        }
        
        renderEncoder.setRenderPipelineDescriptor(BlitColorRegionPass.pipelineDescriptor)
        
        FullScreenTriangle.draw(renderEncoder: renderEncoder)
        
    }
}

final class ClearRenderTargetPass : DrawRenderPass {
    let name = "clearRenderTarget"
    let outputTexture: Texture
    let renderTargetDescriptor: RenderTargetDescriptor
    
    init(outputTexture: Texture, clearColor: ClearColor = ClearColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1.0)) {
        self.outputTexture = outputTexture
        
        var attachment = RenderTargetColorAttachmentDescriptor(texture: outputTexture)
        attachment.clearColor = clearColor
        
        var renderTargetDesc = RenderTargetDescriptor(identifierType: DisplayRenderTargetIndex.self)
        renderTargetDesc[DisplayRenderTargetIndex.display] = attachment
        
        self.renderTargetDescriptor = renderTargetDesc
    }
    
    func execute(renderCommandEncoder renderEncoder: RenderCommandEncoder) {
    }
}
