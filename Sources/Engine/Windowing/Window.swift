//
//  Window.swift
//  InterdimensionalLlama
//
//  Created by Joseph Bennett on 14/11/16.
//
//

import SwiftFrameGraph

import Foundation


public struct WindowSize : Equatable {
    public let width: Int
    public let height: Int
    
    public init(_ width: Int, _ height: Int) {
        self.width = width
        self.height = height
    }
    
    public var aspect : Float {
        return Float(self.width) / Float(self.height)
    }
    
    public static func ==(lhs: WindowSize, rhs: WindowSize) -> Bool {
        return lhs.width == rhs.width && lhs.height == rhs.height
    }

    public var scissorRect : ScissorRect {
        return ScissorRect(x: 0, y: 0, width: self.width, height: self.height)
    }
}

public struct FileChooserOptions : OptionSet {
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    public static let canChooseFiles = FileChooserOptions(rawValue: 1 << 0)
    public static let canChooseDirectories = FileChooserOptions(rawValue: 1 << 1)
    public static let allowsMultipleSelection = FileChooserOptions(rawValue: 1 << 2)
    public static let allowsOtherFileTypes = FileChooserOptions(rawValue: 1 << 3)
}



public protocol Window : class {
    var id : Int { get }
    var title : String { get }
    var dimensions : WindowSize { get }
    
    var hasFocus : Bool { get }
    
    var delegate : _WindowDelegate? { get set }
    
    var texture : Texture { get }
    
    var drawableSize : WindowSize { get }
    
    var fullscreen : Bool { get set }
    
    var isMainWindow : Bool { get set }
    
    func displayOpenDialog(allowedFileTypes: [String], options: FileChooserOptions) -> [URL]?
    func displaySaveDialog(allowedFileTypes: [String], options: FileChooserOptions) -> URL?
    
    func cycleFrames()
}

extension Window {
    public var framebufferScale : Double {
        return Double(self.drawableSize.width) / Double(self.dimensions.width)
    }
}

public protocol _WindowDelegate : class {
    
    var title : String { get }
    var inputManager : InputManager! { get set }
    var desiredSize : WindowSize { get }
    
    var window : Window! { get set }
   
    func drawableSizeDidChange(on window: Window)
    
}
