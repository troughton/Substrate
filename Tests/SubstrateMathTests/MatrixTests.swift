//
//  MatrixTests.swift
//  
//
//  Created by Thomas Roughton on 8/12/19.
//

import XCTest
import RealModule
@testable import SubstrateMath

class MatrixTests: XCTestCase {
    func testAffineMatrixVector() {
        let m = AffineMatrix<Float>.lookAtInv(eye: SIMD3(10, 10, 10), at: SIMD3<Float>(1, 1, 1))
        XCTAssertEqual(m * SIMD4(0, 0, 0, 1), SIMD4(10, 10, 10, 1))
        XCTAssertEqual(m * SIMD4(0, 0, 0, 0), SIMD4(0, 0, 0, 0))
        
        let forwardVec = SIMD4(m.forward, 0)
        XCTAssertEqual(m * SIMD4(0, 0, 1, 0), forwardVec)
        
        XCTAssertEqual((m.inverseNoScale * forwardVec).z, 1, accuracy: 0.001)
        XCTAssertEqual((m.inverse * forwardVec).z, 1, accuracy: 0.001)
    }
    
    func testAffineMatrixProduct() {
        let matrix = AffineMatrix<Float>(rows: SIMD4(1, 2, 3, 4), SIMD4(5, 6, 7, 8), SIMD4(9, 10, 11, 12))
        
        let product = matrix * matrix
        
        for column in 0..<4 {
            for row in 0..<3 {
                let targetValue = dot(matrix[row: row], matrix[column])
                XCTAssertEqual(product[row, column], targetValue)
            }
        }
    }
    
    func testMat2Product() {
        let matrix = Matrix2x2<Float>(SIMD2(1, 2), SIMD2(3, 4))
        
        let product = matrix * matrix
        
        for column in 0..<2 {
            for row in 0..<2 {
                let rowVals = SIMD2(matrix[row, 0], matrix[row, 1])
                let targetValue = dot(rowVals, matrix[column])
                XCTAssertEqual(product[row, column], targetValue)
            }
        }
    }
    
    func testMat3Product() {
        let matrix = Matrix3x3<Float>(SIMD3(1, 2, 3), SIMD3(4, 5, 6), SIMD3(7, 8, 9))
        
        let product = matrix * matrix
        
        for column in 0..<3 {
            for row in 0..<3 {
                let rowVals = SIMD3(matrix[row, 0], matrix[row, 1], matrix[row, 2])
                let targetValue = dot(rowVals, matrix[column])
                XCTAssertEqual(product[row, column], targetValue)
            }
        }
    }
    
    func testMat4Product() {
        let matrix = Matrix4x4<Float>(SIMD4(1, 2, 3, 4), SIMD4(5, 6, 7, 8), SIMD4(9, 10, 11, 12), SIMD4(13, 14, 15, 16))
        
        let product = matrix * matrix
        
        for column in 0..<4 {
            for row in 0..<4 {
                let rowVals = SIMD4(matrix[row, 0], matrix[row, 1], matrix[row, 2], matrix[row, 3])
                let targetValue = dot(rowVals, matrix[column])
                XCTAssertEqual(product[row, column], targetValue)
            }
        }
    }
    
    func testMat4Vector() {
        let matrix = Matrix4x4<Float>(SIMD4(1, 2, 3, 4), SIMD4(5, 6, 7, 8), SIMD4(9, 10, 11, 12), SIMD4(13, 14, 15, 16))
        let vector = SIMD4<Float>(5, 4, 3, 2)
        
        do {
            let product = matrix * vector
            
            for row in 0..<4 {
                let rowVals = SIMD4(matrix[row, 0], matrix[row, 1], matrix[row, 2], matrix[row, 3])
                let targetValue = dot(rowVals, vector)
                XCTAssertEqual(product[row], targetValue)
            }
        }
        
        do {
            let product = vector * matrix
            
            for column in 0..<4 {
                let targetValue = dot(matrix[column], vector)
                XCTAssertEqual(product[column], targetValue)
            }
        }
    }

    func testMat3Inverse() {
        let matrix = Matrix3x3<Float>(AffineMatrix<Float>.rotate(x: rad(10.0), y: rad(0.34), z: rad(42.0)))
        
        let product = matrix * matrix.inverse
        
        for row in 0..<3 {
            for col in 0..<3 {
                XCTAssertEqual(product[row, col], row == col ? 1.0 : 0.0, accuracy: 0.0001)
            }
        }
    }
    
    func testMat4Inverse() {
        let matrix = Matrix4x4<Float>.projLH(x: 3.0, y: 4.0, w: 10.0, h: 10.0, near: 0.1, far: 200.0)
        
        let product = matrix * matrix.inverse
        
        for row in 0..<4 {
            for col in 0..<4 {
                XCTAssertEqual(product[row, col], row == col ? 1.0 : 0.0, accuracy: 0.0001)
            }
        }
    }
    
    func testAffineMatrix2DDecomposition() {
        let scaleMatrix = AffineMatrix2D<Float>.scale(sx: 1.8, sy: 0.7)
        let theta = Angle<Float>(degrees: -48)
        let rotationMatrix = AffineMatrix2D<Float>.rotate(theta)
        let translationMatrix = AffineMatrix2D<Float>.translate(tx: 0.1, ty: -4.3)
        let trs = translationMatrix * rotationMatrix * scaleMatrix
        
        let decomposition = trs.polarDecomposition
        
        XCTAssertEqual(decomposition.translation.x, translationMatrix.c2.x, accuracy: 0.0001)
        XCTAssertEqual(decomposition.translation.y, translationMatrix.c2.y, accuracy: 0.0001)
        
        XCTAssertEqual(decomposition.rotation.radians, theta.radians, accuracy: 0.0001)
        
        XCTAssertEqual(decomposition.scale[0, 0], scaleMatrix[0, 0], accuracy: 0.0001)
        XCTAssertEqual(decomposition.scale[1, 1], scaleMatrix[1, 1], accuracy: 0.0001)
    }
}
