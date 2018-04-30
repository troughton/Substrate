//
//  CocoaWindow.swift
//  InterdimensionalLlama
//
//  Created by Thomas Roughton on 11/03/17.
//
//

#if os(macOS)


import RenderAPI
import MetalKit
import Metal
import AppKit

final class MTKEventView : MTKView {
    weak var inputDelegate : CocoaInputManager? = nil
 
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        self.inputDelegate?.processInputEvent(event)
        return true
    }
    
    override func mouseDown(with event: NSEvent) {
        self.inputDelegate?.processInputEvent(event)
    }
    
    override func mouseUp(with event: NSEvent) {
        self.inputDelegate?.processInputEvent(event)
    }
    
    override func rightMouseDown(with event: NSEvent) {
        self.inputDelegate?.processInputEvent(event)
    }
    
    override func rightMouseUp(with event: NSEvent) {
        self.inputDelegate?.processInputEvent(event)
    }
    
    override func otherMouseDown(with event: NSEvent) {
        self.inputDelegate?.processInputEvent(event)
    }
    
    override func otherMouseUp(with event: NSEvent) {
        self.inputDelegate?.processInputEvent(event)
    }
    
    public override func keyDown(with event: NSEvent) {
        self.inputDelegate?.processInputEvent(event)
    }
    
    public override func keyUp(with event: NSEvent) {
        self.inputDelegate?.processInputEvent(event)
    }
    
    public override func mouseMoved(with event: NSEvent) {
        self.inputDelegate?.processInputEvent(event)
    }
    
    public override func mouseDragged(with event: NSEvent) {
        self.inputDelegate?.processInputEvent(event)
    }
    
    public override func rightMouseDragged(with event: NSEvent) {
        self.inputDelegate?.processInputEvent(event)
    }
    
    public override func otherMouseDragged(with event: NSEvent) {
        self.inputDelegate?.processInputEvent(event)
    }
    
    public override func scrollWheel(with event: NSEvent) {
        self.inputDelegate?.processInputEvent(event)
    }
    
    public override func flagsChanged(with event: NSEvent) {
        self.inputDelegate?.processInputEvent(event)
    }
}


public class CocoaWindow : NSObject, Window, NSWindowDelegate {
    
    private let window : NSWindow
    public let view : MTKView
    public let device : MTLDevice
    
    public var isMainWindow: Bool = false
    
    public private(set) var title : String
    public var dimensions : WindowSize
    
    public let id : Int
    
    public var drawableSize: WindowSize {
        let drawableSize = self.view.drawableSize
        return WindowSize(Int(drawableSize.width), Int(drawableSize.height))
    }
    
    public var delegate: _WindowDelegate?
    
    public var hasFocus: Bool {
        return self.window.isKeyWindow
    }
    
    public var fullscreen: Bool = false {
        didSet {
            if oldValue != fullscreen { self.window.toggleFullScreen(nil) }
        }
    }
    
    public init(id: Int, title: String, dimensions: WindowSize, inputManager: CocoaInputManager) {
        self.id = id
        
        self.dimensions = dimensions
        
        let rect = NSRect(x: 100, y: 100, width: dimensions.width, height: dimensions.height)
        let style: NSWindow.StyleMask = [.titled , .closable , .resizable , .miniaturizable]
        
        let win = NSWindow(contentRect: rect, styleMask: style, backing: .buffered, defer: false)
        win.title = title
        win.makeKeyAndOrderFront(nil)
        
        win.acceptsMouseMovedEvents = true
        win.backgroundColor = NSColor.black
        self.window = win
        
        self.device = MTLCreateSystemDefaultDevice()! // RenderBackend.renderDevice as! MTLDevice
        
        let mtkView = MTKEventView(frame: win.frame, device: self.device)
        self.view = mtkView
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .invalid
        view.framebufferOnly = true
        mtkView.inputDelegate = inputManager
        
        view.layer?.isOpaque = true
//        (mtkView.layer as! CAMetalLayer).displaySyncEnabled = false
        
        self.view.autoresizingMask = [.width, .height]
        win.contentView = self.view
        win.initialFirstResponder = self.view
        
        self.title = title
        
        super.init()
        
        win.delegate = self
        
        win.makeFirstResponder(mtkView)
        
        self._texture = CachedValue(constructor: { [unowned self] in
            let texture = Texture(windowId: self.id, descriptor: self.textureDescriptor, isMinimised: false, nativeWindow: self.view)
            return texture
        })
    }
    
    private var _texture : CachedValue<Texture>!
    
    public var textureDescriptor : TextureDescriptor {
        return TextureDescriptor.texture2DDescriptor(pixelFormat: PixelFormat(rawValue: view.colorPixelFormat.rawValue)!, width: self.drawableSize.width, height: self.drawableSize.height, mipmapped: false)
    }
    
    public var texture : Texture {
        return _texture.value
    }
    
    public func cycleFrames() {
        _texture.reset()
    }
    
    public var nativeWindow: UnsafeMutableRawPointer {
        return Unmanaged.passUnretained(self.view).toOpaque()
    }
    
    public var context: UnsafeMutableRawPointer! {
        return Unmanaged.passUnretained(self.device).toOpaque()
    }
    
    public func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let currentSize = sender.frame.size
        let viewSize = self.view.bounds.size
        self.dimensions = WindowSize(Int(viewSize.width + frameSize.width - currentSize.width), Int(viewSize.height + frameSize.height - currentSize.height))
        
        return frameSize
    }
    
    public func windowDidResize(_ notification: Notification) {
        self.delegate?.drawableSizeDidChange(on: self)
    }
    
    public func windowDidChangeBackingProperties(_ notification: Notification) {
        self.delegate?.drawableSizeDidChange(on: self)
    }
    
    public func displayOpenDialog(allowedFileTypes: [String], options: FileChooserOptions) -> [URL]? {
        var urls : [URL]? = nil
        DispatchQueue.main.sync {
            let panel = NSOpenPanel()
            panel.allowedFileTypes = allowedFileTypes
            panel.allowsOtherFileTypes = options.contains(.allowsOtherFileTypes)
            panel.canChooseFiles = options.contains(.canChooseFiles)
            panel.canChooseDirectories = options.contains(.canChooseDirectories)
            panel.allowsMultipleSelection = options.contains(.allowsMultipleSelection)
            
            if panel.runModal() == NSApplication.ModalResponse.OK {
                urls = panel.urls
            }
        }
        return urls
    }
    
    public func displaySaveDialog(allowedFileTypes: [String], options: FileChooserOptions) -> URL? {
        var url : URL? = nil
        DispatchQueue.main.sync {
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.allowedFileTypes = allowedFileTypes
            panel.allowsOtherFileTypes = options.contains(.allowsOtherFileTypes)
            
            if panel.runModal() == NSApplication.ModalResponse.OK {
                url = panel.url
            }
            
        }
        return url
    }
}


extension _WindowDelegate {
    public func drawableSizeDidChange(on window: Window) {
        
    }
}

#endif
