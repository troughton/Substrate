//
//  GaussianBlur.swift
//  
//
//  Created by Thomas Roughton on 11/05/22.
//

import Foundation
import RealModule

extension Image where ComponentType == Float {

    private static func gaussianBlurWeights(sigma: Float, pixelRadius: Int) -> [Float] {
        let denom: Float = 1.0 / (Float.sqrt(2.0) * sigma)
        
        var weights = (0...pixelRadius).map { i -> Float in
            if i == 0 {
                return Float.erf(0.5 * denom)
            }
            return Float.erf((Float(i) + 0.5) * denom) - Float.erf((Float(i) - 0.5) * denom)
        }
        
        let totalWeight = weights.reduce(0, +)
        for i in weights.indices {
            weights[i] *= 0.5 / totalWeight // 0.5 to account for each half of the curve
        }
        
        return weights
    }
    
    
    private func weightsToWeightVector(weights: [Float]) -> [Float] {
        var weightsVector = [Float]()
        
        weightsVector.reserveCapacity(2 * weights.count - 1)
        weightsVector.append(contentsOf: weights.dropFirst().reversed())
        weightsVector.append(contentsOf: weights)
        
        return weightsVector
    }
    
    public func convolveHorizontal(weights: [Float], wrapMode: ImageEdgeWrapMode = .clamp, into result: inout Image<Float>) {
        precondition(result.width == self.width && result.height == self.height && result.channelCount == self.channelCount)
        
        typealias SIMDType<T: SIMDScalar> = SIMD4<T>
        let simdWidth = SIMDType<Float>.scalarCount
        
        let windowRadiusInclusive = weights.count
        let windowRadius = windowRadiusInclusive - 1
        var slidingWindow = [SIMDType<Float>](repeating: .zero, count: (2 * windowRadius + 1) * self.channelCount) // stored as e.g. (-2r, -1r, 0r, 1r, 2r, -2g, -1g etc.)
        
        let weightsVector = self.weightsToWeightVector(weights: weights)
        let windowWidth = weightsVector.count
        
        for yBase in stride(from: 0, to: self.height, by: simdWidth) {
            var yVector = SIMDType<Int>(repeating: yBase)
            for i in 1..<simdWidth {
                yVector[i] += i
            }
            let simdMask = yVector .< SIMDType(repeating: self.height)
            
            // Load the elements before the current pixel.
            for x in 0..<windowRadius {
                let wrappedCoord = self.computeWrappedCoordinate(x: x - windowRadius, y: yBase, wrapMode: wrapMode)
                
                for c in 0..<self.channelCount {
                    if let wrappedCoord = wrappedCoord {
                        for i in 0..<simdWidth {
                            slidingWindow[c * windowWidth + x][i] = simdMask[i] ? self[wrappedCoord.x, yVector[i], channel: c] : 0.0
                        }
                    } else {
                        slidingWindow[c * windowWidth + x] = .zero
                    }
                }
            }
            
            // Load the current pixel (x = 0)
            for c in 0..<self.channelCount {
                for i in 0..<simdWidth {
                    slidingWindow[c * windowWidth + windowRadius][i] = simdMask[i] ? self[0, yVector[i], channel: c] : 0.0
                }
            }
            
            // Fill the sliding window for the elements after pixel 0.
            for x in 1..<windowRadiusInclusive {
                let windowOffset = x + windowRadius
                let wrappedCoord = self.computeWrappedCoordinate(x: x, y: yBase, wrapMode: wrapMode)
                
                for c in 0..<self.channelCount {
                    if let wrappedCoord = wrappedCoord {
                        for i in 0..<simdWidth {
                            slidingWindow[c * windowWidth + windowOffset][i] = simdMask[i] ? self[wrappedCoord.x, yVector[i], channel: c] : 0.0
                        }
                    } else {
                        slidingWindow[c * windowWidth + windowOffset] = .zero
                    }
                }
            }
            
            // Convolve the middle section of the image.
            for x in 0..<Swift.max(self.width - windowRadiusInclusive, 0) {
                for c in 0..<self.channelCount {
                    for i in 0..<simdWidth where simdMask[i] {
                        precondition(slidingWindow[c * windowWidth + windowRadius][i] == self[x, yVector[i], channel: c])
                    }
                    
                    let dotVector = zip(weightsVector, slidingWindow.dropFirst(c * weightsVector.count))
                        .reduce(SIMDType<Float>.zero, {
                            // FIXME: should be addingProduct/fma, but we don't have a (convenient) way to enable SSE/Neon at compile time, so the resulting library call is a significant bottleneck.
                            // See https://github.com/apple/swift/issues/54069 for details.
                            $0 + $1.0 * $1.1
                        })
                    
                    for i in 0..<simdWidth where simdMask[i] {
                        result[x, yVector[i], channel: c] = dotVector[i]
                    }
                    
                    for i in 1..<windowWidth {
                        slidingWindow[c * windowWidth + i - 1] = slidingWindow[c * windowWidth + i]
                    }
                    
                    // Load the next pixel into the sliding window.
                    for i in 0..<simdWidth where simdMask[i] {
                        slidingWindow[c * windowWidth + windowWidth - 1][i] = self[x + windowRadiusInclusive, yVector[i], channel: c]
                    }
                }
            }
            
            // Now handle the end section where we need to clamp/wrap.
            for x in Swift.max(self.width - windowRadiusInclusive, 0)..<self.width {
                for c in 0..<self.channelCount {
                    let dotVector = zip(weightsVector, slidingWindow.dropFirst(c * weightsVector.count))
                        .reduce(SIMDType<Float>.zero, {
                            // FIXME: should be addingProduct/fma, but we don't have a (convenient) way to enable SSE/Neon at compile time, so the resulting library call is a significant bottleneck.
                            // See https://github.com/apple/swift/issues/54069 for details.
                            $0 + $1.0 * $1.1
                        })
                    
                    for i in 0..<simdWidth where simdMask[i] {
                        result[x, yVector[i], channel: c] = dotVector[i]
                    }
                    
                    for i in 1..<windowWidth {
                        slidingWindow[c * windowWidth + i - 1] = slidingWindow[c * windowWidth + i]
                    }
                    
                    if let wrappedCoord = self.computeWrappedCoordinate(x: x + windowRadiusInclusive, y: yBase, wrapMode: wrapMode) {
                        for i in 0..<simdWidth {
                            slidingWindow[c * windowWidth + windowWidth - 1][i] = simdMask[i] ? self[wrappedCoord.x, yVector[i], channel: c] : 0.0
                        }
                    } else {
                        slidingWindow[c * windowWidth + windowWidth - 1] = .zero
                    }
                }
            }
        }
    }
    
