//
//  InputManager.swift
//  InterdimensionalLlama
//
//  Created by Joseph Bennett on 17/11/16.
//
//

import SubstrateMath

public struct RawInputState : InputSourceState {
    private var state : Float
    // The frame this input was last activated
    private var lastActiveFrame : UInt32
    
    public init(active: Bool, frame: UInt32) {
        self.state = active ? .infinity : -.infinity
        self.lastActiveFrame = frame
    }
    
    public init(value: Float, frame: UInt32) {
        self.state = value
        self.lastActiveFrame = frame
    }

    public func isActive(frame: UInt32) -> Bool {
        return self.state == .infinity || lastActiveFrame == UInt32(truncatingIfNeeded: frame)
    }
    
    public func isActive(frame: UInt64) -> Bool {
        return self.state == .infinity || lastActiveFrame == frame
    }

    // Marks the state as inactive but still allows toggle events this frame to be registered
    public mutating func markInactive() {
        self.state = -.infinity
    }

    public var value : Float {
        get {
            return self.state
        }
        set {
            self.state = newValue
        }
    }

    public var isContinuous : Bool {
        return self.state != .infinity && self.state != -.infinity
    }
    
    public static var `default`: RawInputState {
        return RawInputState(active: false, frame: .max)
    }
}

@MainActor
public protocol InputManager {
    var shouldQuit : Bool { get set }
    
    func update(frame: UInt64, windows: [Window]) async
    var inputState : InputState<RawInputState> { get }
}

protocol InputManagerInternal : AnyObject, InputManager {
    var inputState : InputState<RawInputState> { get set }
}
