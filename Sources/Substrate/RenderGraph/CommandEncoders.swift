//
//  CommandEncoders.swift
//  Substrate
//
//  Created by Thomas Roughton on 30/08/20.
//

import SubstrateUtilities

#if canImport(Metal)
@preconcurrency import Metal
#endif

#if canImport(MetalPerformanceShaders)
@preconcurrency import MetalPerformanceShaders
#endif

#if canImport(Vulkan)
import Vulkan
#endif

@usableFromInline
protocol CommandEncoder : AnyObject {
    var passRecord : RenderPassRecord { get }
    
    var commandRecorder : RenderGraphCommandRecorder { get }
    var startCommandIndex : Int { get }
    
    func endEncoding()
}

// Performance: avoid slow range initialiser until https://github.com/apple/swift/pull/40871 makes it into a release branch.
extension Range where Bound: Strideable, Bound.Stride: SignedInteger {
  /// Creates an instance equivalent to the given `ClosedRange`.
  ///
  /// - Parameter other: A closed range to convert to a `Range` instance.
  ///
  /// An equivalent range must be representable as an instance of Range<Bound>.
  /// For example, passing a closed range with an upper bound of `Int.max`
  /// triggers a runtime error, because the resulting half-open range would
  /// require an upper bound of `Int.max + 1`, which is not representable as
  /// an `Int`.
  @inlinable // trivial-implementation
  public init(_ other: ClosedRange<Bound>) {
    let upperBound = other.upperBound.advanced(by: 1)
    self.init(uncheckedBounds: (lower: other.lowerBound, upper: upperBound))
  }
}

extension CommandEncoder {
    /// Returns the offset of the next command within this pass' command list.
    @inlinable
    public var nextCommandOffset : Int {
        return self.commandRecorder.nextCommandIndex - self.startCommandIndex
    }
    
    @inlinable
    public var renderPass : RenderPass {
        return self.passRecord.pass
    }
}

extension CommandEncoder {
    @inlinable
    public func pushDebugGroup(_ string: String) {
        commandRecorder.pushDebugGroup(string)
    }
    
    @inlinable
    public func popDebugGroup() {
        commandRecorder.record(.popDebugGroup)
    }
    
    @inlinable
    public func debugGroup<T>(_ groupName: String, perform: () throws -> T) rethrows -> T {
        self.pushDebugGroup(groupName)
        let result = try perform()
        self.popDebugGroup()
        return result
    }
    
    @inlinable
    public func insertDebugSignpost(_ string: String) {
        commandRecorder.insertDebugSignpost(string)
    }
}

/*
 
 ** Resource Binding Algorithm-of-sorts **
 
 When the user binds a resource for a key, record the association between that key and that resource.
 
 When the user submits a draw call, look at all key-resource pairs and bind them. Do this by retrieving the resource binding path from the backend, along with how the resource is used. Record the first usage of the resource;  the ‘first use command index’ is the first index for all of the bindings. Keep a handle to allow updating of the applicable command range. If a resource is not used, then it is not an active binding and its update handle is not retained.
 
 After the pipeline state is changed, we need to query all resources given their keys on the next draw call. If they are an active binding and the resource binding path has not changed and the usage type has not changed, then we do not need to make any changes; however, if any of the above change we need to end the applicable command range at the index of the last draw call and register a new resource binding path and update handle.
 
 We can bypass the per-draw-call checks iff the pipeline state has not changed and there have been no changes to bound resources.
 
 For buffers, we also need to track a 32-bit offset. If the offset changes but not the main resource binding path, then we submit a update-offset command instead rather than a ‘bind’ command. The update-offset command includes the ObjectIdentifier for the resource.
 
 When encoding has finished, update the applicable command range for all active bindings to continue through to the last draw call made within the encoder.
 
 
 A requirement for resource binding is that subsequently bound pipeline states are compatible with the pipeline state bound at the time of the first draw call.
 */

struct ResourceUsagePointerList: Collection, Equatable {
    let pointer: UnsafeMutableRawPointer?
    let count: Int
    
    public init(usagePointer: ResourceUsagePointer?) {
        self.pointer = UnsafeMutableRawPointer(usagePointer)
        self.count = usagePointer == nil ? 0 : 1
    }
    
    public init(usagePointers: UnsafeMutableBufferPointer<ResourceUsagePointer>) {
        self.pointer = UnsafeMutableRawPointer(usagePointers.baseAddress)
        self.count = usagePointers.count
    }
    
    public var isEmpty: Bool {
        return self.count == 0
    }
    
    public var startIndex: Int {
        return 0
    }
    
    public var endIndex: Int {
        return self.count
    }
    
    public func index(after i: Int) -> Int {
        return i + 1
    }
    
    public subscript(index: Int) -> ResourceUsagePointer {
        assert(index >= 0 && index < self.count)
        if self.count == 1 {
            return self.pointer!.assumingMemoryBound(to: ResourceUsage.self)
        } else {
            return self.pointer!.assumingMemoryBound(to: ResourceUsagePointer.self)[index]
        }
    }
    
    public var first: ResourceUsagePointer? {
        if self.isEmpty {
            return nil
        }
        return self[0]
    }
}

/// `ResourceBindingEncoder` is the common superclass `CommandEncoder` for all command encoders that can bind resources.
/// You never instantiate a `ResourceBindingEncoder` directly; instead, you are provided with one of its concrete subclasses in a render pass' `execute` method.
public class ResourceBindingEncoder : CommandEncoder {
    
    @usableFromInline
    struct BoundResource {
        public var resource : Resource
        public var bindingCommand : UnsafeMutableRawPointer?
        public var usagePointers : ResourceUsagePointerList // where the first element is the usage pointer for this resource and subsequent elements, if present, are for its subresources
        public var isIndirectlyBound : Bool
        /// Whether the resource is assumed to be used in the same way for the entire time it's bound.
        public var consistentUsageAssumed : Bool
        
//        public var usagePointer: ResourceUsagePointer? {
//            self.usagePointers.first
//        }
    }
    
    @usableFromInline let commandRecorder : RenderGraphCommandRecorder
    @usableFromInline let passRecord: RenderPassRecord
    @usableFromInline let startCommandIndex : Int
    
    @usableFromInline
    enum _ArgumentBufferType {
        case standalone
        case inArray(index: Int, bindingArgs: UnsafeMutablePointer<RenderGraphCommand.SetArgumentBufferArrayArgs>)
        
        @inlinable
        public var arrayIndex : Int {
            switch self {
            case .standalone:
                return 0
            case .inArray(let index, _):
                return index
            }
        }
    }
    
    @usableFromInline
    let pendingArgumentBuffersByKey : ExpandingBuffer<(FunctionArgumentKey, ArgumentBuffer, type: _ArgumentBufferType, assumeConsistentUsage: Bool)>
    var pendingArgumentBufferByKeyCountLastUpdate = 0
    
    let pendingArgumentBuffers : ExpandingBuffer<(ResourceBindingPath, ArgumentBuffer, type: _ArgumentBufferType, assumeConsistentUsage: Bool)>
    var pendingArgumentBufferCountLastUpdate = 0
    
    @usableFromInline
    let resourceBindingCommands : ExpandingBuffer<(FunctionArgumentKey, RenderGraphCommand)>
    var resourceBindingCommandCountLastUpdate = 0

    @usableFromInline
    var boundResources : HashMap<ResourceBindingPath, BoundResource>
    
    // untrackedBoundResources is similar to boundResources, except we explicitly don't track changes in pipeline state;
    // it's assumed that the usage of the resource remains the same until the resource is unbound or the command encoder is
    // ended.
    @usableFromInline
    var untrackedBoundResources : HashMap<ResourceBindingPath, BoundResource>
    
    // Tracks the UAV resources that are read-write – that is, they are both read and written to and therefore require barriers
    // between draws/dispatches.
    // This is overly conservative in the case where non-overlapping regions are read from and written to; however, in that case
    // the computation is usually done in a single dispatch.
    @usableFromInline
    var boundUAVResources : HashSet<ResourceBindingPath>
    
    // The following methods and variables are helpers for updateResourceUsages.
    // They're contained on the object rather than as local variables to minimised allocations and retain-release traffic.
    
    @usableFromInline
    let usagePointersToUpdate : ExpandingBuffer<ResourceUsagePointer> // nodes to update the upper bound on to the last usage index.
    
    deinit {
        self.boundResources.deinit()
        self.untrackedBoundResources.deinit()
        self.boundUAVResources.deinit()
    }
    
    @usableFromInline
    var lastGPUCommandIndex = 0
    
    @usableFromInline
    var needsUpdateBindings = false
    @usableFromInline
    var pipelineStateChanged = false
    @usableFromInline
    var depthStencilStateChanged = false
    
    @usableFromInline
    var currentPipelineReflection : PipelineReflection! = nil
    
    init(commandRecorder: RenderGraphCommandRecorder, passRecord: RenderPassRecord) {
        self.commandRecorder = commandRecorder
        self.passRecord = passRecord
        self.startCommandIndex = self.commandRecorder.nextCommandIndex
        
        self.boundResources = HashMap(allocator: AllocatorType(commandRecorder.renderPassScratchAllocator))
        self.boundUAVResources = HashSet(allocator: AllocatorType(commandRecorder.renderPassScratchAllocator))
        self.untrackedBoundResources = HashMap(allocator: AllocatorType(commandRecorder.renderPassScratchAllocator))
        self.pendingArgumentBuffersByKey = ExpandingBuffer(allocator: AllocatorType(commandRecorder.renderPassScratchAllocator))
        self.pendingArgumentBuffers = ExpandingBuffer(allocator: AllocatorType(commandRecorder.renderPassScratchAllocator))
        self.resourceBindingCommands = ExpandingBuffer(allocator: AllocatorType(commandRecorder.renderPassScratchAllocator))
        self.usagePointersToUpdate = ExpandingBuffer(allocator: AllocatorType(commandRecorder.renderPassScratchAllocator))
        
#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
        self.pushDebugGroup(passRecord.name)
#endif
    }
    
    /// Bind `bytes` with `length` to the current command encoder at the binding corresponding to key `key`.
    public func setBytes(_ bytes: UnsafeRawPointer, length: Int, key: FunctionArgumentKey) {
        let args : RenderGraphCommand.SetBytesArgs = (.nil, commandRecorder.copyBytes(bytes, length: length), UInt32(length))
        
        let argData = commandRecorder.copyData(args)
        
        self.resourceBindingCommands.append(
            (key, .setBytes(argData))
        )
        
        self.needsUpdateBindings = true
    }
    
    /// Bind `bytes` with `length` to the current command encoder at the binding path `path`.
    public func setBytes(_ bytes: UnsafeRawPointer, length: Int, path: ResourceBindingPath) {
        let args : RenderGraphCommand.SetBytesArgs = (path, commandRecorder.copyBytes(bytes, length: length), UInt32(length))
        
        let argData = commandRecorder.copyData(args)
        
        commandRecorder.record(.setBytes(argData))
    }
    
    /// Bind `buffer` with byte offset `offset` to the current command encoder at the binding corresponding to `key`.
    public func setBuffer(_ buffer: Buffer?, offset: Int, key: FunctionArgumentKey) {
        guard let buffer = buffer else { return }
        
        let args : RenderGraphCommand.SetBufferArgs = (.nil, buffer, UInt32(offset), false)
        
        self.resourceBindingCommands.append(
            (key, .setBuffer(commandRecorder.copyData(args)))
        )
        
        self.needsUpdateBindings = true
    }
    
    /// Set the byte offset for the buffer currently bound at the binding path corresponding to `key`  to `offset`.
    public func setBufferOffset(_ offset: Int, key: FunctionArgumentKey) {
        let args : RenderGraphCommand.SetBufferOffsetArgs = (.nil, nil, UInt32(offset))
        
        self.resourceBindingCommands.append(
            (key, .setBufferOffset(commandRecorder.copyData(args)))
        )
        
        self.needsUpdateBindings = true
    }
    
    /// Binds a sampler with the descriptor `descriptor` to the current command encoder at the binding corresponding to `key`.
    public func setSampler(_ descriptor: SamplerDescriptor?, key: FunctionArgumentKey) {
        guard let descriptor = descriptor else { return }
        
        let args : RenderGraphCommand.SetSamplerStateArgs = (.nil, descriptor)
        
        self.resourceBindingCommands.append(
            (key, .setSamplerState(commandRecorder.copyData(args)))
        )
        
        self.needsUpdateBindings = true
    }
    
