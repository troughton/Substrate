//
//  Codable.swift
//  SwiftMath
//
//  Created by Thomas Roughton on 26/04/18.
//

extension Vector2f : Codable {
    
    @inlinable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.x)
        try container.encode(self.y)
    }
    
    @inlinable
    public init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        let x = try values.decode(Float.self)
        let y = try values.decode(Float.self)
        
        self.init(x, y)
    }
}

extension Vector3f : Codable {
    
    @inlinable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.x)
        try container.encode(self.y)
        try container.encode(self.z)
    }
    
    @inlinable
    public init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        let x = try values.decode(Float.self)
        let y = try values.decode(Float.self)
        let z = try values.decode(Float.self)
        
        self.init(x, y, z)
    }
}

extension Vector4f : Codable {
    
    public enum CodingKeys : CodingKey {
        case x
        case y
        case z
        case w
    }
    
    @inlinable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.x)
        try container.encode(self.y)
        try container.encode(self.z)
        try container.encode(self.w)
    }
    
    @inlinable
    public init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        let x = try values.decode(Float.self)
        let y = try values.decode(Float.self)
        let z = try values.decode(Float.self)
        let w = try values.decode(Float.self)
        
        self.init(x, y, z, w)
    }
}

extension Quaternion : Codable {
    
    @inlinable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.x)
        try container.encode(self.y)
        try container.encode(self.z)
        try container.encode(self.w)
    }
    
    @inlinable
    public init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        let x = try values.decode(Float.self)
        let y = try values.decode(Float.self)
        let z = try values.decode(Float.self)
        let w = try values.decode(Float.self)
        
        self.init(x, y, z, w)
    }
}

extension Matrix3x3f : Codable {
    
    public enum CodingKeys : CodingKey {
        case c0
        case c1
        case c2
    }
    
    @inlinable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self[0], forKey: .c0)
        try container.encode(self[1], forKey: .c1)
        try container.encode(self[2], forKey: .c2)
    }
    
    
    @inlinable
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let c0 = try values.decode(Vector3f.self, forKey: .c0)
        let c1 = try values.decode(Vector3f.self, forKey: .c1)
        let c2 = try values.decode(Vector3f.self, forKey: .c2)
        
        self.init(c0, c1, c2)
    }
}

extension Matrix4x4f : Codable {
    
    public enum CodingKeys : CodingKey {
        case c0
        case c1
        case c2
        case c3
    }
    
    @inlinable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self[0], forKey: .c0)
        try container.encode(self[1], forKey: .c1)
        try container.encode(self[2], forKey: .c2)
        try container.encode(self[3], forKey: .c3)
    }
    
    @inlinable
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let c0 = try values.decode(Vector4f.self, forKey: .c0)
        let c1 = try values.decode(Vector4f.self, forKey: .c1)
        let c2 = try values.decode(Vector4f.self, forKey: .c2)
        let c3 = try values.decode(Vector4f.self, forKey: .c3)
        
        self.init(c0, c1, c2, c3)
    }
}
