//
//  DepthStencilDescriptor.swift
//  InterdimensionalLlama
//
//  Created by Thomas Roughton on 7/04/17.
//
//


public struct StencilDescriptor : Hashable {
    
    public var stencilCompareFunction: CompareFunction = .always
    
    /*! Stencil is tested first.  stencilFailureOperation declares how the stencil buffer is updated when the stencil test fails. */
    public var stencilFailureOperation: StencilOperation = .keep
    
    
    /*! If stencil passes, depth is tested next.  Declare what happens when the depth test fails. */
    public var depthFailureOperation: StencilOperation = .keep
    
    
    /*! If both the stencil and depth tests pass, declare how the stencil buffer is updated. */
    public var depthStencilPassOperation: StencilOperation = .keep
    
    public var readMask: UInt32 = 0xFFFFFFFF
    
    public var writeMask: UInt32 = 0xFFFFFFFF
    
    public init() {
        
    }
}

public struct DepthStencilDescriptor : Hashable {
    public init() {
    }
    
    /* Defaults to CompareFuncAlways, which effectively skips the depth test */
    public var depthCompareFunction: CompareFunction = .always
    
    /* Defaults to NO, so no depth writes are performed */
    public var isDepthWriteEnabled: Bool = false
    
    /* Separate stencil state for front and back state.  Both front and back can be made to track the same state by assigning the same StencilDescriptor to both. */
    public var frontFaceStencil = StencilDescriptor()
    
    public var backFaceStencil = StencilDescriptor()
}