    /// Bind `texture` to the current command encoder at the binding corresponding to `key`.
    public func setTexture(_ texture: Texture?, key: FunctionArgumentKey) {
        guard let texture = texture else { return }
        
        let args : RenderGraphCommand.SetTextureArgs = (.nil, texture)
        
        self.resourceBindingCommands.append(
            (key, .setTexture(commandRecorder.copyData(args)))
        )
        
        self.needsUpdateBindings = true
    }
    
    public func setTexture(_ texture: Texture?, path: ResourceBindingPath) {
        guard let texture = texture else { return }
        
        let args : RenderGraphCommand.SetTextureArgs = (.nil, texture)
        
        self.resourceBindingCommands.append(
            (path, .setTexture(commandRecorder.copyData(args)))
        )
        
        self.needsUpdateBindings = true
    }
    
    /// Bind the acceleration structure `structure` to the current command encoder at the binding corresponding to `key`.
    @available(macOS 11.0, iOS 14.0, *)
    public func setAccelerationStructure(_ structure: AccelerationStructure?, key: FunctionArgumentKey) {
        guard let structure = structure else { return }
        
        let args : RenderGraphCommand.SetAccelerationStructureArgs = (.nil, structure)
        
        self.resourceBindingCommands.append(
            (key, .setAccelerationStructure(commandRecorder.copyData(args)))
        )
        
        self.needsUpdateBindings = true
    }
    
    /// Bind the visible function table `table` to the current command encoder at the binding corresponding to `key`.
    @available(macOS 11.0, iOS 14.0, *)
    public func setVisibleFunctionTable(_ table: VisibleFunctionTable?, key: FunctionArgumentKey) {
        guard let table = table else { return }
        
        let args : RenderGraphCommand.SetVisibleFunctionTableArgs = (.nil, table)
        
        self.resourceBindingCommands.append(
            (key, .setVisibleFunctionTable(commandRecorder.copyData(args)))
        )
        
        self.needsUpdateBindings = true
    }
    
    /// Bind the intersection function table `table` to the current command encoder at the binding corresponding to `key`.
    @available(macOS 11.0, iOS 14.0, *)
    public func setIntersectionFunctionTable(_ table: IntersectionFunctionTable?, key: FunctionArgumentKey) {
        guard let table = table else { return }
        
        let args : RenderGraphCommand.SetIntersectionFunctionTableArgs = (.nil, table)
        
        self.resourceBindingCommands.append(
            (key, .setIntersectionFunctionTable(commandRecorder.copyData(args)))
        )
        
        self.needsUpdateBindings = true
    }
    
    /// Construct an `ArgumentBuffer` specified by the `ArgumentBufferEncodable` value `arguments`
    /// and bind it to the binding index `setIndex`, corresponding to a `[[buffer(setIndex + 1)]]` binding for Metal or the
    /// descriptor set at `setIndex` for Vulkan.
    public func setArguments<A : ArgumentBufferEncodable>(_ arguments: inout A, at setIndex: Int) {
        if A.self == NilSet.self {
            return
        }
        
        let bindingPath = RenderBackend.argumentBufferPath(at: setIndex, stages: A.activeStages)
        
        let argumentBuffer = ArgumentBuffer(descriptor: A.argumentBufferDescriptor)
        assert(argumentBuffer.bindings.isEmpty)
        arguments.encode(into: argumentBuffer, setIndex: setIndex, bindingEncoder: self)
     
#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
        argumentBuffer.label = "Descriptor Set for \(String(reflecting: A.self))"
#endif
        
        if _isDebugAssertConfiguration() {
            
            for binding in argumentBuffer.bindings {
                switch binding.1 {
                case .buffer(let buffer, _):
                    assert(buffer.type == .buffer)
                case .texture(let texture):
                    assert(texture.type == .texture)
                default:
                    break
                }
            }
        }

        self.pendingArgumentBuffers.append((bindingPath, argumentBuffer, type: .standalone, assumeConsistentUsage: false))
        self.needsUpdateBindings = true
    }
    
    /// Bind `argumentBuffer` to the binding index `index`, corresponding to a `[[buffer(setIndex + 1)]]` binding for Metal or the
    /// descriptor set at `setIndex` for Vulkan, and mark it as active in render stages `stages`.
    public func setArgumentBuffer(_ argumentBuffer: ArgumentBuffer?, at index: Int, stages: RenderStages) {
        guard let argumentBuffer = argumentBuffer else { return }
        let bindingPath = RenderBackend.argumentBufferPath(at: index, stages: stages)
        
        self.pendingArgumentBuffers.append((bindingPath, argumentBuffer, type: .standalone, assumeConsistentUsage: false))
        self.needsUpdateBindings = true
    }
    
    /// Bind `argumentBuffer` to the binding index `index`, corresponding to a `[[buffer(setIndex + 1)]]` binding for Metal or the
    /// descriptor set at `setIndex` for Vulkan, and mark it as active in render stages `stages`.
    public func setArgumentBuffer<K>(_ argumentBuffer: TypedArgumentBuffer<K>?, at index: Int, stages: RenderStages) {
        guard let argumentBuffer = argumentBuffer?.argumentBuffer else { return }
        self.setArgumentBuffer(argumentBuffer, at: index, stages: stages)
    }
    
    /// Bind `argumentBufferArray` to the binding index `index`, corresponding to a `[[buffer(setIndex + 1)]]` binding for Metal or the
    /// descriptor set at `setIndex` for Vulkan, and mark it as active in render stages `stages`.
    public func setArgumentBufferArray(_ argumentBufferArray: ArgumentBufferArray?, at index: Int, stages: RenderStages, assumeConsistentUsage: Bool = false) {
        guard let argumentBufferArray = argumentBufferArray else { return }
        let bindingPath = RenderBackend.argumentBufferPath(at: index, stages: stages)
        
        let args : RenderGraphCommand.SetArgumentBufferArrayArgs = (bindingPath, argumentBufferArray, false) // false meaning is not yet bound
        let argsPointer = commandRecorder.copyData(args)
        
        for (i, argumentBuffer) in argumentBufferArray._bindings.enumerated() {
            guard let argumentBuffer = argumentBuffer else { continue }
            let type : _ArgumentBufferType = .inArray(index: i, bindingArgs: UnsafeMutablePointer(mutating: argsPointer))
            self.pendingArgumentBuffers.append((bindingPath, argumentBuffer, type: type, assumeConsistentUsage: assumeConsistentUsage))
        }
        
        self.needsUpdateBindings = true
    }
    
    /// Bind `argumentBufferArray` to the binding index `index`, corresponding to a `[[buffer(setIndex + 1)]]` binding for Metal or the
    /// descriptor set at `setIndex` for Vulkan, and mark it as active in render stages `stages`.
    public func setArgumentBufferArray<K>(_ argumentBufferArray: TypedArgumentBufferArray<K>?, at index: Int, stages: RenderStages, assumeConsistentUsage: Bool = false) {
        guard let argumentBufferArray = argumentBufferArray?.argumentBufferArray else { return }
        self.setArgumentBufferArray(argumentBufferArray, at: index, stages: stages, assumeConsistentUsage: assumeConsistentUsage)
    }
    
    public func setArgumentBuffer(_ argumentBuffer: ArgumentBuffer?, key: FunctionArgumentKey) {
        guard let argumentBuffer = argumentBuffer else { return }
        
        self.pendingArgumentBuffersByKey.append((key, argumentBuffer, type: .standalone, assumeConsistentUsage: false))
        self.needsUpdateBindings = true
    }
    
    public func setArgumentBuffer<K>(_ argumentBuffer: TypedArgumentBuffer<K>?, key: FunctionArgumentKey) {
        self.setArgumentBuffer(argumentBuffer?.argumentBuffer, key: key)
    }
    
    public func setArgumentBufferArray(_ argumentBufferArray: ArgumentBufferArray?, key: FunctionArgumentKey, assumeConsistentUsage: Bool = false) {
        guard let argumentBufferArray = argumentBufferArray else { return }
        
        let args : RenderGraphCommand.SetArgumentBufferArrayArgs = (.nil, argumentBufferArray, false) // false meaning is not yet bound
        let argsPointer = commandRecorder.copyData(args)
        
        for (i, argumentBuffer) in argumentBufferArray._bindings.enumerated() {
            guard let argumentBuffer = argumentBuffer else { continue }
            
            let type : _ArgumentBufferType = .inArray(index: i, bindingArgs: UnsafeMutablePointer(mutating: argsPointer))
            self.pendingArgumentBuffersByKey.append((key, argumentBuffer, type: type, assumeConsistentUsage: assumeConsistentUsage))
        }
        
        // We add the command to the commands list here so that the binding key can be translated.
        self.resourceBindingCommands.append((key, RenderGraphCommand.setArgumentBufferArray(UnsafePointer(argsPointer))))
        
        self.needsUpdateBindings = true
    }
    
    public func setArgumentBufferArray<K>(_ argumentBufferArray: TypedArgumentBufferArray<K>?, key: FunctionArgumentKey, assumeConsistentUsage: Bool = false) {
        self.setArgumentBufferArray(argumentBufferArray?.argumentBufferArray, key: key, assumeConsistentUsage: assumeConsistentUsage)
    }
    
    public func useIndirectResource(_ resource: Resource, usageType: ResourceUsageType, stages: RenderStages) {
        _ = self.commandRecorder.resourceUsagePointers(for: resource, encoder: self, usageType: usageType, stages: stages, activeRange: .fullResource, isIndirectlyBound: true, firstCommandOffset: self.nextCommandOffset)
    }
    
    func updateUsageNodes(lastIndex: Int) {
        for usagePointer in usagePointersToUpdate {
            usagePointer.pointee.commandRange = Range(uncheckedBounds: (usagePointer.pointee.commandRange.lowerBound, lastIndex + 1))
        }
        usagePointersToUpdate.removeAll()
    }
   
    func updateResourceUsages(endingEncoding: Bool = false) {
        guard self.needsUpdateBindings || endingEncoding else {
            return
        }
        defer { self.needsUpdateBindings = false }
        
        self.updateResourceUsagesInternal(endingEncoding: endingEncoding)
    }
    
    func replacingBoundResourceNode(at bindingPath: ResourceBindingPath, resultUntrackedIfUsed: Bool, perform: (_ oldNode: BoundResource?) -> BoundResource?) {
        let indexInBoundResources = self.boundResources.find(key: bindingPath)
        var indexInUntrackedBoundResources : Int? = nil
        var currentlyBound: BoundResource? = nil
        
        if let indexInBoundResources = indexInBoundResources {
            currentlyBound = self.boundResources.removeValue(at: indexInBoundResources)
        } else {
            indexInUntrackedBoundResources = self.untrackedBoundResources.find(key: bindingPath)
            if let indexInUntrackedBoundResources = indexInUntrackedBoundResources {
                currentlyBound = self.untrackedBoundResources.removeValue(at: indexInUntrackedBoundResources)
            }
        }
        
        let newValue = perform(currentlyBound)
        
        if let newValue = newValue {
            if resultUntrackedIfUsed, !newValue.usagePointers.isEmpty {
                if let target = indexInUntrackedBoundResources {
                    self.untrackedBoundResources.insertAtIndex(target, key: bindingPath, value: newValue)
                } else {
                    self.untrackedBoundResources.insertUnique(key: bindingPath, value: newValue)
                }
            } else {
                if let target = indexInBoundResources {
                    self.boundResources.insertAtIndex(target, key: bindingPath, value: newValue)
                } else {
                    self.boundResources.insertUnique(key: bindingPath, value: newValue)
                }
            }
        }
        
        if let currentBoundUsages = currentlyBound?.usagePointers, newValue?.usagePointers != currentBoundUsages {
            self.usagePointersToUpdate.append(contentsOf: currentBoundUsages) // The old resource is no longer bound, so we need to end the old usage.
        }
    }
    
