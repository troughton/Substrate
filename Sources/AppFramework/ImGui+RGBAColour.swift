//
//  ImGui+RGBAColor.swift
//  LlamaCore
//
//  Created by Thomas Roughton on 26/08/19.
//

import CImGui
import ImGui
import SubstrateMath

extension ImGui {
    @discardableResult
    public static func colorButton(descriptionId: String, color: RGBAColor, size: SIMD2<Float> = .zero, flags: ColorEditFlags = []) -> Bool {
        return self.colorButton(descriptionId: descriptionId, color: SIMD4(color), size: size, flags: flags)
    }
    
    public static func colorEdit(label: String, color: inout RGBColor, flags: ColorEditFlags) -> Bool {
        var imColor = SIMD3(color)
        defer { color = RGBColor(imColor.x, imColor.y, imColor.z) }
        return self.colorEdit(label: label, color: &imColor, flags: flags)
    }
    
    public static func colorEdit(label: String, color: inout RGBAColor, flags: ColorEditFlags) -> Bool {
        var imColor = SIMD4(color)
        defer { color = RGBAColor(imColor.x, imColor.y, imColor.z, imColor.w) }
        return self.colorEdit(label: label, color: &imColor, flags: flags)
    }
    
}
