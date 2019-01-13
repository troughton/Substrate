// Copyright 2016 Stuart Carnie.
// License: https://github.com/SwiftGFX/SwiftMath#license-bsd-2-clause
//

public typealias vec4 = Vector4f

extension Vector4f : Vector { }

extension Vector4f {
    @inlinable
    public var isZero: Bool {
        return x == 0.0 && y == 0.0 && z == 0.0 && w == 0.0
    }
    
    public static let zero = Vector4f()
}

extension Vector4f: CustomStringConvertible {
    public var description: String {
        return "Vector4f(x: \(x), y: \(y), z: \(z), w: \(w))"
    }
}

extension Vector4f : CustomDebugStringConvertible {
    public var debugDescription : String {
        return self.description
    }
}