    public func convolveVertical(weights: [Float], wrapMode: ImageEdgeWrapMode = .clamp, into result: inout Image<Float>) {
        precondition(result.width == self.width && result.height == self.height && result.channelCount == self.channelCount)
        
        typealias SIMDType<T: SIMDScalar> = SIMD4<T>
        let simdWidth = SIMDType<Float>.scalarCount
        
        let windowRadiusInclusive = weights.count
        let windowRadius = windowRadiusInclusive - 1
        var slidingWindow = [SIMDType<Float>](repeating: .zero, count: (2 * windowRadius + 1) * self.channelCount) // stored as e.g. (-2r, -1r, 0r, 1r, 2r, -2g, -1g etc.)
        
        let weightsVector = self.weightsToWeightVector(weights: weights)
        let windowWidth = weightsVector.count
        
        for xBase in stride(from: 0, to: self.width, by: simdWidth) {
            var xVector = SIMDType(repeating: xBase)
            for i in 1..<simdWidth {
                xVector[i] += i
            }
            let simdMask = xVector .< SIMDType(repeating: self.width)
            
            // Load the elements before the current pixel.
            for y in 0..<windowRadius {
                let wrappedCoord = self.computeWrappedCoordinate(x: xBase, y: y - windowRadius, wrapMode: wrapMode)
                
                for c in 0..<self.channelCount {
                    if let wrappedCoord = wrappedCoord {
                        for i in 0..<simdWidth {
                            slidingWindow[c * windowWidth + y][i] = simdMask[i] ? self[xVector[i], wrappedCoord.y, channel: c] : 0.0
                        }
                    } else {
                        slidingWindow[c * windowWidth + y] = .zero
                    }
                }
            }
            
            // Load the current pixel (x = 0)
            for c in 0..<self.channelCount {
                for i in 0..<simdWidth {
                    slidingWindow[c * windowWidth + windowRadius][i] = simdMask[i] ? self[xVector[i], 0, channel: c] : 0.0
                }
            }
            
            // Fill the sliding window for the elements after pixel 0.
            for y in 1..<windowRadiusInclusive {
                let windowOffset = y + windowRadius
                let wrappedCoord = self.computeWrappedCoordinate(x: xBase, y: y, wrapMode: wrapMode)
                
                for c in 0..<self.channelCount {
                    if let wrappedCoord = wrappedCoord {
                        for i in 0..<simdWidth {
                            slidingWindow[c * windowWidth + windowOffset][i] = simdMask[i] ? self[xVector[i], wrappedCoord.y, channel: c] : 0.0
                        }
                    } else {
                        slidingWindow[c * windowWidth + windowOffset] = .zero
                    }
                }
            }
            
            // Convolve the middle section of the image.
            for y in 0..<Swift.max(self.height - windowRadiusInclusive, 0) {
                for c in 0..<self.channelCount {
                    let dotVector = zip(weightsVector, slidingWindow.dropFirst(c * weightsVector.count))
                        .reduce(SIMDType<Float>.zero, {
                            // FIXME: should be addingProduct/fma, but we don't have a (convenient) way to enable SSE/Neon at compile time, so the resulting library call is a significant bottleneck.
                            // See https://github.com/apple/swift/issues/54069 for details.
                            $0 + $1.0 * $1.1
                        })
                    
                    for i in 0..<simdWidth where simdMask[i] {
                        result[xVector[i], y, channel: c] = dotVector[i]
                    }
                    
                    for i in 1..<windowWidth {
                        slidingWindow[c * windowWidth + i - 1] = slidingWindow[c * windowWidth + i]
                    }
                    
                    // Load the next pixel into the sliding window.
                    for i in 0..<simdWidth where simdMask[i] {
                        slidingWindow[c * windowWidth + windowWidth - 1][i] = self[xVector[i], y + windowRadiusInclusive, channel: c]
                    }
                }
            }
            
            // Now handle the end section where we need to clamp/wrap.
            for y in Swift.max(self.height - windowRadiusInclusive, 0)..<self.height {
                for c in 0..<self.channelCount {
                    let dotVector = zip(weightsVector, slidingWindow.dropFirst(c * weightsVector.count))
                        .reduce(SIMDType<Float>.zero, {
                            // FIXME: should be addingProduct/fma, but we don't have a (convenient) way to enable SSE/Neon at compile time, so the resulting library call is a significant bottleneck.
                            // See https://github.com/apple/swift/issues/54069 for details.
                            $0 + $1.0 * $1.1
                        })
                    
                    for i in 0..<simdWidth where simdMask[i] {
                        result[xVector[i], y, channel: c] = dotVector[i]
                    }
                    
                    for i in 1..<windowWidth {
                        slidingWindow[c * windowWidth + i - 1] = slidingWindow[c * windowWidth + i]
                    }
                    
                    if let wrappedCoord = self.computeWrappedCoordinate(x: xBase, y: y + windowRadiusInclusive, wrapMode: wrapMode) {
                        for i in 0..<simdWidth {
                            slidingWindow[c * windowWidth + windowWidth - 1][i] = simdMask[i] ? self[xVector[i], wrappedCoord.y, channel: c] : 0.0
                        }
                    } else {
                        slidingWindow[c * windowWidth + windowWidth - 1] = .zero
                    }
                }
            }
        }
    }
    
