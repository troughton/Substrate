//
//  ColorSpaceLUTs.swift
//  
//
//  Created by Thomas Roughton on 4/09/20.
//

import Foundation

enum ColorSpaceLUTs {
    private static let srgbToLinearFloatLUT: [UInt32] = [0x00000000,0x399f22b4,0x3a1f22b4,0x3a6eb40e,0x3a9f22b4,0x3ac6eb61,0x3aeeb40e,0x3b0b3e5d,
                                                0x3b1f22b4,0x3b33070b,0x3b46eb61,0x3b5b518d,0x3b70f18d,0x3b83e1c6,0x3b8fe616,0x3b9c87fd,
                                                0x3ba9c9b7,0x3bb7ad6f,0x3bc63549,0x3bd56361,0x3be539c1,0x3bf5ba70,0x3c0373b5,0x3c0c6152,
                                                0x3c15a703,0x3c1f45be,0x3c293e6b,0x3c3391f7,0x3c3e4149,0x3c494d43,0x3c54b6c7,0x3c607eb1,
                                                0x3c6ca5df,0x3c792d22,0x3c830aa8,0x3c89af9f,0x3c9085db,0x3c978dc5,0x3c9ec7c2,0x3ca63433,
                                                0x3cadd37d,0x3cb5a601,0x3cbdac20,0x3cc5e639,0x3cce54ab,0x3cd6f7d5,0x3cdfd010,0x3ce8ddb9,
                                                0x3cf2212c,0x3cfb9ac1,0x3d02a569,0x3d0798dc,0x3d0ca7e6,0x3d11d2af,0x3d171963,0x3d1c7c2e,
                                                0x3d21fb3c,0x3d2796b2,0x3d2d4ebb,0x3d332380,0x3d39152b,0x3d3f23e3,0x3d454fd1,0x3d4b991c,
                                                0x3d51ffef,0x3d58846a,0x3d5f26b7,0x3d65e6fe,0x3d6cc564,0x3d73c20f,0x3d7add29,0x3d810b67,
                                                0x3d84b795,0x3d887330,0x3d8c3e4a,0x3d9018f6,0x3d940345,0x3d97fd4a,0x3d9c0716,0x3da020bb,
                                                0x3da44a4b,0x3da883d7,0x3daccd70,0x3db12728,0x3db59112,0x3dba0b3b,0x3dbe95b5,0x3dc33092,
                                                0x3dc7dbe2,0x3dcc97b6,0x3dd1641f,0x3dd6412c,0x3ddb2eef,0x3de02d77,0x3de53cd5,0x3dea5d19,
                                                0x3def8e52,0x3df4d091,0x3dfa23e8,0x3dff8861,0x3e027f07,0x3e054280,0x3e080ea3,0x3e0ae378,
                                                0x3e0dc105,0x3e10a754,0x3e13966b,0x3e168e52,0x3e198f10,0x3e1c98ad,0x3e1fab30,0x3e22c6a3,
                                                0x3e25eb09,0x3e29186c,0x3e2c4ed0,0x3e2f8e41,0x3e32d6c4,0x3e362861,0x3e39831e,0x3e3ce703,
                                                0x3e405416,0x3e43ca5f,0x3e4749e4,0x3e4ad2ae,0x3e4e64c2,0x3e520027,0x3e55a4e6,0x3e595303,
                                                0x3e5d0a8b,0x3e60cb7c,0x3e6495e0,0x3e6869bf,0x3e6c4720,0x3e702e0c,0x3e741e84,0x3e781890,
                                                0x3e7c1c38,0x3e8014c2,0x3e82203c,0x3e84308d,0x3e8645ba,0x3e885fc5,0x3e8a7eb2,0x3e8ca283,
                                                0x3e8ecb3d,0x3e90f8e1,0x3e932b74,0x3e9562f8,0x3e979f71,0x3e99e0e2,0x3e9c274e,0x3e9e72b7,
                                                0x3ea0c322,0x3ea31892,0x3ea57308,0x3ea7d289,0x3eaa3718,0x3eaca0b7,0x3eaf0f69,0x3eb18333,
                                                0x3eb3fc18,0x3eb67a18,0x3eb8fd37,0x3ebb8579,0x3ebe12e1,0x3ec0a571,0x3ec33d2d,0x3ec5da17,
                                                0x3ec87c33,0x3ecb2383,0x3ecdd00b,0x3ed081cd,0x3ed338cc,0x3ed5f50b,0x3ed8b68d,0x3edb7d54,
                                                0x3ede4965,0x3ee11ac1,0x3ee3f16b,0x3ee6cd67,0x3ee9aeb6,0x3eec955d,0x3eef815d,0x3ef272ba,
                                                0x3ef56976,0x3ef86594,0x3efb6717,0x3efe6e02,0x3f00bd2d,0x3f02460e,0x3f03d1a7,0x3f055ff9,
                                                0x3f06f106,0x3f0884cf,0x3f0a1b56,0x3f0bb49b,0x3f0d50a0,0x3f0eef67,0x3f1090f1,0x3f12353e,
                                                0x3f13dc51,0x3f15862b,0x3f1732cd,0x3f18e239,0x3f1a946f,0x3f1c4971,0x3f1e0141,0x3f1fbbdf,
                                                0x3f21794e,0x3f23398e,0x3f24fca0,0x3f26c286,0x3f288b41,0x3f2a56d3,0x3f2c253d,0x3f2df680,
                                                0x3f2fca9e,0x3f31a197,0x3f337b6c,0x3f355820,0x3f3737b3,0x3f391a26,0x3f3aff7c,0x3f3ce7b5,
                                                0x3f3ed2d2,0x3f40c0d4,0x3f42b1be,0x3f44a590,0x3f469c4b,0x3f4895f1,0x3f4a9282,0x3f4c9201,
                                                0x3f4e946e,0x3f5099cb,0x3f52a218,0x3f54ad57,0x3f56bb8a,0x3f58ccb0,0x3f5ae0cd,0x3f5cf7e0,
                                                0x3f5f11ec,0x3f612eee,0x3f634eef,0x3f6571e9,0x3f6797e3,0x3f69c0d6,0x3f6beccd,0x3f6e1bbf,
                                                0x3f704db8,0x3f7282af,0x3f74baae,0x3f76f5ae,0x3f7933b9,0x3f7b74c6,0x3f7db8e0,0x3f800000]
    
