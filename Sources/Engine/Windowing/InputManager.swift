//
//  InputManager.swift
//  InterdimensionalLlama
//
//  Created by Joseph Bennett on 17/11/16.
//
//

import SwiftMath

public protocol InputManager {
    var inputState : InputState { get }
    var shouldQuit : Bool { get }
    
    func update(windows: [Window])
    
    func signal(forSource source: InputSource) -> SignalMulti<InputSourceState>
    func signal(forSource source: InputSource, onDevice device: DeviceType) -> SignalMulti<InputSourceState>
}

protocol InputManagerInternal : class, InputManager {
    func setInputStateOnNextUpdate(inputSource : InputSource, newInputSourceState: InputSourceState)
    func setInputStateOnNextUpdate(forDevice: Device, inputSource : InputSource, newInputSourceState: InputSourceState)
}

public extension InputMappings {
    public func signalMappings<T : InputAction>(inputManager: InputManager, stringToAction: (String) -> T?) -> [T : Signal<CharacterInputState>] {
        typealias Range = (from: Float, to: Float, default: Float)
        var actionNamesToTuples = [String : [(Signal<InputSourceState>, InputActionInfo, Range)]]()
        
        // find the raw input signal for each action
        for (device, mappings) in self.devices {
            for (source, action) in mappings {
                let inputSignal = inputManager.signal(forSource: source, onDevice: device)
                
                var signalActionPairs = actionNamesToTuples[action.name] ?? []
                
                signalActionPairs.append((inputSignal, action, device.inputRange(for: source)))
                
                actionNamesToTuples[action.name] = signalActionPairs
            }
        }
        
        var mappings = [T : Signal<CharacterInputState>]()
        
        for (actionName, signalActionPairs) in actionNamesToTuples {
            guard let action = stringToAction(actionName) else {
                print("No action found for name \(actionName)")
                continue
            }
            
            // map hardware input state signals into character input state signals
            let characterInputSignals = signalActionPairs.map({ (signalActionPair) -> Signal<CharacterInputState> in
                let (signal, actionInfo, inputRange) = signalActionPair
                
                return signal.transform { (result: Result<InputSourceState>, next: SignalNext<CharacterInputState>) in
                    switch result {
                    case .success(let inputState):
                        
                        let outputState : CharacterInputState
                        switch actionInfo.type {
                        case .digital:
                            switch (action.trigger, inputState) {
                            case (.onStart, .pressed):
                                outputState = .active
                            case (.onEnd, .released):
                                outputState = .active
                            case (.continuous, _) where inputState.isActive:
                                outputState = .active
                            default:
                                outputState = .inactive
                            }
                            
                        case let .range(from, to):
                            let numericValue : Float
                            switch inputState {
                            case .deactivated:
                                numericValue = inputRange.default
                                
                            case let .value(value):
                                let inputRangeSize = inputRange.to - inputRange.from
                                let outputRangeSize = to - from
                                
                                numericValue = (value - inputRange.from) * outputRangeSize / inputRangeSize + from
                            case _ where inputState.isActive:
                                numericValue = to
                            default:
                                numericValue = from
                            }
                            
                            if let component = actionInfo.component {
                                switch component {
                                case "x":
                                    outputState = .vector2(Vector2f(numericValue, 0))
                                case "y":
                                    outputState = .vector2(Vector2f(0, numericValue))
                                default:
                                    fatalError()
                                }
                            } else {
                                outputState = .value(numericValue)
                            }
                        case .analogRaw:
                            let numericValue : Float
                            switch inputState {
                            case let .value(value):
                                numericValue = value
                            default:
                                numericValue = inputRange.default
                            }
                            
                            if let component = actionInfo.component {
                                switch component {
                                case "x":
                                    outputState = .vector2(Vector2f(numericValue, 0))
                                case "y":
                                    outputState = .vector2(Vector2f(0, numericValue))
                                default:
                                    fatalError()
                                }
                            } else {
                                outputState = .value(numericValue)
                            }
                            
                        }
                        
                        next.send(value: outputState)
                    case .failure(let error):
                        next.send(error: error)
                    }
                }
            })
            
            var signal = characterInputSignals.first!
            // merge signals from multiple inputs
            for otherSignal in characterInputSignals.dropFirst() {
                signal = signal.combineLatest(second: otherSignal, { (inputStateA, inputStateB) -> CharacterInputState in
                    switch (inputStateA, inputStateB) {
                    case let (.vector2(vectorA), .vector2(vectorB)):
                        let x = (abs(vectorA.x) > abs(vectorB.x)) ? vectorA.x : vectorB.x
                        let y = (abs(vectorA.y) > abs(vectorB.y)) ? vectorA.y : vectorB.y
                        return .vector2(Vector2f(x, y))
                    case let (.value(valueA), .value(valueB)):
                        return (abs(valueA) > abs(valueB)) ? .value(valueA) : .value(valueB)
                    case (.active, _):
                        return .active
                    case (_, .active):
                        return .active
                    case (.inactive, .inactive):
                        return .inactive
                    default:
                        fatalError()
                    }
                })
                
            }
            
            mappings[action] = signal.distinctUntilChanged(comparator: { (stateA, stateB) -> Bool in
                switch (stateA, stateB) {
                case (.inactive, .inactive):
                    return true
                case (.active, .active):
                    return true
                case let (.value(valueA), .value(valueB)):
                    return valueA == valueB
                case let (.vector2(valueA), .vector2(valueB)):
                    return valueA == valueB
                default:
                    return false
                }
            }).continuous()
            
        }
        
        return mappings
    }

}
