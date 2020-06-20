//
//  SDLWindow.swift
//  InterdimensionalLlama
//
//  Created by Joseph Bennett on 17/11/16.
//
//

#if canImport(CSDL2) && !os(iOS)

#if os(macOS)
    import AppKit
    import MetalKit
#endif

import FrameGraphUtilities
import Foundation
import SwiftFrameGraph
import CSDL2
import CNativeFileDialog

open class SDLWindow : Window {
    
    public let sdlWindowPointer : OpaquePointer
    
    public var title : String
    
    public let id : Int
    
    public var delegate: WindowDelegate?
    
    public var isVisible: Bool {
        get {
            return true // FIXME
        }
        set {
            _ = newValue
        }
    }
    
    public var alpha: Float {
        get {
            var opacity : Float = 0.0
            SDL_GetWindowOpacity(self.sdlWindowPointer, &opacity)
            return opacity
        }
        set {
            SDL_SetWindowOpacity(self.sdlWindowPointer, newValue)
        }
    }
    
    public var windowsInFrontCount: Int {
        return 0 // FIXME
    }
    
    public var dimensions : WindowSize {
        didSet {
            var drawableWidth  = Int32(0)
            var drawableHeight = Int32(0)
            SDL_GL_GetDrawableSize(self.sdlWindowPointer, &drawableWidth, &drawableHeight)
            self.drawableSize = WindowSize(Float(drawableWidth), Float(drawableHeight))
        }
    }
    
    
    public var sdlWindowOptions : SDLWindowOptions {
        return SDLWindowOptions(rawValue: SDL_GetWindowFlags(self.sdlWindowPointer))
    }
    
    public var sdlWindowId : UInt32 {
        return SDL_GetWindowID(self.sdlWindowPointer)
    }
    
    public convenience init(id: Int, title: String, dimensions: WindowSize, frameGraph: FrameGraph) {
        let options : SDLWindowOptions =  [.shown, .resizeable, .allowHighDpi]
        let sdlWindowPointer = SDL_CreateWindow(title, Int32(SDL_WINDOWPOS_UNDEFINED_MASK), Int32(SDL_WINDOWPOS_UNDEFINED_MASK), Int32(dimensions.width), Int32(dimensions.height), options.rawValue)
        
        self.init(id: id, title: title, dimensions: dimensions, sdlWindowPointer: sdlWindowPointer, frameGraph: frameGraph)
    }
    
    public init(id: Int, title: String, dimensions: WindowSize, sdlWindowPointer: OpaquePointer!, frameGraph: FrameGraph) {
        self.id = id
        self.title = title
        self.dimensions = dimensions
        
        self.sdlWindowPointer = sdlWindowPointer
        
        var drawableWidth  = Int32(0)
        var drawableHeight = Int32(0)
        SDL_GL_GetDrawableSize(self.sdlWindowPointer, &drawableWidth, &drawableHeight)
        self.drawableSize = WindowSize(Float(drawableWidth), Float(drawableHeight))
        
        self._texture = Cached()
        
        self._texture.constructor = { [unowned(unsafe) self] in
            return Texture(windowId: self.id, descriptor: self.textureDescriptor, isMinimised: self.minimized, nativeWindow: self.swapChain!, frameGraph: frameGraph)
        }
    }
    
    deinit {
        SDL_DestroyWindow(self.sdlWindowPointer)
    }
    
    public var swapChain : SwapChain! = nil
    
    @Cached public var texture : Texture
    
    public var textureDescriptor : TextureDescriptor {
        return TextureDescriptor(type: .type2D, format: self.swapChain.format, width: Int(self.drawableSize.width), height: Int(self.drawableSize.height), mipmapped: false)
    }
    
    public func cycleFrames() {
        _texture.reset()
    }
    
    public func displayOpenDialog(allowedFileTypes: [String], options: FileChooserOptions) -> [URL]? {
        let filterList = allowedFileTypes.joined(separator: ",")

        var outPath : UnsafeMutablePointer<nfdchar_t>? = nil
        let result : nfdresult_t
        if options.contains(.canChooseDirectories) {
            result = NFD_PickFolder(nil, &outPath)
        } else {
            if options.contains(.allowsMultipleSelection) {
                var pathSet = nfdpathset_t()
                if NFD_OpenDialogMultiple(filterList, nil, &pathSet) == NFD_OKAY {
                    let count = NFD_PathSet_GetCount(&pathSet)
                    var urls = [URL]()
                    for i in 0..<count {
                        let path = String(cString: NFD_PathSet_GetPath(&pathSet, i))
                        urls.append(URL(fileURLWithPath: path))
                    }
                    NFD_PathSet_Free(&pathSet)
                    return urls

                } else {
                    return nil
                }

            } else {
                result = NFD_OpenDialog(filterList, nil, &outPath)
            }
        }

        if result == NFD_OKAY {
            let path = String(cString: outPath!)
            free(outPath)
            return [URL(fileURLWithPath: path)]
        } else {
            return nil
        }
    }
    
    public func displaySaveDialog(allowedFileTypes: [String], options: FileChooserOptions) -> URL? {
        let filterList = allowedFileTypes.joined(separator: ",")

        var outPath : UnsafeMutablePointer<nfdchar_t>? = nil

        if NFD_SaveDialog(filterList, nil, &outPath) == NFD_OKAY {
            let path = String(cString: outPath!)
            free(outPath)
            return URL(fileURLWithPath: path)
        } else {
            return nil
        }
    }
    
