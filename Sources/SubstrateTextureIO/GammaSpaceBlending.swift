//
//  GamamSpaceBlending.swift
//  SubstrateTextureIO
//
//  Created by Thomas Roughton on 10/09/20.
//

extension TextureData where T == UInt8 {
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
        precondition(self.alphaMode == .premultiplied, "The texture must use premultiplied alpha.")
        precondition(self.colorSpace == .sRGB, "The texture must be in the sRGB color space.")
        defer { self.alphaMode = .postmultiplied }
        
        if self.channelCount != 2 && self.channelCount != 4 {
            return
        }
        
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
        precondition(self.alphaMode == .postmultiplied, "The texture must use postmultiplied alpha.")
        precondition(self.colorSpace == .sRGB, "The texture must be in the sRGB color space.")
        defer { self.alphaMode = .premultiplied }
        
        if self.channelCount != 2 && self.channelCount != 4 {
            return
        }
        
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

extension TextureData where T == Float {
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
        precondition(self.alphaMode == .premultiplied, "The texture must use postmultiplied alpha.")
        precondition(self.colorSpace == .sRGB, "The texture must be in the sRGB color space.")
        
        defer { self.alphaMode = .postmultiplied }
        
        if self.channelCount != 2 && self.channelCount != 4 {
            return
        }
        
        /*
         Assume postmultiplied alpha:
         
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
                
                let adjustedAlpha = 1.0 - TextureColorSpace.convert(1.0 - alpha, from: .linearSRGB, to: .sRGB)
                
                for c in 0..<alphaChannel {
                    let premultColor = self[x, y, channel: c]
                    self[x, y, channel: c] = (TextureColorSpace.convert((1.0 - alpha) + TextureColorSpace.convert(premultColor, from: .sRGB, to: .linearSRGB), from: .linearSRGB, to: .sRGB) - (1.0 - adjustedAlpha)) / adjustedAlpha
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
        if self.channelCount != 2 && self.channelCount != 4 {
            self.alphaMode = .premultiplied
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
        precondition(self.alphaMode == .postmultiplied, "The texture must use postmultiplied alpha.")
        precondition(self.colorSpace == .sRGB, "The texture must be in the sRGB color space.")
        defer {
            self.alphaMode = .premultiplied
            self.colorSpace = .linearSRGB
        }
        
        if self.channelCount != 2 && self.channelCount != 4 {
            self.convert(toColorSpace: .linearSRGB)
            return
        }
        
        let alphaChannel = self.channelCount - 1
        
        for y in 0..<self.height {
            for x in 0..<self.width {
                let adjustedAlpha = self[x, y, channel: alphaChannel]
                
                let alpha = 1.0 - TextureColorSpace.convert(1.0 - adjustedAlpha, from: .sRGB, to: .linearSRGB)
                
                for c in 0..<alphaChannel {
                    let srgbBlendColor = self[x, y, channel: c]
                    self[x, y, channel: c] = TextureColorSpace.convert(srgbBlendColor * adjustedAlpha + (1.0 - adjustedAlpha), from: .sRGB, to: .linearSRGB) - (1.0 - alpha)
                }
                self[x, y, channel: alphaChannel] = alpha
            }
        }
    }
}
