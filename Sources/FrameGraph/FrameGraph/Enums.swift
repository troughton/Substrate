//
//  PixelFormat.swift
//  CGRA 402
//
//  Created by Thomas Roughton on 10/03/17.
//  Copyright © 2017 Thomas Roughton. All rights reserved.
//

import Swift

public enum BlendFactor : UInt, Hashable {
    
    case zero
    
    case one
    
    case sourceColor
    
    case oneMinusSourceColor
    
    case sourceAlpha
    
    case oneMinusSourceAlpha
    
    case destinationColor
    
    case oneMinusDestinationColor
    
    case destinationAlpha
    
    case oneMinusDestinationAlpha
    
    case sourceAlphaSaturated
    
    case blendColor
    
    case oneMinusBlendColor
    
    case blendAlpha
    
    case oneMinusBlendAlpha
    
    case source1Color
    
    case oneMinusSource1Color
    
    case source1Alpha
    
    case oneMinusSource1Alpha
}

public enum BlendOperation : UInt, Hashable {
    
    case add
    
    case subtract
    
    case reverseSubtract
    
    case min
    
    case max
}

public struct ColorWriteMask : OptionSet, Hashable {
    
    public var rawValue: UInt
    
    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }
    
    public static var red = ColorWriteMask(rawValue: 1)
    
    public static var green = ColorWriteMask(rawValue: 2)
    
    public static var blue = ColorWriteMask(rawValue: 4)
    
    public static var alpha = ColorWriteMask(rawValue: 8)
    
    public static var all : ColorWriteMask = [.red, .green, .blue, .alpha]
}


public enum PixelFormat : UInt, Hashable {
    
    case invalid = 0
    
    /* Normal 8 bit formats */
    case a8Unorm = 1
    
    case r8Unorm = 10
    case r8Unorm_sRGB = 11
    
    case r8Snorm = 12
    case r8Uint = 13
    case r8Sint = 14
    
    /* Normal 16 bit formats */
    case r16Unorm = 20
    case r16Snorm = 22
    case r16Uint = 23
    case r16Sint = 24
    case r16Float = 25
    
    case rg8Unorm = 30
    case rg8Unorm_sRGB = 31
    case rg8Snorm = 32
    case rg8Uint = 33
    case rg8Sint = 34
    
    case b5g6r5Unorm = 40
    case a1bgr5Unorm = 41
    case abgr4Unorm = 42
    case bgr5a1Unorm = 43
    
    /* Normal 32 bit formats */
    case r32Uint = 53
    case r32Sint = 54
    case r32Float = 55
    
    case rg16Unorm = 60
    case rg16Snorm = 62
    case rg16Uint = 63
    case rg16Sint = 64
    case rg16Float = 65
    
    case rgba8Unorm = 70
    case rgba8Unorm_sRGB = 71
    case rgba8Snorm = 72
    case rgba8Uint = 73
    case rgba8Sint = 74
    
    case bgra8Unorm = 80
    case bgra8Unorm_sRGB = 81
    
    /* Packed 32 bit formats */
    case rgb10a2Unorm = 90
    case rgb10a2Uint = 91
    
    case rg11b10Float = 92
    case rgb9e5Float = 93
    case bgr10a2Unorm = 94
    
    case bgr10_xr = 554
    case bgr10_xr_sRGB = 555
    
    /* Normal 64 bit formats */
    case rg32Uint = 103
    case rg32Sint = 104
    case rg32Float = 105
    
    case rgba16Unorm = 110
    case rgba16Snorm = 112
    case rgba16Uint = 113
    case rgba16Sint = 114
    case rgba16Float = 115
    
    case bgra10_xr = 552
    case bgra10_xr_sRGB = 553
    
    /* Normal 128 bit formats */
    case rgba32Uint = 123
    case rgba32Sint = 124
    case rgba32Float = 125
    
