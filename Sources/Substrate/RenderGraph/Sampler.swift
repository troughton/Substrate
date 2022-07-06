//
//  Sampler.swift
//  Substrate
//
//  Created by Thomas Roughton on 7/04/17.
//
//

public enum SamplerMinMagFilter : UInt, Hashable, Codable, Sendable {
    
    case nearest
    
    case linear
}

public enum SamplerMipFilter : UInt, Hashable, Codable, Sendable {
    
    case notMipmapped
    
    case nearest
    
    case linear
}

public enum SamplerAddressMode : UInt, Hashable, Codable, Sendable {
    /// Clamp texture coordinates between 0 and 1 and repeat the edge value outside of that range.
    case clampToEdge
    
    /// Mirror the texture while coordinates are within -1...1, and clamp to edge when outside.
    @available(OSX 10.11, *)
    case mirrorClampToEdge
    
    /// Wrap to the other side of the texture when texture coordinates are outside 0...1.
    case `repeat`
    
    /// The texture is mirrored between -1 and 1 across 0, and repeated outside of that range.
    case mirrorRepeat
    
    /// Clamp texture coordinates between 0 and 1 and repeat opaque zero (0, 0, 0, 1) for images
    /// without an alpha channel or translucent zero (0, 0, 0, 0) for images with an alpha channel outside of that range.
    case clampToZero
    
    /// Clamp texture coordinates between 0 and 1 and repeat the sampler border color outside of that range.
    @available(OSX 10.12, *)
    case clampToBorderColor
}

public enum SamplerBorderColor : UInt, Hashable, Codable, Sendable {
    case transparentBlack
    case opaqueBlack
    case opaqueWhite
}

public struct SamplerDescriptor : Hashable, Codable, Sendable {
    
    public init() {}
    
    public init(filter: SamplerMinMagFilter = .nearest, mipFilter: SamplerMipFilter = .notMipmapped, addressMode: SamplerAddressMode = .clampToEdge) {
        self.init()
        self.minFilter = filter
        self.magFilter = filter
        self.mipFilter = mipFilter
        self.sAddressMode = addressMode
        self.tAddressMode = addressMode
        self.rAddressMode = addressMode
    }
    
    public var minFilter: SamplerMinMagFilter = .nearest
    
    public var magFilter: SamplerMinMagFilter = .nearest
    
    public var mipFilter: SamplerMipFilter = .notMipmapped
    
    public var maxAnisotropy: Int = 1
    
    public var sAddressMode: SamplerAddressMode = .clampToEdge
    
    public var tAddressMode: SamplerAddressMode = .clampToEdge
    
    public var rAddressMode: SamplerAddressMode = .clampToEdge
    
    public var borderColor: SamplerBorderColor = .opaqueBlack
    
    public var normalizedCoordinates: Bool = true
    
    public var lodMinClamp: Float = 0.0
    
    public var lodMaxClamp: Float = Float.greatestFiniteMagnitude
    
    public var compareFunction: CompareFunction = .never
}

public final class SamplerState {
    public let descriptor: SamplerDescriptor
    public let state: OpaquePointer
    
    init(descriptor: SamplerDescriptor, state: OpaquePointer) {
        self.descriptor = descriptor
        self.state = state
    }
}
