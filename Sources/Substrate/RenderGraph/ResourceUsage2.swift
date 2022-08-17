//
//  File.swift
//  
//
//  Created by Thomas Roughton on 4/07/22.
//

import Foundation

public struct TextureSubresourceRange {
    public var mipLevels: Range<Int>
    public var slices: Range<Int>
    public var depthPlanes: Range<Int>
    
    public init(mipLevels: Range<Int>, slices: Range<Int>, depthPlanes: Range<Int>) {
        self.mipLevels = mipLevels
        self.slices = slices
        self.depthPlanes = depthPlanes
    }
    
    public init(mipLevel: Int, slice: Int, depthPlane: Int) {
        self.mipLevels = mipLevel..<(mipLevel + 1)
        self.slices = slice..<(slice + 1)
        self.depthPlanes = depthPlane..<(depthPlane + 1)
    }
}

public struct ExplicitResourceUsage {
    public enum Subresource {
        case wholeResource
        case bufferRange(Range<Int>)
        case textureSlices(TextureSubresourceRange)
    }
    
    public var resource: Resource
    public var access: ResourceAccessFlags
    public var subresources: [Subresource]
    
    public static func buffer(_ buffer: Buffer, access: BufferAccessFlags, byteRange: Range<Int>? = nil) -> ExplicitResourceUsage {
        return .init(resource: Resource(buffer), access: ResourceAccessFlags(access), subresources: byteRange.map { [.bufferRange($0)] } ?? [.wholeResource])
    }
    
    public static func texture(_ texture: Texture, access: TextureAccessFlags, subresources: [TextureSubresourceRange]? = nil) -> ExplicitResourceUsage {
        return .init(resource: Resource(texture), access: ResourceAccessFlags(access), subresources: subresources?.map { .textureSlices($0) } ?? [.wholeResource])
    }
    
    // MARK: -
    
    public static func read(_ buffer: Buffer, byteRange: Range<Int>? = nil) -> ExplicitResourceUsage {
        return .init(resource: Resource(buffer), access: .shaderRead, subresources: byteRange.map { [.bufferRange($0)] } ?? [.wholeResource])
    }
    
    public static func readWrite(_ buffer: Buffer, byteRange: Range<Int>? = nil) -> ExplicitResourceUsage {
        return .init(resource: Resource(buffer), access: .shaderReadWrite, subresources: byteRange.map { [.bufferRange($0)] } ?? [.wholeResource])
    }
    
    public static func write(_ buffer: Buffer, byteRange: Range<Int>? = nil) -> ExplicitResourceUsage {
        return .init(resource: Resource(buffer), access: .shaderWrite, subresources: byteRange.map { [.bufferRange($0)] } ?? [.wholeResource])
    }
    
    public static func read(_ texture: Texture, subresources: [TextureSubresourceRange]? = nil) -> ExplicitResourceUsage {
        return .init(resource: Resource(texture), access: .shaderRead, subresources: subresources?.map { .textureSlices($0) } ?? [.wholeResource])
    }
    
    public static func readWrite(_ texture: Texture, subresources: [TextureSubresourceRange]? = nil) -> ExplicitResourceUsage {
        return .init(resource: Resource(texture), access: .shaderReadWrite, subresources: subresources?.map { .textureSlices($0) } ?? [.wholeResource])
    }
    
    public static func write(_ texture: Texture, subresources: [TextureSubresourceRange]? = nil) -> ExplicitResourceUsage {
        return .init(resource: Resource(texture), access: .shaderWrite, subresources: subresources?.map { .textureSlices($0) } ?? [.wholeResource])
    }
    
    public static func inputAttachment(_ texture: Texture, subresources: [TextureSubresourceRange]? = nil) -> ExplicitResourceUsage {
        return .init(resource: Resource(texture), access: .inputAttachment, subresources: subresources?.map { .textureSlices($0) } ?? [.wholeResource])
    }
    
    // Render target usages can be inferred from load actions and render target descriptors.
    // We _do_ need to know whether render targets are written to or not.
}