    /* Compressed formats. */
    /* S3TC/DXT */
    case bc1_rgba = 130
    case bc1_rgba_sRGB = 131
    case bc2_rgba = 132
    case bc2_rgba_sRGB = 133
    case bc3_rgba = 134
    case bc3_rgba_sRGB = 135
    
    /* RGTC */
    case bc4_rUnorm = 140
    case bc4_rSnorm = 141
    case bc5_rgUnorm = 142
    case bc5_rgSnorm = 143
    
    /* BPTC */
    case bc6H_rgbFloat = 150
    case bc6H_rgbuFloat = 151
    case bc7_rgbaUnorm = 152
    case bc7_rgbaUnorm_sRGB = 153
    

    case gbgr422 = 240
    
    case bgrg422 = 241
    
    /* Depth */

    case depth16Unorm = 250
    case depth32Float = 252
    
    /* Stencil */

    case stencil8 = 253
    
    /* Depth Stencil */

    case depth24Unorm_stencil8 = 255
    case depth32Float_stencil8 = 260

    case x32_stencil8 = 261
    case x24_stencil8 = 262
}

public extension PixelFormat {
    public init?(string: String) {
        for i in 0...PixelFormat.x24_stencil8.rawValue {
            if let format = PixelFormat(rawValue: i) {
                if String(describing: format) == string {
                    self = format
                    return
                }
            }
        }
        return nil
    }

    public var isDepth : Bool {
        switch self {
        case .depth16Unorm, .depth32Float,
             .depth24Unorm_stencil8, .depth32Float_stencil8:
            return true
        default:
            return false
        }
    }
    
    public var isStencil : Bool {
        switch self {
        case .stencil8,
             .depth24Unorm_stencil8, .depth32Float_stencil8,
             .x24_stencil8, .x32_stencil8:
            return true
        default:
            return false
        }
    }
    
    public var isDepthStencil : Bool {
        switch self {
        case .depth24Unorm_stencil8, .depth32Float_stencil8:
            return true
        default:
            return false
        }
    }
}

@available(OSX 10.11, *)
public enum CPUCacheMode : UInt {
    
    
    case defaultCache
    
    case writeCombined
}

public enum StorageMode : UInt {
    case shared
    case managed
    case `private`
}

public struct BlitOption : OptionSet {
    public static let  depthFromDepthStencil = BlitOption(rawValue: 1 << 0)
    public static let  stencilFromDepthStencil = BlitOption(rawValue: 1 << 1)
    
    public let rawValue : UInt
    
    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }
}

public enum PrimitiveType : UInt {
    
    case point
    
    case line
    
    case lineStrip
    
    case triangle
    
    case triangleStrip
}

public enum DataType : UInt {
    
    case none
    
    case `struct`
    case array
    
    case float
    case float2
    case float3
    case float4
    
    case float2x2
    case float2x3
    case float2x4
    
    case float3x2
    case float3x3
    case float3x4
    
    case float4x2
    case float4x3
    case float4x4
    
    case half
    case half2
    case half3
    case half4
    
    case half2x2
    case half2x3
    case half2x4
    
    case half3x2
    case half3x3
    case half3x4
    
    case half4x2
    case half4x3
    case half4x4
    
    case int
    case int2
    case int3
    case int4
    
    case uint
    case uint2
    case uint3
    case uint4
    
    case short
    case short2
    case short3
    case short4
    
    case ushort
    case ushort2
    case ushort3
    case ushort4
    
    case char
    case char2
    case char3
    case char4
    
    case uchar
    case uchar2
    case uchar3
    case uchar4
    
    case bool
    case bool2
    case bool3
    case bool4
}

public enum VertexFormat : UInt {
    
    
    case invalid
    
    
    case uchar2
    
    case uchar3
    
    case uchar4
    
    
    case char2
    
    case char3
    
    case char4
    
    
    case uchar2Normalized
    
    case uchar3Normalized
    
    case uchar4Normalized
    
    
    case char2Normalized
    
    case char3Normalized
    
    case char4Normalized
    
    
    case ushort2
    
    case ushort3
    
    case ushort4
    
    
    case short2
    
