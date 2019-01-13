//
//  Rect.swift
//  org.SwiftGFX.SwiftMath
//
//  Created by Andrey Volodin on 10.08.16.
//
//

public typealias Size2f = Vector2f

extension Size2f {
    public var width: Float {
        get {
           return x
        }
        set {
            x = newValue
        }
    }
    
    public var height: Float {
        get {
            return y
        }
        set {
            y = newValue
        }
    }
    
    public init(width: Float, height: Float) {
        self.init(width, height)
    }
    
    public init(width: Int, height: Int) {
        self.init(Float(width), Float(height))
    }
}

extension Size2f {
    /**
     Check if a size has power of two dimensions.
     */
    public var isPOT: Bool {
        let w = UInt(width)
        let h = UInt(height)
        return w == w.nextPOT && h == h.nextPOT
    }
}

// TODO:  
// - rect union
// - rect intersection
// - offset, scale
public struct Rect {
    public var origin: Point
    // TODO: Gracefully handle negative size case or forbid it
    public var size:   Size2f
    
    public var minX: Float { return origin.x }
    public var minY: Float { return origin.y }
    public var midX: Float { return origin.x + size.x / 2.0 }
    public var midY: Float { return origin.y + size.y / 2.0 }
    public var maxX: Float { return origin.x + size.x }
    public var maxY: Float { return origin.y + size.y }
    
    public var bottomLeft:  Point { return Point(minX, minY) }
    public var bottomRight: Point { return Point(maxX, maxY) }
    public var topLeft:     Point { return Point(minX, maxY) }
    public var topRight:    Point { return Point(maxX, maxY) }
    
    public var width : Float { return size.width }
    public var height: Float { return size.height }
    
    public init(bottomLeft: Point, topRight: Point) {
        origin = bottomLeft
        size = topRight - bottomLeft
    }
    
    public init(origin: Point = .zero, size: Size2f = .zero) {
        self.origin = origin
        self.size   = size
    }
    
    public static let zero = Rect(origin: Point.zero, size: Vector2f.zero)
}

extension Rect: CustomStringConvertible {
    public var description: String {
        return "Rect(origin: (\(origin.x), \(origin.y)), size: (\(size.x), \(size.y)))"
    }
}

extension Rect: Equatable {
    public static func ==(lhs: Rect, rhs: Rect) -> Bool {
        return
            lhs.size == rhs.size &&
            lhs.origin == rhs.origin
    }
}

extension Rect {
    public func sizeScaled(by s: Float) -> Rect {
        return Rect(origin: origin, size: size * s)
    }
    
    public func originScaled(by s: Float) -> Rect {
        return Rect(origin: origin * s, size: size)
    }
    
    public func scaled(by s: Float) -> Rect {
        return Rect(origin: origin * s, size: size * s)
    }
}

extension Rect {
    /* Transform `self' by `matrix' and return the result. Since affine transforms do
     not preserve rectangles in general, this function returns the smallest
     rectangle which contains the transformed corner points of `self'. If `matrix'
     consists solely of scales, flips and translations, then the returned
     rectangle coincides with the rectangle constructed from the four
     transformed corners. */
    public nonmutating func applying(matrix: Matrix4x4f) -> Rect {
        let bl = matrix * bottomLeft
        let br = matrix * bottomRight
        let tl = matrix * topLeft
        let tr = matrix * topRight
        
        // TODO: Add test for simple matrix (without rotation, skew, etc)
        // return (bl, tr) in that case
        var newBL = bl
        var newTR = tr
        
        for v in [bl, br, tl, tr] {
            newBL.x = min(v.x, newBL.x)
            newBL.y = min(v.y, newBL.y)
            
            newTR.x = max(v.x, newTR.x)
            newTR.y = max(v.y, newTR.y)
        }
        
        return Rect(bottomLeft: newBL, topRight: newTR)
    }
}
