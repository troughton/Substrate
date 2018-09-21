//
//  RenderTargetDescriptor.swift
//  InterdimensionalLlama
//
//  Created by Thomas Roughton on 2/04/17.
//
//

import Utilities

public protocol RenderTargetAttachmentDescriptor {
    /*!
     @property texture
     @abstract The Texture object for this attachment.
     */
    var texture: Texture { get set }
    
    /*!
     @property level
     @abstract The mipmap level of the texture to be used for rendering.  Default is zero.
     */
    var level: Int { get set }
    
    
    /*!
     @property slice
     @abstract The slice of the texture to be used for rendering.  Default is zero.
     */
    var slice: Int { get set }
    
    
    /*!
     @property depthPlane
     @abstract The depth plane of the texture to be used for rendering.  Default is zero.
     */
    var depthPlane: Int { get set }
    
    /*!
     @property wantsClear
     @abstract Whether this attachment wants to be cleared before being used for rendering.
     */
    var wantsClear : Bool { get }
}

public struct RenderTargetColorAttachmentDescriptor : RenderTargetAttachmentDescriptor, Hashable {

    public init(texture: Texture) {
        self.texture = texture
    }
    
    /*!
     @property texture
     @abstract The Texture object for this attachment.
     */
    public var texture: Texture
    
    /*!
     @property level
     @abstract The mipmap level of the texture to be used for rendering.  Default is zero.
     */
    public var level: Int = 0
    
    
    /*!
     @property slice
     @abstract The slice of the texture to be used for rendering.  Default is zero.
     */
    public var slice: Int = 0
    
    
    /*!
     @property depthPlane
     @abstract The depth plane of the texture to be used for rendering.  Default is zero.
     */
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
    
    /*!
     @property texture
     @abstract The Texture object for this attachment.
     */
    public var texture: Texture
    
    /*!
     @property level
     @abstract The mipmap level of the texture to be used for rendering.  Default is zero.
     */
    public var level: Int = 0
    
    
    /*!
     @property slice
     @abstract The slice of the texture to be used for rendering.  Default is zero.
     */
    public var slice: Int = 0
    
    
    /*!
     @property depthPlane
     @abstract The depth plane of the texture to be used for rendering.  Default is zero.
     */
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
    
    /*!
     @property texture
     @abstract The Texture object for this attachment.
     */
    public var texture: Texture
    
    /*!
     @property level
     @abstract The mipmap level of the texture to be used for rendering.  Default is zero.
     */
    public var level: Int = 0
    
    
    /*!
     @property slice
     @abstract The slice of the texture to be used for rendering.  Default is zero.
     */
    public var slice: Int = 0
    
    
    /*!
     @property depthPlane
     @abstract The depth plane of the texture to be used for rendering.  Default is zero.
     */
    public var depthPlane: Int = 0
    
    public var clearStencil : UInt32? = nil
    
    public var wantsClear : Bool {
        return self.clearStencil != nil
    }
}

/*!
 @class RenderTargetDescriptor
 @abstract RenderTargetDescriptor represents a collection of attachments to be used to create a concrete render command encoder
 */
public struct RenderTargetDescriptor : Hashable {
    
    public init<I : RenderTargetIdentifier>(identifierType: I.Type) {
         self.colorAttachments = Array(repeating: nil, count: I.count)
    }
    
    public var colorAttachments : [RenderTargetColorAttachmentDescriptor?]
    
    public var depthAttachment : RenderTargetDepthAttachmentDescriptor? = nil
    
    public var stencilAttachment : RenderTargetStencilAttachmentDescriptor? = nil
    
    /*!
     @property visibilityResultBuffer:
     @abstract Buffer into which samples passing the depth and stencil tests are counted.
     */
    public var visibilityResultBuffer: Buffer? = nil
    
    /*!
     @property renderTargetArrayLength:
     @abstract The number of active layers
     */
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
