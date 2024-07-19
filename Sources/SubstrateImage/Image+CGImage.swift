//
//  Image+CGImage.swift
//  
//
//  Created by Thomas Roughton on 12/05/23.
//

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
import SubstrateMath

extension Image {
    
    private func cgColorSpace(cieSpace: CIEXYZ1931ColorSpace<Float>, isGrayscale: Bool) -> CGColorSpace {
        // TODO: handle more custom colour spaces
        switch cieSpace {
        case .acesCG:
            return CGColorSpace(name: CGColorSpace.acescgLinear)!
        case .dciP3:
            return CGColorSpace(name: CGColorSpace.dcip3)!
        case .displayP3:
            return CGColorSpace(name: CGColorSpace.displayP3)!
        case .linearSRGB:
            return CGColorSpace(name: isGrayscale ? CGColorSpace.linearGray : CGColorSpace.linearSRGB)!
        case .rec2020:
            if #available(macOS 12.0, iOS 15.1, *) {
                return CGColorSpace(name: CGColorSpace.itur_2020_sRGBGamma)!
            } else {
                break
            }
        case .rec709:
            return CGColorSpace(name: CGColorSpace.itur_709)!
        case .sRGB:
            return CGColorSpace(name: CGColorSpace.sRGB)!
        default:
            break
        }
        
        var gamma = CGFloat(cieSpace.eotf.representativeGamma ?? 1.0)
        switch cieSpace.eotf {
        case .linear:
            gamma = 1.0
        case .power(let power):
            gamma = CGFloat(power)
        case .hlg:
            if cieSpace.primaries == .sRGB {
                if #available(macOS 13.0, *) {
                    // itur_709_HLG has incorrect availability information.
                    
                    let itur709HLG: CFString = "kCGColorSpaceITUR_709_HLG" as CFString // CGColorSpace.itur_709_HLG has incorrect availability on macOS 12 which leads to missing symbols at runtime.
                    return CGColorSpace(name: itur709HLG)!
                } else {
                    break
                }
            } else if cieSpace.primaries == .p3 {
                return CGColorSpace(name: CGColorSpace.displayP3_HLG)!
            } else {
                return CGColorSpace(name: CGColorSpace.itur_2100_HLG)!
            }
        case .pq:
            if cieSpace.primaries == .sRGB {
                if #available(iOS 15.1, *) {
                    return CGColorSpace(name: CGColorSpace.itur_709_PQ)!
                } else {
                    break
                }
            } else if cieSpace.primaries == .p3 {
                return CGColorSpace(name: CGColorSpace.displayP3_PQ)!
            } else {
                return CGColorSpace(name: CGColorSpace.itur_2100_PQ)!
            }
        default:
            break
        }
        let whitePoint = cieSpace.referenceWhite.value
        var whitePointCG: [CGFloat] = [CGFloat(whitePoint.X), CGFloat(whitePoint.Y), CGFloat(whitePoint.Z)]
        var gammaCG: [CGFloat] = [gamma, gamma, gamma]
        let xyzToRGB = Matrix3x3<Double>(cieSpace.xyzToRGBMatrix)
        return withUnsafeBytes(of: xyzToRGB) { xyzToRGB -> CGColorSpace in
            let xyzToRGB = xyzToRGB.bindMemory(to: CGFloat.self)
            return CGColorSpace(calibratedRGBWhitePoint: &whitePointCG, blackPoint: nil, gamma: &gammaCG, matrix: xyzToRGB.baseAddress)!
        }
    }
    
    public var cgColorSpace: CGColorSpace {
        let isGrayscale = self.channelCount < 3
        
        switch self.colorSpace {
        case .undefined:
            return isGrayscale ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
        case .gammaSRGB(let gamma):
            var whitePoint: [CGFloat] = [0.3127, 0.3290, 1.0]
            return CGColorSpace(calibratedGrayWhitePoint: &whitePoint, blackPoint: nil, gamma: CGFloat(gamma)) ?? CGColorSpace(name: CGColorSpace.linearSRGB)!
        case .linearSRGB:
            return CGColorSpace(name: isGrayscale ? CGColorSpace.linearGray : CGColorSpace.linearSRGB)!
        case .sRGB:
            return CGColorSpace(name: isGrayscale ? CGColorSpace.genericGrayGamma2_2 : CGColorSpace.sRGB)!
        case .cieRGB(let cieSpace):
            return self.cgColorSpace(cieSpace: cieSpace, isGrayscale: isGrayscale)
        }
    }
    
    public var cgBitmapInfo: CGBitmapInfo {
        var bitmapInfo = CGBitmapInfo()
        if T.self == Float.self {
            bitmapInfo.formUnion(.floatComponents)
        } else if T.self == UInt16.self {
            bitmapInfo.formUnion(.byteOrder16Little)
        } else if T.self == UInt32.self {
            bitmapInfo.formUnion(.byteOrder32Little)
        }
        if self.channelCount == 4 || self.channelCount == 2 {
            bitmapInfo.formUnion(CGBitmapInfo(rawValue: self.alphaMode == .premultiplied ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.last.rawValue))
        } else {
            bitmapInfo.formUnion(CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue))
        }
        return bitmapInfo
    }
}

