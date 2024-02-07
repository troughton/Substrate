//
//  ArgumentBuffer.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 16/03/18.
//

#if canImport(Metal)

@preconcurrency import Metal

extension ArgumentBufferDescriptor {
    func offset(index: Int, arrayIndex: Int) -> Int {
        let argumentIndex = self.arguments.binarySearch(predicate: { $0.index <= index }) - 1
        let argument = self.arguments[argumentIndex]
        assert(arrayIndex < argument.arrayLength)
        return argument.encodedBufferOffset + arrayIndex * argument.encodedBufferStride
    }
}

enum MetalArgumentBufferImpl: _ArgumentBufferImpl {
    static func encodedBufferSizeAndAlign(forArgument argument: ArgumentDescriptor) -> (size: Int, alignment: Int) {
        switch argument.resourceType {
        case .inlineData(let type):
            return (type.size!, type.alignment!)
        default:
            return (MemoryLayout<UInt64>.size, MemoryLayout<UInt64>.alignment)
        }
    }
    
    static var supportsResourceGPUAddresses: Bool {
        #if !targetEnvironment(simulator)
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, *) {
            return true
        }
        #endif
        return false
    }
    
    static func setBuffer(_ buffer: Buffer, offset: Int, at index: Int, arrayIndex: Int, on argBuffer: ArgumentBuffer) {
        if self.supportsResourceGPUAddresses {
            precondition(buffer[\.gpuAddresses] != 0, "Resource \(buffer) does not have a backing resource.")
            
            let gpuAddress = buffer[\.gpuAddresses] + UInt64(offset)
            
            argBuffer[\.mappedContents]!.storeBytes(of: gpuAddress, toByteOffset: argBuffer.descriptor.offset(index: index, arrayIndex: arrayIndex), as: UInt64.self)
        } else {
            let argBufferMTL = argBuffer.mtlBuffer!
            let encoder = argBuffer[\.encoders]!.takeUnretainedValue()
            encoder.setArgumentBuffer(argBufferMTL.buffer, offset: argBufferMTL.offset)
            
            let mtlBuffer = buffer.mtlBuffer!
            encoder.setBuffer(mtlBuffer.buffer, offset: mtlBuffer.offset + offset, index: index + arrayIndex)
        }
        
        if let heap = buffer.heap, let mtlHeap = heap.backingResourcePointer {
            argBuffer.usedHeaps.insert(mtlHeap)
        } else if let mtlResource = buffer.backingResourcePointer {
            argBuffer.usedResources.insert(mtlResource)
        }
    }
    
    static func setTexture(_ texture: Texture, at index: Int, arrayIndex: Int, on argBuffer: ArgumentBuffer) {
        if self.supportsResourceGPUAddresses {
            precondition(texture[\.gpuAddresses] != 0, "Resource \(texture) does not have a backing resource.")
            argBuffer[\.mappedContents]!.storeBytes(of: texture[\.gpuAddresses], toByteOffset: argBuffer.descriptor.offset(index: index, arrayIndex: arrayIndex), as: UInt64.self)
        } else {
            let argBufferMTL = argBuffer.mtlBuffer!
            let encoder = argBuffer[\.encoders]!.takeUnretainedValue()
            encoder.setArgumentBuffer(argBufferMTL.buffer, offset: argBufferMTL.offset)
            
            encoder.setTexture(texture.mtlTexture!, index: index + arrayIndex)
        }
        
        if let heap = texture.heap, let mtlHeap = heap.backingResourcePointer {
            argBuffer.usedHeaps.insert(mtlHeap)
        } else if let mtlResource = texture.backingResourcePointer {
            argBuffer.usedResources.insert(mtlResource)
        }
    }
    
    static func setAccelerationStructure(_ structure: AccelerationStructure, at index: Int, arrayIndex: Int, on argBuffer: ArgumentBuffer) {
        if self.supportsResourceGPUAddresses {
            precondition(structure[\.gpuAddresses] != 0, "Resource \(structure) does not have a backing resource.")
            argBuffer[\.mappedContents]!.storeBytes(of: structure[\.gpuAddresses], toByteOffset: argBuffer.descriptor.offset(index: index, arrayIndex: arrayIndex), as: UInt64.self)
        } else {
            let argBufferMTL = argBuffer.mtlBuffer!
            let encoder = argBuffer[\.encoders]!.takeUnretainedValue()
            encoder.setArgumentBuffer(argBufferMTL.buffer, offset: argBufferMTL.offset)
            
            encoder.setAccelerationStructure(structure.mtlAccelerationStructure!, index: index + arrayIndex)
        }
        
        if let heap = structure.heap, let mtlHeap = heap.backingResourcePointer {
            argBuffer.usedHeaps.insert(mtlHeap)
        } else if let mtlResource = structure.backingResourcePointer {
            argBuffer.usedResources.insert(mtlResource)
        }
    }
    
    static func setVisibleFunctionTable(_ table: VisibleFunctionTable, at index: Int, arrayIndex: Int, on argBuffer: ArgumentBuffer) {
        if self.supportsResourceGPUAddresses {
            precondition(table[\.gpuAddresses] != 0, "Resource \(table) does not have a backing resource.")
            argBuffer[\.mappedContents]!.storeBytes(of: table[\.gpuAddresses], toByteOffset: argBuffer.descriptor.offset(index: index, arrayIndex: arrayIndex), as: UInt64.self)
        } else {
            let argBufferMTL = argBuffer.mtlBuffer!
            let encoder = argBuffer[\.encoders]!.takeUnretainedValue()
            encoder.setArgumentBuffer(argBufferMTL.buffer, offset: argBufferMTL.offset)
            
            encoder.setVisibleFunctionTable(table.mtlVisibleFunctionTable!, index: index + arrayIndex)
        }
        
        if let heap = table.heap, let mtlHeap = heap.backingResourcePointer {
            argBuffer.usedHeaps.insert(mtlHeap)
        } else if let mtlResource = table.backingResourcePointer {
            argBuffer.usedResources.insert(mtlResource)
        }
    }
    
    static func setIntersectionFunctionTable(_ table: IntersectionFunctionTable, at index: Int, arrayIndex: Int, on argBuffer: ArgumentBuffer) {
        if self.supportsResourceGPUAddresses {
            precondition(table[\.gpuAddresses] != 0, "Resource \(table) does not have a backing resource.")
            
            argBuffer[\.mappedContents]!.storeBytes(of: table[\.gpuAddresses], toByteOffset: argBuffer.descriptor.offset(index: index, arrayIndex: arrayIndex), as: UInt64.self)
        } else {
            let argBufferMTL = argBuffer.mtlBuffer!
            let encoder = argBuffer[\.encoders]!.takeUnretainedValue()
            encoder.setArgumentBuffer(argBufferMTL.buffer, offset: argBufferMTL.offset)
            
            encoder.setIntersectionFunctionTable(table.mtlIntersectionFunctionTable!, index: index + arrayIndex)
        }
        
        if let heap = table.heap, let mtlHeap = heap.backingResourcePointer {
            argBuffer.usedHeaps.insert(mtlHeap)
        } else if let mtlResource = table.backingResourcePointer {
            argBuffer.usedResources.insert(mtlResource)
        }
    }
    
    static func setSampler(_ sampler: SamplerState, at index: Int, arrayIndex: Int, on argBuffer: ArgumentBuffer) {
        let state = Unmanaged<MTLSamplerState>.fromOpaque(UnsafeRawPointer(sampler.state)).takeUnretainedValue()
        
        if self.supportsResourceGPUAddresses {
            argBuffer[\.mappedContents]!.storeBytes(of: state.gpuResourceID, toByteOffset: argBuffer.descriptor.offset(index: index, arrayIndex: arrayIndex), as: MTLResourceID.self)
        } else {
            let argBufferMTL = argBuffer.mtlBuffer!
            let encoder = argBuffer[\.encoders]!.takeUnretainedValue()
            encoder.setArgumentBuffer(argBufferMTL.buffer, offset: argBufferMTL.offset)
            
            encoder.setSamplerState(state, index: index + arrayIndex)
        }
    }
    
    static func setBytes(_ bytes: UnsafeRawBufferPointer, at index: Int, arrayIndex: Int, on argBuffer: ArgumentBuffer) {
        let offset = argBuffer.descriptor.offset(index: index, arrayIndex: arrayIndex)
        argBuffer[\.mappedContents]!.advanced(by: offset).copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
    }
}

#endif // canImport(Metal)
