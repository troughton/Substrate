//
//  utils.swift
//  org.SwiftGFX.SwiftMath
//
//  Created by Andrey Volodin on 29.09.16.
//
//

import RealModule

extension UInt {
    
    /** returns the Next Power of Two value.
     
     Examples:
     - If "value" is 15, it will return 16.
     - If "value" is 16, it will return 16.
     - If "value" is 17, it will return 32.
     */
    @inlinable
    public var nextPOT: UInt {
        var x = self &- 1
        x = x | (x &>> 1) as UInt
        x = x | (x &>> 2) as UInt
        x = x | (x &>> 4) as UInt
        x = x | (x &>> 8) as UInt
        x = x | (x &>> 16) as UInt
        return x &+ 1
    }
}

extension Float {
    @inlinable
    public init(half: UInt16) {
        let magic = Float(bitPattern: (113 << 23) as UInt32)
        let shifted_exp : UInt32 = UInt32(0x7c00) << UInt32(13); // exponent mask after shift
        
        var o : UInt32 = 0
        o = UInt32(half & UInt16(0x7fff)) << UInt32(13);     // exponent/mantissa bits
        
        let exp : UInt32 = shifted_exp & o   // just the exponent
        o += UInt32(127 - 15) << UInt32(23);        // exponent adjust
        
        // handle exponent special cases
        if (exp == shifted_exp) { // Inf/NaN?
            o += UInt32(128 - 16) &<< UInt32(23);    // extra exp adjust
        } else if (exp == 0) { // Zero/Denormal?
            o += UInt32(1) &<< UInt32(23)             // extra exp adjust
            
            var oFloat = Float(bitPattern: o)
            oFloat -= magic;             // renormalize
            o = oFloat.bitPattern
        }
        
        o |= UInt32(half & 0x8000) &<< UInt32(16);    // sign bit
        
        self = Float(bitPattern: o)
    }
}

/// Flips the y (since in uvs y increases down, while for cubemaps it increases up.
@inlinable
public func cubeMapUVToDirection<Scalar: BinaryFloatingPoint>(uv: SIMD2<Scalar>, face: Int) -> SIMD3<Scalar> {
    let scaledUV = SIMD2<Scalar>(1, -1).addingProduct(uv, SIMD2<Scalar>(2, -2))
    
    switch face {
    case 0:
        return normalize(SIMD3<Scalar>(1, scaledUV.y, -scaledUV.x))
    case 1:
        return normalize(SIMD3<Scalar>(-1, scaledUV.y, scaledUV.x))
    case 2:
        return normalize(SIMD3<Scalar>(scaledUV.x, 1, -scaledUV.y))
    case 3:
        return normalize(SIMD3<Scalar>(scaledUV.x, -1, scaledUV.y))
    case 4:
        return normalize(SIMD3<Scalar>(scaledUV.x, scaledUV.y, 1))
    case 5:
        return normalize(SIMD3<Scalar>(-scaledUV.x, scaledUV.y, -1))
    default:
        preconditionFailure("Invalid cubemap face index.")
    }
}
