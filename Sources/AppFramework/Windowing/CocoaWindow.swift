//
//  CocoaWindow.swift
//  InterdimensionalLlama
//
//  Created by Thomas Roughton on 11/03/17.
//
//

import SubstrateUtilities
import Substrate

#if os(macOS) || os(iOS)
import MetalKit
import Metal

public protocol MTKWindow {
    var mtkView : MTKView { get }
}

#endif

#if os(macOS)
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

public final class CocoaNSWindow : NSWindow {
    public override var canBecomeKey: Bool {
        return true
    }
    
    public override var canBecomeMain: Bool {
        return true
    }
}

public class CocoaWindow : NSObject, Window, NSWindowDelegate, MTKWindow {
    internal let window : NSWindow
    public let mtkView : MTKView
    public let device : MTLDevice
    
    public var title : String {
        get {
            return self.window.title
        }
        
        set {
            self.window.title = newValue
        }
    }
    
    private var _dimensions : WindowSize
    
    public var dimensions : WindowSize {
        get {
            return _dimensions
        }
        set {
            let position = self.position
            _dimensions = newValue
            self.window.setContentSize(NSSize(width: Int(_dimensions.width), height: Int(_dimensions.height)))
            self.position = position // Resizing happens from the bottom left, whereas we want to maintain the position from the top left.
        }
    }
    
    public var position: WindowPosition {
        get {
            guard let screen = self.window.screen else { return WindowPosition(0, 0) }
            
            let frame = self.window.frame
            
            let screenTop = screen.frame.origin.y + screen.frame.height
            let positionOnScreenY = Float(frame.origin.y) + self.dimensions.height // Excluding the title bar.
            let positionY = Float(screenTop) - positionOnScreenY
            return WindowPosition(Float(frame.origin.x), Float(positionY))
        }
        
        set {
            guard let screen = self.window.screen else { return }
            
            let yToTransform = newValue.y + self.dimensions.height // the bottom-left corner.
            
            let screenTop = screen.frame.origin.y + screen.frame.height
            let positionOnScreenY = screenTop - CGFloat(yToTransform)
            self.window.setFrameOrigin(NSPoint(x: CGFloat(newValue.x), y: CGFloat(positionOnScreenY)))
        }
    }
    
    public let id : Int
    
    var _texture = CachedAsync<Texture>()
    
    public var drawableSize: WindowSize {
        let drawableSize = self.mtkView.drawableSize
        return WindowSize(Float(drawableSize.width), Float(drawableSize.height))
    }
    
    public var delegate: WindowDelegate?
    
    public var hasFocus: Bool {
        get {
            return self.window.isKeyWindow
        }
        set {
            if newValue {
                self.window.makeKey()
            }
        }
    }
    
    public var isVisible: Bool {
        get {
            return self.window.isVisible
        }
        set {
            if newValue {
                self.window.orderFront(nil)
            } else {
                self.window.orderOut(nil)
            }
        }
    }
    
    public var fullscreen: Bool = false {
        didSet {
            if oldValue != fullscreen { self.window.toggleFullScreen(nil) }
        }
    }
    
    public var windowsInFrontCount: Int {
        return self.window.orderedIndex
    }
    
    public var alpha : Float {
        get {
            return self.window.isOpaque ? 1.0 : Float(self.window.alphaValue)
        }
        set {
            if newValue >= 1.0 {
                self.window.isOpaque = true
            } else {
                self.window.isOpaque = false
                self.window.alphaValue = CGFloat(newValue)
            }
        }
    }
    
