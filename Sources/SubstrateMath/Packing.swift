
@usableFromInline
struct FloatBits {
    public var bitPattern : UInt32
    
    @inlinable
    public init(bitPattern: UInt32) {
        self.bitPattern = bitPattern
    }
    
    @inlinable
    public var exponentBitPattern : UInt32 {
        get {
            return self.bitPattern >> 23 & 0b11111111
        }
        set {
            self.bitPattern &= ~(0b11111111 << 23)
            self.bitPattern |= (newValue & 0b11111111) << 23
        }
    }
    
    @inlinable
    public var sign : FloatingPointSign {
        get {
            return self.bitPattern >> 31 & 0b1 == 0 ? .plus : .minus
        }
        set {
            if newValue == .minus {
                self.bitPattern |= 1 << 31
            } else {
                self.bitPattern &= 0x7FFFFFFF
            }
        }
    }
    
    @inlinable
    public var significandBitPattern : UInt32 {
        get {
            return self.bitPattern & 0x7FFFFF
        }
        set {
            self.bitPattern &= ~0x7FFFFF
            self.bitPattern |= (newValue & 0x7FFFFF)
        }
    }
}


@frozen
public struct Float16 : Hashable, Codable {
    public var bitPattern : UInt16
    
    @inlinable
    public init(bitPattern: UInt16) {
        self.bitPattern = bitPattern
    }
    
    @inlinable
    public var exponentBitPattern : UInt16 {
        return self.bitPattern >> 10 & 0b11111
    }
    
    @inlinable
    public var sign : FloatingPointSign {
        return self.bitPattern >> 15 & 0b1 == 0 ? .plus : .minus
    }
    
    @inlinable
    public var significandBitPattern : UInt16 {
        return self.bitPattern & 0b1111111111
    }
}


extension Float {
    @inlinable
    public init(_ h: Float16) {
        // https://fgiesen.wordpress.com/2012/03/28/half-to-float-done-quic/
        let magic = Float32(bitPattern: 126 << 23)
        var o = FloatBits(bitPattern: (0 as Float).bitPattern)
        
        if h.exponentBitPattern == 0 { // Zero / Denormal
            o.bitPattern = magic.bitPattern
            o.bitPattern = (Float(bitPattern: o.bitPattern) - magic).bitPattern
        } else {
            o.significandBitPattern = UInt32(h.significandBitPattern) << 13
            if (h.exponentBitPattern == 0x1f) { // Inf/NaN
                o.exponentBitPattern = 255
            } else {
                o.exponentBitPattern = 127 - 15 + UInt32(h.exponentBitPattern)
            }
        }
        
        o.sign = h.sign
        self.init(bitPattern: o.bitPattern)
    }
}

extension Float16 {
    @inlinable
    public init(_ float: Float) {
        let x = float.bitPattern
        var result = 0 as UInt32
        result |= (x >> 16) & 0x8000
        result |= ((((x & 0x7f800000) &- 0x38000000) >> 13) & 0x7c00)
        result |= (x >> 13) & 0x03ff
        self.init(bitPattern: UInt16(result))
    }
}

extension Float16 : ExpressibleByFloatLiteral {
    public typealias FloatLiteralType = Float
    
    @inlinable
    public init(floatLiteral value: Self.FloatLiteralType) {
        self.init(value)
    }
}

typealias Half = Float16

public enum Packing {
    
    @inlinable
    public static func packFloatToUChar4(_ x: Float, _ y: Float, _ z: Float, _ w: Float) -> UInt32 {
        let w0 = clamp(x, min: 0, max: 1) * Float(UInt8.max)
        let w1 = clamp(y, min: 0, max: 1) * Float(UInt8.max)
        let w2 = clamp(z, min: 0, max: 1) * Float(UInt8.max)
        let w3 = clamp(w, min: 0, max: 1) * Float(UInt8.max)
        
        return (UInt32(w3) &<< 24) | (UInt32(w2) &<< 16) | (UInt32(w1) &<< 8) | UInt32(w0)
    }
    
    @inlinable
    public static func packFloatToSnorm16(_ x: Float, _ y: Float, _ z: Float) -> (Int16, Int16, Int16) {
        let v0 = clamp(x, min: -1, max: 1) * Float(Int16.max)
        let v1 = clamp(y, min: -1, max: 1) * Float(Int16.max)
        let v2 = clamp(z, min: -1, max: 1) * Float(Int16.max)
        
        return (Int16(v0), Int16(v1), Int16(v2))
    }
    
    @inlinable
    public static func packFloatToUnorm16(_ x: Float, _ y: Float) -> (UInt16, UInt16) {
        let h0 = x * Float(UInt16.max)
        let h1 = y * Float(UInt16.max)
        return (UInt16(h0), UInt16(h1))
    }
    
    @inlinable
    public static func packIntsToUInt32(_ x: UInt8, _ y: UInt8, _ z: UInt8, _ w: UInt8) -> UInt32 {
        return (UInt32(w) &<< 24) | (UInt32(z) &<< 16) | (UInt32(y) &<< 8) | UInt32(x)
    }
    
    
    @inlinable
    public static func packFloatToUInt32(_ x: Float, _ y: Float) -> UInt32 {
        let x = Float16(x).bitPattern
        let y = Float16(y).bitPattern
        return UInt32(x) | (UInt32(y) &<< 16)
    }
}


