//
//  RenderBackend.swift
//  CGRA 402
//
//  Created by Thomas Roughton on 10/03/17.
//  Copyright © 2017 Thomas Roughton. All rights reserved.
//

import Foundation

#if canImport(Metal)
import Metal
#endif
#if canImport(Vulkan)
import Vulkan
#endif

@usableFromInline
protocol PipelineReflection : AnyObject {
    func bindingPath(argumentBuffer: ArgumentBuffer, argumentName: String, arrayIndex: Int) -> ResourceBindingPath?
    func bindingPath(argumentName: String, arrayIndex: Int, argumentBufferPath: ResourceBindingPath?) -> ResourceBindingPath?
    func bindingPath(pathInOriginalArgumentBuffer: ResourceBindingPath, newArgumentBufferPath: ResourceBindingPath) -> ResourceBindingPath
    func argumentReflection(at path: ResourceBindingPath) -> ArgumentReflection?
    func bindingIsActive(at path: ResourceBindingPath) -> Bool

    func argumentBufferEncoder(at path: ResourceBindingPath, currentEncoder: UnsafeRawPointer?) -> UnsafeRawPointer?
    
    var threadExecutionWidth: Int { get }
}

extension PipelineReflection {
    public func bindingIsActive(at path: ResourceBindingPath) -> Bool {
        return self.argumentReflection(at: path)?.isActive ?? false
    }
}

public enum RenderAPI {
#if canImport(Metal)
    case metal
#endif
#if canImport(Vulkan)
    case vulkan
#endif
}


public protocol RenderBackendProtocol : AnyObject {
    func backingResource(_ resource: Resource) -> Any?
    
    func sizeAndAlignment(for texture: TextureDescriptor) -> (size: Int, alignment: Int)
    func sizeAndAlignment(for buffer: BufferDescriptor) -> (size: Int, alignment: Int)
    
    func supportsPixelFormat(_ format: PixelFormat, usage: TextureUsage) -> Bool
    var hasUnifiedMemory : Bool { get }
    
    var renderDevice : Any { get }
    
    var api : RenderAPI { get }
}

@usableFromInline
protocol _RenderBackendProtocol : RenderBackendProtocol {
    func materialisePersistentTexture(_ texture: Texture) -> Bool
    func materialisePersistentBuffer(_ buffer: Buffer) -> Bool
    func materialiseHeap(_ heap: Heap) -> Bool
    @available(macOS 11.0, iOS 14.0, *)
    func materialiseAccelerationStructure(_ structure: AccelerationStructure) -> Bool
    
    func replaceBackingResource(for buffer: Buffer, with: Any?) -> Any?
    func replaceBackingResource(for texture: Texture, with: Any?) -> Any?
    func replaceBackingResource(for heap: Heap, with: Any?) -> Any?
    @available(macOS 11.0, iOS 14.0, *)
    func replaceBackingResource(for structure: AccelerationStructure, with: Any?) -> Any?
    
    func registerWindowTexture(texture: Texture, context: Any)
    func registerExternalResource(_ resource: Resource, backingResource: Any)
    
    func updateLabel(on resource: Resource)
    var requiresEmulatedInputAttachments : Bool { get }
    
    func bufferContents(for buffer: Buffer, range: Range<Int>) -> UnsafeMutableRawPointer
    func buffer(_ buffer: Buffer, didModifyRange range: Range<Int>)
    
    func copyTextureBytes(from texture: Texture, to bytes: UnsafeMutableRawPointer, bytesPerRow: Int, region: Region, mipmapLevel: Int)
    func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int)
    func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, slice: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int)
    
    func usedSize(for heap: Heap) -> Int
    func currentAllocatedSize(for heap: Heap) -> Int
    func maxAvailableSize(forAlignment alignment: Int, in heap: Heap) -> Int
    
    func updatePurgeableState(for resource: Resource, to: ResourcePurgeableState?) -> ResourcePurgeableState
    
    @available(macOS 11.0, iOS 14.0, *)
    func accelerationStructureSizes(for descriptor: AccelerationStructureDescriptor) -> AccelerationStructureSizes
    
    // Note: The pipeline reflection functions may return nil if reflection information could not be created for the pipeline.
    func renderPipelineReflection(descriptor: RenderPipelineDescriptor, renderTarget: RenderTargetDescriptor) -> PipelineReflection?
    func computePipelineReflection(descriptor: ComputePipelineDescriptor) -> PipelineReflection?
    
    func dispose(texture: Texture)
    func dispose(buffer: Buffer)
    func dispose(argumentBuffer: ArgumentBuffer)
    func dispose(argumentBufferArray: ArgumentBufferArray)
    func dispose(heap: Heap)
    
    @available(macOS 11.0, iOS 14.0, *)
    func dispose(accelerationStructure: AccelerationStructure)
    
    var pushConstantPath : ResourceBindingPath { get }
    func argumentBufferPath(at index: Int, stages: RenderStages) -> ResourceBindingPath
}

