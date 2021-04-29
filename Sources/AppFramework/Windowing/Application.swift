//
//  AppDelegate.swift
//  CGRA 402
//
//  Created by Thomas Roughton on 9/03/17.
//  Copyright (c) 2017 Thomas Roughton. All rights reserved.
//

import Substrate
import ImGui
import Foundation

public protocol ApplicationDelegate : AnyObject {
    func applicationWillInitialise()
    func applicationDidInitialise(_ application: Application)
    func applicationWillUpdate(_ application: Application, frame: UInt64, deltaTime: Double)
    func applicationDidUpdate(_ application: Application, frame: UInt64, deltaTime: Double)
    func applicationDidBeginImGuiFrame(_ application: Application, frame: UInt64, deltaTime: Double)
    func applicationRenderedImGui(_ application: Application, frame: UInt64, renderData: ImGui.RenderData, window: Window, scissorRect: ScissorRect)
    func applicationWillExit(_ application: Application)
}

extension ApplicationDelegate {
    public func applicationWillInitialise() {}
    public func applicationDidInitialise(_ application: Application) {}
    public func applicationWillUpdate(_ application: Application, frame: UInt64, deltaTime: Double) {}
    public func applicationDidUpdate(_ application: Application, frame: UInt64, deltaTime: Double) {}
    public func applicationDidBeginImGuiFrame(_ application: Application, frame: UInt64, deltaTime: Double) {}
    public func applicationRenderedImGui(_ application: Application, frame: UInt64, renderData: ImGui.RenderData, window: Window, scissorRect: ScissorRect) {}
    public func applicationWillExit(_ application: Application) {}
}

public class Application {
    public static var sharedApplication : Application! = nil
    
    let updateScheduler : UpdateScheduler
    
    public internal(set) var windows : [Window]
    public private(set) var updateables : [FrameUpdateable]
    
    public let windowRenderGraph : RenderGraph
    public var inputManager : InputManager
    public internal(set) var inputLayers : [InputLayer]
    let imguiInputLayer : ImGuiInputLayer
    
    private var currentFrame : UInt64 = 0
    private var timeLastUpdate = DispatchTime.now().uptimeNanoseconds
    
    public weak var delegate : ApplicationDelegate? = nil
    
    init(delegate: ApplicationDelegate?, updateables: [FrameUpdateable], inputManager: @autoclosure () -> InputManager, updateScheduler: UpdateScheduler, windowRenderGraph: RenderGraph) {
        ImGui.createContext()
        RenderGraph.initialise()
        
        self.inputManager = inputManager()
        self.windows = []
        self.updateables = []
        self.updateScheduler = updateScheduler
        self.windowRenderGraph = windowRenderGraph
        
        self.imguiInputLayer = ImGuiInputLayer()
        self.inputLayers = [self.imguiInputLayer]
        
        assert(Application.sharedApplication == nil)
        Application.sharedApplication = self
        
        for updateable in updateables {
            self.addUpdateable(updateable)
        }
        
        self.delegate = delegate
        delegate?.applicationDidInitialise(self)
        
        // ImGui.initialisePlatformInterface is called after applicationDidInitialise to give the application a chance to e.g. set its own fonts.
        ImGui.initialisePlatformInterface()
    }
    
    public func addUpdateable(_ updateable: FrameUpdateable) {
        self.updateables.append(updateable)
        if let windowDelegate = updateable as? WindowDelegate {
            let window = self.createWindow(title: windowDelegate.title, dimensions: windowDelegate.desiredSize, flags: .resizable, renderGraph: self.windowRenderGraph)
            window.delegate = windowDelegate
            windowDelegate.window = window
            inputLayers.append(contentsOf: windowDelegate.inputLayers)
        }
    }
    
    public func removeUpdateable(_ updateable: FrameUpdateable) {
        if let windowDelegate = updateable as? WindowDelegate {
            for layer in windowDelegate.inputLayers {
                self.inputLayers.removeAll(where: { $0 === layer })
            }
            self.destroyWindow(windowDelegate.window)
        }
        self.updateables.remove(at: self.updateables.firstIndex(where: { $0 === updateable })!)
    }
    
    deinit {
        Application.sharedApplication = nil
        self.delegate?.applicationWillExit(self)
        ImGui.destroyContext()
    }
    
    func nextAvailableWindowId() -> Int {
        if let (offset, _) =  self.windows.enumerated().first(where: { $0 != $1.id }) {
            return offset
        } else {
            return self.windows.count
        }
    }
    
    func processInput(frame: UInt64) {
        self.inputManager.update(frame: frame, windows: self.windows)
        
        var inputState = self.inputManager.inputState
        for layer in self.inputLayers {
            layer.processInput(rawInput: &inputState, frame: frame)
        }
    }
    
    func updateFrameUpdateables(frame: UInt64, deltaTime: Double) {
        if !self.windows.isEmpty {
            ImGui.beginFrame(windows: self.windows, inputLayer: self.imguiInputLayer, deltaTime: deltaTime)
            self.delegate?.applicationDidBeginImGuiFrame(self, frame: frame, deltaTime: deltaTime)
        }
        
        self.updateables.forEach {
            $0.update(frame: frame, deltaTime: deltaTime)
        }
        
        if !self.windows.isEmpty {
            ImGui.render()
            
            #if os(iOS)
            let imguiData = ImGui.renderData(drawData: ImGui.drawData!, clipScale: screens[0].backingScaleFactor)
            let window = windows[0]
            self.delegate?.applicationRenderedImGui(self, frame: frame, data: imguiData, window: window, scissorRect: window.drawableSize.scissorRect)
            #else
            ImGui.updatePlatformWindows()
            
            for i in 0..<Int(ImGui.platformIO.pointee.Viewports.Size) {
                let viewport = ImGui.platformIO.pointee.Viewports.Data[i]!
                let window = viewport.pointee.window
                let imguiData = ImGui.renderData(drawData: viewport.pointee.DrawData, clipScale: viewport.pointee.DpiScale)
                self.delegate?.applicationRenderedImGui(self, frame: frame, renderData: imguiData, window: window, scissorRect: window.drawableSize.scissorRect)
            }
            #endif
        }
    }
    
    public func update() {
        let currentTime = DispatchTime.now().uptimeNanoseconds
        let deltaTime = Double(currentTime - self.timeLastUpdate) * 1e-9
        
        self.delegate?.applicationWillUpdate(self, frame: self.currentFrame, deltaTime: deltaTime)
        
        for window in self.windows {
            window.cycleFrames()
        }
        self.processInput(frame: self.currentFrame)
        
        self.updateFrameUpdateables(frame: self.currentFrame, deltaTime: deltaTime)
        
        self.delegate?.applicationDidUpdate(self, frame: self.currentFrame, deltaTime: deltaTime)
        
        self.currentFrame += 1
        self.timeLastUpdate = currentTime
    }
    
    public func createWindow(title: String, dimensions: WindowSize, flags: WindowCreationFlags, renderGraph: RenderGraph) -> Window {
        fatalError("createWindow(title:dimensions:flags:) needs concrete implementation.")
    }
    
    public func destroyWindow(_ window: Window) {
        self.windows.remove(at: self.windows.firstIndex(where: { $0 === window })!)
    }
    
    public func setCursorPosition(to position: SIMD2<Float>) {
        fatalError("setCursorPosition(to:) needs concrete implementation.")
    }
    
    public var screens : [Screen] {
        fatalError("screens needs concrete implementation.")
    }
}
