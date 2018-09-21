//
//  Sampler.swift
//  InterdimensionalLlama
//
//  Created by Thomas Roughton on 7/04/17.
//
//

/*!
 @enum SamplerMinMagFilter
 @abstract Options for filtering texels within a mip level.
 
 @constant SamplerMinMagFilterNearest
 Select the single texel nearest to the sample point.
 
 @constant SamplerMinMagFilterLinear
 Select two texels in each dimension, and interpolate linearly between them.  Not all devices support linear filtering for all formats.  Integer textures can not use linear filtering on any device, and only some devices support linear filtering of Float textures.
 */
public enum SamplerMinMagFilter : UInt {
    
    case nearest
    
    case linear
}

/*!
 @enum SamplerMipFilter
 @abstract Options for selecting and filtering between mipmap levels
 @constant SamplerMipFilterNotMipmapped The texture is sampled as if it only had a single mipmap level.  All samples are read from level 0.
 @constant SamplerMipFilterNearest The nearst mipmap level is selected.
 @constant SamplerMipFilterLinear If the filter falls between levels, both levels are sampled, and their results linearly interpolated between levels.
 */
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
    case clampToEdge
    
    @available(OSX 10.11, *)
    case mirrorClampToEdge
    
    case `repeat`
    
    case mirrorRepeat
    
    case clampToZero
    
    /*!
     @constant SamplerAddressModeClampToBorderColor
     Clamp to border color returns the value specified by the borderColor variable of the SamplerDesc.
     */
    @available(OSX 10.12, *)
    case clampToBorderColor
}

/*!
 @enum SamplerBorderColor
 @abstract Specify the color value that will be clamped to when the sampler address mode is SamplerAddressModeClampToBorderColor.
 
 @constant SamplerBorderColorTransparentBlack
 Transparent black returns {0,0,0,1} for clamped texture values.
 
 @constant SamplerBorderColorOpaqueBlack
 OpaqueBlack returns {0,0,0,1} for clamped texture values.
 
 @constant SamplerBorderColorOpaqueWhite
 OpaqueWhite returns {1,1,1,1} for clamped texture values.
 */
public enum SamplerBorderColor : UInt {
    
    
    case transparentBlack // {0,0,0,0}
    
    case opaqueBlack // {0,0,0,1}
    
    case opaqueWhite // {1,1,1,1}
}


/*!
 @class SamplerDescriptor
 @abstract A mutable descriptor used to configure a sampler.  When complete, this can be used to create an immutable SamplerState.
 */
public struct SamplerDescriptor : Hashable {
    
    public init() {
        
    }
    
    /*!
     @property minFilter
     @abstract Filter option for combining texels within a mipmap level the sample footprint is larger than a pixel (minification).
     @discussion The default value is SamplerMinMagFilterNearest.
     */
    public var minFilter: SamplerMinMagFilter = .nearest
    
    
    /*!
     @property magFilter
     @abstract Filter option for combining texels within a mipmap level the sample footprint is smaller than a pixel (magnification).
     @discussion The default value is SamplerMinMagFilterNearest.
     */
    public var magFilter: SamplerMinMagFilter = .nearest
    
    
    /*!
     @property mipFilter
     @abstract Filter options for filtering between two mipmap levels.
     @discussion The default value is SamplerMipFilterNotMipmapped
     */
    public var mipFilter: SamplerMipFilter = .notMipmapped
    
    
    /*!
     @property maxAnisotropy
     @abstract The number of samples that can be taken to improve quality of sample footprints that are anisotropic.
     @discussion The default value is 1.
     */
    public var maxAnisotropy: Int = 1
    
    
    /*!
     @property sAddressMode
     @abstract Set the wrap mode for the S texture coordinate.  The default value is SamplerAddressModeClampToEdge.
     */
    public var sAddressMode: SamplerAddressMode = .clampToEdge
    
    
    /*!
     @property tAddressMode
     @abstract Set the wrap mode for the T texture coordinate.  The default value is SamplerAddressModeClampToEdge.
     */
    public var tAddressMode: SamplerAddressMode = .clampToEdge
    
    
    /*!
     @property rAddressMode
     @abstract Set the wrap mode for the R texture coordinate.  The default value is SamplerAddressModeClampToEdge.
     */
    public var rAddressMode: SamplerAddressMode = .clampToEdge
    
    
    /*!
     @property borderColor
     @abstract Set the color for the SamplerAddressMode to one of the predefined in the SamplerBorderColor enum.
     */
    public var borderColor: SamplerBorderColor = .opaqueBlack
    
    
    /*!
     @property normalizedCoordinates.
     @abstract If YES, texture coordates are from 0 to 1.  If NO, texture coordinates are 0..width, 0..height.
     @discussion normalizedCoordinates defaults to YES.  Non-normalized coordinates should only be used with 1D and 2D textures with the ClampToEdge wrap mode, otherwise the results of sampling are undefined.
     */
    public var normalizedCoordinates: Bool = true
    
    
    /*!
     @property lodMinClamp
     @abstract The minimum level of detail that will be used when sampling from a texture.
     @discussion The default value of lodMinClamp is 0.0.  Clamp values are ignored for texture sample variants that specify an explicit level of detail.
     */
    public var lodMinClamp: Float = 0.0
    
    
    /*!
     @property lodMaxClamp
     @abstract The maximum level of detail that will be used when sampling from a texture.
     @discussion The default value of lodMaxClamp is FLT_MAX.  Clamp values are ignored for texture sample variants that specify an explicit level of detail.
     */
    public var lodMaxClamp: Float = Float.greatestFiniteMagnitude
    
    
    /*!
     @property compareFunction
     @abstract Set the comparison function used when sampling shadow maps. The default value is CompareFunctionNever.
     */
    public var compareFunction: CompareFunction = .never
}
