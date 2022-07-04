//
//  File.swift
//  
//
//  Created by Thomas Roughton on 4/07/22.
//

import Foundation

public struct TextureSubresource {
    public var mipLevel: Int
    public var slice: Int
    public var depthPlane: Int
}

public struct ExplicitResourceUsage {
    public var resource: Resource
    public var accessType: ResourceAccessType
    public var usageType: ResourceUsageType
    public var subresources: [SubresourceMask]
    
    public static func read(_ buffer: Buffer, byteRange: Range<Int>? = nil) -> ExplicitResourceUsage {
        
    }
    
    public static func readWrite(_ buffer: Buffer, byteRange: Range<Int>? = nil) -> ExplicitResourceUsage {
    }
    
    public static func write(_ buffer: Buffer, byteRange: Range<Int>? = nil) -> ExplicitResourceUsage {
        
    }
    
    public static func read(_ texture: Texture, subresources: [TextureSubresource]? = nil) -> ExplicitResourceUsage {
        
    }
    
    public static func readWrite(_ texture: Texture, subresources: [TextureSubresource]? = nil) -> ExplicitResourceUsage {
        
    }
    
    public static func write(_ texture: Texture, subresources: [TextureSubresource]? = nil) -> ExplicitResourceUsage {
        
    }
    
    public static func inputAttachment(_ texture: Texture, subresources: [TextureSubresource]? = nil) -> ExplicitResourceUsage {
        
    }
    
    public static func blitSource(_ texture: Texture, subresources: [TextureSubresource]? = nil) -> ExplicitResourceUsage {
        
    }
    
    public static func blitDestination(_ texture: Texture, subresources: [TextureSubresource]? = nil) -> ExplicitResourceUsage {
        
    }
    
    // Render target usages can be inferred from load actions and render target descriptors.
    // We _do_ need to know whether render targets are written to or not.
}
