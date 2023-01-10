import RealModule
import SubstrateUtilities

public enum SphericalHarmonics {
    
    public struct ZerothBand<Scalar: BinaryFloatingPoint & SIMDScalar> {
        public var value: Scalar
        
        @inlinable
        public init(value: Scalar) {
            self.value = value
        }
        
        @inlinable
        public init(encoding value: Scalar, direction: SIMD3<Scalar>) {
            self.value = value
        }
        
        @inlinable
        public init<S>(_ other: ZerothBand<S>) {
            self.value = .init(other.value)
        }
        
        @inlinable
        public func reconstruct(direction: SIMD3<Scalar>) -> Scalar {
            return self.value
        }
        
        @inlinable
        public func reconstructIrradiance(direction: SIMD3<Scalar>) -> Scalar {
            return self.value
        }
        
        @inlinable
        public static func +=(lhs: inout ZerothBand, rhs: ZerothBand) {
            lhs.value += rhs.value
        }
        
        @inlinable
        public static func +(lhs: ZerothBand, rhs: ZerothBand) -> ZerothBand {
            var result = lhs
            result += rhs
            return result
        }
        
        @inlinable
        public static func -=(lhs: inout ZerothBand, rhs: ZerothBand) {
            lhs.value -= rhs.value
        }
        
        @inlinable
        public static func -(lhs: ZerothBand, rhs: ZerothBand) -> ZerothBand {
            var result = lhs
            result -= rhs
            return result
        }
        
        @inlinable
        public static func *=(lhs: inout ZerothBand, rhs: Scalar) {
            lhs.value *= rhs
        }
        
        @inlinable
        public static func *(lhs: ZerothBand, rhs: Scalar) -> ZerothBand {
            var result = lhs
            result *= rhs
            return result
        }
    }
    
    public struct FirstBand<Scalar: BinaryFloatingPoint & SIMDScalar> {
        public var x: Scalar
        public var y: Scalar
        public var z: Scalar
        
        @inlinable
        public init() {
            self.x = .zero
            self.y = .zero
            self.z = .zero
        }
        
        @inlinable
        public init<S>(_ other: FirstBand<S>) {
            self.x = .init(other.x)
            self.y = .init(other.y)
            self.z = .init(other.z)
        }
        
        @inlinable
        public init(x: Scalar, y: Scalar, z: Scalar) {
            self.x = x
            self.y = y
            self.z = z
        }
        
        @inlinable
        public init(encoding value: Scalar, direction: SIMD3<Scalar>) {
            self.x = value * direction.x
            self.y = value * direction.y
            self.z = value * direction.z
        }
        
        @inlinable
        public func reconstruct(direction: SIMD3<Scalar>) -> Scalar {
            return 3.0 * dot(direction, SIMD3(self.x, self.y, self.z))
        }
        
        @inlinable
        public func reconstructIrradiance(direction: SIMD3<Scalar>) -> Scalar {
            return 2.0 * dot(direction, SIMD3(self.x, self.y, self.z))
        }
        
        @inlinable
        public static func +=(lhs: inout FirstBand, rhs: FirstBand) {
            lhs.x += rhs.x
            lhs.y += rhs.y
            lhs.z += rhs.z
        }
        
        @inlinable
        public static func +(lhs: FirstBand, rhs: FirstBand) -> FirstBand {
            var result = lhs
            result += rhs
            return result
        }
        
        @inlinable
        public static func -=(lhs: inout FirstBand, rhs: FirstBand) {
            lhs.x -= rhs.x
            lhs.y -= rhs.y
            lhs.z -= rhs.z
        }
        
        @inlinable
        public static func -(lhs: FirstBand, rhs: FirstBand) -> FirstBand {
            var result = lhs
            result -= rhs
            return result
        }
        
        @inlinable
        public static func *=(lhs: inout FirstBand, rhs: Scalar) {
            lhs.x *= rhs
            lhs.y *= rhs
            lhs.z *= rhs
        }
        
        @inlinable
        public static func *(lhs: FirstBand, rhs: Scalar) -> FirstBand {
            var result = lhs
            result *= rhs
            return result
        }
    }
    