    public var position: WindowPosition {
        get {
            var x : Int32 = 0
            var y : Int32 = 0
            SDL_GetWindowPosition(self.sdlWindowPointer, &x, &y)
            return WindowPosition(Float(x), Float(y))
        }
        set {
            SDL_SetWindowPosition(self.sdlWindowPointer, Int32(newValue.x), Int32(newValue.y))
        }
    }
    
    public var hasFocus: Bool {
        get {
            return self.sdlWindowOptions.contains(.inputFocus)
        }
        set {
            SDL_SetWindowGrab(self.sdlWindowPointer, SDL_bool(rawValue: newValue ? 1 : 0))
        }
    }
    
    public private(set) var drawableSize = WindowSize(0, 0) {
        didSet {
            self.delegate?.drawableSizeDidChange(on: self)
        }
    }
    
    public var fullscreen : Bool {
        get {
            return sdlWindowOptions.contains(.fullscreen)
        }
        
        set (fullscreen) {
            SDL_SetWindowFullscreen(self.sdlWindowPointer, fullscreen ? SDLWindowOptions.fullscreen.rawValue : 0)
        }
    }
    
    public var maximized : Bool {
        get {
            return sdlWindowOptions.contains(.maximized)
        }
        
        set(maximized) {
            if maximized {
                SDL_MaximizeWindow(self.sdlWindowPointer)
            } else {
                SDL_RestoreWindow(self.sdlWindowPointer)
            }
        }
    }
    
    public var minimized : Bool {
        get {
            return sdlWindowOptions.contains(.minimized)
        }
        
        set(minimized) {
            if minimized {
                SDL_MinimizeWindow(self.sdlWindowPointer)
            } else {
                SDL_RestoreWindow(self.sdlWindowPointer)
            }
        }
    }
    
    public func didReceiveEvent(event: SDL_Event) {
        let windowEventID = SDL_WindowEventID(SDL_WindowEventID.RawValue(event.window.event))
        
        switch windowEventID {
        case SDL_WINDOWEVENT_SIZE_CHANGED:
            self.dimensions = WindowSize(Float(event.window.data1), Float(event.window.data2))
        default:
            break
        }
    }
}

public struct SDLWindowOptions: OptionSet {
    public let rawValue: UInt32
    
    @inlinable
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    
    public static let fullscreen = SDLWindowOptions(rawValue: SDLWindowOptions.RawValue(SDL_WINDOW_FULLSCREEN.rawValue))
    
    // fullscreen window at the current desktop resolution
    public static let fullscreenDesktop = SDLWindowOptions(rawValue: SDLWindowOptions.RawValue(SDL_WINDOW_FULLSCREEN_DESKTOP.rawValue))
    
    // window usable with OpenGL context
    public static let openGL = SDLWindowOptions(rawValue: SDLWindowOptions.RawValue(SDL_WINDOW_OPENGL.rawValue))
    
    public static let shown = SDLWindowOptions(rawValue: SDLWindowOptions.RawValue(SDL_WINDOW_SHOWN.rawValue))
    
    public static let hidden = SDLWindowOptions(rawValue: SDLWindowOptions.RawValue(SDL_WINDOW_HIDDEN.rawValue))
    
    // no window decoration
    public static let borderless = SDLWindowOptions(rawValue: SDLWindowOptions.RawValue(SDL_WINDOW_BORDERLESS.rawValue))
    
    public static let resizeable = SDLWindowOptions(rawValue: SDLWindowOptions.RawValue(SDL_WINDOW_RESIZABLE.rawValue))
    
    public static let minimized = SDLWindowOptions(rawValue: SDLWindowOptions.RawValue(SDL_WINDOW_MINIMIZED.rawValue))
    
    public static let maximized = SDLWindowOptions(rawValue: SDLWindowOptions.RawValue(SDL_WINDOW_MAXIMIZED.rawValue))
    
    // window has grabbed input focus
    public static let inputGrabbed = SDLWindowOptions(rawValue: SDLWindowOptions.RawValue(SDL_WINDOW_INPUT_GRABBED.rawValue))
    
    // window has input focus
    public static let inputFocus = SDLWindowOptions(rawValue: SDLWindowOptions.RawValue(SDL_WINDOW_INPUT_FOCUS.rawValue))
    
    // window has mouse focus
    public static let mouseFocus = SDLWindowOptions(rawValue: SDLWindowOptions.RawValue(SDL_WINDOW_MOUSE_FOCUS.rawValue))
    
    // window not created by SDL
    public static let foreign = SDLWindowOptions(rawValue: SDLWindowOptions.RawValue(SDL_WINDOW_FOREIGN.rawValue))
    
    // window should be created in high-DPI mode if supported (>= SDL 2.0.1)
    public static let allowHighDpi = SDLWindowOptions(rawValue: SDLWindowOptions.RawValue(SDL_WINDOW_ALLOW_HIGHDPI.rawValue))
    
    // window has mouse captured (unrelated to INPUT_GRABBED, >= SDL 2.0.4)
    public static let mouseCapture = SDLWindowOptions(rawValue: SDLWindowOptions.RawValue(SDL_WINDOW_MOUSE_CAPTURE.rawValue))

    // window supports Vulkan
    public static let vulkan = SDLWindowOptions(rawValue: SDLWindowOptions.RawValue(SDL_WINDOW_VULKAN.rawValue))

}

#endif