    func updateResourceUsagesInternal(endingEncoding: Bool) {
        defer { self.pipelineStateChanged = false }
        
        if endingEncoding {
            // We shouldn't bind anything if we're ending encoding; doing so could mean we bind invalid resources
            // and then are unable to materialise them within the backends' resource registries since their lifetime
            // has already expired.
            let endIndex = self.lastGPUCommandIndex + 1
            self.boundResources.forEach { (path, value) in
                for usagePointer in value.usagePointers {
                    usagePointer.pointee.commandRange = usagePointer.pointee.commandRange.lowerBound..<endIndex
                }
            }
            self.untrackedBoundResources.forEach { (path, value) in
                for usagePointer in value.usagePointers {
                    usagePointer.pointee.commandRange = usagePointer.pointee.commandRange.lowerBound..<endIndex
                }
            }
            return
        }
        
        guard let pipelineReflection = self.currentPipelineReflection else {
            fatalError("No render or compute pipeline is set for pass \(renderPass.name).")
        }
        
        let firstCommandOffset = self.nextCommandOffset
        
        let resourceBindingCommandsStartCount = self.resourceBindingCommands.count
        
        // If the pipeline state hasn't changed, only try to bind new commands.
        let processingRange = (pipelineStateChanged ? 0 : self.resourceBindingCommandCountLastUpdate)..<resourceBindingCommandsStartCount
        
        for i in processingRange {
            let (key, command) = self.resourceBindingCommands[i]
            guard let bindingPath = key.computedBindingPath(pipelineReflection: pipelineReflection) else {
                self.resourceBindingCommands.append((key, command))
                continue
            }
            
            replacingBoundResourceNode(at: bindingPath, resultUntrackedIfUsed: false, perform: { currentlyBound in
                var bufferOffset = 0
                
                let argsPtr : UnsafeMutableRawPointer
                let resource : Resource
                switch command {
                case .setSamplerState(let args):
                    UnsafeMutablePointer(mutating: args).pointee.bindingPath = bindingPath
                    self.commandRecorder.record(command)
                    return nil
                    
                case .setArgumentBufferArray(let args):
                    // We'll actually add setArgumentBufferArray to the command
                    // stream later once its first argument buffer is bound.
                    UnsafeMutablePointer(mutating: args).pointee.bindingPath = bindingPath
                    return nil
                    
                case .setBytes(let args):
                    UnsafeMutablePointer(mutating: args).pointee.bindingPath = bindingPath
                    self.commandRecorder.record(command)
                    return nil
                    
                case .setBufferOffset(let args):
                    UnsafeMutablePointer(mutating: args).pointee.bindingPath = bindingPath
                    self.commandRecorder.record(command)
                    
                    guard let setBufferArgsRaw = currentlyBound?.bindingCommand else {
                        assertionFailure("No buffer bound when setBufferOffset was called for key \(key).")
                        return currentlyBound
                    }
                    let setBufferArgs = setBufferArgsRaw.assumingMemoryBound(to: RenderGraphCommand.SetBufferArgs.self)
                    
                    let handle = setBufferArgs.pointee.buffer
                    UnsafeMutablePointer(mutating: args).pointee.buffer = handle
                    setBufferArgs.pointee.hasDynamicOffset = true
                    
                    return currentlyBound
                    
                case .setBuffer(let args):
                    if let previousArgs = currentlyBound?.bindingCommand?.assumingMemoryBound(to: RenderGraphCommand.SetBufferArgs.self) {
                        if previousArgs.pointee.buffer == args.pointee.buffer { // Ignore the duplicate binding.
                            if !self.pipelineStateChanged, previousArgs.pointee.offset == args.pointee.offset {
                                return currentlyBound
                            } /* else {
                             // TODO: translate duplicate setBuffer calls into setBufferOffset.
                             }*/
                        }
                    }
                    
                    resource = Resource(args.pointee.buffer)
                    UnsafeMutablePointer(mutating: args).pointee.bindingPath = bindingPath
                    argsPtr = UnsafeMutableRawPointer(mutating: args)
                    bufferOffset = Int(args.pointee.offset)
                    
                case .setTexture(let args):
                    if let previousArgs = currentlyBound?.bindingCommand?.assumingMemoryBound(to: RenderGraphCommand.SetTextureArgs.self) {
                        if !self.pipelineStateChanged, previousArgs.pointee.texture == args.pointee.texture { // Ignore the duplicate binding.
                            return currentlyBound
                        }
                    }
                    
                    resource = Resource(args.pointee.texture)
                    UnsafeMutablePointer(mutating: args).pointee.bindingPath = bindingPath
                    argsPtr = UnsafeMutableRawPointer(mutating: args)
                    
                case .setAccelerationStructure(let args):
                    if let previousArgs = currentlyBound?.bindingCommand?.assumingMemoryBound(to: RenderGraphCommand.SetAccelerationStructureArgs.self) {
                        if !self.pipelineStateChanged, previousArgs.pointee.structure == args.pointee.structure { // Ignore the duplicate binding.
                            return currentlyBound
                        }
                    }
                    
                    resource = Resource(args.pointee.structure)
                    UnsafeMutablePointer(mutating: args).pointee.bindingPath = bindingPath
                    argsPtr = UnsafeMutableRawPointer(mutating: args)
                    
                case .setVisibleFunctionTable(let args):
                    if let previousArgs = currentlyBound?.bindingCommand?.assumingMemoryBound(to: RenderGraphCommand.SetVisibleFunctionTableArgs.self) {
                        if !self.pipelineStateChanged, previousArgs.pointee.table == args.pointee.table { // Ignore the duplicate binding.
                            return currentlyBound
                        }
                    }
                    
                    _ = args.pointee.table.replacePipelineState(with: self.currentPipelineReflection.pipelineState!, expectingCurrentValue: nil)
                    
                    resource = Resource(args.pointee.table)
                    UnsafeMutablePointer(mutating: args).pointee.bindingPath = bindingPath
                    argsPtr = UnsafeMutableRawPointer(mutating: args)
                    
                case .setIntersectionFunctionTable(let args):
                    if let previousArgs = currentlyBound?.bindingCommand?.assumingMemoryBound(to: RenderGraphCommand.SetIntersectionFunctionTableArgs.self) {
                        if !self.pipelineStateChanged, previousArgs.pointee.table == args.pointee.table { // Ignore the duplicate binding.
                            return currentlyBound
                        }
                    }
                    _ = args.pointee.table.replacePipelineState(with: self.currentPipelineReflection.pipelineState!, expectingCurrentValue: nil)
                    
                    resource = Resource(args.pointee.table)
                    UnsafeMutablePointer(mutating: args).pointee.bindingPath = bindingPath
                    argsPtr = UnsafeMutableRawPointer(mutating: args)
                    
                default:
                    preconditionFailure()
                }
                
                // Optimisation: if the pipeline state hasn't changed, these are the only resources we need to consider, so look up their reflection data immediately.
                // This only applies for render commands, since we may need to insert memory barriers between compute and blit commands.
                if !self.pipelineStateChanged,
                    let reflection = pipelineReflection.argumentReflection(at: bindingPath), reflection.isActive {
                    self.commandRecorder.record(command)
                    let usagePointers = self.commandRecorder.resourceUsagePointers(for: resource, encoder: self, usageType: reflection.usageType, stages: reflection.activeStages, activeRange: reflection.activeRange.offset(by: bufferOffset), isIndirectlyBound: false, firstCommandOffset: firstCommandOffset)
                    if reflection.usageType.isUAVWrite {
                        self.boundUAVResources.insert(bindingPath)
                    } else {
                        self.boundUAVResources.remove(bindingPath)
                    }
                    return BoundResource(resource: resource, bindingCommand: argsPtr, usagePointers: usagePointers, isIndirectlyBound: false, consistentUsageAssumed: false)
                } else {
                    return BoundResource(resource: resource, bindingCommand: argsPtr, usagePointers: ResourceUsagePointerList(usagePointer: nil), isIndirectlyBound: false, consistentUsageAssumed: false)
                }
            })
        }
        
        self.resourceBindingCommands.removeRange(processingRange)
        
        let pendingArgumentBuffersByKeyStartCount = self.pendingArgumentBuffersByKey.count
        let argumentBufferByKeyProcessingRange = (pipelineStateChanged ? 0 : self.pendingArgumentBufferByKeyCountLastUpdate)..<pendingArgumentBuffersByKeyStartCount
        // If the pipeline state hasn't changed, only try to bind new argument buffers.
        for i in argumentBufferByKeyProcessingRange {
            let (key, argumentBuffer, argBufferType, assumeConsistentUsage) = self.pendingArgumentBuffersByKey[i]
            
            let arrayIndex = argBufferType.arrayIndex
            
            let argumentBufferPath : ResourceBindingPath
            if let path = key.bindingPath(arrayIndex: arrayIndex, argumentBufferPath: nil) {
                guard pipelineReflection.bindingIsActive(at: path) else {
                    self.pendingArgumentBuffersByKey.append((key, argumentBuffer, argBufferType, assumeConsistentUsage))
                    continue
                }
                argumentBufferPath = path
            } else if let path = pipelineReflection.bindingPath(argumentBuffer: argumentBuffer, argumentName: key.stringValue, arrayIndex: arrayIndex) {
                argumentBufferPath = path
            } else {
                self.pendingArgumentBuffersByKey.append((key, argumentBuffer, argBufferType, assumeConsistentUsage))
                continue
            }
            
            self.pendingArgumentBuffers.append((argumentBufferPath, argumentBuffer, argBufferType, assumeConsistentUsage))
        }
        
        self.pendingArgumentBuffersByKey.removeRange(argumentBufferByKeyProcessingRange)
        
        let pendingArgumentBuffersStartCount = self.pendingArgumentBuffers.count
        let argumentBufferProcessingRange = (pipelineStateChanged ? 0 : self.pendingArgumentBufferCountLastUpdate)..<pendingArgumentBuffersStartCount
        // If the pipeline state hasn't changed, only try to bind new argument buffers.
        for i in argumentBufferProcessingRange {
            let (argumentBufferPath, argumentBuffer, argBufferType, assumeConsistentUsage) = self.pendingArgumentBuffers[i]
            
            guard pipelineReflection.bindingIsActive(at: argumentBufferPath) else {
                self.pendingArgumentBuffers.append((argumentBufferPath, argumentBuffer, argBufferType, assumeConsistentUsage))
                continue
            }
            
            replacingBoundResourceNode(at: argumentBufferPath, resultUntrackedIfUsed: assumeConsistentUsage, perform: { currentlyBound in
                let argsPtr : UnsafeMutableRawPointer
                
                switch argBufferType {
                case .standalone:
                    argsPtr = UnsafeMutableRawPointer(mutating: commandRecorder.copyData((argumentBufferPath, argumentBuffer) as RenderGraphCommand.SetArgumentBufferArgs))
                case .inArray(_, let bindingArgs):
                    argsPtr = UnsafeMutableRawPointer(mutating: bindingArgs)
                }
                
                // Optimisation: if the pipeline state hasn't changed, these are the only resources we need to consider, so look up their reflection data immediately.
                // This only applies for render commands, since we may need to insert memory barriers between compute and blit commands.
                if !self.pipelineStateChanged,
                    let reflection = pipelineReflection.argumentReflection(at: argumentBufferPath), reflection.isActive {
                    argumentBuffer.updateEncoder(pipelineReflection: pipelineReflection, bindingPath: argumentBufferPath)
                    
                    switch argBufferType {
                    case .standalone:
                        self.commandRecorder.record(.setArgumentBuffer(argsPtr.assumingMemoryBound(to: RenderGraphCommand.SetArgumentBufferArgs.self)))
                    case .inArray(_, let bindingArgs):
                        if !bindingArgs.pointee.isBound {
                            self.commandRecorder.record(.setArgumentBufferArray(argsPtr.assumingMemoryBound(to: RenderGraphCommand.SetArgumentBufferArrayArgs.self)))
                            bindingArgs.pointee.isBound = true
                        }
                        assert(argsPtr.assumingMemoryBound(to: RenderGraphCommand.SetArgumentBufferArrayArgs.self).pointee.argumentBuffer == argumentBuffer.sourceArray)
                    }
                    
                    let usagePointers = self.commandRecorder.resourceUsagePointers(for: argumentBuffer, encoder: self, usageType: reflection.usageType, stages: reflection.activeStages, firstCommandOffset: firstCommandOffset)
                    
                    if reflection.usageType.isUAVWrite {
                        self.boundUAVResources.insert(argumentBufferPath)
                    } else {
                        self.boundUAVResources.remove(argumentBufferPath)
                    }
                    
                    return BoundResource(resource: Resource(argumentBuffer), bindingCommand: argsPtr, usagePointers: usagePointers, isIndirectlyBound: false, consistentUsageAssumed: false)
                } else {
                    return BoundResource(resource: Resource(argumentBuffer), bindingCommand: argsPtr, usagePointers: ResourceUsagePointerList(usagePointer: nil), isIndirectlyBound: false, consistentUsageAssumed: false)
                }
            })
            
            argumentBuffer.translateEnqueuedBindings { (key, arrayIndex, argumentResource) in
                guard let bindingPath = key.bindingPath(argumentBufferPath: argumentBufferPath, arrayIndex: arrayIndex, pipelineReflection: pipelineReflection) else {
                    if let resource = argumentResource.resource {
                        let _ = self.commandRecorder.resourceUsagePointers(for: resource, encoder: self, usageType: .unusedArgumentBuffer, stages: .cpuBeforeRender, activeRange: .inactive, isIndirectlyBound: true, firstCommandOffset: firstCommandOffset)
                    }
                    
                    return nil
                }
                
                return bindingPath
            }
            
            for (bindingPath, argumentResource) in argumentBuffer.bindings {
                let bindingPath = pipelineReflection.bindingPath(pathInOriginalArgumentBuffer: bindingPath, newArgumentBufferPath: argumentBufferPath)
                
                guard let resource = argumentResource.resource else {
                    if let existingUsage = self.boundResources.removeValue(forKey: bindingPath) {
                        self.usagePointersToUpdate.append(contentsOf: existingUsage.usagePointers)
                    }
                    if let existingUsage = self.untrackedBoundResources.removeValue(forKey: bindingPath) {
                        self.usagePointersToUpdate.append(contentsOf: existingUsage.usagePointers)
                    }
                    continue
                }
                
                replacingBoundResourceNode(at: bindingPath, resultUntrackedIfUsed: assumeConsistentUsage, perform: { currentlyBound in
                    // Optimisation: if the pipeline state hasn't changed, these are the only resources we need to consider, so look up their reflection data immediately.
                    let usageNodes: ResourceUsagePointerList
                    if !self.pipelineStateChanged, let reflection = pipelineReflection.argumentReflection(at: bindingPath), reflection.isActive {
                        usageNodes = self.commandRecorder.resourceUsagePointers(for: resource, encoder: self, usageType: reflection.usageType, stages: reflection.activeStages, activeRange: reflection.activeRange.offset(by: argumentResource.activeRangeOffsetIntoResource), isIndirectlyBound: true, firstCommandOffset: firstCommandOffset)
                        if reflection.usageType.isUAVWrite {
                            self.boundUAVResources.insert(bindingPath)
                        } else {
                            self.boundUAVResources.remove(bindingPath)
                        }
                    } else {
                        usageNodes = .init(usagePointer: nil)
                    }
                    return BoundResource(resource: resource, bindingCommand: nil, usagePointers: usageNodes, isIndirectlyBound: true, consistentUsageAssumed: assumeConsistentUsage)
                })
            }
        }
        
        self.pendingArgumentBuffers.removeRange(argumentBufferProcessingRange)
        
        if self.pipelineStateChanged {
            // Only update tracked bound resources, not any members of untrackedBoundResources
            // We should also bind any resources that haven't been yet bound – if the pipeline state changed, we may have skipped binding earlier
            // and intended to have it done here instead.
            
            self.boundUAVResources.removeAll()
            
            self.boundResources.forEachMutating { bindingPath, /* inout */ boundResource, /* inout */ deleteEntry in
                if let reflection = pipelineReflection.argumentReflection(at: bindingPath), reflection.isActive {
                    // Mark the resource as used if it currently isn't
                    assert(reflection.type == boundResource.resource.type || (reflection.type == .buffer && boundResource.resource.type == .argumentBuffer))
                        
                    // If the command to bind the resource hasn't yet been inserted into the command stream, insert it now.
                    if boundResource.usagePointers.isEmpty, let bindingCommandArgs = boundResource.bindingCommand {
                        switch boundResource.resource.type {
                        case .texture:
                            self.commandRecorder.record(.setTexture(bindingCommandArgs.assumingMemoryBound(to: RenderGraphCommand.SetTextureArgs.self)))
                        case .buffer:
                            self.commandRecorder.record(.setBuffer(bindingCommandArgs.assumingMemoryBound(to: RenderGraphCommand.SetBufferArgs.self)))
                        case .accelerationStructure:
                            self.commandRecorder.record(.setAccelerationStructure(bindingCommandArgs.assumingMemoryBound(to: RenderGraphCommand.SetAccelerationStructureArgs.self)))
                        case .visibleFunctionTable:
                            self.commandRecorder.record(.setVisibleFunctionTable(bindingCommandArgs.assumingMemoryBound(to: RenderGraphCommand.SetVisibleFunctionTableArgs.self)))
                        case .intersectionFunctionTable:
                            self.commandRecorder.record(.setIntersectionFunctionTable(bindingCommandArgs.assumingMemoryBound(to: RenderGraphCommand.SetIntersectionFunctionTableArgs.self)))
                        case .argumentBuffer:
                            let argumentBuffer = ArgumentBuffer(boundResource.resource)!
                            
                            // The command might be either a setArgumentBuffer or setArgumentBufferArray command.
                            // Check to see whether the resource is an ArgumentBuffer or ArgumentBufferArray to distinguish.
                            let setArgumentBufferArgs = bindingCommandArgs.assumingMemoryBound(to: RenderGraphCommand.SetArgumentBufferArgs.self)
                            
                            if Resource(setArgumentBufferArgs.pointee.argumentBuffer).type == .argumentBufferArray {
                                let arrayArguments = bindingCommandArgs.assumingMemoryBound(to: RenderGraphCommand.SetArgumentBufferArrayArgs.self)
                                if !arrayArguments.pointee.isBound {
                                    self.commandRecorder.record(.setArgumentBufferArray(arrayArguments))
                                    arrayArguments.pointee.isBound = true
                                }
                                assert(arrayArguments.pointee.argumentBuffer == argumentBuffer.sourceArray)
                            } else {
                                let setArgumentBufferArgs = bindingCommandArgs.assumingMemoryBound(to: RenderGraphCommand.SetArgumentBufferArgs.self)
                                self.commandRecorder.record(.setArgumentBuffer(setArgumentBufferArgs))
                            }
                            
                        default:
                            preconditionFailure()
                        }
                    }
                    
                    // If the pipeline state has changed, check for an updated encoder for any argument buffers.
                    ArgumentBuffer(boundResource.resource)?.updateEncoder(pipelineReflection: pipelineReflection, bindingPath: bindingPath)
                    
                    var bufferOffset = 0
                    if case .buffer = boundResource.resource.type, let bindingCommandArgs = boundResource.bindingCommand {
                        bufferOffset = Int(bindingCommandArgs.assumingMemoryBound(to: RenderGraphCommand.SetBufferArgs.self).pointee.offset)
                    }
                    
                    let usagePointers = self.commandRecorder.resourceUsagePointers(for: boundResource.resource, encoder: self, usageType: reflection.usageType, stages: reflection.activeStages, activeRange: reflection.activeRange.offset(by: bufferOffset), isIndirectlyBound: boundResource.isIndirectlyBound, firstCommandOffset: firstCommandOffset)
                    boundResource.usagePointers = usagePointers
                    
                    if reflection.usageType.isUAVWrite {
                        self.boundUAVResources.insertUnique(bindingPath) // Guaranteed to not be present since we cleared boundUAVResources before this block.
                    } else if boundResource.consistentUsageAssumed {
                        deleteEntry = true // Delete the entry from this HashMap
                        self.untrackedBoundResources.insertUnique(key: bindingPath, value: boundResource)
                    }
                    
                } else {
                    // The resource is currently unused; end its usage.
                    if boundResource.isIndirectlyBound {
                        let _ = self.commandRecorder.resourceUsagePointers(for: boundResource.resource, encoder: self, usageType: .unusedArgumentBuffer, stages: .cpuBeforeRender, activeRange: .inactive, isIndirectlyBound: true, firstCommandOffset: firstCommandOffset)
                    } else {
                        // The resource is currently unused; end its usage.
                        self.usagePointersToUpdate.append(contentsOf: boundResource.usagePointers)
                        boundResource.usagePointers = .init(usagePointer: nil)
                    }
                }
            }
        } else {
            self.boundUAVResources.forEach { bindingPath in
                self.boundResources.withValue(forKey: bindingPath, perform: { boundResourcePtr, _ in
                    let boundResource = boundResourcePtr.pointee
                    let usage = boundResource.usagePointers.first!.pointee
                    let usagePointers = self.commandRecorder.resourceUsagePointers(for: boundResource.resource, encoder: self, usageType: usage.type, stages: usage.stages, activeRange: usage.activeRange, isIndirectlyBound: boundResource.isIndirectlyBound, firstCommandOffset: firstCommandOffset)
                    boundResourcePtr.pointee.usagePointers = usagePointers
                })
            }
        }
        
        self.updateUsageNodes(lastIndex: self.lastGPUCommandIndex)
        
        self.resourceBindingCommandCountLastUpdate = self.resourceBindingCommands.count
        self.pendingArgumentBufferByKeyCountLastUpdate = self.pendingArgumentBuffersByKey.count
        self.pendingArgumentBufferCountLastUpdate = self.pendingArgumentBuffers.count
    }
    
