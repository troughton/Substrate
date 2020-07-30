//
//  ImGui+RGBAColor.swift
//  LlamaCore
//
//  Created by Thomas Roughton on 26/08/19.
//

import CImGui
import ImGui
import SwiftMath

extension ImGui {
    @discardableResult
    public static func colorButton(descriptionId: String, color: RGBAColor, flags: ColorEditFlags = [], size: SIMD2<Float> = .zero) -> Bool {
        return self.colorButton(descriptionId: descriptionId, color: SIMD4(color), flags: flags, size: size)
    }
    
    public static func colorEdit3(label: String, color: inout RGBColor, flags: ColorEditFlags) -> Bool {
        var imColor = SIMD3(color)
        defer { color = RGBColor(imColor.x, imColor.y, imColor.z) }
        return self.colorEdit3(label: label, color: &imColor, flags: flags)
    }
    
    public static func colorEdit4(label: String, color: inout RGBAColor, flags: ColorEditFlags) -> Bool {
        var imColor = SIMD4(color)
        defer { color = RGBAColor(imColor.x, imColor.y, imColor.z, imColor.w) }
        return self.colorEdit4(label: label, color: &imColor, flags: flags)
    }
    
}
