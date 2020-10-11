//
//  TypedRenderPipelineDescriptor.swift
//  Substrate
//
//  Created by Thomas Roughton on 7/04/17.
//
//

import SubstrateUtilities

public struct BlendDescriptor : Hashable {
    public var sourceRGBBlendFactor: BlendFactor = .one

    public var destinationRGBBlendFactor: BlendFactor = .zero
    
    public var rgbBlendOperation: BlendOperation = .add
    
    public var sourceAlphaBlendFactor: BlendFactor = .one
    
    public var destinationAlphaBlendFactor: BlendFactor = .zero
    
    public var alphaBlendOperation: BlendOperation = .add
    
    public init() {
        
    }
}

public struct TypedRenderPipelineDescriptor<R : RenderPassReflection> {
    public var descriptor : RenderPipelineDescriptor
    
    public init(attachmentCount: Int) {
        self.descriptor = RenderPipelineDescriptor(attachmentCount: attachmentCount)
    }
    
    @inlinable
    public var label: String? {
        get {
            return self.descriptor.label
        }
        set {
            self.descriptor.label = newValue
        }
    }
    
    @inlinable
    public var vertexDescriptor : VertexDescriptor? {
        get {
            return self.descriptor.vertexDescriptor
        }
        set {
            self.descriptor.vertexDescriptor = newValue
        }
    }
    
    @inlinable
    public var vertexFunction: R.VertexFunction! {
        get {
            guard let function = self.descriptor.vertexFunction else {
                fatalError("No valid pipeline function set.")
            }
            return R.VertexFunction(rawValue: function)!
        }
        set {
            self.descriptor.vertexFunction = newValue?.rawValue
        }
    }
    
    public var fragmentFunction: R.FragmentFunction? {
        get {
            return self.descriptor.fragmentFunction.map { R.FragmentFunction(rawValue: $0)! }
        }
        set {
            self.descriptor.fragmentFunction = newValue?.rawValue
        }
    }
    
    // Rasterization and visibility state
    
    @inlinable
    public var isAlphaToCoverageEnabled: Bool {
        get {
            return self.descriptor.isAlphaToCoverageEnabled
        }
        set {
            self.descriptor.isAlphaToCoverageEnabled = newValue
        }
    }
    
    @inlinable
    public var isAlphaToOneEnabled: Bool {
        get {
            return self.descriptor.isAlphaToOneEnabled
        }
        set {
            self.descriptor.isAlphaToOneEnabled = newValue
        }
    }
    
    @inlinable
    public var isRasterizationEnabled: Bool {
        get {
            return self.descriptor.isRasterizationEnabled
        }
        set {
            self.descriptor.isRasterizationEnabled = newValue
        }
    }
    
    // Color attachment names to blend descriptors
    @inlinable
    public var blendStates : [BlendDescriptor?] {
        _read {
            yield self.descriptor.blendStates
        }
        _modify {
            yield &self.descriptor.blendStates
        }
    }
    
    @inlinable
    public var writeMasks : [ColorWriteMask] {
        _read {
            yield self.descriptor.writeMasks
        }
        _modify {
            yield &self.descriptor.writeMasks
        }
    }
    
    var constantsChanged = false
    
    public var constants : R.FunctionConstants = R.FunctionConstants() {
        didSet {
            if constants != oldValue {
                self.constantsChanged = true
            }
        }
    }
    
    public mutating func flushConstants() {
        if self.constantsChanged {
            self.descriptor.functionConstants = FunctionConstants(constants)
        }
        self.constantsChanged = false
    }
}

public struct RenderPipelineDescriptor : Hashable {
    public init(attachmentCount: Int) {
        self.blendStates = [BlendDescriptor?](repeating: nil, count: attachmentCount)
        self.writeMasks = [ColorWriteMask](repeating: .all, count: attachmentCount)
    }
    
    public var label: String? = nil
    
    public var vertexDescriptor : VertexDescriptor? = nil
    
    public var vertexFunction: String? = nil
    public var fragmentFunction: String? = nil
    
    /* Rasterization and visibility state */
    public var isAlphaToCoverageEnabled: Bool = false
    public var isAlphaToOneEnabled: Bool = false
    public var isRasterizationEnabled: Bool = true
    
    // Color attachment names to blend descriptors
    public var blendStates : [BlendDescriptor?]
    public var writeMasks : [ColorWriteMask]
    public var functionConstants : FunctionConstants? = nil
    
    @inlinable
    public mutating func setFunctionConstants<FC : FunctionConstantCodable>(_ functionConstants: FC) {
        self.functionConstants = try! FunctionConstants(functionConstants)
    }
    
    // Hash computation.
    // Hashes don't need to be unique, so let's go for a simple function
    // and rely on == for the proper check.
    @inlinable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.vertexFunction)
        hasher.combine(self.fragmentFunction)
        hasher.combine(self.label)
    }
}

public struct TypedComputePipelineDescriptor<R : RenderPassReflection> {
    public var descriptor : ComputePipelineDescriptor
    
    public init() {
        self.descriptor = ComputePipelineDescriptor()
    }
    
    public var function: R.ComputeFunction? {
        get {
            return self.descriptor.function.map { R.ComputeFunction(rawValue: $0)! }
        }
        set {
            self.descriptor.function = newValue?.rawValue
        }
    }
    
    var constantsChanged = false
    
    public var constants : R.FunctionConstants = R.FunctionConstants() {
        didSet {
            if constants != oldValue {
                self.constantsChanged = true
            }
        }
    }
    
    public mutating func flushConstants() {
        if self.constantsChanged {
            self.descriptor._functionConstants = FunctionConstants(constants)
        }
        self.constantsChanged = false
    }
}

public struct ComputePipelineDescriptor : Hashable {
    public var function : String! = nil
    public var _functionConstants : FunctionConstants? = nil
    
    @inlinable
    init() {
        
    }
    
    public init(function: String) {
        self.function = function
    }
    
    @inlinable
    public mutating func setFunctionConstants<FC : FunctionConstantCodable>(_ functionConstants: FC) {
        self._functionConstants = try! FunctionConstants(functionConstants)
    }
    
    @inlinable
    public mutating func setFunctionConstants(_ functionConstants: FunctionConstants) {
        self._functionConstants = functionConstants
    }
}
