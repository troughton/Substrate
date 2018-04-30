//
//  RenderPipelineDescriptor.swift
//  InterdimensionalLlama
//
//  Created by Thomas Roughton on 26/12/17.
//

import Metal
import FrameGraph
import RenderAPI

struct MetalRenderPipelineDescriptor : Hashable {
    var descriptor : RenderPipelineDescriptor
    var colorAttachmentFormats : [MTLPixelFormat]
    var depthAttachmentFormat : MTLPixelFormat = .invalid
    var stencilAttachmentFormat : MTLPixelFormat = .invalid
    
    public init(_ descriptor: RenderPipelineDescriptor, renderTargetDescriptor: RenderTargetDescriptor) {
        self.descriptor = descriptor
        self.colorAttachmentFormats = renderTargetDescriptor.colorAttachments.map { MTLPixelFormat($0?.texture.descriptor.pixelFormat ?? .invalid) }
        self.depthAttachmentFormat = MTLPixelFormat(renderTargetDescriptor.depthAttachment?.texture.descriptor.pixelFormat ?? .invalid)
        self.stencilAttachmentFormat = MTLPixelFormat(renderTargetDescriptor.stencilAttachment?.texture.descriptor.pixelFormat ?? .invalid)
    }
}
