//
//  MatrixTests.swift
//  
//
//  Created by Thomas Roughton on 8/12/19.
//

import XCTest
@testable import SubstrateImage

class ImageIOTests: XCTestCase {
    
    func testEXRRoundTrip() {
        var image = Image<Float>(width: 73, height: 28, channelCount: 4, colorSpace: .linearSRGB, alphaMode: .premultiplied)
        image.apply(channelRange: 0..<3) { _ in 0.5 }
        image.apply(channelRange: 3..<4) { _ in 1.0 }
        
        let testImage = try! Image<Float>(data: image.exrData())
        XCTAssertEqual(image, testImage)
    }
}