    @usableFromInline func resetAllBindings() {
        self.resourceBindingCommandCountLastUpdate = 0
        self.pendingArgumentBufferByKeyCountLastUpdate = 0
        self.pendingArgumentBufferCountLastUpdate = 0
        
        self.resourceBindingCommands.removeAll()
        self.pendingArgumentBuffers.removeAll()
        self.pendingArgumentBuffersByKey.removeAll()
        
        let endIndex = self.lastGPUCommandIndex + 1
        
        self.boundResources.removeAll(iterating: { (path, value) in
            for usagePointer in value.usagePointers {
                usagePointer.pointee.commandRange = usagePointer.pointee.commandRange.lowerBound..<endIndex
            }
        })
        
        self.untrackedBoundResources.removeAll(iterating: { (path, value) in
            for usagePointer in value.usagePointers {
                usagePointer.pointee.commandRange = usagePointer.pointee.commandRange.lowerBound..<endIndex
            }
        })
    }
    
    @usableFromInline func endEncoding() {
        self.updateResourceUsages(endingEncoding: true)
#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
        self.popDebugGroup() // Pass Name
#endif
    }
}

extension ResourceBindingEncoder {
    
    @inlinable
    public func setValue<T : ResourceProtocol>(_ value: T, key: FunctionArgumentKey) {
        preconditionFailure("setValue should not be used with resources; use setBuffer, setTexture, or setArgumentBuffer instead.")
    }
    
    @inlinable
    public func setValue<T>(_ value: T, key: FunctionArgumentKey) {
        assert(!(T.self is AnyObject.Type), "setValue should only be used with value types.")
        
        var value = value
        withUnsafeBytes(of: &value) { bytes in
            self.setBytes(bytes.baseAddress!, length: bytes.count, key: key)
        }
    }
}

public protocol AnyRenderCommandEncoder {
    func setArgumentBuffer<K>(_ argumentBuffer: TypedArgumentBuffer<K>?, at index: Int, stages: RenderStages)
    
    func setArgumentBufferArray<K>(_ argumentBufferArray: TypedArgumentBufferArray<K>?, at index: Int, stages: RenderStages, assumeConsistentUsage: Bool)
    
    func setVertexBuffer(_ buffer: Buffer?, offset: Int, index: Int)
    
    func setVertexBufferOffset(_ offset: Int, index: Int)
    
    func setViewport(_ viewport: Viewport)
    
    func setFrontFacing(_ frontFacingWinding: Winding)
    
    func setCullMode(_ cullMode: CullMode)

    func setScissorRect(_ rect: ScissorRect)
    
    func setDepthBias(_ depthBias: Float, slopeScale: Float, clamp: Float)
    
    func setStencilReferenceValue(_ referenceValue: UInt32)
    
    func setStencilReferenceValues(front frontReferenceValue: UInt32, back backReferenceValue: UInt32)
    
    func drawPrimitives(type primitiveType: PrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int, baseInstance: Int) async
    
    func drawIndexedPrimitives(type primitiveType: PrimitiveType, indexCount: Int, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: Int, instanceCount: Int, baseVertex: Int, baseInstance: Int)  async
}

/// `RenderCommandEncoder` allows you to encode rendering commands to be executed by the GPU within a single `DrawRenderPass`.
public class RenderCommandEncoder : ResourceBindingEncoder, AnyRenderCommandEncoder {
    
    @usableFromInline
    enum Attachment : Hashable, CustomHashable {
        case color(Int)
        case depth
        case stencil
        
        public var customHashValue: Int {
            switch self {
            case .depth:
                return 1 << 0
            case .stencil:
                return 1 << 1
            case .color(let index):
                return 1 << 2 &+ index
            }
        }
    }
    
    struct DrawDynamicState: OptionSet {
        let rawValue: Int
        
        init(rawValue: Int) {
            self.rawValue = rawValue
        }
        
        static let viewport = DrawDynamicState(rawValue: 1 << 0)
        static let scissorRect = DrawDynamicState(rawValue: 1 << 1)
        static let frontFacing = DrawDynamicState(rawValue: 1 << 2)
        static let cullMode = DrawDynamicState(rawValue: 1 << 3)
        static let triangleFillMode = DrawDynamicState(rawValue: 1 << 4)
        static let depthBias = DrawDynamicState(rawValue: 1 << 5)
        static let stencilReferenceValue = DrawDynamicState(rawValue: 1 << 6)
    }
    