    @inlinable @inline(__always)
    static func srgbToLinearFloat(_ value: UInt8) -> Float {
        return Float(bitPattern: srgbToLinearFloatLUT[Int(value)])
    }
    
    static let linearToSRGBLUT: [UInt8] = {
        return (0...UInt8.max).map { return floatToUnorm(ImageColorSpace.convert(unormToFloat($0), from: .linearSRGB, to: .sRGB), type: UInt8.self) }
    }()
    
    @inlinable @inline(__always)
    static func linearToSRGB(_ value: UInt8) -> UInt8 {
        return linearToSRGBLUT[Int(value)]
    }
    
    static let sRGBToLinearLUT: [UInt8] = {
        return (0...UInt8.max).map { return floatToUnorm(srgbToLinearFloat($0), type: UInt8.self) }
    }()
    
    @inlinable @inline(__always)
    static func sRGBToLinear(_ value: UInt8) -> UInt8 {
        return sRGBToLinearLUT[Int(value)]
    }

    static let premultToPostmultAlphaLUT: [UInt8] = {
        return (0..<256 * 256).map { i in
            let alphaByte = UInt8(truncatingIfNeeded: i >> 8)
            let alpha = unormToFloat(alphaByte)
            let value = UInt8(truncatingIfNeeded: i & 0xFF)
            
            if alphaByte == 0 {
                return value
            }
            
            let floatVal = unormToFloat(value)
            let linearVal = clamp(floatVal / alpha, min: 0.0, max: 1.0)
            return floatToUnorm(linearVal, type: UInt8.self)
        }
    }()
    
    @inlinable @inline(__always)
    static func premultToPostmult(value: UInt8, alpha: UInt8) -> UInt8 {
        return premultToPostmultAlphaLUT[Int(alpha) * 256 + Int(value)]
    }
    
    static let postmultToPremultAlphaLUT: [UInt8] = {
        return (0..<256 * 256).map { i in
            let alpha = unormToFloat(UInt8(truncatingIfNeeded: i >> 8))
            let value = UInt8(truncatingIfNeeded: i & 0xFF)
            
            let floatVal = unormToFloat(value)
            let linearVal = floatVal * alpha
            return floatToUnorm(linearVal, type: UInt8.self)
        }
    }()
    
