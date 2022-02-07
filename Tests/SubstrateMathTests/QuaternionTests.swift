//
//  MatrixTests.swift
//  
//
//  Created by Thomas Roughton on 8/12/19.
//

import XCTest
import RealModule
@testable import SubstrateMath

class QuaternionTests: XCTestCase {
    func testEulerAngleConventions() {
        
        for sourceEuler in [
            SIMD3(0.0, 0.5 * .pi, 0.0),
            SIMD3(0.5 * .pi, 0.0, 0.0),
            SIMD3(0.0, 0.0, 0.5 * .pi),
            SIMD3(0.3 * .pi, 0.9 * .pi, 0.0),
                            SIMD3(-0.7 * .pi, 0.2 * .pi, 0.0),
                            SIMD3(0.0, 0.6 * .pi, 0.4 * .pi),
                            SIMD3(-0.15 * .pi, 0.3 * .pi, -0.4 * .pi)] {
            
            let quaternionA = Quaternion(eulerAngles: sourceEuler)
            let quaternionB = Quaternion(angle: Angle(radians: sourceEuler.z), axis: SIMD3(0, 0, 1)) * Quaternion(angle: Angle(radians: sourceEuler.x), axis: SIMD3(1, 0, 0)) * Quaternion(angle: Angle(radians: sourceEuler.y), axis: SIMD3(0, 1, 0))
            
            let vectorA = Matrix3x3(quaternion: quaternionA) * SIMD3(0, 0, 1)
            let vectorB = Matrix3x3(quaternion: quaternionB) * SIMD3(0, 0, 1)
            
            XCTAssertEqual(vectorA.x, vectorB.x, accuracy: 0.001)
            XCTAssertEqual(vectorA.y, vectorB.y, accuracy: 0.001)
            XCTAssertEqual(vectorA.z, vectorB.z, accuracy: 0.001)
        }
    }
}
