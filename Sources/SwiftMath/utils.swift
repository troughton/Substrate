//
//  utils.swift
//  org.SwiftGFX.SwiftMath
//
//  Created by Andrey Volodin on 29.09.16.
//
//

import Foundation

extension UInt {
    
    /** returns the Next Power of Two value.
     
     Examples:
     - If "value" is 15, it will return 16.
     - If "value" is 16, it will return 16.
     - If "value" is 17, it will return 32.
     */
    public var nextPOT: UInt {
        var x = self - 1
        x = x | (x >> 1)
        x = x | (x >> 2)
        x = x | (x >> 4)
        x = x | (x >> 8)
        x = x | (x >> 16)
        return x + 1
    }
}

extension Float {
    
    public init(half: UInt16) {
        let magic = Float(bitPattern: 113 << 23)
        let shifted_exp : UInt32 = 0x7c00 << 13; // exponent mask after shift
        
        var o : UInt32 = 0
        
        o = UInt32(half & 0x7fff) << 13;     // exponent/mantissa bits
        
        let exp : UInt32 = shifted_exp & o   // just the exponent
        o += UInt32((127 - 15) << 23);        // exponent adjust
        
        // handle exponent special cases
        if (exp == shifted_exp) { // Inf/NaN?
            o += UInt32((128 - 16) << 23);    // extra exp adjust
        } else if (exp == 0) { // Zero/Denormal?
        
            o += UInt32(1 << 23);             // extra exp adjust
            
            var oFloat = Float(bitPattern: o)
            oFloat -= magic;             // renormalize
            o = oFloat.bitPattern
        }
        
        o |= UInt32(half & 0x8000) << 16;    // sign bit
        
        self = Float(bitPattern: o)
    }
}

/// Flips the y (since in uvs y increases down, while for cubemaps it increases up.
public func cubeMapUVToDirection(uv: Vector2f, face: Int) -> Vector3f {
    let scaledUV = (uv - Vector2f(0.5)) * Vector2f(2, -2)
    
    switch face {
    case 0:
        return Vector3f(1, scaledUV.y, -scaledUV.x).normalized;
    case 1:
        return Vector3f(-1, scaledUV.y, scaledUV.x).normalized;
    case 2:
        return Vector3f(scaledUV.x, 1, -scaledUV.y).normalized;
    case 3:
        return Vector3f(scaledUV.x, -1, scaledUV.y).normalized;
    case 4:
        return Vector3f(scaledUV.x, scaledUV.y, 1).normalized;
    case 5:
        return Vector3f(-scaledUV.x, scaledUV.y, -1).normalized;
    default:
        fatalError("Invalid cubemap face index.")
    }
}
