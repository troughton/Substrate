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
    
    /// The texture to perform a multisample resolve action on at the completion of the render pass.
    var resolveTexture : Texture? { get set }
    
    /// The mipmap level of the resolve texture to resolve to.
    var resolveLevel : Int { get set }
    
    /// The slice of the resolve texture to resolve to.
    var resolveSlice : Int { get set }
    
    /// The depth plane of the resolve texture to resolve to.
    var resolveDepthPlane : Int { get set }
}

extension RenderTargetAttachmentDescriptor {
    var arraySlice: Int {
        if texture.descriptor.textureType == .typeCube || texture.descriptor.textureType == .typeCubeArray {
            return self.slice / 6
        }
        return self.slice
    }
    
    var resolveArraySlice: Int {
        if texture.descriptor.textureType == .typeCube || texture.descriptor.textureType == .typeCubeArray {
            return self.resolveSlice / 6
        }
        return self.resolveSlice
    }
}

public struct ColorAttachmentDescriptor : RenderTargetAttachmentDescriptor, Hashable {

    public init(texture: Texture, level: Int = 0, slice: Int = 0, depthPlane: Int = 0,
                resolveTexture: Texture? = nil, resolveLevel: Int = 0, resolveSlice: Int = 0, resolveDepthPlane: Int = 0) {
        self.texture = texture
        self.level = level
        self.slice = slice
        self.depthPlane = depthPlane
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
    
    public init(texture: Texture, level: Int = 0, slice: Int = 0, depthPlane: Int = 0,
                resolveTexture: Texture? = nil, resolveLevel: Int = 0, resolveSlice: Int = 0, resolveDepthPlane: Int = 0) {
        self.texture = texture
        self.level = level
        self.slice = slice
        self.depthPlane = depthPlane
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
    
    public init(texture: Texture, level: Int = 0, slice: Int = 0, depthPlane: Int = 0,
                resolveTexture: Texture? = nil, resolveLevel: Int = 0, resolveSlice: Int = 0, resolveDepthPlane: Int = 0) {
        self.texture = texture
        self.level = level
        self.slice = slice
        self.depthPlane = depthPlane
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
    
    /// The texture to perform a multisample resolve action on at the completion of the render pass.
    public var resolveTexture : Texture? = nil
    
    /// The mipmap level of the resolve texture to resolve to.
    public var resolveLevel : Int = 0
    
    /// The slice of the resolve texture to resolve to.
    public var resolveSlice : Int = 0
    
    /// The depth plane of the resolve texture to resolve to.
    public var resolveDepthPlane : Int = 0
}

protocol ClearOperation {
    var isClear: Bool { get }
    var isKeep: Bool { get }
    var isDiscard: Bool { get }
}

public enum ColorClearOperation: ClearOperation {
    case discard
    case keep
    case clear(ClearColor)
    
    var isClear: Bool {
        if case .clear = self {
            return true
        }
        return false
    }
    
    var isDiscard: Bool {
        if case .discard = self {
            return true
        }
        return false
    }
    
    var isKeep: Bool {
        if case .keep = self {
            return true
        }
        return false
    }
}

public enum DepthClearOperation: ClearOperation {
    case discard
    case keep
    case clear(Double)
    
    var isClear: Bool {
        if case .clear = self {
            return true
        }
        return false
    }
    
    var isDiscard: Bool {
        if case .discard = self {
            return true
        }
        return false
    }
    
    var isKeep: Bool {
        if case .keep = self {
            return true
        }
        return false
    }
}

public enum StencilClearOperation: ClearOperation {
    case discard
    case keep
    case clear(UInt32)
    
    var isClear: Bool {
        if case .clear = self {
            return true
        }
        return false
    }
    
    var isDiscard: Bool {
        if case .discard = self {
            return true
        }
        return false
    }
    
    var isKeep: Bool {
        if case .keep = self {
            return true
        }
        return false
    }
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
        
        width = min(self.depthAttachment.map { $0.texture.width >> $0.level } ?? .max, width)
        height = min(self.depthAttachment.map { $0.texture.height >> $0.level } ?? .max, height)
        width = min(self.stencilAttachment.map { $0.texture.width >> $0.level } ?? .max, width)
        height = min(self.stencilAttachment.map { $0.texture.height >> $0.level } ?? .max, height)
        
        for attachment in self.colorAttachments {
            width = min(attachment.map { $0.texture.width >> $0.level } ?? .max, width)
            height = min(attachment.map { $0.texture.height >> $0.level } ?? .max, height)
        }
        
        return width == .max ? Size(length: 1) : Size(width: width, height: height, depth: 1)
    }
    
    public var width: Int {
        return self.size.width
    }
    
    public var height: Int {
        return self.size.height
    }
    
    static func descriptorsAreMergeable(passA: DrawRenderPass, passB: DrawRenderPass) -> Bool {
        let descriptorA = passA.renderTargetDescriptor
        let descriptorB = passB.renderTargetDescriptor
        
        if let depthA = descriptorA.depthAttachment, let depthB = descriptorB.depthAttachment, depthA.texture != depthB.texture || passB.depthClearOperation.isClear  {
            return false
        }
        
        if let stencilA = descriptorA.stencilAttachment, let stencilB = descriptorB.stencilAttachment, stencilA.texture != stencilB.texture || passB.stencilClearOperation.isClear {
            return false
        }
        
        if let visA = descriptorA.visibilityResultBuffer, let visB = descriptorB.visibilityResultBuffer, visA != visB {
            return false
        }
        
        for i in 0..<min(descriptorA.colorAttachments.count, descriptorB.colorAttachments.count) {
            if let colorA = descriptorA.colorAttachments[i], let colorB = descriptorB.colorAttachments[i], colorA.texture != colorB.texture || passB.colorClearOperation(attachmentIndex: i).isClear {
                return false
            }
        }
        
        return descriptorA.size == descriptorB.size
    }
}