    public struct SecondBand<Scalar: BinaryFloatingPoint & SIMDScalar> {
        public var mNeg2: Scalar
        public var mNeg1: Scalar
        public var m0: Scalar
        public var mPos1: Scalar
        public var mPos2: Scalar
        
        @inlinable
        public init() {
            self.mNeg2 = .zero
            self.mNeg1 = .zero
            self.m0 = .zero
            self.mPos1 = .zero
            self.mPos2 = .zero
        }
        
        @inlinable
        public init<S>(_ other: SecondBand<S>) {
            self.mNeg2 = .init(other.mNeg2)
            self.mNeg1 = .init(other.mNeg1)
            self.m0 = .init(other.m0)
            self.mPos1 = .init(other.mPos1)
            self.mPos2 = .init(other.mPos2)
        }
        
        @inlinable
        public init(mNeg2: Scalar, mNeg1: Scalar, m0: Scalar, mPos1: Scalar, mPos2: Scalar) {
            self.mNeg2 = mNeg2
            self.mNeg1 = mNeg1
            self.m0 = m0
            self.mPos1 = mPos1
            self.mPos2 = mPos2
        }
        
        @inlinable
        public init(encoding value: Scalar, direction: SIMD3<Scalar>) {
            self.mNeg2 = value * (direction.z * direction.x) as Scalar
            self.mNeg1 = value * (direction.z * direction.y) as Scalar
            self.m0 = value * ((direction.y * direction.y) as Scalar - (1.0 as Scalar) / (3.0 as Scalar))
            self.mPos1 = value * (direction.y * direction.x) as Scalar
            self.mPos2 = value * ((direction.x * direction.x) as Scalar - (direction.z * direction.z) as Scalar)
        }
        
        @inlinable
        public func reconstruct(direction: SIMD3<Scalar>) -> Scalar {
            var result = 0.0 as Scalar
            
            result += direction.z * direction.x * self.mNeg2
            result += direction.z * direction.y * self.mNeg1
            result += direction.y * direction.x * self.mPos1
            result *= 15.0 as Scalar
            
            let ySq: Scalar = direction.y * direction.y
            result += (11.25 as Scalar) * (ySq - (1.0 as Scalar) / (3.0 as Scalar)) * self.m0
            result += (3.75 as Scalar) * ((direction.x * direction.x) as Scalar - (direction.z * direction.z) as Scalar) as Scalar * self.mPos2
            
            return result
        }
        
        @inlinable
        public func reconstructIrradiance(direction: SIMD3<Scalar>) -> Scalar {
            return 0.25 * self.reconstruct(direction: direction)
        }
        
        @inlinable
        public static func +=(lhs: inout SecondBand, rhs: SecondBand) {
            lhs.mNeg2 += rhs.mNeg2
            lhs.mNeg1 += rhs.mNeg1
            lhs.m0 += rhs.m0
            lhs.mPos1 += rhs.mPos1
            lhs.mPos2 += rhs.mPos2
        }
        
        @inlinable
        public static func +(lhs: SecondBand, rhs: SecondBand) -> SecondBand {
            var result = lhs
            result += rhs
            return result
        }
        
        @inlinable
        public static func -=(lhs: inout SecondBand, rhs: SecondBand) {
            lhs.mNeg2 -= rhs.mNeg2
            lhs.mNeg1 -= rhs.mNeg1
            lhs.m0 -= rhs.m0
            lhs.mPos1 -= rhs.mPos1
            lhs.mPos2 -= rhs.mPos2
        }
        
        @inlinable
        public static func -(lhs: SecondBand, rhs: SecondBand) -> SecondBand {
            var result = lhs
            result -= rhs
            return result
        }
        
        @inlinable
        public static func *=(lhs: inout SecondBand, rhs: Scalar) {
            lhs.mNeg2 *= rhs
            lhs.mNeg1 *= rhs
            lhs.m0 *= rhs
            lhs.mPos1 *= rhs
            lhs.mPos2 *= rhs
        }
        
        @inlinable
        public static func *(lhs: SecondBand, rhs: Scalar) -> SecondBand {
            var result = lhs
            result *= rhs
            return result
        }
    }
    
