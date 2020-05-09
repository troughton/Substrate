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
import ImGui

public class CocoaApplication : Application {
    
    public init(delegate: ApplicationDelegate?, updateables: @autoclosure () -> [FrameUpdateable], updateScheduler: UpdateScheduler, windowFrameGraph: FrameGraph) {
        delegate?.applicationWillInitialise()
        
        let updateables = updateables()
        precondition(!updateables.isEmpty)
        
        super.init(delegate: delegate, updateables: updateables, inputManager: CocoaInputManager(), updateScheduler: updateScheduler, windowFrameGraph: windowFrameGraph)
    }
    
    public override func createWindow(title: String, dimensions: WindowSize, flags: WindowCreationFlags, frameGraph: FrameGraph) -> Window {
        let window = CocoaWindow(id: self.nextAvailableWindowId(), title: title, dimensions: dimensions, inputManager: self.inputManager as! CocoaInputManager, flags: flags, frameGraph: frameGraph)
        
        window.mtkView.isPaused = true
        window.mtkView.enableSetNeedsDisplay = true
        
        self.windows.append(window)
        return window
    }
    
    public override func setCursorPosition(to position: SIMD2<Float>) {
        CGWarpMouseCursorPosition(CGPoint(x: CGFloat(position.x), y: CGFloat(position.y)))
    }
    
    public override var screens : [Screen] {
        var screens = [Screen]()
        for nsScreen in NSScreen.screens {
            screens.append(Screen(nsScreen))
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
