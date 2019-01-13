//
//  RenderScheduler.swift
//  CGRAGame
//
//  Created by Joseph Bennett on 14/05/17.
//  Copyright © 2017 Team Llama. All rights reserved.
//



import Dispatch

protocol GameplayScheduler {
    func start(updateLoop: @escaping () -> Void)
    func waitUntilUpdate()
    var shouldQuit : Bool { get set }
}

#if SDL_WINDOWING

public final class SDLRenderScheduler : GameplayScheduler  {
    public var shouldQuit : Bool = false
    
    init() {
    }
    
    public func start(updateLoop: @escaping () -> Void) {
        updateLoop()
    }
    
    public func waitUntilUpdate() {
        // Don't wait; just proceed as quickly as possible
    }
}

#endif

#if canImport(MetalKit)

import MetalKit

public final class MetalRenderScheduler : NSObject, GameplayScheduler, MTKViewDelegate  {
    private let updateTrigger: DispatchSemaphore
    let windows : [Window]

    public var shouldQuit : Bool = false
    private var shouldStart : Bool = false
    private var vsyncUpdate : Bool = false

    init(windows: [Window]) {
        self.updateTrigger = DispatchSemaphore(value: 0)
        self.windows = windows
        
        super.init()
        
        let mainWindow = windows.first! as! MTKWindow
        
        let view = mainWindow.mtkView
        view.delegate = self
        
        for window in windows.dropFirst() {
            (window as! MTKWindow).mtkView.isPaused = true
            (window as! MTKWindow).mtkView.enableSetNeedsDisplay = true
        }
        
        view.isPaused = true
    #if os(macOS)
        self.vsyncUpdate = (view.layer as! CAMetalLayer).displaySyncEnabled
    #else
        self.vsyncUpdate = true
    #endif
    }
    
    public func start(updateLoop: @escaping () -> Void) {
        (self.windows.first as! MTKWindow?)?.mtkView.isPaused = false

        let applicationQueue = DispatchQueue(label: "Application Queue", qos: .userInteractive)
        applicationQueue.async {
            updateLoop()
        }
    }
    
    public func draw(in view: MTKView) {
        for window in windows.dropFirst() {
            (window as! MTKWindow).mtkView.draw()
        }
        
        if self.vsyncUpdate {
            self.updateTrigger.signal()
        }
    }
    
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    }

    public func waitUntilUpdate() {
        if !self.vsyncUpdate {
            return
        }
        
        self.updateTrigger.wait()

        while case .success = self.updateTrigger.wait(timeout: .now()) {
            // Drain the semaphore.
        }
    }
}

#endif // canImport(MetalKit)
