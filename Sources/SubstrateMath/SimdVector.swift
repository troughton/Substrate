//
//  SimdVector.swift
//  SwiftMath
//
//  Created by Thomas Roughton on 6/05/18.
//

public struct SIMDVector3f {
    public var x = Vector4f() // stores x0, x1, x2, x3
    public var y = Vector4f() // stores y0, y1, y2, y3
    public var z = Vector4f() // etc.
    
    @inlinable
    public init() {
        
    }
    
    @inlinable
    public init(x: Vector4f, y: Vector4f, z: Vector4f) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct SIMDVector4f {
    public var x = Vector4f() // stores x0, x1, x2, x3
    public var y = Vector4f() // stores y0, y1, y2, y3
    public var z = Vector4f() // etc.
    public var w = Vector4f()
    
    @inlinable
    public init() {
        
    }
    
    @inlinable
    public init(x: Vector4f, y: Vector4f, z: Vector4f, w: Vector4f) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }
}

public struct SIMDAffineMatrix {
    public var c0 = SIMDVector3f()
    public var c1 = SIMDVector3f()
    public var c2 = SIMDVector3f()
    public var c3 = SIMDVector3f()
    
    @inlinable
    public init() {
        
    }
    
    @inlinable
    public init(c0: SIMDVector3f, c1: SIMDVector3f, c2: SIMDVector3f, c3: SIMDVector3f) {
        self.c0 = c0
        self.c1 = c1
        self.c2 = c2
        self.c3 = c3
    }
}

public struct SIMDMatrix {
    public var x = SIMDVector4f()
    public var y = SIMDVector4f()
    public var z = SIMDVector4f()
    public var w = SIMDVector4f()
    
    @inlinable
    public init() {
        
    }
    
    @inlinable
    public init(x: SIMDVector4f, y: SIMDVector4f, z: SIMDVector4f, w: SIMDVector4f) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }
}

@inlinable
public func *(v: SIMDVector4f, m: SIMDMatrix) -> SIMDVector4f {
    var x: SIMD4<Float> = v.x * m.x.x;     x = v.y * m.x.y + x;    x = v.z * m.x.z + x;    x = v.w * m.x.w + x;
    var y: SIMD4<Float> = v.x * m.y.x;     y = v.y * m.y.y + y;    y = v.z * m.y.z + y;    y = v.w * m.y.w + y;
    var z: SIMD4<Float> = v.x * m.z.x;     z = v.y * m.z.y + z;    z = v.z * m.z.z + z;    z = v.w * m.z.w + z;
    var w: SIMD4<Float> = v.x * m.w.x;     w = v.y * m.w.y + w;    w = v.z * m.w.z + w;    w = v.w * m.w.w + w;
    let res = SIMDVector4f(x: x, y: y, z: z, w: w)
    return res;
}

@inlinable
public func *(m: SIMDMatrix, v: SIMDVector4f) -> SIMDVector4f {
    var x: SIMD4<Float> = v.x * m.x.x;     x += v.y * m.y.x;    x += v.z * m.z.x;    x += v.w * m.w.x;
    var y: SIMD4<Float> = v.x * m.x.y;     y += v.y * m.y.y;    y += v.z * m.z.y;    y += v.w * m.w.y;
    var z: SIMD4<Float> = v.x * m.x.z;     z += v.y * m.y.z;    z += v.z * m.z.z;    z += v.w * m.w.z;
    var w: SIMD4<Float> = v.x * m.x.w;     w += v.y * m.y.w;    w += v.z * m.z.w;    w += v.w * m.w.w;
    let res = SIMDVector4f(x: x, y: y, z: z, w: w)
    return res;
}

@inlinable
public func *(lhs: SIMDMatrix, rhs: SIMDMatrix) -> SIMDMatrix {
    let x = lhs * rhs.x
    let y = lhs * rhs.y
    let z = lhs * rhs.z
    let w = lhs * rhs.w
    let res = SIMDMatrix(x: x, y: y, z: z, w: w)
    return res
}

// Affine matrices

@inlinable
public func mulPosition(_ m: SIMDMatrix, _ v: SIMDVector3f) -> SIMDVector4f {
    var x = v.x * m.x.x;     x += v.y * m.y.x;    x += v.z * m.z.x;    x += m.w.x;
    var y = v.x * m.x.y;     y += v.y * m.y.y;    y += v.z * m.z.y;    y += m.w.y;
    var z = v.x * m.x.z;     z += v.y * m.y.z;    z += v.z * m.z.z;    z += m.w.z;
    var w = v.x * m.x.w;     w += v.y * m.y.w;    w += v.z * m.z.w;    w += m.w.w;
    let res = SIMDVector4f(x: x, y: y, z: z, w: w)
    return res;
}

@inlinable
public func mulDirection(_ m: SIMDMatrix, _ v: SIMDVector3f) -> SIMDVector4f {
    var x = v.x * m.x.x;     x += v.y * m.y.x;    x += v.z * m.z.x;
    var y = v.x * m.x.y;     y += v.y * m.y.y;    y += v.z * m.z.y;
    var z = v.x * m.x.z;     z += v.y * m.y.z;    z += v.z * m.z.z;
    var w = v.x * m.x.w;     w += v.y * m.y.w;    w += v.z * m.z.w;
    let res = SIMDVector4f(x: x, y: y, z: z, w: w)
    return res;
}

@inlinable
public func *(lhs: SIMDMatrix, rhs: SIMDAffineMatrix) -> SIMDMatrix {
    let x = mulDirection(lhs, rhs.c0)
    let y = mulDirection(lhs, rhs.c1)
    let z = mulDirection(lhs, rhs.c2)
    let w = mulPosition(lhs, rhs.c3)
    let res = SIMDMatrix(x: x, y: y, z: z, w: w)
    return res
}
