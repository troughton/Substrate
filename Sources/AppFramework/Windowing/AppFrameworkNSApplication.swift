//
//  AppFrameworkNSApplication.swift
//  CGRAGame
//
//  Created by Thomas Roughton on 9/06/17.
//  Copyright © 2017 Team Llama. All rights reserved.
//

#if os(macOS)

import Foundation
import AppKit

public final class AppFrameworkNSApplication : NSApplication {
    
    public override func sendEvent(_ event: NSEvent) {
        let type : NSEvent.EventType = event.type
        
        switch type {
        case .keyDown, .keyUp, .flagsChanged:
            let focused = event.window?.firstResponder
            if focused?.isKind(of: MTKEventView.self) ?? false {
                switch type {
                case .keyDown:
                    focused?.keyDown(with: event)
                    return
                case .keyUp:
                    focused?.keyUp(with: event)
                    return
                case .flagsChanged:
                    focused?.flagsChanged(with: event)
                    return
                default:
                    break
                }
            }
        default:
            break
        }
        
        super.sendEvent(event)
    }
}

#endif
