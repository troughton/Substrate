//
//  Screen.swift
//  LlamaCore
//
//  Created by Thomas Roughton on 25/10/18.
//

import Foundation
import SwiftMath

public struct Screen {
    var position : WindowPosition
    var dimensions : WindowSize
    
    var workspacePosition : WindowPosition
    var workspaceDimensions : WindowSize
    
    var backingScaleFactor : Float
}
