//
//  ResourceAllocator.swift
//  FrameGraph
//
//  Created by Thomas Roughton on 29/06/17.
//  Copyright © 2017 Team Llama. All rights reserved.
//

import Utilities
import Metal

protocol ResourceAllocator {
    func cycleFrames()
}


protocol TextureAllocator : ResourceAllocator {
    func collectTextureWithDescriptor(_ descriptor: MTLTextureDescriptor) -> MTLTextureReference
    func depositTexture(_ texture: MTLTextureReference)
}

protocol BufferAllocator : ResourceAllocator {
    func collectBufferWithLength(_ length: Int, options: MTLResourceOptions) -> MTLBufferReference
    func depositBuffer(_ buffer: MTLBufferReference)
}


extension MTLResourceOptions {
    
    func matches(storageMode: MTLStorageMode, cpuCacheMode: MTLCPUCacheMode) -> Bool {
        var matches = true
        switch storageMode {
        #if os(macOS)
        case .managed:
            matches = false
        #endif
        case .shared:
            matches = matches && self.contains(.storageModeShared)
        case .private:
            matches = matches && self.contains(.storageModePrivate)
        case .memoryless:
            #if os(macOS)
            matches = false
            #else
            matches = matches && self.contains(.storageModeMemoryless)
            #endif
        }
        
        switch cpuCacheMode {
        case .writeCombined:
            matches = matches && self.contains(.cpuCacheModeWriteCombined)
        case .defaultCache:
            break // defaultCache is an empty OptionSet.
        }
        
        return matches
    }
}
