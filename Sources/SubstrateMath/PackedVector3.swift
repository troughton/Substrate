//
//  PackedVector3.swift
//  
//

typealias PackedSIMD3<Scalar> = PackedVector3<Float>
typealias PackedVector3d = PackedVector3<Double>

@frozen
public struct PackedVector3<Scalar: SIMDScalar>: Hashable, Codable {
    public var x: Scalar
    public var y: Scalar
    public var z: Scalar
    
    @inlinable
    public init(_ x: Scalar, _ y: Scalar, _ z: Scalar) {
        self.x = x
        self.y = y
        self.z = z
    }
    
    @inlinable
    public init(repeating value: Scalar) {
        self.x = value
        self.y = value
        self.z = value
    }
}

extension PackedVector3 {
    @inlinable
    public init(_ vector: SIMD3<Scalar>) {
        self.x = vector.x
        self.y = vector.y
        self.z = vector.z
    }
}

extension PackedVector3 where Scalar == Float {
    @inlinable
    public init(_ vector: RGBColor) {
        self.x = vector.r
        self.y = vector.g
        self.z = vector.b
    }
}

extension SIMD3 {
    @inlinable
    public init(_ vector: PackedVector3<Scalar>) {
        self.init(vector.x, vector.y, vector.z)
    }
}

extension SIMD4 {
    @inlinable
    public init(_ xyz: PackedVector3<Scalar>, _ w: Scalar) {
        self.init(xyz.x, xyz.y, xyz.z, w)
    }
}

extension PackedVector3 {
    @inlinable public var xy:SIMD2<Scalar> { get { return SIMD2<Scalar>(x,y) } set { x = newValue.x; y = newValue.y } }
    @inlinable public var xyz:SIMD3<Scalar> { get { return SIMD3<Scalar>(x,y,z) } set { x = newValue.x; y = newValue.y; z = newValue.z } }
    @inlinable public var xz:SIMD2<Scalar> { get { return SIMD2<Scalar>(x,z) } set { x = newValue.x; z = newValue.y } }
    @inlinable public var xzy:SIMD3<Scalar> { get { return SIMD3<Scalar>(x,z,y) } set { x = newValue.x; z = newValue.y; y = newValue.z } }
    @inlinable public var yx:SIMD2<Scalar> { get { return SIMD2<Scalar>(y,x) } set { y = newValue.x; x = newValue.y } }
    @inlinable public var yxz:SIMD3<Scalar> { get { return SIMD3<Scalar>(y,x,z) } set { y = newValue.x; x = newValue.y; z = newValue.z } }
    @inlinable public var yz:SIMD2<Scalar> { get { return SIMD2<Scalar>(y,z) } set { y = newValue.x; z = newValue.y } }
    @inlinable public var yzx:SIMD3<Scalar> { get { return SIMD3<Scalar>(y,z,x) } set { y = newValue.x; z = newValue.y; x = newValue.z } }
    @inlinable public var zx:SIMD2<Scalar> { get { return SIMD2<Scalar>(z,x) } set { z = newValue.x; x = newValue.y } }
    @inlinable public var zxy:SIMD3<Scalar> { get { return SIMD3<Scalar>(z,x,y) } set { z = newValue.x; x = newValue.y; y = newValue.z } }
    @inlinable public var zy:SIMD2<Scalar> { get { return SIMD2<Scalar>(z,y) } set { z = newValue.x; y = newValue.y } }
    @inlinable public var zyx:SIMD3<Scalar> { get { return SIMD3<Scalar>(z,y,x) } set { z = newValue.x; y = newValue.y; x = newValue.z } }
}