    public struct L2Function<Scalar: BinaryFloatingPoint & SIMDScalar> {
        public var l0: ZerothBand<Scalar>
        public var l1: FirstBand<Scalar>
        public var l2: SecondBand<Scalar>
        
        @inlinable
        public init(l0: ZerothBand<Scalar>, l1: FirstBand<Scalar>, l2: SecondBand<Scalar>) {
            self.l0 = l0
            self.l1 = l1
            self.l2 = l2
        }
        
        @inlinable
        public init<S>(_ other: L2Function<S>) {
            self.l0 = .init(other.l0)
            self.l1 = .init(other.l1)
            self.l2 = .init(other.l2)
        }
        
        @inlinable
        public init(encoding value: Scalar, direction: SIMD3<Scalar>) {
            self.l0 = .init(encoding: value, direction: direction)
            self.l1 = .init(encoding: value, direction: direction)
            self.l2 = .init(encoding: value, direction: direction)
        }
        
        @inlinable
        public static func constant(value: Scalar) -> L2Function {
            return .init(l0: .init(value: value), l1: .init(), l2: .init())
        }
        
        @inlinable
        public func reconstruct(direction: SIMD3<Scalar>, zonalCoefficients: SIMD3<Scalar> = SIMD3(1, 1, 1)) -> Scalar {
            var result = 0.0 as Scalar
            result += self.l0.reconstruct(direction: direction) * zonalCoefficients.x
            result += self.l1.reconstruct(direction: direction) * zonalCoefficients.y
            result += self.l2.reconstruct(direction: direction) * zonalCoefficients.z
            return result
        }
        
        @inlinable
        public func reconstructIrradiance(direction: SIMD3<Scalar>) -> Scalar {
            var result = 0.0 as Scalar
            result += self.l0.reconstructIrradiance(direction: direction)
            result += self.l1.reconstructIrradiance(direction: direction)
            result += self.l2.reconstructIrradiance(direction: direction)
            return result
        }
        
        @inlinable
        public static func +=(lhs: inout L2Function, rhs: L2Function) {
            lhs.l0 += rhs.l0
            lhs.l1 += rhs.l1
            lhs.l2 += rhs.l2
        }
        
        @inlinable
        public static func +(lhs: L2Function, rhs: L2Function) -> L2Function {
            var result = lhs
            result += rhs
            return result
        }
        
        @inlinable
        public static func -=(lhs: inout L2Function, rhs: L2Function) {
            lhs.l0 -= rhs.l0
            lhs.l1 -= rhs.l1
            lhs.l2 -= rhs.l2
        }
        
        @inlinable
        public static func -(lhs: L2Function, rhs: L2Function) -> L2Function {
            var result = lhs
            result -= rhs
            return result
        }
        
        @inlinable
        public static func *=(lhs: inout L2Function, rhs: Scalar) {
            lhs.l0 *= rhs
            lhs.l1 *= rhs
            lhs.l2 *= rhs
        }
        
        @inlinable
        public static func *(lhs: L2Function, rhs: Scalar) -> L2Function {
            var result = lhs
            result *= rhs
            return result
        }
    }
    
    public struct L2RGBFunction<Scalar: BinaryFloatingPoint & SIMDScalar> {
        public var r: L2Function<Scalar>
        public var g: L2Function<Scalar>
        public var b: L2Function<Scalar>
        
        @inlinable
        public init(r: L2Function<Scalar>, g: L2Function<Scalar>, b: L2Function<Scalar>) {
            self.r = r
            self.g = g
            self.b = b
        }
        
        @inlinable
        public init<S>(_ other: L2RGBFunction<S>) {
            self.r = .init(other.r)
            self.g = .init(other.g)
            self.b = .init(other.b)
        }
        
        @inlinable
        public init(encoding value: SIMD3<Scalar>, direction: SIMD3<Scalar>) {
            self.r = .init(encoding: value.x, direction: direction)
            self.g = .init(encoding: value.y, direction: direction)
            self.b = .init(encoding: value.z, direction: direction)
        }
        
        @inlinable
        public static func constant(value: SIMD3<Scalar>) -> L2RGBFunction {
            return .init(r: .constant(value: value.x), g: .constant(value: value.y), b: .constant(value: value.z))
        }
        
