//
//  RenderTargetDescriptor.swift
//  Substrate
//
//  Created by Thomas Roughton on 2/04/17.
//
//

import SubstrateUtilities

public protocol RenderTargetAttachmentDescriptor {
    var texture: Texture { get set }
    
    /// The mipmap level of the texture to be used for rendering.
    var level: Int { get set }
    
    /// The slice of the texture to be used for rendering.
    var slice: Int { get set }
    
    /// The depth plane of the texture to be used for rendering.
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

// Since none of the level/slice/depth plane values are allowed to exceed UInt16.max, we can reduce the storage requirements.
protocol _RenderTargetAttachmentDescriptor: RenderTargetAttachmentDescriptor {
    var _level: UInt16 { get set }
    
    var _slice: UInt16 { get set }
    
    var _depthPlane: UInt16 { get set }
    
    /// _The mipmap level of the resolve texture to resolve to.
    var _resolveLevel : UInt16 { get set }
    
    /// _The slice of the resolve texture to resolve to.
    var _resolveSlice : UInt16 { get set }
    
    /// _The depth plane of the resolve texture to resolve to.
    var _resolveDepthPlane : UInt16 { get set }
}

extension _RenderTargetAttachmentDescriptor {
    @inlinable
    public var level: Int {
        get {
            return Int(self._level)
        }
        set {
            self._level = UInt16(newValue)
        }
    }
    
    @inlinable
    public var slice: Int {
        get {
            return Int(self._slice)
        }
        set {
            self._slice = UInt16(newValue)
        }
    }
    
    @inlinable
    public var depthPlane: Int {
        get {
            return Int(self._depthPlane)
        }
        set {
            self._depthPlane = UInt16(newValue)
        }
    }
    
    @inlinable
    public var resolveLevel: Int {
        get {
            return Int(self._resolveLevel)
        }
        set {
            self._resolveLevel = UInt16(newValue)
        }
    }
    
    @inlinable
    public var resolveSlice: Int {
        get {
            return Int(self._resolveSlice)
        }
        set {
            self._resolveSlice = UInt16(newValue)
        }
    }
    
    @inlinable
    public var resolveDepthPlane: Int {
        get {
            return Int(self._resolveDepthPlane)
        }
        set {
            self._resolveDepthPlane = UInt16(newValue)
        }
    }
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

public struct ColorAttachmentDescriptor : RenderTargetAttachmentDescriptor, _RenderTargetAttachmentDescriptor, Hashable, Sendable {
    public var texture: Texture
    
    /// The texture to perform a multisample resolve action on at the completion of the render pass.
    public var resolveTexture : Texture? = nil
    
    @usableFromInline var _level: UInt16
    @usableFromInline var _slice: UInt16
    @usableFromInline var _depthPlane: UInt16
    @usableFromInline var _resolveLevel : UInt16
    @usableFromInline var _resolveSlice : UInt16
    @usableFromInline var _resolveDepthPlane : UInt16
    
    @inlinable
    public init(texture: Texture, level: Int = 0, slice: Int = 0, depthPlane: Int = 0,
                resolveTexture: Texture? = nil, resolveLevel: Int = 0, resolveSlice: Int = 0, resolveDepthPlane: Int = 0) {
        self.texture = texture
        self.resolveTexture = resolveTexture
        self._level = UInt16(level)
        self._slice = UInt16(slice)
        self._depthPlane = UInt16(depthPlane)
        self._resolveLevel = UInt16(resolveLevel)
        self._resolveSlice = UInt16(resolveSlice)
        self._resolveDepthPlane = UInt16(resolveDepthPlane)
    }
}

public struct DepthAttachmentDescriptor : RenderTargetAttachmentDescriptor, _RenderTargetAttachmentDescriptor, Hashable, Sendable {
    public var texture: Texture
    
    /// The texture to perform a multisample resolve action on at the completion of the render pass.
    public var resolveTexture : Texture? = nil
    
    @usableFromInline var _level: UInt16
    @usableFromInline var _slice: UInt16
    @usableFromInline var _depthPlane: UInt16
    @usableFromInline var _resolveLevel : UInt16
    @usableFromInline var _resolveSlice : UInt16
    @usableFromInline var _resolveDepthPlane : UInt16
    
    @inlinable
    public init(texture: Texture, level: Int = 0, slice: Int = 0, depthPlane: Int = 0,
                resolveTexture: Texture? = nil, resolveLevel: Int = 0, resolveSlice: Int = 0, resolveDepthPlane: Int = 0) {
        self.texture = texture
        self.resolveTexture = resolveTexture
        self._level = UInt16(level)
        self._slice = UInt16(slice)
        self._depthPlane = UInt16(depthPlane)
        self._resolveLevel = UInt16(resolveLevel)
        self._resolveSlice = UInt16(resolveSlice)
        self._resolveDepthPlane = UInt16(resolveDepthPlane)
    }
}

public struct StencilAttachmentDescriptor : RenderTargetAttachmentDescriptor, _RenderTargetAttachmentDescriptor, Hashable, Sendable {
    public var texture: Texture
    
    /// The texture to perform a multisample resolve action on at the completion of the render pass.
    public var resolveTexture : Texture? = nil
    
