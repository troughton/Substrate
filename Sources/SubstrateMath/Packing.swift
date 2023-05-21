
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


public struct Float16 : Hashable, Codable, Sendable {
    public var bitPattern : UInt16
    
    @inlinable
    public init(bitPattern: UInt16) {
        self.bitPattern = bitPattern
    }
    
    @inlinable
    public var exponentBitPattern : UInt16 {
        get {
            return self.bitPattern >> 10 & 0b11111
        } set {
            self.bitPattern &= 0b1000001111111111
            self.bitPattern |= (newValue & 0b11111) << 5
        }
    }
    
    @inlinable
    public var sign : FloatingPointSign {
        get {
            return self.bitPattern >> 15 & 0b1 == 0 ? .plus : .minus
        } set {
            switch newValue {
            case .plus:
                self.bitPattern &= ~(1 << 15)
            case .minus:
                self.bitPattern |= 1 << 15
            }
        }
    }
    
    @inlinable
    public var significandBitPattern : UInt16 {
        get {
            return self.bitPattern & 0b1111111111
        } set {
            self.bitPattern &= 0b0000000000
            self.bitPattern |= newValue & 0b1111111111
        }
    }
}


extension Float {
    @inlinable
    public init(_ h: Float16) {
        // https://fgiesen.wordpress.com/2012/03/28/half-to-float-done-quic/
        let magic = Float32(bitPattern: 126 << 23)
        var o = FloatBits(bitPattern: 0)
        
        if h.exponentBitPattern == 0 { // Zero / Denormal
            o.bitPattern = magic.bitPattern &+ UInt32(h.significandBitPattern)
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
        // https://stackoverflow.com/a/60047308{
        let x = float.bitPattern
        let b = x &+ 0x00001000; // round-to-nearest-even: add last bit after truncated mantissa
        let e = (b & 0x7F800000) >> 23 // exponent
        let m = b & 0x007FFFFF // mantissa; in line below: 0x007FF000 = 0x00800000-0x00001000 = decimal indicator flag - initial rounding
           
        var result = (b & 0x80000000) >> 16
        
        if e > 101 && e < 113 {
            result |= (((0x007FF000 &+ m) >> (125 &- e)) &+ 1) >> 1
        }
        if e > 112 {
            result |= (((e &- 112) << 10) & 0x7C00) | m >> 13
        }
        if e > 143 {
            result |= 0x7FFF
        }
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
        let w0 = clamp(x, min: 0, max: 1) * Float(UInt8.max) + 0.5
        let w1 = clamp(y, min: 0, max: 1) * Float(UInt8.max) + 0.5
        let w2 = clamp(z, min: 0, max: 1) * Float(UInt8.max) + 0.5
        let w3 = clamp(w, min: 0, max: 1) * Float(UInt8.max) + 0.5
        
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


