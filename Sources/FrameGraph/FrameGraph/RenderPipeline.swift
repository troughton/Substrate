//
//  RenderPipelineDescriptor.swift
//  SwiftFrameGraph
//
//  Created by Thomas Roughton on 7/04/17.
//
//

import Utilities

@_fixed_layout
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

public protocol RenderTargetIdentifier : RawRepresentable where RawValue == Int {
    static var count : Int { get }
}

extension RenderTargetIdentifier where Self : CaseIterable {
    public static var count : Int {
        return self.allCases.count
    }
}

public enum DisplayRenderTargetIndex : Int, CaseIterable, RenderTargetIdentifier {
    case display
}

@_fixed_layout
public struct RenderPipelineDescriptor<I : RenderTargetIdentifier> {
    @usableFromInline var _descriptor : _RenderPipelineDescriptor
    
    @inlinable
    public init() {
        self._descriptor = _RenderPipelineDescriptor(identifierType: I.self)
    }
    
    @inlinable
    public var label: String? {
        get {
            return self._descriptor.label
        }
        set {
            self._descriptor.label = newValue
        }
    }
    
    @inlinable
    public var vertexDescriptor : VertexDescriptor? {
        get {
            return self._descriptor.vertexDescriptor
        }
        set {
            self._descriptor.vertexDescriptor = newValue
        }
    }
    
    @inlinable
    public var vertexFunction : String? {
        get {
            return self._descriptor.vertexFunction
        }
        set {
            self._descriptor.vertexFunction = newValue
        }
    }
    
    @inlinable
    public var fragmentFunction : String? {
        get {
            return self._descriptor.fragmentFunction
        }
        set {
            self._descriptor.fragmentFunction = newValue
        }
    }
    
    /* Rasterization and visibility state */
    @inlinable
    public var sampleCount : Int {
        get {
            return self._descriptor.sampleCount
        }
        set {
            self._descriptor.sampleCount = newValue
        }
    }
    
    @inlinable
    public var isAlphaToCoverageEnabled: Bool {
        get {
            return self._descriptor.isAlphaToCoverageEnabled
        }
        set {
            self._descriptor.isAlphaToCoverageEnabled = newValue
        }
    }
    
    @inlinable
    public var isAlphaToOneEnabled: Bool {
        get {
            return self._descriptor.isAlphaToOneEnabled
        }
        set {
            self._descriptor.isAlphaToOneEnabled = newValue
        }
    }
    
    @inlinable
    public var isRasterizationEnabled: Bool {
        get {
            return self._descriptor.isRasterizationEnabled
        }
        set {
            self._descriptor.isRasterizationEnabled = newValue
        }
    }
    
    @inlinable
    public mutating func setFunctionConstants<FC : FunctionConstants>(_ functionConstants: FC) {
        self._descriptor.functionConstants = AnyFunctionConstants(functionConstants)
    }
    
    @inlinable
    public subscript(blendStateFor attachment: I) -> BlendDescriptor? {
        get {
            return self._descriptor.blendStates[attachment.rawValue]
        }
        set {
            self._descriptor.blendStates[attachment.rawValue] = newValue
        }
    }
    
    @inlinable
    public subscript(writeMaskFor attachment: I) -> ColorWriteMask {
        get {
            return self._descriptor.writeMasks[attachment.rawValue]
        }
        set {
            self._descriptor.writeMasks[attachment.rawValue] = newValue
        }
    }
}

@_fixed_layout
public struct _RenderPipelineDescriptor : Hashable {
    public init<I : RenderTargetIdentifier>(identifierType: I.Type) {
        self.blendStates = [BlendDescriptor?](repeating: nil, count: I.count)
        self.writeMasks = [ColorWriteMask](repeating: .all, count: I.count)
    }
    
    public var label: String? = nil
    
    public var vertexDescriptor : VertexDescriptor? = nil
    
    public var vertexFunction: String? = nil
    public var fragmentFunction: String? = nil
    
    /* Rasterization and visibility state */
    public var sampleCount: Int = 1
    public var isAlphaToCoverageEnabled: Bool = false
    public var isAlphaToOneEnabled: Bool = false
    public var isRasterizationEnabled: Bool = true
    
    // Color attachment names to blend descriptors
    public var blendStates : [BlendDescriptor?]
    public var writeMasks : [ColorWriteMask]
    public var functionConstants : AnyFunctionConstants? = nil
    
    // Hash computation.
    // Hashes don't need to be unique, so let's go for a simple function
    // and rely on == for the proper check.
    @inlinable
    public var hashValue : Int {
        var result = 134
        result = 37 &* result &+ self.vertexFunction.hashValue
        result = 37 &* result &+ self.fragmentFunction.hashValue
        result = 37 &* result &+ self.label.hashValue
        return result
    }
}

@_fixed_layout
public struct ComputePipelineDescriptor : Hashable {
    public var function : String
    public var _functionConstants : AnyFunctionConstants? = nil
    
    public init(function: String) {
        self.function = function
    }
    
    @inlinable
    public mutating func setFunctionConstants<FC : FunctionConstants>(_ functionConstants: FC) {
        self._functionConstants = AnyFunctionConstants(functionConstants)
    }
}