    @inlinable @inline(__always)
    static func postmultToPremult(value: UInt8, alpha: UInt8) -> UInt8 {
        return postmultToPremultAlphaLUT[Int(alpha) * 256 + Int(value)]
    }
    
    static let sRGBPremultToPostmultAlphaLUT: [UInt8] = {
        return (0..<256 * 256).map { i in
            let alphaByte = UInt8(truncatingIfNeeded: i >> 8)
            let alpha = unormToFloat(alphaByte)
            let value = UInt8(truncatingIfNeeded: i & 0xFF)
            
            if alphaByte == 0 {
                return value
            }
            
            let floatVal = unormToFloat(value)
            let linearVal = clamp(ImageColorSpace.convert(floatVal, from: .sRGB, to: .linearSRGB) / alpha, min: 0.0, max: 1.0)
            return floatToUnorm(ImageColorSpace.convert(linearVal, from: .linearSRGB, to: .sRGB), type: UInt8.self)
        }
    }()
    
    @inlinable @inline(__always)
    static func sRGBPremultToPostmult(value: UInt8, alpha: UInt8) -> UInt8 {
        return sRGBPremultToPostmultAlphaLUT[Int(alpha) * 256 + Int(value)]
    }
    
    static let sRGBPostmultToPremultAlphaLUT: [UInt8] = {
        return (0..<256 * 256).map { i in
            let alpha = unormToFloat(UInt8(truncatingIfNeeded: i >> 8))
            let value = UInt8(truncatingIfNeeded: i & 0xFF)
            
            let floatVal = unormToFloat(value)
            let linearVal = ImageColorSpace.convert(floatVal, from: .sRGB, to: .linearSRGB) * alpha
            return floatToUnorm(ImageColorSpace.convert(linearVal, from: .linearSRGB, to: .sRGB), type: UInt8.self)
        }
    }()
    
    @inlinable @inline(__always)
    static func sRGBPostmultToPremult(value: UInt8, alpha: UInt8) -> UInt8 {
        return sRGBPostmultToPremultAlphaLUT[Int(alpha) * 256 + Int(value)]
    }
    
    // See TextureData.convertPremultLinearBlendedSRGBToPostmultSRGBBlendedSRGB
    static let linearBlendedSRGBToSRGBBlendedSRGB_AlphaLUT: [UInt8] = {
        return (0..<256).map { i in
            let alpha = unormToFloat(UInt8(truncatingIfNeeded: i))
            let adjustedAlpha = 1.0 - ImageColorSpace.convert(1.0 - alpha, from: .linearSRGB, to: .sRGB)
            return floatToUnorm(adjustedAlpha, type: UInt8.self)
        }
    }()
    
    // Converts from a premultiplied alpha RGB value in sRGB space to a postmultiplied alpha RGB value in sRGB space that is designed
    // to be blended in sRGB space while preserving the appearance of blending in linear space.
    // See TextureData.adjustForSRGBSpaceBlending
    static let premultLinearBlendedSRGBToPostmultSRGBBlendedSRGB_ColorLUT: [UInt8] = {
        return (0..<256 * 256).map { i in
            let alpha = unormToFloat(UInt8(truncatingIfNeeded: i >> 8))
            let value = UInt8(truncatingIfNeeded: i & 0xFF)
            guard alpha > 0 && alpha < 1.0 else { return value }
            
            let adjustedAlpha = 1.0 - ImageColorSpace.convert(1.0 - alpha, from: .linearSRGB, to: .sRGB)
            
            let premultColor = unormToFloat(value)
            let adjustedColor = (ImageColorSpace.convert((1.0 - alpha) + ImageColorSpace.convert(premultColor, from: .sRGB, to: .linearSRGB), from: .linearSRGB, to: .sRGB) - (1.0 - adjustedAlpha)) / adjustedAlpha
            return floatToUnorm(adjustedColor, type: UInt8.self)
        }
    }()
    
    @inlinable @inline(__always)
    static func linearBlendedSRGBToSRGBBlendedSRGB(alpha: UInt8) -> UInt8 {
        return linearBlendedSRGBToSRGBBlendedSRGB_AlphaLUT[Int(alpha)]
    }
    
