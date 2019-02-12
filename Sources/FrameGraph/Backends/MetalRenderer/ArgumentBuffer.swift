//
//  _ArgumentBuffer.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 16/03/18.
//

import Metal
import SwiftFrameGraph

extension MTLArgumentEncoder {

    // TODO: not all resources may exist at the first use, so we need to try to fill in the remaining resources once they're materialised every time the argument buffer is bound.
    func encodeArguments(from argBuffer: _ArgumentBuffer, argumentBufferPath: ResourceBindingPath, resourceRegistry: ResourceRegistry, stateCaches: StateCaches) {
        
        for (bindingPath, binding) in argBuffer.bindings {
            
            let bindingIndex = MetalResourceBindingPath(bindingPath).bindIndex
            
            switch binding {
            case .texture(let texture):
                guard let mtlTexture = resourceRegistry[texture] else { continue }
                self.setTexture(mtlTexture, index: bindingIndex)
            case .buffer(let buffer, let offset):
                guard let mtlBuffer = resourceRegistry[buffer] else { continue }
                self.setBuffer(mtlBuffer.buffer, offset: offset + mtlBuffer.offset, index: bindingIndex)
            case .sampler(let descriptor):
                let samplerState = stateCaches[descriptor]
                self.setSamplerState(samplerState, index: bindingIndex)
            case .bytes(let offset, let length):
                let bytes = argBuffer._bytes(offset: offset)
                self.constantData(at: bindingIndex).copyMemory(from: bytes, byteCount: length)
            }
        }
    }
}
