//
//  PipelineReflection.swift
//  RenderAPI
//
//  Created by Joseph Bennett on 20/12/17.
//

public enum ResourceUsageType {
    case read
    case write
    case readWrite

    // A render target that is only written to (e.g. a color attachment with blending disabled)
    case writeOnlyRenderTarget
    // A render target that is also read from, whether by blending or by depth/stencil operations
    case readWriteRenderTarget

    case sampler
    case inputAttachment
    case constantBuffer

    case blitSource
    case blitDestination
    case blitSynchronisation
    
    case vertexBuffer
    case indexBuffer
    case indirectBuffer
    
    // Present in an argument buffer, but not actually used until later on.
    case argumentBufferUnused

    public var isRenderTarget : Bool {
        return self == .writeOnlyRenderTarget || self == .readWriteRenderTarget
    }
}

/// A generic resource binding path.
/// Can be customised by the backends to any size-compatible POD type,
/// and then converted into a ResourceBindingPath for use of the FrameGraph.
public struct ResourceBindingPath : Hashable {
    public var value : UInt64
    
    public init(value: UInt64) {
        self.value = value
    }
    
    public static let `nil` = ResourceBindingPath(value: UInt64.max)
}

public struct ArgumentReflection {
    public let isActive : Bool
    public let type : ResourceType
    public let bindingPath : ResourceBindingPath
    public let usageType : ResourceUsageType
    public let stages : RenderStages
    
    public init(isActive: Bool, type: ResourceType, bindingPath: ResourceBindingPath, usageType: ResourceUsageType, stages: RenderStages) {
        self.isActive = isActive
        self.type = type
        self.bindingPath = bindingPath
        self.usageType = usageType
        self.stages = stages
    }
}
