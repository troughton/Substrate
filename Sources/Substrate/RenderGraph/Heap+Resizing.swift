//
//  Heap+Resizing.swift
//  Substrate
//
//  Created by Thomas Roughton on 3/05/21.
//

import Foundation
import SubstrateUtilities

extension Heap {
    public func resize(_ newSize: Int) async -> Bool {
        var newDescriptor = self.descriptor
        newDescriptor.size = newSize
        
        guard let newHeap = Heap(descriptor: newDescriptor) else {
            return false
        }
        
        let purgeableState = self.updatePurgeableState(to: .nonDiscardable)
        
        var newChildResources = [Resource: Resource]()
        for resource in self.childResources {
            if let oldBuffer = Buffer(resource) {
                let newBuffer = Buffer(descriptor: oldBuffer.descriptor, heap: newHeap, flags: .persistent)!
                
                if purgeableState != .discarded, oldBuffer.descriptor.usageHint.contains(.blitSource), newBuffer.descriptor.usageHint.contains(.blitDestination) {
                    await GPUResourceUploader.runBlitPass(using: [
                        oldBuffer.as(.blitSource),
                        newBuffer.as(.blitDestination)
                    ]) { bce in
                        bce.copy(from: oldBuffer, sourceOffset: 0, to: newBuffer, destinationOffset: 0, size: oldBuffer.length)
                    }
                }
                
                newChildResources[resource] = Resource(newBuffer)
            } else if let oldTexture = Texture(resource) {
                let newTexture = Texture(descriptor: oldTexture.descriptor, heap: newHeap, flags: .persistent)!
                
                if purgeableState != .discarded, oldTexture.descriptor.usageHint.contains(.blitSource), newTexture.descriptor.usageHint.contains(.blitDestination) {
                    await GPUResourceUploader.runBlitPass(using: [
                        oldTexture.as(.blitSource),
                        newTexture.as(.blitDestination)
                    ]) { bce in
                        for slice in 0..<oldTexture.descriptor.depth * oldTexture.descriptor.arrayLength {
                            for level in 0..<oldTexture.descriptor.mipmapLevelCount {
                                bce.copy(from: oldTexture, sourceSlice: slice, sourceLevel: level, sourceOrigin: Origin(), sourceSize: oldTexture.size, to: newTexture, destinationSlice: slice, destinationLevel: level, destinationOrigin: Origin())
                            }
                        }
                    }
                }
                
                newChildResources[resource] = Resource(newTexture)
            } else {
                fatalError()
            }
        }
        
        newHeap.updatePurgeableState(to: purgeableState)
        
        let newHeapResource = RenderBackend.replaceBackingResource(for: newHeap, with: nil)
        _ = RenderBackend.replaceBackingResource(for: self, with: newHeapResource)
        newHeap.dispose()
        
        self.descriptor = newDescriptor
        
        for (resource, tempResource) in newChildResources {
            let newBackingResource = RenderBackend.replaceBackingResource(for: tempResource, with: nil)
            _ = RenderBackend.replaceBackingResource(for: resource, with: newBackingResource)
            tempResource.dispose()
        }
        
        return true
    }
}
