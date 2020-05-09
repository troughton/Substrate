//
//  InputSource.swift
//  CGRAGame
//
//  Created by Thomas Roughton on 30/05/17.
//  Copyright © 2017 Team Llama. All rights reserved.
//

public var MaxGamepadSlots = 8

public enum InputSource : String, Codable {
    case esc, `return`, tab, space, backspace
    case up, down, left, right
    case insert, delete, home, end, pageUp, pageDown
    case print
    
    case plus, minus, equals, leftBracket, rightBracket, semicolon
    case quote, comma, period, slash, backslash, tilde
    
    case shift
    case control
    case option
    case command
    
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    
    case numPad0, numPad1, numPad2, numPad3, numPad4
    case numPad5, numPad6, numPad7, numPad8, numPad9
    
    case key0, key1, key2, key3, key4, key5, key6, key7, key8, key9
    
    case keyA, keyB, keyC, keyD, keyE, keyF, keyG, keyH
    case keyI, keyJ, keyK, keyL, keyM, keyN, keyO, keyP
    case keyQ, keyR, keyS, keyT, keyU, keyV, keyW, keyX
    case keyY, keyZ
    
    case mouseX, mouseY, mouseXRelative, mouseYRelative, mouseScrollX, mouseScrollY
    case mouseXInWindow, mouseYInWindow
    
    case mouseButtonLeft, mouseButtonMiddle, mouseButtonRight
    
    case gamepadA, gamepadB, gamepadX, gamepadY, gamepadLeftStick, gamepadRightStick
    case gamepadLeftShoulder, gamepadRightShoulder, gamepadUp, gamepadDown, gamepadLeft
    case gamepadRight, gamepadBack, gamepadStart, gamepadGuide
    case gamepadLeftAxisX, gamepadLeftAxisY, gamepadRightAxisX, gamepadRightAxisY
    
    case gamepadLeftTrigger, gamepadRightTrigger
    
    public var devices : [DeviceType] {
        
        switch self {
        case .esc, .return, .tab, .space, .backspace,
             .up, .down, .left, .right,
             .insert, .delete, .home, .end, .pageUp, .pageDown,
             .print,
             .plus, .minus, .equals, .leftBracket, .rightBracket, .semicolon,
             .quote, .comma, .period, .slash, .backslash, .tilde,
             .shift,
             .control,
             .option,
             .command,
             .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12,
             .numPad0, .numPad1, .numPad2, .numPad3, .numPad4,
             .numPad5, .numPad6, .numPad7, .numPad8, .numPad9,
             .key0, .key1, .key2, .key3, .key4, .key5, .key6, .key7, .key8, .key9,
             .keyA, .keyB, .keyC, .keyD, .keyE, .keyF, .keyG, .keyH,
             .keyI, .keyJ, .keyK, .keyL, .keyM, .keyN, .keyO, .keyP,
             .keyQ, .keyR, .keyS, .keyT, .keyU, .keyV, .keyW, .keyX,
             .keyY, .keyZ:
            return [.keyboard, .keyboardScanCode]
            
            
            
        case .mouseX, .mouseY, .mouseXRelative, .mouseYRelative, .mouseScrollX, .mouseScrollY,
             .mouseButtonLeft, .mouseButtonMiddle, .mouseButtonRight, .mouseXInWindow, .mouseYInWindow:
            return [.mouse]
            
            
        case .gamepadA, .gamepadB, .gamepadX, .gamepadY, .gamepadLeftStick, .gamepadRightStick,
             .gamepadLeftShoulder, .gamepadRightShoulder, .gamepadUp, .gamepadDown, .gamepadLeft,
             .gamepadRight, .gamepadBack, .gamepadStart, .gamepadGuide,
             .gamepadLeftAxisX, .gamepadLeftAxisY, .gamepadRightAxisX, .gamepadRightAxisY,
             .gamepadLeftTrigger, .gamepadRightTrigger:
            return DeviceType.gamepads
            
        }
    }
}

public enum InputSourceTransitionState : InputSourceState {
    case pressed
    case held
    case released
    case deactivated
    case value(Float)
    
    public var value : Float {
        switch self {
        case let .value(value):
            return value
        case .pressed:
            fallthrough
        case .held:
            return 1.0
        default:
            return 0.0
        }
    }
    
    public var isActive : Bool {
        switch self {
        case .pressed:
            return true
        case .held:
            return true
        case let .value(value):
            return value != 0
        default:
            return false
        }
    }
    
    public static var `default`: InputSourceTransitionState {
        return .deactivated
    }
}

extension InputSourceTransitionState: Equatable {}


