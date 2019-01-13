//
//  CocoaApplication.swift
//  Renderer
//
//  Created by Thomas Roughton on 20/01/18.
//

#if os(macOS)

import SwiftMath
import SwiftFrameGraph
import Cocoa
import MetalKit
import DrawTools

import MetalRenderer

public class CocoaApplication : Application {
    
    public init(windowDelegates: () -> [WindowDelegate]) {
        
        Application.earlyInit()
        
        let renderBackend = MetalBackend(numInflightFrames: RenderMaxInflightFrames)
        let renderer = Renderer(backend: renderBackend)
        
        let inputManager = CocoaInputManager()
        
        let windowDelegates = windowDelegates()
        precondition(!windowDelegates.isEmpty)
        
        let windows = windowDelegates.enumerated().map { (i, windowDelegate) -> Window in
            let dimensions = windowDelegate.desiredSize
            
            let window = CocoaWindow(id: i, title: windowDelegate.title, dimensions: dimensions, inputManager: inputManager, flags: [.resizable])
            window.delegate = windowDelegate
            return window
        }
        
        let gameplayScheduler = MetalRenderScheduler(windows: windows)
        
        super.init(windowDelegates: windowDelegates, windows: windows, inputManager: inputManager, renderer: renderer, gameplayScheduler: gameplayScheduler)
    }
    
    public override func createWindow(title: String, dimensions: WindowSize, flags: WindowCreationFlags) -> Window {
        let window = DispatchQueue.main.sync { CocoaWindow(id: self.nextAvailableWindowId(), title: title, dimensions: dimensions, inputManager: self.inputManager as! CocoaInputManager, flags: flags) }
        self.windows.append(window)
        return window
    }
    
    public override func setCursorPosition(to position: Vector2f) {
        CGWarpMouseCursorPosition(CGPoint(x: CGFloat(position.x), y: CGFloat(position.y)))
    }
    
    public override var screens : [Screen] {
        var screens = [Screen]()
        DispatchQueue.main.sync {
            for nsScreen in NSScreen.screens {
                screens.append(Screen(nsScreen))
            }
        }
        return screens
    }
}

extension Screen {
    init(_ nsScreen: NSScreen) {
        self.position = WindowPosition(Float(nsScreen.frame.minX), Float(nsScreen.frame.minY))
        self.dimensions = WindowSize(Float(nsScreen.frame.width), Float(nsScreen.frame.height))
        
        self.workspacePosition = WindowPosition(Float(nsScreen.visibleFrame.minX), Float(nsScreen.visibleFrame.minY))
        self.workspaceDimensions = WindowSize(Float(nsScreen.visibleFrame.width), Float(nsScreen.visibleFrame.height))
        
        self.backingScaleFactor = Float(nsScreen.backingScaleFactor)
    }
}

#endif
