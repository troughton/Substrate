//
//  DepthStencilDescriptor.swift
//  Substrate
//
//  Created by Thomas Roughton on 7/04/17.
//
//

/// `StencilDescriptor` describes the tests and operations to perform on a render target's stencil attachment, if present.
/// The stencil test is performed before the depth test.
public struct StencilDescriptor : Hashable {
    
    /// The comparison function for the stencil test. The result of this comparison against the value currently in the stencil buffer
    /// determines whether the stencil test succeeds or fails.
    /// The comparison is performed as `fragmentValue CompareFunction valueInBuffer`; for example, `fragmentValue lessThan valueInBuffer`.
    public var stencilCompareFunction: CompareFunction = .always
    
    /// The operation to perform on the stencil buffer when the stencil test fails.
    public var stencilFailureOperation: StencilOperation = .keep
    
    /// The operation to perform on the stencil buffer when the stencil test succeeds
    /// but the depth test (as described in the `DepthStencilDescriptor`) fails.
    public var depthFailureOperation: StencilOperation = .keep
    
    /// The operation to perform on the stencil buffer when both the stencil and depth tests
    /// succeed.
    public var depthStencilPassOperation: StencilOperation = .keep
    
    /// The binary read mask that the stencil buffer's value is ANDed with before evaluating the stencil test.
    public var readMask: UInt32 = 0xFFFFFFFF
    
    /// The binary write mask that determines the bits within each pixel's stencil value that are written to when writing to
    /// the stencil buffer.
    public var writeMask: UInt32 = 0xFFFFFFFF
    
    @inlinable
    public init(stencilComparison: CompareFunction = .always,
                onStencilFailure: StencilOperation = .keep,
                onDepthFailure: StencilOperation = .keep,
                onStencilDepthPass: StencilOperation = .keep,
                readMask: UInt32 = 0xFFFFFFFF,
                writeMask: UInt32 = 0xFFFFFFFF) {
        self.stencilCompareFunction = stencilComparison
        self.stencilFailureOperation = onStencilFailure
        self.depthFailureOperation = onDepthFailure
        self.depthStencilPassOperation = onStencilDepthPass
        self.readMask = readMask
        self.writeMask = writeMask
    }
}

/// `DepthStencilDescriptor` describes the tests and operations to perform on a render target's depth and stencil attachments, if present.
/// The stencil test is performed before the depth test.
public struct DepthStencilDescriptor : Hashable {
    
    /// The function used to test fragment depths against the values in the depth buffer. If the comparison function fails, the fragment shader may not
    /// be executed for the fragments which failed the test, and no writes will be performed to any attachments or read-write buffers for those pixels.
    /// The comparison is performed as `fragmentValue CompareFunction valueInBuffer`; for example, `fragmentValue lessThan valueInBuffer`.
    public var depthCompareFunction: CompareFunction = .always
    
    /// Whether depth values which pass the `depthCompareFunction` should be written to the depth buffer.
    public var isDepthWriteEnabled: Bool = false
    
    /// Whether fragments outside the frustum near or far planes should get clipped or clamped.
    public var depthClipMode: DepthClipMode = .clip
    
    /// The stencil state for pixels belonging to front-facing triangles. May be set to the same value as the `backFaceStencil`.
    public var frontFaceStencil = StencilDescriptor()
    
    /// The stencil state for pixels belonging to front-facing triangles. May be set to the same value as the `frontFaceStencil`.
    public var backFaceStencil = StencilDescriptor()
    
    @inlinable
    public init() {
        
    }
    
    @inlinable
    public init(depthComparison: CompareFunction = .always,
                depthWriteEnabled: Bool,
                depthClipMode: DepthClipMode = .clip,
                stencilDescriptor: StencilDescriptor = StencilDescriptor()) {
        self.depthCompareFunction = depthComparison
        self.isDepthWriteEnabled = depthWriteEnabled
        self.depthClipMode = depthClipMode
        self.frontFaceStencil = stencilDescriptor
        self.backFaceStencil = stencilDescriptor
    }
}

public final class DepthStencilState {
    public let descriptor: DepthStencilDescriptor
    public let state: OpaquePointer
    
    init(descriptor: DepthStencilDescriptor, state: OpaquePointer) {
        self.descriptor = descriptor
        self.state = state
    }
}
