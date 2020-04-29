import Foundation
import stb_image_write
import tinyexr

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
        case unexpectedDataFormat(found: Any.Type, required: Any.Type)
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
            guard T.self == UInt8.self else { throw SaveError.unexpectedDataFormat(found: T.self, required: UInt8.self) }
            result = stbi_write_png(filePath, Int32(self.width), Int32(self.height), Int32(self.channels), self.data as! UnsafeMutablePointer<UInt8>, Int32(self.width * self.channels))
        case .hdr:
            guard T.self == Float.self else { throw SaveError.unexpectedDataFormat(found: T.self, required: Float.self) }
            result = stbi_write_hdr(filePath, Int32(self.width), Int32(self.height), Int32(self.channels), self.data as! UnsafeMutablePointer<Float>)
        case .bmp:
            guard T.self == UInt8.self else { throw SaveError.unexpectedDataFormat(found: T.self, required: UInt8.self) }
            result = stbi_write_bmp(filePath, Int32(self.width), Int32(self.height), Int32(self.channels), self.data as! UnsafeMutablePointer<UInt8>)
        case .tga:
            guard T.self == UInt8.self else { throw SaveError.unexpectedDataFormat(found: T.self, required: UInt8.self) }
            result = stbi_write_tga(filePath, Int32(self.width), Int32(self.height), Int32(self.channels), self.data as! UnsafeMutablePointer<UInt8>)
        case .jpg:
            guard T.self == UInt8.self else { throw SaveError.unexpectedDataFormat(found: T.self, required: UInt8.self) }
            result = stbi_write_jpg(filePath, Int32(self.width), Int32(self.height), Int32(self.channels), self.data as! UnsafeMutablePointer<UInt8>, /* quality = */ 90)
        case .exr:
            guard T.self == Float.self else { throw SaveError.unexpectedDataFormat(found: T.self, required: Float.self) }
            let exrResult = SaveEXR(self.data as! UnsafeMutablePointer<Float>, Int32(self.width), Int32(self.height), Int32(self.channels), 0, filePath, &error)
            result = exrResult == 0 ? 1 : 0
        }
        
        if result == 0 {
            throw SaveError.errorWritingFile(error.map { String(cString: $0) } ?? "(no error message)")
        }
    }
}
