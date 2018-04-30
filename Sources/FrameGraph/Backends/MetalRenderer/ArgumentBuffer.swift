//
//  ArgumentBuffer.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 16/03/18.
//

import Metal
import RenderAPI

final class MetalArgumentBuffer {
    public let buffer : MTLBuffer
    public let offset : Int
    
    public init(encoder: MTLArgumentEncoder, resourceRegistry: ResourceRegistry, stateCaches: StateCaches, bindingPath: ResourceBindingPath, arguments: ArgumentBuffer) {
    
        let storage = resourceRegistry.allocateArgumentBufferStorage(for: arguments, encodedLength: encoder.encodedLength)
        self.buffer = storage.buffer
        self.offset = storage.offset
        
        self.encodeArguments(from: arguments, argumentBufferPath: bindingPath, encoder: encoder, resourceRegistry: resourceRegistry, stateCaches: stateCaches)
    }
    
    // TODO: not all resources may exist at the first use, so we need to try to fill in the remaining resources once they're materialised every time the argument buffer is bound.
    
    func encodeArguments(from buffer: ArgumentBuffer, argumentBufferPath: ResourceBindingPath, encoder: MTLArgumentEncoder, resourceRegistry: ResourceRegistry, stateCaches: StateCaches) {
        encoder.setArgumentBuffer(self.buffer, offset: self.offset)
        
        for (bindingPath, binding) in buffer.bindings {

            let bindingIndex = MetalResourceBindingPath(bindingPath).bindIndex
            
            switch binding {
            case .texture(let texture):
                guard let mtlTexture = resourceRegistry[texture] else { continue }
                encoder.setTexture(mtlTexture, index: bindingIndex)
            case .buffer(let buffer, let offset):
                guard let mtlBuffer = resourceRegistry[buffer] else { continue }
                encoder.setBuffer(mtlBuffer.buffer, offset: offset + mtlBuffer.offset, index: bindingIndex)
            case .sampler(let descriptor):
                let samplerState = stateCaches[descriptor]
                encoder.setSamplerState(samplerState, index: bindingIndex)
            case .bytes(let offset, let length):
                let bytes = buffer.bytes(offset: offset)
                encoder.constantData(at: bindingIndex).copyMemory(from: bytes, byteCount: length)
            }
        }
        
        self.buffer.didModifyRange(self.offset..<(self.offset + encoder.encodedLength))
    }
}
