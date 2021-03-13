// WARNING: This file is generated. Modifications will be lost.

// Copyright (c) 2015-2016 David Turnbull
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and/or associated documentation files (the
// "Materials"), to deal in the Materials without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Materials, and to
// permit persons to whom the Materials are furnished to do so, subject to
// the following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Materials.
//
// THE MATERIALS ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
// IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
// CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
// TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
// MATERIALS OR THE USE OR OTHER DEALINGS IN THE MATERIALS.


extension SIMD2 {
    @inlinable public var xy:SIMD2<Scalar> { get { return SIMD2<Scalar>(x,y) } set { x = newValue.x; y = newValue.y } }
    @inlinable public var yx:SIMD2<Scalar> { get { return SIMD2<Scalar>(y,x) } set { y = newValue.x; x = newValue.y } }
}

extension SIMD3 {
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

extension SIMD4 {
    @inlinable public var xy:SIMD2<Scalar> { get { return SIMD2<Scalar>(x,y) } set { x = newValue.x; y = newValue.y } }
    @inlinable public var xyz:SIMD3<Scalar> { get { return SIMD3<Scalar>(x,y,z) } set { x = newValue.x; y = newValue.y; z = newValue.z } }
    @inlinable public var xyzw:SIMD4<Scalar> { get { return SIMD4<Scalar>(x,y,z,w) } set { x = newValue.x; y = newValue.y; z = newValue.z; w = newValue.w } }
    @inlinable public var xyw:SIMD3<Scalar> { get { return SIMD3<Scalar>(x,y,w) } set { x = newValue.x; y = newValue.y; w = newValue.z } }
    @inlinable public var xywz:SIMD4<Scalar> { get { return SIMD4<Scalar>(x,y,w,z) } set { x = newValue.x; y = newValue.y; w = newValue.z; z = newValue.w } }
    @inlinable public var xz:SIMD2<Scalar> { get { return SIMD2<Scalar>(x,z) } set { x = newValue.x; z = newValue.y } }
    @inlinable public var xzy:SIMD3<Scalar> { get { return SIMD3<Scalar>(x,z,y) } set { x = newValue.x; z = newValue.y; y = newValue.z } }
    @inlinable public var xzyw:SIMD4<Scalar> { get { return SIMD4<Scalar>(x,z,y,w) } set { x = newValue.x; z = newValue.y; y = newValue.z; w = newValue.w } }
    @inlinable public var xzw:SIMD3<Scalar> { get { return SIMD3<Scalar>(x,z,w) } set { x = newValue.x; z = newValue.y; w = newValue.z } }
    @inlinable public var xzwy:SIMD4<Scalar> { get { return SIMD4<Scalar>(x,z,w,y) } set { x = newValue.x; z = newValue.y; w = newValue.z; y = newValue.w } }
    @inlinable public var xw:SIMD2<Scalar> { get { return SIMD2<Scalar>(x,w) } set { x = newValue.x; w = newValue.y } }
    @inlinable public var xwy:SIMD3<Scalar> { get { return SIMD3<Scalar>(x,w,y) } set { x = newValue.x; w = newValue.y; y = newValue.z } }
    @inlinable public var xwyz:SIMD4<Scalar> { get { return SIMD4<Scalar>(x,w,y,z) } set { x = newValue.x; w = newValue.y; y = newValue.z; z = newValue.w } }
    @inlinable public var xwz:SIMD3<Scalar> { get { return SIMD3<Scalar>(x,w,z) } set { x = newValue.x; w = newValue.y; z = newValue.z } }
    @inlinable public var xwzy:SIMD4<Scalar> { get { return SIMD4<Scalar>(x,w,z,y) } set { x = newValue.x; w = newValue.y; z = newValue.z; y = newValue.w } }
    @inlinable public var yx:SIMD2<Scalar> { get { return SIMD2<Scalar>(y,x) } set { y = newValue.x; x = newValue.y } }
    @inlinable public var yxz:SIMD3<Scalar> { get { return SIMD3<Scalar>(y,x,z) } set { y = newValue.x; x = newValue.y; z = newValue.z } }
    @inlinable public var yxzw:SIMD4<Scalar> { get { return SIMD4<Scalar>(y,x,z,w) } set { y = newValue.x; x = newValue.y; z = newValue.z; w = newValue.w } }
    @inlinable public var yxw:SIMD3<Scalar> { get { return SIMD3<Scalar>(y,x,w) } set { y = newValue.x; x = newValue.y; w = newValue.z } }
    @inlinable public var yxwz:SIMD4<Scalar> { get { return SIMD4<Scalar>(y,x,w,z) } set { y = newValue.x; x = newValue.y; w = newValue.z; z = newValue.w } }
    @inlinable public var yz:SIMD2<Scalar> { get { return SIMD2<Scalar>(y,z) } set { y = newValue.x; z = newValue.y } }
    @inlinable public var yzx:SIMD3<Scalar> { get { return SIMD3<Scalar>(y,z,x) } set { y = newValue.x; z = newValue.y; x = newValue.z } }
    @inlinable public var yzxw:SIMD4<Scalar> { get { return SIMD4<Scalar>(y,z,x,w) } set { y = newValue.x; z = newValue.y; x = newValue.z; w = newValue.w } }
    @inlinable public var yzw:SIMD3<Scalar> { get { return SIMD3<Scalar>(y,z,w) } set { y = newValue.x; z = newValue.y; w = newValue.z } }
    @inlinable public var yzwx:SIMD4<Scalar> { get { return SIMD4<Scalar>(y,z,w,x) } set { y = newValue.x; z = newValue.y; w = newValue.z; x = newValue.w } }
    @inlinable public var yw:SIMD2<Scalar> { get { return SIMD2<Scalar>(y,w) } set { y = newValue.x; w = newValue.y } }
    @inlinable public var ywx:SIMD3<Scalar> { get { return SIMD3<Scalar>(y,w,x) } set { y = newValue.x; w = newValue.y; x = newValue.z } }
    @inlinable public var ywxz:SIMD4<Scalar> { get { return SIMD4<Scalar>(y,w,x,z) } set { y = newValue.x; w = newValue.y; x = newValue.z; z = newValue.w } }
    @inlinable public var ywz:SIMD3<Scalar> { get { return SIMD3<Scalar>(y,w,z) } set { y = newValue.x; w = newValue.y; z = newValue.z } }
    @inlinable public var ywzx:SIMD4<Scalar> { get { return SIMD4<Scalar>(y,w,z,x) } set { y = newValue.x; w = newValue.y; z = newValue.z; x = newValue.w } }
    @inlinable public var zx:SIMD2<Scalar> { get { return SIMD2<Scalar>(z,x) } set { z = newValue.x; x = newValue.y } }
    @inlinable public var zxy:SIMD3<Scalar> { get { return SIMD3<Scalar>(z,x,y) } set { z = newValue.x; x = newValue.y; y = newValue.z } }
    @inlinable public var zxyw:SIMD4<Scalar> { get { return SIMD4<Scalar>(z,x,y,w) } set { z = newValue.x; x = newValue.y; y = newValue.z; w = newValue.w } }
    @inlinable public var zxw:SIMD3<Scalar> { get { return SIMD3<Scalar>(z,x,w) } set { z = newValue.x; x = newValue.y; w = newValue.z } }
    @inlinable public var zxwy:SIMD4<Scalar> { get { return SIMD4<Scalar>(z,x,w,y) } set { z = newValue.x; x = newValue.y; w = newValue.z; y = newValue.w } }
    @inlinable public var zy:SIMD2<Scalar> { get { return SIMD2<Scalar>(z,y) } set { z = newValue.x; y = newValue.y } }
    @inlinable public var zyx:SIMD3<Scalar> { get { return SIMD3<Scalar>(z,y,x) } set { z = newValue.x; y = newValue.y; x = newValue.z } }
    @inlinable public var zyxw:SIMD4<Scalar> { get { return SIMD4<Scalar>(z,y,x,w) } set { z = newValue.x; y = newValue.y; x = newValue.z; w = newValue.w } }
    @inlinable public var zyw:SIMD3<Scalar> { get { return SIMD3<Scalar>(z,y,w) } set { z = newValue.x; y = newValue.y; w = newValue.z } }
    @inlinable public var zywx:SIMD4<Scalar> { get { return SIMD4<Scalar>(z,y,w,x) } set { z = newValue.x; y = newValue.y; w = newValue.z; x = newValue.w } }
    @inlinable public var zw:SIMD2<Scalar> { get { return SIMD2<Scalar>(z,w) } set { z = newValue.x; w = newValue.y } }
    @inlinable public var zwx:SIMD3<Scalar> { get { return SIMD3<Scalar>(z,w,x) } set { z = newValue.x; w = newValue.y; x = newValue.z } }
    @inlinable public var zwxy:SIMD4<Scalar> { get { return SIMD4<Scalar>(z,w,x,y) } set { z = newValue.x; w = newValue.y; x = newValue.z; y = newValue.w } }
    @inlinable public var zwy:SIMD3<Scalar> { get { return SIMD3<Scalar>(z,w,y) } set { z = newValue.x; w = newValue.y; y = newValue.z } }
    @inlinable public var zwyx:SIMD4<Scalar> { get { return SIMD4<Scalar>(z,w,y,x) } set { z = newValue.x; w = newValue.y; y = newValue.z; x = newValue.w } }
    @inlinable public var wx:SIMD2<Scalar> { get { return SIMD2<Scalar>(w,x) } set { w = newValue.x; x = newValue.y } }
    @inlinable public var wxy:SIMD3<Scalar> { get { return SIMD3<Scalar>(w,x,y) } set { w = newValue.x; x = newValue.y; y = newValue.z } }
    @inlinable public var wxyz:SIMD4<Scalar> { get { return SIMD4<Scalar>(w,x,y,z) } set { w = newValue.x; x = newValue.y; y = newValue.z; z = newValue.w } }
    @inlinable public var wxz:SIMD3<Scalar> { get { return SIMD3<Scalar>(w,x,z) } set { w = newValue.x; x = newValue.y; z = newValue.z } }
    @inlinable public var wxzy:SIMD4<Scalar> { get { return SIMD4<Scalar>(w,x,z,y) } set { w = newValue.x; x = newValue.y; z = newValue.z; y = newValue.w } }
    @inlinable public var wy:SIMD2<Scalar> { get { return SIMD2<Scalar>(w,y) } set { w = newValue.x; y = newValue.y } }
    @inlinable public var wyx:SIMD3<Scalar> { get { return SIMD3<Scalar>(w,y,x) } set { w = newValue.x; y = newValue.y; x = newValue.z } }
    @inlinable public var wyxz:SIMD4<Scalar> { get { return SIMD4<Scalar>(w,y,x,z) } set { w = newValue.x; y = newValue.y; x = newValue.z; z = newValue.w } }
    @inlinable public var wyz:SIMD3<Scalar> { get { return SIMD3<Scalar>(w,y,z) } set { w = newValue.x; y = newValue.y; z = newValue.z } }
    @inlinable public var wyzx:SIMD4<Scalar> { get { return SIMD4<Scalar>(w,y,z,x) } set { w = newValue.x; y = newValue.y; z = newValue.z; x = newValue.w } }
    @inlinable public var wz:SIMD2<Scalar> { get { return SIMD2<Scalar>(w,z) } set { w = newValue.x; z = newValue.y } }
    @inlinable public var wzx:SIMD3<Scalar> { get { return SIMD3<Scalar>(w,z,x) } set { w = newValue.x; z = newValue.y; x = newValue.z } }
    @inlinable public var wzxy:SIMD4<Scalar> { get { return SIMD4<Scalar>(w,z,x,y) } set { w = newValue.x; z = newValue.y; x = newValue.z; y = newValue.w } }
    @inlinable public var wzy:SIMD3<Scalar> { get { return SIMD3<Scalar>(w,z,y) } set { w = newValue.x; z = newValue.y; y = newValue.z } }
    @inlinable public var wzyx:SIMD4<Scalar> { get { return SIMD4<Scalar>(w,z,y,x) } set { w = newValue.x; z = newValue.y; y = newValue.z; x = newValue.w } }
}
