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

public struct InputModifier {
    public var device : DeviceType
    public var input : InputSource
    public var modifies : DeviceType
}

public struct InputRange {
    public var start : Float
    public var end : Float
}

public struct InputLayerMapping<ActionType: InputActionType> {
    public struct Input : Codable {
        public var device : DeviceType
        public var input : InputSource
        public var range : InputRange?
    }
    
    /// The action that is activated when the conditions for this mapping are met.
    public var action: ActionType
    /// The edge on which this mapping is triggered.
    public var trigger : InputTrigger
    /// All inputs that must be active for this mapping to be active.
    public var inputs : [Input]
}

//public extension InputMappings {
//    public static func mappingsFromFile
//}

// MARK: - Codable Conformances

extension InputTrigger : Codable {}

extension InputModifier : Codable {}

extension InputRange : Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.start = try container.decode(Float.self)
        self.end = try container.decode(Float.self)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.start)
        try container.encode(self.end)
    }
}

extension InputLayerMapping : Codable {
}
