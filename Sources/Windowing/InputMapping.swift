//
//  InputMapping.swift
//  InterdimensionalLlama
//
//  Created by Thomas Roughton on 29/12/16.
//
//

import Foundation
import SwiftMath

public enum InputTrigger : String {
    case onStart
    case onEnd
    case continuous
}

struct InputModifier {
    var device : DeviceType
    var input : InputSource
    var modifies : DeviceType
}

struct InputRange {
    var start : Float
    var end : Float
}

struct InputLayerMapping<ActionType: InputActionType> {
    struct Input : Codable {
        var device : DeviceType
        var input : InputSource
        var range : InputRange?
    }
    
    /// The action that is activated when the conditions for this mapping are met.
    var action: ActionType
    /// The edge on which this mapping is triggered.
    var trigger : InputTrigger
    /// All inputs that must be active for this mapping to be active.
    var inputs : [Input]
}

// MARK: - Codable Conformances

extension InputTrigger : Codable {}

extension InputModifier : Codable {}

extension InputRange : Codable {
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.start = try container.decode(Float.self)
        self.end = try container.decode(Float.self)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.start)
        try container.encode(self.end)
    }
}

extension InputLayerMapping : Codable {
}