        @inlinable
        public func reconstruct(direction: SIMD3<Scalar>, zonalCoefficients: SIMD3<Scalar> = SIMD3(1, 1, 1)) -> SIMD3<Scalar> {
            return SIMD3(self.r.reconstruct(direction: direction, zonalCoefficients: zonalCoefficients),
                         self.g.reconstruct(direction: direction, zonalCoefficients: zonalCoefficients),
                         self.b.reconstruct(direction: direction, zonalCoefficients: zonalCoefficients))
        }
        
        @inlinable
        public func reconstructIrradiance(direction: SIMD3<Scalar>) -> SIMD3<Scalar> {
            return SIMD3(self.r.reconstructIrradiance(direction: direction),
                         self.g.reconstructIrradiance(direction: direction),
                         self.b.reconstructIrradiance(direction: direction))
        }
        
        @inlinable
        public static func +=(lhs: inout L2RGBFunction, rhs: L2RGBFunction) {
            lhs.r += rhs.r
            lhs.g += rhs.g
            lhs.b += rhs.b
        }
        
        @inlinable
        public static func +(lhs: L2RGBFunction, rhs: L2RGBFunction) -> L2RGBFunction {
            var result = lhs
            result += rhs
            return result
        }
        
        @inlinable
        public static func -=(lhs: inout L2RGBFunction, rhs: L2RGBFunction) {
            lhs.r -= rhs.r
            lhs.g -= rhs.g
            lhs.b -= rhs.b
        }
        
        @inlinable
        public static func -(lhs: L2RGBFunction, rhs: L2RGBFunction) -> L2RGBFunction {
            var result = lhs
            result -= rhs
            return result
        }
        
        @inlinable
        public static func *=(lhs: inout L2RGBFunction, rhs: SIMD3<Scalar>) {
            lhs.r *= rhs.x
            lhs.g *= rhs.y
            lhs.b *= rhs.z
        }
        
        @inlinable
        public static func *(lhs: L2RGBFunction, rhs: SIMD3<Scalar>) -> L2RGBFunction {
            var result = lhs
            result *= rhs
            return result
        }
        
        @inlinable
        public static func *=(lhs: inout L2RGBFunction, rhs: Scalar) {
            lhs.r *= rhs
            lhs.g *= rhs
            lhs.b *= rhs
        }
        
        @inlinable
        public static func *(lhs: L2RGBFunction, rhs: Scalar) -> L2RGBFunction {
            var result = lhs
            result *= rhs
            return result
        }
    }
}

extension SphericalHarmonics.ZerothBand: Equatable where Scalar: Equatable {}
extension SphericalHarmonics.ZerothBand: Codable where Scalar: Codable {
    public init(from decoder: Decoder) throws {
        self.init(value: try decoder.singleValueContainer().decode(Scalar.self))
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.value)
    }
}

extension SphericalHarmonics.FirstBand: Equatable where Scalar: Equatable {}
extension SphericalHarmonics.FirstBand: Codable where Scalar: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.init(x: try container.decode(Scalar.self), y: try container.decode(Scalar.self), z: try container.decode(Scalar.self))
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.x)
        try container.encode(self.y)
        try container.encode(self.z)
    }
}

extension SphericalHarmonics.SecondBand: Equatable where Scalar: Equatable {}
extension SphericalHarmonics.SecondBand: Codable where Scalar: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.init(mNeg2: try container.decode(Scalar.self), mNeg1: try container.decode(Scalar.self), m0: try container.decode(Scalar.self), mPos1: try container.decode(Scalar.self), mPos2: try container.decode(Scalar.self))
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.mNeg2)
        try container.encode(self.mNeg1)
        try container.encode(self.m0)
        try container.encode(self.mPos1)
        try container.encode(self.mPos2)
    }
}

extension SphericalHarmonics.L2Function: Equatable where Scalar: Equatable {}
extension SphericalHarmonics.L2Function: Codable where Scalar: Codable {}

extension SphericalHarmonics.L2RGBFunction: Equatable where Scalar: Equatable {}
extension SphericalHarmonics.L2RGBFunction: Codable where Scalar: Codable {}