extension Image where ComponentType: SIMDScalar {
    @_specialize(kind: full, where ComponentType == UInt8)
    @_specialize(kind: full, where ComponentType == UInt16)
    @_specialize(kind: full, where ComponentType == Float)
    init(_cgImage cgImage: CGImage, fileInfo: ImageFileInfo?, loadingDelegate: ImageLoadingDelegate? = nil) throws {
        var cgImage = cgImage
        
        let cgColorSpace = cgImage.colorSpace
        let colorSpace: ImageColorSpace
        
        let itur709HLG: CFString = "kCGColorSpaceITUR_709_HLG" as CFString // CGColorSpace.itur_709_HLG has incorrect availability on macOS 12 which leads to missing symbols at runtime.
        let itur_2020_sRGBGamma: CFString = "kCGColorSpaceITUR_2020_sRGBGamma" as CFString // iOS 15.1 availability
        let linearITUR_2020: CFString = "kCGColorSpaceLinearITUR_2020" as CFString // iOS 15.0 availability
        let itur_709_PQ: CFString = "kCGColorSpaceITUR_709_PQ" as CFString // iOS 15.1 availability
        switch cgColorSpace?.name {
        case CGColorSpace.linearSRGB, CGColorSpace.linearGray, CGColorSpace.extendedLinearSRGB:
            colorSpace = .linearSRGB
        case CGColorSpace.sRGB, CGColorSpace.extendedSRGB:
            colorSpace = .sRGB
        case CGColorSpace.acescgLinear:
            colorSpace = .cieRGB(colorSpace: .acesCG)
        case CGColorSpace.dcip3:
            colorSpace = .cieRGB(colorSpace: .dciP3)
        case CGColorSpace.displayP3:
            colorSpace = .cieRGB(colorSpace: .displayP3)
        case itur_2020_sRGBGamma:
            colorSpace = .cieRGB(colorSpace: .rec2020)
        case linearITUR_2020:
            var cieSpace = CIEXYZ1931ColorSpace<Float>.rec2020
            cieSpace.eotf = .linear
            colorSpace = .cieRGB(colorSpace: cieSpace)
        case CGColorSpace.itur_2020, CGColorSpace.extendedITUR_2020:
            var cieSpace = CIEXYZ1931ColorSpace<Float>.rec2020
            cieSpace.eotf = .power(2.4)
            colorSpace = .cieRGB(colorSpace: cieSpace)
        case CGColorSpace.itur_709:
            colorSpace = .cieRGB(colorSpace: .rec709)
        case itur709HLG:
            var cieSpace = CIEXYZ1931ColorSpace<Float>.rec709
            cieSpace.eotf = .hlg
            colorSpace = .cieRGB(colorSpace: cieSpace)
        case CGColorSpace.displayP3_HLG:
            var cieSpace = CIEXYZ1931ColorSpace<Float>.displayP3
            cieSpace.eotf = .hlg
            colorSpace = .cieRGB(colorSpace: cieSpace)
        case CGColorSpace.itur_2100_HLG:
            var cieSpace = CIEXYZ1931ColorSpace<Float>.rec2020
            cieSpace.eotf = .hlg
            colorSpace = .cieRGB(colorSpace: cieSpace)
        case itur_709_PQ:
            var cieSpace = CIEXYZ1931ColorSpace<Float>.rec709
            cieSpace.eotf = .pq
            colorSpace = .cieRGB(colorSpace: cieSpace)
        case CGColorSpace.displayP3_PQ:
            var cieSpace = CIEXYZ1931ColorSpace<Float>.displayP3
            cieSpace.eotf = .pq
            colorSpace = .cieRGB(colorSpace: cieSpace)
        case CGColorSpace.itur_2100_PQ:
            var cieSpace = CIEXYZ1931ColorSpace<Float>.rec2020
            cieSpace.eotf = .pq
            colorSpace = .cieRGB(colorSpace: cieSpace)
        default:
            if ComponentType.self == UInt8.self, let sRGB = cgImage.copy(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) {
                cgImage = sRGB
                colorSpace = .sRGB
            } else if let linearSRGB = cgImage.copy(colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!) {
                cgImage = linearSRGB
                colorSpace = .linearSRGB
            } else {
                colorSpace = .undefined
            }
        }
        
        guard let data = cgImage.dataProvider?.data as NSData? else {
            throw ImageLoadingError.invalidData(message: "Unable to retrieve CGImage data provider")
        }
        
        let alphaMode: ImageAlphaMode
        switch cgImage.alphaInfo {
        case .first, .last:
            alphaMode = .postmultiplied
        case .premultipliedFirst, .premultipliedLast:
            alphaMode = .premultiplied
        default:
            alphaMode = .none
        }
        
        let loadingDelegate = loadingDelegate ?? DefaultImageLoadingDelegate()
        let channelCount = fileInfo.map { loadingDelegate.channelCount(for: $0) } ?? (cgImage.bitsPerPixel / cgImage.bitsPerComponent)
        
        let (imageData, allocator) = try loadingDelegate.allocateMemory(byteCount: cgImage.width * cgImage.height * channelCount * MemoryLayout<ComponentType>.stride, alignment: MemoryLayout<SIMD4<ComponentType>>.stride, zeroed: false)
        
        self.init(width: cgImage.width, height: cgImage.height,
                  channelCount: channelCount,
                  colorSpace: colorSpace,
                  alphaMode: alphaMode,
                  data: imageData.bindMemory(to: ComponentType.self),
                  allocator: allocator)
        
        let sourceChannelCount = cgImage.bitsPerPixel / cgImage.bitsPerComponent
        let width = self.width
        let height = self.height
        
        self.withUnsafeMutableBufferPointer { contentsBuffer in
            for y in 0..<height {
                let base = data.bytes + y * cgImage.bytesPerRow
                let dest = contentsBuffer.baseAddress!.advanced(by: y * width * channelCount)
                if sourceChannelCount == channelCount {
                    for i in 0..<width * channelCount {
                        dest.advanced(by: i).initialize(to: base.load(fromByteOffset: i * MemoryLayout<ComponentType>.stride, as: ComponentType.self))
                    }
                } else {
                    for x in 0..<width {
                        for c in 0..<Swift.min(sourceChannelCount, channelCount) {
                            dest.advanced(by: x * channelCount + c).initialize(to: base.load(fromByteOffset: (x * sourceChannelCount + c) * MemoryLayout<ComponentType>.stride, as: ComponentType.self))
                        }
                        for c in Swift.min(sourceChannelCount, channelCount)..<channelCount {
                            dest.advanced(by: x * channelCount + c).withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<ComponentType>.size) { $0.initialize(repeating: 0 as UInt8, count: MemoryLayout<ComponentType>.size) }
                        }
                    }
                }
            }
            
            // Reference: https://stackoverflow.com/a/49087310
            let alphaInfo: CGImageAlphaInfo? = CGImageAlphaInfo(rawValue: cgImage.bitmapInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue)
            let alphaFirst: Bool = alphaInfo == .premultipliedFirst || alphaInfo == .first || alphaInfo == .noneSkipFirst
            let alphaLast: Bool = alphaInfo == .premultipliedLast || alphaInfo == .last || alphaInfo == .noneSkipLast
            var argbOrder: Bool = false
            if cgImage.bitsPerComponent == 8, !cgImage.bitmapInfo.intersection([.byteOrder16Little, .byteOrder32Little]).isEmpty {
                argbOrder = true
            } else if cgImage.bitsPerComponent == 16, cgImage.bitmapInfo.contains(.byteOrder32Little) {
                argbOrder = true
            } else if cgImage.bitsPerComponent == 16, !cgImage.bitmapInfo.contains(.byteOrder16Little) {
                contentsBuffer.withMemoryRebound(to: UInt16.self) { buffer in
                    for i in buffer.indices {
                        buffer[i] = buffer[i].bigEndian
                    }
                }
                
                argbOrder = false
            } else if cgImage.bitsPerComponent == 32, !cgImage.bitmapInfo.contains(.byteOrder32Little) {
                contentsBuffer.withMemoryRebound(to: UInt32.self) { buffer in
                    for i in buffer.indices {
                        buffer[i] = buffer[i].bigEndian
                    }
                }
                
                argbOrder = false
            }
            
            if channelCount == 2 {
                if alphaFirst != argbOrder {
                    for baseIndex in stride(from: 0, to: contentsBuffer.count, by: channelCount) {
                        contentsBuffer.swapAt(baseIndex + 0, baseIndex + 1) // AR to RA
                    }
                }
            } else if channelCount == 3 {
                if argbOrder {
                    for baseIndex in stride(from: 0, to: contentsBuffer.count, by: channelCount) {
                        contentsBuffer.swapAt(baseIndex + 0, baseIndex + 2) // BGR to RGB
                    }
                }
            } else if channelCount == 4 {
                let swizzle: SIMD4<Int>
                if alphaFirst && argbOrder {
                    swizzle = SIMD4(2, 1, 0, 3)
                } else if alphaFirst {
                    swizzle = SIMD4(1, 2, 3, 0)
                } else if alphaLast && argbOrder {
                    swizzle = SIMD4(3, 2, 1, 0)
                } else {
                    swizzle = SIMD4(0, 1, 2, 3)
                }
                
                if swizzle != SIMD4(0, 1, 2, 3) {
                    contentsBuffer.withMemoryRebound(to: SIMD4<ComponentType>.self) { buffer in
                        for i in buffer.indices {
                            buffer[i] = buffer[i][swizzle]
                        }
                    }
                }
            }
        }
    }
}

