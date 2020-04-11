//
//  ArgumentBuffer.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 16/03/18.
//

#if canImport(Metal)

import Metal

extension _ArgumentBuffer {
    func setArguments(storage: MTLBufferReference, resourceMap: FrameResourceMap<MetalBackend>) {
        if self.stateFlags.contains(.initialised) { return }
        
        let argEncoder = Unmanaged<MTLArgumentEncoder>.fromOpaque(self.encoder!).takeUnretainedValue()
        
        argEncoder.setArgumentBuffer(storage.buffer, offset: storage.offset)
        argEncoder.encodeArguments(from: self, resourceMap: resourceMap)
        
        self.markAsInitialised()
    }
}

extension _ArgumentBufferArray {
    func setArguments(storage: MTLBufferReference, resourceMap: FrameResourceMap<MetalBackend>) {
        var argEncoder : MTLArgumentEncoder? = nil
        
        for (i, argumentBuffer) in self._bindings.enumerated() {
            guard let argumentBuffer = argumentBuffer else { continue }
            if argumentBuffer.stateFlags.contains(.initialised) { continue }
            
            if argEncoder == nil {
                argEncoder = Unmanaged<MTLArgumentEncoder>.fromOpaque(argumentBuffer.encoder!).takeUnretainedValue()
            }
            
            argEncoder!.setArgumentBuffer(storage.buffer, startOffset: storage.offset, arrayElement: i)
            argEncoder!.encodeArguments(from: argumentBuffer, resourceMap: resourceMap)
        }
    }
}

extension MTLArgumentEncoder {
    func encodeArguments(from argBuffer: _ArgumentBuffer, resourceMap: FrameResourceMap<MetalBackend>) {
        for (bindingPath, binding) in argBuffer.bindings {
            
            let bindingIndex = bindingPath.bindIndex
            
            switch binding {
            case .texture(let texture):
                let mtlTexture = resourceMap[texture].texture
                self.setTexture(mtlTexture, index: bindingIndex)
            case .buffer(let buffer, let offset):
                let mtlBuffer = resourceMap[buffer]
                self.setBuffer(mtlBuffer.buffer, offset: offset + mtlBuffer.offset, index: bindingIndex)
            case .sampler(let descriptor):
                let samplerState = resourceMap[descriptor]
                self.setSamplerState(samplerState, index: bindingIndex)
            case .bytes(let offset, let length):
                let bytes = argBuffer._bytes(offset: offset)
                self.constantData(at: bindingIndex).copyMemory(from: bytes, byteCount: length)
            }
        }
    }
}

#endif // canImport(Metal)
