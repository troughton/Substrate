//
//  InputMapping.swift
//  InterdimensionalLlama
//
//  Created by Thomas Roughton on 29/12/16.
//
//

import Foundation
import SubstrateMath

public enum InputTrigger : String {
    case onStart
    case onEnd
    case continuous
}

public struct InputModifier {
    public var device : DeviceType
    public var input : InputSource
    public var modifies : DeviceType
    
    public init(device: DeviceType, input: InputSource, modifies: DeviceType) {
        self.device = device
        self.input = input
        self.modifies = modifies
    }
}

public struct InputRange {
    public var start : Float
    public var end : Float
    
    public init(start: Float, end: Float) {
        self.start = start
        self.end = end
    }
}

public struct InputLayerMapping<ActionType: InputActionType> {
    public struct Input : Codable {
        public var device : DeviceType
        public var input : InputSource
        public var range : InputRange?
        
        public init(device: DeviceType, input: InputSource, range: InputRange? = nil) {
            self.device = device
            self.input = input
            self.range = range
        }
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
