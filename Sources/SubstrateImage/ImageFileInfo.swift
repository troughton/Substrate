//
//  ImageFileFormat.swift
//  
//
//  Created by Thomas Roughton on 12/05/23.
//

import Foundation


public struct ImageFileFormat: Hashable, Codable {
    public var typeIdentifier: String
    
    public init(typeIdentifier: String) {
        self.typeIdentifier = typeIdentifier
    }
    
    public static func ~=(lhs: ImageFileFormat, rhs: ImageFileFormat) -> Bool {
        return lhs == rhs
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(typeIdentifier: try container.decode(String.self))
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.typeIdentifier)
    }
}


public struct ImageFileInfo: Hashable, Codable {
    public let format: ImageFileFormat?
    public let width : Int
    public let height : Int
    public let channelCount : Int
    
    public let bitDepth: Int
    public let isSigned: Bool
    public let isFloatingPoint: Bool
    
    public let colorSpace: ImageColorSpace
    public let alphaMode: ImageAlphaMode
    
    /// The physical size of the image in metres.
    public let physicalSize: SIMD2<Double>?
    
    public init(format: ImageFileFormat? = nil,
                width: Int, height: Int, channelCount: Int,
                bitDepth: Int,
                isSigned: Bool,
                isFloatingPoint: Bool,
                colorSpace: ImageColorSpace,
                alphaMode: ImageAlphaMode,
                physicalSize: SIMD2<Double>? = nil) {
        self.format = format
        self.width = width
        self.height = height
        self.channelCount = channelCount
        self.bitDepth = bitDepth
        self.isSigned = isSigned
        self.isFloatingPoint = isFloatingPoint
        self.colorSpace = colorSpace
        self.alphaMode = alphaMode
        self.physicalSize = physicalSize
    }
}
