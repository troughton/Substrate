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
    
    public init(resource: Resource, usage type: ResourceUsageType, subresources: [Subresource] = [.wholeResource], stages: RenderStages = []) {
        self.resource = resource
        self.subresources = subresources
        self.stages = stages
        self.type = type
    }

    // Render target usages can be inferred from load actions and render target descriptors.
    // We _do_ need to know whether render targets are written to or not.
}

extension ResourceUsage : CustomStringConvertible {
    public var description: String {
        return "ResourceUsage(resource: \(self.resource), subresources: \(self.subresources), type: \(self.type), stages: \(self.stages))"
    }
}

extension ResourceProtocol {
    public func `as`(_ type: ResourceUsageType, subresources: [ResourceUsage.Subresource] = [.wholeResource], stages: RenderStages = []) -> ResourceUsage {
        return ResourceUsage(resource: Resource(self), usage: type, subresources: subresources, stages: stages)
    }
}

extension ArgumentBuffer {
    public func `as`(_ type: ArgumentBufferUsage, stages: RenderStages = []) -> ResourceUsage {
        return ResourceUsage(resource: Resource(self), usage: ResourceUsageType(type), subresources: [.wholeResource], stages: stages)
    }
}

extension Buffer {
    public func `as`(_ type: BufferUsage, byteRange: Range<Int>? = nil, stages: RenderStages = []) -> ResourceUsage {
        return ResourceUsage(resource: Resource(self), usage: ResourceUsageType(type), subresources: byteRange.map { [.bufferRange($0)] } ?? [.wholeResource], stages: stages)
    }
}

extension Texture {
    public func `as`(_ type: TextureUsage, subresources: [TextureSubresourceRange]? = nil, stages: RenderStages = []) -> ResourceUsage {
        return ResourceUsage(resource: Resource(self), usage: ResourceUsageType(type), subresources: subresources?.map { .textureSlices($0) } ?? [.wholeResource], stages: stages)
    }
    
    public func `as`(_ type: TextureUsage, slice: Int, mipLevel: Int, stages: RenderStages = []) -> ResourceUsage {
        return ResourceUsage(resource: Resource(self), usage: ResourceUsageType(type), subresources: [.textureSlices(.init(slice: slice, mipLevel: mipLevel))], stages: stages)
    }
    
    public func `as`(_ type: TextureUsage, slices: Range<Int>, mipLevels: Range<Int>, stages: RenderStages = []) -> ResourceUsage {
        return ResourceUsage(resource: Resource(self), usage: ResourceUsageType(type), subresources: [.textureSlices(.init(slices: slices, mipLevels: mipLevels))], stages: stages)
    }
}

public struct RecordedResourceUsage {
    @usableFromInline var passIndex: Int
    @usableFromInline var usage: ResourceUsage
    @usableFromInline var activeRange: ActiveResourceRange
    
    init(passIndex: Int, usage: ResourceUsage, allocator: AllocatorType, defaultStages: RenderStages) {
        var usage = usage
        if usage.stages.isEmpty {
            usage.stages = defaultStages
        }
        
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
