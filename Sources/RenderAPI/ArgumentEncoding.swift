//
//  ArgumentEncoder.swift
//  RenderAPI
//
//  Created by Thomas Roughton on 22/02/18.
//

import Foundation

public protocol FunctionArgumentKey {
    var stringValue : String { get }
    var bindingPath : ResourceBindingPath? { get }
}

public struct FunctionArgumentCodingKey : FunctionArgumentKey {
    public let codingKey : CodingKey
    
    public init(_ codingKey: CodingKey) {
        self.codingKey = codingKey
    }
    
    public var stringValue: String {
        return self.codingKey.stringValue
    }
}

extension FunctionArgumentKey {
    
    public var bindingPath : ResourceBindingPath? {
        return nil
    }
    
    public func bindingPath(argumentBufferPath: ResourceBindingPath?, arrayIndex: Int) -> ResourceBindingPath? {
        return self.bindingPath ?? RenderBackend.bindingPath(argumentName: self.stringValue, arrayIndex: arrayIndex, argumentBufferPath: argumentBufferPath)
    }
    
    public var computedBindingPath : ResourceBindingPath? {
        return self.bindingPath ?? RenderBackend.bindingPath(argumentName: self.stringValue, arrayIndex: 0, argumentBufferPath: nil)
    }
}

extension String : FunctionArgumentKey {
    public var stringValue : String {
        return self
    }
}

public class ArgumentBuffer : Resource {
    public enum ArgumentResource {
        case buffer(Buffer, offset: Int)
        case texture(Texture)
        case sampler(SamplerDescriptor)
        case bytes(offset: Int, length: Int)
    }
    
    fileprivate lazy var bytes = Data()
    public fileprivate(set) var enqueuedBindings = [(FunctionArgumentKey, Int, ArgumentResource)]()
    public var bindings = [(ResourceBindingPath, ArgumentResource)]()
    
    public override init(flags: ResourceFlags) {
        super.init(flags: flags)
    }
    
    public func translateEnqueuedBindings(_ closure: (FunctionArgumentKey, Int, ArgumentResource) -> ResourceBindingPath?) {
        var unhandledBindings = [(FunctionArgumentKey, Int, ArgumentResource)]()
        
        while let (key, arrayIndex, binding) = self.enqueuedBindings.popLast() {
            if let bindingPath = closure(key, arrayIndex, binding) {
                self.bindings.append((bindingPath, binding))
            } else {
                unhandledBindings.append((key, arrayIndex, binding))
            }
        }
        
        self.enqueuedBindings = unhandledBindings
    }
    
    public func bytes(offset: Int) -> UnsafeRawPointer {
        return self.bytes.withUnsafeBytes {
            return UnsafeRawPointer($0) + offset
        }
    }
}

public final class TypedArgumentBuffer<K : FunctionArgumentKey> : ArgumentBuffer {
    
    public func setBuffer(_ buffer: Buffer, offset: Int, key: K) {
        assert(!self.flags.contains(.persistent) || buffer.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        self.enqueuedBindings.append(
            (key, 0, .buffer(buffer, offset: offset))
        )
    }
    
    public func setTexture(_ texture: Texture, key: K, arrayIndex: Int = 0) {
        assert(!self.flags.contains(.persistent) || texture.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        self.enqueuedBindings.append(
            (key, arrayIndex, .texture(texture))
        )
    }
    
    public func setSampler(_ sampler: SamplerDescriptor, key: K, arrayIndex: Int = 0) {
        self.enqueuedBindings.append(
            (key, 0, .sampler(sampler))
        )
    }
    
    public func setValue<T>(_ value: T, key: K) {
        var value = value
        withUnsafeBytes(of: &value) { bufferPointer in
            self.setBytes(bufferPointer.baseAddress!, length: bufferPointer.count, for: key)
        }
    }
    
    public func setBytes(_ bytes: UnsafeRawPointer, length: Int, for key: K) {
        let currentOffset = self.bytes.count
        self.bytes.append(bytes.assumingMemoryBound(to: UInt8.self), count: length)
        self.enqueuedBindings.append(
            (key, 0, .bytes(offset: currentOffset, length: length))
        )
    }
}

extension TypedArgumentBuffer {
    
    public func setBuffers(_ buffers: [Buffer], offsets: [Int], keys: [K]) {
        for (buffer, (offset, key)) in zip(buffers, zip(offsets, keys)) {
            self.setBuffer(buffer, offset: offset, key: key)
        }
    }
    
    public func setTextures(_ textures: [Texture], keys: [K]) {
        for (texture, key) in zip(textures, keys) {
            self.setTexture(texture, key: key)
        }
    }
    
    public func setSamplers(_ samplers: [SamplerDescriptor], keys: [K]) {
        for (sampler, key) in zip(samplers, keys) {
            self.setSampler(sampler, key: key)
        }
    }
}
