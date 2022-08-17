//
//  File.swift
//  
//
//  Created by Thomas Roughton on 4/07/22.
//

import Foundation
import SubstrateUtilities

public struct TextureSubresourceRange {
    public var slices: Range<Int>
    public var mipLevels: Range<Int>
    
    public init(slices: Range<Int>, mipLevels: Range<Int>) {
        self.slices = slices
        self.mipLevels = mipLevels
    }
    
    public init(slice: Int, mipLevel: Int) {
        self.mipLevels = mipLevel..<(mipLevel + 1)
        self.slices = slice..<(slice + 1)
    }
}

public struct ResourceUsage {
    public enum Subresource {
        case wholeResource
        case bufferRange(Range<Int>)
        case textureSlices(TextureSubresourceRange)
    }
    
    public var resource: Resource
    public var type: ResourceUsageType
    public var stages: RenderStages // empty means the default for the pass.
    public var subresources: [Subresource]
    
    public init(resource: Resource, type: ResourceUsageType, stages: RenderStages = [], subresources: [Subresource] = [.wholeResource]) {
        self.resource = resource
        self.subresources = subresources
        self.stages = stages
        self.type = type
    }
    
    public init(_ buffer: Buffer, _ type: BufferUsage, stages: RenderStages = [], byteRange: Range<Int>? = nil) {
        self.init(resource: Resource(buffer), type: ResourceUsageType(type), stages: stages, subresources: byteRange.map { [.bufferRange($0)] } ?? [.wholeResource])
    }
    
    public init(_ texture: Texture, _ type: TextureUsage, stages: RenderStages = [], subresources: [TextureSubresourceRange]? = nil) {
        self.init(resource: Resource(texture), type: ResourceUsageType(type), stages: stages, subresources: subresources?.map { .textureSlices($0) } ?? [.wholeResource])
    }
    
    public init(_ texture: Texture, _ type: TextureUsage, stages: RenderStages = [], slice: Int, mipLevel: Int) {
        self.init(resource: Resource(texture), type: ResourceUsageType(type), stages: stages, subresources: [.textureSlices(.init(slice: slice, mipLevel: mipLevel))])
    }

    // Render target usages can be inferred from load actions and render target descriptors.
    // We _do_ need to know whether render targets are written to or not.
}

extension ResourceUsage : CustomStringConvertible {
    public var description: String {
        return "ResourceUsage(resource: \(self.resource), subresources: \(self.subresources), type: \(self.type), stages: \(self.stages))"
    }
}

public struct RecordedResourceUsage {
    @usableFromInline var passIndex: Int
    @usableFromInline var usage: ResourceUsage
    @usableFromInline var activeRange: ActiveResourceRange
    
    init(passIndex: Int, usage: ResourceUsage, allocator: AllocatorType) {
        self.passIndex = passIndex
        self.usage = usage
        
        var activeRange = ActiveResourceRange.inactive
        if usage.subresources.isEmpty {
            activeRange = .fullResource
        } else {
            var textureMask = SubresourceMask()
            for subresource in usage.subresources {
                switch subresource {
                case .wholeResource:
                    activeRange = .fullResource
                case .bufferRange(let range):
                    activeRange.formUnion(with: .buffer(range), resource: usage.resource, allocator: allocator)
                case .textureSlices(let textureRange):
                    guard let texture = Texture(usage.resource) else { break }
                    for mipLevel in textureRange.mipLevels {
                        for slice in textureRange.slices {
                            textureMask[slice: slice, level: mipLevel, descriptor: texture.descriptor, allocator: allocator] = true
                        }
                    }
                }
            }
            if usage.resource.type == .texture {
                activeRange.formUnion(with: .texture(textureMask), resource: usage.resource, allocator: allocator)
            }
        }
        
        self.activeRange = activeRange
    }
    
    @inlinable
    public var resource: Resource {
        return self.usage.resource
    }
    
    @inlinable
    public var type: ResourceUsageType {
        return self.usage.type
    }
    
    @inlinable
    public var gpuType: ResourceUsageType {
        return self.usage.type.subtracting(.cpuReadWrite)
    }
    
    @inlinable
    public var stages: RenderStages {
        return self.usage.stages
    }
}

extension RecordedResourceUsage : CustomStringConvertible {
    public var description: String {
        return "RecordedResourceUsage(passIndex: \(self.passIndex), usage: \(self.usage.description))"
    }
}
