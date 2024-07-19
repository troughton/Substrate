//
//  ImGuiInputLayer.swift
//  LlamaCore
//
//  Created by Thomas Roughton on 28/10/18.
//

import ImGui

public final class ImGuiInputLayer : InputLayer {
    public override func processInput(rawInput: inout InputState<RawInputState>, frame: UInt64) {
        super.processInput(rawInput: &rawInput, frame: frame)
        
        if ImGui.io.pointee.WantCaptureMouse {
            rawInput[.mouse] = DeviceInputState<RawInputState>(type: .mouse)
        }
        
        if ImGui.io.pointee.WantCaptureKeyboard {
            rawInput[.keyboardScanCode] = DeviceInputState<RawInputState>(type: .keyboardScanCode)
            rawInput[.keyboard] = DeviceInputState<RawInputState>(type: .keyboard)
        }
    }
}