    case short3
    
    case short4
    
    
    case ushort2Normalized
    
    case ushort3Normalized
    
    case ushort4Normalized
    
    
    case short2Normalized
    
    case short3Normalized
    
    case short4Normalized
    
    
    case half2
    
    case half3
    
    case half4
    
    
    case float
    
    case float2
    
    case float3
    
    case float4
    
    
    case int
    
    case int2
    
    case int3
    
    case int4
    
    
    case uint
    
    case uint2
    
    case uint3
    
    case uint4
    
    
    case int1010102Normalized
    
    case uint1010102Normalized
}

public enum IndexType : UInt {
    case uint16
    case uint32
}

public enum CullMode : UInt {
    
    
    case none
    
    case front
    
    case back
}

public enum Winding : UInt {
    
    
    case clockwise
    
    case counterClockwise
}

public enum DepthClipMode : UInt {
    
    
    case clip
    
    case clamp
}

public enum TriangleFillMode : UInt {
    
    
    case fill
    
    case lines
}

public enum CompareFunction : UInt {
    
    
    case never
    
    case less
    
    case equal
    
    case lessEqual
    
    case greater
    
    case notEqual
    
    case greaterEqual
    
    case always
}

public enum StencilOperation : UInt {
    
    
    case keep
    
    case zero
    
    case replace
    
    case incrementClamp
    
    case decrementClamp
    
    case invert
    
    case incrementWrap
    
    case decrementWrap
}

public struct Viewport {
    
    public var originX: Double
    
    public var originY: Double
    
    public var width: Double
    
    public var height: Double
    
    public var zNear: Double
    
    public var zFar: Double
    
    public init(originX: Double, originY: Double, width: Double, height: Double, zNear: Double, zFar: Double) {
        self.originX = originX
        self.originY = originY
        self.width = width
        self.height = height
        self.zNear = zNear
        self.zFar = zFar
    }
}


public struct ClearColor : Hashable {
    
    public var red: Double
    
    public var green: Double
    
    public var blue: Double
    
    public var alpha: Double
    
    public init() {
        self.red = 0.0
        self.green = 0.0
        self.blue = 0.0
        self.alpha = 0.0
    }
    
    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

/*!
 @struct Origin
 @abstract Identify a pixel in an image. Origin is ususally used as the upper-left corner of a region of a texture.
 */
public struct Origin {
    
    public var x: Int
    
    public var y: Int
    
    public var z: Int
    
    public init() {
        self.x = 0
        self.y = 0
        self.z = 0
    }
    
    public init(x: Int, y: Int, z: Int) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/*!
 @typedef Size
 @abstract A set of dimensions to declare the size of an object such as a compute kernel work group or grid.
 */
public struct Size : Hashable {
    
    public var width: Int
    
    public var height: Int
    
    public var depth: Int
    
    public init() {
        self.width = 0
        self.height = 0
        self.depth = 0
    }
    
    public init(width: Int, height: Int, depth: Int = 1) {
        self.width = width
        self.height = height
        self.depth = depth
    }
    
    
    public init(length: Int) {
        self.width = length
        self.height = 1
        self.depth = 1
    }
}

public struct Region {
    
    public var origin: Origin
    
    public var size: Size
    
    public init() {
        self.origin = Origin()
        self.size = Size()
    }
    
    public init(origin: Origin, size: Size) {
        self.origin = origin
        self.size = size
    }
    
    public init(x: Int, y: Int, width: Int, height: Int) {
        self.origin = Origin(x: x, y: y, z: 0)
        self.size = Size(width: width, height: height, depth: 1)
    }
}

public struct ScissorRect : Equatable {
    
    public var x : Int = 0
    public var y : Int = 0
    public var width : Int = 0
    public var height : Int = 0
    
    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
    
    public static func ==(lhs: ScissorRect, rhs: ScissorRect) -> Bool {
        return lhs.x == rhs.x && lhs.y == rhs.y && lhs.width == rhs.width && lhs.height == rhs.height
    }
}
