//
//  ArgumentBuffer.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 16/03/18.
//

#if canImport(Metal)

import Metal

extension ArgumentBufferDescriptor {
    func offset(index: Int, arrayIndex: Int) -> Int {
        let argumentIndex = self.arguments.binarySearch(predicate: { $0.index <= index }) - 1
        let argument = self.arguments[argumentIndex]
        assert(arrayIndex < argument.arrayLength)
        return argument.encodedBufferOffset + arrayIndex * argument.encodedBufferStride
    }
    
    func metalIndex(index: Int, arrayIndex: Int) -> Int {
        return index + arrayIndex
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
        let metalIndex = argBuffer.descriptor.metalIndex(index: index, arrayIndex: arrayIndex)
        if self.supportsResourceGPUAddresses {
            precondition(buffer[\.gpuAddresses] != 0, "Resource \(buffer) does not have a backing resource.")
            
            let gpuAddress = buffer[\.gpuAddresses] + UInt64(offset)
            
            argBuffer[\.mappedContents]!.storeBytes(of: gpuAddress, toByteOffset: argBuffer.descriptor.offset(index: index, arrayIndex: arrayIndex), as: UInt64.self)
        } else {
            let argBufferMTL = argBuffer.mtlBuffer!
            let encoder = argBuffer[\.encoders]!.takeUnretainedValue()
            encoder.setArgumentBuffer(argBufferMTL.buffer, offset: argBufferMTL.offset)
            
            let mtlBuffer = buffer.mtlBuffer!
            encoder.setBuffer(mtlBuffer.buffer, offset: mtlBuffer.offset + offset, index: metalIndex)
        }
        
        argBuffer.encodedResources[metalIndex] = Resource(buffer)
        self.invalidateUsedResources(for: argBuffer)
    }
    
    static func setArgumentBuffer(_ buffer: ArgumentBuffer, at index: Int, arrayIndex: Int, on argBuffer: ArgumentBuffer) {
        let metalIndex = argBuffer.descriptor.metalIndex(index: index, arrayIndex: arrayIndex)
        if self.supportsResourceGPUAddresses {
            precondition(buffer[\.gpuAddresses] != 0, "Resource \(buffer) does not have a backing resource.")
            
            let gpuAddress = buffer[\.gpuAddresses]
            
            argBuffer[\.mappedContents]!.storeBytes(of: gpuAddress, toByteOffset: argBuffer.descriptor.offset(index: index, arrayIndex: arrayIndex), as: UInt64.self)
        } else {
            let argBufferMTL = argBuffer.mtlBuffer!
            let encoder = argBuffer[\.encoders]!.takeUnretainedValue()
            encoder.setArgumentBuffer(argBufferMTL.buffer, offset: argBufferMTL.offset)
            
            let mtlBuffer = buffer.mtlBuffer!
            encoder.setBuffer(mtlBuffer.buffer, offset: mtlBuffer.offset, index: metalIndex)
        }
        
        argBuffer.encodedResources[metalIndex] = buffer.baseResource ?? Resource(buffer)
        self.invalidateUsedResources(for: argBuffer)
    }
    
    static func setTexture(_ texture: Texture, at index: Int, arrayIndex: Int, on argBuffer: ArgumentBuffer) {
        let metalIndex = argBuffer.descriptor.metalIndex(index: index, arrayIndex: arrayIndex)
        if self.supportsResourceGPUAddresses {
            precondition(texture[\.gpuAddresses] != 0, "Resource \(texture) does not have a backing resource.")
            argBuffer[\.mappedContents]!.storeBytes(of: texture[\.gpuAddresses], toByteOffset: argBuffer.descriptor.offset(index: index, arrayIndex: arrayIndex), as: UInt64.self)
        } else {
            let argBufferMTL = argBuffer.mtlBuffer!
            let encoder = argBuffer[\.encoders]!.takeUnretainedValue()
            encoder.setArgumentBuffer(argBufferMTL.buffer, offset: argBufferMTL.offset)
            
            encoder.setTexture(texture.mtlTexture!, index: metalIndex)
        }
        
        argBuffer.encodedResources[metalIndex] = texture.baseResource ?? Resource(texture)
        self.invalidateUsedResources(for: argBuffer)
    }
    
    static func setAccelerationStructure(_ structure: AccelerationStructure, at index: Int, arrayIndex: Int, on argBuffer: ArgumentBuffer) {
        let metalIndex = argBuffer.descriptor.metalIndex(index: index, arrayIndex: arrayIndex)
        if self.supportsResourceGPUAddresses {
            precondition(structure[\.gpuAddresses] != 0, "Resource \(structure) does not have a backing resource.")
            argBuffer[\.mappedContents]!.storeBytes(of: structure[\.gpuAddresses], toByteOffset: argBuffer.descriptor.offset(index: index, arrayIndex: arrayIndex), as: UInt64.self)
        } else {
            let argBufferMTL = argBuffer.mtlBuffer!
            let encoder = argBuffer[\.encoders]!.takeUnretainedValue()
            encoder.setArgumentBuffer(argBufferMTL.buffer, offset: argBufferMTL.offset)
            
            encoder.setAccelerationStructure(structure.mtlAccelerationStructure!, index: metalIndex)
        }
        
        argBuffer.encodedResources[metalIndex] = Resource(structure)
        self.invalidateUsedResources(for: argBuffer)
    }
    