    @usableFromInline var _level: UInt16
    @usableFromInline var _slice: UInt16
    @usableFromInline var _depthPlane: UInt16
    @usableFromInline var _resolveLevel : UInt16
    @usableFromInline var _resolveSlice : UInt16
    @usableFromInline var _resolveDepthPlane : UInt16
    
    @inlinable
    public init(texture: Texture, level: Int = 0, slice: Int = 0, depthPlane: Int = 0,
                resolveTexture: Texture? = nil, resolveLevel: Int = 0, resolveSlice: Int = 0, resolveDepthPlane: Int = 0) {
        self.texture = texture
        self.resolveTexture = resolveTexture
        self._level = UInt16(level)
        self._slice = UInt16(slice)
        self._depthPlane = UInt16(depthPlane)
        self._resolveLevel = UInt16(resolveLevel)
        self._resolveSlice = UInt16(resolveSlice)
        self._resolveDepthPlane = UInt16(resolveDepthPlane)
    }
}

protocol ClearOperation {
    var isClear: Bool { get }
    var isKeep: Bool { get }
    var isDiscard: Bool { get }
}

public enum ColorClearOperation: ClearOperation, Sendable {
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

public enum DepthClearOperation: ClearOperation, Sendable {
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

public enum StencilClearOperation: ClearOperation, Sendable {
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

// For compatibility with old RenderGraph versions:
public typealias RenderTargetColorAttachmentDescriptor = ColorAttachmentDescriptor
public typealias RenderTargetDepthAttachmentDescriptor = DepthAttachmentDescriptor
public typealias RenderTargetStencilAttachmentDescriptor = StencilAttachmentDescriptor

public typealias ColorAttachmentArray<T> = Array8<T>

public struct RenderTargetDescriptor : Hashable, Sendable {
    public var colorAttachments: ColorAttachmentArray<ColorAttachmentDescriptor?>
    
    public var depthAttachment : DepthAttachmentDescriptor? = nil
    
    public var stencilAttachment : StencilAttachmentDescriptor? = nil
    
    public var visibilityResultBuffer: Buffer? = nil
    
    public var renderTargetArrayLength: Int = 0
    
    @available(*, deprecated, renamed: "init()")
    @inlinable
    public init(attachmentCount: Int) {
        precondition(attachmentCount <= 8, "Up to eight color attachments are supported for a single RenderTargetDescriptor.")
        self.colorAttachments = .init(repeating: nil)
    }
    
    @inlinable
    public init() {
        self.colorAttachments = .init(repeating: nil)
    }
    
    @inlinable
    public init(colorAttachments: [ColorAttachmentDescriptor?] = [], depthAttachment: DepthAttachmentDescriptor? = nil, stencilAttachment: StencilAttachmentDescriptor? = nil) {
        precondition(colorAttachments.count <= 8, "Up to eight color attachments are supported for a single RenderTargetDescriptor.")
        self.colorAttachments = .init({ i in
            i < colorAttachments.count ? colorAttachments[i] : nil
        })
        self.depthAttachment = depthAttachment
        self.stencilAttachment = stencilAttachment
    }
    
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
    
    
    func tryUpdateDescriptor<D : RenderTargetAttachmentDescriptor>(_ desc: inout D?, with new: D?, clearOperation: ClearOperation) -> Bool {
        guard let descriptor = desc else {
            desc = new
            return true
        }
        
        guard let new = new else {
            return true
        }
        
        if clearOperation.isClear {
            // If descriptor was not nil, it must've already had and been using this attachment,
            // so we can't overwrite its load action.
            return false
        }
        
        return  descriptor.texture     == new.texture &&
                descriptor.level       == new.level &&
                descriptor.slice       == new.slice &&
                descriptor.depthPlane  == new.depthPlane
    }
    
    mutating func tryMerge(withPass pass: ProxyDrawRenderPass) -> Bool {
        if pass.renderTargetDescriptor.size != self.size {
            return false // The render targets must be the same size.
        }
        
        let passDescriptor = pass.renderTargetDescriptor
        
        var newDescriptor = self
        
        for i in 0..<min(newDescriptor.colorAttachments.count, passDescriptor.colorAttachments.count) {
            if !self.tryUpdateDescriptor(&newDescriptor.colorAttachments[i], with: passDescriptor.colorAttachments[i], clearOperation: pass.colorClearOperation(attachmentIndex: i)) {
                return false
            }
        }
        
        if !self.tryUpdateDescriptor(&newDescriptor.depthAttachment, with: passDescriptor.depthAttachment, clearOperation: pass.depthClearOperation) {
            return false
        }
        
        if !self.tryUpdateDescriptor(&newDescriptor.stencilAttachment, with: passDescriptor.stencilAttachment, clearOperation: pass.stencilClearOperation) {
            return false
        }
        
        if newDescriptor.visibilityResultBuffer != nil && passDescriptor.visibilityResultBuffer != newDescriptor.visibilityResultBuffer {
            return false
        } else {
            newDescriptor.visibilityResultBuffer = passDescriptor.visibilityResultBuffer
        }
        
        newDescriptor.renderTargetArrayLength = max(newDescriptor.renderTargetArrayLength, passDescriptor.renderTargetArrayLength)
        
        self = newDescriptor
        
        return true
    }
}
