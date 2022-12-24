//
//  Texture.swift
//  
//
//  Created by Thomas Roughton on 2/07/21.
//

import SubstrateUtilities


public struct Texture : ResourceProtocol {
    public struct TextureViewDescriptor {
        public var pixelFormat: PixelFormat
        public var textureType: TextureType
        public var levels: Range<Int>
        public var slices: Range<Int>
        
            public init(pixelFormat: PixelFormat, textureType: TextureType, levels: Range<Int> = -1..<0, slices: Range<Int> = -1..<0) {
            self.pixelFormat = pixelFormat
            self.textureType = textureType
            self.levels = levels
            self.slices = slices
        }
    }

    @usableFromInline let _handle : UnsafeRawPointer
    @inlinable public var handle : Handle { return UInt64(UInt(bitPattern: _handle)) }
    
    public init(handle: Handle) {
        assert(Resource(handle: handle).type == .texture)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
    }
    
    @available(*, deprecated, renamed: "init(descriptor:renderGraph:flags:)")
    public init(descriptor: TextureDescriptor, frameGraph: RenderGraph?, flags: ResourceFlags = []) {
        self.init(descriptor: descriptor, renderGraph: frameGraph, flags: flags)
    }
    
    public init(descriptor: TextureDescriptor, renderGraph: RenderGraph? = nil, flags: ResourceFlags = []) {
        precondition((1...16384).contains(descriptor.width) && (1...16384).contains(descriptor.height) && (1...16384).contains(descriptor.depth), "Invalid size for descriptor \(descriptor); all dimensions must be in the range 1...16384")
        
        if flags.contains(.persistent) || flags.contains(.historyBuffer) {
            self = PersistentTextureRegistry.instance.allocate(descriptor: descriptor, heap: nil, flags: flags)
            
            assert(!descriptor.usageHint.isEmpty, "Persistent resources must explicitly specify their usage.")
            let didAllocate = RenderBackend.materialisePersistentResource(self)
            assert(didAllocate, "Allocation failed for persistent texture \(self)")
            if !didAllocate { self.dispose() }
        } else {
            precondition(descriptor.storageMode != .private || RenderGraph.activeRenderGraph == nil, "GPU-private transient resources cannot be created during render graph execution. Instead, create this resource in an init() method and pass in the render graph to use.")
            guard let renderGraph = renderGraph ?? RenderGraph.activeRenderGraph else {
                fatalError("The RenderGraph must be specified for transient resources created outside of a render pass' execute() method.")
            }
            precondition(renderGraph.transientRegistryIndex >= 0, "Transient resources are not supported on the RenderGraph \(renderGraph)")
            self = TransientTextureRegistry.instances[renderGraph.transientRegistryIndex].allocate(descriptor: descriptor, flags: flags)
            
            if descriptor.storageMode != .private {
                renderGraph.context.transientRegistry!.allocateBufferIfNeeded(self, forceGPUPrivate: false)
            }
        }
    }
    
    public static func _createPersistentTextureWithoutDescriptor(flags: ResourceFlags = [.persistent]) -> Texture {
        precondition(flags.contains(.persistent))
        return PersistentTextureRegistry.instance.allocateHandle(flags: flags)
    }
    
    public func _initialisePersistentTexture(descriptor: TextureDescriptor, heap: Heap?) {
        precondition(self.flags.contains(.persistent))
        PersistentTextureRegistry.instance.initialize(resource: self, descriptor: descriptor, heap: heap, flags: self.flags)
        
        assert(!descriptor.usageHint.isEmpty, "Persistent resources must explicitly specify their usage.")
        let didAllocate = RenderBackend.materialisePersistentResource(self)
        assert(didAllocate, "Allocation failed for persistent texture \(self)")
        if !didAllocate { self.dispose() }
    }
    
    public init?(descriptor: TextureDescriptor, heap: Heap, flags: ResourceFlags = [.persistent]) {
        precondition((1...16384).contains(descriptor.width) && (1...16384).contains(descriptor.height) && (1...16384).contains(descriptor.depth), "Invalid size for descriptor \(descriptor); all dimensions must be in the range 1...16384")
        
        assert(flags.contains(.persistent), "Heap-allocated resources must be persistent.")
        assert(!descriptor.usageHint.isEmpty, "Persistent resources must explicitly specify their usage.")
        
        var descriptor = descriptor
        descriptor.storageMode = heap.storageMode
        descriptor.cacheMode = heap.cacheMode
        
        self = PersistentTextureRegistry.instance.allocate(descriptor: descriptor, heap: heap, flags: flags)
        
        if !RenderBackend.materialisePersistentResource(self) {
            self.dispose()
            return nil
        }
        
        heap.childResources.insert(Resource(self))
    }
    
