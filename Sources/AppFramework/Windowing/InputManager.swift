//
//  InputManager.swift
//  InterdimensionalLlama
//
//  Created by Joseph Bennett on 17/11/16.
//
//

import SwiftMath

public struct RawInputState : InputSourceState {
    private var state : Float
    // The frame this input was last activated
    private var lastActiveFrame : UInt32
    
    init(active: Bool, frame: UInt32) {
        self.state = active ? .infinity : -.infinity
        self.lastActiveFrame = frame
    }
    
    init(value: Float, frame: UInt32) {
        self.state = value
        self.lastActiveFrame = frame
    }

    func isActive(frame: UInt32) -> Bool {
        return self.state == .infinity || lastActiveFrame == UInt32(truncatingIfNeeded: frame)
    }
    
    func isActive(frame: UInt64) -> Bool {
        return self.state == .infinity || lastActiveFrame == frame
    }

    // Marks the state as inactive but still allows toggle events this frame to be registered
    mutating func markInactive() {
        self.state = -.infinity
    }

    var value : Float {
        get {
            return self.state
        }
        set {
            self.state = newValue
        }
    }

    var isContinuous : Bool {
        return self.state != .infinity && self.state != -.infinity
    }
    
    public static var `default`: RawInputState {
        return RawInputState(active: false, frame: .max)
    }
}

public protocol InputManager {
    var shouldQuit : Bool { get set }
    
    func update(frame: UInt64, windows: [Window])
    var inputState : InputState<RawInputState> { get }
}

protocol InputManagerInternal : class, InputManager {
    var inputState : InputState<RawInputState> { get set }
}
