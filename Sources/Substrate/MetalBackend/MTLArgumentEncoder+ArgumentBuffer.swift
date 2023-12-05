//
//  ArgumentBuffer.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 16/03/18.
//

#if canImport(Metal)

@preconcurrency import Metal

extension ArgumentBuffer {
    func setArguments(storage: MTLBufferReference, resourceMap: FrameResourceMap<MetalBackend>) async {
        if self.stateFlags.contains(.initialised) { return }
        
        let argEncoder = Unmanaged<MetalArgumentEncoder>.fromOpaque(self.encoder!).takeUnretainedValue()
        
        // Zero out the argument buffer.
        let destPointer = storage.buffer.contents() + storage.offset
        var allocationLength = self.allocationLength
        if allocationLength == .max {
            allocationLength = argEncoder.encoder.encodedLength
        }
        destPointer.assumingMemoryBound(to: UInt8.self).assign(repeating: 0, count: allocationLength)
        
        argEncoder.encoder.setArgumentBuffer(storage.buffer, offset: storage.offset)
        await argEncoder.encodeArguments(from: self, resourceMap: resourceMap)
        
        self.markAsInitialised()
    }
}

extension ArgumentBufferArray {
    func setArguments(storage: MTLBufferReference, resourceMap: FrameResourceMap<MetalBackend>) async {
        var argEncoder : MetalArgumentEncoder? = nil
        
        for (i, argumentBuffer) in self._bindings.enumerated() {
            guard let argumentBuffer = argumentBuffer else { continue }
            if argumentBuffer.stateFlags.contains(.initialised) { continue }
            
            if argEncoder == nil {
                argEncoder = Unmanaged<MetalArgumentEncoder>.fromOpaque(argumentBuffer.encoder!).takeUnretainedValue()
            }
            
            argEncoder!.encoder.setArgumentBuffer(storage.buffer, startOffset: storage.offset, arrayElement: i)
            await argEncoder!.encodeArguments(from: argumentBuffer, resourceMap: resourceMap)
        }
    }
}

extension MetalArgumentEncoder {
    func encodeArguments(from argBuffer: ArgumentBuffer, resourceMap: FrameResourceMap<MetalBackend>) async {
        for (bindingPath, binding) in argBuffer.bindings {
            
            let bindingIndex = bindingPath.bindIndex
            guard bindingIndex <= self.maxBindingIndex else { continue }
            
            switch binding {
            case .texture(let texture):
                // We need to use renderTargetTexture in case the texture hasn't been materialised yet; this may force early drawable retrieval.
                // Substrate immediate-mode will address this issue directly.
                guard let mtlTexture = texture.flags.contains(.windowHandle) ? try? await resourceMap.renderTargetTexture(texture) : resourceMap[texture] else { continue }
                self.encoder.setTexture(mtlTexture.texture, index: bindingIndex)
            case .buffer(let buffer, let offset):
                guard let mtlBuffer = resourceMap[buffer] else { continue }
                self.encoder.setBuffer(mtlBuffer.buffer, offset: offset + mtlBuffer.offset, index: bindingIndex)
            case .accelerationStructure(let structure):
                guard #available(macOS 11.0, iOS 14.0, *), let mtlStructure = resourceMap[structure] else { continue }
                self.encoder.setAccelerationStructure((mtlStructure as! MTLAccelerationStructure), index: bindingIndex)
            case .visibleFunctionTable(let table):
                guard #available(macOS 11.0, iOS 14.0, *), let mtlTable = resourceMap[table] else { continue }
                self.encoder.setVisibleFunctionTable(mtlTable.table, index: bindingIndex)
            case .intersectionFunctionTable(let table):
                guard #available(macOS 11.0, iOS 14.0, *), let mtlTable = resourceMap[table] else { continue }
                self.encoder.setIntersectionFunctionTable(mtlTable.table, index: bindingIndex)
            case .sampler(let descriptor):
                let samplerState = await resourceMap[descriptor]
                self.encoder.setSamplerState(samplerState, index: bindingIndex)
            case .bytes(let offset, let length):
                let bytes = argBuffer._bytes(offset: offset)
                self.encoder.constantData(at: bindingIndex).copyMemory(from: bytes, byteCount: length)
            }
        }
    }
}

#endif // canImport(Metal)
