//
//  File.swift
//  
//
//  Created by Thomas Roughton on 4/07/22.
//

import Foundation
import SubstrateUtilities

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

public struct ResourceUsage {
    public enum Subresource {
        case wholeResource
        case bufferRange(Range<Int>)
        case textureSlices(TextureSubresourceRange)
    }
    
    public var resource: Resource
    public var subresources: [Subresource]
    public var type: ResourceUsageType
    public var stages: RenderStages // empty means the default for the pass.
    
    public static func buffer(_ buffer: Buffer, byteRange: Range<Int>? = nil, type: BufferUsage, stages: RenderStages = []) -> ResourceUsage {
        return .init(resource: Resource(buffer), subresources: byteRange.map { [.bufferRange($0)] } ?? [.wholeResource], type: ResourceUsageType(type), stages: stages)
    }
    
    public static func texture(_ texture: Texture, subresources: [TextureSubresourceRange]? = nil, type: TextureUsage, stages: RenderStages = []) -> ResourceUsage {
        return .init(resource: Resource(texture), subresources: subresources?.map { .textureSlices($0) } ?? [.wholeResource], type: ResourceUsageType(type), stages: stages)
    }
    
    // MARK: -
    
    public static func read(_ buffer: Buffer, byteRange: Range<Int>? = nil, stages: RenderStages = []) -> ResourceUsage {
        return .init(resource: Resource(buffer), subresources: byteRange.map { [.bufferRange($0)] } ?? [.wholeResource], type: .shaderRead, stages: stages)
    }
    
    public static func readWrite(_ buffer: Buffer, byteRange: Range<Int>? = nil, stages: RenderStages = []) -> ResourceUsage {
        return .init(resource: Resource(buffer), subresources: byteRange.map { [.bufferRange($0)] } ?? [.wholeResource], type: .shaderReadWrite, stages: stages)
    }
    
    public static func write(_ buffer: Buffer, byteRange: Range<Int>? = nil, stages: RenderStages = []) -> ResourceUsage {
        return .init(resource: Resource(buffer), subresources: byteRange.map { [.bufferRange($0)] } ?? [.wholeResource], type: .shaderWrite, stages: stages)
    }
    
    public static func read(_ texture: Texture, subresources: [TextureSubresourceRange]? = nil, stages: RenderStages = []) -> ResourceUsage {
        return .init(resource: Resource(texture), subresources: subresources?.map { .textureSlices($0) } ?? [.wholeResource], type: .shaderRead, stages: stages)
    }
    
    public static func readWrite(_ texture: Texture, subresources: [TextureSubresourceRange]? = nil, stages: RenderStages = []) -> ResourceUsage {
        return .init(resource: Resource(texture), subresources: subresources?.map { .textureSlices($0) } ?? [.wholeResource], type: .shaderReadWrite, stages: stages)
    }
    
    public static func write(_ texture: Texture, subresources: [TextureSubresourceRange]? = nil, stages: RenderStages = []) -> ResourceUsage {
        return .init(resource: Resource(texture), subresources: subresources?.map { .textureSlices($0) } ?? [.wholeResource], type: .shaderWrite, stages: stages)
    }
    
    public static func inputAttachment(_ texture: Texture, subresources: [TextureSubresourceRange]? = nil, stages: RenderStages = []) -> ResourceUsage {
        return .init(resource: Resource(texture), subresources: subresources?.map { .textureSlices($0) } ?? [.wholeResource], type: .inputAttachment, stages: stages)
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
                            for depthPlane in textureRange.depthPlanes {
                                let indexSlice = slice * texture.descriptor.depth + depthPlane
                                textureMask[slice: indexSlice, level: mipLevel, descriptor: texture.descriptor, allocator: allocator] = true
                            }
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
