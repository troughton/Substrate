//
//  RenderPipelineDescriptor.swift
//  SwiftFrameGraph
//
//  Created by Thomas Roughton on 7/04/17.
//
//

import Utilities

public struct BlendDescriptor : Hashable {
    
    /*! Defaults to BlendFactorOne */
    public var sourceRGBBlendFactor: BlendFactor = .one
    
    
    /*! Defaults to BlendFactorZero */
    public var destinationRGBBlendFactor: BlendFactor = .zero
    
    
    /*! Defaults to BlendOperationAdd */
    public var rgbBlendOperation: BlendOperation = .add
    
    
    /*! Defaults to BlendFactorOne */
    public var sourceAlphaBlendFactor: BlendFactor = .one
    
    
    /*! Defaults to BlendFactorZero */
    public var destinationAlphaBlendFactor: BlendFactor = .zero
    
    
    /*! Defaults to BlendOperationAdd */
    public var alphaBlendOperation: BlendOperation = .add
    
    public init() {
        
    }
}

public protocol RenderTargetIdentifier : RawRepresentable where RawValue == Int {
    static var count : Int { get }
}

extension RenderTargetIdentifier where Self : CaseIterable {
    static var count : Int {
        return self.allCases.count
    }
}

public enum DisplayRenderTargetIndex : Int, CaseIterable, RenderTargetIdentifier {
    case display
    
    public static var count: Int {
        return DisplayRenderTargetIndex.allCases.count
    }
}

public struct RenderPipelineDescriptor : Hashable {
    public init<I : RenderTargetIdentifier>(identifier: I.Type) {
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
    
    public subscript<I : RenderTargetIdentifier>(blendStateFor attachment: I) -> BlendDescriptor? {
        get {
            return self.blendStates[attachment.rawValue]
        }
        set {
            self.blendStates[attachment.rawValue] = newValue
        }
    }
    
    public subscript<I : RenderTargetIdentifier>(writeMaskFor attachment: I) -> ColorWriteMask {
        get {
            return self.writeMasks[attachment.rawValue]
        }
        set {
            self.writeMasks[attachment.rawValue] = newValue
        }
    }
    
    // Hash computation.
    // Hashes don't need to be unique, so let's go for a simple function
    // and rely on == for the proper check.
    public var hashValue : Int {
        var result = 134
        result = 37 &* result &+ self.vertexFunction.hashValue
        result = 37 &* result &+ self.fragmentFunction.hashValue
        result = 37 &* result &+ self.label.hashValue
        return result
    }
}

public struct ComputePipelineDescriptor : Hashable {
    public var function : String
    public var functionConstants : AnyFunctionConstants? = nil
    
    public init(function: String) {
        self.function = function
    }
}
