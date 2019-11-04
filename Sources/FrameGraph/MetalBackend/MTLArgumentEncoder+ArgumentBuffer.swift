//
//  ArgumentBuffer.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 16/03/18.
//

#if canImport(Metal)

import Metal

extension _ArgumentBuffer {
    func setArguments(storage: MTLBufferReference, resourceMap: MetalFrameResourceMap, stateCaches: MetalStateCaches) {
        if self.stateFlags.contains(.initialised) { return }
        
        let argEncoder = Unmanaged<MTLArgumentEncoder>.fromOpaque(self.encoder!).takeUnretainedValue()
        
        argEncoder.setArgumentBuffer(storage.buffer, offset: storage.offset)
        argEncoder.encodeArguments(from: self, resourceMap: resourceMap, stateCaches: stateCaches)
        
        self.markAsInitialised()
    }
}

extension _ArgumentBufferArray {
    func setArguments(storage: MTLBufferReference, resourceMap: MetalFrameResourceMap, stateCaches: MetalStateCaches) {
        var argEncoder : MTLArgumentEncoder? = nil
        
        for (i, argumentBuffer) in self._bindings.enumerated() {
            guard let argumentBuffer = argumentBuffer else { continue }
            if argumentBuffer.stateFlags.contains(.initialised) { continue }
            
            if argEncoder == nil {
                argEncoder = Unmanaged<MTLArgumentEncoder>.fromOpaque(argumentBuffer.encoder!).takeUnretainedValue()
            }
            
            argEncoder!.setArgumentBuffer(storage.buffer, startOffset: storage.offset, arrayElement: i)
            argEncoder!.encodeArguments(from: argumentBuffer, resourceMap: resourceMap, stateCaches: stateCaches)
        }
    }
}

extension MTLArgumentEncoder {
    func encodeArguments(from argBuffer: _ArgumentBuffer, resourceMap: MetalFrameResourceMap, stateCaches: MetalStateCaches) {
        for (bindingPath, binding) in argBuffer.bindings {
            
            let bindingIndex = bindingPath.bindIndex
            
            switch binding {
            case .texture(let texture):
                let mtlTexture = resourceMap[texture]
                self.setTexture(mtlTexture, index: bindingIndex)
            case .buffer(let buffer, let offset):
                let mtlBuffer = resourceMap[buffer]
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
