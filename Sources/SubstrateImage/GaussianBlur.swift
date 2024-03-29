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
    
    // General version; about 40% slower when pixelWeight != nil and about 5% slower when it is nil (due to the pixelSwizzle).
    @inline(__always)
    func _convolve(weights: [Float], wrapMode: ImageEdgeWrapMode = .clamp, pixelSwizzle: SIMD2<Int>, pixelWeight: ((_ x: Int, _ y: Int) -> Float)? = nil, into result: inout Image<Float>) {
        precondition(result.width == self.width && result.height == self.height && result.channelCount == self.channelCount)
        
        result.ensureUniqueness() // so we can use the setUnchecked methods.
        
        let inputBuffer = self.storage.data
        let resultBuffer = result.storage.data
        
        typealias SIMDType<T: SIMDScalar> = SIMD8<T>
        let simdWidth = SIMDType<Float>.scalarCount
        
        let windowRadiusInclusive = weights.count
        let windowRadius = windowRadiusInclusive - 1
        
        let weightsVector = self.weightsToWeightVector(weights: weights)
        let windowWidth = weightsVector.count
        
        let dimensions = SIMD2(self.width, self.height)
        let swizzledDimensions = dimensions[pixelSwizzle]
        
        let strideDimension = swizzledDimensions.y
        
        let slidingWindowCount = (2 * windowRadius + 1) * self.channelCount
        let pixelWeightsSlidingWindowCount = pixelWeight != nil ? (2 * windowRadius + 1) : 0
        
        withUnsafeTemporaryAllocation(byteCount: (slidingWindowCount + pixelWeightsSlidingWindowCount) * MemoryLayout<SIMDType<Float>>.stride, alignment: MemoryLayout<SIMDType<Float>>.alignment) { slidingWindow in
            let slidingWindow = slidingWindow.bindMemory(to: SIMDType<Float>.self)
            let pixelWeightsSlidingWindow = UnsafeMutableBufferPointer(rebasing: slidingWindow.dropFirst(slidingWindowCount))
            
            for base in stride(from: 0, to: strideDimension, by: simdWidth) {
                var normalVector = SIMDType<Int>(repeating: base)
                for i in 1..<simdWidth {
                    normalVector[i] += i
                }
                let simdMask = normalVector .< SIMDType(repeating: strideDimension)
                
                // Load the elements before the current pixel.
                for windowI in 0..<windowRadius {
                    let wrappedCoord = self.computeWrappedCoordinate(coord: windowI - windowRadius, size: swizzledDimensions.x, wrapMode: wrapMode)
                    
                    for c in 0..<self.channelCount {
                        if let wrappedCoord = wrappedCoord {
                            for i in 0..<simdWidth {
                                let pixel = SIMD2(wrappedCoord, normalVector[i])[pixelSwizzle]
                                slidingWindow[c * windowWidth + windowI][i] = simdMask[i] ? inputBuffer[self.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] : 0.0
                            }
                        } else {
                            slidingWindow[c * windowWidth + windowI] = .zero
                        }
                    }
                    
                    if let pixelWeight = pixelWeight {
                        if let wrappedCoord = wrappedCoord {
                            for i in 0..<simdWidth {
                                let pixel = SIMD2(wrappedCoord, normalVector[i])[pixelSwizzle]
                                pixelWeightsSlidingWindow[windowI][i] = simdMask[i] ? pixelWeight(pixel.x, pixel.y) : 0.0
                            }
                        } else {
                            pixelWeightsSlidingWindow[windowI] = .zero
                        }
                    }
                }
                
                // Load the current pixel (x = 0)
                for c in 0..<self.channelCount {
                    for i in 0..<simdWidth {
                        let pixel = SIMD2(0, normalVector[i])[pixelSwizzle]
                        slidingWindow[c * windowWidth + windowRadius][i] = simdMask[i] ? inputBuffer[self.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] : 0.0
                        
                        if let pixelWeight = pixelWeight {
                            pixelWeightsSlidingWindow[windowRadius][i] = simdMask[i] ? pixelWeight(pixel.x, pixel.y) : 0.0
                        }
                    }
                }
                
                // Fill the sliding window for the elements after pixel 0.
                for windowI in 1..<windowRadiusInclusive {
                    let windowOffset = windowI + windowRadius
                    let wrappedCoord = self.computeWrappedCoordinate(coord: windowI, size: swizzledDimensions.x, wrapMode: wrapMode)
                    
                    for c in 0..<self.channelCount {
                        if let wrappedCoord = wrappedCoord {
                            for i in 0..<simdWidth {
                                let pixel = SIMD2(wrappedCoord, normalVector[i])[pixelSwizzle]
                                slidingWindow[c * windowWidth + windowOffset][i] = simdMask[i] ? inputBuffer[self.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] : 0.0
                            }
                        } else {
                            slidingWindow[c * windowWidth + windowOffset] = .zero
                        }
                    }
                    
                    if let pixelWeight = pixelWeight {
                        if let wrappedCoord = wrappedCoord {
                            for i in 0..<simdWidth {
                                let pixel = SIMD2(wrappedCoord, normalVector[i])[pixelSwizzle]
                                pixelWeightsSlidingWindow[windowOffset][i] = simdMask[i] ? pixelWeight(pixel.x, pixel.y) : 0.0
                            }
                        } else {
                            pixelWeightsSlidingWindow[windowOffset] = .zero
                        }
                    }
                }
                
                // Convolve the middle section of the image.
                for windowI in 0..<Swift.max(swizzledDimensions.x - windowRadiusInclusive, 0) {
                    for c in 0..<self.channelCount {
                        var dotVector: SIMDType<Float> = .zero
                        
                        if pixelWeight != nil {
                            var pixelWeights: SIMDType<Float> = .zero
                            for i in 0..<windowWidth {
                                let weightsProduct = weightsVector[i] * pixelWeightsSlidingWindow[i]
                                pixelWeights += weightsProduct
#if SUBSTRATE_IMAGE_FMA || arch(arm64)
                                dotVector.addProduct(weightsProduct, slidingWindow[c * windowWidth + i])
#else
                                dotVector += weightsProduct * slidingWindow[c * windowWidth + i]
#endif
                            }
                            dotVector /= pixelWeights.replacing(with: .ulpOfOne, where: pixelWeights .== .zero)
                            
                            let pixelWeight = pixelWeightsSlidingWindow[windowRadius]
                            dotVector = (SIMDType<Float>.one - pixelWeight) * slidingWindow[c * windowWidth + windowRadius] + pixelWeight * dotVector
                        } else {
                            for i in 0..<windowWidth {
#if SUBSTRATE_IMAGE_FMA || arch(arm64)
                                dotVector.addProduct(SIMDType(repeating: weightsVector[i]), slidingWindow[c * windowWidth + i])
#else
                                dotVector += weightsVector[i] * slidingWindow[c * windowWidth + i]
#endif
                            }
                        }
                        
                        for i in 0..<simdWidth where simdMask[i] {
                            let pixel = SIMD2(windowI, normalVector[i])[pixelSwizzle]
                            resultBuffer[result.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] = dotVector[i]
                        }
                        
                        for i in 1..<windowWidth {
                            slidingWindow[c * windowWidth + i - 1] = slidingWindow[c * windowWidth + i]
                        }
                        
                        // Load the next pixel into the sliding window.
                        for i in 0..<simdWidth where simdMask[i] {
                            let pixel = SIMD2(windowI + windowRadiusInclusive, normalVector[i])[pixelSwizzle]
                            slidingWindow[c * windowWidth + windowWidth - 1][i] = inputBuffer[self.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)]
                        }
                    }
                    
                    if let pixelWeight = pixelWeight {
                        for i in 1..<windowWidth {
                            pixelWeightsSlidingWindow[i - 1] = pixelWeightsSlidingWindow[i]
                        }
                        
                        // Load the next pixel into the sliding window.
                        for i in 0..<simdWidth where simdMask[i] {
                            let pixel = SIMD2(windowI + windowRadiusInclusive, normalVector[i])[pixelSwizzle]
                            pixelWeightsSlidingWindow[windowWidth - 1][i] = pixelWeight(pixel.x, pixel.y)
                        }
                    }
                }
                
                // Now handle the end section where we need to clamp/wrap.
                for windowI in Swift.max(swizzledDimensions.x - windowRadiusInclusive, 0)..<swizzledDimensions.x {
                    for c in 0..<self.channelCount {
                        var dotVector = SIMDType<Float>.zero
                        
                        if pixelWeight != nil {
                            var pixelWeights: SIMDType<Float> = .zero
                            for i in 0..<windowWidth {
                                let weightsProduct = weightsVector[i] * pixelWeightsSlidingWindow[i]
                                pixelWeights += weightsProduct
#if SUBSTRATE_IMAGE_FMA || arch(arm64)
                                dotVector.addProduct(weightsProduct, slidingWindow[c * windowWidth + i])
#else
                                dotVector += weightsProduct * slidingWindow[c * windowWidth + i]
#endif
                            }
                            dotVector /= pixelWeights.replacing(with: .ulpOfOne, where: pixelWeights .== .zero)
                            
                            let pixelWeight = pixelWeightsSlidingWindow[windowRadius]
                            dotVector = (SIMDType<Float>.one - pixelWeight) * slidingWindow[c * windowWidth + windowRadius] + pixelWeight * dotVector
                        } else {
                            for i in 0..<windowWidth {
#if SUBSTRATE_IMAGE_FMA || arch(arm64)
                                dotVector.addProduct(SIMDType(repeating: weightsVector[i]), slidingWindow[c * windowWidth + i])
#else
                                dotVector += weightsVector[i] * slidingWindow[c * windowWidth + i]
#endif
                            }
                        }
                        
                        for i in 0..<simdWidth where simdMask[i] {
                            let pixel = SIMD2(windowI, normalVector[i])[pixelSwizzle]
                            resultBuffer[result.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] = dotVector[i]
                        }
                        
                        for i in 1..<windowWidth {
                            slidingWindow[c * windowWidth + i - 1] = slidingWindow[c * windowWidth + i]
                        }
                        
                        if let wrappedCoord = self.computeWrappedCoordinate(coord: windowI + windowRadiusInclusive, size: swizzledDimensions.x, wrapMode: wrapMode) {
                            for i in 0..<simdWidth {
                                let pixel = SIMD2(wrappedCoord, normalVector[i])[pixelSwizzle]
                                slidingWindow[c * windowWidth + windowWidth - 1][i] = simdMask[i] ? inputBuffer[self.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] : 0.0
                            }
                        } else {
                            slidingWindow[c * windowWidth + windowWidth - 1] = .zero
                        }
                        
                        if let pixelWeight = pixelWeight {
                            for i in 1..<windowWidth {
                                pixelWeightsSlidingWindow[i - 1] = pixelWeightsSlidingWindow[i]
                            }
                            
                            if let wrappedCoord = self.computeWrappedCoordinate(coord: windowI + windowRadiusInclusive, size: swizzledDimensions.x, wrapMode: wrapMode) {
                                for i in 0..<simdWidth {
                                    let pixel = SIMD2(wrappedCoord, normalVector[i])[pixelSwizzle]
                                    pixelWeightsSlidingWindow[windowWidth - 1][i] = simdMask[i] ? pixelWeight(pixel.x, pixel.y) : 0.0
                                }
                            } else {
                                pixelWeightsSlidingWindow[windowWidth - 1] = .zero
                            }
                        }
                    }
                }
            }
        }
    }
    
    func _convolveX(weights: [Float], wrapMode: ImageEdgeWrapMode = .clamp, into result: inout Image<Float>) {
        precondition(result.width == self.width && result.height == self.height && result.channelCount == self.channelCount)
        
        result.ensureUniqueness() // so we can use the setUnchecked methods.
        
        let inputBuffer = self.storage.data
        let resultBuffer = result.storage.data
        
        typealias SIMDType<T: SIMDScalar> = SIMD8<T>
        let simdWidth = SIMDType<Float>.scalarCount
        
        let windowRadiusInclusive = weights.count
        let windowRadius = windowRadiusInclusive - 1
        
        let weightsVector = self.weightsToWeightVector(weights: weights)
        let windowWidth = weightsVector.count
        
        let dimensions = SIMD2(self.width, self.height)
        let swizzledDimensions = dimensions
        
        let strideDimension = swizzledDimensions.y
        
        let slidingWindowCount = (2 * windowRadius + 1) * self.channelCount
        
        withUnsafeTemporaryAllocation(byteCount: (slidingWindowCount) * MemoryLayout<SIMDType<Float>>.stride, alignment: MemoryLayout<SIMDType<Float>>.alignment) { slidingWindow in
            let slidingWindow = slidingWindow.bindMemory(to: SIMDType<Float>.self)
            
            for base in stride(from: 0, to: strideDimension, by: simdWidth) {
                var normalVector = SIMDType<Int>(repeating: base)
                for i in 1..<simdWidth {
                    normalVector[i] += i
                }
                let simdMask = normalVector .< SIMDType(repeating: strideDimension)
                
                // Load the elements before the current pixel.
                for windowI in 0..<windowRadius {
                    let wrappedCoord = self.computeWrappedCoordinate(coord: windowI - windowRadius, size: swizzledDimensions.x, wrapMode: wrapMode)
                    
                    for c in 0..<self.channelCount {
                        if let wrappedCoord = wrappedCoord {
                            for i in 0..<simdWidth {
                                let pixel = SIMD2(wrappedCoord, normalVector[i])
                                slidingWindow[c * windowWidth + windowI][i] = simdMask[i] ? inputBuffer[self.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] : 0.0
                            }
                        } else {
                            slidingWindow[c * windowWidth + windowI] = .zero
                        }
                    }
                }
                
                // Load the current pixel (x = 0)
                for c in 0..<self.channelCount {
                    for i in 0..<simdWidth {
                        let pixel = SIMD2(0, normalVector[i])
                        slidingWindow[c * windowWidth + windowRadius][i] = simdMask[i] ? inputBuffer[self.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] : 0.0
                    }
                }
                
                // Fill the sliding window for the elements after pixel 0.
                for windowI in 1..<windowRadiusInclusive {
                    let windowOffset = windowI + windowRadius
                    let wrappedCoord = self.computeWrappedCoordinate(coord: windowI, size: swizzledDimensions.x, wrapMode: wrapMode)
                    
                    for c in 0..<self.channelCount {
                        if let wrappedCoord = wrappedCoord {
                            for i in 0..<simdWidth {
                                let pixel = SIMD2(wrappedCoord, normalVector[i])
                                slidingWindow[c * windowWidth + windowOffset][i] = simdMask[i] ? inputBuffer[self.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] : 0.0
                            }
                        } else {
                            slidingWindow[c * windowWidth + windowOffset] = .zero
                        }
                    }
                }
                
                // Convolve the middle section of the image.
                for windowI in 0..<Swift.max(swizzledDimensions.x - windowRadiusInclusive, 0) {
                    for c in 0..<self.channelCount {
                        var dotVector: SIMDType<Float> = .zero
                        
                        for i in 0..<windowWidth {
#if SUBSTRATE_IMAGE_FMA || arch(arm64)
                            dotVector.addProduct(SIMDType(repeating: weightsVector[i]), slidingWindow[c * windowWidth + i])
#else
                            dotVector += weightsVector[i] * slidingWindow[c * windowWidth + i]
#endif
                        }
                        
                        for i in 0..<simdWidth where simdMask[i] {
                            let pixel = SIMD2(windowI, normalVector[i])
                            resultBuffer[result.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] = dotVector[i]
                        }
                        
                        for i in 1..<windowWidth {
                            slidingWindow[c * windowWidth + i - 1] = slidingWindow[c * windowWidth + i]
                        }
                        
                        // Load the next pixel into the sliding window.
                        for i in 0..<simdWidth where simdMask[i] {
                            let pixel = SIMD2(windowI + windowRadiusInclusive, normalVector[i])
                            slidingWindow[c * windowWidth + windowWidth - 1][i] = inputBuffer[self.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)]
                        }
                    }
                }
                
                // Now handle the end section where we need to clamp/wrap.
                for windowI in Swift.max(swizzledDimensions.x - windowRadiusInclusive, 0)..<swizzledDimensions.x {
                    for c in 0..<self.channelCount {
                        var dotVector = SIMDType<Float>.zero
                        
                        for i in 0..<windowWidth {
#if SUBSTRATE_IMAGE_FMA || arch(arm64)
                            dotVector.addProduct(SIMDType(repeating: weightsVector[i]), slidingWindow[c * windowWidth + i])
#else
                            dotVector += weightsVector[i] * slidingWindow[c * windowWidth + i]
#endif
                        }
                        
                        for i in 0..<simdWidth where simdMask[i] {
                            let pixel = SIMD2(windowI, normalVector[i])
                            resultBuffer[result.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] = dotVector[i]
                        }
                        
                        for i in 1..<windowWidth {
                            slidingWindow[c * windowWidth + i - 1] = slidingWindow[c * windowWidth + i]
                        }
                        
                        if let wrappedCoord = self.computeWrappedCoordinate(coord: windowI + windowRadiusInclusive, size: swizzledDimensions.x, wrapMode: wrapMode) {
                            for i in 0..<simdWidth {
                                let pixel = SIMD2(wrappedCoord, normalVector[i])
                                slidingWindow[c * windowWidth + windowWidth - 1][i] = simdMask[i] ? inputBuffer[self.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] : 0.0
                            }
                        } else {
                            slidingWindow[c * windowWidth + windowWidth - 1] = .zero
                        }
                    }
                }
            }
        }
    }
    
    func _convolveY(weights: [Float], wrapMode: ImageEdgeWrapMode = .clamp, into result: inout Image<Float>) {
        precondition(result.width == self.width && result.height == self.height && result.channelCount == self.channelCount)
        
        result.ensureUniqueness() // so we can use the setUnchecked methods.
        
        let inputBuffer = self.storage.data
        let resultBuffer = result.storage.data
        
        typealias SIMDType<T: SIMDScalar> = SIMD8<T>
        let simdWidth = SIMDType<Float>.scalarCount
        
        let windowRadiusInclusive = weights.count
        let windowRadius = windowRadiusInclusive - 1
        
        let weightsVector = self.weightsToWeightVector(weights: weights)
        let windowWidth = weightsVector.count
        
        let dimensions = SIMD2(self.width, self.height)
        let swizzledDimensions = SIMD2(self.height, self.width)
        
        let strideDimension = swizzledDimensions.y
        
        let slidingWindowCount = (2 * windowRadius + 1) * self.channelCount
        
        withUnsafeTemporaryAllocation(byteCount: (slidingWindowCount) * MemoryLayout<SIMDType<Float>>.stride, alignment: MemoryLayout<SIMDType<Float>>.alignment) { slidingWindow in
            let slidingWindow = slidingWindow.bindMemory(to: SIMDType<Float>.self)
            
            for base in stride(from: 0, to: strideDimension, by: simdWidth) {
                var normalVector = SIMDType<Int>(repeating: base)
                for i in 1..<simdWidth {
                    normalVector[i] += i
                }
                let simdMask = normalVector .< SIMDType(repeating: strideDimension)
                
                // Load the elements before the current pixel.
                for windowI in 0..<windowRadius {
                    let wrappedCoord = self.computeWrappedCoordinate(coord: windowI - windowRadius, size: swizzledDimensions.x, wrapMode: wrapMode)
                    
                    for c in 0..<self.channelCount {
                        if let wrappedCoord = wrappedCoord {
                            for i in 0..<simdWidth {
                                let pixel = SIMD2(normalVector[i], wrappedCoord)
                                slidingWindow[c * windowWidth + windowI][i] = simdMask[i] ? inputBuffer[self.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] : 0.0
                            }
                        } else {
                            slidingWindow[c * windowWidth + windowI] = .zero
                        }
                    }
                }
                
                // Load the current pixel (x = 0)
                for c in 0..<self.channelCount {
                    for i in 0..<simdWidth {
                        let pixel = SIMD2(normalVector[i], 0)
                        slidingWindow[c * windowWidth + windowRadius][i] = simdMask[i] ? inputBuffer[self.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] : 0.0
                    }
                }
                
                // Fill the sliding window for the elements after pixel 0.
                for windowI in 1..<windowRadiusInclusive {
                    let windowOffset = windowI + windowRadius
                    let wrappedCoord = self.computeWrappedCoordinate(coord: windowI, size: swizzledDimensions.x, wrapMode: wrapMode)
                    
                    for c in 0..<self.channelCount {
                        if let wrappedCoord = wrappedCoord {
                            for i in 0..<simdWidth {
                                let pixel = SIMD2(normalVector[i], wrappedCoord)
                                slidingWindow[c * windowWidth + windowOffset][i] = simdMask[i] ? inputBuffer[self.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] : 0.0
                            }
                        } else {
                            slidingWindow[c * windowWidth + windowOffset] = .zero
                        }
                    }
                }
                
                // Convolve the middle section of the image.
                for windowI in 0..<Swift.max(swizzledDimensions.x - windowRadiusInclusive, 0) {
                    for c in 0..<self.channelCount {
                        var dotVector: SIMDType<Float> = .zero
                        
                        for i in 0..<windowWidth {
#if SUBSTRATE_IMAGE_FMA || arch(arm64)
                            dotVector.addProduct(SIMDType(repeating: weightsVector[i]), slidingWindow[c * windowWidth + i])
#else
                            dotVector += weightsVector[i] * slidingWindow[c * windowWidth + i]
#endif
                        }
                        
                        for i in 0..<simdWidth where simdMask[i] {
                            let pixel = SIMD2(normalVector[i], windowI)
                            resultBuffer[result.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] = dotVector[i]
                        }
                        
                        for i in 1..<windowWidth {
                            slidingWindow[c * windowWidth + i - 1] = slidingWindow[c * windowWidth + i]
                        }
                        
                        // Load the next pixel into the sliding window.
                        for i in 0..<simdWidth where simdMask[i] {
                            let pixel = SIMD2(normalVector[i], windowI + windowRadiusInclusive)
                            slidingWindow[c * windowWidth + windowWidth - 1][i] = inputBuffer[self.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)]
                        }
                    }
                }
                
                // Now handle the end section where we need to clamp/wrap.
                for windowI in Swift.max(swizzledDimensions.x - windowRadiusInclusive, 0)..<swizzledDimensions.x {
                    for c in 0..<self.channelCount {
                        var dotVector = SIMDType<Float>.zero
                        
                        for i in 0..<windowWidth {
#if SUBSTRATE_IMAGE_FMA || arch(arm64)
                            dotVector.addProduct(SIMDType(repeating: weightsVector[i]), slidingWindow[c * windowWidth + i])
#else
                            dotVector += weightsVector[i] * slidingWindow[c * windowWidth + i]
#endif
                        }
                        
                        for i in 0..<simdWidth where simdMask[i] {
                            let pixel = SIMD2(normalVector[i], windowI)
                            resultBuffer[result.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] = dotVector[i]
                        }
                        
                        for i in 1..<windowWidth {
                            slidingWindow[c * windowWidth + i - 1] = slidingWindow[c * windowWidth + i]
                        }
                        
                        if let wrappedCoord = self.computeWrappedCoordinate(coord: windowI + windowRadiusInclusive, size: swizzledDimensions.x, wrapMode: wrapMode) {
                            for i in 0..<simdWidth {
                                let pixel = SIMD2(normalVector[i], wrappedCoord)
                                slidingWindow[c * windowWidth + windowWidth - 1][i] = simdMask[i] ? inputBuffer[self.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] : 0.0
                            }
                        } else {
                            slidingWindow[c * windowWidth + windowWidth - 1] = .zero
                        }
                    }
                }
            }
        }
    }
    
    func _convolveX(weights: [Float], wrapMode: ImageEdgeWrapMode = .clamp, pixelWeightImage: Image<Float>, into result: inout Image<Float>) {
        precondition(result.width == self.width && result.height == self.height && result.channelCount == self.channelCount)
        precondition(pixelWeightImage.width == self.width && pixelWeightImage.height == self.height)
        precondition(pixelWeightImage.channelCount == 1)
        
        result.ensureUniqueness() // so we can use the setUnchecked methods.
        
        let inputBuffer = self.storage.data
        let resultBuffer = result.storage.data
        let pixelWeightsBuffer = pixelWeightImage.storage.data
        
        typealias SIMDType<T: SIMDScalar> = SIMD8<T>
        let simdWidth = SIMDType<Float>.scalarCount
        
        let windowRadiusInclusive = weights.count
        let windowRadius = windowRadiusInclusive - 1
        
        let weightsVector = self.weightsToWeightVector(weights: weights)
        let windowWidth = weightsVector.count
        
        let dimensions = SIMD2(self.width, self.height)
        let swizzledDimensions = dimensions
        
        let strideDimension = swizzledDimensions.y
        
        let slidingWindowCount = (2 * windowRadius + 1) * self.channelCount
        let pixelWeightsSlidingWindowCount = (2 * windowRadius + 1)
        
        withUnsafeTemporaryAllocation(byteCount: (slidingWindowCount + pixelWeightsSlidingWindowCount) * MemoryLayout<SIMDType<Float>>.stride, alignment: MemoryLayout<SIMDType<Float>>.alignment) { slidingWindow in
            let slidingWindow = slidingWindow.bindMemory(to: SIMDType<Float>.self)
            let pixelWeightsSlidingWindow = UnsafeMutableBufferPointer(rebasing: slidingWindow.dropFirst(slidingWindowCount))
            
            for base in stride(from: 0, to: strideDimension, by: simdWidth) {
                var normalVector = SIMDType<Int>(repeating: base)
                for i in 1..<simdWidth {
                    normalVector[i] += i
                }
                let simdMask = normalVector .< SIMDType(repeating: strideDimension)
                
                // Load the elements before the current pixel.
                for windowI in 0..<windowRadius {
                    let wrappedCoord = self.computeWrappedCoordinate(coord: windowI - windowRadius, size: swizzledDimensions.x, wrapMode: wrapMode)
                    
                    for c in 0..<self.channelCount {
                        if let wrappedCoord = wrappedCoord {
                            for i in 0..<simdWidth {
                                let pixel = SIMD2(wrappedCoord, normalVector[i])
                                slidingWindow[c * windowWidth + windowI][i] = simdMask[i] ? inputBuffer[self.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] : 0.0
                            }
                        } else {
                            slidingWindow[c * windowWidth + windowI] = .zero
                        }
                    }
                    
                    if let wrappedCoord = wrappedCoord {
                        for i in 0..<simdWidth {
                            let pixel = SIMD2(wrappedCoord, normalVector[i])
                            pixelWeightsSlidingWindow[windowI][i] = simdMask[i] ? pixelWeightsBuffer[pixelWeightImage.uncheckedIndex(x: pixel.x, y: pixel.y, channel: 0)] : 0.0
                        }
                    } else {
                        pixelWeightsSlidingWindow[windowI] = .zero
                    }
                }
                
                // Load the current pixel (x = 0)
                for c in 0..<self.channelCount {
                    for i in 0..<simdWidth {
                        let pixel = SIMD2(0, normalVector[i])
                        slidingWindow[c * windowWidth + windowRadius][i] = simdMask[i] ? inputBuffer[self.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] : 0.0
                        
                        pixelWeightsSlidingWindow[windowRadius][i] = simdMask[i] ? pixelWeightsBuffer[pixelWeightImage.uncheckedIndex(x: pixel.x, y: pixel.y, channel: 0)] : 0.0
                    }
                }
                
                // Fill the sliding window for the elements after pixel 0.
                for windowI in 1..<windowRadiusInclusive {
                    let windowOffset = windowI + windowRadius
                    let wrappedCoord = self.computeWrappedCoordinate(coord: windowI, size: swizzledDimensions.x, wrapMode: wrapMode)
                    
                    for c in 0..<self.channelCount {
                        if let wrappedCoord = wrappedCoord {
                            for i in 0..<simdWidth {
                                let pixel = SIMD2(wrappedCoord, normalVector[i])
                                slidingWindow[c * windowWidth + windowOffset][i] = simdMask[i] ? inputBuffer[self.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] : 0.0
                            }
                        } else {
                            slidingWindow[c * windowWidth + windowOffset] = .zero
                        }
                    }
                    
                    if let wrappedCoord = wrappedCoord {
                        for i in 0..<simdWidth {
                            let pixel = SIMD2(wrappedCoord, normalVector[i])
                            pixelWeightsSlidingWindow[windowOffset][i] = simdMask[i] ? pixelWeightsBuffer[pixelWeightImage.uncheckedIndex(x: pixel.x, y: pixel.y, channel: 0)] : 0.0
                        }
                    } else {
                        pixelWeightsSlidingWindow[windowOffset] = .zero
                    }
                }
                
                // Convolve the middle section of the image.
                for windowI in 0..<Swift.max(swizzledDimensions.x - windowRadiusInclusive, 0) {
                    for c in 0..<self.channelCount {
                        var dotVector: SIMDType<Float> = .zero
                        
                        var pixelWeights: SIMDType<Float> = .zero
                        for i in 0..<windowWidth {
                            let weightsProduct = weightsVector[i] * pixelWeightsSlidingWindow[i]
                            pixelWeights += weightsProduct
#if SUBSTRATE_IMAGE_FMA || arch(arm64)
                            dotVector.addProduct(weightsProduct, slidingWindow[c * windowWidth + i])
#else
                            dotVector += weightsProduct * slidingWindow[c * windowWidth + i]
#endif
                        }
                        dotVector /= pixelWeights.replacing(with: .ulpOfOne, where: pixelWeights .== .zero)
                        
                        let pixelWeight = pixelWeightsSlidingWindow[windowRadius]
                        dotVector = (SIMDType<Float>.one - pixelWeight) * slidingWindow[c * windowWidth + windowRadius] + pixelWeight * dotVector
                        
                        for i in 0..<simdWidth where simdMask[i] {
                            let pixel = SIMD2(windowI, normalVector[i])
                            resultBuffer[result.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] = dotVector[i]
                        }
                        
                        for i in 1..<windowWidth {
                            slidingWindow[c * windowWidth + i - 1] = slidingWindow[c * windowWidth + i]
                        }
                        
                        // Load the next pixel into the sliding window.
                        for i in 0..<simdWidth where simdMask[i] {
                            let pixel = SIMD2(windowI + windowRadiusInclusive, normalVector[i])
                            slidingWindow[c * windowWidth + windowWidth - 1][i] = inputBuffer[self.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)]
                        }
                    }
                    
                    for i in 1..<windowWidth {
                        pixelWeightsSlidingWindow[i - 1] = pixelWeightsSlidingWindow[i]
                    }
                    
                    // Load the next pixel into the sliding window.
                    for i in 0..<simdWidth where simdMask[i] {
                        let pixel = SIMD2(windowI + windowRadiusInclusive, normalVector[i])
                        pixelWeightsSlidingWindow[windowWidth - 1][i] = pixelWeightsBuffer[pixelWeightImage.uncheckedIndex(x: pixel.x, y: pixel.y, channel: 0)]
                    }
                }
                
                // Now handle the end section where we need to clamp/wrap.
                for windowI in Swift.max(swizzledDimensions.x - windowRadiusInclusive, 0)..<swizzledDimensions.x {
                    for c in 0..<self.channelCount {
                        var dotVector = SIMDType<Float>.zero
                        
                        var pixelWeights: SIMDType<Float> = .zero
                        for i in 0..<windowWidth {
                            let weightsProduct = weightsVector[i] * pixelWeightsSlidingWindow[i]
                            pixelWeights += weightsProduct
#if SUBSTRATE_IMAGE_FMA || arch(arm64)
                            dotVector.addProduct(weightsProduct, slidingWindow[c * windowWidth + i])
#else
                            dotVector += weightsProduct * slidingWindow[c * windowWidth + i]
#endif
                        }
                        dotVector /= pixelWeights.replacing(with: .ulpOfOne, where: pixelWeights .== .zero)
                        
                        let pixelWeight = pixelWeightsSlidingWindow[windowRadius]
                        dotVector = (SIMDType<Float>.one - pixelWeight) * slidingWindow[c * windowWidth + windowRadius] + pixelWeight * dotVector
                        
                        
                        for i in 0..<simdWidth where simdMask[i] {
                            let pixel = SIMD2(windowI, normalVector[i])
                            resultBuffer[result.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] = dotVector[i]
                        }
                        
                        for i in 1..<windowWidth {
                            slidingWindow[c * windowWidth + i - 1] = slidingWindow[c * windowWidth + i]
                        }
                        
                        if let wrappedCoord = self.computeWrappedCoordinate(coord: windowI + windowRadiusInclusive, size: swizzledDimensions.x, wrapMode: wrapMode) {
                            for i in 0..<simdWidth {
                                let pixel = SIMD2(wrappedCoord, normalVector[i])
                                slidingWindow[c * windowWidth + windowWidth - 1][i] = simdMask[i] ? inputBuffer[self.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] : 0.0
                            }
                        } else {
                            slidingWindow[c * windowWidth + windowWidth - 1] = .zero
                        }
                        
                        for i in 1..<windowWidth {
                            pixelWeightsSlidingWindow[i - 1] = pixelWeightsSlidingWindow[i]
                        }
                        
                        if let wrappedCoord = self.computeWrappedCoordinate(coord: windowI + windowRadiusInclusive, size: swizzledDimensions.x, wrapMode: wrapMode) {
                            for i in 0..<simdWidth {
                                let pixel = SIMD2(wrappedCoord, normalVector[i])
                                pixelWeightsSlidingWindow[windowWidth - 1][i] = simdMask[i] ? pixelWeightsBuffer[pixelWeightImage.uncheckedIndex(x: pixel.x, y: pixel.y, channel: 0)] : 0.0
                            }
                        } else {
                            pixelWeightsSlidingWindow[windowWidth - 1] = .zero
                        }
                    }
                }
            }
        }
    }
    
    func _convolveY(weights: [Float], wrapMode: ImageEdgeWrapMode = .clamp,  pixelWeightImage: Image<Float>, into result: inout Image<Float>) {
        precondition(result.width == self.width && result.height == self.height && result.channelCount == self.channelCount)
        precondition(pixelWeightImage.width == self.width && pixelWeightImage.height == self.height)
        precondition(pixelWeightImage.channelCount == 1)
        
        result.ensureUniqueness() // so we can use the setUnchecked methods.
        
        let inputBuffer = self.storage.data
        let resultBuffer = result.storage.data
        let pixelWeightsBuffer = pixelWeightImage.storage.data
        
        typealias SIMDType<T: SIMDScalar> = SIMD8<T>
        let simdWidth = SIMDType<Float>.scalarCount
        
        let windowRadiusInclusive = weights.count
        let windowRadius = windowRadiusInclusive - 1
        
        let weightsVector = self.weightsToWeightVector(weights: weights)
        let windowWidth = weightsVector.count
        
        let dimensions = SIMD2(self.width, self.height)
        let swizzledDimensions = SIMD2(self.height, self.width)
        
        let strideDimension = swizzledDimensions.y
        
        let slidingWindowCount = (2 * windowRadius + 1) * self.channelCount
        let pixelWeightsSlidingWindowCount = (2 * windowRadius + 1)
        
        withUnsafeTemporaryAllocation(byteCount: (slidingWindowCount + pixelWeightsSlidingWindowCount) * MemoryLayout<SIMDType<Float>>.stride, alignment: MemoryLayout<SIMDType<Float>>.alignment) { slidingWindow in
            let slidingWindow = slidingWindow.bindMemory(to: SIMDType<Float>.self)
            let pixelWeightsSlidingWindow = UnsafeMutableBufferPointer(rebasing: slidingWindow.dropFirst(slidingWindowCount))
            
            for base in stride(from: 0, to: strideDimension, by: simdWidth) {
                var normalVector = SIMDType<Int>(repeating: base)
                for i in 1..<simdWidth {
                    normalVector[i] += i
                }
                let simdMask = normalVector .< SIMDType(repeating: strideDimension)
                
                // Load the elements before the current pixel.
                for windowI in 0..<windowRadius {
                    let wrappedCoord = self.computeWrappedCoordinate(coord: windowI - windowRadius, size: swizzledDimensions.x, wrapMode: wrapMode)
                    
                    for c in 0..<self.channelCount {
                        if let wrappedCoord = wrappedCoord {
                            for i in 0..<simdWidth {
                                let pixel = SIMD2(normalVector[i], wrappedCoord)
                                slidingWindow[c * windowWidth + windowI][i] = simdMask[i] ? inputBuffer[self.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] : 0.0
                            }
                        } else {
                            slidingWindow[c * windowWidth + windowI] = .zero
                        }
                    }
                    
                    if let wrappedCoord = wrappedCoord {
                        for i in 0..<simdWidth {
                            let pixel = SIMD2(normalVector[i], wrappedCoord)
                            pixelWeightsSlidingWindow[windowI][i] = simdMask[i] ? pixelWeightsBuffer[pixelWeightImage.uncheckedIndex(x: pixel.x, y: pixel.y, channel: 0)] : 0.0
                        }
                    } else {
                        pixelWeightsSlidingWindow[windowI] = .zero
                    }
                }
                
                // Load the current pixel (x = 0)
                for c in 0..<self.channelCount {
                    for i in 0..<simdWidth {
                        let pixel = SIMD2(normalVector[i], 0)
                        slidingWindow[c * windowWidth + windowRadius][i] = simdMask[i] ? inputBuffer[self.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] : 0.0
                        
                        pixelWeightsSlidingWindow[windowRadius][i] = simdMask[i] ? pixelWeightsBuffer[pixelWeightImage.uncheckedIndex(x: pixel.x, y: pixel.y, channel: 0)] : 0.0
                    }
                }
                
                // Fill the sliding window for the elements after pixel 0.
                for windowI in 1..<windowRadiusInclusive {
                    let windowOffset = windowI + windowRadius
                    let wrappedCoord = self.computeWrappedCoordinate(coord: windowI, size: swizzledDimensions.x, wrapMode: wrapMode)
                    
                    for c in 0..<self.channelCount {
                        if let wrappedCoord = wrappedCoord {
                            for i in 0..<simdWidth {
                                let pixel = SIMD2(normalVector[i], wrappedCoord)
                                slidingWindow[c * windowWidth + windowOffset][i] = simdMask[i] ? inputBuffer[self.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] : 0.0
                            }
                        } else {
                            slidingWindow[c * windowWidth + windowOffset] = .zero
                        }
                    }
                    
                    if let wrappedCoord = wrappedCoord {
                        for i in 0..<simdWidth {
                            let pixel = SIMD2(normalVector[i], wrappedCoord)
                            pixelWeightsSlidingWindow[windowOffset][i] = simdMask[i] ? pixelWeightsBuffer[pixelWeightImage.uncheckedIndex(x: pixel.x, y: pixel.y, channel: 0)] : 0.0
                        }
                    } else {
                        pixelWeightsSlidingWindow[windowOffset] = .zero
                    }
                }
                
                // Convolve the middle section of the image.
                for windowI in 0..<Swift.max(swizzledDimensions.x - windowRadiusInclusive, 0) {
                    for c in 0..<self.channelCount {
                        var dotVector: SIMDType<Float> = .zero
                        
                        var pixelWeights: SIMDType<Float> = .zero
                        for i in 0..<windowWidth {
                            let weightsProduct = weightsVector[i] * pixelWeightsSlidingWindow[i]
                            pixelWeights += weightsProduct
#if SUBSTRATE_IMAGE_FMA || arch(arm64)
                            dotVector.addProduct(weightsProduct, slidingWindow[c * windowWidth + i])
#else
                            dotVector += weightsProduct * slidingWindow[c * windowWidth + i]
#endif
                        }
                        dotVector /= pixelWeights.replacing(with: .ulpOfOne, where: pixelWeights .== .zero)
                        
                        let pixelWeight = pixelWeightsSlidingWindow[windowRadius]
                        dotVector = (SIMDType<Float>.one - pixelWeight) * slidingWindow[c * windowWidth + windowRadius] + pixelWeight * dotVector
                        
                        for i in 0..<simdWidth where simdMask[i] {
                            let pixel = SIMD2(normalVector[i], windowI)
                            resultBuffer[result.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] = dotVector[i]
                        }
                        
                        for i in 1..<windowWidth {
                            slidingWindow[c * windowWidth + i - 1] = slidingWindow[c * windowWidth + i]
                        }
                        
                        // Load the next pixel into the sliding window.
                        for i in 0..<simdWidth where simdMask[i] {
                            let pixel = SIMD2(normalVector[i], windowI + windowRadiusInclusive)
                            slidingWindow[c * windowWidth + windowWidth - 1][i] = inputBuffer[self.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)]
                        }
                    }
                    
                    for i in 1..<windowWidth {
                        pixelWeightsSlidingWindow[i - 1] = pixelWeightsSlidingWindow[i]
                    }
                    
                    // Load the next pixel into the sliding window.
                    for i in 0..<simdWidth where simdMask[i] {
                        let pixel = SIMD2(normalVector[i], windowI + windowRadiusInclusive)
                        pixelWeightsSlidingWindow[windowWidth - 1][i] = pixelWeightsBuffer[pixelWeightImage.uncheckedIndex(x: pixel.x, y: pixel.y, channel: 0)]
                    }
                }
                
                // Now handle the end section where we need to clamp/wrap.
                for windowI in Swift.max(swizzledDimensions.x - windowRadiusInclusive, 0)..<swizzledDimensions.x {
                    for c in 0..<self.channelCount {
                        var dotVector = SIMDType<Float>.zero
                        
                        var pixelWeights: SIMDType<Float> = .zero
                        for i in 0..<windowWidth {
                            let weightsProduct = weightsVector[i] * pixelWeightsSlidingWindow[i]
                            pixelWeights += weightsProduct
#if SUBSTRATE_IMAGE_FMA || arch(arm64)
                            dotVector.addProduct(weightsProduct, slidingWindow[c * windowWidth + i])
#else
                            dotVector += weightsProduct * slidingWindow[c * windowWidth + i]
#endif
                        }
                        dotVector /= pixelWeights.replacing(with: .ulpOfOne, where: pixelWeights .== .zero)
                        
                        let pixelWeight = pixelWeightsSlidingWindow[windowRadius]
                        dotVector = (SIMDType<Float>.one - pixelWeight) * slidingWindow[c * windowWidth + windowRadius] + pixelWeight * dotVector
                        
                        
                        for i in 0..<simdWidth where simdMask[i] {
                            let pixel = SIMD2(normalVector[i], windowI)
                            resultBuffer[result.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] = dotVector[i]
                        }
                        
                        for i in 1..<windowWidth {
                            slidingWindow[c * windowWidth + i - 1] = slidingWindow[c * windowWidth + i]
                        }
                        
                        if let wrappedCoord = self.computeWrappedCoordinate(coord: windowI + windowRadiusInclusive, size: swizzledDimensions.x, wrapMode: wrapMode) {
                            for i in 0..<simdWidth {
                                let pixel = SIMD2(normalVector[i], wrappedCoord)
                                slidingWindow[c * windowWidth + windowWidth - 1][i] = simdMask[i] ? inputBuffer[self.uncheckedIndex(x: pixel.x, y: pixel.y, channel: c)] : 0.0
                            }
                        } else {
                            slidingWindow[c * windowWidth + windowWidth - 1] = .zero
                        }
                        
                        for i in 1..<windowWidth {
                            pixelWeightsSlidingWindow[i - 1] = pixelWeightsSlidingWindow[i]
                        }
                        
                        if let wrappedCoord = self.computeWrappedCoordinate(coord: windowI + windowRadiusInclusive, size: swizzledDimensions.x, wrapMode: wrapMode) {
                            for i in 0..<simdWidth {
                                let pixel = SIMD2(normalVector[i], wrappedCoord)
                                pixelWeightsSlidingWindow[windowWidth - 1][i] = simdMask[i] ? pixelWeightsBuffer[pixelWeightImage.uncheckedIndex(x: pixel.x, y: pixel.y, channel: 0)] : 0.0
                            }
                        } else {
                            pixelWeightsSlidingWindow[windowWidth - 1] = .zero
                        }
                    }
                }
            }
        }
    }
    
    public func convolveHorizontal(weights: [Float], wrapMode: ImageEdgeWrapMode = .clamp, into result: inout Image<Float>) {
        self._convolveX(weights: weights, wrapMode: wrapMode, into: &result)
    }
    
    public func convolveVertical(weights: [Float], wrapMode: ImageEdgeWrapMode = .clamp, into result: inout Image<Float>) {
        self._convolveY(weights: weights, wrapMode: wrapMode, into: &result)
    }
    
    
    public func convolveHorizontal(weights: [Float], weightsImage: Image<Float>, wrapMode: ImageEdgeWrapMode = .clamp, into result: inout Image<Float>) {
        self._convolveX(weights: weights, wrapMode: wrapMode, pixelWeightImage: weightsImage, into: &result)
    }
    
    public func convolveVertical(weights: [Float], weightsImage: Image<Float>, wrapMode: ImageEdgeWrapMode = .clamp, into result: inout Image<Float>) {
        self._convolveY(weights: weights, wrapMode: wrapMode, pixelWeightImage: weightsImage, into: &result)
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
    
    public func convolveHorizontal(weights: [Float], weightsImage: Image<Float>, wrapMode: ImageEdgeWrapMode = .clamp) -> Image<Float> {
        var result = Image(width: self.width, height: self.height, channelCount: self.channelCount, colorSpace: self.colorSpace, alphaMode: self.alphaMode)
        self.convolveHorizontal(weights: weights, weightsImage: weightsImage, wrapMode: wrapMode, into: &result)
        return result
    }
    
    public func convolveVertical(weights: [Float], weightsImage: Image<Float>, wrapMode: ImageEdgeWrapMode = .clamp) -> Image<Float> {
        var result = Image(width: self.width, height: self.height, channelCount: self.channelCount, colorSpace: self.colorSpace, alphaMode: self.alphaMode)
        self.convolveVertical(weights: weights, weightsImage: weightsImage, wrapMode: wrapMode, into: &result)
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
    
    public mutating func gaussianBlur(sigmaX: Float, sigmaY: Float, weightsImage: Image<Float>, wrapMode: ImageEdgeWrapMode = .clamp) {
        if sigmaX == sigmaY {
            let weights = Self.gaussianBlurWeights(sigma: sigmaX, pixelRadius: Int((3.0 * sigmaX).rounded(.up)))
            let result = self.convolveHorizontal(weights: weights, weightsImage: weightsImage, wrapMode: wrapMode)
            result.convolveVertical(weights: weights, weightsImage: weightsImage, wrapMode: wrapMode, into: &self)
        } else {
            let result = self.convolveHorizontal(weights: Self.gaussianBlurWeights(sigma: sigmaX, pixelRadius: Int((3.0 * sigmaX).rounded(.up))), weightsImage: weightsImage, wrapMode: wrapMode)
            result.convolveVertical(weights: Self.gaussianBlurWeights(sigma: sigmaY, pixelRadius: Int((3.0 * sigmaY).rounded(.up))), weightsImage: weightsImage, wrapMode: wrapMode, into: &self)
        }
    }
    
    public mutating func gaussianBlur(sigma: Float, weightsImage: Image<Float>, wrapMode: ImageEdgeWrapMode = .clamp) {
        self.gaussianBlur(sigmaX: sigma, sigmaY: sigma, weightsImage: weightsImage, wrapMode: wrapMode)
    }
}


