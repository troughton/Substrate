//
//  MetalResourceAllocator.swift
//  FrameGraph
//
//  Created by Thomas Roughton on 29/06/17.
//  Copyright © 2017 Team Llama. All rights reserved.
//

#if canImport(Metal)

import FrameGraphUtilities
import Metal

protocol MetalResourceAllocator {
    func cycleFrames()
}


protocol MetalTextureAllocator : MetalResourceAllocator {
    func collectTextureWithDescriptor(_ descriptor: MTLTextureDescriptor) -> (MTLTextureReference, [FenceDependency], ContextWaitEvent)
    func depositTexture(_ texture: MTLTextureReference, fences: [FenceDependency], waitEvent: ContextWaitEvent)
}

protocol MetalBufferAllocator : MetalResourceAllocator {
    func collectBufferWithLength(_ length: Int, options: MTLResourceOptions) -> (MTLBufferReference, [FenceDependency], ContextWaitEvent)
    func depositBuffer(_ buffer: MTLBufferReference, fences: [FenceDependency], waitEvent: ContextWaitEvent)
}


extension MTLResourceOptions {
    
    func matches(storageMode: MTLStorageMode, cpuCacheMode: MTLCPUCacheMode) -> Bool {
        var matches = true
        switch storageMode {
        #if os(macOS) || targetEnvironment(macCatalyst)
        case .managed:
            matches = self.contains(.storageModeManaged)
        #endif
        case .shared:
            matches = matches && self.contains(.storageModeShared)
        case .private:
            matches = matches && self.contains(.storageModePrivate)
        case .memoryless:
            #if os(macOS) || targetEnvironment(macCatalyst)
            matches = false
            #else
            matches = matches && self.contains(.storageModeMemoryless)
            #endif
        @unknown default:
            break
        }
        
        switch cpuCacheMode {
        case .writeCombined:
            matches = matches && self.contains(.cpuCacheModeWriteCombined)
        case .defaultCache:
            break // defaultCache is an empty OptionSet.
        @unknown default:
            break
        }
        
        return matches
    }
}

#endif // canImport(Metal)
