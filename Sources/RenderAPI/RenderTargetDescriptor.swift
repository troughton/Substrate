//
//  RenderTargetDescriptor.swift
//  InterdimensionalLlama
//
//  Created by Thomas Roughton on 2/04/17.
//
//

import Utilities

public protocol RenderTargetAttachmentDescriptor {
    var texture: Texture { get set }
    
    /// The mipmap level to be used for rendering.
    var level: Int { get set }
    
    /// The slice of the texture to be used for rendering.
    var slice: Int { get set }
    
    /// The depth plane of the texture to be used for rendering.
    var depthPlane: Int { get set }
    
    /// Whether this attachment wants to be cleared before being used for rendering.
    var wantsClear : Bool { get }
}

public struct RenderTargetColorAttachmentDescriptor : RenderTargetAttachmentDescriptor, Hashable {

    public init(texture: Texture) {
        self.texture = texture
    }
    
    public var texture: Texture
    
    /// The mipmap level to be used for rendering.
    public var level: Int = 0
    
    /// The slice of the texture to be used for rendering.
    public var slice: Int = 0
    
    /// The depth plane of the texture to be used for rendering.
    public var depthPlane: Int = 0
    
    public var clearColor : ClearColor? = nil
    
    public var wantsClear: Bool {
        return self.clearColor != nil
    }
}

public struct RenderTargetDepthAttachmentDescriptor : RenderTargetAttachmentDescriptor, Hashable {
    
    public init(texture: Texture) {
        self.texture = texture
    }
    
    public var texture: Texture

    /// The mipmap level to be used for rendering.
    public var level: Int = 0

    /// The slice of the texture to be used for rendering.
    public var slice: Int = 0
    
    /// The depth plane of the texture to be used for rendering.
    public var depthPlane: Int = 0
    
    public var clearDepth : Double? = nil
    
    public var wantsClear : Bool {
        return self.clearDepth != nil
    }
}

public struct RenderTargetStencilAttachmentDescriptor : RenderTargetAttachmentDescriptor, Hashable {
    
    public init(texture: Texture) {
        self.texture = texture
    }
    
    public var texture: Texture
    
    /// The mipmap level to be used for rendering.
    public var level: Int = 0
    
    /// The slice of the texture to be used for rendering.
    public var slice: Int = 0

    /// The depth plane of the texture to be used for rendering.
    public var depthPlane: Int = 0
    
    public var clearStencil : UInt32? = nil
    
    public var wantsClear : Bool {
        return self.clearStencil != nil
    }
}

/**
 A render target descriptor describes a collection of attachments to be used in a DrawRenderPass.
 */
public struct RenderTargetDescriptor : Hashable {
    
    public init<I : RenderTargetIdentifier>(identifierType: I.Type) {
         self.colorAttachments = Array(repeating: nil, count: I.count)
    }
    
    public var colorAttachments : [RenderTargetColorAttachmentDescriptor?]
    
    public var depthAttachment : RenderTargetDepthAttachmentDescriptor? = nil
    
    public var stencilAttachment : RenderTargetStencilAttachmentDescriptor? = nil
    

    /// Buffer into which samples passing the depth and stencil tests are counted.
    public var visibilityResultBuffer: Buffer? = nil
    
    /// The number of active layers
    public var renderTargetArrayLength: Int = 0
    
    public subscript<I : RenderTargetIdentifier>(attachment: I) -> RenderTargetColorAttachmentDescriptor? {
        get {
            return self.colorAttachments[attachment.rawValue]
        }
        set {
            self.colorAttachments[attachment.rawValue] = newValue
        }
    }
    
    public var size : Size {
        var width = 0
        var height = 0
        
        width = max(self.depthAttachment?.texture.width ?? 0, width)
        height = max(self.depthAttachment?.texture.height ?? 0, height)
        
        for attachment in self.colorAttachments {
            width = max(attachment?.texture.width ?? 0, width)
            height = max(attachment?.texture.height ?? 0, height)
        }
        
        return Size(width: width, height: height, depth: 1)
    }
}