    @available(*, deprecated, renamed: "init(descriptor:externalResource:renderGraph:flags:)")
    public init(descriptor: TextureDescriptor, externalResource: Any, frameGraph: RenderGraph?, flags: ResourceFlags = [.persistent, .externalOwnership]) {
        self.init(descriptor: descriptor, externalResource: externalResource, renderGraph: frameGraph, flags: flags)
    }
    
    public init(descriptor: TextureDescriptor, externalResource: Any, renderGraph: RenderGraph? = nil, flags: ResourceFlags = [.persistent, .externalOwnership]) {
        if flags.contains(.persistent) || flags.contains(.historyBuffer) {
            self = PersistentTextureRegistry.instance.allocate(descriptor: descriptor, heap: nil, flags: flags)
        } else {
            precondition(descriptor.storageMode != .private || RenderGraph.activeRenderGraph == nil, "GPU-private transient resources cannot be created during render graph execution. Instead, create this resource in an init() method and pass in the render graph to use.")
            guard let renderGraph = renderGraph ?? RenderGraph.activeRenderGraph else {
                fatalError("The RenderGraph must be specified for transient resources created outside of a render pass' execute() method.")
            }
            self = TransientTextureRegistry.instances[renderGraph.transientRegistryIndex].allocate(descriptor: descriptor, flags: flags)
        }
        
        if self.flags.contains(.persistent) {
            assert(!descriptor.usageHint.isEmpty, "Persistent resources must explicitly specify their usage.")
        }
        RenderBackend.registerExternalResource(Resource(self), backingResource: externalResource)
    }
    
    public init(viewOf base: Texture, descriptor: TextureViewDescriptor, renderGraph: RenderGraph? = nil) {
        let flags : ResourceFlags = .resourceView
        
        guard let transientRegistryIndex = renderGraph?.transientRegistryIndex ?? RenderGraph.activeRenderGraph?.transientRegistryIndex ?? (!base._usesPersistentRegistry ? base.transientRegistryIndex : nil) else {
            fatalError("The RenderGraph must be specified for transient resources created outside of a render pass' execute() method.")
        }
        precondition(transientRegistryIndex >= 0, "Transient resources are not supported on this RenderGraph")
        
        self = TransientTextureRegistry.instances[transientRegistryIndex].allocate(descriptor: descriptor, baseResource: base, flags: flags)
        
        if base.storageMode != .private {
            renderGraph.context.transientRegistry!.allocateTextureView(self)
        }
    }
    
    public init(viewOf base: Buffer, descriptor: Buffer.TextureViewDescriptor, renderGraph: RenderGraph? = nil) {
        let flags : ResourceFlags = .resourceView
        
        guard let transientRegistryIndex = renderGraph?.transientRegistryIndex ?? RenderGraph.activeRenderGraph?.transientRegistryIndex ?? (!base._usesPersistentRegistry ? base.transientRegistryIndex : nil) else {
            fatalError("The RenderGraph must be specified for transient resources created outside of a render pass' execute() method.")
        }
        precondition(transientRegistryIndex >= 0, "Transient resources are not supported on this RenderGraph")
        
        self = TransientTextureRegistry.instances[transientRegistryIndex].allocate(descriptor: descriptor, baseResource: base, flags: flags)
        
        if base.storageMode != .private {
            renderGraph.context.transientRegistry!.allocateTextureView(self)
        }
    }
    
    public init(descriptor: TextureDescriptor, isMinimised: Bool, nativeWindow: Any, renderGraph: RenderGraph) async {
        self.init(descriptor: descriptor, renderGraph: renderGraph, flags: isMinimised ? [] : .windowHandle)
        
        if !isMinimised {
            await renderGraph.context.registerWindowTexture(for: self, swapchain: nativeWindow)
        }
    }
    
    public func copyBytes(to bytes: UnsafeMutableRawPointer, bytesPerRow: Int, region: Region, mipmapLevel: Int) async {
        await self.waitForCPUAccess(accessType: .read)
        await RenderBackend.copyTextureBytes(from: self, to: bytes, bytesPerRow: bytesPerRow, region: region, mipmapLevel: mipmapLevel)
    }
    
