//
//  Matrix3x4.swift
//  CGRAGame
//
//  Created by Thomas Roughton on 6/06/17.
//  Copyright © 2017 Team Llama. All rights reserved.
//

#if !NOSIMD
    import simd
    
    /// Represents a standard 3x4 transformation matrix.
    /// - remark:
    /// Matrices are stored in column-major order
    public struct Matrix3x4f : Equatable {
        public var d: float3x4 = float3x4()
        
        //MARK: - initializers
        
        /// Creates an instance initialized to zero
        public init() {
        }
        
        /// Creates an instance using the vector to initialize the diagonal elements
        @inlinable
        public init(diagonal v: Vector3f) {
            self.init()
            self.d = float3x4(diagonal: v.d)
        }
        
        /// Creates an instance with the specified columns
        ///
        /// - parameter c0: a vector representing column 0
        /// - parameter c1: a vector representing column 1
        /// - parameter c2: a vector representing column 2
        /// - parameter c3: a vector representing column 3
        @inlinable
        public init(_ c0: Vector4f, _ c1: Vector4f, _ c2: Vector4f) {
            self.init()
            self.d = float3x4(columns: (c0.d, c1.d, c2.d))
        }
        
        //MARK:- properties
        
//        public var transpose : Matrix4x3f {
//            return unsafeBitCast(d.transpose, to: Matrix3x4f.self)
//        }
        
        
        // MARK: - subscript operations
        
        /// Access the `col`th column vector
        @inlinable
        public subscript(col: Int) -> Vector4f {
            get {
                return unsafeBitCast(d[col], to: Vector4f.self)
            }
            
            set {
                d[col] = newValue.d
            }
        }
        
        /// Access the `col`th column vector and then `row`th element
        @inlinable
        public subscript(col: Int, row: Int) -> Float {
            get {
                return d[col, row]
            }
            
            set {
                d[col, row] = newValue
            }
        }
        
        //MARK:- operators
        
        @inlinable
        public static prefix func -(lhs: Matrix3x4f) -> Matrix3x4f {
            return unsafeBitCast(-lhs.d, to: Matrix3x4f.self)
        }
        
        @inlinable
        public static func *(lhs: Matrix3x4f, rhs: Float) -> Matrix3x4f {
            return unsafeBitCast(lhs.d * rhs, to: Matrix3x4f.self)
        }
        
        @inlinable
        public static func ==(lhs: Matrix3x4f, rhs: Matrix3x4f) -> Bool {
            return lhs[0] == rhs[0] && lhs[1] == rhs[1] && lhs[2] == rhs[2]
        }
    }
    
#endif

