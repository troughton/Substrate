//
//  CocoaInputManager.swift
//  InterdimensionalLlama
//
//  Created by Thomas Roughton on 20/03/17.
//
//

#if os(macOS)

import AppKit
import Carbon
import SwiftMath
import Cocoa

import DrawTools
import CDebugDrawTools

public final class CocoaInputManager : InputManagerInternal {
    public var inputState = InputState()
    
    private var updateAccess = DispatchQueue(label: "idl.updateAccess")
    private var eventQueue = [NSEvent]()
    
    private var gamepadManager : SDLGamepadManager! = nil
    
    private var endpoints = [Any]()
    
    private var cursorHidden = false
    
    public init() {
        self.gamepadManager = SDLGamepadManager(inputManager: self)
        
        self.setupImGui()
        
        self.endpoints += [self.signal(forSource: .command, onDevice: .keyboard).combineLatest(second: self.signal(forSource: .keyQ, onDevice: .keyboardScanCode)) { (stateA, stateB) -> Bool in
            
            switch (stateA, stateB) {
            case (.pressed, _) where stateB.isActive:
                return true
            case (_, .pressed) where stateA.isActive:
                return true
            default:
                return false
            }
            }.subscribeValues { value in
                if value {
                    NSApp.perform(#selector(NSApp.terminate), with: nil, afterDelay: 0.1)
                }
        }]
    }
    
    public func setupImGui() {
        let io = ImGui.io
        withUnsafeMutablePointer(to: &io.pointee.KeyMap.0) {
            let keyMap = UnsafeMutableBufferPointer(start: $0, count: ImGuiKey_COUNT)
            keyMap[Int(ImGuiKey_Tab)] = Int32(kVK_Tab);                     // Keyboard mapping. ImGui will use those indices to peek into the io.KeyDown[] array.
            keyMap[Int(ImGuiKey_LeftArrow)] = Int32(kVK_LeftArrow);
            keyMap[Int(ImGuiKey_RightArrow)] = Int32(kVK_RightArrow);
            keyMap[Int(ImGuiKey_UpArrow)] = Int32(kVK_UpArrow)
            keyMap[Int(ImGuiKey_DownArrow)] = Int32(kVK_DownArrow)
            keyMap[Int(ImGuiKey_PageUp)] = Int32(kVK_PageUp)
            keyMap[Int(ImGuiKey_PageDown)] = Int32(kVK_PageDown)
            keyMap[Int(ImGuiKey_Home)] = Int32(kVK_Home)
            keyMap[Int(ImGuiKey_End)] = Int32(kVK_End)
            keyMap[Int(ImGuiKey_Delete)] = Int32(kVK_ForwardDelete)
            keyMap[Int(ImGuiKey_Backspace)] = Int32(kVK_Delete)
            keyMap[Int(ImGuiKey_Enter)] = Int32(kVK_Return)
            keyMap[Int(ImGuiKey_Escape)] = Int32(kVK_Escape)
            keyMap[Int(ImGuiKey_Space)] = Int32(kVK_Space)
            keyMap[Int(ImGuiKey_A)] = Int32(kVK_ANSI_A)
            keyMap[Int(ImGuiKey_C)] = Int32(kVK_ANSI_C)
            keyMap[Int(ImGuiKey_V)] = Int32(kVK_ANSI_V)
            keyMap[Int(ImGuiKey_X)] = Int32(kVK_ANSI_X)
            keyMap[Int(ImGuiKey_Y)] = Int32(kVK_ANSI_Y)
            keyMap[Int(ImGuiKey_Z)] = Int32(kVK_ANSI_Z)
        }
    }
    
    private var setStateOnNextUpdate : [(Device, InputSource, InputSourceState)] = []
    public private(set) var shouldQuit: Bool = false
    
    
    public func signal(forSource source: InputSource) -> SignalMulti<InputSourceState> {
        return self.signal(forSource: source, onDevice: source.devices.first!)
    }
    
    public func signal(forSource source: InputSource, onDevice device: DeviceType) -> SignalMulti<InputSourceState> {
        return self.inputState[device].signal(for: source)
    }
    
    public func update(windows: [Window]) {
        self.setStateOnNextUpdate.forEach { (device, inputSource, newInputState) in device[inputSource] = newInputState }
        self.setStateOnNextUpdate.removeAll(keepingCapacity: true)
        
        self.updateAccess.sync {
            self.handleEvents(windows: windows)
            self.gamepadManager.update()
        }
        
        let imguiCursor = ImGui.mouseCursor
        if imguiCursor != .none && cursorHidden {
            NSCursor.unhide()
            cursorHidden = false
        }
        switch imguiCursor {
        case .none:
            if !cursorHidden {
                NSCursor.hide()
                cursorHidden = true
            }
        case .arrow:
            NSCursor.arrow.set()
        case .move:
            NSCursor.closedHand.set()
        case .textInput:
            NSCursor.iBeam.set()
        case .resizeEW:
            NSCursor.resizeLeftRight.set()
        case .resizeNS:
            NSCursor.resizeUpDown.set()
        case .resizeNESW: // FIXME: before release, we should remove this private methods.
            (NSCursor.perform(NSSelectorFromString("_windowResizeNorthEastSouthWestCursor"))?.takeUnretainedValue() as! NSCursor).set()
        case .resizeNWSE:
            (NSCursor.perform(NSSelectorFromString("_windowResizeNorthWestSouthEastCursor"))?.takeUnretainedValue() as! NSCursor).set()
        }
    }
    
    func setInputStateOnNextUpdate(inputSource : InputSource, newInputSourceState: InputSourceState) {
        setInputStateOnNextUpdate(forDevice: self.inputState[inputSource.devices.first!], inputSource: inputSource, newInputSourceState: newInputSourceState)
    }
    
    func setInputStateOnNextUpdate(forDevice: Device, inputSource : InputSource, newInputSourceState: InputSourceState) {
        setStateOnNextUpdate.append((forDevice, inputSource, newInputSourceState))
    }
    
    private func handleEvents(windows: [Window]) {
        
        var mouseScrollX : CGFloat = 0.0
        var mouseScrollY : CGFloat = 0.0
        
        for event in self.eventQueue {
            
            switch event.type {
            case .keyDown where !event.isARepeat:
                if let inputSource = InputSource(keyCode: event.keyCode) {
                    inputState[.keyboardScanCode][inputSource] = .pressed
                    setInputStateOnNextUpdate(forDevice: inputState[.keyboardScanCode], inputSource: inputSource, newInputSourceState: .held)
                }
                
                if let character = event.charactersIgnoringModifiers?.first, let inputSource = InputSource(character: character) {
                    inputState[.keyboard][inputSource] = .pressed
                    setInputStateOnNextUpdate(forDevice: inputState[.keyboard], inputSource: inputSource, newInputSourceState: .held)
                }
                
                withUnsafeMutablePointer(to: &ImGui.io.pointee.KeysDown.0, { keysDown in
                    keysDown.advanced(by: Int(event.keyCode)).pointee = true
                })
                
                if let chars = event.characters {
                    ImGui.io.pointee.addUTF8InputCharacters(chars.utf8CString)
                }
                
            case .keyUp:
                if let inputSource = InputSource(keyCode: event.keyCode) {
                    inputState[.keyboardScanCode][inputSource] = .released
                    setInputStateOnNextUpdate(forDevice: inputState[.keyboardScanCode], inputSource: inputSource, newInputSourceState: .deactivated)
                }
                
                if let character = event.charactersIgnoringModifiers?.first, let inputSource = InputSource(character: character) {
                    inputState[.keyboard][inputSource] = .released
                    setInputStateOnNextUpdate(forDevice: inputState[.keyboard], inputSource: inputSource, newInputSourceState: .deactivated)
                }
                
                withUnsafeMutablePointer(to: &ImGui.io.pointee.KeysDown.0, { keysDown in
                    keysDown.advanced(by: Int(event.keyCode)).pointee = false
                })
                
            case .flagsChanged:
                let allFlags : [(NSEvent.ModifierFlags, InputSource)] = [(.control, .control), (.option, .option), (.command, .command), (.shift, .shift)]
                
                for flag in allFlags {
                    let previousState = inputState[.keyboardScanCode][flag.1]
                    let currentlyActive = event.modifierFlags.contains(flag.0)
                    
                    switch (previousState, currentlyActive) {
                    case (.deactivated, true), (.released, true):
                        inputState[.keyboardScanCode][flag.1] = .pressed
                        setInputStateOnNextUpdate(forDevice: inputState[.keyboardScanCode], inputSource: flag.1, newInputSourceState: .held)
                        
                        inputState[.keyboard][flag.1] = .pressed
                        setInputStateOnNextUpdate(forDevice: inputState[.keyboard], inputSource: flag.1, newInputSourceState: .held)
                        
                    case (.held, false), (.pressed, false):
                        inputState[.keyboardScanCode][flag.1] = .released
                        setInputStateOnNextUpdate(forDevice: inputState[.keyboardScanCode], inputSource: flag.1, newInputSourceState: .deactivated)
                        
                        inputState[.keyboard][flag.1] = .released
                        setInputStateOnNextUpdate(forDevice: inputState[.keyboard], inputSource: flag.1, newInputSourceState: .deactivated)
                        
                    default:
                        break
                    }
                }
                
                ImGui.io.pointee.KeyShift = event.modifierFlags.contains(.shift)
                ImGui.io.pointee.KeyCtrl = event.modifierFlags.contains(.control)
                ImGui.io.pointee.KeyAlt = event.modifierFlags.contains(.option)
                ImGui.io.pointee.KeySuper = event.modifierFlags.contains(.command)
                
                break
                
            case .leftMouseDragged:
                fallthrough
            case .rightMouseDragged:
                fallthrough
            case .otherMouseDragged:
                fallthrough
            case .mouseMoved:
                let location = event.locationInWindow
                
                inputState[.mouse][.mouseX] = .value(Float(location.x))
                inputState[.mouse][.mouseY] = .value(Float(location.y))
                
                inputState[.mouse][.mouseXRelative] = .value(Float(event.deltaX))
                inputState[.mouse][.mouseYRelative] = .value(Float(event.deltaY))
            
            case .leftMouseDown:
                fallthrough
            case .rightMouseDown:
                fallthrough
            case .otherMouseDown:
                if let inputSource = InputSource(mouseButton: event.buttonNumber) {
                    inputState[.mouse][inputSource] = .pressed
                    setInputStateOnNextUpdate(forDevice: inputState[.mouse], inputSource: inputSource, newInputSourceState: .held)
                }
            case .leftMouseUp:
                fallthrough
            case .rightMouseUp:
                fallthrough
            case .otherMouseUp:
                if let inputSource = InputSource(mouseButton: event.buttonNumber) {
                    inputState[.mouse][inputSource] = .released
                    setInputStateOnNextUpdate(forDevice: inputState[.mouse], inputSource: inputSource, newInputSourceState: .deactivated)
                }
            case .scrollWheel:
                mouseScrollX += event.scrollingDeltaX
                mouseScrollY += event.scrollingDeltaY
            default:
                break
            }
        }
        
        inputState[.mouse][.mouseScrollX] = .value(Float(mouseScrollX))
        inputState[.mouse][.mouseScrollY] = .value(Float(mouseScrollY))
        
        self.eventQueue.removeAll(keepingCapacity: true)
    }
    
    public func processInputEvent(_ event: NSEvent) {
        self.updateAccess.sync {
            self.eventQueue.append(event)
        }
    }
    
}


extension InputSource {
    