    public func replace(region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) async {
        await self.waitForCPUAccess(accessType: .write)
        
        await RenderBackend.replaceTextureRegion(texture: self, region: region, mipmapLevel: mipmapLevel, withBytes: bytes, bytesPerRow: bytesPerRow)
    }
    
    public func replace(region: Region, mipmapLevel: Int, slice: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int) async {
        await self.waitForCPUAccess(accessType: .write)
        
        await RenderBackend.replaceTextureRegion(texture: self, region: region, mipmapLevel: mipmapLevel, slice: slice, withBytes: bytes, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerImage)
    }
    
    public var stateFlags: ResourceStateFlags {
        get {
            if self.flags.intersection([.historyBuffer, .persistent]) == [] {
                return []
            }
            return self[\.stateFlags] ?? []
        }
        nonmutating set {
            assert(self.flags.intersection([.historyBuffer, .persistent]) != [], "State flags can only be set on persistent resources.")
            
            self[\.stateFlags] = newValue
        }
    }
    
    public var storageMode: StorageMode {
        return self.descriptor.storageMode
    }
    
    public internal(set) var descriptor : TextureDescriptor {
        get {
            return self[\.descriptors]
        }
        nonmutating set {
            self[\.descriptors] = newValue
        }
    }
    
    public var heap : Heap? {
        return self[\.heaps]
    }
    
    public var size : Size {
        return Size(width: self.descriptor.width, height: self.descriptor.height, depth: self.descriptor.depth)
    }
    
    public var width : Int {
        return self.descriptor.width
    }
    
    public var height : Int {
        return self.descriptor.height
    }
    
    public var depth : Int {
        return self.descriptor.depth
    }
    
    public var baseResource : Resource? {
        get {
            if !self.isTextureView {
                return nil
            } else {
                return self[\.baseResources]
            }
        }
    }
    
    public var textureViewBaseInfo : TextureViewBaseInfo? {
        if !self.isTextureView {
            return nil
        } else {
            return self[\.textureViewInfos]
        }
    }
    
    public func dispose() {
        guard self._usesPersistentRegistry, self.isValid else {
            return
        }
        self.heap?.childResources.remove(Resource(self))
        PersistentTextureRegistry.instance.dispose(self)
    }
    
    public static let invalid = Texture(descriptor: TextureDescriptor(type: .type2D, format: .r32Float, width: 1, height: 1, mipmapped: false, storageMode: .private, usage: .shaderRead), flags: .persistent)
    
    public static var resourceType: ResourceType {
        return .texture
    }
}

extension Texture: CustomStringConvertible {
    public var description: String {
        return "Texture(handle: \(self.handle)) { \(self.label.map { "label: \($0), "} ?? "")descriptor: \(self.descriptor), stateFlags: \(self.stateFlags), flags: \(self.flags) }"
    }
}

extension Texture: ResourceProtocolImpl {
    @usableFromInline typealias SharedProperties = TextureProperties
    @usableFromInline typealias TransientProperties = TextureProperties.TransientTextureProperties
    @usableFromInline typealias PersistentProperties = TextureProperties.PersistentTextureProperties
    
    @usableFromInline static func transientRegistry(index: Int) -> TransientTextureRegistry? {
        return TransientTextureRegistry.instances[index]
    }
    
    @usableFromInline static var persistentRegistry: PersistentRegistry<Self> { PersistentTextureRegistry.instance }
    
    @usableFromInline typealias Descriptor = TextureDescriptor
}


public enum TextureViewBaseInfo {
    case buffer(Buffer.TextureViewDescriptor)
    case texture(Texture.TextureViewDescriptor)
}

@usableFromInline struct TextureProperties: SharedResourceProperties {
    @usableFromInline struct TransientTextureProperties: ResourceProperties {
        var baseResources : UnsafeMutablePointer<Resource?>
        var textureViewInfos : UnsafeMutablePointer<TextureViewBaseInfo?>
        
        @usableFromInline init(capacity: Int) {
            self.baseResources = UnsafeMutablePointer.allocate(capacity: capacity)
            self.textureViewInfos = UnsafeMutablePointer.allocate(capacity: capacity)
        }
        
