//
//  iOSApplication.swift
//  Renderer
//
//  Created by Thomas Roughton on 20/01/18.
//

#if os(iOS)

import SwiftMath
import SwiftFrameGraph
import UIKit
import MetalKit
import ImGui

final class CocoaInputManager : InputManagerInternal {
    
    var inputState = InputState<RawInputState>()
    
    var shouldQuit: Bool = false
    var frame: UInt64 = 0
    
    init() {
        
    }
    
    func updateMousePosition(_ touch: UITouch) {
        var location = touch.preciseLocation(in: touch.window)
        if let window = touch.window {
            location.y = window.bounds.height - location.y
        }
        
        inputState[.mouse][.mouseX] = RawInputState(value: Float(location.x), frame: self.frame)
        inputState[.mouse][.mouseY] = RawInputState(value: Float(location.y), frame: self.frame)
        inputState[.mouse][.mouseXInWindow] = RawInputState(value: Float(location.x), frame: self.frame)
        inputState[.mouse][.mouseYInWindow] = RawInputState(value: Float(location.y), frame: self.frame)
    }
    
    func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let touch = touches.first!
        self.updateMousePosition(touch)
        
    
        inputState[.mouse][.mouseButtonLeft] = RawInputState(active: true, frame: frame)
    }
    
    func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let touch = touches.first!
        self.updateMousePosition(touch)
        
        let location = touch.preciseLocation(in: touch.window)
        let previousLocation = touch.precisePreviousLocation(in: touch.window)
        
        let deltaX = location.x - previousLocation.x
        let deltaY = location.y - previousLocation.y
        
        inputState[.mouse][.mouseXRelative] = RawInputState(value: Float(deltaX), frame: self.frame)
        inputState[.mouse][.mouseYRelative] = RawInputState(value: Float(-deltaY), frame: self.frame)
    }
    
    func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let touch = touches.first!
        self.updateMousePosition(touch)
        
        inputState[.mouse][.mouseButtonLeft].markInactive()
    }
    
    func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        inputState[.mouse][.mouseButtonLeft].markInactive()
    }
    
    
    func insertText(_ text: String) {
        ImGui.io.pointee.addUTF8InputCharacters(text.utf8CString)
    }
    
    func deleteBackward() {
        inputState[.keyboard][.backspace] = RawInputState(active: true, frame: self.frame)
        inputState[.keyboardScanCode][.backspace] = RawInputState(active: true, frame: self.frame)
    }
    
    func update() {
        self.frame = self.frame &+ 1
    }
}

public class CocoaApplication : Application {
    
    let contentScaleFactor : Float
    
    public init(delegate: AppDelegate?, viewController: UIViewController, windowDelegate: @autoclosure () -> WindowDelegate, updateScheduler: MetalUpdateScheduler, windowFrameGraph: FrameGraph) {
        delegate?.applicationWillInitialise()
        
        let inputManager = CocoaInputManager()
        
        let windowDelegate = windowDelegate()
        
        let window = CocoaWindow(viewController: viewController, inputManager: inputManager)
        window.delegate = windowDelegate
        
        let windows : [Window] = [window]
        self.contentScaleFactor = Float(viewController.view.contentScaleFactor)
        
        super.init(updateables: [windowDelegate], windows: windows, inputManager: inputManager, updateScheduler: updateScheduler, windowFrameGraph: windowFrameGraph)
    }
    
    public override func createWindow(title: String, dimensions: WindowSize, flags: WindowCreationFlags) -> Window {
        fatalError("Can't create windows on iOS")
    }
    
    public override func setCursorPosition(to position: SIMD2<Float>) {
    }
    
    public override var screens : [Screen] {
        return [Screen(position: WindowPosition(0, 0),
                       dimensions: self.windows[0].dimensions,
                       workspacePosition: WindowPosition(0, 0),
                       workspaceDimensions: self.windows[0].dimensions,
                       backingScaleFactor: self.contentScaleFactor)]
    }
}

#endif // os(iOS)

