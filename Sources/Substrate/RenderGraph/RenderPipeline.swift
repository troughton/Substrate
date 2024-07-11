//
//  TypedRenderPipelineDescriptor.swift
//  Substrate
//
//  Created by Thomas Roughton on 7/04/17.
//
//

import SubstrateUtilities

public struct BlendDescriptor : Hashable, Sendable {
    public var sourceRGBBlendFactor: BlendFactor = .one

    public var destinationRGBBlendFactor: BlendFactor = .zero
    
    public var rgbBlendOperation: BlendOperation = .add
    
    public var sourceAlphaBlendFactor: BlendFactor = .one
    
    public var destinationAlphaBlendFactor: BlendFactor = .zero
    
    public var alphaBlendOperation: BlendOperation = .add
    
    public init(sourceRGBBlendFactor: BlendFactor = .one, destinationRGBBlendFactor: BlendFactor = .zero, rgbBlendOperation: BlendOperation = .add, sourceAlphaBlendFactor: BlendFactor = .one, destinationAlphaBlendFactor: BlendFactor = .zero, alphaBlendOperation: BlendOperation = .add) {
        self.sourceRGBBlendFactor = sourceRGBBlendFactor
        self.destinationRGBBlendFactor = destinationRGBBlendFactor
        self.rgbBlendOperation = rgbBlendOperation
        self.sourceAlphaBlendFactor = sourceAlphaBlendFactor
        self.destinationAlphaBlendFactor = destinationAlphaBlendFactor
        self.alphaBlendOperation = alphaBlendOperation
    }
}

public struct FunctionDescriptor : Hashable, ExpressibleByStringLiteral, Sendable {
    public var name : String = ""
    public var constants : FunctionConstants? = nil
    
    @inlinable
    init() {
        
    }
    
    @inlinable
    public init(functionName: String, constants: FunctionConstants? = nil) {
        self.name = functionName
        self.constants = constants
    }
    
    public init(stringLiteral value: String) {
        self.init(functionName: value)
    }
    
    @inlinable
    public mutating func setFunctionConstants<FC : FunctionConstantCodable>(_ functionConstants: FC) {
        self.constants = try! FunctionConstants(functionConstants)
    }
}

public struct TypedRenderPipelineDescriptor<R : RenderPassReflection> {
    public var descriptor : RenderPipelineDescriptor
    
    public init() {
        self.descriptor = RenderPipelineDescriptor()
    }
    
