//
//  ImGuiTextureLookup.swift
//  LlamaCore
//
//  Created by Thomas Roughton on 25/08/19.
//

import ImGui
import SwiftFrameGraph
import SwiftMath

public final class TextureLookup {
    private static var maxIndex : UInt32 = 1
    private static var labelsToIdentifiers = [String : UInt32]()
    private static var identifiersToTextures = [UInt32 : Texture]()
    
    public static func register<S : RawRepresentable>(_ texture: Texture, label: S) where S.RawValue == String {
        self.register(texture, label: label.rawValue)
    }
    
    public static func register(_ texture: Texture, label: String) {
        let index = self.transientTextureReference(label: label)
        self.identifiersToTextures[index] = texture
    }
    
    public static func transientTextureReference<S : RawRepresentable>(label: S) -> UInt32 where S.RawValue == String {
        return self.transientTextureReference(label: label.rawValue)
    }
    
    public static func transientTextureReference(label: String) -> UInt32 {
        if let index = self.labelsToIdentifiers[label] {
            return index
        } else {
            let index = self.maxIndex
            self.maxIndex += 1
            self.labelsToIdentifiers[label] = index
            return index
        }
    }
    
    public static func textureWithId(_ identifier: UInt32) -> Texture? {
        return self.identifiersToTextures[identifier]
    }
}

extension ImGui {
    public static func image(label: String, size: Vector2f, uv0: Vector2f = Vector2f(repeating: 0), uv1: Vector2f = Vector2f(repeating: 1), tintColour: Vector4f = Vector4f(repeating: 1), borderColour: Vector4f = Vector4f(repeating: 0))  {
        let identifier = TextureLookup.transientTextureReference(label: label)
        self.image(UnsafeMutableRawPointer(bitPattern: UInt(identifier)), size: size, uv0: uv0, uv1: uv1, tintColor: tintColour, borderColor: borderColour)
    }
    
    public static func image<S : RawRepresentable>(label: S, size: Vector2f, uv0: Vector2f = Vector2f(repeating: 0), uv1: Vector2f = Vector2f(repeating: 1), tintColour: Vector4f = Vector4f(repeating: 1), borderColour: Vector4f = Vector4f(repeating: 0)) where S.RawValue == String {
        let identifier = TextureLookup.transientTextureReference(label: label)
        self.image(UnsafeMutableRawPointer(bitPattern: UInt(identifier))!, size: size, uv0: uv0, uv1: uv1, tintColor: tintColour, borderColor: borderColour)
    }
    
    public static func imageButton(label: String, size: Vector2f, uv0: Vector2f, uv1: Vector2f, framePadding: Int, backgroundColour: Vector4f, tintColour: Vector4f) -> Bool {
        let identifier = TextureLookup.transientTextureReference(label: label)
        return self.imageButton(UnsafeMutableRawPointer(bitPattern: UInt(identifier)), size: size, uv0: uv0, uv1: uv1, framePadding: framePadding, backgroundColor: backgroundColour, tintColor: tintColour)
    }
    
    public static func imageButton<S : RawRepresentable>(label: S, size: Vector2f, uv0: Vector2f, uv1: Vector2f, framePadding: Int, backgroundColour: Vector4f, tintColour: Vector4f) -> Bool where S.RawValue == String {
        let identifier = TextureLookup.transientTextureReference(label: label)
        return self.imageButton(UnsafeMutableRawPointer(bitPattern: UInt(identifier)), size: size, uv0: uv0, uv1: uv1, framePadding: framePadding, backgroundColor: backgroundColour, tintColor: tintColour)
    }
    
    public static func image(_ texture: Texture, size: Vector2f, uv0: Vector2f = Vector2f(repeating: 0), uv1: Vector2f = Vector2f(repeating: 1), tintColour: Vector4f = Vector4f(repeating: 1), borderColour: Vector4f = Vector4f(repeating: 0))  {
        self.image(UnsafeMutableRawPointer(bitPattern: UInt(exactly: texture.handle)!), size: size, uv0: uv0, uv1: uv1, tintColor: tintColour, borderColor: borderColour)
    }
    
    public static func imageButton(_ texture: Texture, size: Vector2f, uv0: Vector2f = Vector2f(repeating: 0), uv1: Vector2f = Vector2f(repeating: 1), framePadding: Int, backgroundColour: Vector4f, tintColour: Vector4f) -> Bool {
        return self.imageButton(UnsafeMutableRawPointer(bitPattern: UInt(exactly: texture.handle)!), size: size, uv0: uv0, uv1: uv1, framePadding: framePadding, backgroundColor: backgroundColour, tintColor: tintColour)
    }
}
