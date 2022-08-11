//
//  ArgumentBuffer.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 16/03/18.
//

#if canImport(Metal)

@preconcurrency import Metal

extension ArgumentBuffer {
    func setArguments(storage: MTLBufferReference, resourceMap: FrameResourceMap<MetalBackend>) {
        if self.stateFlags.contains(.initialised) { return }
        
        let argEncoder = Unmanaged<MetalArgumentEncoder>.fromOpaque(self.encoder!).takeUnretainedValue()
        
        // Zero out the argument buffer.
        let destPointer = storage.buffer.contents() + storage.offset
        destPointer.assumingMemoryBound(to: UInt8.self).assign(repeating: 0, count: min(self.maximumAllocationLength, argEncoder.encoder.encodedLength))
        
        argEncoder.encoder.setArgumentBuffer(storage.buffer, startOffset: storage.offset, arrayElement: 0)
        argEncoder.encodeArguments(from: self, resourceMap: resourceMap)
        
        self.markAsInitialised()
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
                
                if let mtlHeap = mtlTexture.heap {
                    argBuffer.usedHeaps.insert(Unmanaged.passUnretained(mtlHeap).toOpaque())
                } else {
                    argBuffer.usedResources.insert(Unmanaged.passUnretained(mtlTexture).toOpaque())
                }
                
            case .buffer(let buffer, let offset):
                guard let mtlBuffer = resourceMap[buffer] else { continue }
                self.encoder.setBuffer(mtlBuffer.buffer, offset: offset + mtlBuffer.offset, index: bindingIndex)
                
                if let mtlHeap = mtlBuffer.buffer.heap {
                    argBuffer.usedHeaps.insert(Unmanaged.passUnretained(mtlHeap).toOpaque())
                } else {
                    argBuffer.usedResources.insert(mtlBuffer._buffer.toOpaque())
                }
                
            case .accelerationStructure(let structure):
                guard #available(macOS 11.0, iOS 14.0, *), let mtlStructure = resourceMap[structure] as! MTLAccelerationStructure? else { continue }
                self.encoder.setAccelerationStructure(mtlStructure, index: bindingIndex)
                
                if let mtlHeap = mtlStructure.heap {
                    argBuffer.usedHeaps.insert(Unmanaged.passUnretained(mtlHeap).toOpaque())
                } else {
                    argBuffer.usedResources.insert(Unmanaged.passUnretained(mtlStructure).toOpaque())
                }
                
            case .visibleFunctionTable(let table):
                guard #available(macOS 11.0, iOS 14.0, *), let mtlTable = resourceMap[table] else { continue }
                self.encoder.setVisibleFunctionTable(mtlTable.table, index: bindingIndex)
                
                if let mtlHeap = mtlTable.table.heap {
                    argBuffer.usedHeaps.insert(Unmanaged.passUnretained(mtlHeap).toOpaque())
                } else {
                    argBuffer.usedResources.insert(Unmanaged.passUnretained(mtlTable.table).toOpaque())
                }
            case .intersectionFunctionTable(let table):
                guard #available(macOS 11.0, iOS 14.0, *), let mtlTable = resourceMap[table] else { continue }
                self.encoder.setIntersectionFunctionTable(mtlTable.table, index: bindingIndex)
                
                if let mtlHeap = mtlTable.table.heap {
                    argBuffer.usedHeaps.insert(Unmanaged.passUnretained(mtlHeap).toOpaque())
                } else {
                    argBuffer.usedResources.insert(Unmanaged.passUnretained(mtlTable.table).toOpaque())
                }
            case .sampler(let samplerState):
                self.encoder.setSamplerState(Unmanaged<MTLSamplerState>.fromOpaque(UnsafeRawPointer(samplerState.state)).takeUnretainedValue(), index: bindingIndex)
            case .bytes(let offset, let length):
                let bytes = argBuffer._bytes(offset: offset)
                self.encoder.constantData(at: bindingIndex).copyMemory(from: bytes, byteCount: length)
            }
        }
    }
}

#endif // canImport(Metal)