public struct RenderBackend {
    @usableFromInline static var _backend : _RenderBackendProtocol! = nil
    
    @inlinable
    public static var backend : RenderBackendProtocol {
        return _backend
    }

    @inlinable
    public static var api : RenderAPI {
        return _backend.api
    }
    
    public static func initialise(api: RenderAPI, applicationName: String, device: Any? = nil, libraryPath: String? = nil, enableValidation: Bool = true, enableShaderHotReloading: Bool = true) {
        switch api {
#if canImport(Metal)
        case .metal:
            _backend = MetalBackend(device: device as! MTLDevice?, libraryPath: libraryPath, enableValidation: enableValidation, enableShaderHotReloading: enableShaderHotReloading)
#endif
#if canImport(Vulkan)
        case .vulkan:
            let instance = VulkanInstance(applicationName: applicationName, applicationVersion: VulkanVersion(major: 0, minor: 0, patch: 1), engineName: "Substrate", engineVersion: VulkanVersion(major: 3, minor: 0, patch: 1))!
            _backend = VulkanBackend(instance: instance, shaderLibraryURL: URL(fileURLWithPath: libraryPath!))
#endif
        }
    }
    
    @inlinable
    public static var isInitialised: Bool {
        return _backend != nil
    }
    
    @inlinable
    public static func materialisePersistentTexture(_ texture: Texture) -> Bool {
        return _backend.materialisePersistentTexture(texture)
    }

    @inlinable
    public static func registerExternalResource(_ resource: Resource, backingResource: Any) {
        return _backend.registerExternalResource(resource, backingResource: backingResource)
    }
    
    @inlinable
    public static func registerWindowTexture(texture: Texture, context: Any) {
        return _backend.registerWindowTexture(texture: texture, context: context)
    }
    
    @inlinable
    static func updateLabel<R: ResourceProtocol>(on resource: R) {
        return _backend.updateLabel(on: Resource(resource))
    }
    
    @inlinable
    public static func materialisePersistentBuffer(_ buffer: Buffer) -> Bool {
        return _backend.materialisePersistentBuffer(buffer)
    }
    
