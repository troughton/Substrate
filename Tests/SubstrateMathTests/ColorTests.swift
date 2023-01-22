//
//  ColorTests.swift
//
//
//  Created by Thomas Roughton on 8/12/19.
//

import XCTest
import RealModule
@testable import SubstrateMath

class ColorTests: XCTestCase {
    
    func testColorSpaceTransform() {
        let srgbToXYZ =  CIEXYZ1931ColorSpace<Float>.sRGB.primaries.rgbToXYZMatrix
        
        let referenceSRGBToXYZ = Matrix3x3<Float>(SIMD3(0.4124, 0.3576, 0.1805),
                                                  SIMD3(0.2126, 0.7152, 0.0722),
                                                  SIMD3(0.0193, 0.1192, 0.9505)).transpose
        for c in 0..<3 {
            for r in 0..<3 {
                XCTAssertEqual(srgbToXYZ[c][r], referenceSRGBToXYZ[c][r], accuracy: 0.001)
            }
        }
        
        print(CIEXYZ1931ColorSpace<Double>.sRGB.xyzToRGBMatrix * CIEXYZ1931ColorSpace<Double>.sonySGamut3.rgbToXYZMatrix)
    }
}
