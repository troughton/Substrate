//
//  File.swift
//  
//
//  Created by Thomas Roughton on 30/04/22.
//

import Foundation
import XCTest
@testable import SubstrateImage

class PixelViewTests: XCTestCase {
    
    func testPixelView() {
        for channelCount in 1...4 {
            var image = Image<UInt32>(width: 489, height: 233, channelCount: channelCount, colorSpace: .linearSRGB, alphaMode: .none)
            image.apply { _ in UInt32.random(in: 0..<UInt32.max) }
            
            var xorResult = 0 as UInt32
            
            for y in 0..<image.height {
                for x in 0..<image.width {
                    for c in 0..<image.channelCount {
                        xorResult |= image[x, y, channel: c]
                    }
                }
            }
            
            var xorResult2 = 0 as UInt32
            for (x, y, _, pixelValue) in image {
                xorResult2 |= pixelValue
            }
            
            XCTAssertEqual(xorResult, xorResult2)
            
            
            var xorResult3 = 0 as UInt32
            for (x, y, pixelValue) in image.pixels {
                for c in 0..<image.channelCount {
                    xorResult3 |= pixelValue[c]
                }
            }
            
            XCTAssertEqual(xorResult, xorResult3)
        }
    }
}
