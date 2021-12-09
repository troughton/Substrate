//
//  ArgumentBuffer.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 16/03/18.
//

#if canImport(Metal)

import Metal

extension ArgumentBuffer {
    func setArguments(storage: MTLBufferReference, resourceMap: FrameResourceMap<MetalBackend>) {
        if self.stateFlags.contains(.initialised) { return }
        
        let argEncoder = Unmanaged<MetalArgumentEncoder>.fromOpaque(self.encoder!).takeUnretainedValue()
        
        // Zero out the argument buffer.
        let destPointer = storage.buffer.contents() + storage.offset
        destPointer.assumingMemoryBound(to: UInt8.self).assign(repeating: 0, count: argEncoder.encoder.encodedLength)
        
        argEncoder.encoder.setArgumentBuffer(storage.buffer, offset: storage.offset)
        argEncoder.encodeArguments(from: self, resourceMap: resourceMap)
        
        self.markAsInitialised()
    }
}

extension ArgumentBufferArray {
    func setArguments(storage: MTLBufferReference, resourceMap: FrameResourceMap<MetalBackend>) {
        var argEncoder : MetalArgumentEncoder? = nil
        
        for (i, argumentBuffer) in self._bindings.enumerated() {
            guard let argumentBuffer = argumentBuffer else { continue }
            if argumentBuffer.stateFlags.contains(.initialised) { continue }
            
            if argEncoder == nil {
                argEncoder = Unmanaged<MetalArgumentEncoder>.fromOpaque(argumentBuffer.encoder!).takeUnretainedValue()
            }
            
            argEncoder!.encoder.setArgumentBuffer(storage.buffer, startOffset: storage.offset, arrayElement: i)
            argEncoder!.encodeArguments(from: argumentBuffer, resourceMap: resourceMap)
        }
    }
}

extension MetalArgumentEncoder {
    func encodeArguments(from argBuffer: ArgumentBuffer, resourceMap: FrameResourceMap<MetalBackend>) {
        for (bindingPath, binding) in argBuffer.bindings {
            
            let bindingIndex = bindingPath.bindIndex
            guard bindingIndex <= self.maxBindingIndex else { continue }
            
            switch binding {
            case .texture(let texture):
                guard let mtlTexture = resourceMap[texture]?.texture else { continue }
                self.encoder.setTexture(mtlTexture, index: bindingIndex)
            case .buffer(let buffer, let offset):
                guard let mtlBuffer = resourceMap[buffer] else { continue }
                self.encoder.setBuffer(mtlBuffer.buffer, offset: offset + mtlBuffer.offset, index: bindingIndex)
            case .sampler(let descriptor):
                let samplerState = resourceMap[descriptor]
                self.encoder.setSamplerState(samplerState, index: bindingIndex)
            case .bytes(let offset, let length):
                let bytes = argBuffer._bytes(offset: offset)
                self.encoder.constantData(at: bindingIndex).copyMemory(from: bytes, byteCount: length)
            }
        }
    }
}

#endif // canImport(Metal)
