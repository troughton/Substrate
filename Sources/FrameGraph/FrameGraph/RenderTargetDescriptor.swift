//
//  RenderTargetDescriptor.swift
//  SwiftFrameGraph
//
//  Created by Thomas Roughton on 2/04/17.
//
//

import Utilities

public protocol RenderTargetAttachmentDescriptor {
    var texture: Texture { get set }
    
    var level: Int { get set }
    
    var slice: Int { get set }
    
    var depthPlane: Int { get set }
    
    var wantsClear : Bool { get }
    
    /// If true, this texture's previous contents will not be loaded,
    /// and will be overwritten when the attachment is stored.
    var fullyOverwritesContents : Bool { get set }
}

public struct RenderTargetColorAttachmentDescriptor : RenderTargetAttachmentDescriptor, Hashable {

    public init(texture: Texture) {
        self.texture = texture
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
}

public struct RenderTargetDepthAttachmentDescriptor : RenderTargetAttachmentDescriptor, Hashable {
    
    public init(texture: Texture) {
        self.texture = texture
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
}

public struct RenderTargetStencilAttachmentDescriptor : RenderTargetAttachmentDescriptor, Hashable {
    
    public init(texture: Texture) {
        self.texture = texture
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
}

public struct RenderTargetDescriptor : Hashable {
    
    public init<I : RenderTargetIdentifier>(identifierType: I.Type) {
         self.colorAttachments = Array(repeating: nil, count: I.count)
    }
    
    public var colorAttachments : [RenderTargetColorAttachmentDescriptor?]
    
    public var depthAttachment : RenderTargetDepthAttachmentDescriptor? = nil
    
    public var stencilAttachment : RenderTargetStencilAttachmentDescriptor? = nil
    
    public var visibilityResultBuffer: Buffer? = nil
    
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
    
    public static func areMergeable(_ descriptorA: RenderTargetDescriptor, _ descriptorB: RenderTargetDescriptor) -> Bool {
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
        
        return true
    }
}
