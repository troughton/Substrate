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
        let srgbToXYZ =  CIEXYZ1931ColorSpace<Float>.sRGB.rgbToXYZMatrix
        
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
    
    
    func colorMatrix(inputColorSpace: CIEXYZ1931ColorSpace<Double>, outputColorSpace: CIEXYZ1931ColorSpace<Double>, exposureScale: Double, inputReferenceWhite: SIMD2<Double>, outputReferenceWhite: SIMD2<Double>) -> Matrix3x3<Float> {
        let toXYZ = inputColorSpace.rgbToXYZMatrix
        let scale = Matrix3x3<Double>(diagonal: SIMD3(exposureScale, exposureScale, exposureScale))
        
        var whitePointAdaptation = Matrix3x3<Double>.identity
        if inputReferenceWhite != outputReferenceWhite {
            whitePointAdaptation = CIEXYZ1931ColorSpace<Double>.chromaticAdaptationMatrix(from: XYZColor(chromacity: SIMD2(inputReferenceWhite)), to: XYZColor(chromacity: SIMD2(outputReferenceWhite)))
        }
        
        let toRGB = outputColorSpace.xyzToRGBMatrix
        return Matrix3x3<Float>(toRGB * whitePointAdaptation * scale * toXYZ)
    }
    
    func testColorSpaceTransformB() {
        
        let colorMatrix = self.colorMatrix(inputColorSpace: .rec2020, outputColorSpace: .rec2020, exposureScale: 1.0, inputReferenceWhite: CIEXYZ1931ColorSpace<Double>.ReferenceWhite.d65.chromacity, outputReferenceWhite: CIEXYZ1931ColorSpace<Double>.ReferenceWhite.d65.chromacity)
        print("Colour matrix is \(colorMatrix)")
    }
}