        @usableFromInline func deallocate() {
            self.baseResources.deallocate()
            self.textureViewInfos.deallocate()
        }
        
        @usableFromInline func initialize(index: Int, descriptor: TextureDescriptor, heap: Heap?, flags: ResourceFlags) {
            self.baseResources.advanced(by: index).initialize(to: nil)
            self.textureViewInfos.advanced(by: index).initialize(to: nil)
        }
        
        @usableFromInline func initialize(index: Int, descriptor: Buffer.TextureViewDescriptor, baseResource: Buffer) {
            self.baseResources.advanced(by: index).initialize(to: Resource(baseResource))
            self.textureViewInfos.advanced(by: index).initialize(to: .buffer(descriptor))
        }
        
        @usableFromInline func initialize(index: Int, viewDescriptor: Texture.TextureViewDescriptor, baseResource: Texture) {
            self.baseResources.advanced(by: index).initialize(to: Resource(baseResource))
            self.textureViewInfos.advanced(by: index).initialize(to: .texture(viewDescriptor))
        }
        
        @usableFromInline func deinitialize(from index: Int, count: Int) {
            self.baseResources.advanced(by: index).deinitialize(count: count)
            self.textureViewInfos.advanced(by: index).deinitialize(count: count)
        }
    }
    
    @usableFromInline struct PersistentTextureProperties: PersistentResourceProperties {
        
        let stateFlags : UnsafeMutablePointer<ResourceStateFlags>
        /// The index that must be completed on the GPU for each queue before the CPU can read from this resource's memory.
        let readWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The index that must be completed on the GPU for each queue before the CPU can write to this resource's memory.
        let writeWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The RenderGraphs that are currently using this resource.
        let activeRenderGraphs : UnsafeMutablePointer<UInt8.AtomicRepresentation>
        let heaps : UnsafeMutablePointer<Heap?>
        
        @usableFromInline init(capacity: Int) {
            self.stateFlags = .allocate(capacity: capacity)
            self.readWaitIndices = .allocate(capacity: capacity)
            self.writeWaitIndices = .allocate(capacity: capacity)
            self.activeRenderGraphs = .allocate(capacity: capacity)
            self.heaps = .allocate(capacity: capacity)
        }
        
        @usableFromInline func deallocate() {
            self.stateFlags.deallocate()
            self.readWaitIndices.deallocate()
            self.writeWaitIndices.deallocate()
            self.activeRenderGraphs.deallocate()
            self.heaps.deallocate()
        }
        
        @usableFromInline func initialize(index: Int, descriptor: TextureDescriptor, heap: Heap?, flags: ResourceFlags) {
            self.stateFlags.advanced(by: index).initialize(to: [])
            self.readWaitIndices.advanced(by: index).initialize(to: SIMD8(repeating: 0))
            self.writeWaitIndices.advanced(by: index).initialize(to: SIMD8(repeating: 0))
            self.activeRenderGraphs.advanced(by: index).initialize(to: UInt8.AtomicRepresentation(0))
            self.heaps.advanced(by: index).initialize(to: heap)
        }
        
        @usableFromInline func deinitialize(from index: Int, count: Int) {
            self.stateFlags.advanced(by: index).deinitialize(count: count)
            self.readWaitIndices.advanced(by: index).deinitialize(count: count)
            self.writeWaitIndices.advanced(by: index).deinitialize(count: count)
            self.activeRenderGraphs.advanced(by: index).deinitialize(count: count)
            self.heaps.advanced(by: index).deinitialize(count: count)
        }
        
        @usableFromInline var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { self.activeRenderGraphs }
        @usableFromInline var readWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { self.readWaitIndices }
        @usableFromInline var writeWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { self.writeWaitIndices }
    }
    
    let descriptors : UnsafeMutablePointer<TextureDescriptor>
    let usages : UnsafeMutablePointer<ChunkArray<RecordedResourceUsage>>
    let backingResources : UnsafeMutablePointer<UnsafeMutableRawPointer?>
    
#if canImport(Metal)
    let gpuAddresses: UnsafeMutablePointer<UInt64>
#endif
    
    @usableFromInline init(capacity: Int) {
        self.descriptors = UnsafeMutablePointer.allocate(capacity: capacity)
        self.usages = UnsafeMutablePointer.allocate(capacity: capacity)
        self.backingResources = UnsafeMutablePointer.allocate(capacity: capacity)
        
#if canImport(Metal)
        self.gpuAddresses = UnsafeMutablePointer.allocate(capacity: capacity)
#endif
    }
    