    init?(mouseButton: Int) {
        switch mouseButton {
        case 0:
            self = .mouseButtonLeft
        case 1:
            self = .mouseButtonRight
        case 2:
            self = .mouseButtonMiddle
        default:
            return nil
        }
    }
    
    init?(character: Character) {
        switch character {
        case "a", "A":
            self = .keyA
        case "b", "B":
            self = .keyB
        case "c", "C":
            self = .keyC
        case "d", "D":
            self = .keyD
        case "e", "E":
            self = .keyE
        case "f", "F":
            self = .keyF
        case "g", "G":
            self = .keyG
        case "h", "H":
            self = .keyH
        case "i", "I":
            self = .keyI
        case "j", "J":
            self = .keyJ
        case "k", "K":
            self = .keyK
        case "l", "L":
            self = .keyL
        case "m", "M":
            self = .keyM
        case "n", "N":
            self = .keyN
        case "o", "O":
            self = .keyO
        case "p", "P":
            self = .keyP
        case "q", "Q":
            self = .keyQ
        case "r", "R":
            self = .keyR
        case "s", "S":
            self = .keyS
        case "t", "T":
            self = .keyT
        case "u", "U":
            self = .keyU
        case "v", "V":
            self = .keyV
        case "w", "W":
            self = .keyW
        case "x", "X":
            self = .keyX
        case "y", "Y":
            self = .keyY
        case "z", "Z":
            self = .keyZ
        default:
            return nil
        }
        
    }
    