public enum DeviceType : Codable {
    case mouse
    case keyboard
    case keyboardScanCode
    case gamepad(slot: Int)
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        switch name {
        case "mouse":
            self = .mouse
        case "keyboard":
            self = .keyboard
        case "keyboardScanCode":
            self = .keyboardScanCode
        case "gamepad":
            self = .gamepad(slot: 0)
        default:
            fatalError()
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .mouse:
            try container.encode("mouse")
        case .keyboard:
            try container.encode("keyboard")
        case .keyboardScanCode:
            try container.encode("keyboardScanCode")
        case .gamepad(_):
            try container.encode("gamepad")
        }
    }
    
    public var defaultConnectionStatus : Bool {
        switch self {
        case .keyboard, .keyboardScanCode, .mouse:
            return true
        case .gamepad(slot: _):
            return false
        }
    }
    
    public static var allTypes : [DeviceType] {
        return [.mouse, .keyboard, .keyboardScanCode] + self.gamepads
    }
    
    public static var gamepads : [DeviceType] {
        return (0...MaxGamepadSlots - 1).map { .gamepad(slot: $0) }
    }
    
    public func inputRange(for input: InputSource) -> (from: Float, to: Float, default: Float) {
        switch self {
        case .gamepad(_):
            switch input {
            case .gamepadLeftAxisX, .gamepadLeftAxisY,
                 .gamepadRightAxisX, .gamepadRightAxisY:
                return (from: -1.0, to: 1.0, default: 0.0)
            default:
                break
            }
        default:
            break
        }
        
        return (from: 0.0, to: 1.0, default: 0.0)
    }
}

extension DeviceType : Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .mouse:
            hasher.combine(0)
        case .keyboard:
            hasher.combine(1)
        case .keyboardScanCode:
            hasher.combine(2)
        case .gamepad(let slot):
            hasher.combine(3)
            hasher.combine(slot)
        }
    }
}

extension DeviceType {
    public static func ==(lhs: DeviceType, rhs: DeviceType) -> Bool {
        switch (lhs, rhs) {
        case (.mouse, .mouse):
            return true
        case (.keyboard, .keyboard):
            return true
        case (.keyboardScanCode, .keyboardScanCode):
            return true
        case (let .gamepad(slot1), let .gamepad(slot2)):
            return slot1 == slot2
        default:
            return false
        }
    }
    
}

public protocol InputSourceState {
    static var `default` : Self { get }
}

public struct DeviceInputState<T : InputSourceState> {
    public let type: DeviceType
    fileprivate var mappings: [InputSource : T] = [:]
    
    public var connected : Bool
    
    init(type: DeviceType) {
        self.type = type
        self.connected = type.defaultConnectionStatus
    }
    
    public subscript(index: InputSource) -> T {
        get {
            return self.mappings[index, default: .default]
        }
        set (inputSourceState) {
            self.mappings[index] = inputSourceState
        }
    }
}

public struct InputState<T : InputSourceState> {
    
    public private(set) var devices : [DeviceType : DeviceInputState<T>]
    
    public init() {
        var devices = [DeviceType : DeviceInputState<T>]()
        
        for type in DeviceType.allTypes {
            devices[type] = DeviceInputState(type: type)
        }
        
        self.devices = devices
    }
    
    public subscript(deviceType: DeviceType) -> DeviceInputState<T> {
        get {
            return devices[deviceType]!
        }
        set {
            self.devices[deviceType] = newValue
        }
    }
    
    public subscript(inputSource: InputSource) -> T {
        get {
            let deviceType = inputSource.devices.first!
            return self[deviceType][inputSource]
        }
        
        set (inputSourceState){
            let deviceType = inputSource.devices.first!
            self[deviceType][inputSource] = inputSourceState
        }
    }
}


extension InputState where T == InputSourceTransitionState {
    mutating func update(rawState: InputState<RawInputState>, frame: UInt64) {
        for (deviceType, device) in rawState.devices {
            for (sourceType, state) in device.mappings {
                if state.isContinuous {
                    self[deviceType][sourceType] = .value(state.value)
                } else {
                    let newState : InputSourceTransitionState
                    
                    switch (self[deviceType][sourceType], state.isActive(frame: frame)) {
                    case (.released, true), (.deactivated, true):
                         newState = .pressed
                    case (.pressed, true), (.held, true):
                        newState = .held
                    case (.pressed, false), (.held, false):
                        newState = .released
                    case (.released, false), (.deactivated, false):
                        newState = .deactivated
                    case (.value(_), let isActive):
                        newState = isActive ? .value(1.0) : .value(0.0)
                    }
                    
                    self[deviceType][sourceType] = newState
                }
            }
            
            // Handle all the sources that are missing in the state dictionary.
            // The device's state will always be inactive.
            // Since we're not mutating the keys/we're only changing values this _should_ be safe.
            for sourceType in self[deviceType].mappings.keys where device.mappings[sourceType] == nil {
                let newState : InputSourceTransitionState
                
                switch self[deviceType][sourceType] {
                case .pressed, .held:
                    newState = .released
                case .released, .deactivated:
                    newState = .deactivated
                case .value(_):
                    newState = .value(0.0)
                }
                
                self[deviceType][sourceType] = newState
            }
        }
    }
}
