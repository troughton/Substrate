//
//  DepthStencilDescriptor.swift
//  InterdimensionalLlama
//
//  Created by Thomas Roughton on 7/04/17.
//
//


public struct StencilDescriptor : Hashable {
    
    public var stencilCompareFunction: CompareFunction = .always
    
    public var stencilFailureOperation: StencilOperation = .keep
    
    public var depthFailureOperation: StencilOperation = .keep
    
    public var depthStencilPassOperation: StencilOperation = .keep
    
    public var readMask: UInt32 = 0xFFFFFFFF
    
    public var writeMask: UInt32 = 0xFFFFFFFF
    
    public init() {
        
    }
}

public struct DepthStencilDescriptor : Hashable {
    public init() {
    }
    
    public var depthCompareFunction: CompareFunction = .always
    
    public var isDepthWriteEnabled: Bool = false
    
    public var frontFaceStencil = StencilDescriptor()
    
    public var backFaceStencil = StencilDescriptor()
}

