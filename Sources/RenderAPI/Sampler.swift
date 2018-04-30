//
//  Sampler.swift
//  InterdimensionalLlama
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
 
 @constant SamplerAddressModeMirrorClampToEdge
 
 @constant SamplerAddressModeRepeat
 
 
 @constant SamplerAddressModeMirrorRepeat
 
 @constant SamplerAddressModeClampToZero
 ClampToZero returns transparent zero (0,0,0,0) for images with an alpha channel, and returns opaque zero (0,0,0,1) for images without an alpha channel.
 */
public enum SamplerAddressMode : UInt {
    /// Texture coordinates will be clamped between 0 and 1.
    case clampToEdge
    
    /// Mirror the texture while coordinates are within -1..1, and clamp to edge when outside.
    @available(OSX 10.11, *)
    case mirrorClampToEdge
    
    /// Wrap to the other side of the texture, effectively ignoring integral parts of the texture coordinate.
    case `repeat`
    
    /// Between -1 and 1 the texture is mirrored across the 0 axis.  The image is repeated outside of that range.
    case mirrorRepeat
    
    /// When sampling outside of a texture, zero is returned.
    case clampToZero
    
    /// When sampling outside of a texture, the border color specified on the sampler descriptor is used.
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
    
    /// Filter option for combining texels within a mipmap level the sample footprint is larger than a pixel (minification).
    public var minFilter: SamplerMinMagFilter = .nearest
    
    
    /// Filter option for combining texels within a mipmap level the sample footprint is smaller than a pixel (magnification).
    public var magFilter: SamplerMinMagFilter = .nearest
    
    /// Filter options for filtering between two mipmap levels.
    public var mipFilter: SamplerMipFilter = .notMipmapped
    
    /// The number of samples that can be taken to improve quality of sample footprints that are anisotropic.
    public var maxAnisotropy: Int = 1
    
    /// Sets the wrap mode for the S texture coordinate.
    public var sAddressMode: SamplerAddressMode = .clampToEdge
    
    /// Sets the wrap mode for the T texture coordinate.
    public var tAddressMode: SamplerAddressMode = .clampToEdge

    /// Sets the wrap mode for the R texture coordinate.
    public var rAddressMode: SamplerAddressMode = .clampToEdge
    
    /// Sets the border color for when the address mode is set to clampToBorderColor.
    public var borderColor: SamplerBorderColor = .opaqueBlack
    
    /// Whether the coordinates are normalized (zero to one) or in the range 0...width, 0...height
    public var normalizedCoordinates: Bool = true
    
    /// The minimum level of detail that will be used when sampling from a texture.
    public var lodMinClamp: Float = 0.0
    
    /// The maximum level of detail that will be used when sampling from a texture.
    public var lodMaxClamp: Float = Float.greatestFiniteMagnitude
    
    /// Sets the comparison function used when sampling shadow maps.
    public var compareFunction: CompareFunction = .never
}
