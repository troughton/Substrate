//
//  ArgumentEncoder.swift
//  FrameGraph
//
//  Created by Thomas Roughton on 19/12/17.
//  Copyright © 2017 Team Llama. All rights reserved.
//

public struct BufferView : Encodable {
    public var buffer : Buffer
    public var offset : Int
    
    public init(into buffer: Buffer, offset: Int) {
        self.buffer = buffer
        self.offset = offset
    }
}

extension Buffer : Encodable {
    public func encode(to encoder: Encoder) throws {
        fatalError("Buffer.encode(to:) should never be called directly.")
    }
}

extension Texture : Encodable {
    public func encode(to encoder: Encoder) throws {
        fatalError("Texture.encode(to:) should never be called directly.")
    }
}

extension SamplerDescriptor : Encodable {
    public func encode(to encoder: Encoder) throws {
        fatalError("SamplerDescriptor.encode(to:) should never be called directly.")
    }
}

open class FunctionArgumentEncoder<CE : ResourceBindingEncoder> : Encoder {
    /// Contextual user-provided information for use during encoding.
    open var userInfo: [CodingUserInfoKey : Any] = [:]
    
    let commandEncoder : CE
    public var codingPath: [CodingKey] = []
    
    public init(commandEncoder: CE) {
        self.commandEncoder = commandEncoder
    }
    
    // MARK: - Encoding Values
    
    open func encode<T : Encodable>(_ value: T) throws {
        try value.encode(to: self)
    }
    
    // MARK: - Encoder Methods
    public func container<Key>(keyedBy: Key.Type) -> KeyedEncodingContainer<Key> {
        let container = _FunctionArgumentKeyedEncodingContainer<Key, CE>(referencing: self, codingPath: self.codingPath)
        return KeyedEncodingContainer(container)
    }
    
    public func unkeyedContainer() -> UnkeyedEncodingContainer {
        fatalError("Unkeyed containers are unsupported.")
    }
    
    public func singleValueContainer() -> SingleValueEncodingContainer {
        fatalError()
    }
}

// MARK: - Encoding Containers

fileprivate struct _FunctionArgumentKeyedEncodingContainer<K : CodingKey, CE : ResourceBindingEncoder> : KeyedEncodingContainerProtocol {
    typealias Key = K
    
    // MARK: Properties
    
    /// A reference to the encoder we're writing to.
    private let encoder: FunctionArgumentEncoder<CE>
    private let commandEncoder : CE
    
    /// The path of coding keys taken to get to this point in encoding.
    private(set) public var codingPath: [CodingKey]
    
    // MARK: - Initialization
    
    /// Initializes `self` with the given references.
    fileprivate init(referencing encoder: FunctionArgumentEncoder<CE>, codingPath: [CodingKey]) {
        self.encoder = encoder
        self.codingPath = codingPath
        self.commandEncoder = self.encoder.commandEncoder
    }
    
    func functionArgumentKey(_ key: K) -> FunctionArgumentKey {
        if let key = key as? FunctionArgumentKey {
            return key
        }
        return key.stringValue
    }
    
    // MARK: - KeyedEncodingContainerProtocol Methods
    
    public mutating func encodeNil(forKey key: Key) throws {
        // Do nothing; setting nil for an argument doesn't have any practical use.
    }
    
    public mutating func encode(_ value: Bool, forKey key: Key) throws {
        self.commandEncoder.setValue(value, key: functionArgumentKey(key))
    }
    
    public mutating func encode(_ value: Int, forKey key: Key) throws {
        throw ArgumentEncodingError.unsupportedValue(value, "Use sized types rather than Ints.")
    }
    public mutating func encode(_ value: Int8, forKey key: Key) throws {
        self.commandEncoder.setValue(value, key: functionArgumentKey(key))
    }
    public mutating func encode(_ value: Int16, forKey key: Key) throws {
        self.commandEncoder.setValue(value, key: functionArgumentKey(key))
    }
    public mutating func encode(_ value: Int32, forKey key: Key) throws {
        self.commandEncoder.setValue(value, key: functionArgumentKey(key))
    }
    public mutating func encode(_ value: Int64, forKey key: Key) throws {
        self.commandEncoder.setValue(value, key: functionArgumentKey(key))
    }
    public mutating func encode(_ value: UInt, forKey key: Key) throws {
        throw ArgumentEncodingError.unsupportedValue(value, "Use sized types rather than UInts.")
    }
    public mutating func encode(_ value: UInt8, forKey key: Key) throws {
        self.commandEncoder.setValue(value, key: functionArgumentKey(key))
    }
    public mutating func encode(_ value: UInt16, forKey key: Key) throws {
        self.commandEncoder.setValue(value, key: functionArgumentKey(key))
    }
    public mutating func encode(_ value: UInt32, forKey key: Key) throws {
        self.commandEncoder.setValue(value, key: functionArgumentKey(key))
    }
    public mutating func encode(_ value: UInt64, forKey key: Key) throws {
        self.commandEncoder.setValue(value, key: functionArgumentKey(key))
    }
    public mutating func encode(_ value: String, forKey key: Key) throws {
        throw ArgumentEncodingError.unsupportedValue(value, "Strings may not be encoded.")
    }
    public mutating func encode(_ value: Float, forKey key: Key) throws {
        self.commandEncoder.setValue(value, key: functionArgumentKey(key))
    }
    
    public mutating func encode(_ value: Double, forKey key: Key) throws {
        self.commandEncoder.setValue(value, key: functionArgumentKey(key))
    }
    
    public mutating func encode<T : Encodable>(_ value: T, forKey key: Key) throws {
        switch value {
        case let texture as Texture:
            self.commandEncoder.setTexture(texture, key: functionArgumentKey(key))
        case let buffer as Buffer:
            self.commandEncoder.setBuffer(buffer, offset: 0, key: functionArgumentKey(key))
        case let bufferView as BufferView:
            self.commandEncoder.setBuffer(bufferView.buffer, offset: bufferView.offset, key: functionArgumentKey(key))
        case let sampler as SamplerDescriptor:
            self.commandEncoder.setSampler(sampler, key: functionArgumentKey(key))
        default:
            self.commandEncoder.setValue(value, key: functionArgumentKey(key))
        }
    }
    
    public mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
        fatalError("Nested keyed containers are unsupported. Use argument buffers instead.")
    }
    
    public mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        fatalError("Unkeyed containers are unsupported.")
    }
    
    public mutating func superEncoder() -> Encoder {
        fatalError("Unimplemented.")
    }
    
    public mutating func superEncoder(forKey key: Key) -> Encoder {
        fatalError("Unimplemented.")
    }
}

public enum ArgumentEncodingError<T> : Error {
    case unsupportedValue(T, String)
    case invalidKey(CodingKey)
}