    public init(id: Int, title: String, dimensions: WindowSize, inputManager: CocoaInputManager, flags: WindowCreationFlags, renderGraph: RenderGraph) {
        self.id = id
        
        self._dimensions = dimensions
        
        let rect = NSRect(x: 100, y: 100, width: Int(exactly: dimensions.width)!, height: Int(exactly: dimensions.height)!)
        
        var style: NSWindow.StyleMask = flags.contains(.borderless) ? [.borderless] :  [.titled , .closable, .miniaturizable]
        if flags.contains(.resizable) {
            style.formUnion(.resizable)
        }
        
        let win = CocoaNSWindow(contentRect: rect, styleMask: style, backing: .buffered, defer: false)
        win.title = title
        
        if !flags.contains(.hidden) {
            win.makeKeyAndOrderFront(nil)
        }
        
        win.acceptsMouseMovedEvents = true
        win.backgroundColor = NSColor.black
        self.window = win
        
        self.device = RenderBackend.renderDevice as! MTLDevice
        
        let mtkView = MTKEventView(frame: win.frame, device: self.device)
        self.mtkView = mtkView
        if win.screen?.canRepresent(.p3) ?? false {
            mtkView.colorPixelFormat = .bgr10a2Unorm
            mtkView.colorspace = CGColorSpace(name: CGColorSpace.linearSRGB)
        } else {
            mtkView.colorPixelFormat = .bgra8Unorm_srgb
        }
        mtkView.depthStencilPixelFormat = .invalid
        mtkView.framebufferOnly = true
        mtkView.inputDelegate = inputManager
        
        mtkView.layer?.isOpaque = true
        (mtkView.layer as! CAMetalLayer).displaySyncEnabled = false
        (mtkView.layer as! CAMetalLayer).wantsExtendedDynamicRangeContent = true
        mtkView.autoResizeDrawable = true
        
        self.mtkView.autoresizingMask = [.width, .height]
        win.contentView = self.mtkView
        win.initialFirstResponder = self.mtkView
        
        
        super.init()
        
        win.delegate = self
        win.makeFirstResponder(mtkView)
        win.isReleasedWhenClosed = false
        
        self._texture.constructor = { [unowned(unsafe) self] in
            return await self.getTexture(renderGraph: renderGraph)
        }
    }
    
    deinit {
        if Thread.isMainThread {
            self.window.close()
        } else {
            let window = self.window
            DispatchQueue.main.async {
                window.close()
            }
        }
    }
    
    @MainActor
    private func getTexture(renderGraph: RenderGraph) async -> Texture {
        return await Texture(descriptor: self.textureDescriptor, isMinimised: false, nativeWindow: self.mtkView.layer as Any, renderGraph: renderGraph)
    }
    
    public func texture() async -> Texture {
        return await _texture.getValue()
    }
    
    public var textureDescriptor : TextureDescriptor {
        return TextureDescriptor(type: .type2D, format: PixelFormat(rawValue: mtkView.colorPixelFormat.rawValue)!, width: Int(exactly: self.drawableSize.width)!, height: Int(exactly: self.drawableSize.height)!, mipmapped: false)
    }
    
    public func cycleFrames() {
        _texture.reset()
    }
    
    public var nativeWindow: UnsafeMutableRawPointer {
        return Unmanaged.passUnretained(self.mtkView).toOpaque()
    }
    
    public var context: UnsafeMutableRawPointer! {
        return Unmanaged.passUnretained(self.device).toOpaque()
    }
    
    public func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let currentSize = sender.frame.size
        let viewSize = self.mtkView.bounds.size
        self._dimensions = WindowSize(Float(viewSize.width + frameSize.width - currentSize.width), Float(viewSize.height + frameSize.height - currentSize.height))
        
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
        let panel = NSOpenPanel()
        panel.allowedFileTypes = allowedFileTypes
        panel.allowsOtherFileTypes = options.contains(.allowsOtherFileTypes)
        panel.canChooseFiles = options.contains(.canChooseFiles)
        panel.canChooseDirectories = options.contains(.canChooseDirectories)
        panel.allowsMultipleSelection = options.contains(.allowsMultipleSelection)
        
        if panel.runModal() == NSApplication.ModalResponse.OK {
            urls = panel.urls
        }
        return urls
    }
    
    public func windowWillClose(_ notification: Notification) {
        //        NSApp.terminate(self)
    }
    
    public func displaySaveDialog(allowedFileTypes: [String], options: FileChooserOptions) -> URL? {
        var url : URL? = nil
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedFileTypes = allowedFileTypes
        panel.allowsOtherFileTypes = options.contains(.allowsOtherFileTypes)
        
        if panel.runModal() == NSApplication.ModalResponse.OK {
            url = panel.url
        }
        return url
    }
}

#endif

extension WindowDelegate {
    public func drawableSizeDidChange(on window: Window) {
        
    }
}