// MARK: - Deringing


// https://github.com/google/filament/blob/main/libs/ibl/src/CubemapSH.cpp
/*
 * Copyright (C) 2015 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
// Modifications: Ported to Swift.

extension SphericalHarmonics.FirstBand where Scalar: Real {
    public func rotated(by M: Matrix3x3<Scalar>) -> SphericalHarmonics.FirstBand<Scalar> {
        //    constexpr float3 N0{ 1, 0, 0 };
        //    constexpr float3 N1{ 0, 1, 0 };
        //    constexpr float3 N2{ 0, 0, 1 };
        //
        //    constexpr mat3f A1 = { // this is the projection of N0, N1, N2 to SH space
        //            float3{ -N0.y, N0.z, -N0.x },
        //            float3{ -N1.y, N1.z, -N1.x },
        //            float3{ -N2.y, N2.z, -N2.x }
        //    };
        //
        //    const mat3f invA1 = inverse(A1);

        let invA1TimesK = Matrix3x3<Scalar>(
            SIMD3( 0, -1,  0 ),
            SIMD3( 0,  0,  1 ),
            SIMD3(-1,  0,  0)
        )

        // below can't be constexpr
        let MN0 = M[0]  // M * N0;
        let MN1 = M[1]  // M * N1;
        let MN2 = M[2]  // M * N2;
        let R1OverK = Matrix3x3(
                SIMD3( -MN0.y, MN0.z, -MN0.x ),
                SIMD3( -MN1.y, MN1.z, -MN1.x ),
                SIMD3( -MN2.y, MN2.z, -MN2.x)
        )

        let result: SIMD3<Scalar> = R1OverK * (invA1TimesK * SIMD3(self.x, self.y, self.z))
        return .init(x: result.x, y: result.y, z: result.z)
    }
    
    public mutating func rotate(by M: Matrix3x3<Scalar>) {
        self = self.rotated(by: M)
    }
}

extension SphericalHarmonics.SecondBand where Scalar: Real {
    public func rotated(by M: Matrix3x3<Scalar>) -> SphericalHarmonics.SecondBand<Scalar> {
        let M_SQRT_3  = 1.7320508076 as Scalar
        let n = 1.0 as Scalar / Scalar.sqrt(2.0)

        //  Below we precompute (with help of Mathematica):
        //    constexpr float3 N0{ 1, 0, 0 };
        //    constexpr float3 N1{ 0, 0, 1 };
        //    constexpr float3 N2{ n, n, 0 };
        //    constexpr float3 N3{ n, 0, n };
        //    constexpr float3 N4{ 0, n, n };
        //    constexpr float M_SQRT_PI = 1.7724538509f;
        //    constexpr float M_SQRT_15 = 3.8729833462f;
        //    constexpr float k = M_SQRT_15 / (2.0f * M_SQRT_PI);
        //    --> k * inverse(mat5{project(N0), project(N1), project(N2), project(N3), project(N4)})
        let invATimesK: Array5<Array5<Scalar>> = [
            [    0,        1,   2,   0,  0 ] as Array5<Scalar>,
            [   -1,        0,   0,   0, -2 ] as Array5<Scalar>,
            [    0, M_SQRT_3,   0,   0,  0 ] as Array5<Scalar>,
            [    1,        1,   0,  -2,  0 ] as Array5<Scalar>,
            [    2,        1,   0,   0,  0 ] as Array5<Scalar>
        ]

        // This projects a vec3 to SH2/k space (i.e. we premultiply by 1/k)
        // below can't be constexpr
        func project(_ s: SIMD3<Scalar>) -> Array5<Scalar> {
            let neg2: Scalar = s.y * s.x
            let neg1: Scalar =  -((s.y * s.z) as Scalar)
            let m0Scale: Scalar = 1.0 as Scalar / (2.0 * M_SQRT_3)
            let m0: Scalar = m0Scale * (((3.0 as Scalar) * s.z * s.z - 1.0 as Scalar) as Scalar)
            let pos1: Scalar = -(s.z * s.x)
            let pos2: Scalar = (0.5 as Scalar) * ((s.x * s.x) as Scalar - (s.y * s.y) as Scalar)
            return [
                neg2, neg1, m0, pos1, pos2
            ]
        }
        
        func multiply(_ a: Array5<Array5<Scalar>>, _ b: Array5<Scalar>) -> Array5<Scalar> {
            var result = Array5<Scalar>(repeating: .zero)
            
            for i in 0..<5 {
                for j in 0..<5 {
                    result[i] += (a[j][i] * b[j]) as Scalar
                }
            }
            
            return result
        }
        
        // this is: invA * k * band2
        // 5x5 matrix by vec5 (this a lot of zeroes and constants, which the compiler should eliminate)
        let invATimesKTimesBand2 = multiply(invATimesK, [self.mNeg2, self.mNeg1, self.m0, self.mPos1, self.mPos2])

           // this is: mat5{project(N0), project(N1), project(N2), project(N3), project(N4)} / k
        // (the 1/k comes from project(), see above)
            let ROverK: Array5<Array5<Scalar>> = [
            project(M[0]),                  // M * N0
            project(M[2]),                  // M * N1
            project(n * (M[0] + M[1]) as SIMD3<Scalar>),     // M * N2
            project(n * (M[0] + M[2]) as SIMD3<Scalar>),     // M * N3
            project(n * (M[1] + M[2]) as SIMD3<Scalar>)      // M * N4
        ]
        
        // notice how "k" disappears
        // this is: (R / k) * (invA * k) * band2 == R * invA * band2
        let result = multiply(ROverK, invATimesKTimesBand2);
        
        return SphericalHarmonics.SecondBand(mNeg2: result[0], mNeg1: result[1], m0: result[2], mPos1: result[3], mPos2: result[4])
    }
    
    
    public mutating func rotate(by M: Matrix3x3<Scalar>) {
        self = self.rotated(by: M)
    }
}


extension SphericalHarmonics {
    
    /*
     * SH from environment with high dynamic range (or high frequencies -- high dynamic range creates
     * high frequencies) exhibit "ringing" and negative values when reconstructed.
     * To mitigate this, we need to low-pass the input image -- or equivalently window the SH by
     * coefficient that tapper towards zero with the band.
     *
     * We use ideas and techniques from
     *    Stupid Spherical Harmonics (SH)
     *    Deringing Spherical Harmonics
     * by Peter-Pike Sloan
     * https://www.ppsloan.org/publications/shdering.pdf
     *
     */
    public static func sincWindow<Scalar: BinaryFloatingPoint & Real>(l: Int, w: Scalar) -> Scalar {
        if l == 0 {
            return 1.0
        } else if Scalar(l) >= w {
            return .zero
        }
        
        // we use a sinc window scaled to the desired window size in bands units
        // a sinc window only has zonal harmonics
        var x = (Scalar.pi * Scalar(l)) / w;
        x = Scalar.sin(x) / x

        // The convolution of a SH function f and a ZH function h is just the product of both
        // scaled by 1 / K(0,l) -- the window coefficients include this scale factor.

        // Taking the window to power N is equivalent to applying the filter N times
        return Scalar.pow(x, 4)
    }
}

