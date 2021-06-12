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
        var image = Image<Float>(width: 73, height: 28, channels: 4, colorSpace: .linearSRGB, alphaMode: .premultiplied)
        image.apply({ _ in 0.5 }, channelRange: 0..<3)
        image.apply({ _ in 1.0 }, channelRange: 3..<4)
        
        let testImage = try! Image<Float>(data: image.exrData())
        XCTAssertEqual(image, testImage)
    }
}
