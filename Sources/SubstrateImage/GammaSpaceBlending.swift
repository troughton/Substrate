//
//  GamamSpaceBlending.swift
//  SubstrateTextureIO
//
//  Created by Thomas Roughton on 10/09/20.
//

extension Image where ComponentType == UInt8 {
    /// This method adjusts the texture values such that the results look more-or-less correct when blended in sRGB gamma space.
    /// The texture must already be in the sRGB color space and use premultiplied alpha, and the resulting texture will use postmultiplied alpha.
    /// This is useful when taking a GPU-generated texture and converting it so that blending will behave consistently in applications such as
    /// Photoshop or web browsers.
    ///
    /// In general, blending should be performed in linear space. However, due to legacy reasons, many applications
    /// blend in gamma space by default, including web browsers (https://observablehq.com/@toja/color-blending-with-gamma-correction)
    /// and Photoshop. Photoshop's behavior can be corrected by turning on "Blend RGB Colors using Gamma == 1.0" in the "Color Settings" dialog; however,
    /// for cases such as web browsers we just have to deal with the incorrect behavior.
    public mutating func convertPremultLinearBlendedSRGBToPostmultSRGBBlendedSRGB() {
        if self.alphaMode == .none { return }
        
        precondition(self.alphaMode == .premultiplied, "The texture must use premultiplied alpha.")
        precondition(self.colorSpace == .sRGB, "The texture must be in the sRGB color space.")
        defer { self.alphaMode = .postmultiplied }
        
        self.ensureUniqueness()
        
        let alphaChannel = self.channelCount - 1
        for y in 0..<self.height {
            for x in 0..<self.width {
                let alpha = self[x, y, channel: alphaChannel]
                if alpha == 0 || alpha == .max { continue }
                for c in 0..<alphaChannel {
                    let processedValue = ColorSpaceLUTs.premultLinearBlendedSRGBToPostmultSRGBBlendedSRGB(alpha: alpha, value: self[x, y, channel: c])
                    self.setUnchecked(x: x, y: y, channel: c, value: processedValue)
                }
                self.setUnchecked(x: x, y: y, channel: alphaChannel, value: ColorSpaceLUTs.linearBlendedSRGBToSRGBBlendedSRGB(alpha: alpha))
            }
        }
    }
    
    /// This method adjusts the texture values such that the textures that were originally intended to be blended in sRGB gamma space have more or less matching results when blended in linear space.
    /// The texture must already be in the sRGB color space and use postmultiplied alpha, and the resulting texture will use premultiplied alpha.
    /// This is useful when taking an image that was generated in an environment that blends in gamma space (e.g. Photoshop or Illustrator) and bringing it to the GPU, where blending is performed (correctly) in linear space.
    ///
    /// In general, blending should be performed in linear space. However, due to legacy reasons, many applications
    /// blend in gamma space by default, including web browsers (https://observablehq.com/@toja/color-blending-with-gamma-correction)
    /// and Photoshop. Photoshop's behavior can be corrected by turning on "Blend RGB Colors using Gamma == 1.0" in the "Color Settings" dialog; however,
    /// for cases such as web browsers we just have to deal with the incorrect behavior.
    public mutating func convertPostmultSRGBBlendedSRGBToPremultLinearBlendedSRGB() {
        if self.alphaMode == .none { return }
        
        precondition(self.alphaMode == .postmultiplied, "The texture must use postmultiplied alpha.")
        precondition(self.colorSpace == .sRGB, "The texture must be in the sRGB color space.")
        defer { self.alphaMode = .premultiplied }
        
        self.ensureUniqueness()
        
        let alphaChannel = self.channelCount - 1
        for y in 0..<self.height {
            for x in 0..<self.width {
                let alpha = self[x, y, channel: alphaChannel]
                if alpha == 0 || alpha == .max { continue }
                for c in 0..<alphaChannel {
                    let processedValue = ColorSpaceLUTs.postmultSRGBBlendedSRGBToPremultLinearBlendedSRGB(alpha: alpha, value: self[x, y, channel: c])
                    self.setUnchecked(x: x, y: y, channel: c, value: processedValue)
                }
                self.setUnchecked(x: x, y: y, channel: alphaChannel, value: ColorSpaceLUTs.sRGBBlendedSRGBToLinearBlendedSRGB(alpha: alpha))
            }
        }
    }
}

extension Image where ComponentType == UInt8 {
    private func _convertPremultSRGBBlendedSRGBToPremultLinearBlendedSRGB() {
        let alphaChannel = self.channelCount - 1
        for y in 0..<self.height {
            for x in 0..<self.width {
                let alpha = self[x, y, channel: alphaChannel]
                for c in 0..<alphaChannel {
                    let channelVal = self[x, y, channel: c]
                    self.setUnchecked(x: x, y: y, channel: c, value: ColorSpaceLUTs.premultSRGBBlendedSRGBToPremultLinearBlendedSRGB(alpha: alpha, value: channelVal))
                }
            }
        }
    }
}

