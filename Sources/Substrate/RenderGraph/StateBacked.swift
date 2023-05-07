//
//  StateBacked.swift
//  Substrate
//
//  Created by Thomas Roughton on 31/07/22.
//

import Foundation

public protocol StateDescriptor {
    associatedtype State
    
    init()
    init(describing state: State)
    func makeState() async -> State
}

@propertyWrapper
public struct StateBacked<Descriptor: StateDescriptor> {
    public var wrappedValue: Descriptor {
        didSet {
            self._state = nil
        }
    }
    @usableFromInline var _state: Descriptor.State?
    
    @inlinable
    public init(wrappedValue: Descriptor) {
        self.wrappedValue = wrappedValue
    }
    
    @inlinable
    public var state: Descriptor.State {
        mutating get async {
            if let _state = self._state {
                return _state
            }
            self._state = await self.wrappedValue.makeState()
            return self._state!
        }
    }
    
    @inlinable
    public mutating func setState(_ state: Descriptor.State) {
        self.wrappedValue = .init(describing: state)
        self._state = state
    }
    
    @inlinable
    public var projectedValue: StateBacked<Descriptor> {
        get {
            return self
        }
        set {
            self = newValue
        }
    }
}

extension SamplerDescriptor: StateDescriptor {
    public typealias State = SamplerState
    
    public init(describing state: SamplerState) {
        self = state.descriptor
    }
    
    public func makeState() async -> SamplerState {
        return await RenderBackend._backend.samplerState(for: self)
    }
}

extension RenderPipelineDescriptor: StateDescriptor {
    public typealias State = RenderPipelineState
    
    public init(describing state: RenderPipelineState) {
        self = state.descriptor
    }
    
    public func makeState() async -> RenderPipelineState {
        return await RenderBackend._backend.renderPipelineState(for: self)
    }
}

extension TypedRenderPipelineDescriptor: StateDescriptor {
    public typealias State = RenderPipelineState
    
    public init(describing state: RenderPipelineState) {
        self.init(descriptor: state.descriptor)
    }
    
    public func makeState() async -> RenderPipelineState {
        var descriptor = self.descriptor
        if self.constantsChanged {
            descriptor.functionConstants = FunctionConstants(self.constants)
        }
        return await descriptor.makeState()
    }
}

extension ComputePipelineDescriptor: StateDescriptor {
    public typealias State = ComputePipelineState
    
    public init(describing state: ComputePipelineState) {
        self = state.descriptor
    }
    
    public func makeState() async -> ComputePipelineState {
        return await RenderBackend._backend.computePipelineState(for: self)
    }
}

extension TypedComputePipelineDescriptor: StateDescriptor {
    public typealias State = ComputePipelineState
    
    public init(describing state: ComputePipelineState) {
        self.init(descriptor: state.descriptor)
    }
    
    public func makeState() async -> ComputePipelineState {
        var descriptor = self.descriptor
        if self.constantsChanged {
            descriptor.functionConstants = FunctionConstants(self.constants)
        }
        return await descriptor.makeState()
    }
}

extension DepthStencilDescriptor: StateDescriptor {
    public typealias State = DepthStencilState
    
    public init(describing state: DepthStencilState) {
        self = state.descriptor
    }
    
    public func makeState() async -> DepthStencilState {
        return await RenderBackend._backend.depthStencilState(for: self)
    }
}