    public init(descriptor: RenderPipelineDescriptor) {
        self.descriptor = descriptor
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
            guard !self.descriptor.vertexFunction.name.isEmpty else {
                fatalError("No valid pipeline function set.")
            }
            return R.VertexFunction(rawValue: self.descriptor.vertexFunction.name)!
        }
        set {
            self.descriptor.vertexFunction.name = newValue?.rawValue ?? ""
        }
    }
    
    public var fragmentFunction: R.FragmentFunction? {
        get {
            return R.FragmentFunction(rawValue: self.descriptor.fragmentFunction.name)
        }
        set {
            self.descriptor.fragmentFunction.name = newValue?.rawValue ?? ""
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
    
    @inlinable
    public var fillMode: TriangleFillMode {
        get {
            return self.descriptor.fillMode
        }
        set {
            self.descriptor.fillMode = newValue
        }
    }
    
    // Color attachment names to blend descriptors
    @inlinable
    public var blendStates : ColorAttachmentArray<BlendDescriptor?> {
        _read {
            yield self.descriptor.blendStates
        }
        _modify {
            yield &self.descriptor.blendStates
        }
    }
    
    @inlinable
    public var writeMasks : ColorAttachmentArray<ColorWriteMask> {
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

extension TypedRenderPipelineDescriptor: Sendable where R.FunctionConstants: Sendable {}

public struct VertexRenderPipelineDescriptor: Hashable, Sendable {
    public var vertexDescriptor : VertexDescriptor? = nil
    
    public var vertexFunction: FunctionDescriptor = .init()
    
    public var functionConstants : FunctionConstants? {
        get {
            return self.vertexFunction.constants
        }
        set {
            self.vertexFunction.constants = newValue
        }
    }
}

public struct MeshRenderPipelineDescriptor: Hashable, Sendable {
    public init()  {
        
    }
    
    public var objectFunction: FunctionDescriptor = .init()
    public var meshFunction: FunctionDescriptor = .init()
    
    public var maxTotalThreadsPerObjectThreadgroup: Int = 0
    public var maxTotalThreadsPerMeshThreadgroup: Int = 0
    
    public var objectThreadgroupSizeIsMultipleOfThreadExecutionWidth: Bool = false
    public var meshThreadgroupSizeIsMultipleOfThreadExecutionWidth: Bool = false
    
    public var payloadMemoryLength: Int = 0
    
    public var maxTotalThreadgroupsPerMeshGrid: Int = 0
 
    public var functionConstants : FunctionConstants? {
        get {
            return self.meshFunction.constants ?? self.objectFunction.constants
        }
        set {
            self.meshFunction.constants = newValue
            self.objectFunction.constants = newValue
        }
    }
}

public struct RenderPipelineDescriptor: Hashable, Sendable {
    enum VertexProcessingDescriptor: Hashable, Sendable {
        case vertex(VertexRenderPipelineDescriptor)
        case mesh(MeshRenderPipelineDescriptor)
        
        var functionConstants : FunctionConstants? {
            get {
                switch self {
                case .vertex(let vertex):
                    return vertex.functionConstants
                case .mesh(let mesh):
                    return mesh.functionConstants
                }
            }
            set {
                switch self {
                case .vertex(var vertex):
                    vertex.functionConstants = newValue
                    self = .vertex(vertex)
                case .mesh(var mesh):
                    mesh.functionConstants = newValue
                    self = .mesh(mesh)
                }
            }
        }
        
        var vertexPipelineDescriptor: VertexRenderPipelineDescriptor {
            get {
                switch self {
                case .vertex(let vertex):
                    return vertex
                default:
                    return .init()
                }
            }
            set {
                self = .vertex(newValue)
            }
        }
        
        var meshPipelineDescriptor: MeshRenderPipelineDescriptor {
            get {
                switch self {
                case .mesh(let mesh):
                    return mesh
                default:
                    return .init()
                }
            }
            set {
                self = .mesh(newValue)
            }
        }
    }
    
    public init() {
        
    }
    
    public init(renderTargets: RenderTargetsDescriptor) {
        self.init()
        self.setPixelFormatsAndSampleCount(from: renderTargets)
    }
    
    public var label: String? = nil
    
    var _vertexProcessingDescriptor: VertexProcessingDescriptor = .vertex(.init())
    
    public var vertexFunction: FunctionDescriptor {
        get {
            self._vertexProcessingDescriptor.vertexPipelineDescriptor.vertexFunction
        }
        set {
            self._vertexProcessingDescriptor.vertexPipelineDescriptor.vertexFunction = newValue
        }
    }
    
    public var vertexDescriptor: VertexDescriptor? {
        get {
            self._vertexProcessingDescriptor.vertexPipelineDescriptor.vertexDescriptor
        }
        set {
            self._vertexProcessingDescriptor.vertexPipelineDescriptor.vertexDescriptor = newValue
        }
    }
    
    public var meshPipeline: MeshRenderPipelineDescriptor {
        get {
            self._vertexProcessingDescriptor.meshPipelineDescriptor
        }
        set {
            self._vertexProcessingDescriptor.meshPipelineDescriptor = newValue
        }
    }
    
    public var fragmentFunction: FunctionDescriptor = .init()
    
    /* Rasterization and visibility state */
    public var isAlphaToCoverageEnabled: Bool = false
    public var isAlphaToOneEnabled: Bool = false
    public var isRasterizationEnabled: Bool = true
    
    public var fillMode: TriangleFillMode = .fill
    
    public var colorAttachmentFormats : ColorAttachmentArray<PixelFormat> = .init(repeating: .invalid)
    public var depthAttachmentFormat : PixelFormat = .invalid
    public var stencilAttachmentFormat : PixelFormat = .invalid
    
    public var rasterSampleCount : Int = 1
    
    public var blendStates : ColorAttachmentArray<BlendDescriptor?> = .init(repeating: nil)
    public var writeMasks : ColorAttachmentArray<ColorWriteMask> = .init(repeating: .all)
    public var functionConstants : FunctionConstants? {
        get {
            return self.fragmentFunction.constants ?? self._vertexProcessingDescriptor.functionConstants
        }
        set {
            self._vertexProcessingDescriptor.functionConstants = newValue
            self.fragmentFunction.constants = newValue
        }
    }
    
    @inlinable
    public mutating func setFunctionConstants<FC : FunctionConstantEncodable>(_ functionConstants: FC) {
        self.functionConstants = FunctionConstants(functionConstants)
    }
    
    @_disfavoredOverload
    @available(*, deprecated)
    @inlinable
    public mutating func setFunctionConstants<FC : FunctionConstantCodable>(_ functionConstants: FC) throws {
        self.functionConstants = try FunctionConstants(functionConstants)
    }
    
    @inlinable
    public mutating func setPixelFormatsAndSampleCount(from descriptor: RenderTargetsDescriptor) {
        self.colorAttachmentFormats = .init(descriptor.colorAttachments.lazy.map { $0?.texture.descriptor.pixelFormat ?? .invalid })
        self.depthAttachmentFormat = descriptor.depthAttachment?.texture.descriptor.pixelFormat ?? .invalid
        self.stencilAttachmentFormat = descriptor.stencilAttachment?.texture.descriptor.pixelFormat ?? .invalid
        
        var sampleCount = 0
        if let depthSampleCount = descriptor.depthAttachment?.texture.descriptor.sampleCount {
            sampleCount = depthSampleCount
        }
        if let stencilSampleCount = descriptor.stencilAttachment?.texture.descriptor.sampleCount {
            assert(sampleCount == 0 || sampleCount == stencilSampleCount)
            sampleCount = stencilSampleCount
        }
        
        for i in 0..<descriptor.colorAttachments.count {
            if let attachmentSampleCount = descriptor.colorAttachments[i]?.texture.descriptor.sampleCount {
                assert(sampleCount == 0 || sampleCount == attachmentSampleCount)
                sampleCount = attachmentSampleCount
            }
        }
        
        self.rasterSampleCount = sampleCount
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

public class PipelineState: Hashable, @unchecked Sendable {
    var state: OpaquePointer
    
    init(state: OpaquePointer) {
        self.state = state
    }
    
    init(state: AnyObject & Sendable) {
        self.state = OpaquePointer(Unmanaged.passUnretained(state).toOpaque())
    }
    
    func argumentBufferDescriptor(at path: ResourceBindingPath) -> ArgumentBufferDescriptor? {
        preconditionFailure()
    }
    
    public static func ==(lhs: PipelineState, rhs: PipelineState) -> Bool {
        return lhs === rhs
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

public class RenderPipelineState: PipelineState, @unchecked Sendable {
    public let descriptor: RenderPipelineDescriptor
    
    private let argumentBufferDescriptors: [ResourceBindingPath: ArgumentBufferDescriptor]
    
    init(descriptor: RenderPipelineDescriptor, state: OpaquePointer, argumentBufferDescriptors: [ResourceBindingPath: ArgumentBufferDescriptor]) {
        self.descriptor = descriptor
        self.argumentBufferDescriptors = argumentBufferDescriptors
        super.init(state: state)
    }
    
    public override func argumentBufferDescriptor(at path: ResourceBindingPath) -> ArgumentBufferDescriptor? {
        return self.argumentBufferDescriptors[path]
    }
}

public struct TypedComputePipelineDescriptor<R : RenderPassReflection> {
    public var descriptor : ComputePipelineDescriptor
    
    public init() {
        self.descriptor = ComputePipelineDescriptor()
    }
    
    @inlinable
    public init(descriptor: ComputePipelineDescriptor) {
        self.descriptor = descriptor
    }
    
    public var function: R.ComputeFunction? {
        get {
            return R.ComputeFunction(rawValue: self.descriptor.function.name)
        }
        set {
            self.descriptor.function.name = newValue?.rawValue ?? ""
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

extension TypedComputePipelineDescriptor: Sendable where R.FunctionConstants: Sendable {}

public struct ComputePipelineDescriptor : Hashable, Sendable {
    public var function = FunctionDescriptor()
    
    public var functionName : String {
        get {
            return self.function.name
        }
        set {
            self.function.name = newValue
        }
    }
    
    public var functionConstants : FunctionConstants? {
        get {
            return self.function.constants
        }
        set {
            self.function.constants = newValue
        }
    }
    
    public var linkedFunctions: [FunctionDescriptor] = []
    public var threadgroupSizeIsMultipleOfThreadExecutionWidth = false
    
    @inlinable
    public init() {
        
    }
    
    @inlinable
    public init(function: String) {
        self.function = .init(functionName: function)
    }
    
    @inlinable
    public init(function: FunctionDescriptor) {
        self.function = function
    }
    
    @inlinable
    public mutating func setFunctionConstants<FC : FunctionConstantCodable>(_ functionConstants: FC) {
        self.functionConstants = try! FunctionConstants(functionConstants)
    }
    
    @inlinable
    public mutating func setFunctionConstants(_ functionConstants: FunctionConstants) {
        self.functionConstants = functionConstants
    }
}

public class ComputePipelineState: PipelineState {
    public let descriptor: ComputePipelineDescriptor
    private let argumentBufferDescriptors: [ResourceBindingPath: ArgumentBufferDescriptor]
    let threadExecutionWidth: Int
    
    init(descriptor: ComputePipelineDescriptor, state: OpaquePointer, argumentBufferDescriptors: [ResourceBindingPath: ArgumentBufferDescriptor], threadExecutionWidth: Int) {
        self.descriptor = descriptor
        self.argumentBufferDescriptors = argumentBufferDescriptors
        self.threadExecutionWidth = threadExecutionWidth
        super.init(state: state)
    }
    
    public override func argumentBufferDescriptor(at path: ResourceBindingPath) -> ArgumentBufferDescriptor? {
        return self.argumentBufferDescriptors[path]
    }
}
