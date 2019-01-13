// Copyright 2016 Stuart Carnie.
// License: https://github.com/SwiftGFX/SwiftMath#license-bsd-2-clause
//

public typealias vec2 = Vector2f

extension Vector2f : Vector { }

extension Vector2f {
    //MARK: - initializers
    
    @inlinable
    public init(_ v: Vector4f) {
        self.init(v.x, v.y)
    }
    
    @inlinable
    public init(_ v: Vector3f) {
        self.init(v.x, v.y)
    }
    
    @inlinable
    public init(x: Int, y: Int) {
        self.init(x: Float(x), y: Float(y))
    }
    
    @inlinable
    public init(_ x: Int, _ y: Int) {
        self.init(x: Float(x), y: Float(y))
    }
}

extension Vector2f {
    
    public static let zero = Vector2f()
    
    @inlinable
    public var isZero: Bool {
        return x == 0.0 && y == 0.0
    }
}

@inlinable
public func floor(_ v: Vector2f) -> Vector2f {
    #if NOSIMD
    return Vector2f(v.x.rounded(.down), v.y.rounded(.down))
    #else
    var result = Vector2f()
    result.d = floor(v.d)
    return result
    #endif
}

@inlinable
public func ceil(_ v: Vector2f) -> Vector2f {
    #if NOSIMD
    return Vector2f(v.x.rounded(.up), v.y.rounded(.up))
    #else
    var result = Vector2f()
    result.d = ceil(v.d)
    return result
    #endif
}

@inlinable
public func min(_ a: Vector2f, _ b: Vector2f) -> Vector2f {
    #if NOSIMD
    return Vector2f(min(a.x, b.x), min(a.y, b.y))
    #else
    var result = Vector2f()
    result.d = min(a.d, b.d)
    return result
    #endif
}

@inlinable
public func max(_ a: Vector2f, _ b: Vector2f) -> Vector2f {
    #if NOSIMD
    return Vector2f(max(a.x, b.x), max(a.y, b.y))
    #else
    var result = Vector2f()
    result.d = max(a.d, b.d)
    return result
    #endif
}

@inlinable
public func clamp(_ x: Vector2f, min minVec: Vector2f, max maxVec: Vector2f) -> Vector2f {
    return min(max(minVec, x), maxVec)
}


extension Vector2f: CustomStringConvertible {
    public var description: String {
        return "Vector2f(x: \(x), y: \(y))"
    }
}

extension Vector2f : CustomDebugStringConvertible {
    public var debugDescription : String {
        return self.description
    }
}
