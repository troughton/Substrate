//
//  ImGui+RGBAColour.swift
//  LlamaCore
//
//  Created by Thomas Roughton on 26/08/19.
//

import cimgui
import ImGui
import SwiftMath

extension ImGui {
    @discardableResult
    public static func colorButton(descriptionId: String, color: RGBAColour, flags: ColorEditFlags = [], size: ImVec2 = ImVec2(repeating: 0)) -> Bool {
        return self.colorButton(descriptionId: descriptionId, color: ImVec4(color), flags: flags, size: size)
    }
    
    public static func colorEdit3(label: String, color: inout RGBColour, flags: ColorEditFlags) -> Bool {
        var imColor = ImVec3(color)
        defer { color = RGBColour(imColor.x, imColor.y, imColor.z) }
        return self.colorEdit3(label: label, color: &imColor, flags: flags)
    }
    
    public static func colorEdit4(label: String, color: inout RGBAColour, flags: ColorEditFlags) -> Bool {
        var imColor = ImVec4(color)
        defer { color = RGBAColour(imColor.x, imColor.y, imColor.z, imColor.w) }
        return self.colorEdit4(label: label, color: &imColor, flags: flags)
    }
    
}