    let drawRenderPass : DrawRenderPass
    
    @usableFromInline
    var boundVertexBuffers = [ResourceUsagePointer?](repeating: nil, count: 8)
    @usableFromInline
    var renderTargetAttachmentUsages : HashMap<Attachment, ResourceUsagePointer>
    
    var renderPipelineDescriptor : RenderPipelineDescriptor? = nil
    var depthStencilDescriptor : DepthStencilDescriptor? = nil
    
    @usableFromInline
    var gpuCommandsStartIndexColor : Int? = nil
    @usableFromInline
    var gpuCommandsStartIndexDepthStencil : Int? = nil
    
    var nonDefaultDynamicState: DrawDynamicState = []

    init(commandRecorder: RenderGraphCommandRecorder, renderPass: DrawRenderPass, passRecord: RenderPassRecord) {
        self.drawRenderPass = renderPass
        self.renderTargetAttachmentUsages = HashMap(allocator: AllocatorType(commandRecorder.renderPassScratchAllocator))
        
        super.init(commandRecorder: commandRecorder, passRecord: passRecord)
        
        assert(passRecord.pass === renderPass)
        
        var needsClearCommand = false
        
        for (i, attachment) in renderPass.renderTargetsDescriptor.colorAttachments.enumerated() {
            guard let attachment = attachment else { continue }
            needsClearCommand = needsClearCommand || renderPass.colorClearOperation(attachmentIndex: i).isClear
            let usagePointers = self.commandRecorder.resourceUsagePointers(for: attachment.texture, slice: attachment.slice, level: attachment.level, encoder: self, usageType: renderPass.colorClearOperation(attachmentIndex: i).isClear ? .writeOnlyRenderTarget : .unusedRenderTarget, stages: .fragment, isIndirectlyBound: false, firstCommandOffset: 0)
            assert(usagePointers.count == 1, "There shouldn't be any subresources for a render target texture usage")
            let usagePointer = usagePointers.first!
            self.renderTargetAttachmentUsages[.color(i)] = usagePointer
        }
        
        if let depthAttachment = renderPass.renderTargetsDescriptor.depthAttachment {
            needsClearCommand = needsClearCommand || renderPass.depthClearOperation.isClear
            let usagePointers = self.commandRecorder.resourceUsagePointers(for: depthAttachment.texture, slice: depthAttachment.slice, level: depthAttachment.level, encoder: self, usageType: renderPass.depthClearOperation.isClear ? .writeOnlyRenderTarget : .unusedRenderTarget, stages: .vertex, isIndirectlyBound: false, firstCommandOffset: 0)
            assert(usagePointers.count == 1, "There shouldn't be any subresources for a render target texture usage")
            let usagePointer = usagePointers.first!
            self.renderTargetAttachmentUsages[.depth] = usagePointer
        }
        
        if let stencilAttachment = renderPass.renderTargetsDescriptor.stencilAttachment {
            needsClearCommand = needsClearCommand || renderPass.stencilClearOperation.isClear
            let usagePointers = self.commandRecorder.resourceUsagePointers(for: stencilAttachment.texture, slice: stencilAttachment.slice, level: stencilAttachment.level, encoder: self, usageType: renderPass.stencilClearOperation.isClear ? .writeOnlyRenderTarget : .unusedRenderTarget, stages: .vertex, isIndirectlyBound: false, firstCommandOffset: 0)
            assert(usagePointers.count == 1, "There shouldn't be any subresources for a render target texture usage")
            let usagePointer = usagePointers.first!
            self.renderTargetAttachmentUsages[.stencil] = usagePointer
        }
        
        if needsClearCommand {
            // Insert a dummy command into the stream.
            // This is necessary since clearing a render target has effects that can be depended upon by later passes,
            // even when there are no other commands for the encoder.
            // Not having any commands breaks the fence/hazard management in the backends, so insert one here.
            self.commandRecorder.record(.clearRenderTargets)
        }
    }
    
    deinit {
        self.renderTargetAttachmentUsages.deinit()
    }
    
    @usableFromInline
    func updateColorAttachmentUsages(endingEncoding: Bool) {
        guard let gpuCommandsStartIndex = self.gpuCommandsStartIndexColor else {
            return
        }
        self.gpuCommandsStartIndexColor = nil
        
        guard let renderPipelineDescriptor = self.renderPipelineDescriptor else {
            assertionFailure("No render pipeline descriptor bound.")
            return
        }
        
        for (i, attachment) in drawRenderPass.renderTargetsDescriptor.colorAttachments.enumerated() {
            guard let attachment = attachment else { continue }
            
            defer {
                if endingEncoding, let resolveTexture = attachment.resolveTexture {
                    let _ = self.commandRecorder.resourceUsagePointers(for: attachment.texture, slice: attachment.slice, level: attachment.level, encoder: self, usageType: .readWriteRenderTarget, stages: .fragment, isIndirectlyBound: false, firstCommandOffset: self.lastGPUCommandIndex) // Mark the attachment as read for the resolve.
                    let _ = self.commandRecorder.resourceUsagePointers(for: resolveTexture, slice: attachment.resolveSlice, level: attachment.resolveLevel, encoder: self, usageType: .writeOnlyRenderTarget, stages: .fragment, isIndirectlyBound: false, firstCommandOffset: self.lastGPUCommandIndex) // Mark the resolve attachment as written to.
                }
            }
        
            guard renderPipelineDescriptor.writeMasks[i, default: []] != [] else {
                continue
            }
            
            let type : ResourceUsageType = renderPipelineDescriptor.blendStates[i] != nil ? .readWriteRenderTarget : .writeOnlyRenderTarget
            
            if let usagePointer = self.renderTargetAttachmentUsages[.color(i)] {
                switch (type, usagePointer.pointee.type) {
                case (.readWriteRenderTarget, _):
                    usagePointer.pointee.type = .readWriteRenderTarget
                case (_, .unusedRenderTarget):
                    usagePointer.pointee.type = type
                default:
                    break // No change necessary.
                }
                usagePointer.pointee.commandRange = Range(usagePointer.pointee.commandRange.lowerBound...self.lastGPUCommandIndex) // extend the usage's timeline
                
                if usagePointer.pointee.type.isRead {
                    self.commandRecorder.readResources.insert(attachment.texture.resourceForUsageTracking)
                }
                if usagePointer.pointee.type.isWrite {
                    self.commandRecorder.writtenResources.insert(attachment.texture.resourceForUsageTracking)
                }
                continue
            }
            
            let usagePointers = self.commandRecorder.resourceUsagePointers(for: attachment.texture, slice: attachment.slice, level: attachment.level, encoder: self, usageType: type, stages: .fragment, isIndirectlyBound: false, firstCommandOffset: gpuCommandsStartIndex)
            assert(usagePointers.count == 1, "There shouldn't be any subresources for a render target texture usage")
            let usagePointer = usagePointers.first!
            usagePointer.pointee.commandRange = Range(gpuCommandsStartIndex...self.lastGPUCommandIndex)
            self.renderTargetAttachmentUsages[.color(i)] = usagePointer
        }
    }
    
    @usableFromInline
    func updateDepthStencilAttachmentUsages(endingEncoding: Bool) {
        guard let gpuCommandsStartIndex = self.gpuCommandsStartIndexDepthStencil else {
            return
        }
        self.gpuCommandsStartIndexDepthStencil = nil
        
        guard let depthStencilDescriptor = self.depthStencilDescriptor else {
            return // No depth writes enabled, depth test always passes, no stencil tests.
        }
        
        depthCheck: if let depthAttachment = drawRenderPass.renderTargetsDescriptor.depthAttachment {
            let type : ResourceUsageType
            switch (depthStencilDescriptor.depthCompareFunction, depthStencilDescriptor.isDepthWriteEnabled) {
            case (.always, false):
                break depthCheck
            case (.always, true):
                type = .writeOnlyRenderTarget
            default:
                type = .readWriteRenderTarget // TODO: should we have a special readOnlyRenderTarget for e.g. depth writes disabled but depth comparison on?
            }
            
            if let usagePointer = self.renderTargetAttachmentUsages[.depth] {
                switch (type, usagePointer.pointee.type) {
                case (.readWriteRenderTarget, _):
                    usagePointer.pointee.type = .readWriteRenderTarget
                case (_, .unusedRenderTarget):
                    usagePointer.pointee.type = .writeOnlyRenderTarget
                default:
                    break // No change necessary.
                }
                usagePointer.pointee.commandRange = Range(usagePointer.pointee.commandRange.lowerBound...self.lastGPUCommandIndex) // extend the usage's timeline
                if usagePointer.pointee.type.isRead {
                    self.commandRecorder.readResources.insert(depthAttachment.texture.resourceForUsageTracking)
                }
                if usagePointer.pointee.type.isWrite {
                    self.commandRecorder.writtenResources.insert(depthAttachment.texture.resourceForUsageTracking)
                }
                break depthCheck
            }
            
            let usagePointers = self.commandRecorder.resourceUsagePointers(for: depthAttachment.texture, slice: depthAttachment.slice, level: depthAttachment.level, encoder: self, usageType: type, stages: [.vertex, .fragment], isIndirectlyBound: false, firstCommandOffset: gpuCommandsStartIndex)
            assert(usagePointers.count == 1, "There shouldn't be any subresources for a render target texture usage")
            let usagePointer = usagePointers.first!
            usagePointer.pointee.commandRange = Range(gpuCommandsStartIndex...self.lastGPUCommandIndex)
            self.renderTargetAttachmentUsages[.depth] = usagePointer
            
            if endingEncoding, let resolveTexture = depthAttachment.resolveTexture {
                let _ = self.commandRecorder.resourceUsagePointers(for: depthAttachment.texture, slice: depthAttachment.slice, level: depthAttachment.level, encoder: self, usageType: .readWriteRenderTarget, stages: .fragment, isIndirectlyBound: false, firstCommandOffset: self.lastGPUCommandIndex) // Mark the attachment as read for the resolve.
                let _ = self.commandRecorder.resourceUsagePointers(for: resolveTexture, slice: depthAttachment.resolveSlice, level: depthAttachment.resolveLevel, encoder: self, usageType: .writeOnlyRenderTarget, stages: .fragment, isIndirectlyBound: false, firstCommandOffset: self.lastGPUCommandIndex) // Mark the resolve attachment as written to.
            }
        }
        
        stencilCheck: if let stencilAttachment = drawRenderPass.renderTargetsDescriptor.stencilAttachment {
            let isRead = depthStencilDescriptor.backFaceStencil.stencilCompareFunction != .always || depthStencilDescriptor.frontFaceStencil.stencilCompareFunction != .always
            let isWrite =   depthStencilDescriptor.backFaceStencil.stencilFailureOperation != .keep ||
                            depthStencilDescriptor.backFaceStencil.depthFailureOperation != .keep ||
                            depthStencilDescriptor.backFaceStencil.depthStencilPassOperation != .keep ||
                            depthStencilDescriptor.frontFaceStencil.stencilFailureOperation != .keep ||
                            depthStencilDescriptor.frontFaceStencil.depthFailureOperation != .keep ||
                            depthStencilDescriptor.frontFaceStencil.depthStencilPassOperation != .keep
            
            guard isRead || isWrite else { break stencilCheck }
            
            let type : ResourceUsageType = isRead ? .readWriteRenderTarget : .writeOnlyRenderTarget
            
            if let usagePointer = self.renderTargetAttachmentUsages[.stencil] {
                switch (type, usagePointer.pointee.type) {
                case (.readWriteRenderTarget, _):
                    usagePointer.pointee.type = .readWriteRenderTarget
                case (_, .unusedRenderTarget):
                    usagePointer.pointee.type = .writeOnlyRenderTarget
                default:
                    break // No change necessary.
                }
                usagePointer.pointee.commandRange = Range(usagePointer.pointee.commandRange.lowerBound...self.lastGPUCommandIndex) // extend the usage's timeline
                if usagePointer.pointee.type.isRead {
                    self.commandRecorder.readResources.insert(stencilAttachment.texture.resourceForUsageTracking)
                }
                if usagePointer.pointee.type.isWrite {
                    self.commandRecorder.writtenResources.insert(stencilAttachment.texture.resourceForUsageTracking)
                }
                break stencilCheck
            }
            
            let usagePointers = self.commandRecorder.resourceUsagePointers(for: stencilAttachment.texture, slice: stencilAttachment.slice, level: stencilAttachment.level, encoder: self, usageType: type, stages: [.vertex, .fragment], isIndirectlyBound: false, firstCommandOffset: gpuCommandsStartIndex)
            assert(usagePointers.count == 1, "There shouldn't be any subresources for a render target texture usage")
            let usagePointer = usagePointers.first!
            usagePointer.pointee.commandRange = Range(gpuCommandsStartIndex...self.lastGPUCommandIndex)
            self.renderTargetAttachmentUsages[.stencil] = usagePointer
            
            if endingEncoding, let resolveTexture = stencilAttachment.resolveTexture {
                let _ = self.commandRecorder.resourceUsagePointers(for: stencilAttachment.texture, slice: stencilAttachment.slice, level: stencilAttachment.level, encoder: self, usageType: .readWriteRenderTarget, stages: .fragment, isIndirectlyBound: false, firstCommandOffset: self.lastGPUCommandIndex) // Mark the attachment as read for the resolve.
                let _ = self.commandRecorder.resourceUsagePointers(for: resolveTexture, slice: stencilAttachment.resolveSlice, level: stencilAttachment.resolveLevel,  encoder: self, usageType: .writeOnlyRenderTarget, stages: .fragment, isIndirectlyBound: false, firstCommandOffset: self.lastGPUCommandIndex) // Mark the resolve attachment as written to.
            }
        }
    }
    
