//
//  UpdateScheduler.swift
//  CGRAGame
//
//  Created by Joseph Bennett on 14/05/17.
//  Copyright © 2017 Team Llama. All rights reserved.
//

import Dispatch
import Substrate

@_silgen_name("swift_task_runAndBlockThread")
public func runAsyncAndBlock(_ asyncFun: @escaping () async -> ())

@MainActor
public protocol UpdateScheduler {
}

#if canImport(CSDL2) && !(os(iOS) || os(tvOS) || (os(macOS) && arch(arm64)))

public final class SDLUpdateScheduler : UpdateScheduler  {
    public init(appDelegate: ApplicationDelegate?, windowDelegates: @escaping @autoclosure () -> [WindowDelegate], windowRenderGraph: RenderGraph) async {
        let application = await SDLApplication(delegate: appDelegate, updateables: windowDelegates(), updateScheduler: self, windowRenderGraph: windowRenderGraph)
    
        while !application.inputManager.shouldQuit {
            await application.update()
        }
    }
}

#endif // canImport(CSDL2)

#if os(macOS)

import MetalKit

@MainActor
public final class MetalUpdateScheduler : NSObject, UpdateScheduler, MTKViewDelegate  {
    private var application : CocoaApplication! = nil
    var previousTask: Task<Void, Never>?
    
    public init(appDelegate: ApplicationDelegate?, windowDelegates: @autoclosure () async -> [WindowDelegate], windowRenderGraph: RenderGraph) async {
        super.init()
        
        self.application = await CocoaApplication(delegate: appDelegate, updateables: await windowDelegates(), updateScheduler: self, windowRenderGraph: windowRenderGraph)
        
        let mainWindow = application.windows.first! as! MTKWindow
    
        let view = mainWindow.mtkView
        view.delegate = self
    
        view.enableSetNeedsDisplay = false
        view.isPaused = false
    }
    
    public func draw(in view: MTKView) {
        if application.inputManager.shouldQuit {
            NSApp.terminate(nil)
            return
        }
        
        for window in application.windows.dropFirst() {
            (window as! MTKWindow).mtkView.draw()
        }
        
        let previousTask = self.previousTask
        self.previousTask = detach {
            await previousTask?.get()
            await self.application.update()
        }
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    }
}

#elseif os(iOS) || os(tvOS)

import MetalKit

public final class MetalUpdateScheduler : NSObject, UpdateScheduler, MTKViewDelegate  {
    private var vsyncUpdate : Bool = false
    private var application : CocoaApplication! = nil

    public init(appDelegate: ApplicationDelegate?, viewController: UIViewController, windowDelegate: @escaping @autoclosure () -> WindowDelegate, windowRenderGraph: RenderGraph) {
        super.init()

        self.application = CocoaApplication(delegate: appDelegate, viewController: viewController, windowDelegate: windowDelegate(), updateScheduler: self, windowRenderGraph: windowRenderGraph)
        
        let mainWindow = application.windows.first! as! MTKWindow
        
        let view = mainWindow.mtkView
        view.delegate = self

        for window in application.windows.dropFirst() {
            (window as! MTKWindow).mtkView.isPaused = true
            (window as! MTKWindow).mtkView.enableSetNeedsDisplay = true
        }
    }

    public func draw(in view: MTKView) {
        if application.inputManager.shouldQuit {
            return
        }
        
        for window in application.windows.dropFirst() {
            (window as! MTKWindow).mtkView.draw()
        }
        
        autoreleasepool {
            application.update()
        }
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        if let window = (view as! MTKEventView).frameworkWindow {
            window.delegate?.drawableSizeDidChange(on: window)
        }
    }
}

#endif // canImport(MetalKit)
