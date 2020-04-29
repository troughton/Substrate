import Foundation
import stb_image_write
import tinyexr
import LodePNG

extension TextureData {
    public enum SaveFormat: String {
        case png
        case bmp
        case tga
        case hdr
        case jpg
        case exr
        
        public var isLinearHDR : Bool {
            switch self {
            case .hdr, .exr:
                return true
            default:
                return false
            }
        }
        
        public var fileExtension : String {
            return self.rawValue
        }
    }
    
    public enum SaveError: Error {
        case unknownFormat(String)
        case errorWritingFile(String)
        case invalidChannelCount(Int)
        case unexpectedDataFormat(found: Any.Type, required: [Any.Type])
    }
    
    public func write(to url: URL) throws {
        guard let saveFormat = SaveFormat(rawValue: url.pathExtension) else {
            throw SaveError.unknownFormat(url.pathExtension)
        }
        
        let filePath = url.path
        
        let result : Int32
        var error : UnsafePointer<Int8>? = nil
        switch saveFormat {
        case .png:
            
            let colourType: LodePNGColorType
            switch self.channels {
            case 1:
                colourType = LCT_GREY
            case 2:
                colourType = LCT_GREY_ALPHA
            case 3:
                colourType = LCT_RGB
            case 4:
                colourType = LCT_RGBA
            default:
                throw SaveError.invalidChannelCount(self.channels)
            }
            
            guard T.self == UInt8.self || T.self == UInt16.self else { throw SaveError.unexpectedDataFormat(found: T.self, required: [UInt8.self, UInt16.self]) }
            
            let errorCode = self.data.withMemoryRebound(to: UInt8.self, capacity: self.width * self.height * self.channels * MemoryLayout<T>.stride) { pixelData in
                return lodepng_encode_file(filePath, pixelData, UInt32(self.width), UInt32(self.height), colourType, UInt32(MemoryLayout<T>.size * 8))
            }
            
            if errorCode != 0 {
                error = lodepng_error_text(errorCode)
            }
            result = errorCode == 0 ? 1 : 0
        case .hdr:
            guard T.self == Float.self else { throw SaveError.unexpectedDataFormat(found: T.self, required: [Float.self]) }
            result = stbi_write_hdr(filePath, Int32(self.width), Int32(self.height), Int32(self.channels), self.data as! UnsafeMutablePointer<Float>)
        case .bmp:
            guard T.self == UInt8.self else { throw SaveError.unexpectedDataFormat(found: T.self, required: [UInt8.self]) }
            result = stbi_write_bmp(filePath, Int32(self.width), Int32(self.height), Int32(self.channels), self.data as! UnsafeMutablePointer<UInt8>)
        case .tga:
            guard T.self == UInt8.self else { throw SaveError.unexpectedDataFormat(found: T.self, required: [UInt8.self]) }
            result = stbi_write_tga(filePath, Int32(self.width), Int32(self.height), Int32(self.channels), self.data as! UnsafeMutablePointer<UInt8>)
        case .jpg:
            guard T.self == UInt8.self else { throw SaveError.unexpectedDataFormat(found: T.self, required: [UInt8.self]) }
            result = stbi_write_jpg(filePath, Int32(self.width), Int32(self.height), Int32(self.channels), self.data as! UnsafeMutablePointer<UInt8>, /* quality = */ 90)
        case .exr:
            guard T.self == Float.self else { throw SaveError.unexpectedDataFormat(found: T.self, required: [Float.self]) }
            let exrResult = SaveEXR(self.data as! UnsafeMutablePointer<Float>, Int32(self.width), Int32(self.height), Int32(self.channels), 0, filePath, &error)
            result = exrResult == 0 ? 1 : 0
        }
        
        if result == 0 {
            throw SaveError.errorWritingFile(error.map { String(cString: $0) } ?? "(no error message)")
        }
    }
}
