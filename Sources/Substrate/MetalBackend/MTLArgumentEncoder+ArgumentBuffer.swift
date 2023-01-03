//
//  ArgumentBuffer.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 16/03/18.
//

#if canImport(Metal)

@preconcurrency import Metal

extension ArgumentBufferDescriptor {
    func offset(forBindIndex bindIndex: Int) -> Int {
        let argumentIndex = self.arguments.binarySearch(predicate: { $0.index <= bindIndex }) - 1
        let argument = self.arguments[argumentIndex]
        return argument.encodedBufferOffset + (bindIndex - argument.index) * argument.encodedBufferStride
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
    
    static func setBuffer(_ buffer: Buffer, offset: Int, at path: ResourceBindingPath, on argBuffer: ArgumentBuffer) {
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, *) {
            precondition(buffer[\.gpuAddresses] != 0, "Resource \(buffer) does not have a backing resource.")
            
            let gpuAddress = buffer[\.gpuAddresses] + UInt64(offset)
            
            argBuffer[\.mappedContents]!.storeBytes(of: gpuAddress, toByteOffset: argBuffer.descriptor.offset(forBindIndex: path.bindIndex), as: UInt64.self)
        } else {
            let argBufferMTL = argBuffer.mtlBuffer!
            let encoder = argBuffer[\.encoders]!.takeUnretainedValue()
            encoder.setArgumentBuffer(argBufferMTL.buffer, offset: argBufferMTL.offset)
            
            let mtlBuffer = buffer.mtlBuffer!
            encoder.setBuffer(mtlBuffer.buffer, offset: mtlBuffer.offset + offset, index: path.bindIndex)
        }
        
        if let heap = buffer.heap, let mtlHeap = heap[\.backingResources] {
            argBuffer.usedHeaps.insert(mtlHeap)
        } else if let mtlResource = buffer[\.backingResources] {
            argBuffer.usedResources.insert(mtlResource)
        }
    }
    
    static func setTexture(_ texture: Texture, at path: ResourceBindingPath, on argBuffer: ArgumentBuffer) {
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, *) {
            precondition(texture[\.gpuAddresses] != 0, "Resource \(texture) does not have a backing resource.")
            argBuffer[\.mappedContents]!.storeBytes(of: texture[\.gpuAddresses], toByteOffset: argBuffer.descriptor.offset(forBindIndex: path.bindIndex), as: UInt64.self)
        } else {
            let argBufferMTL = argBuffer.mtlBuffer!
            let encoder = argBuffer[\.encoders]!.takeUnretainedValue()
            encoder.setArgumentBuffer(argBufferMTL.buffer, offset: argBufferMTL.offset)
            
            encoder.setTexture(texture.mtlTexture!, index: path.bindIndex)
        }
        
        if let heap = texture.heap, let mtlHeap = heap[\.backingResources] {
            argBuffer.usedHeaps.insert(mtlHeap)
        } else if let mtlResource = texture[\.backingResources] {
            argBuffer.usedResources.insert(mtlResource)
        }
    }
    
    static func setAccelerationStructure(_ structure: AccelerationStructure, at path: ResourceBindingPath, on argBuffer: ArgumentBuffer) {
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, *) {
            precondition(structure[\.gpuAddresses] != 0, "Resource \(structure) does not have a backing resource.")
            argBuffer[\.mappedContents]!.storeBytes(of: structure[\.gpuAddresses], toByteOffset: argBuffer.descriptor.offset(forBindIndex: path.bindIndex), as: UInt64.self)
        } else {
            let argBufferMTL = argBuffer.mtlBuffer!
            let encoder = argBuffer[\.encoders]!.takeUnretainedValue()
            encoder.setArgumentBuffer(argBufferMTL.buffer, offset: argBufferMTL.offset)
            
            encoder.setAccelerationStructure(structure.mtlAccelerationStructure!, index: path.bindIndex)
        }
        
        if let heap = structure.heap, let mtlHeap = heap[\.backingResources] {
            argBuffer.usedHeaps.insert(mtlHeap)
        } else if let mtlResource = structure[\.backingResources] {
            argBuffer.usedResources.insert(mtlResource)
        }
    }
    
    static func setVisibleFunctionTable(_ table: VisibleFunctionTable, at path: ResourceBindingPath, on argBuffer: ArgumentBuffer) {
        
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, *) {
            precondition(table[\.gpuAddresses] != 0, "Resource \(table) does not have a backing resource.")
            argBuffer[\.mappedContents]!.storeBytes(of: table[\.gpuAddresses], toByteOffset: argBuffer.descriptor.offset(forBindIndex: path.bindIndex), as: UInt64.self)
        } else {
            let argBufferMTL = argBuffer.mtlBuffer!
            let encoder = argBuffer[\.encoders]!.takeUnretainedValue()
            encoder.setArgumentBuffer(argBufferMTL.buffer, offset: argBufferMTL.offset)
            
            encoder.setVisibleFunctionTable(table.mtlVisibleFunctionTable!, index: path.bindIndex)
        }
        
        if let heap = table.heap, let mtlHeap = heap[\.backingResources] {
            argBuffer.usedHeaps.insert(mtlHeap)
        } else if let mtlResource = table[\.backingResources] {
            argBuffer.usedResources.insert(mtlResource)
        }
    }
    
    static func setIntersectionFunctionTable(_ table: IntersectionFunctionTable, at path: ResourceBindingPath, on argBuffer: ArgumentBuffer) {
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, *) {
            precondition(table[\.gpuAddresses] != 0, "Resource \(table) does not have a backing resource.")
            
            argBuffer[\.mappedContents]!.storeBytes(of: table[\.gpuAddresses], toByteOffset: argBuffer.descriptor.offset(forBindIndex: path.bindIndex), as: UInt64.self)
        } else {
            let argBufferMTL = argBuffer.mtlBuffer!
            let encoder = argBuffer[\.encoders]!.takeUnretainedValue()
            encoder.setArgumentBuffer(argBufferMTL.buffer, offset: argBufferMTL.offset)
            
            encoder.setIntersectionFunctionTable(table.mtlIntersectionFunctionTable!, index: path.bindIndex)
        }
        
        if let heap = table.heap, let mtlHeap = heap[\.backingResources] {
            argBuffer.usedHeaps.insert(mtlHeap)
        } else if let mtlResource = table[\.backingResources] {
            argBuffer.usedResources.insert(mtlResource)
        }
    }
    
    static func setSampler(_ sampler: SamplerState, at path: ResourceBindingPath, on argBuffer: ArgumentBuffer) {
        let state = Unmanaged<MTLSamplerState>.fromOpaque(UnsafeRawPointer(sampler.state)).takeUnretainedValue()
        
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, *) {
            argBuffer[\.mappedContents]!.storeBytes(of: state.gpuResourceID, toByteOffset: argBuffer.descriptor.offset(forBindIndex: path.bindIndex), as: MTLResourceID.self)
        } else {
            let argBufferMTL = argBuffer.mtlBuffer!
            let encoder = argBuffer[\.encoders]!.takeUnretainedValue()
            encoder.setArgumentBuffer(argBufferMTL.buffer, offset: argBufferMTL.offset)
            
            encoder.setSamplerState(state, index: path.bindIndex)
        }
    }
    
    static func setBytes(_ bytes: UnsafeRawBufferPointer, at path: ResourceBindingPath, on argBuffer: ArgumentBuffer) {
        let offset = argBuffer.descriptor.offset(forBindIndex: path.bindIndex)
        argBuffer[\.mappedContents]!.advanced(by: offset).copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
    }
}

#endif // canImport(Metal)
