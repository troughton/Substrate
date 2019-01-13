//
//  Sampler.swift
//  SwiftFrameGraph
//
//  Created by Thomas Roughton on 7/04/17.
//
//

public enum SamplerMinMagFilter : UInt {
    
    case nearest
    
    case linear
}

public enum SamplerMipFilter : UInt {
    
    case notMipmapped
    
    case nearest
    
    case linear
}

/*!
 @enum SamplerAddressMode
 @abstract Options for what value is returned when a fetch falls outside the bounds of a texture.
 
 @constant SamplerAddressModeClampToEdge
 Texture coordinates will be clamped between 0 and 1.
 
 @constant SamplerAddressModeMirrorClampToEdge
 Mirror the texture while coordinates are within -1..1, and clamp to edge when outside.
 
 @constant SamplerAddressModeRepeat
 Wrap to the other side of the texture, effectively ignoring fractional parts of the texture coordinate.
 
 @constant SamplerAddressModeMirrorRepeat
 Between -1 and 1 the texture is mirrored across the 0 axis.  The image is repeated outside of that range.
 
 @constant SamplerAddressModeClampToZero
 ClampToZero returns transparent zero (0,0,0,0) for images with an alpha channel, and returns opaque zero (0,0,0,1) for images without an alpha channel.
 */
public enum SamplerAddressMode : UInt {
    /// Texture coordinates will be clamped between 0 and 1, and the edge value will be repeated outside that range.
    case clampToEdge
    
    ///  Mirror the texture while coordinates are within -1..1, and clamp to edge when outside.
    @available(OSX 10.11, *)
    case mirrorClampToEdge
    
    /// Wrap to the other side of the texture, effectively ignoring integral parts of the texture coordinate.
    case `repeat`
    
    /// Between -1 and 1 the texture is mirrored across the 0 axis.  The image is repeated outside of that range.
    case mirrorRepeat
    
    /// Texture coordinates will be clamped between 0 and 1, and zero will be repeated outside that range.
    case clampToZero
    
    /// Texture coordinates will be clamped between 0 and 1, and the border color set on the sampler will be repeated outside that range.
    @available(OSX 10.12, *)
    case clampToBorderColor
}

public enum SamplerBorderColor : UInt {
    
    
    case transparentBlack // {0,0,0,0}
    
    case opaqueBlack // {0,0,0,1}
    
    case opaqueWhite // {1,1,1,1}
}

public struct SamplerDescriptor : Hashable {
    
    public init() {
        
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