    /// The debug label for this render command encoder. Inferred from the render pass' name by default.
    public var label : String = "" {
        didSet {
            commandRecorder.setLabel(label)
        }
    }
    
    public func setRenderPipelineDescriptor(_ descriptor: RenderPipelineDescriptor, retainExistingBindings: Bool = true) async {
        if !retainExistingBindings {
            self.resetAllBindings()
        }
        
        self.renderPipelineDescriptor = descriptor
        self.currentPipelineReflection = await RenderBackend.renderPipelineReflection(descriptor: descriptor, renderTarget: self.drawRenderPass.renderTargetsDescriptor)
        
        self.pipelineStateChanged = true
        self.needsUpdateBindings = true
        
        self.updateColorAttachmentUsages(endingEncoding: false)
    }
    
    public func setVertexBuffer(_ buffer: Buffer?, offset: Int, index: Int) {
        if let currentBinding = self.boundVertexBuffers[index] {
            let lowerBound = currentBinding.pointee.commandRange.lowerBound
            // In normal execution, the last GPU command index should always be at least lowerBound.
            // However, if we don't have a valid pipeline state, it's possible that no GPU commands get executed;
            // in that case, we use max(lowerBound, self.lastGPUCommandIndex) to prevent the Swift stdlib from asserting.
            currentBinding.pointee.commandRange = Range(lowerBound...max(lowerBound, self.lastGPUCommandIndex))
        }
        
        guard let buffer = buffer else { return }
        
        let newUsageNodes = self.commandRecorder.resourceUsagePointers(for: buffer, bufferRange: offset..<buffer.length, encoder: self, usageType: .vertexBuffer, stages: .vertex, isIndirectlyBound: false, firstCommandOffset: self.nextCommandOffset)
        self.boundVertexBuffers[index] = newUsageNodes.first
        
        commandRecorder.record(RenderGraphCommand.setVertexBuffer, (buffer, UInt32(offset), UInt32(index)))
    }
    
    public func setVertexBufferOffset(_ offset: Int, index: Int) {
        commandRecorder.record(RenderGraphCommand.setVertexBufferOffset(offset: UInt32(offset), index: UInt32(index)))
    }

    public func setViewport(_ viewport: Viewport) {
        commandRecorder.record(RenderGraphCommand.setViewport, viewport)
        self.nonDefaultDynamicState.formUnion(.viewport)
    }
    
    public func setFrontFacing(_ frontFacingWinding: Winding) {
        commandRecorder.record(.setFrontFacing(frontFacingWinding))
        self.nonDefaultDynamicState.formUnion(.frontFacing)
    }
    
    public func setCullMode(_ cullMode: CullMode) {
        commandRecorder.record(.setCullMode(cullMode))
        self.nonDefaultDynamicState.formUnion(.cullMode)
    }
    
    public func setDepthStencilDescriptor(_ descriptor: DepthStencilDescriptor?) {
        guard self.drawRenderPass.renderTargetsDescriptor.depthAttachment != nil ||
            self.drawRenderPass.renderTargetsDescriptor.stencilAttachment != nil else {
                return
        }
        
        var descriptor = descriptor ?? DepthStencilDescriptor()
        if self.drawRenderPass.renderTargetsDescriptor.depthAttachment == nil {
            descriptor.depthCompareFunction = .always
            descriptor.isDepthWriteEnabled = false
        }
        if self.drawRenderPass.renderTargetsDescriptor.stencilAttachment == nil {
            descriptor.frontFaceStencil = .init()
            descriptor.backFaceStencil = .init()
        }
        
        self.depthStencilDescriptor = descriptor
        self.depthStencilStateChanged = true
        
        self.updateDepthStencilAttachmentUsages(endingEncoding: false)
    }
    
//    @inlinable
    public func setScissorRect(_ rect: ScissorRect) {
        commandRecorder.record(RenderGraphCommand.setScissorRect, rect)
        self.nonDefaultDynamicState.formUnion(.scissorRect)
    }
    
    public func setDepthBias(_ depthBias: Float, slopeScale: Float, clamp: Float) {
        commandRecorder.record(RenderGraphCommand.setDepthBias, (depthBias, slopeScale, clamp))
        self.nonDefaultDynamicState.formUnion(.depthBias)
    }
    
    public func setStencilReferenceValue(_ referenceValue: UInt32) {
        commandRecorder.record(.setStencilReferenceValue(referenceValue))
        self.nonDefaultDynamicState.formUnion(.stencilReferenceValue)
    }
    
    public func setStencilReferenceValues(front frontReferenceValue: UInt32, back backReferenceValue: UInt32) {
        commandRecorder.record(.setStencilReferenceValues(front: frontReferenceValue, back: backReferenceValue))
        self.nonDefaultDynamicState.formUnion(.stencilReferenceValue)
    }
    
    public func drawPrimitives(type primitiveType: PrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int = 1, baseInstance: Int = 0) {
        assert(instanceCount > 0, "instanceCount(\(instanceCount)) must be non-zero.")

        guard self.currentPipelineReflection != nil else {
            assert(self.renderPipelineDescriptor != nil, "No render or compute pipeline is set for pass \(renderPass.name).")
            return
        }

        self.updateResourceUsages()
        self.lastGPUCommandIndex = self.nextCommandOffset
        
        self.gpuCommandsStartIndexColor = self.gpuCommandsStartIndexColor ?? self.nextCommandOffset
        self.gpuCommandsStartIndexDepthStencil = self.gpuCommandsStartIndexDepthStencil ?? self.nextCommandOffset
        
        commandRecorder.record(RenderGraphCommand.drawPrimitives, (primitiveType, UInt32(vertexStart), UInt32(vertexCount), UInt32(instanceCount), UInt32(baseInstance)))
    }
    
    public func drawIndexedPrimitives(type primitiveType: PrimitiveType, indexCount: Int, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: Int, instanceCount: Int = 1, baseVertex: Int = 0, baseInstance: Int = 0) {
        assert(instanceCount > 0, "instanceCount(\(instanceCount)) must be non-zero.")
        
        guard self.currentPipelineReflection != nil else {
            assert(self.renderPipelineDescriptor != nil, "No render or compute pipeline is set for pass \(renderPass.name).")
            return
        }

        self.updateResourceUsages()
        self.lastGPUCommandIndex = self.nextCommandOffset
        
        self.gpuCommandsStartIndexColor = self.gpuCommandsStartIndexColor ?? self.nextCommandOffset
        self.gpuCommandsStartIndexDepthStencil = self.gpuCommandsStartIndexDepthStencil ?? self.nextCommandOffset
        self.commandRecorder.addResourceUsage(for: indexBuffer, bufferRange: indexBufferOffset..<indexBuffer.length, commandIndex: self.nextCommandOffset, encoder: self, usageType: .indexBuffer, stages: .vertex, isIndirectlyBound: false)
        
        commandRecorder.record(RenderGraphCommand.drawIndexedPrimitives, (primitiveType, UInt32(indexCount), indexType, indexBuffer, UInt32(indexBufferOffset), UInt32(instanceCount), Int32(baseVertex), UInt32(baseInstance)))
    }
    
    override func updateResourceUsages(endingEncoding: Bool = false) {
        if !endingEncoding {
            // Set the depth-stencil and pipeline states here to filter out unused states.
            if self.depthStencilStateChanged {
                let box = Unmanaged.passRetained(ReferenceBox(self.depthStencilDescriptor!))
                commandRecorder.addUnmanagedReference(box)
                commandRecorder.record(RenderGraphCommand.setDepthStencilDescriptor(box))
                self.depthStencilStateChanged = false
            }
            
            if self.pipelineStateChanged {
//                if let pipelineState = self.currentPipelineReflection.pipelineState {
//                    commandRecorder.record(RenderGraphCommand.setRenderPipelineState, (pipelineState, self.renderPipelineDescriptor?.fragmentFunction != nil, self.renderPipelineDescriptor?.fillMode ?? .fill))
//                } else {
                    let box = Unmanaged.passRetained(ReferenceBox(self.renderPipelineDescriptor!))
                    commandRecorder.addUnmanagedReference(box)
                    commandRecorder.record(RenderGraphCommand.setRenderPipelineDescriptor(box))
//                }
                // self.pipelineStateChanged = false // set by super.updateResourceUsages
            }
        }
        
        super.updateResourceUsages(endingEncoding: endingEncoding)
        
        if endingEncoding {
            for usagePointer in self.boundVertexBuffers {
                guard let usagePointer = usagePointer else { continue }
                if self.lastGPUCommandIndex > usagePointer.pointee.commandRange.lowerBound {
                    usagePointer.pointee.commandRange = Range(usagePointer.pointee.commandRange.lowerBound...self.lastGPUCommandIndex)
                }
            }
            
            self.updateColorAttachmentUsages(endingEncoding: endingEncoding)
            self.updateDepthStencilAttachmentUsages(endingEncoding: endingEncoding)
        }
    }
    
    @usableFromInline override func endEncoding() {
        // Reset any dynamic state to the defaults.
        let renderTargetSize = self.drawRenderPass.renderTargetsDescriptor.size
        if self.nonDefaultDynamicState.contains(.viewport) {
            commandRecorder.record(RenderGraphCommand.setViewport, Viewport(originX: 0.0, originY: 0.0, width: Double(renderTargetSize.width), height: Double(renderTargetSize.height), zNear: 0.0, zFar: 1.0))
        }
        if self.nonDefaultDynamicState.contains(.scissorRect) {
            commandRecorder.record(RenderGraphCommand.setScissorRect, ScissorRect(x: 0, y: 0, width: renderTargetSize.width, height: renderTargetSize.height))
        }
        if self.nonDefaultDynamicState.contains(.frontFacing) {
            commandRecorder.record(.setFrontFacing(.counterClockwise))
        }
        if self.nonDefaultDynamicState.contains(.cullMode) {
            commandRecorder.record(.setCullMode(.none))
        }
        if self.nonDefaultDynamicState.contains(.depthBias) {
            commandRecorder.record(RenderGraphCommand.setDepthBias, (depthBias: 0.0, slopeScale: 0.0, clamp: 0.0))
        }
        if self.nonDefaultDynamicState.contains(.stencilReferenceValue) {
            commandRecorder.record(.setStencilReferenceValue(0))
        }
        
        super.endEncoding()
    }
}


public class ComputeCommandEncoder : ResourceBindingEncoder {
    
    let computeRenderPass : ComputeRenderPass
    
    private var currentComputePipeline : ComputePipelineDescriptorBox? = nil
    
    init(commandRecorder: RenderGraphCommandRecorder, renderPass: ComputeRenderPass, passRecord: RenderPassRecord) {
        self.computeRenderPass = renderPass
        super.init(commandRecorder: commandRecorder, passRecord: passRecord)
        
        assert(passRecord.pass === renderPass)
    }
    
    public var label : String = "" {
        didSet {
            commandRecorder.setLabel(label)
        }
    }
    