extension SphericalHarmonics.L2Function where Scalar: Real {
    public func rotated(by M: Matrix3x3<Scalar>) -> SphericalHarmonics.L2Function<Scalar> {
        return .init(l0: self.l0, l1: self.l1.rotated(by: M), l2: self.l2.rotated(by: M))
    }
    
    public mutating func rotate(by M: Matrix3x3<Scalar>) {
        self = self.rotated(by: M)
    }
}

extension SphericalHarmonics.L2RGBFunction where Scalar: Real {
    @_specialize(kind: full, where Scalar == Float)
    public mutating func window(cutoff: Scalar = 0.0) {
        func shmin(_ f: SphericalHarmonics.L2Function<Scalar>) -> Scalar {
            // See "Deringing Spherical Harmonics" by Peter-Pike Sloan
            // https://www.ppsloan.org/publications/shdering.pdf

            let M_SQRT_PI: Scalar = 1.7724538509
            let M_SQRT_3: Scalar  = 1.7320508076
            let M_SQRT_5: Scalar  = 2.2360679775
            let M_SQRT_15: Scalar = 3.8729833462
            let A: Array9<Scalar> = [
                (1.0 as Scalar) / (2.0 as Scalar * M_SQRT_PI),    // 0: 0  0
                (-M_SQRT_3 as Scalar)  / (2.0 as Scalar * M_SQRT_PI),    // 1: 1 -1
                (M_SQRT_3 as Scalar)  / (2.0 as Scalar * M_SQRT_PI),    // 2: 1  0
                (-M_SQRT_3 as Scalar)  / (2.0 as Scalar * M_SQRT_PI),    // 3: 1  1
                (M_SQRT_15 as Scalar) / (2.0 as Scalar * M_SQRT_PI),    // 4: 2 -2
                (-M_SQRT_15 as Scalar) / (2.0 as Scalar * M_SQRT_PI),    // 5: 2 -1
                (M_SQRT_5 as Scalar)  / (4.0 as Scalar * M_SQRT_PI),    // 6: 2  0
                (-M_SQRT_15 as Scalar) / (2.0 as Scalar * M_SQRT_PI),    // 7: 2  1
                (M_SQRT_15 as Scalar) / (4.0 as Scalar * M_SQRT_PI)     // 8: 2  2
            ]

            // first this to do is to rotate the SH to align Z with the optimal linear direction
            let dir = normalize(SIMD3<Scalar>(-f.l1.z, -f.l1.x, f.l1.y ))
            let z_axis: SIMD3<Scalar> = -dir
            let x_axis: SIMD3<Scalar> = normalize(cross(z_axis, SIMD3<Scalar>(0, 1, 0)))
            let y_axis: SIMD3<Scalar> = cross(x_axis, z_axis)
            let M = Matrix3x3<Scalar>(x_axis, y_axis, -z_axis).transpose
            
            let f = f.rotated(by: M)
            // here we're guaranteed to have normalize(float3{ -f[3], -f[1], f[2] }) == { 0, 0, 1 }
            
            // Find the min for |m| = 2
            // ------------------------
            //
            // Peter-Pike Sloan shows that the minimum can be expressed as a function
            // of z such as:  m2min = -m2max * (1 - z^2) =  m2max * z^2 - m2max
            //      with m2max = A[8] * std::sqrt(f[8] * f[8] + f[4] * f[4]);
            // We can therefore include this in the ZH min computation (which is function of z^2 as well)
            let m2max: Scalar = A[8] * Scalar.sqrt((f.l2.mPos2 * f.l2.mPos2) as Scalar + (f.l2.mNeg2 * f.l2.mNeg2) as Scalar)
            
            // Find the min of the zonal harmonics
            // -----------------------------------
            //
            // This comes from minimizing the function:
            //      ZH(z) = (A[0] * f[0])
            //            + (A[2] * f[2]) * z
            //            + (A[6] * f[6]) * (3 * s.z * s.z - 1)
            //
            // We do that by finding where it's derivative d/dz is zero:
            //      dZH(z)/dz = a * z^2 + b * z + c
            //      which is zero for z = -b / 2 * a
            //
            // We also needs to check that -1 < z < 1, otherwise the min is either in z = -1 or 1
            //
            let a: Scalar = ((3.0 as Scalar) * A[6]) as Scalar * f.l2.m0 + m2max
            let b: Scalar = A[2] * f.l1.y
            let c: Scalar = (A[0] * f.l0.value) as Scalar - (A[6] * f.l2.m0) as Scalar - m2max

            let zmin: Scalar = -b / (2.0 as Scalar * a)
            let m0min_z: Scalar = (a * (zmin * zmin) as Scalar) as Scalar + (b * zmin) as Scalar + c
            let m0min_b: Scalar = min((a + b) as Scalar + c, (a - b) as Scalar + c)

            let m0min = (a > 0 && zmin >= (-1 as Scalar) && zmin <= (1 as Scalar)) ? m0min_z : m0min_b

            // Find the min for l = 2, |m| = 1
            // -------------------------------
            //
            // Note l = 1, |m| = 1 is guaranteed to be 0 because of the rotation step
            //
            // The function considered is:
            //        Y(x, y, z) = A[5] * f[5] * s.y * s.z
            //                   + A[7] * f[7] * s.z * s.x
            let d: Scalar = A[4] * Scalar.sqrt((f.l2.mNeg1 * f.l2.mNeg1) as Scalar + (f.l2.mPos1 * f.l2.mPos1) as Scalar)

            // the |m|=1 function is minimal in -0.5 -- use that to skip the Newton's loop when possible
            var minimum = m0min - ((0.5 as Scalar) * d) as Scalar
            if (minimum < 0) {
                // We could be negative, to find the minimum we will use Newton's method
                // See https://en.wikipedia.org/wiki/Newton%27s_method_in_optimization

                // this is the function we're trying to minimize
                func testFunc(_ x: Scalar) -> Scalar {
                    let x2: Scalar = x * x
                    // first term accounts for ZH + |m| = 2, second terms for |m| = 1
                    let firstTerm: Scalar = (a * x2) as Scalar + (b * x) as Scalar + c
                    let secondTerm: Scalar = (d * x) as Scalar * Scalar.sqrt(1.0 as Scalar - x2)
                    return firstTerm + secondTerm
                };

                // This is func' / func'' -- this was computed with Mathematica
                func increment(_ x: Scalar) -> Scalar {
                    let x2: Scalar = x * x
                    var numerator: Scalar = d
                    numerator += ((-2.0 as Scalar) * d * x2) as Scalar
                    numerator += (b + (2.0 as Scalar) * (a * x) as Scalar) as Scalar * Scalar.sqrt(1.0 as Scalar - x2) as Scalar
                    numerator *= (x2 - (1.0 as Scalar)) as Scalar
                    
                    var denominator: Scalar = (3.0 as Scalar) * d * x
                    denominator += (-2.0 as Scalar) * d * x2 * x as Scalar
                    denominator += (-2.0 as Scalar) * a * Scalar.pow(1 as Scalar - x2, 1.5 as Scalar) as Scalar
                    return numerator / denominator
                }

                var dz = 0.0 as Scalar
                var z = (-1.0 as Scalar) / Scalar.sqrt(2.0);   // we start guessing at the min of |m|=1 function
                repeat {
                    minimum = testFunc(z) // evaluate our function
                    dz = increment(z) // refine our guess by this amount
                    z = z - dz
                    // exit if z goes out of range, or if we have reached enough precision
                } while (abs(z) <= 1 && abs(dz) > 1e-5)

                if (abs(z) > 1) {
                    // z was out of range
                    minimum = min(testFunc(1), testFunc(-1))
                }
            }
            return minimum
        }

        func windowing(f: SphericalHarmonics.L2Function<Scalar>, cutoff: Scalar) -> SphericalHarmonics.L2Function<Scalar> {
            var f = f
            f.l0 *= SphericalHarmonics.sincWindow(l: 0, w: cutoff)
            f.l1 *= SphericalHarmonics.sincWindow(l: 1, w: cutoff)
            f.l2 *= SphericalHarmonics.sincWindow(l: 2, w: cutoff)
            return f
        }

        var cutoff = cutoff
        
        if cutoff == 0 { // auto windowing (default)
            let numBands = 3

            cutoff = Scalar(numBands * 4 + 1) // start at a large band
            
            // We need to process each channel separately
            for SH in [self.r, self.g, self.b] {
                // find a cut-off band that works
                var l = Scalar(numBands)
                var r = cutoff
                var i = 0
                while i < 16 && l + 0.1 < r {
                    let m: Scalar = 0.5 * (l + r) as Scalar
                    if shmin(windowing(f: SH, cutoff: m)) < 0 {
                        r = m
                    } else {
                        l = m
                    }
                    
                    i += 1
                }
                cutoff = min(cutoff, l)
            }
        }

        self.r = windowing(f: self.r, cutoff: cutoff)
        self.g = windowing(f: self.g, cutoff: cutoff)
        self.b = windowing(f: self.b, cutoff: cutoff)
    }
    
    @_specialize(kind: full, where Scalar == Float)
    public func windowed(cutoff: Scalar = 0.0) -> SphericalHarmonics.L2RGBFunction<Scalar> {
        var result = self
        result.window(cutoff: cutoff)
        return result
    }
}
