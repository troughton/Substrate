//
//  File.swift
//  
//
//  Created by Thomas Roughton on 6/07/22.
//

#if canImport(Metal)
import Foundation
import Metal

final class MetalAccelerationStructureCommandEncoder: AccelerationStructureCommandEncoderImpl {
    let encoder: MTLAccelerationStructureCommandEncoder
    
    init(encoder: MTLAccelerationStructureCommandEncoder) {
        self.encoder = encoder
    }
    
    func setLabel(_ label: String) {
        encoder.label = label
    }
    
    func pushDebugGroup(_ groupName: String) {
        encoder.pushDebugGroup(groupName)
    }
    
    func popDebugGroup() {
        encoder.popDebugGroup()
    }
    
    func insertDebugSignpost(_ string: String) {
        encoder.insertDebugSignpost(string)
    }
    
    func build(accelerationStructure structure: AccelerationStructure, descriptor: AccelerationStructureDescriptor, scratchBuffer: Buffer, scratchBufferOffset: Int) {
        let structure = structure.mtlAccelerationStructure!
        let descriptor = descriptor.metalDescriptor()
        let scratchBuffer = scratchBuffer.mtlBuffer!
        let scratchBufferOffset = scratchBufferOffset
        encoder.build(accelerationStructure: structure, descriptor: descriptor, scratchBuffer: scratchBuffer.buffer, scratchBufferOffset: scratchBuffer.offset + scratchBufferOffset)
    }

    func refit(sourceAccelerationStructure source: AccelerationStructure, descriptor: AccelerationStructureDescriptor, destinationAccelerationStructure destination: AccelerationStructure?, scratchBuffer: Buffer, scratchBufferOffset: Int) {
        let source = source.mtlAccelerationStructure!
        let descriptor = descriptor.metalDescriptor()
        let destination = destination.map { $0.mtlAccelerationStructure! }
        let scratchBuffer = scratchBuffer.mtlBuffer!
        let scratchBufferOffset = scratchBufferOffset
        
        encoder.refit(sourceAccelerationStructure: source, descriptor: descriptor, destinationAccelerationStructure: destination, scratchBuffer: scratchBuffer.wrappedValue, scratchBufferOffset: scratchBuffer.offset + scratchBufferOffset)
    }
    
    func copy(sourceAccelerationStructure source: AccelerationStructure, destinationAccelerationStructure destination: AccelerationStructure) {
        encoder.copy(sourceAccelerationStructure: source.mtlAccelerationStructure!, destinationAccelerationStructure: destination.mtlAccelerationStructure!)
    }

    // vkCmdWriteAccelerationStructuresPropertiesKHR
    func writeCompactedSize(of structure: AccelerationStructure, to toBuffer: Buffer, offset: Int) {
        let buffer = toBuffer.mtlBuffer!
        encoder.writeCompactedSize(accelerationStructure: structure.mtlAccelerationStructure!, buffer: buffer.buffer, offset: buffer.offset + offset)
    }

    func copyAndCompact(sourceAccelerationStructure source: AccelerationStructure, destinationAccelerationStructure destination: AccelerationStructure) {
        destination.descriptor = source.descriptor
        encoder.copyAndCompact(sourceAccelerationStructure: source.mtlAccelerationStructure!, destinationAccelerationStructure: destination.mtlAccelerationStructure!)
    }
}

extension MTLAccelerationStructureCommandEncoder {
    func executeResourceCommands(resourceCommandIndex: inout Int, resourceCommands: [CompactedResourceCommand<MetalCompactedResourceCommandType>], passIndex: Int, order: PerformOrder, isAppleSiliconGPU: Bool) {
        while resourceCommandIndex < resourceCommands.count {
            let command = resourceCommands[resourceCommandIndex]
            
            guard command.index < passIndex || (command.index == passIndex && command.order == order) else {
                break
            }
            
            switch command.command {
            case .resourceMemoryBarrier, .scopedMemoryBarrier:
                break
                
            case .useResources(let resources, let usage, _):
                self.__use(resources.baseAddress!, count: resources.count, usage: usage)
                
            case .useHeaps(let heaps):
                for heap in heaps {
                    self.useHeap(heap.resource.takeUnretainedValue())
                }
                
            case .updateFence(let fence, _):
                self.updateFence(fence.fence)
                
            case .waitForFence(let fence, _):
                self.waitForFence(fence.fence)
            }
            
            resourceCommandIndex += 1
        }
    }
}

#endif // canImport(Metal)