    init?(keyCode: UInt16) {
        switch Int(keyCode) {
            
        // special keys
        case kVK_Escape:
            self = .esc
        case kVK_Return:
            self = .return
        case kVK_Tab:
            self = .tab
        case kVK_Space:
            self = .space
        case kVK_Delete:
            self = .backspace
        case kVK_UpArrow:
            self = .up
        case kVK_DownArrow:
            self = .down
        case kVK_LeftArrow:
            self = .left
        case kVK_RightArrow:
            self = .right
        case kVK_ForwardDelete:
            self = .delete
        case kVK_Home:
            self = .home
        case kVK_End:
            self = .end
        case kVK_PageDown:
            self = .pageUp
        case kVK_PageUp:
            self = .pageDown
            
        case kVK_Shift:
            self = .shift
        case kVK_RightShift:
            self = .shift
            
        // punctuation
        case kVK_ANSI_Equal:
            self = .equals
        case kVK_ANSI_Minus:
            self = .minus
        case kVK_ANSI_LeftBracket:
            self = .leftBracket
        case kVK_ANSI_RightBracket:
            self = .rightBracket
        case kVK_ANSI_Comma:
            self = .comma
        case kVK_ANSI_Period:
            self = .period
        case kVK_ANSI_Slash:
            self = .slash
            
        // function keys (f1-f9)
        case kVK_F1:
            self = .f1
        case kVK_F2:
            self = .f2
        case kVK_F3:
            self = .f3
        case kVK_F4:
            self = .f4
        case kVK_F5:
            self = .f5
        case kVK_F6:
            self = .f6
        case kVK_F7:
            self = .f7
        case kVK_F8:
            self = .f8
        case kVK_F9:
            self = .f9
            
            
        // number pad numbers 0-9
        case kVK_ANSI_Keypad0:
            self = .numPad0
        case kVK_ANSI_Keypad1:
            self = .numPad1
        case kVK_ANSI_Keypad2:
            self = .numPad2
        case kVK_ANSI_Keypad3:
            self = .numPad3
        case kVK_ANSI_Keypad4:
            self = .numPad4
        case kVK_ANSI_Keypad5:
            self = .numPad5
        case kVK_ANSI_Keypad6:
            self = .numPad6
        case kVK_ANSI_Keypad7:
            self = .numPad7
        case kVK_ANSI_Keypad8:
            self = .numPad8
        case kVK_ANSI_Keypad9:
            self = .numPad9
            
        // number 0-9
        case kVK_ANSI_0:
            self = .key0
        case kVK_ANSI_1:
            self = .key1
        case kVK_ANSI_2:
            self = .key2
        case kVK_ANSI_3:
            self = .key3
        case kVK_ANSI_4:
            self = .key4
        case kVK_ANSI_5:
            self = .key5
        case kVK_ANSI_6:
            self = .key6
        case kVK_ANSI_7:
            self = .key7
        case kVK_ANSI_8:
            self = .key8
        case kVK_ANSI_9:
            self = .key9
            
        // alphabet A - Z
        case kVK_ANSI_A:
            self = .keyA
        case kVK_ANSI_B:
            self = .keyB
        case kVK_ANSI_C:
            self = .keyC
        case kVK_ANSI_D:
            self = .keyD
        case kVK_ANSI_E:
            self = .keyE
        case kVK_ANSI_F:
            self = .keyF
        case kVK_ANSI_G:
            self = .keyG
        case kVK_ANSI_H:
            self = .keyH
        case kVK_ANSI_I:
            self = .keyI
        case kVK_ANSI_J:
            self = .keyJ
        case kVK_ANSI_K:
            self = .keyK
        case kVK_ANSI_L:
            self = .keyL
        case kVK_ANSI_M:
            self = .keyM
        case kVK_ANSI_N:
            self = .keyN
        case kVK_ANSI_O:
            self = .keyO
        case kVK_ANSI_P:
            self = .keyP
        case kVK_ANSI_Q:
            self = .keyQ
        case kVK_ANSI_R:
            self = .keyR
        case kVK_ANSI_S:
            self = .keyS
        case kVK_ANSI_T:
            self = .keyT
        case kVK_ANSI_U:
            self = .keyU
        case kVK_ANSI_V:
            self = .keyV
        case kVK_ANSI_W:
            self = .keyW
        case kVK_ANSI_X:
            self = .keyX
        case kVK_ANSI_Y:
            self = .keyY
        case kVK_ANSI_Z:
            self = .keyZ
        default:
            return nil
        }
    }
    
}

#endif