    @usableFromInline func deallocate() {
        self.descriptors.deallocate()
        self.usages.deallocate()
        self.backingResources.deallocate()
        
#if canImport(Metal)
        self.gpuAddresses.deallocate()
#endif
    }
    
    @usableFromInline func initialize(index: Int, descriptor: TextureDescriptor, heap: Heap?, flags: ResourceFlags) {
        self.descriptors.advanced(by: index).initialize(to: descriptor)
        self.usages.advanced(by: index).initialize(to: ChunkArray())
        self.backingResources.advanced(by: index).initialize(to: nil)
        
#if canImport(Metal)
        self.gpuAddresses.advanced(by: index).initialize(to: 0)
#endif
    }
    
    @usableFromInline func initialize(index: Int, descriptor: Buffer.TextureViewDescriptor, baseResource: Buffer) {
        self.descriptors.advanced(by: index).initialize(to: descriptor.descriptor)
        self.usages.advanced(by: index).initialize(to: ChunkArray())
        self.backingResources.advanced(by: index).initialize(to: nil)
        
#if canImport(Metal)
        self.gpuAddresses.advanced(by: index).initialize(to: 0)
#endif
    }
    
    @usableFromInline func initialize(index: Int, viewDescriptor: Texture.TextureViewDescriptor, baseResource: Texture) {
        var descriptor = baseResource.descriptor
        descriptor.pixelFormat = viewDescriptor.pixelFormat
        descriptor.textureType = viewDescriptor.textureType
        if viewDescriptor.slices.lowerBound != -1 {
            descriptor.arrayLength = viewDescriptor.slices.count
        }
        if viewDescriptor.levels.lowerBound != -1 {
            descriptor.mipmapLevelCount = viewDescriptor.levels.count
        }
        self.descriptors.advanced(by: index).initialize(to: descriptor)
        self.usages.advanced(by: index).initialize(to: ChunkArray())
        self.backingResources.advanced(by: index).initialize(to: nil)
        
#if canImport(Metal)
        self.gpuAddresses.advanced(by: index).initialize(to: 0)
#endif
    }
    
    @usableFromInline func deinitialize(from index: Int, count: Int) {
        self.descriptors.advanced(by: index).deinitialize(count: count)
        self.usages.advanced(by: index).deinitialize(count: count)
    }
    
    @usableFromInline var usagesOptional: UnsafeMutablePointer<ChunkArray<RecordedResourceUsage>>? { self.usages }
}

@usableFromInline final class TransientTextureRegistry: TransientFixedSizeRegistry<Texture> {
    @usableFromInline static let instances = TransientRegistryArray<TransientTextureRegistry>()
    
    @usableFromInline func allocate(descriptor: Buffer.TextureViewDescriptor, baseResource: Buffer, flags: ResourceFlags) -> Texture {
        let resource = self.allocateHandle(flags: flags)
        self.sharedStorage.initialize(index: resource.index, descriptor: descriptor, baseResource: baseResource)
        self.transientStorage.initialize(index: resource.index, descriptor: descriptor, baseResource: baseResource)
        self.labels.advanced(by: resource.index).initialize(to: nil)
        baseResource.descriptor.usageHint.formUnion(.textureView)
        
        return resource
    }
    
    @usableFromInline func allocate(descriptor viewDescriptor: Texture.TextureViewDescriptor, baseResource: Texture, flags: ResourceFlags) -> Texture {
        let resource = self.allocateHandle(flags: flags)
        self.sharedStorage.initialize(index: resource.index, viewDescriptor: viewDescriptor, baseResource: baseResource)
        self.transientStorage.initialize(index: resource.index, viewDescriptor: viewDescriptor, baseResource: baseResource)
        self.labels.advanced(by: resource.index).initialize(to: nil)
        
        if baseResource.descriptor.pixelFormat.channelCount != viewDescriptor.pixelFormat.channelCount || baseResource.descriptor.pixelFormat.bytesPerPixel != viewDescriptor.pixelFormat.bytesPerPixel {
            baseResource.descriptor.usageHint.formUnion(.pixelFormatView)
        }
        
        return resource
    }
}

final class PersistentTextureRegistry: PersistentRegistry<Texture> {
    static let instance = PersistentTextureRegistry()
}
