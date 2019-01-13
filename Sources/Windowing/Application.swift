//
//  AppDelegate.swift
//  CGRA 402
//
//  Created by Thomas Roughton on 9/03/17.
//  Copyright (c) 2017 Thomas Roughton. All rights reserved.
//

import SwiftMath
import SwiftFrameGraph
import DrawTools
import Foundation

public class Application {
    static var sharedApplication : Application! = nil
    
    private var renderer : Renderer
    private var gameplayScheduler : GameplayScheduler
    
    public var windows : [Window]
    private var windowDelegates : [WindowDelegate]
    
    private var timeLastUpdate = DispatchTime.now().uptimeNanoseconds
    
    public var inputManager : InputManager
    
    public let inputLayers : [InputLayer]
    let imguiInputLayer : ImGuiInputLayer
    
    let gameplaySemaphore = DispatchSemaphore(value: 1)
    
    private var currentFrame : UInt64 = 0
    
    static func earlyInit() {
        ImGui.createContext()
    }
    
    init(windowDelegates: [WindowDelegate], windows: [Window], inputManager: InputManager, renderer: Renderer, gameplayScheduler: GameplayScheduler) {
        self.renderer = renderer
        self.gameplayScheduler = gameplayScheduler
        self.inputManager = inputManager
        self.windows = windows
        self.windowDelegates = windowDelegates
        
        let mainWindow = self.windows.first!
        mainWindow.isMainWindow = true
        
        
        self.imguiInputLayer = ImGuiInputLayer()
        
        var inputLayers : [InputLayer] = [self.imguiInputLayer]
        windowDelegates.forEach {
            inputLayers.append(contentsOf: $0.inputLayers)
        }
        
        self.windows.forEach {
            $0.delegate?.window = $0
        }
        
        self.inputLayers = inputLayers
        
        ImGui.initialiseRendering(mainWindow: mainWindow)
        
        assert(Application.sharedApplication == nil)
        Application.sharedApplication = self
        
        self.gameplayScheduler.start(updateLoop: self.updateLoop)
    }
    
    deinit {
        ImGui.destroyContext()
    }
    
    func nextAvailableWindowId() -> Int {
        if let (offset, _) =  self.windows.enumerated().first(where: { $0 != $1.id }) {
            return offset
        } else {
            return self.windows.count
        }
    }
    
    func update() {
        self.gameplaySemaphore.wait() // Wait for the previous gameplay stage to finish.
        
        let time = DispatchTime.now().uptimeNanoseconds
        Timing.deltaTime = Double(time - timeLastUpdate) * 1e-9
        Timing.currentGameplayFrame = self.currentFrame
        
        self.inputManager.update(windows: self.windows)
        
        var inputState = self.inputManager.inputState
        for layer in self.inputLayers {
            layer.processInput(rawInput: &inputState, frame: self.inputManager.frame)
        }
        
        var renderRequests = [RenderRequest]()
        
        ImGui.beginFrame(windows: self.windows, inputLayer: self.imguiInputLayer)
        
        self.windows.forEach { window in
            guard let delegate = window.delegate as? WindowDelegate else { return }
            renderRequests += delegate.update(frame: self.currentFrame)
        }
        
        ImGui.render()
        
        #if os(iOS)
        let imguiData = ImGui.renderData(drawData: ImGui.drawData!, clipScale: screens[0].backingScaleFactor)
        let window = windows[0]
        renderRequests.append(
            RenderRequest(source: .imgui(imguiData), destination: .window(window), scissor: window.drawableSize.scissorRect)
        )
        #else
        ImGui.updatePlatformWindows()
        
        for i in 0..<Int(ImGui.platformIO.pointee.Viewports.Size) {
            let viewport = ImGui.platformIO.pointee.Viewports.Data[i]!
            let window = viewport.pointee.window
            let imguiData = ImGui.renderData(drawData: viewport.pointee.DrawData, clipScale: viewport.pointee.DpiScale)
            renderRequests.append(
                RenderRequest(source: .imgui(imguiData), destination: .window(window), scissor: window.drawableSize.scissorRect)
            )
        }
        #endif
        
        self.renderer.render(frame: self.currentFrame, renderRequests: renderRequests, windows: windows)
        self.renderer.renderStartedSemaphore.wait() // Wait for rendering to begin...
        self.gameplaySemaphore.signal() // before we start the next gameplay stage.
        
        timeLastUpdate = time
        self.currentFrame += 1
    }
    
    func updateLoop() {
        while !self.inputManager.shouldQuit {  // Enter main loop.
            self.gameplayScheduler.waitUntilUpdate()
            
            autoreleasepool {
                self.update()
            }
        }
        self.gameplayScheduler.shouldQuit = true
        Application.sharedApplication = nil
        print("Exiting the program.")
        
    }
    
    public func createWindow(title: String, dimensions: WindowSize, flags: WindowCreationFlags) -> Window {
        fatalError("createWindow(title:dimensions:flags:) needs concrete implementation.")
    }
    
    public func destroyWindow(window: Window) {
        self.windows.remove(at: self.windows.firstIndex(where: { $0 === window })!)
    }
    
    public func setCursorPosition(to position: Vector2f) {
        fatalError("setCursorPosition(to:) needs concrete implementation.")
    }
    
    public var screens : [Screen] {
        fatalError("screens needs concrete implementation.")
    }
}
