
#if canImport(Compressonator)
import Compressonator

extension CMP_FORMAT {
    
    public init(_ pixelFormat: PixelFormat) {
        switch pixelFormat {
        case .invalid:
            self = CMP_FORMAT_Unknown
        case .r8Unorm, .r8Unorm_sRGB, .r8Snorm, .r8Uint, .r8Sint:
            self = CMP_FORMAT_R_8
        case .rg8Unorm, .rg8Unorm_sRGB, .rg8Snorm, .rg8Uint, .rg8Sint:
            self = CMP_FORMAT_RG_8
        case .r16Unorm, .r16Snorm, .r16Uint, .r16Sint:
            self = CMP_FORMAT_R_16
        case .r16Float:
            self = CMP_FORMAT_R_16F
        case .rgba8Snorm, .rgba8Unorm, .rgba8Unorm_sRGB:
            self = CMP_FORMAT_RGBA_8888
        case .bgra8Unorm, .bgra8Unorm_sRGB:
            self = CMP_FORMAT_BGRA_8888
        case .rgba16Unorm, .rgba16Snorm, .rgba16Uint, .rgba16Sint:
            self = CMP_FORMAT_RGBA_16
        case .rgba16Float:
            self = CMP_FORMAT_RGBA_16F
        case .rgba32Float:
            self = CMP_FORMAT_RGBA_32F
        case .bgr10a2Unorm:
            self = CMP_FORMAT_ARGB_2101010
        case .rgb9e5Float:
            self = CMP_FORMAT_RGBE_32F
        case .bc1_rgba, .bc1_rgba_sRGB:
            self = CMP_FORMAT_BC1
        case .bc2_rgba, .bc2_rgba_sRGB:
            self = CMP_FORMAT_BC2
        case .bc3_rgba, .bc3_rgba_sRGB:
            self = CMP_FORMAT_BC3
        case .bc4_rSnorm, .bc4_rUnorm:
            self = CMP_FORMAT_BC4
        case .bc5_rgSnorm, .bc5_rgUnorm:
            self = CMP_FORMAT_BC5
        case .bc6H_rgbFloat:
            self = CMP_FORMAT_BC6H_SF
        case .bc6H_rgbuFloat:
            self = CMP_FORMAT_BC6H
        case .bc7_rgbaUnorm, .bc7_rgbaUnorm_sRGB:
            self = CMP_FORMAT_BC7
        default:
            fatalError("Unhandled format")
        }
    }
}

extension CMP_Texture {
    public init(width: Int, height: Int, pixelFormat: PixelFormat, data: UnsafeMutableRawPointer? = nil) {
        self.init()
        self.dwSize = UInt32(MemoryLayout<CMP_Texture>.size)
        self.dwWidth = UInt32(width)
        self.dwHeight = UInt32(height)
        self.dwPitch = UInt32(exactly: pixelFormat.bytesPerPixel * Double(width))!
        self.format = CMP_FORMAT(pixelFormat)
        self.dwDataSize = CMP_CalculateBufferSize(&self)
        self.pData = (data ?? .allocate(byteCount: Int(self.dwDataSize), alignment: 64)).assumingMemoryBound(to: CMP_BYTE.self)
    }
    
    public init(width: Int, height: Int, format: CMP_FORMAT, bytesPerPixel: Int, data: UnsafeMutableRawPointer? = nil) {
         self.init()
         self.dwSize = UInt32(MemoryLayout<CMP_Texture>.size)
         self.dwWidth = UInt32(width)
         self.dwHeight = UInt32(height)
         self.dwPitch = UInt32(bytesPerPixel * width)
         self.format = format
         self.dwDataSize = CMP_CalculateBufferSize(&self)
         self.pData = (data ?? .allocate(byteCount: Int(self.dwDataSize), alignment: 64)).assumingMemoryBound(to: CMP_BYTE.self)
     }
}

#endif