extension Image where T: BinaryInteger & FixedWidthInteger & UnsignedInteger {
    /// Converts to postmultiplied alpha, assuming that the source premultiplied alpha values were intended
    /// to be blended in gamma space.
    public mutating func convertPremultGammaBlendedToPostmultLinearBlended() {
        precondition(self.alphaMode == .premultiplied)
        if self.colorSpace == .linearSRGB { return }
        
        let colorSpace = self.colorSpace
        self.reinterpretColor(as: .undefined)
        self.convertToPostmultipliedAlpha()
        self.reinterpretColor(as: colorSpace)
    }
    
    @_specialize(kind: full, where ComponentType == UInt8)
    @_specialize(kind: full, where ComponentType == UInt16)
    @_specialize(kind: full, where ComponentType == UInt32)
    public mutating func convertPremultGammaBlendedToPremultLinearBlended() {
        precondition(self.alphaMode == .premultiplied)
        if self.colorSpace == .linearSRGB { return }
        
        self.ensureUniqueness()
        
        if T.self == UInt8.self, self.colorSpace == .sRGB {
            (self as! Image<UInt8>)._convertPremultSRGBBlendedSRGBToPremultLinearBlendedSRGB()
            return
        }
        
        let sourceColorSpace = self.colorSpace
        
        let alphaChannel = self.channelCount - 1
        for y in 0..<self.height {
            for x in 0..<self.width {
                let alpha = unormToFloat(self[x, y, channel: alphaChannel])
                for c in 0..<alphaChannel {
                    let floatVal = unormToFloat(self[x, y, channel: c])
                    let postMultFloatVal = clamp(floatVal / alpha, min: 0.0, max: 1.0)
                    let linearVal = ImageColorSpace.convert(postMultFloatVal, from: sourceColorSpace, to: .linearSRGB) * alpha
                    self.setUnchecked(x: x, y: y, channel: c, value: floatToUnorm(ImageColorSpace.convert(linearVal, from: .linearSRGB, to: sourceColorSpace), type: T.self))
                }
            }
        }
    }
}

extension Image where ComponentType == Float {
    /// This method adjusts the texture values such that the results look more-or-less correct when blended in sRGB gamma space.
    /// The texture must already be in the sRGB color space and use premultiplied alpha, and the resulting texture will use postmultiplied alpha.
    /// This is useful when taking a GPU-generated texture and converting it so that blending will behave consistently in applications such as
    /// Photoshop or web browsers. 
    ///
    /// In general, blending should be performed in linear space. However, due to legacy reasons, many applications
    /// blend in gamma space by default, including web browsers (https://observablehq.com/@toja/color-blending-with-gamma-correction)
    /// and Photoshop. Photoshop's behavior can be corrected by turning on "Blend RGB Colors using Gamma == 1.0" in the "Color Settings" dialog; however,
    /// for cases such as web browsers we just have to deal with the incorrect behavior.
    public mutating func convertPremultLinearBlendedSRGBToPostmultSRGBBlendedSRGB() {
        if self.alphaMode == .none { return }
        
        precondition(self.alphaMode == .premultiplied, "The texture must use premultiplied alpha.")
        precondition(self.colorSpace == .sRGB, "The texture must be in the sRGB color space.")
        
        defer { self.alphaMode = .postmultiplied }
        
        /*
         Assume premultiplied alpha:
         
         Correct:
         blendR = linearToSRGB(sRGBToLinear(baseR) * (1.0 - alpha) + sRGBToLinear(r) * alpha)
         blendG = linearToSRGB(sRGBToLinear(baseG) * (1.0 - alpha) + sRGBToLinear(g) * alpha)
         blendB = linearToSRGB(sRGBToLinear(baseB) * (1.0 - alpha) + sRGBToLinear(b) * alpha)
         
         What we're getting:
         blendR = baseR * (1.0 - alpha) + r * alpha
         blendG = baseG * (1.0 - alpha) + g * alpha
         blendB = baseB * (1.0 - alpha) + b * alpha
         
         We need to find r', g', b', a' such that:
         baseR * (1.0 - a') + r' * a' = linearToSRGB(sRGBToLinear(baseR) * (1.0 - alpha) + sRGBToLinear(r) * alpha)
         baseG * (1.0 - a') + g' * a' = linearToSRGB(sRGBToLinear(baseG) * (1.0 - alpha) + sRGBToLinear(g) * alpha)
         baseB * (1.0 - a') + b' * a' = linearToSRGB(sRGBToLinear(baseB) * (1.0 - alpha) + sRGBToLinear(b) * alpha)
         
         If we make r, g, b all 0:
         
         base * (1.0 - a') = linearToSRGB(sRGBToLinear(base) * (1.0 - alpha))
         base - a' * base = linearToSRGB(sRGBToLinear(base) * (1.0 - alpha))
         a' = (base - linearToSRGB(sRGBToLinear(base) * (1.0 - alpha))) / base
         
         If base == 1.0:
         
         a' = 1.0 - linearToSRGB(1.0 - alpha)
         
         Next, find the colour adjustment:
         
         base * (1.0 - a') + r' * a' = linearToSRGB(sRGBToLinear(base) * (1.0 - alpha) + sRGBToLinear(r) * alpha)
         
         If base == 1:
         
         (1.0 - a') + r' * a' = linearToSRGB((1.0 - alpha) + sRGBToLinear(r) * alpha)
         r' = (linearToSRGB((1.0 - alpha) + sRGBToLinear(r) * alpha) - (1.0 - a')) / a'
         */
        
        let alphaChannel = self.channelCount - 1
        
        for y in 0..<self.height {
            for x in 0..<self.width {
                let alpha = self[x, y, channel: alphaChannel]
                guard alpha > 0 && alpha < 1.0 else { continue }
                
                let adjustedAlpha = 1.0 - ImageColorSpace.convert(1.0 - alpha, from: .linearSRGB, to: .sRGB)
                
                for c in 0..<alphaChannel {
                    let premultColor = self[x, y, channel: c]
                    self[x, y, channel: c] = (ImageColorSpace.convert((1.0 - alpha) + ImageColorSpace.convert(premultColor, from: .sRGB, to: .linearSRGB), from: .linearSRGB, to: .sRGB) - (1.0 - adjustedAlpha)) / adjustedAlpha
                }
                self[x, y, channel: alphaChannel] = adjustedAlpha
            }
        }
    }
    
