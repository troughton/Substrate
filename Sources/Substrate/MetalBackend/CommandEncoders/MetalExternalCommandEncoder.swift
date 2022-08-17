//
//  File.swift
//  
//
//  Created by Thomas Roughton on 15/07/22.
//

#if canImport(Metal)
import Foundation
import Metal

final class MetalExternalCommandEncoder: ExternalCommandEncoderImpl {
    let commandBuffer: MTLCommandBuffer
    
    init(commandBuffer: MTLCommandBuffer) {
        self.commandBuffer = commandBuffer
    }
    
    func setLabel(_ label: String) {
        commandBuffer.label = label
    }
    
    func pushDebugGroup(_ groupName: String) {
        commandBuffer.pushDebugGroup(groupName)
    }
    
    func popDebugGroup() {
        commandBuffer.popDebugGroup()
    }
    
    func insertDebugSignpost(_ string: String) {
        commandBuffer.pushDebugGroup(string)
        commandBuffer.popDebugGroup()
    }
    
    func encodeCommand(_ command: (UnsafeRawPointer) -> Void) {
        command(Unmanaged.passUnretained(self.commandBuffer).toOpaque())
    }
}

#endif // canImport(Metal)
