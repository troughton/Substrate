//
//  Dependency.swift
//  
//
//  Created by Thomas Roughton on 27/03/20.
//

import Foundation

protocol Dependency {
    init(resource: Resource,
         producingUsage: ResourceUsage, producingEncoder: Int,
         consumingUsage: ResourceUsage, consumingEncoder: Int)
    init(signal: FenceDependency, wait: FenceDependency)
    
    var signal: FenceDependency { get }
    var wait: FenceDependency { get }
    
    func merged(with otherDependency: Self) -> Self
}

struct FenceDependency {
    var encoderIndex: Int
    var index: Int // The index of the dependency within the command stream
    var stages: RenderStages
}

// For fence tracking - support at most one dependency between each set of two render passes. Make the fence update as early as possible, and make the fence wait as late as possible.
struct CoarseDependency: Dependency {
    var signal : FenceDependency
    var wait : FenceDependency
    
    init(resource: Resource,
         producingUsage: ResourceUsage, producingEncoder: Int,
         consumingUsage: ResourceUsage, consumingEncoder: Int) {
        precondition(consumingEncoder > producingEncoder)
        self.signal = FenceDependency(encoderIndex: producingEncoder, index: producingUsage.commandRange.last!, stages: producingUsage.stages)
        self.wait = FenceDependency(encoderIndex: consumingEncoder, index: consumingUsage.commandRange.lowerBound, stages: consumingUsage.stages)
    }
    
    init(signal: FenceDependency, wait: FenceDependency) {
        self.signal = signal
        self.wait = wait
    }
    
    public func merged(with otherDependency: CoarseDependency) -> CoarseDependency {
        var result = self
        result.wait.index = min(result.wait.index, otherDependency.wait.index)
        result.wait.stages.formUnion(otherDependency.wait.stages)
        
        result.signal.index = max(result.signal.index, otherDependency.signal.index)
        result.signal.stages.formUnion(otherDependency.signal.stages)
        
        return result
    }
}

// For fence tracking - support at most one dependency between each set of two render passes. Make the fence update as early as possible, and make the fence wait as late as possible.
struct FineDependency: Dependency {
    var signal : FenceDependency
    var wait : FenceDependency
    
    var resources: [(Resource, producingUsage: ResourceUsage, consumingUsage: ResourceUsage)]
    
    init(resource: Resource,
         producingUsage: ResourceUsage, producingEncoder: Int, consumingUsage: ResourceUsage, consumingEncoder: Int) {
        precondition(consumingEncoder > producingEncoder)
        self.signal = FenceDependency(encoderIndex: producingEncoder, index: producingUsage.commandRange.last!, stages: producingUsage.stages)
        self.wait = FenceDependency(encoderIndex: consumingEncoder, index: consumingUsage.commandRange.lowerBound, stages: consumingUsage.stages)
        
        self.resources = [(resource, producingUsage, consumingUsage)]
    }
    
    init(signal: FenceDependency, wait: FenceDependency) {
        self.signal = signal
        self.wait = wait
        // Heap aliasing dependency with no associated resources.
        // TODO: check that this is correct once the Vulkan backend supports resource aliasing.
        self.resources = []
    
    }
    
    public func merged(with otherDependency: FineDependency) -> FineDependency {
        var result = self
        result.wait.index = min(result.wait.index, otherDependency.wait.index)
        result.wait.stages.formUnion(otherDependency.wait.stages)
        
        result.signal.index = max(result.signal.index, otherDependency.signal.index)
        result.signal.stages.formUnion(otherDependency.signal.stages)
        
        result.resources.append(contentsOf: otherDependency.resources)
        
        return result
    }
}
