//
//  PipelineReflection.swift
//  RenderAPI
//
//  Created by Joseph Bennett on 20/12/17.
//

import SubstrateUtilities

/// A generic resource binding path.
/// Can be customised by the backends to any size-compatible POD type,
/// and then converted into a ResourceBindingPath for use of the RenderGraph.
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
    public var arrayLength : Int
    public var usageType : ResourceUsageType
    public var activeStages : RenderStages
    public var activeRange: ActiveResourceRange
    
    public init(type: ResourceType, bindingPath: ResourceBindingPath, arrayLength: Int, usageType: ResourceUsageType, activeStages: RenderStages, activeRange: ActiveResourceRange) {
        self.type = type
        self.bindingPath = bindingPath
        self.arrayLength = arrayLength
        self.usageType = usageType
        self.activeStages = activeStages
        self.activeRange = activeRange
    }
    
    public var isActive: Bool {
        return !self.activeStages.isEmpty
    }
}