    public func setComputePipelineDescriptor(_ descriptor: ComputePipelineDescriptor, retainExistingBindings: Bool = true) async {
        if !retainExistingBindings {
            self.resetAllBindings()
        }
        
        self.currentPipelineReflection = await RenderBackend.computePipelineReflection(descriptor: descriptor)
        
        self.pipelineStateChanged = true
        self.needsUpdateBindings = true

        let pipelineBox = ComputePipelineDescriptorBox(descriptor)
        self.currentComputePipeline = pipelineBox
        
        let box = Unmanaged.passRetained(pipelineBox)
        commandRecorder.addUnmanagedReference(box)
        commandRecorder.record(.setComputePipelineDescriptor(box))
    }
    
    /// The number of threads in a SIMD group/wave for the current pipeline state.
    public var currentThreadExecutionWidth: Int {
        return self.currentPipelineReflection?.threadExecutionWidth ?? 0
    }
    
    public func setStageInRegion(_ region: Region) {
        commandRecorder.record(RenderGraphCommand.setStageInRegion, region)
    }
    
    public func setThreadgroupMemoryLength(_ length: Int, index: Int) {
        commandRecorder.record(.setThreadgroupMemoryLength(length: UInt32(length), index: UInt32(index)))
    }
    
    @usableFromInline
    func updateThreadgroupExecutionWidth(threadsPerThreadgroup: Size) {
        let threads = threadsPerThreadgroup.width * threadsPerThreadgroup.height * threadsPerThreadgroup.depth
        let isMultiple = threads % self.currentThreadExecutionWidth == 0
        self.currentComputePipeline!.threadGroupSizeIsMultipleOfThreadExecutionWidth = self.currentComputePipeline!.threadGroupSizeIsMultipleOfThreadExecutionWidth && isMultiple
    }

    public func dispatchThreads(_ threadsPerGrid: Size, threadsPerThreadgroup: Size) {
        guard self.currentPipelineReflection != nil else {
            assert(self.currentComputePipeline != nil, "No compute pipeline is set for pass \(renderPass.name).")
            return
        }
        precondition(threadsPerGrid.width > 0 && threadsPerGrid.height > 0 && threadsPerGrid.depth > 0)
        precondition(threadsPerThreadgroup.width > 0 && threadsPerThreadgroup.height > 0 && threadsPerThreadgroup.depth > 0)
        
        self.needsUpdateBindings = true // to track barriers between resources bound for the compute command

        self.updateThreadgroupExecutionWidth(threadsPerThreadgroup: threadsPerThreadgroup)
        self.updateResourceUsages()
        self.lastGPUCommandIndex = self.nextCommandOffset
        
        commandRecorder.record(RenderGraphCommand.dispatchThreads, (threadsPerGrid, threadsPerThreadgroup))
    }
    
    public func dispatchThreadgroups(_ threadgroupsPerGrid: Size, threadsPerThreadgroup: Size) {
        guard self.currentPipelineReflection != nil else {
            assert(self.currentComputePipeline != nil, "No compute pipeline is set for pass \(renderPass.name).")
            return
        }
        precondition(threadgroupsPerGrid.width > 0 && threadgroupsPerGrid.height > 0 && threadgroupsPerGrid.depth > 0)
        precondition(threadsPerThreadgroup.width > 0 && threadsPerThreadgroup.height > 0 && threadsPerThreadgroup.depth > 0)
        
        self.needsUpdateBindings = true // to track barriers between resources bound for the compute command
        
        self.updateThreadgroupExecutionWidth(threadsPerThreadgroup: threadsPerThreadgroup)
        self.updateResourceUsages()
        self.lastGPUCommandIndex = self.nextCommandOffset
        
        commandRecorder.record(RenderGraphCommand.dispatchThreadgroups, (threadgroupsPerGrid, threadsPerThreadgroup))
    }
    
    public func dispatchThreadgroups(indirectBuffer: Buffer, indirectBufferOffset: Int, threadsPerThreadgroup: Size) {
        guard self.currentPipelineReflection != nil else {
            assert(self.currentComputePipeline != nil, "No compute pipeline is set for pass \(renderPass.name).")
            return
        }
        precondition(threadsPerThreadgroup.width > 0 && threadsPerThreadgroup.height > 0 && threadsPerThreadgroup.depth > 0)
        
        self.needsUpdateBindings = true // to track barriers between resources bound for the compute command
        
        self.updateThreadgroupExecutionWidth(threadsPerThreadgroup: threadsPerThreadgroup)
        self.updateResourceUsages()
        self.lastGPUCommandIndex = self.nextCommandOffset
        
        self.commandRecorder.addResourceUsage(for: indirectBuffer, bufferRange: indirectBufferOffset..<(indirectBufferOffset + 3 * MemoryLayout<UInt32>.stride), commandIndex: self.nextCommandOffset, encoder: self, usageType: .indirectBuffer, stages: .compute, isIndirectlyBound: false)
        
        commandRecorder.record(RenderGraphCommand.dispatchThreadgroupsIndirect, (indirectBuffer, UInt32(indirectBufferOffset), threadsPerThreadgroup))
    }
}

public class BlitCommandEncoder : CommandEncoder {

    @usableFromInline let commandRecorder : RenderGraphCommandRecorder
    @usableFromInline let passRecord: RenderPassRecord
    @usableFromInline let startCommandIndex: Int
    let blitRenderPass : BlitRenderPass
    
    init(commandRecorder: RenderGraphCommandRecorder, renderPass: BlitRenderPass, passRecord: RenderPassRecord) {
        self.commandRecorder = commandRecorder
        self.blitRenderPass = renderPass
        self.passRecord = passRecord
        self.startCommandIndex = self.commandRecorder.nextCommandIndex
        
        assert(passRecord.pass === renderPass)
        
#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
        self.pushDebugGroup(passRecord.name)
#endif
    }
    
    @usableFromInline func endEncoding() {
#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
        self.popDebugGroup() // Pass Name
#endif
    }
    
    public var label : String = "" {
        didSet {
            commandRecorder.setLabel(label)
        }
    }
    
    public func copy(from sourceBuffer: Buffer, sourceOffset: Int, sourceBytesPerRow: Int, sourceBytesPerImage: Int, sourceSize: Size, to destinationTexture: Texture, destinationSlice: Int, destinationLevel: Int, destinationOrigin: Origin, options: BlitOption = []) {
        assert(sourceBuffer.length - sourceOffset >= sourceSize.height * sourceBytesPerRow)
        let commandOffset = self.nextCommandOffset
        
        commandRecorder.addResourceUsage(for: sourceBuffer, bufferRange: sourceOffset..<(sourceOffset + sourceSize.height * sourceBytesPerRow), commandIndex: commandOffset, encoder: self, usageType: .blitSource, stages: .blit, isIndirectlyBound: false)
        commandRecorder.addResourceUsage(for: destinationTexture, slice: destinationSlice, level: destinationLevel, commandIndex: commandOffset, encoder: self, usageType: .blitDestination, stages: .blit, isIndirectlyBound: false)
        
        commandRecorder.record(RenderGraphCommand.copyBufferToTexture, (sourceBuffer, UInt32(sourceOffset), UInt32(sourceBytesPerRow), UInt32(sourceBytesPerImage), sourceSize, destinationTexture, UInt32(destinationSlice), UInt32(destinationLevel), destinationOrigin, options))
    }
    
    public func copy(from sourceBuffer: Buffer, sourceOffset: Int, to destinationBuffer: Buffer, destinationOffset: Int, size: Int) {
        let commandOffset = self.nextCommandOffset
        
        commandRecorder.addResourceUsage(for: sourceBuffer, bufferRange: sourceOffset..<(sourceOffset + size), commandIndex: commandOffset, encoder: self, usageType: .blitSource, stages: .blit, isIndirectlyBound: false)
        commandRecorder.addResourceUsage(for: destinationBuffer, bufferRange: destinationOffset..<(destinationOffset + size), commandIndex: commandOffset, encoder: self, usageType: .blitDestination, stages: .blit, isIndirectlyBound: false)
        
        commandRecorder.record(RenderGraphCommand.copyBufferToBuffer, (sourceBuffer, UInt32(sourceOffset), destinationBuffer, UInt32(destinationOffset), UInt32(size)))
    }
    
    public func copy(from sourceTexture: Texture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: Origin, sourceSize: Size, to destinationBuffer: Buffer, destinationOffset: Int, destinationBytesPerRow: Int, destinationBytesPerImage: Int, options: BlitOption = []) {
        let commandOffset = self.nextCommandOffset
        
        commandRecorder.addResourceUsage(for: sourceTexture, slice: sourceSlice, level: sourceLevel, commandIndex: commandOffset, encoder: self, usageType: .blitSource, stages: .blit, isIndirectlyBound: false)
        commandRecorder.addResourceUsage(for: destinationBuffer, bufferRange: destinationOffset..<(destinationOffset + destinationBytesPerImage), commandIndex: commandOffset, encoder: self, usageType: .blitDestination, stages: .blit, isIndirectlyBound: false)
        
        commandRecorder.record(RenderGraphCommand.copyTextureToBuffer, (sourceTexture, UInt32(sourceSlice), UInt32(sourceLevel), sourceOrigin, sourceSize, destinationBuffer, UInt32(destinationOffset), UInt32(destinationBytesPerRow), UInt32(destinationBytesPerImage), options))
    }
    
    public func copy(from sourceTexture: Texture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: Origin, sourceSize: Size, to destinationTexture: Texture, destinationSlice: Int, destinationLevel: Int, destinationOrigin: Origin) {
        let commandOffset = self.nextCommandOffset
        
        commandRecorder.addResourceUsage(for: sourceTexture, slice: sourceSlice, level: sourceLevel, commandIndex: commandOffset, encoder: self, usageType: .blitSource, stages: .blit, isIndirectlyBound: false)
        commandRecorder.addResourceUsage(for: destinationTexture, slice: destinationSlice, level: destinationLevel, commandIndex: commandOffset, encoder: self, usageType: .blitDestination, stages: .blit, isIndirectlyBound: false)
        
        commandRecorder.record(RenderGraphCommand.copyTextureToTexture, (sourceTexture, UInt32(sourceSlice), UInt32(sourceLevel), sourceOrigin, sourceSize, destinationTexture, UInt32(destinationSlice), UInt32(destinationLevel), destinationOrigin))
    }
    
    public func fill(buffer: Buffer, range: Range<Int>, value: UInt8) {
        commandRecorder.addResourceUsage(for: buffer, bufferRange: range, commandIndex: self.nextCommandOffset, encoder: self, usageType: .blitDestination, stages: .blit, isIndirectlyBound: false)
        
        commandRecorder.record(RenderGraphCommand.fillBuffer, (buffer, range, value))
    }
    
    public func generateMipmaps(for texture: Texture) {
        guard texture.descriptor.mipmapLevelCount > 1 else { return }
        #if canImport(Metal)
        if RenderBackend._backend is MetalBackend {
            commandRecorder.addResourceUsage(for: texture, slice: nil, level: nil, commandIndex: self.nextCommandOffset, encoder: self, usageType: .mipGeneration, stages: .blit, isIndirectlyBound: false)
            commandRecorder.record(.generateMipmaps(texture))
            return
        }
        #endif
        for slice in 0..<texture.descriptor.slicesPerLevel {
            for destLevel in 1..<texture.descriptor.mipmapLevelCount {
                let sourceLevel = destLevel - 1
                commandRecorder.addResourceUsage(for: texture, slice: slice, level: sourceLevel, commandIndex: self.nextCommandOffset, encoder: self, usageType: .blitSource, stages: .blit, isIndirectlyBound: false)
                commandRecorder.addResourceUsage(for: texture, slice: slice, level: destLevel, commandIndex: self.nextCommandOffset, encoder: self, usageType: .blitDestination, stages: .blit, isIndirectlyBound: false)
                let args: RenderGraphCommand.BlitTextureToTextureArgs = (texture, UInt32(slice), UInt32(sourceLevel), Origin(), texture.descriptor.size(mipLevel: sourceLevel), texture, UInt32(slice), UInt32(destLevel), Origin(), texture.descriptor.size(mipLevel: destLevel), .linear)
                commandRecorder.record(RenderGraphCommand.blitTextureToTexture, args)
            }
        }
    }
    
    public func synchronize(buffer: Buffer) {
        commandRecorder.addResourceUsage(for: buffer, bufferRange: buffer.range, commandIndex: self.nextCommandOffset, encoder: self, usageType: .blitSynchronisation, stages: .blit, isIndirectlyBound: false)
        
        commandRecorder.record(.synchroniseBuffer(buffer))
    }
    
    public func synchronize(texture: Texture) {
        commandRecorder.addResourceUsage(for: texture, slice: nil, level: nil, commandIndex: self.nextCommandOffset, encoder: self, usageType: .blitSynchronisation, stages: .blit, isIndirectlyBound: false)
        commandRecorder.record(.synchroniseTexture(texture))
    }
    
