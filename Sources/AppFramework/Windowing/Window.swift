//
//  Window.swift
//  InterdimensionalLlama
//
//  Created by Joseph Bennett on 14/11/16.
//
//

import Substrate

import Foundation

public struct WindowPosition : Equatable {
    public var x: Float
    public var y: Float
    
    public init(_ x: Float, _ y: Float) {
        self.x = x
        self.y = y
    }
}

public struct WindowSize : Equatable {
    public var width: Float
    public var height: Float
    
    public init(_ width: Float, _ height: Float) {
        self.width = width
        self.height = height
    }
    
    public var aspect : Float {
        return self.width / self.height
    }

    public var scissorRect : ScissorRect {
        return ScissorRect(x: 0, y: 0, width: Int(exactly: self.width)!, height: Int(exactly: self.height)!)
    }
}

public struct FileChooserOptions : OptionSet {
    public let rawValue: Int
    
    @inlinable
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    public static let canChooseFiles = FileChooserOptions(rawValue: 1 << 0)
    public static let canChooseDirectories = FileChooserOptions(rawValue: 1 << 1)
    public static let allowsMultipleSelection = FileChooserOptions(rawValue: 1 << 2)
    public static let allowsOtherFileTypes = FileChooserOptions(rawValue: 1 << 3)
}

public struct WindowCreationFlags : OptionSet {
    public let rawValue: Int
    
    @inlinable
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    public static let borderless = WindowCreationFlags(rawValue: 1 << 0)
    public static let hidden = WindowCreationFlags(rawValue: 1 << 1)
    public static let resizable = WindowCreationFlags(rawValue: 1 << 2)
}

public protocol Window : AnyObject {
    var id : Int { get }
    var title : String { get set }
    
    var dimensions : WindowSize { get set }
    var position : WindowPosition { get set }

    var hasFocus : Bool { get set }
    var isVisible: Bool { get set }
    
    var delegate : WindowDelegate? { get set }
    
    var texture : Texture { get }
    
    var drawableSize : WindowSize { get }

    var fullscreen : Bool { get set }
    
    var alpha : Float { get set }
    
    /// How many windows are in front of this window
    var windowsInFrontCount : Int { get }
    
    func displayOpenDialog(allowedFileTypes: [String], options: FileChooserOptions) -> [URL]?
    func displaySaveDialog(allowedFileTypes: [String], options: FileChooserOptions) -> URL?
    
    func cycleFrames()
}

extension Window {
    public var framebufferScale : Double {
        return Double(self.drawableSize.width) / Double(self.dimensions.width)
    }
}

public protocol FrameUpdateable : AnyObject {
    func update(frame: UInt64, deltaTime: Double) async
}

public protocol WindowDelegate : FrameUpdateable {
    
    var title : String { get }
    var desiredSize : WindowSize { get }
    
    var window : Window! { get set }
   
    func drawableSizeDidChange(on window: Window)
    
    var inputLayers : [InputLayer] { get }
}

