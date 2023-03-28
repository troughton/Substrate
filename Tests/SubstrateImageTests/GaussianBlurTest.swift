//
//  GaussianBlurTest.swift
//  
//
//  Created by Thomas Roughton on 28/03/23.
//

import XCTest
import SubstrateImage

final class GaussianBlurTest: XCTestCase {

    var inputImage: Image<Float>! = nil
    var inputMask: Image<Float>! = nil
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        var inputImage = Image<Float>(width: 1024, height: 1023, channelCount: 4)
        inputImage.apply { _ in Float.random(in: 0...1) }
        self.inputImage = inputImage
        
        var inputMask = Image<Float>(width: 1024, height: 1023, channelCount: 1)
        inputMask.apply { _ in Float.random(in: 0...1) }
        self.inputMask = inputMask
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testBlurPerformance() throws {
        var imageToBlur = self.inputImage!
        imageToBlur.withUnsafeMutableBufferPointer { _ in } // trigger CoW
        
        self.measure {
            // Put the code you want to measure the time of here.
            imageToBlur.gaussianBlur(sigma: 40.0, wrapMode: .clamp)
        }
    }
    
    func testMaskedBlurPerformance() throws {
        var imageToBlur = self.inputImage!
        imageToBlur.withUnsafeMutableBufferPointer { _ in } // trigger CoW
        
        self.measure {
            // Put the code you want to measure the time of here.
            imageToBlur.gaussianBlur(sigma: 40.0, weightsImage: self.inputMask, wrapMode: .clamp)
        }
    }

}
