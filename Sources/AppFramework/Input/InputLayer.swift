//
//  InputLayer.swift
//  LlamaCore
//
//  Created by Thomas Roughton on 28/10/18.
//

import Foundation

public enum InputActionState : InputSourceState {
    case active
    case inactive
    case value(Float)
    
    public static var `default`: InputActionState {
        return .inactive
    }
    
    public var isActive : Bool {
        switch self {
        case .active:
            return true
        case .value(let val) where val != 0:
            return true
        default:
            return false
        }
    }
    
    public var value : Float {
        switch self {
        case .active:
            return 1.0
        case .inactive:
            return 0.0
        case .value(let val):
            return val
        }
    }
}

public protocol InputLayer : AnyObject {
    func processInput(rawInput: inout InputState<RawInputState>, frame: UInt64)
}

public protocol InputActionType : Hashable, Codable {
    
}


public final class ConfigurableInputLayer<ActionType : InputActionType> : InputLayer {
    public let modifiers : [InputModifier]
    public let mappings : [InputLayerMapping<ActionType>]
    
    var transitionState = InputState<InputSourceTransitionState>()
    private var actionState = [ActionType : InputActionState]()
    
    public init(modifiers: [InputModifier], mappings: [InputLayerMapping<ActionType>]) {
        self.modifiers = modifiers
        self.mappings = mappings
    }
    
    public subscript(transitionState deviceType: DeviceType) -> DeviceInputState<InputSourceTransitionState> {
        return self.transitionState[deviceType]
    }
    
    public subscript(transitionState inputSource: InputSource) -> InputSourceTransitionState {
        return self.transitionState[inputSource]
    }
    
    public subscript(actionType: ActionType) -> InputActionState {
        return self.actionState[actionType, default: .inactive]
    }
    
    public func processInput(rawInput: inout InputState<RawInputState>, frame: UInt64) {
        self.transitionState.update(rawState: rawInput, frame: frame)
        self.actionState.removeAll(keepingCapacity: true)

        var activeModifiers = [InputModifier]()
        for modifier in self.modifiers {
            if rawInput[modifier.device][modifier.input].isActive(frame: frame) {
                activeModifiers.append(modifier)
            }
        }
        
        mappingLoop: for mapping in self.mappings {
            
            for modifier in activeModifiers {
                if mapping.inputs.contains(where: { $0.device == modifier.device && $0.input == modifier.input }) {
                    continue
                }
                if mapping.inputs.contains(where: { $0.device == modifier.modifies }) {
                    continue mappingLoop
                }
            }
            
            var pressedCount = 0
            var activeCount = 0
            var releasedCount = 0
            var value : Float? = nil
            
            for input in mapping.inputs {
                let transitionState = self.transitionState[input.device][input.input]
                switch transitionState {
                case .pressed:
                    pressedCount += 1
                    activeCount += 1
                case .held:
                    activeCount += 1
                case .released:
                    releasedCount += 1
                case .deactivated:
                    break
                case .value(let val):
                    value = val
                    activeCount += (val != 0) ? 1 : 0
                }
                
                if let range = input.range {
                    switch transitionState {
                    case .value(let val):
                        value = range.start + val * (range.end - range.start)
                    case _ where transitionState.isActive:
                        value = range.end
                    default:
                        value = range.start
                    }
                }
            }
            
            // onStart: All inputs must be active and at least one must be pressed
            // onEnd: All inputs must be either active or released, and at least one must be released
            // continuous: All inputs must be active
            
            let isActive : Bool
            switch mapping.trigger {
            case .onStart:
                isActive = activeCount == mapping.inputs.count && pressedCount > 0
            case .onEnd:
                isActive = (activeCount + releasedCount) == mapping.inputs.count && releasedCount > 0
            case .continuous:
                isActive = activeCount == mapping.inputs.count
            }
            
            if isActive {
                if let value = value {
                    self.actionState[mapping.action] = .value(value)
                } else {
                    self.actionState[mapping.action] = .active
                }
            }
        }
    }
}

extension ConfigurableInputLayer : Codable {
    enum CodingKeys : CodingKey {
        case modifiers
        case mappings
    }
    
    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let modifiers = try container.decode([InputModifier].self, forKey: .modifiers)
        let mappings = try container.decode([InputLayerMapping<ActionType>].self, forKey: .mappings)
        
        self.init(modifiers: modifiers, mappings: mappings)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.modifiers, forKey: .modifiers)
        try container.encode(self.mappings, forKey: .mappings)
    }
}
