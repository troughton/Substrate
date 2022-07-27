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
    public var subresources: [Subresource]
    public var access: ResourceAccessFlags
    public var stages: RenderStages // empty means the default for the pass.
    
    public static func buffer(_ buffer: Buffer, byteRange: Range<Int>? = nil, access: BufferAccessFlags, stages: RenderStages = []) -> ExplicitResourceUsage {
        return .init(resource: Resource(buffer), subresources: byteRange.map { [.bufferRange($0)] } ?? [.wholeResource], access: ResourceAccessFlags(access), stages: stages)
    }
    
    public static func texture(_ texture: Texture, subresources: [TextureSubresourceRange]? = nil, access: TextureAccessFlags, stages: RenderStages = []) -> ExplicitResourceUsage {
        return .init(resource: Resource(texture), subresources: subresources?.map { .textureSlices($0) } ?? [.wholeResource], access: ResourceAccessFlags(access), stages: stages)
    }
    
    // MARK: -
    
    public static func read(_ buffer: Buffer, byteRange: Range<Int>? = nil, stages: RenderStages = []) -> ExplicitResourceUsage {
        return .init(resource: Resource(buffer), subresources: byteRange.map { [.bufferRange($0)] } ?? [.wholeResource], access: .shaderRead, stages: stages)
    }
    
    public static func readWrite(_ buffer: Buffer, byteRange: Range<Int>? = nil, stages: RenderStages = []) -> ExplicitResourceUsage {
        return .init(resource: Resource(buffer), subresources: byteRange.map { [.bufferRange($0)] } ?? [.wholeResource], access: .shaderReadWrite, stages: stages)
    }
    
    public static func write(_ buffer: Buffer, byteRange: Range<Int>? = nil, stages: RenderStages = []) -> ExplicitResourceUsage {
        return .init(resource: Resource(buffer), subresources: byteRange.map { [.bufferRange($0)] } ?? [.wholeResource], access: .shaderWrite, stages: stages)
    }
    
    public static func read(_ texture: Texture, subresources: [TextureSubresourceRange]? = nil, stages: RenderStages = []) -> ExplicitResourceUsage {
        return .init(resource: Resource(texture), subresources: subresources?.map { .textureSlices($0) } ?? [.wholeResource], access: .shaderRead, stages: stages)
    }
    
    public static func readWrite(_ texture: Texture, subresources: [TextureSubresourceRange]? = nil, stages: RenderStages = []) -> ExplicitResourceUsage {
        return .init(resource: Resource(texture), subresources: subresources?.map { .textureSlices($0) } ?? [.wholeResource], access: .shaderReadWrite, stages: stages)
    }
    
    public static func write(_ texture: Texture, subresources: [TextureSubresourceRange]? = nil, stages: RenderStages = []) -> ExplicitResourceUsage {
        return .init(resource: Resource(texture), subresources: subresources?.map { .textureSlices($0) } ?? [.wholeResource], access: .shaderWrite, stages: stages)
    }
    
    public static func inputAttachment(_ texture: Texture, subresources: [TextureSubresourceRange]? = nil, stages: RenderStages = []) -> ExplicitResourceUsage {
        return .init(resource: Resource(texture), subresources: subresources?.map { .textureSlices($0) } ?? [.wholeResource], access: .inputAttachment, stages: stages)
    }
    
    // Render target usages can be inferred from load actions and render target descriptors.
    // We _do_ need to know whether render targets are written to or not.
}

public struct RecordedResourceUsage {
    var passIndex: Int
    var usage: ExplicitResourceUsage
}
