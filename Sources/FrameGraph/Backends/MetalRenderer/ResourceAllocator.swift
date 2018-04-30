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
    func collectTextureWithDescriptor(_ descriptor: MTLTextureDescriptor) -> MTLTexture
    func depositTexture(_ texture: MTLTexture)
}

protocol BufferAllocator : ResourceAllocator {
    func collectBufferWithLength(_ length: Int, options: MTLResourceOptions) -> MTLBufferReference
    func depositBuffer(_ buffer: MTLBufferReference)
}


extension MTLResourceOptions {
    
    func matches(storageMode: MTLStorageMode, cpuCacheMode: MTLCPUCacheMode) -> Bool {
        var matches = true
        switch storageMode {
        case .managed:
            matches = matches && self.contains(.storageModeManaged)
        case .shared:
            matches = matches && self.contains(.storageModeShared)
        case .private:
            matches = matches && self.contains(.storageModePrivate)
        case .memoryless:
            fatalError("Memoryless resources aren't correctly handled yet.")
        }
        
        switch cpuCacheMode {
        case .defaultCache:
            break // defaultCache is an empty OptionSet.
        case .writeCombined:
            matches = matches && self.contains(.cpuCacheModeWriteCombined)
        }
        
        return matches
    }
}
