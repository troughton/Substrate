//
//  DependencyTableTests.swift
//  
//
//  Created by Thomas Roughton on 8/12/19.
//

import XCTest
@testable import SubstrateUtilities

class MatrixTests: XCTestCase {
    func testTransitiveReduction() {
        var matrix = DependencyTable(capacity: 4, defaultValue: false)
        matrix.setDependency(from: 1, on: 0, to: true)
        matrix.setDependency(from: 2, on: 1, to: true)
        matrix.setDependency(from: 3, on: 2, to: true)
        matrix.setDependency(from: 3, on: 0, to: true)
        matrix.formTransitiveReduction()
        
        XCTAssertTrue(matrix.dependency(from: 1, on: 0))
        XCTAssertTrue(matrix.dependency(from: 2, on: 1))
        XCTAssertTrue(matrix.dependency(from: 3, on: 2))
        XCTAssertFalse(matrix.dependency(from: 3, on: 0))
    }
}