    @inlinable
    public static func materialiseHeap(_ heap: Heap) -> Bool {
        return _backend.materialiseHeap(heap)
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    @inlinable
    public static func materialiseAccelerationStructure(_ structure: AccelerationStructure) -> Bool {
        return _backend.materialiseAccelerationStructure(structure)
    }
    
    static func replaceBackingResource(for buffer: Buffer, with: Any?) -> Any? {
        return _backend.replaceBackingResource(for: buffer, with: with)
    }
    
    static func replaceBackingResource(for texture: Texture, with: Any?) -> Any? {
        return _backend.replaceBackingResource(for: texture, with: with)
    }
    
    static func replaceBackingResource(for heap: Heap, with: Any?) -> Any? {
        return _backend.replaceBackingResource(for: heap, with: with)
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    static func replaceBackingResource(for accelerationStructure: AccelerationStructure, with: Any?) -> Any? {
        return _backend.replaceBackingResource(for: accelerationStructure, with: with)
    }
    
    @inlinable
    static func renderPipelineReflection(descriptor: RenderPipelineDescriptor, renderTarget: RenderTargetDescriptor) -> PipelineReflection? {
        return _backend.renderPipelineReflection(descriptor: descriptor, renderTarget: renderTarget)
    }
    
    @inlinable
    static func computePipelineReflection(descriptor: ComputePipelineDescriptor) -> PipelineReflection? {
        return _backend.computePipelineReflection(descriptor: descriptor)
    }
    
    @inlinable
    public static func dispose(texture: Texture) {
        return _backend.dispose(texture: texture)
    }
    
    @inlinable
    public static func dispose(buffer: Buffer) {
        return _backend.dispose(buffer: buffer)
    }
    
    @inlinable
    public static func dispose(argumentBuffer: ArgumentBuffer) {
        return _backend.dispose(argumentBuffer: argumentBuffer)
    }
    
    @inlinable
    public static func dispose(argumentBufferArray: ArgumentBufferArray) {
        return _backend.dispose(argumentBufferArray: argumentBufferArray)
    }
    
    @inlinable
    public static func dispose(heap: Heap) {
        return _backend.dispose(heap: heap)
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    @inlinable
    public static func dispose(accelerationStructure: AccelerationStructure) {
        return _backend.dispose(accelerationStructure: accelerationStructure)
    }
    
    @inlinable
    public static func backingResource<R : ResourceProtocol>(_ resource: R) -> Any? {
        return _backend.backingResource(Resource(resource))
    }
    
    @inlinable
    public static func supportsPixelFormat(_ pixelFormat: PixelFormat, usage: TextureUsage = .shaderRead) -> Bool {
        return _backend.supportsPixelFormat(pixelFormat, usage: usage)
    }
    
    @inlinable
    public static var isDepth24Stencil8PixelFormatSupported : Bool {
        return self.supportsPixelFormat(.depth24Unorm_stencil8, usage: .renderTarget)
    }
    
    @inlinable
    public static var hasUnifiedMemory : Bool {
        return _backend.hasUnifiedMemory
    }
    
    @inlinable
    static var requiresEmulatedInputAttachments : Bool {
        return _backend.requiresEmulatedInputAttachments
    }
    
    @inlinable
    public static func bufferContents(for buffer: Buffer, range: Range<Int>) -> UnsafeMutableRawPointer {
        return _backend.bufferContents(for: buffer, range: range)
    }
    
    @inlinable
    public static func buffer(_ buffer: Buffer, didModifyRange range: Range<Int>) {
        return _backend.buffer(buffer, didModifyRange: range)
    }

    @inlinable
    public static func copyTextureBytes(from texture: Texture, to bytes: UnsafeMutableRawPointer, bytesPerRow: Int, region: Region, mipmapLevel: Int) {
        return _backend.copyTextureBytes(from: texture, to: bytes, bytesPerRow: bytesPerRow, region: region, mipmapLevel: mipmapLevel)
    }
    
    @inlinable
    public static func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) {
        return _backend.replaceTextureRegion(texture: texture, region: region, mipmapLevel: mipmapLevel, withBytes: bytes, bytesPerRow: bytesPerRow)
    }

    @inlinable
    public static func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, slice: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int) {
        return _backend.replaceTextureRegion(texture: texture, region: region, mipmapLevel: mipmapLevel, slice: slice, withBytes: bytes, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerImage)
    }
    
    @inlinable
    static func updatePurgeableState(for resource: Resource, to: ResourcePurgeableState?) -> ResourcePurgeableState {
        return _backend.updatePurgeableState(for: resource, to: to)
    }
    
    @inlinable
    public static func sizeAndAlignment(for texture: TextureDescriptor) -> (size: Int, alignment: Int) {
        return _backend.sizeAndAlignment(for: texture)
    }
    
    @inlinable
    public static func sizeAndAlignment(for buffer: BufferDescriptor) -> (size: Int, alignment: Int) {
        return _backend.sizeAndAlignment(for: buffer)
    }
    
    @inlinable
    static func usedSize(for heap: Heap) -> Int {
        return _backend.usedSize(for: heap)
    }
    
    @inlinable
    static func currentAllocatedSize(for heap: Heap) -> Int {
        return _backend.currentAllocatedSize(for: heap)
    }
    
    @inlinable
    static func maxAvailableSize(forAlignment alignment: Int, in heap: Heap) -> Int {
        return _backend.maxAvailableSize(forAlignment: alignment, in: heap)
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    @inlinable
    static func accelerationStructureSizes(for descriptor: AccelerationStructureDescriptor) -> AccelerationStructureSizes {
        return _backend.accelerationStructureSizes(for: descriptor)
    }
    
    @inlinable
    public static var renderDevice : Any {
        return _backend.renderDevice
    }
    
    @inlinable
    public static var pushConstantPath : ResourceBindingPath {
        return _backend.pushConstantPath
    }
    
     /// There are eight binding slots for argument buffers; this maps from a binding index to the ResourceBindingPath that identifies that index in the backend.
    @inlinable
    public static func argumentBufferPath(at index: Int, stages: RenderStages) -> ResourceBindingPath {
        assert(index < 8)
        return _backend.argumentBufferPath(at: index, stages: stages)
    }
}

public enum FunctionType : UInt {
    case vertex
    case fragment
    case kernel
}

public enum FunctionConstantValue : Hashable {
    case int8(Int8)
    case int16(Int16)
    case int32(Int32)
    
    case uint8(UInt8)
    case uint16(UInt16)
    case uint32(UInt32)
    
    case bool(Bool)
    case float(Float)
}

public typealias FunctionConstantCodable = Encodable & Hashable

public protocol FunctionConstantEncodable : NoArgConstructable, Equatable {
    func encode(into constants: inout FunctionConstants)
}

public struct FunctionConstants : Hashable {
    public struct IndexedConstant : Hashable {
        public var index : Int
        public var value : FunctionConstantValue
        
        public init(index: Int, value: FunctionConstantValue) {
            self.index = index
            self.value = value
        }
    }
    
    public var indexedConstants : [IndexedConstant] = []
    public var namedConstants : [String : FunctionConstantValue] = [:]
    
    public init<T : FunctionConstantCodable>(_ constants: T) throws {
        let encoder = FunctionConstantEncoder()
        try constants.encode(to: encoder)
        self.namedConstants = encoder.constants
    }
    
    @inlinable
    public init<T : FunctionConstantEncodable>(_ constants: T) {
        self.init()
        constants.encode(into: &self)
    }
    
    @inlinable
    public init() {
        
    }
    
    // Indexed constants
    
    @inlinable
    public mutating func setConstant(_ constant: Int8, at index: Int) {
        self.indexedConstants.append(FunctionConstants.IndexedConstant(index: index, value: .int8(constant)))
    }
    
    @inlinable
    public mutating func setConstant(_ constant: Int16, at index: Int) {
        self.indexedConstants.append(FunctionConstants.IndexedConstant(index: index, value: .int16(constant)))
    }
    
    @inlinable
    public mutating func setConstant(_ constant: Int32, at index: Int) {
        self.indexedConstants.append(FunctionConstants.IndexedConstant(index: index, value: .int32(constant)))
    }
    
    @inlinable
    public mutating func setConstant(_ constant: UInt8, at index: Int) {
        self.indexedConstants.append(FunctionConstants.IndexedConstant(index: index, value: .uint8(constant)))
    }
    
    @inlinable
    public mutating func setConstant(_ constant: UInt16, at index: Int) {
        self.indexedConstants.append(FunctionConstants.IndexedConstant(index: index, value: .uint16(constant)))
    }
    
    @inlinable
    public mutating func setConstant(_ constant: UInt32, at index: Int) {
        self.indexedConstants.append(FunctionConstants.IndexedConstant(index: index, value: .uint32(constant)))
    }
    
    @inlinable
    public mutating func setConstant(_ constant: Float, at index: Int) {
        self.indexedConstants.append(FunctionConstants.IndexedConstant(index: index, value: .float(constant)))
    }
    
    @inlinable
    public mutating func setConstant(_ constant: Bool, at index: Int) {
        self.indexedConstants.append(FunctionConstants.IndexedConstant(index: index, value: .bool(constant)))
    }
    
    // Named constants
    
    @inlinable
    public mutating func setConstant(_ constant: Int8, for name: String) {
        self.namedConstants[name] = .int8(constant)
    }
    
    @inlinable
    public mutating func setConstant(_ constant: Int16, for name: String) {
        self.namedConstants[name] = .int16(constant)
    }
    
    @inlinable
    public mutating func setConstant(_ constant: Int32, for name: String) {
        self.namedConstants[name] = .int32(constant)
    }
    
    @inlinable
    public mutating func setConstant(_ constant: UInt8, for name: String) {
        self.namedConstants[name] = .uint8(constant)
    }
    
    @inlinable
    public mutating func setConstant(_ constant: UInt16, for name: String) {
        self.namedConstants[name] = .uint16(constant)
    }
    
    @inlinable
    public mutating func setConstant(_ constant: UInt32, for name: String) {
        self.namedConstants[name] = .uint32(constant)
    }
    
    @inlinable
    public mutating func setConstant(_ constant: Float, for name: String) {
        self.namedConstants[name] = .float(constant)
    }
    
    @inlinable
    public mutating func setConstant(_ constant: Bool, for name: String) {
        self.namedConstants[name] = .bool(constant)
    }
}

public enum VertexStepFunction : UInt {
    case constant
    
    case perVertex
    
    case perInstance
    
    case perPatch
    
    case perPatchControlPoint
}