extension Image where ComponentType: SIMDScalar & UnsignedInteger & FixedWidthInteger {
    @_specialize(kind: full, where ComponentType == UInt8)
    @_specialize(kind: full, where ComponentType == UInt16)
    public init(cgImage: CGImage, fileInfo: ImageFileInfo? = nil, loadingDelegate: ImageLoadingDelegate? = nil) throws {
        try self.init(_cgImage: cgImage, fileInfo: fileInfo, loadingDelegate: loadingDelegate)
        
        if let fileInfo = fileInfo, fileInfo.channelCount < self.channelCount {
            let alphaChannelIndex = self.channelCount - 1
            self.apply(channelRange: alphaChannelIndex..<self.channelCount) { _ in
                ComponentType.max
            }
        }
    }
}

extension Image where ComponentType: SIMDScalar & SignedInteger & FixedWidthInteger {
    public init(cgImage: CGImage, fileInfo: ImageFileInfo? = nil, loadingDelegate: ImageLoadingDelegate? = nil) throws {
        try self.init(_cgImage: cgImage, fileInfo: fileInfo, loadingDelegate: loadingDelegate)
    }
}

extension Image where ComponentType: SIMDScalar & BinaryFloatingPoint {
    @_specialize(kind: full, where ComponentType == Float)
    public init(cgImage: CGImage, fileInfo: ImageFileInfo? = nil, loadingDelegate: ImageLoadingDelegate? = nil) throws {
        try self.init(_cgImage: cgImage, fileInfo: fileInfo, loadingDelegate: loadingDelegate)
        
        if let fileInfo = fileInfo, fileInfo.channelCount < self.channelCount {
            let alphaChannelIndex = self.channelCount - 1
            self.apply(channelRange: alphaChannelIndex..<self.channelCount) { _ in
                1.0
            }
        }
    }
}

#endif
