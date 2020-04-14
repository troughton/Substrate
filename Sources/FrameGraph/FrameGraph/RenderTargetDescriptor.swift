//
//  RenderTargetDescriptor.swift
//  SwiftFrameGraph
//
//  Created by Thomas Roughton on 2/04/17.
//
//

import FrameGraphUtilities

public protocol RenderTargetAttachmentDescriptor {
    var texture: Texture { get set }
    
    var level: Int { get set }
    
    var slice: Int { get set }
    
    var depthPlane: Int { get set }
    
    var wantsClear : Bool { get }
    
    /// If true, this texture's previous contents will not be loaded,
    /// and will be overwritten when the attachment is stored.
    var fullyOverwritesContents : Bool { get set }
    
    /// The texture to perform a multisample resolve action on at the completion of the render pass.
    var resolveTexture : Texture? { get set }
    
    /// The mipmap level of the resolve texture to resolve to.
    var resolveLevel : Int { get set }
    
    /// The slice of the resolve texture to resolve to.
    var resolveSlice : Int { get set }
    
    /// The depth plane of the resolve texture to resolve to.
    var resolveDepthPlane : Int { get set }
}

public struct ColorAttachmentDescriptor : RenderTargetAttachmentDescriptor, Hashable {

    public init(texture: Texture, level: Int = 0, slice: Int = 0, depthPlane: Int = 0, clearColor: ClearColor? = nil,
                resolveTexture: Texture? = nil, resolveLevel: Int = 0, resolveSlice: Int = 0, resolveDepthPlane: Int = 0) {
        self.texture = texture
        self.level = level
        self.slice = slice
        self.depthPlane = depthPlane
        self.clearColor = clearColor
        self.resolveTexture = resolveTexture
        self.resolveLevel = resolveLevel
        self.resolveSlice = resolveSlice
        self.resolveDepthPlane = resolveDepthPlane
    }
    
    public var texture: Texture
    
    /// The mipmap level of the texture to be used for rendering.
    public var level: Int = 0
    
    /// The slice of the texture to be used for rendering. 
    public var slice: Int = 0
    
    /// The depth plane of the texture to be used for rendering.
    public var depthPlane: Int = 0
    
    /// The color to clear this attachment to.
    public var clearColor : ClearColor? = nil
    
    /// If true, this texture's previous contents will not be loaded,
    /// and will be overwritten when the attachment is stored.
    public var fullyOverwritesContents : Bool = false
    
    public var wantsClear: Bool {
        return self.clearColor != nil
    }
    
    /// The texture to perform a multisample resolve action on at the completion of the render pass.
    public var resolveTexture : Texture? = nil
    
    /// The mipmap level of the resolve texture to resolve to.
    public var resolveLevel : Int = 0
    
    /// The slice of the resolve texture to resolve to.
    public var resolveSlice : Int = 0
    
    /// The depth plane of the resolve texture to resolve to.
    public var resolveDepthPlane : Int = 0
    
}

public struct DepthAttachmentDescriptor : RenderTargetAttachmentDescriptor, Hashable {
    
    public init(texture: Texture, level: Int = 0, slice: Int = 0, depthPlane: Int = 0, clearDepth: Double? = nil,
                resolveTexture: Texture? = nil, resolveLevel: Int = 0, resolveSlice: Int = 0, resolveDepthPlane: Int = 0) {
        self.texture = texture
        self.level = level
        self.slice = slice
        self.depthPlane = depthPlane
        self.clearDepth = clearDepth
        self.resolveTexture = resolveTexture
        self.resolveLevel = resolveLevel
        self.resolveSlice = resolveSlice
        self.resolveDepthPlane = resolveDepthPlane
    }
    
    public var texture: Texture
    
    /// The mipmap level of the texture to be used for rendering.
    public var level: Int = 0

    /// The slice of the texture to be used for rendering. 
    public var slice: Int = 0

    /// The depth plane of the texture to be used for rendering.
    public var depthPlane: Int = 0
    
    /// The depth to clear this attachment to.
    public var clearDepth : Double? = nil
    
    /// If true, this texture's previous contents will not be loaded,
    /// and will be overwritten when the attachment is stored.
    public var fullyOverwritesContents : Bool = false
    
    public var wantsClear : Bool {
        return self.clearDepth != nil
    }
    
    /// The texture to perform a multisample resolve action on at the completion of the render pass.
    public var resolveTexture : Texture? = nil
    
    /// The mipmap level of the resolve texture to resolve to.
    public var resolveLevel : Int = 0
    
    /// The slice of the resolve texture to resolve to.
    public var resolveSlice : Int = 0
    
    /// The depth plane of the resolve texture to resolve to.
    public var resolveDepthPlane : Int = 0
}

