//
//  PipelineReflection.swift
//  RenderAPI
//
//  Created by Joseph Bennett on 20/12/17.
//

import FrameGraphUtilities

public enum ResourceUsageType {
    case read
    case write
    case readWrite

    /// A render target attachment that is unused.
    case unusedRenderTarget
    /// A render target that is only written to (e.g. a color attachment with blending disabled)
    case writeOnlyRenderTarget
    /// A render target that is also read from, whether by blending or by depth/stencil operations
    case readWriteRenderTarget
    /// A render target that is simultaneously used as an input attachment (including read or sample operations).
    case inputAttachmentRenderTarget

    case sampler
    case inputAttachment
    case constantBuffer

    case blitSource
    case blitDestination
    case blitSynchronisation
    case mipGeneration
    
    case vertexBuffer
    case indexBuffer
    case indirectBuffer
    
    // Present in an argument buffer, but not actually used until later on.
    case unusedArgumentBuffer

    // Used in a previous frame
    case previousFrame

    public var isRenderTarget : Bool {
        switch self {
        case .unusedRenderTarget, .writeOnlyRenderTarget, .readWriteRenderTarget, .inputAttachmentRenderTarget:
            return true
        default:
            return false
        }
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
    
    @inlinable
    public static func ==(lhs: ResourceBindingPath, rhs: ResourceBindingPath) -> Bool {
        return lhs.value == rhs.value
    }
}

extension ResourceBindingPath : CustomHashable {
    public var customHashValue : Int {
        return Int(truncatingIfNeeded: self.value &* 39)
    }
}

public struct ArgumentReflection {
    public var type : ResourceType
    public var bindingPath : ResourceBindingPath
    public var usageType : ResourceUsageType
    public var activeStages : RenderStages
    public var activeRange: ActiveResourceRange
    
    public init(type: ResourceType, bindingPath: ResourceBindingPath, usageType: ResourceUsageType, activeStages: RenderStages, activeRange: ActiveResourceRange) {
        self.type = type
        self.bindingPath = bindingPath
        self.usageType = usageType
        self.activeStages = activeStages
        self.activeRange = activeRange
    }
    
    public var isActive: Bool {
        return !self.activeStages.isEmpty
    }
}
