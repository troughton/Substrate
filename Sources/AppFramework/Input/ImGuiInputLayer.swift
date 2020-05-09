//
//  ImGuiInputLayer.swift
//  LlamaCore
//
//  Created by Thomas Roughton on 28/10/18.
//

import ImGui

public final class ImGuiInputLayer : InputLayer {
    var transitionState = InputState<InputSourceTransitionState>()
    
    init() {
        
    }
    
    public subscript(inputSource: InputSource) -> InputSourceTransitionState {
        return self.transitionState[inputSource.devices.first!][inputSource]
    }
    
    public func processInput(rawInput: inout InputState<RawInputState>, frame: UInt64) {
        self.transitionState.update(rawState: rawInput, frame: frame)
        
        if ImGui.wantsCaptureMouse {
            rawInput[.mouse] = DeviceInputState<RawInputState>(type: .mouse)
        }
        
        if ImGui.wantsCaptureKeyboard {
            rawInput[.keyboardScanCode] = DeviceInputState<RawInputState>(type: .keyboardScanCode)
            rawInput[.keyboard] = DeviceInputState<RawInputState>(type: .keyboard)
        }
        
    }
}
