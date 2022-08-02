//
//  TypedRenderPipelineDescriptor.swift
//  Substrate
//
//  Created by Thomas Roughton on 26/12/17.
//

#if canImport(Metal)

@preconcurrency import Metal

struct MetalRenderPipelineDescriptor : Hashable {
    var descriptor : RenderPipelineDescriptor
    var colorAttachmentFormats : [MTLPixelFormat]
    var depthAttachmentFormat : MTLPixelFormat = .invalid
    var stencilAttachmentFormat : MTLPixelFormat = .invalid
    
    var colorAttachmentSampleCounts : [Int?]
    var depthSampleCount : Int?
    var stencilSampleCount : Int?
    
    public init(_ descriptor: RenderPipelineDescriptor, renderTargetsDescriptor: RenderTargetDescriptor) {
        self.descriptor = descriptor
        self.colorAttachmentFormats = renderTargetsDescriptor.colorAttachments.map { MTLPixelFormat($0?.texture.descriptor.pixelFormat ?? .invalid) }
        self.depthAttachmentFormat = MTLPixelFormat(renderTargetsDescriptor.depthAttachment?.texture.descriptor.pixelFormat ?? .invalid)
        self.stencilAttachmentFormat = MTLPixelFormat(renderTargetsDescriptor.stencilAttachment?.texture.descriptor.pixelFormat ?? .invalid)
        
        self.colorAttachmentSampleCounts = renderTargetsDescriptor.colorAttachments.map { $0?.texture.descriptor.sampleCount }
        self.depthSampleCount = renderTargetsDescriptor.depthAttachment?.texture.descriptor.sampleCount
        self.stencilSampleCount = renderTargetsDescriptor.stencilAttachment?.texture.descriptor.sampleCount
    }
}

#endif // canImport(Metal)
