//
//  SDLGamepadManager.swift
//  LlamaGame
//
//  Created by Thomas Roughton on 11/06/17.
//  Copyright © 2017 Team Llama. All rights reserved.
//

import Foundation
import CSDL2

public final class SDLGamepadManager {
    
    private weak var inputManager: InputManagerInternal!
    
    public init(inputManager: InputManager) {
        if SDL_Init(SDL_INIT_GAMECONTROLLER) != 0 {
            let error = String(cString: SDL_GetError())
            print("Unable to initialise SDL: \(error)")
        }
        self.inputManager = (inputManager as! InputManagerInternal)
    }
    
    /// Mapping from an internal SDL id for a controller to our device slot.
    private var gamepadSlots = [Int32](repeating: EmptyGamepadSlot, count: DeviceType.gamepads.count)
    
    public func update() {
        
        var event = SDL_Event()
        
        while SDL_PollEvent(&event) != 0 {
            switch SDL_EventType(rawValue: SDL_EventType.RawValue(event.type)) {
                
            case SDL_CONTROLLERDEVICEADDED:
                let deviceIndex = event.cdevice.which
                
                guard let gamepadSlot = self.gamepadSlots.lowestEmptyIndex else {
                    print("No more controller slots available. Ignoring.")
                    break
                }
                
                print("Controller connected to slot \(gamepadSlot)")
                
                let gameController = SDL_GameControllerOpen(deviceIndex)
                inputManager.inputState[.gamepad(slot: gamepadSlot)].connected = true
                
                let joyStick = SDL_GameControllerGetJoystick(gameController)
                let instanceId = SDL_JoystickInstanceID(joyStick)
                
                gamepadSlots[gamepadSlot] = instanceId
                
            case SDL_CONTROLLERDEVICEREMOVED:
                let instanceId = event.cdevice.which
                
                guard let gamepadSlot = self.gamepadSlots.index(of: instanceId) else {
                    print("SDL tried to remove gamepad that we aren't keeping track of.")
                    break
                }
                
                print("Controller removed from slot \(gamepadSlot)")
                
                let gameController = SDL_GameControllerFromInstanceID(instanceId)
                SDL_GameControllerClose(gameController)
                inputManager.inputState[.gamepad(slot: gamepadSlot)].connected = false
                
                gamepadSlots[gamepadSlot] = EmptyGamepadSlot
                
                
            case SDL_CONTROLLERBUTTONDOWN:
                let instanceId = event.cbutton.which
                
                guard let gamepadSlot = self.gamepadSlots.index(of: instanceId) else {
                    print("SDL sent button down event for untracked gamepad")
                    break
                }
                
                let device = inputManager.inputState[.gamepad(slot: gamepadSlot)]
                
                let buttonId = event.cbutton.button
                
                if let inputSource = InputSource(fromGameControllerButton: buttonId) {
                    let previousState = device[inputSource]
                    
                    if previousState != .held {
                        device[inputSource] = .pressed
                        inputManager.setInputStateOnNextUpdate(forDevice: device, inputSource: inputSource, newInputSourceState: .held)
                    }
                }
                
            case SDL_CONTROLLERBUTTONUP:
                let instanceId = event.cbutton.which
                
                guard let gamepadSlot = self.gamepadSlots.index(of: instanceId) else {
                    print("SDL sent button up event for untracked gamepad")
                    break
                }
                
                let device = inputManager.inputState[.gamepad(slot: gamepadSlot)]
                
                let buttonId = event.cbutton.button
                
                if let inputSource = InputSource(fromGameControllerButton: buttonId) {
                    inputManager.inputState[.gamepad(slot: gamepadSlot)][inputSource] = .released
                    inputManager.setInputStateOnNextUpdate(forDevice: device, inputSource: inputSource, newInputSourceState: .deactivated)
                }
                
                
            case SDL_CONTROLLERAXISMOTION:
                let instanceId = event.caxis.which
                
                guard let gamepadSlot = self.gamepadSlots.index(of: instanceId) else {
                    print("SDL sent axis motion event for untracked gamepad")
                    break
                }
                
                let device = inputManager.inputState[.gamepad(slot: gamepadSlot)]
                
                let axisId = event.caxis.axis
                
                if let inputSource = InputSource(fromGameControllerAxis: axisId) {
                    var value = Float(event.caxis.value)
                    
                    if (value > JoyStickDeadZone || value < -JoyStickDeadZone) {
                        if (value > JoyStickDeadZone) {
                            value -= JoyStickDeadZone
                        } else {
                            value += JoyStickDeadZone
                        }
                        
                        var normalizedValue = value/(SDLJoyStickMaxValue - JoyStickDeadZone)
                        
                        if (normalizedValue > 1.0) {
                            normalizedValue = 1.0
                        } else if (normalizedValue < -1.0) {
                            normalizedValue = -1.0
                        }
                        
                        device[inputSource] = .value(normalizedValue)
                    } else {
                        device[inputSource] = .value(0.0)
                    }
                }
                
                
            default:
                break
            }
        }
        
    }
    
    //    private func handleWindowEvent(sdlWindowEventId : SDL_WindowEventID) {
    //        switch sdlWindowEventId {
    //        case SDL_WINDOWEVENT_CLOSE:
    //            shouldQuit = true
    //        default:
    //            break
    //        }
    //    }
}
