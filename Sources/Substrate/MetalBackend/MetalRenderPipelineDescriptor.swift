//
//  TypedRenderPipelineDescriptor.swift
//  Substrate
//
//  Created by Thomas Roughton on 26/12/17.
//

#if canImport(Metal)

import Metal

struct MetalRenderPipelineDescriptor : Hashable {
    var descriptor : RenderPipelineDescriptor
    var colorAttachmentFormats : [MTLPixelFormat]
    var depthAttachmentFormat : MTLPixelFormat = .invalid
    var stencilAttachmentFormat : MTLPixelFormat = .invalid
    
    var colorAttachmentSampleCounts : [Int?]
    var depthSampleCount : Int?
    var stencilSampleCount : Int?
    
    public init(_ descriptor: RenderPipelineDescriptor, renderTargetDescriptor: RenderTargetDescriptor) {
        self.descriptor = descriptor
        self.colorAttachmentFormats = renderTargetDescriptor.colorAttachments.map { MTLPixelFormat($0?.texture.descriptor.pixelFormat ?? .invalid) }
        self.depthAttachmentFormat = MTLPixelFormat(renderTargetDescriptor.depthAttachment?.texture.descriptor.pixelFormat ?? .invalid)
        self.stencilAttachmentFormat = MTLPixelFormat(renderTargetDescriptor.stencilAttachment?.texture.descriptor.pixelFormat ?? .invalid)
        
        self.colorAttachmentSampleCounts = renderTargetDescriptor.colorAttachments.map { $0?.texture.descriptor.sampleCount }
        self.depthSampleCount = renderTargetDescriptor.depthAttachment?.texture.descriptor.sampleCount
        self.stencilSampleCount = renderTargetDescriptor.stencilAttachment?.texture.descriptor.sampleCount
    }
}

#endif // canImport(Metal)
