//
//  SplitTests.swift
//  
//
//  Created by Thomas Roughton on 23/11/22.
//

import XCTest
import SubstrateMath

final class SplineTests: XCTestCase {
    func testLinearPolynomial() throws {
        let polynomial = CubicPolynomial(centripetalCatmullRomWithPoints: 0.0, 0.0, 2.0, 2.0)
        XCTAssertEqual(0.0, polynomial.evaluate(at: 0.0))
        XCTAssertEqual(2.0, polynomial.evaluate(at: 1.0), accuracy: 0.001)
        XCTAssertEqual(1.0, polynomial.evaluate(at: 0.5), accuracy: 0.001)
        XCTAssertEqual(0.5, polynomial.evaluate(at: 0.25), accuracy: 0.001)
        XCTAssertEqual(1.5, polynomial.evaluate(at: 0.75), accuracy: 0.001)
    }

}
