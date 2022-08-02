//
//  File.swift
//  
//
//  Created by Thomas Roughton on 6/07/22.
//

#if canImport(Metal)
import Foundation
import Metal

final class MetalAccelerationStructureCommandEncoder: AccelerationStructureCommandEncoder {
    let encoder: MTLAccelerationStructureCommandEncoder
    let resourceMap: FrameResourceMap<MetalBackend>
    
    init(passRecord: RenderPassRecord, encoder: MTLAccelerationStructureCommandEncoder, resourceMap: FrameResourceMap<MetalBackend>) {
        self.encoder = encoder
        self.resourceMap = resourceMap
        super.init(accelerationStructureRenderPass: passRecord.pass as! AccelerationStructureRenderPass, passRecord: passRecord)
    }
    
    override func build(accelerationStructure structure: AccelerationStructure, descriptor: AccelerationStructureDescriptor, scratchBuffer: Buffer, scratchBufferOffset: Int) {
        let structure = resourceMap[structure]! as! MTLAccelerationStructure
        let descriptor = descriptor.metalDescriptor(resourceMap: resourceMap)
        let scratchBuffer = resourceMap[scratchBuffer]!
        let scratchBufferOffset = scratchBufferOffset
        encoder.build(accelerationStructure: structure, descriptor: descriptor, scratchBuffer: scratchBuffer.buffer, scratchBufferOffset: scratchBuffer.offset + scratchBufferOffset)
    }
    
    override func build(accelerationStructure: AccelerationStructure, descriptor: AccelerationStructureDescriptor) {
        let scratchBuffer = Buffer(length: descriptor.sizes.buildScratchBufferSize, storageMode: .private)
        self.build(accelerationStructure: accelerationStructure, descriptor: descriptor, scratchBuffer: scratchBuffer, scratchBufferOffset: 0)
    }

    override func refit(sourceAccelerationStructure source: AccelerationStructure, descriptor: AccelerationStructureDescriptor, destinationAccelerationStructure destination: AccelerationStructure?, scratchBuffer: Buffer, scratchBufferOffset: Int) {
        let source = resourceMap[source]! as! MTLAccelerationStructure
        let descriptor = descriptor.metalDescriptor(resourceMap: resourceMap)
        let destination = destination.map { resourceMap[$0]! as! MTLAccelerationStructure }
        let scratchBuffer = resourceMap[scratchBuffer]!
        let scratchBufferOffset = scratchBufferOffset
        
        encoder.refit(sourceAccelerationStructure: source, descriptor: descriptor, destinationAccelerationStructure: destination, scratchBuffer: scratchBuffer.buffer, scratchBufferOffset: scratchBuffer.offset + scratchBufferOffset)
    }
    
    override func refit(sourceAccelerationStructure: AccelerationStructure, descriptor: AccelerationStructureDescriptor, destinationAccelerationStructure: AccelerationStructure?) {
        let scratchBuffer = Buffer(length: descriptor.sizes.refitScratchBufferSize, storageMode: .private)
        self.refit(sourceAccelerationStructure: sourceAccelerationStructure, descriptor: descriptor, destinationAccelerationStructure: destinationAccelerationStructure, scratchBuffer: scratchBuffer, scratchBufferOffset: 0)
    }
    
    override func copy(sourceAccelerationStructure source: AccelerationStructure, destinationAccelerationStructure destination: AccelerationStructure) {
        let source = resourceMap[source]! as! MTLAccelerationStructure
        let destination = resourceMap[destination]! as! MTLAccelerationStructure
        encoder.copy(sourceAccelerationStructure: source, destinationAccelerationStructure: destination)
    }

    // vkCmdWriteAccelerationStructuresPropertiesKHR
    override func writeCompactedSize(of structure: AccelerationStructure, to toBuffer: Buffer, offset: Int) {
        let structure = resourceMap[structure]! as! MTLAccelerationStructure
        let buffer = resourceMap[toBuffer]!
        encoder.writeCompactedSize(accelerationStructure: structure, buffer: buffer.buffer, offset: buffer.offset + offset)
    }

    override func copyAndCompact(sourceAccelerationStructure source: AccelerationStructure, destinationAccelerationStructure destination: AccelerationStructure) {
        destination.descriptor = source.descriptor
        let source = resourceMap[source]! as! MTLAccelerationStructure
        let destination = resourceMap[destination]! as! MTLAccelerationStructure
        encoder.copyAndCompact(sourceAccelerationStructure: source, destinationAccelerationStructure: destination)
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