    static func setVisibleFunctionTable(_ table: VisibleFunctionTable, at index: Int, arrayIndex: Int, on argBuffer: ArgumentBuffer) {
        let metalIndex = argBuffer.descriptor.metalIndex(index: index, arrayIndex: arrayIndex)
        if self.supportsResourceGPUAddresses {
            precondition(table[\.gpuAddresses] != 0, "Resource \(table) does not have a backing resource.")
            argBuffer[\.mappedContents]!.storeBytes(of: table[\.gpuAddresses], toByteOffset: argBuffer.descriptor.offset(index: index, arrayIndex: arrayIndex), as: UInt64.self)
        } else {
            let argBufferMTL = argBuffer.mtlBuffer!
            let encoder = argBuffer[\.encoders]!.takeUnretainedValue()
            encoder.setArgumentBuffer(argBufferMTL.buffer, offset: argBufferMTL.offset)
            
            encoder.setVisibleFunctionTable(table.mtlVisibleFunctionTable!, index: metalIndex)
        }
        
        argBuffer.encodedResources[metalIndex] = Resource(table)
        self.invalidateUsedResources(for: argBuffer)
    }
    
    static func setIntersectionFunctionTable(_ table: IntersectionFunctionTable, at index: Int, arrayIndex: Int, on argBuffer: ArgumentBuffer) {
        let metalIndex = argBuffer.descriptor.metalIndex(index: index, arrayIndex: arrayIndex)
        if self.supportsResourceGPUAddresses {
            precondition(table[\.gpuAddresses] != 0, "Resource \(table) does not have a backing resource.")
            
            argBuffer[\.mappedContents]!.storeBytes(of: table[\.gpuAddresses], toByteOffset: argBuffer.descriptor.offset(index: index, arrayIndex: arrayIndex), as: UInt64.self)
        } else {
            let argBufferMTL = argBuffer.mtlBuffer!
            let encoder = argBuffer[\.encoders]!.takeUnretainedValue()
            encoder.setArgumentBuffer(argBufferMTL.buffer, offset: argBufferMTL.offset)
            
            encoder.setIntersectionFunctionTable(table.mtlIntersectionFunctionTable!, index: metalIndex)
        }
        
        argBuffer.encodedResources[metalIndex] = Resource(table)
        self.invalidateUsedResources(for: argBuffer)
    }
    
    static func setSampler(_ sampler: SamplerState, at index: Int, arrayIndex: Int, on argBuffer: ArgumentBuffer) {
        let state = Unmanaged<MTLSamplerState>.fromOpaque(UnsafeRawPointer(sampler.state)).takeUnretainedValue()
        
        if self.supportsResourceGPUAddresses, #available(macOS 13.0, iOS 16.0, tvOS 16.0, *) {
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
    
    static func invalidateUsedResources(for argBuffer: ArgumentBuffer) {
        argBuffer.encodedResourcesLock.withLock {
            argBuffer.usedResources.removeAll()
            argBuffer.usedHeaps.removeAll()
        }
    }
    
    static func computeUsedResources(for argBuffer: ArgumentBuffer) {
        assert(argBuffer.encodedResourcesLock.isLocked)
        guard argBuffer.usedResources.isEmpty, argBuffer.usedHeaps.isEmpty else { return }
        
        for resource in argBuffer.encodedResources {
            guard let resource = resource, let backingResourcePtr = resource.backingResourcePointer else { continue }
            if let nestedArgumentBuffer = ArgumentBuffer(resource) {
                self.computeUsedResources(for: nestedArgumentBuffer)
                
                // We use all the resources that the referenced argument buffer uses...
                for heap in nestedArgumentBuffer.usedHeaps {
                    argBuffer.usedHeaps.insert(heap)
                }
                
                for resource in nestedArgumentBuffer.usedResources {
                    argBuffer.usedResources.insert(resource)
                }
            }
            
            if let heap = resource.heap, let mtlHeap = heap.backingResourcePointer {
                argBuffer.usedHeaps.insert(mtlHeap)
            } else {
                argBuffer.usedResources.insert(backingResourcePtr)
            }
        }
    }
    
    static func computeUsedResources(for argBufferArray: ArgumentBufferArray) {
        assert(argBufferArray.encodedResourcesLock.isLocked)
        guard argBufferArray.usedResources.isEmpty, argBufferArray.usedHeaps.isEmpty else { return }
        
        for i in 0..<argBufferArray.arrayLength {
            let nestedArgBuffer = argBufferArray[i]
            nestedArgBuffer.encodedResourcesLock.withLock {
                self.computeUsedResources(for: nestedArgBuffer)
                
                for usedResource in nestedArgBuffer.usedResources {
                    argBufferArray.usedResources.insert(usedResource)
                }
                
                for usedResource in nestedArgBuffer.usedHeaps {
                    argBufferArray.usedHeaps.insert(usedResource)
                }
            }
        }
    }
}

#endif // canImport(Metal)
