public struct RenderDuration: Hashable, Sendable {
    public var seconds: Double
    
    @inlinable
    public init(nanoseconds: UInt64) {
        self.seconds = Double(nanoseconds) * 1e-9
    }

    @inlinable
    public init(milliseconds: Double) {
        self.seconds = milliseconds * 1e-3
    }
    
    @inlinable
    public init(seconds: Double) {
        self.seconds = seconds
    }
    
    @inlinable
    public var milliseconds: Double {
        return Double(self.nanoseconds) * 1e-6
    }
    
    @inlinable
    public var nanoseconds: Int64 {
        return Int64(self.seconds * 1e9)
    }
    
    @inlinable
    public static var zero: RenderDuration { .init(seconds: 0) }
}

extension RenderDuration: Comparable {
    @inlinable
    public static func <(lhs: RenderDuration, rhs: RenderDuration) -> Bool {
        return lhs.seconds < rhs.seconds
    }
}

extension RenderDuration {
    @inlinable
    public static func +=(lhs: inout RenderDuration, rhs: RenderDuration) {
        lhs.seconds += rhs.seconds
    }
    
    @inlinable
    public static func +(lhs: RenderDuration, rhs: RenderDuration) -> RenderDuration {
        return .init(seconds: lhs.seconds + rhs.seconds)
    }
    
    @inlinable
    public static func -=(lhs: inout RenderDuration, rhs: RenderDuration) {
        lhs.seconds -= rhs.seconds
    }
    
    @inlinable
    public static func -(lhs: RenderDuration, rhs: RenderDuration) -> RenderDuration {
        return .init(seconds: lhs.seconds - rhs.seconds)
    }
    
    @inlinable
    public static func *=(lhs: inout RenderDuration, rhs: Double) {
        lhs.seconds *= rhs
    }
    
    @inlinable
    public static func *(lhs: RenderDuration, rhs: Double) -> RenderDuration {
        return .init(seconds: lhs.seconds * rhs)
    }
    
    @inlinable
    public static func *(lhs: Double, rhs: RenderDuration) -> RenderDuration {
        return .init(seconds: lhs * rhs.seconds)
    }
    
    @inlinable
    public static func /=(lhs: inout RenderDuration, rhs: Double) {
        lhs.seconds /= rhs
    }
    
    @inlinable
    public static func /(lhs: RenderDuration, rhs: Double) -> RenderDuration {
        return .init(seconds: lhs.seconds / rhs)
    }
}

extension RenderDuration: Codable {
    @inlinable
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(seconds: try container.decode(Double.self))
    }
    
    @inlinable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.seconds)
    }
}
