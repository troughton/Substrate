//
//  UpdateScheduler.swift
//  CGRAGame
//
//  Created by Joseph Bennett on 14/05/17.
//  Copyright © 2017 Team Llama. All rights reserved.
//

import Dispatch
import Substrate

public protocol UpdateScheduler {
}

#if canImport(CSDL2) && !(os(macOS) && arch(arm64))

public final class SDLUpdateScheduler : UpdateScheduler  {
    public init(appDelegate: ApplicationDelegate?, windowDelegates: @escaping @autoclosure () -> [WindowDelegate], windowRenderGraph: RenderGraph) {
        let application = SDLApplication(delegate: appDelegate, updateables: windowDelegates(), updateScheduler: self, windowRenderGraph: windowRenderGraph)
    
        while !application.inputManager.shouldQuit {
            #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
            autoreleasepool {
                runAsyncAndBlock {
                    await application.update()
                }
            }
            #else
            runAsyncAndBlock {
                await application.update()
            }
            #endif
        }
    }
}

#endif // canImport(CSDL2)

#if os(macOS)

import MetalKit

public final class MetalUpdateScheduler : NSObject, UpdateScheduler, MTKViewDelegate  {
    private var application : CocoaApplication! = nil
    
    public init(appDelegate: ApplicationDelegate?, windowDelegates: @escaping @autoclosure () -> [WindowDelegate], windowRenderGraph: RenderGraph) {
        super.init()
        
        self.application = CocoaApplication(delegate: appDelegate, updateables: windowDelegates(), updateScheduler: self, windowRenderGraph: windowRenderGraph)
        
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
        
        autoreleasepool {
            runAsyncAndBlock {
                await self.application.update()
            }
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

        self.application = CocoaApplication(delegate: appDelegate, viewController: viewController, windowDelegate: windowDelegate, updateScheduler: self, windowRenderGraph: windowRenderGraph)

        let mainWindow = windows.first! as! MTKWindow

        let view = mainWindow.mtkView
        view.delegate = self

        for window in windows.dropFirst() {
            (window as! MTKWindow).mtkView.isPaused = true
            (window as! MTKWindow).mtkView.enableSetNeedsDisplay = true
        }
    }

    public func draw(in view: MTKView) {
        if application.inputManager.shouldQuit {
            Application.exit()
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