public struct StencilAttachmentDescriptor : RenderTargetAttachmentDescriptor, Hashable {
    
    public init(texture: Texture, level: Int = 0, slice: Int = 0, depthPlane: Int = 0, clearStencil: UInt32? = nil,
                resolveTexture: Texture? = nil, resolveLevel: Int = 0, resolveSlice: Int = 0, resolveDepthPlane: Int = 0) {
        self.texture = texture
        self.level = level
        self.slice = slice
        self.depthPlane = depthPlane
        self.clearStencil = clearStencil
        self.resolveTexture = resolveTexture
        self.resolveLevel = resolveLevel
        self.resolveSlice = resolveSlice
        self.resolveDepthPlane = resolveDepthPlane
    }
    
    public var texture: Texture
    
    /// The mipmap level of the texture to be used for rendering.
    public var level: Int = 0
    
    /// The slice of the texture to be used for rendering. 
    public var slice: Int = 0
    
    /// The depth plane of the texture to be used for rendering.
    public var depthPlane: Int = 0
    
    /// The stencil value to clear this attachment to.
    public var clearStencil : UInt32? = nil
    
    /// If true, this texture's previous contents will not be loaded,
    /// and will be overwritten when the attachment is stored.
    public var fullyOverwritesContents : Bool = false
    
    public var wantsClear : Bool {
        return self.clearStencil != nil
    }
    
    /// The texture to perform a multisample resolve action on at the completion of the render pass.
    public var resolveTexture : Texture? = nil
    
    /// The mipmap level of the resolve texture to resolve to.
    public var resolveLevel : Int = 0
    
    /// The slice of the resolve texture to resolve to.
    public var resolveSlice : Int = 0
    
    /// The depth plane of the resolve texture to resolve to.
    public var resolveDepthPlane : Int = 0
}


// For compatibility with old FrameGraph versions:
public typealias RenderTargetColorAttachmentDescriptor = ColorAttachmentDescriptor
public typealias RenderTargetDepthAttachmentDescriptor = DepthAttachmentDescriptor
public typealias RenderTargetStencilAttachmentDescriptor = StencilAttachmentDescriptor

public struct RenderTargetDescriptor : Hashable {
    
    @inlinable
    public init(attachmentCount: Int) {
        self.colorAttachments = .init(repeating: nil, count: attachmentCount)
    }
    
    @inlinable
    public init(colorAttachments: [ColorAttachmentDescriptor?] = [], depthAttachment: DepthAttachmentDescriptor? = nil, stencilAttachment: StencilAttachmentDescriptor? = nil) {
        self.colorAttachments = colorAttachments
        self.depthAttachment = depthAttachment
        self.stencilAttachment = stencilAttachment
    }
    
    public var colorAttachments : [ColorAttachmentDescriptor?]
    
    public var depthAttachment : DepthAttachmentDescriptor? = nil
    
    public var stencilAttachment : StencilAttachmentDescriptor? = nil
    
    public var visibilityResultBuffer: Buffer? = nil
    
    public var renderTargetArrayLength: Int = 0
    
    public var size : Size {
        var width = Int.max
        var height = Int.max
        
        width = min(self.depthAttachment?.texture.width ?? .max, width)
        height = min(self.depthAttachment?.texture.height ?? .max, height)
        width = min(self.stencilAttachment?.texture.width ?? .max, width)
        height = min(self.stencilAttachment?.texture.height ?? .max, height)
        
        for attachment in self.colorAttachments {
            width = min(attachment?.texture.width ?? .max, width)
            height = min(attachment?.texture.height ?? .max, height)
        }
        
        return width == .max ? Size(length: 1) : Size(width: width, height: height, depth: 1)
    }
    
    public var width: Int {
        return self.size.width
    }
    
    public var height: Int {
        return self.size.height
    }
    
    static func areMergeable(_ descriptorA: RenderTargetDescriptor, _ descriptorB: RenderTargetDescriptor) -> Bool {
        if let depthA = descriptorA.depthAttachment, let depthB = descriptorB.depthAttachment, depthA.texture != depthB.texture || depthB.wantsClear {
            return false
        }
        
        if let stencilA = descriptorA.stencilAttachment, let stencilB = descriptorB.stencilAttachment, stencilA.texture != stencilB.texture || stencilB.wantsClear {
            return false
        }
        
        if let visA = descriptorA.visibilityResultBuffer, let visB = descriptorB.visibilityResultBuffer, visA != visB {
            return false
        }
        
        for i in 0..<min(descriptorA.colorAttachments.count, descriptorB.colorAttachments.count) {
            if let colorA = descriptorA.colorAttachments[i], let colorB = descriptorB.colorAttachments[i], colorA.texture != colorB.texture || colorB.wantsClear {
                return false
            }
        }
        
        return descriptorA.size == descriptorB.size
    }
}
