//
//  Image+Codable.swift
//  
//
//  Created by Thomas Roughton on 11/02/21.
//

import Foundation

enum ImageCodingKeys: CodingKey {
    case fileInfo
    case data
}

public enum ImageDecodingError: Error {
    case invalidDimensions(width: Int, height: Int, channelCount: Int)
    case noValidFormat(ImageFileInfo)
    case incompatibleFormat(ImageFileInfo, Any.Type)
}

public struct AnyCodableImage: Codable {
    public let image: AnyImage
    
    public init(_ image: AnyImage) {
        self.image = image
    }
    
    static func decodeImage<T>(header: ImageFileInfo, data: Data, type: T.Type) -> Image<T> {
        var image = Image<T>(width: header.width, height: header.height, channelCount: header.channelCount,
                        colorSpace: header.colorSpace, alphaMode: header.alphaMode)
        image.withUnsafeMutableBufferPointer { destination in
            data.withUnsafeBytes { source in
                let source = source.bindMemory(to: T.self)
                destination.baseAddress?.update(from: source.baseAddress!, count: source.count)
            }
        }
        
        return image
    }
    
    public static func decode(from decoder: Decoder) throws -> AnyImage {
        let container = try decoder.container(keyedBy: ImageCodingKeys.self)
        let header = try container.decode(ImageFileInfo.self, forKey: .fileInfo)
        let data = try container.decode(Data.self, forKey: .data)
        
        // Sanitise for reasonable dimensions.
        guard header.width > 0, header.width <= 655536,
              header.height > 0, header.height <= 655536,
              header.channelCount > 0, header.channelCount <= 1024 else {
            throw ImageDecodingError.invalidDimensions(width: header.width, height: header.height, channelCount: header.channelCount)
        }
        
        switch (header.bitDepth, header.isSigned, header.isFloatingPoint) {
        case (8, false, false):
            return decodeImage(header: header, data: data, type: UInt8.self)
        case (8, true, false):
            return decodeImage(header: header, data: data, type: Int8.self)
        case (16, false, false):
            return decodeImage(header: header, data: data, type: UInt16.self)
        case (16, true, false):
            return decodeImage(header: header, data: data, type: Int16.self)
        case (32, false, false):
            return decodeImage(header: header, data: data, type: UInt32.self)
        case (32, true, false):
            return decodeImage(header: header, data: data, type: Int32.self)
        case (64, false, false):
            return decodeImage(header: header, data: data, type: UInt64.self)
        case (64, true, false):
            return decodeImage(header: header, data: data, type: Int64.self)
        case (32, true, true):
            return decodeImage(header: header, data: data, type: Float.self)
        case (64, true, true):
            return decodeImage(header: header, data: data, type: Double.self)
        #if (os(iOS) || os(tvOS) || os(watchOS)) && !targetEnvironment(macCatalyst)
        case (16, true, true):
            if #available(iOS 14.0, tvOS 14.0, watchOS 14.0, *) {
                return decodeImage(header: header, data: data, type: Float16.self)
            } else {
                // Fallback on earlier versions
                throw ImageDecodingError.noValidFormat(header)
            }
        #endif
        #if arch(x86_64) && !os(Windows)
        case (80, true, true):
            return decodeImage(header: header, data: data, type: Float80.self)
        #endif
        default:
            throw ImageDecodingError.noValidFormat(header)
        }
    }
    
    public init(from decoder: Decoder) throws {
        self.image = try AnyCodableImage.decode(from: decoder)
    }
    
    public func encode(to encoder: Encoder) throws {
        try self.image.encode(to: encoder)
    }
}

extension Image: Codable {
    public init(from decoder: Decoder) throws {
        let anyImage = try AnyCodableImage.decode(from: decoder)
        guard let image = anyImage as? Image<ComponentType> else {
            throw ImageDecodingError.incompatibleFormat(anyImage.fileInfo, ComponentType.self)
        }
        self = image
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ImageCodingKeys.self)
        try container.encode(self.fileInfo, forKey: .fileInfo)
        try container.encode(self.data, forKey: .data)
    }
}
