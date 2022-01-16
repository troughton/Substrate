//
//  MatrixTests.swift
//  
//
//  Created by Thomas Roughton on 8/12/19.
//

import XCTest
import RealModule
@testable import SubstrateMath

class FrustumTests: XCTestCase {
    func testPlaneOrientations() {
        let m = Matrix4x4<Float>.ortho(left: 0.0, right: 1.0, bottom: 0.0, top: 1.0, near: 0.0, far: 1.0)
        let frustum = Frustum(worldToProjectionMatrix: m)
        print(frustum)
        
        XCTAssertEqual(frustum.leftPlane, FrustumPlane(normalVector: SIMD3(1, 0, 0), constant: 0.0))
        XCTAssertEqual(frustum.rightPlane, FrustumPlane(normalVector: SIMD3(-1, 0, 0), constant: 1.0))
        XCTAssertEqual(frustum.bottomPlane, FrustumPlane(normalVector: SIMD3(0, 1, 0), constant: 0.0))
        XCTAssertEqual(frustum.topPlane, FrustumPlane(normalVector: SIMD3(0, -1, 0), constant: 1.0))
        XCTAssertEqual(frustum.nearPlane, FrustumPlane(normalVector: SIMD3(0, 0, 1), constant: 0.0))
        XCTAssertEqual(frustum.farPlane, FrustumPlane(normalVector: SIMD3(0, 0, -1), constant: 1.0))
    }
    
}