    @inlinable @inline(__always)
    static func premultLinearBlendedSRGBToPostmultSRGBBlendedSRGB(alpha: UInt8, value: UInt8) -> UInt8 {
        return premultLinearBlendedSRGBToPostmultSRGBBlendedSRGB_ColorLUT[Int(alpha) * 256 + Int(value)]
    }
    
    // The inverse of linearBlendedSRGBToSRGBBlendedSRGB_AlphaLUT
    // See TextureData.adjustForLinearSpaceBlending
    static let sRGBBlendedSRGBToLinearBlendedSRGB_AlphaLUT: [UInt8] = {
        return (0..<256).map { i in
            let adjustedAlpha = unormToFloat(UInt8(truncatingIfNeeded: i))
            let alpha = 1.0 - ImageColorSpace.convert(1.0 - adjustedAlpha, from: .sRGB, to: .linearSRGB)
            return floatToUnorm(alpha, type: UInt8.self)
        }
    }()
    
    // Converts from a postmultiplied alpha RGB value in sRGB space that was designed to be blended in
    // sRGB space to a premultiplied alpha RGB value in sRGB space that is designed
    // to be blended in linear space.
    // See TextureData.convertPostmultSRGBBlendedSRGBToPremultLinearBlendedSRGB
    static let postmultSRGBBlendedSRGBToPremultLinearBlendedSRGB_ColorLUT: [UInt8] = {
        return (0..<256 * 256).map { i in
            let adjustedAlpha = unormToFloat(UInt8(truncatingIfNeeded: i >> 8))
            let value = UInt8(truncatingIfNeeded: i & 0xFF)
            guard adjustedAlpha > 0 && adjustedAlpha < 1.0 else { return value }
            
            let alpha = 1.0 - ImageColorSpace.convert(1.0 - adjustedAlpha, from: .sRGB, to: .linearSRGB)
            
            let srgbBlendColor = unormToFloat(value)
            let premultColor = ImageColorSpace.convert((ImageColorSpace.convert(srgbBlendColor * adjustedAlpha + (1.0 - adjustedAlpha), from: .sRGB, to: .linearSRGB) - (1.0 - alpha)), from: .linearSRGB, to: .sRGB)
            
            return floatToUnorm(premultColor, type: UInt8.self)
        }
    }()
    
    @inlinable @inline(__always)
    static func sRGBBlendedSRGBToLinearBlendedSRGB(alpha: UInt8) -> UInt8 {
        return sRGBBlendedSRGBToLinearBlendedSRGB_AlphaLUT[Int(alpha)]
    }
    
    @inlinable @inline(__always)
    static func postmultSRGBBlendedSRGBToPremultLinearBlendedSRGB(alpha: UInt8, value: UInt8) -> UInt8 {
        return postmultSRGBBlendedSRGBToPremultLinearBlendedSRGB_ColorLUT[Int(alpha) * 256 + Int(value)]
    }
    
    // Converts from a premultiplied alpha RGB value that is designed to be blended in sRGB space
    // to a premultiplied alpha RGB value in sRGB space that is designed to be blended in linear space.
    static let premultSRGBBlendedSRGBToPremultLinearBlendedSRGB_ColorLUT: [UInt8] = {
        return (0..<256 * 256).map { i in
            let alpha = unormToFloat(UInt8(truncatingIfNeeded: i >> 8))
            let value = UInt8(truncatingIfNeeded: i & 0xFF)
            guard alpha > 0 && alpha < 1.0 else { return value }
            
            let floatVal = unormToFloat(value)
            let postMultFloatVal = clamp(floatVal / alpha, min: 0.0, max: 1.0)
            let linearVal = ImageColorSpace.convert(postMultFloatVal, from: .sRGB, to: .linearSRGB) * alpha
            return floatToUnorm(ImageColorSpace.convert(linearVal, from: .linearSRGB, to: .sRGB), type: UInt8.self)
        }
    }()
    
    @inlinable @inline(__always)
    static func premultSRGBBlendedSRGBToPremultLinearBlendedSRGB(alpha: UInt8, value: UInt8) -> UInt8 {
        return premultSRGBBlendedSRGBToPremultLinearBlendedSRGB_ColorLUT[Int(alpha) * 256 + Int(value)]
    }
}
