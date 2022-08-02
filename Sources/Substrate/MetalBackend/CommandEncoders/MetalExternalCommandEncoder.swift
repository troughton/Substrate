//
//  File.swift
//  
//
//  Created by Thomas Roughton on 15/07/22.
//

#if canImport(Metal)
import Foundation
import Metal

final class MetalExternalCommandEncoder: ExternalCommandEncoder {
    let commandBuffer: MTLCommandBuffer
    
    init(commandBuffer: MTLCommandBuffer, passRecord: RenderPassRecord) {
        self.commandBuffer = commandBuffer
        super.init(renderPass: passRecord.pass as! ExternalRenderPass, passRecord: passRecord)
    }
    
    override func encodeCommand(_ command: (UnsafeRawPointer) -> Void) {
        command(Unmanaged.passUnretained(self.commandBuffer).toOpaque())
    }
}

#endif // canImport(Metal)
