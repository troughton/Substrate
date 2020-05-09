//
//  ExternallyDrivenScheduler.swift
//  AppFramework
//
//  Created by Thomas Roughton on 10/07/19.
//

#if os(macOS)

import MetalKit
import SwiftFrameGraph

public final class ExternallyDrivenScheduler : UpdateScheduler  {
    private var application : Application! = nil
    
    public init(appDelegate: ApplicationDelegate?, updateables: @escaping @autoclosure () -> [FrameUpdateable], windowFrameGraph: FrameGraph) {
        self.application = CocoaApplication(delegate: appDelegate, updateables: updateables(), updateScheduler: self, windowFrameGraph: windowFrameGraph)
    }
    
    public func update() {
        autoreleasepool {
            for window in application.windows {
                (window as! MTKWindow).mtkView.draw()
            }
        }
    }
    
    public func quit() {
        self.application = nil
    }
}

#endif
