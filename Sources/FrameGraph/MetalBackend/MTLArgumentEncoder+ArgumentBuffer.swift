//
//  ArgumentBuffer.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 16/03/18.
//

#if canImport(Metal)

import Metal

extension MTLArgumentEncoder {
    func encodeArguments(from argBuffer: _ArgumentBuffer, resourceRegistry: MetalResourceRegistry, stateCaches: MetalStateCaches) {
        for (bindingPath, binding) in argBuffer.bindings {
            
            let bindingIndex = bindingPath.bindIndex
            
            switch binding {
            case .texture(let texture):
                let mtlTexture = resourceRegistry[texture]!
                self.setTexture(mtlTexture, index: bindingIndex)
            case .buffer(let buffer, let offset):
                let mtlBuffer = resourceRegistry[buffer]!
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

#endif // canImport(Metal)