    public func synchronize(texture: Texture, slice: Int, level: Int) {
        commandRecorder.addResourceUsage(for: texture, slice: slice, level: level, commandIndex: self.nextCommandOffset, encoder: self, usageType: .blitSynchronisation, stages: .blit, isIndirectlyBound: false)
        commandRecorder.record(RenderGraphCommand.synchroniseTextureSlice, (texture, UInt32(slice), UInt32(level)))
    }
}

public final class ExternalCommandEncoder : CommandEncoder {
    
    @usableFromInline let commandRecorder : RenderGraphCommandRecorder
    @usableFromInline let passRecord: RenderPassRecord
    @usableFromInline let startCommandIndex: Int
    let externalRenderPass : ExternalRenderPass
    
    init(commandRecorder: RenderGraphCommandRecorder, renderPass: ExternalRenderPass, passRecord: RenderPassRecord) {
        self.commandRecorder = commandRecorder
        self.externalRenderPass = renderPass
        self.passRecord = passRecord
        self.startCommandIndex = self.commandRecorder.nextCommandIndex
        
        assert(passRecord.pass === renderPass)
        
#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
        self.pushDebugGroup(passRecord.name)
#endif
    }
    
    @usableFromInline func endEncoding() {
#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
        self.popDebugGroup() // Pass Name
#endif
    }
    
    public var label : String = "" {
        didSet {
            commandRecorder.setLabel(label)
        }
    }
    
    func encodeCommand(usingResources resources: [(Resource, ResourceUsageType, ActiveResourceRange)], _ command: @escaping (_ commandBuffer: UnsafeRawPointer) -> Void) {
        let commandBox = Unmanaged.passRetained(ExternalCommandBox(command: command))
        self.commandRecorder.addUnmanagedReference(commandBox)
        
        for (resource, usageType, activeRange) in resources {
            _ = commandRecorder.resourceUsagePointers(for: resource, encoder: self, usageType: usageType, stages: .compute, activeRange: activeRange, isIndirectlyBound: false, firstCommandOffset: self.nextCommandOffset)
        }
        
        commandRecorder.record(RenderGraphCommand.encodeExternalCommand(commandBox))
    }
    
    #if canImport(Metal)
    
    public func encodeToMetalCommandBuffer(usingResources resources: [(Resource, ResourceUsageType, ActiveResourceRange)], _ command: @escaping (_ commandBuffer: MTLCommandBuffer) -> Void) {
        self.encodeCommand(usingResources: resources, { (cmdBuffer) in
            command(Unmanaged<MTLCommandBuffer>.fromOpaque(cmdBuffer).takeUnretainedValue())
        })
    }
    
    #endif
    
    #if canImport(MetalPerformanceShaders)
    
    @available(OSX 10.14, *)
    public func encodeRayIntersection(intersector: MPSRayIntersector, intersectionType: MPSIntersectionType, rayBuffer: Buffer, rayBufferOffset: Int, intersectionBuffer: Buffer, intersectionBufferOffset: Int, rayCount: Int, accelerationStructure: MPSAccelerationStructure) {
        
        let intersector = Unmanaged.passRetained(intersector)
        self.commandRecorder.addUnmanagedReference(intersector)
        
        let accelerationStructure = Unmanaged.passRetained(accelerationStructure)
        self.commandRecorder.addUnmanagedReference(accelerationStructure)
        
        commandRecorder.addResourceUsage(for: rayBuffer, bufferRange: rayBufferOffset..<(rayBufferOffset + rayCount * MemoryLayout<MPSRayOriginMinDistanceDirectionMaxDistance>.stride), commandIndex: self.nextCommandOffset, encoder: self, usageType: .read, stages: .compute, isIndirectlyBound: false)
        commandRecorder.addResourceUsage(for: intersectionBuffer, bufferRange: intersectionBufferOffset..<(intersectionBufferOffset + rayCount * MemoryLayout<MPSIntersectionDistancePrimitiveIndexInstanceIndexCoordinates>.stride), commandIndex: self.nextCommandOffset, encoder: self, usageType: .write, stages: .compute, isIndirectlyBound: false)
        
        commandRecorder.record(RenderGraphCommand.encodeRayIntersection, (intersector, intersectionType, rayBuffer, rayBufferOffset, intersectionBuffer, intersectionBufferOffset, rayCount, accelerationStructure))
    }
    
    @available(OSX 10.14, *)
    public func encodeRayIntersection(intersector: MPSRayIntersector, intersectionType: MPSIntersectionType, rayBuffer: Buffer, rayBufferOffset: Int, intersectionBuffer: Buffer, intersectionBufferOffset: Int, rayCountBuffer: Buffer, rayCountBufferOffset: Int, accelerationStructure: MPSAccelerationStructure) {
        
        let intersector = Unmanaged.passRetained(intersector)
        self.commandRecorder.addUnmanagedReference(intersector)
        
        let accelerationStructure = Unmanaged.passRetained(accelerationStructure)
        self.commandRecorder.addUnmanagedReference(accelerationStructure)
        
        commandRecorder.addResourceUsage(for: rayBuffer, bufferRange: rayBufferOffset..<rayBuffer.length, commandIndex: self.nextCommandOffset, encoder: self, usageType: .read, stages: .compute, isIndirectlyBound: false)
        commandRecorder.addResourceUsage(for: intersectionBuffer, bufferRange: intersectionBufferOffset..<intersectionBuffer.length, commandIndex: self.nextCommandOffset, encoder: self, usageType: .write, stages: .compute, isIndirectlyBound: false)
        commandRecorder.addResourceUsage(for: rayCountBuffer, bufferRange: rayCountBufferOffset..<(rayCountBufferOffset + MemoryLayout<UInt32>.stride), commandIndex: self.nextCommandOffset, encoder: self, usageType: .read, stages: .compute, isIndirectlyBound: false)
        
        commandRecorder.record(RenderGraphCommand.encodeRayIntersectionRayCountBuffer, (intersector, intersectionType, rayBuffer, rayBufferOffset, intersectionBuffer, intersectionBufferOffset, rayCountBuffer, rayCountBufferOffset, accelerationStructure))
    }
    
    #endif
}

@available(macOS 11.0, iOS 14.0, *)
public class AccelerationStructureCommandEncoder : CommandEncoder {
    
    @usableFromInline let commandRecorder : RenderGraphCommandRecorder
    @usableFromInline let passRecord: RenderPassRecord
    @usableFromInline let startCommandIndex: Int
    let accelerationStructureRenderPass : AccelerationStructureRenderPass
    
    init(commandRecorder: RenderGraphCommandRecorder, accelerationStructureRenderPass: AccelerationStructureRenderPass, passRecord: RenderPassRecord) {
        self.commandRecorder = commandRecorder
        self.accelerationStructureRenderPass = accelerationStructureRenderPass
        self.passRecord = passRecord
        self.startCommandIndex = self.commandRecorder.nextCommandIndex
        
        assert(passRecord.pass === renderPass)
        
        self.pushDebugGroup(passRecord.name)
    }
    
    @usableFromInline func endEncoding() {
        self.popDebugGroup() // Pass Name
    }
    
    public var label : String = "" {
        didSet {
            commandRecorder.setLabel(label)
        }
    }
    
    public func build(accelerationStructure: AccelerationStructure, descriptor: AccelerationStructureDescriptor, scratchBuffer: Buffer, scratchBufferOffset: Int) {
        accelerationStructure.descriptor = descriptor
        commandRecorder.addResourceUsage(for: accelerationStructure, commandIndex: self.nextCommandOffset, encoder: self, usageType: .write, stages: .compute, isIndirectlyBound: false)
        commandRecorder.addResourceUsage(for: scratchBuffer, bufferRange: scratchBufferOffset..<scratchBuffer.length, commandIndex: self.nextCommandOffset, encoder: self, usageType: .readWrite, stages: .compute, isIndirectlyBound: false)
        commandRecorder.record(RenderGraphCommand.buildAccelerationStructure, (accelerationStructure, descriptor, scratchBuffer, scratchBufferOffset))
    }
    
    
    public func build(accelerationStructure: AccelerationStructure, descriptor: AccelerationStructureDescriptor) {
        let scratchBuffer = Buffer(length: descriptor.sizes.buildScratchBufferSize, storageMode: .private)
        self.build(accelerationStructure: accelerationStructure, descriptor: descriptor, scratchBuffer: scratchBuffer, scratchBufferOffset: 0)
    }

    public func refit(sourceAccelerationStructure: AccelerationStructure, descriptor: AccelerationStructureDescriptor, destinationAccelerationStructure: AccelerationStructure?, scratchBuffer: Buffer, scratchBufferOffset: Int) {
        
        if let destinationStructure = destinationAccelerationStructure {
            sourceAccelerationStructure.descriptor = nil
            destinationStructure.descriptor = descriptor
            commandRecorder.addResourceUsage(for: destinationStructure, commandIndex: self.nextCommandOffset, encoder: self, usageType: .write, stages: .compute, isIndirectlyBound: false)
        } else {
            sourceAccelerationStructure.descriptor = descriptor
        }
        
        commandRecorder.addResourceUsage(for: sourceAccelerationStructure, commandIndex: self.nextCommandOffset, encoder: self, usageType: .read, stages: .compute, isIndirectlyBound: false)
        commandRecorder.addResourceUsage(for: scratchBuffer, bufferRange: scratchBufferOffset..<scratchBuffer.length, commandIndex: self.nextCommandOffset, encoder: self, usageType: .readWrite, stages: .compute, isIndirectlyBound: false)
        
        commandRecorder.record(RenderGraphCommand.refitAccelerationStructure, (sourceAccelerationStructure, descriptor, destinationAccelerationStructure, scratchBuffer, scratchBufferOffset))
    }
    
    
    public func refit(sourceAccelerationStructure: AccelerationStructure, descriptor: AccelerationStructureDescriptor, destinationAccelerationStructure: AccelerationStructure?) {
        let scratchBuffer = Buffer(length: descriptor.sizes.refitScratchBufferSize, storageMode: .private)
        self.refit(sourceAccelerationStructure: sourceAccelerationStructure, descriptor: descriptor, destinationAccelerationStructure: destinationAccelerationStructure, scratchBuffer: scratchBuffer, scratchBufferOffset: 0)
    }
    
    public func copy(sourceAccelerationStructure: AccelerationStructure, destinationAccelerationStructure: AccelerationStructure) {
        commandRecorder.addResourceUsage(for: sourceAccelerationStructure, commandIndex: self.nextCommandOffset, encoder: self, usageType: .read, stages: .compute, isIndirectlyBound: false)
        commandRecorder.addResourceUsage(for: destinationAccelerationStructure, commandIndex: self.nextCommandOffset, encoder: self, usageType: .write, stages: .compute, isIndirectlyBound: false)
        
        commandRecorder.record(RenderGraphCommand.copyAccelerationStructure, (sourceAccelerationStructure, destinationAccelerationStructure))
        
        destinationAccelerationStructure.descriptor = sourceAccelerationStructure.descriptor
    }

        // vkCmdWriteAccelerationStructuresPropertiesKHR
    public func writeCompactedSize(of accelerationStructure: AccelerationStructure, to buffer: Buffer, offset: Int) {
        commandRecorder.addResourceUsage(for: accelerationStructure, commandIndex: self.nextCommandOffset, encoder: self, usageType: .read, stages: .compute, isIndirectlyBound: false)
        commandRecorder.addResourceUsage(for: buffer, bufferRange: offset..<(offset + MemoryLayout<UInt32>.stride), commandIndex: self.nextCommandOffset, encoder: self, usageType: .write, stages: .compute, isIndirectlyBound: false)
        
        commandRecorder.record(RenderGraphCommand.writeCompactedAccelerationStructureSize, (accelerationStructure, buffer, offset))
    }

        
    public func copyAndCompact(sourceAccelerationStructure: AccelerationStructure, destinationAccelerationStructure: AccelerationStructure) {
        commandRecorder.addResourceUsage(for: sourceAccelerationStructure, commandIndex: self.nextCommandOffset, encoder: self, usageType: .read, stages: .compute, isIndirectlyBound: false)
        commandRecorder.addResourceUsage(for: destinationAccelerationStructure, commandIndex: self.nextCommandOffset, encoder: self, usageType: .write, stages: .compute, isIndirectlyBound: false)
        
        commandRecorder.record(RenderGraphCommand.copyAndCompactAccelerationStructure, (sourceAccelerationStructure, destinationAccelerationStructure))
        
        destinationAccelerationStructure.descriptor = sourceAccelerationStructure.descriptor
    }

}