    public func convolveHorizontal(weights: [Float], wrapMode: ImageEdgeWrapMode = .clamp) -> Image<Float> {
        var result = Image(width: self.width, height: self.height, channelCount: self.channelCount, colorSpace: self.colorSpace, alphaMode: self.alphaMode)
        self.convolveHorizontal(weights: weights, wrapMode: wrapMode, into: &result)
        return result
    }
    
    public func convolveVertical(weights: [Float], wrapMode: ImageEdgeWrapMode = .clamp) -> Image<Float> {
        var result = Image(width: self.width, height: self.height, channelCount: self.channelCount, colorSpace: self.colorSpace, alphaMode: self.alphaMode)
        self.convolveVertical(weights: weights, wrapMode: wrapMode, into: &result)
        return result
    }
    
    public mutating func gaussianBlur(sigmaX: Float, sigmaY: Float, wrapMode: ImageEdgeWrapMode = .clamp) {
        if sigmaX == sigmaY {
            let weights = Self.gaussianBlurWeights(sigma: sigmaX, pixelRadius: Int((3.0 * sigmaX).rounded(.up)))
            let result = self.convolveHorizontal(weights: weights, wrapMode: wrapMode)
            result.convolveVertical(weights: weights, wrapMode: wrapMode, into: &self)
        } else {
            let result = self.convolveHorizontal(weights: Self.gaussianBlurWeights(sigma: sigmaX, pixelRadius: Int((3.0 * sigmaX).rounded(.up))), wrapMode: wrapMode)
            result.convolveVertical(weights: Self.gaussianBlurWeights(sigma: sigmaY, pixelRadius: Int((3.0 * sigmaY).rounded(.up))), wrapMode: wrapMode, into: &self)
        }
    }
    
    public mutating func gaussianBlur(sigma: Float, wrapMode: ImageEdgeWrapMode = .clamp) {
        self.gaussianBlur(sigmaX: sigma, sigmaY: sigma, wrapMode: wrapMode)
    }
}