    /// This method adjusts the texture values such that the textures that were originally intended to be blended in sRGB gamma space have more or less
    /// matching results when blended in linear space.
    /// The texture must already be in the sRGB color space and use postmultiplied alpha, and the resulting texture will use premultiplied alpha.
    /// This is useful when taking an image that was generated in an environment that blends in gamma space (e.g. Photoshop or Illustrator) and bringing it to the GPU, where blending is performed (correctly) in linear space.
    ///
    /// In general, blending should be performed in linear space. However, due to legacy reasons, many applications
    /// blend in gamma space by default, including web browsers (https://observablehq.com/@toja/color-blending-with-gamma-correction)
    /// and Photoshop. Photoshop's behavior can be corrected by turning on "Blend RGB Colors using Gamma == 1.0" in the "Color Settings" dialog; however,
    /// for cases such as web browsers we just have to deal with the incorrect behavior.
    public mutating func convertPostmultSRGBBlendedSRGBToPremultLinearBlendedSRGB() {
        if self.alphaMode == .none {
            return
        }
        
        self.convertPostmultSRGBBlendedSRGBToPremultLinear()
        self.convert(toColorSpace: .sRGB)
    }
    
    /// This method adjusts the texture values such that the textures that were originally intended to be blended in sRGB gamma space have more or less
    /// matching results when blended in linear space.
    /// The texture must already be in the sRGB color space and use postmultiplied alpha, and the resulting texture will use premultiplied alpha.
    /// This is useful when taking an image that was generated in an environment that blends in gamma space (e.g. Photoshop or Illustrator) and bringing it to the GPU, where blending is performed (correctly) in linear space.
    ///
    /// In general, blending should be performed in linear space. However, due to legacy reasons, many applications
    /// blend in gamma space by default, including web browsers (https://observablehq.com/@toja/color-blending-with-gamma-correction)
    /// and Photoshop. Photoshop's behavior can be corrected by turning on "Blend RGB Colors using Gamma == 1.0" in the "Color Settings" dialog; however,
    /// for cases such as web browsers we just have to deal with the incorrect behavior.
    public mutating func convertPostmultSRGBBlendedSRGBToPremultLinear() {
        if self.alphaMode == .none {
            self.convert(toColorSpace: .linearSRGB)
            return
        }
        
        precondition(self.alphaMode == .postmultiplied, "The texture must use postmultiplied alpha.")
        precondition(self.colorSpace == .sRGB, "The texture must be in the sRGB color space.")
        defer {
            self.alphaMode = .premultiplied
            self.colorSpace = .linearSRGB
        }
        
        let alphaChannel = self.channelCount - 1
        
        for y in 0..<self.height {
            for x in 0..<self.width {
                let adjustedAlpha = self[x, y, channel: alphaChannel]
                
                let alpha = 1.0 - ImageColorSpace.convert(1.0 - adjustedAlpha, from: .sRGB, to: .linearSRGB)
                
                for c in 0..<alphaChannel {
                    let srgbBlendColor = self[x, y, channel: c]
                    self[x, y, channel: c] = ImageColorSpace.convert(srgbBlendColor * adjustedAlpha + (1.0 - adjustedAlpha), from: .sRGB, to: .linearSRGB) - (1.0 - alpha)
                }
                self[x, y, channel: alphaChannel] = alpha
            }
        }
    }
    
    /// Converts to postmultiplied alpha, assuming that the source premultiplied alpha values were intended
    /// to be blended in gamma space.
    public mutating func convertPremultGammaBlendedToPostmultLinearBlended() {
        let colorSpace = self.colorSpace
        self.reinterpretColor(as: .undefined)
        self.convertToPostmultipliedAlpha()
        self.reinterpretColor(as: colorSpace)
    }
}
