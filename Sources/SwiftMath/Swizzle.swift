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


extension Vector2f {
    @inlinable public var xy:Vector2f { get { return Vector2f(x,y) } set { x = newValue.x; y = newValue.y } }
    @inlinable public var yx:Vector2f { get { return Vector2f(y,x) } set { y = newValue.x; x = newValue.y } }
    @inlinable public var rg:Vector2f { get { return Vector2f(x,y) } set { x = newValue.x; y = newValue.y } }
    @inlinable public var gr:Vector2f { get { return Vector2f(y,x) } set { y = newValue.x; x = newValue.y } }
    @inlinable public var st:Vector2f { get { return Vector2f(x,y) } set { x = newValue.x; y = newValue.y } }
    @inlinable public var ts:Vector2f { get { return Vector2f(y,x) } set { y = newValue.x; x = newValue.y } }
}

extension Vector3f {
    @inlinable public var xy:Vector2f { get { return Vector2f(x,y) } set { x = newValue.x; y = newValue.y } }
    @inlinable public var xyz:Vector3f { get { return Vector3f(x,y,z) } set { x = newValue.x; y = newValue.y; z = newValue.z } }
    @inlinable public var xz:Vector2f { get { return Vector2f(x,z) } set { x = newValue.x; z = newValue.y } }
    @inlinable public var xzy:Vector3f { get { return Vector3f(x,z,y) } set { x = newValue.x; z = newValue.y; y = newValue.z } }
    @inlinable public var yx:Vector2f { get { return Vector2f(y,x) } set { y = newValue.x; x = newValue.y } }
    @inlinable public var yxz:Vector3f { get { return Vector3f(y,x,z) } set { y = newValue.x; x = newValue.y; z = newValue.z } }
    @inlinable public var yz:Vector2f { get { return Vector2f(y,z) } set { y = newValue.x; z = newValue.y } }
    @inlinable public var yzx:Vector3f { get { return Vector3f(y,z,x) } set { y = newValue.x; z = newValue.y; x = newValue.z } }
    @inlinable public var zx:Vector2f { get { return Vector2f(z,x) } set { z = newValue.x; x = newValue.y } }
    @inlinable public var zxy:Vector3f { get { return Vector3f(z,x,y) } set { z = newValue.x; x = newValue.y; y = newValue.z } }
    @inlinable public var zy:Vector2f { get { return Vector2f(z,y) } set { z = newValue.x; y = newValue.y } }
    @inlinable public var zyx:Vector3f { get { return Vector3f(z,y,x) } set { z = newValue.x; y = newValue.y; x = newValue.z } }
    @inlinable public var rg:Vector2f { get { return Vector2f(x,y) } set { x = newValue.x; y = newValue.y } }
    @inlinable public var rgb:Vector3f { get { return Vector3f(x,y,z) } set { x = newValue.x; y = newValue.y; z = newValue.z } }
    @inlinable public var rb:Vector2f { get { return Vector2f(x,z) } set { x = newValue.x; z = newValue.y } }
    @inlinable public var rbg:Vector3f { get { return Vector3f(x,z,y) } set { x = newValue.x; z = newValue.y; y = newValue.z } }
    @inlinable public var gr:Vector2f { get { return Vector2f(y,x) } set { y = newValue.x; x = newValue.y } }
    @inlinable public var grb:Vector3f { get { return Vector3f(y,x,z) } set { y = newValue.x; x = newValue.y; z = newValue.z } }
    @inlinable public var gb:Vector2f { get { return Vector2f(y,z) } set { y = newValue.x; z = newValue.y } }
    @inlinable public var gbr:Vector3f { get { return Vector3f(y,z,x) } set { y = newValue.x; z = newValue.y; x = newValue.z } }
    @inlinable public var br:Vector2f { get { return Vector2f(z,x) } set { z = newValue.x; x = newValue.y } }
    @inlinable public var brg:Vector3f { get { return Vector3f(z,x,y) } set { z = newValue.x; x = newValue.y; y = newValue.z } }
    @inlinable public var bg:Vector2f { get { return Vector2f(z,y) } set { z = newValue.x; y = newValue.y } }
    @inlinable public var bgr:Vector3f { get { return Vector3f(z,y,x) } set { z = newValue.x; y = newValue.y; x = newValue.z } }
    @inlinable public var st:Vector2f { get { return Vector2f(x,y) } set { x = newValue.x; y = newValue.y } }
    @inlinable public var stp:Vector3f { get { return Vector3f(x,y,z) } set { x = newValue.x; y = newValue.y; z = newValue.z } }
    @inlinable public var sp:Vector2f { get { return Vector2f(x,z) } set { x = newValue.x; z = newValue.y } }
    @inlinable public var spt:Vector3f { get { return Vector3f(x,z,y) } set { x = newValue.x; z = newValue.y; y = newValue.z } }
    @inlinable public var ts:Vector2f { get { return Vector2f(y,x) } set { y = newValue.x; x = newValue.y } }
    @inlinable public var tsp:Vector3f { get { return Vector3f(y,x,z) } set { y = newValue.x; x = newValue.y; z = newValue.z } }
    @inlinable public var tp:Vector2f { get { return Vector2f(y,z) } set { y = newValue.x; z = newValue.y } }
    @inlinable public var tps:Vector3f { get { return Vector3f(y,z,x) } set { y = newValue.x; z = newValue.y; x = newValue.z } }
    @inlinable public var ps:Vector2f { get { return Vector2f(z,x) } set { z = newValue.x; x = newValue.y } }
    @inlinable public var pst:Vector3f { get { return Vector3f(z,x,y) } set { z = newValue.x; x = newValue.y; y = newValue.z } }
    @inlinable public var pt:Vector2f { get { return Vector2f(z,y) } set { z = newValue.x; y = newValue.y } }
    @inlinable public var pts:Vector3f { get { return Vector3f(z,y,x) } set { z = newValue.x; y = newValue.y; x = newValue.z } }
}

extension Vector4f {
    @inlinable public var xy:Vector2f { get { return Vector2f(x,y) } set { x = newValue.x; y = newValue.y } }
    @inlinable public var xyz:Vector3f { get { return Vector3f(x,y,z) } set { x = newValue.x; y = newValue.y; z = newValue.z } }
    @inlinable public var xyzw:Vector4f { get { return Vector4f(x,y,z,w) } set { x = newValue.x; y = newValue.y; z = newValue.z; w = newValue.w } }
    @inlinable public var xyw:Vector3f { get { return Vector3f(x,y,w) } set { x = newValue.x; y = newValue.y; w = newValue.z } }
    @inlinable public var xywz:Vector4f { get { return Vector4f(x,y,w,z) } set { x = newValue.x; y = newValue.y; w = newValue.z; z = newValue.w } }
    @inlinable public var xz:Vector2f { get { return Vector2f(x,z) } set { x = newValue.x; z = newValue.y } }
    @inlinable public var xzy:Vector3f { get { return Vector3f(x,z,y) } set { x = newValue.x; z = newValue.y; y = newValue.z } }
    @inlinable public var xzyw:Vector4f { get { return Vector4f(x,z,y,w) } set { x = newValue.x; z = newValue.y; y = newValue.z; w = newValue.w } }
    @inlinable public var xzw:Vector3f { get { return Vector3f(x,z,w) } set { x = newValue.x; z = newValue.y; w = newValue.z } }
    @inlinable public var xzwy:Vector4f { get { return Vector4f(x,z,w,y) } set { x = newValue.x; z = newValue.y; w = newValue.z; y = newValue.w } }
    @inlinable public var xw:Vector2f { get { return Vector2f(x,w) } set { x = newValue.x; w = newValue.y } }
    @inlinable public var xwy:Vector3f { get { return Vector3f(x,w,y) } set { x = newValue.x; w = newValue.y; y = newValue.z } }
    @inlinable public var xwyz:Vector4f { get { return Vector4f(x,w,y,z) } set { x = newValue.x; w = newValue.y; y = newValue.z; z = newValue.w } }
    @inlinable public var xwz:Vector3f { get { return Vector3f(x,w,z) } set { x = newValue.x; w = newValue.y; z = newValue.z } }
    @inlinable public var xwzy:Vector4f { get { return Vector4f(x,w,z,y) } set { x = newValue.x; w = newValue.y; z = newValue.z; y = newValue.w } }
    @inlinable public var yx:Vector2f { get { return Vector2f(y,x) } set { y = newValue.x; x = newValue.y } }
    @inlinable public var yxz:Vector3f { get { return Vector3f(y,x,z) } set { y = newValue.x; x = newValue.y; z = newValue.z } }
    @inlinable public var yxzw:Vector4f { get { return Vector4f(y,x,z,w) } set { y = newValue.x; x = newValue.y; z = newValue.z; w = newValue.w } }
    @inlinable public var yxw:Vector3f { get { return Vector3f(y,x,w) } set { y = newValue.x; x = newValue.y; w = newValue.z } }
    @inlinable public var yxwz:Vector4f { get { return Vector4f(y,x,w,z) } set { y = newValue.x; x = newValue.y; w = newValue.z; z = newValue.w } }
    @inlinable public var yz:Vector2f { get { return Vector2f(y,z) } set { y = newValue.x; z = newValue.y } }
    @inlinable public var yzx:Vector3f { get { return Vector3f(y,z,x) } set { y = newValue.x; z = newValue.y; x = newValue.z } }
    @inlinable public var yzxw:Vector4f { get { return Vector4f(y,z,x,w) } set { y = newValue.x; z = newValue.y; x = newValue.z; w = newValue.w } }
    @inlinable public var yzw:Vector3f { get { return Vector3f(y,z,w) } set { y = newValue.x; z = newValue.y; w = newValue.z } }
    @inlinable public var yzwx:Vector4f { get { return Vector4f(y,z,w,x) } set { y = newValue.x; z = newValue.y; w = newValue.z; x = newValue.w } }
    @inlinable public var yw:Vector2f { get { return Vector2f(y,w) } set { y = newValue.x; w = newValue.y } }
    @inlinable public var ywx:Vector3f { get { return Vector3f(y,w,x) } set { y = newValue.x; w = newValue.y; x = newValue.z } }
    @inlinable public var ywxz:Vector4f { get { return Vector4f(y,w,x,z) } set { y = newValue.x; w = newValue.y; x = newValue.z; z = newValue.w } }
    @inlinable public var ywz:Vector3f { get { return Vector3f(y,w,z) } set { y = newValue.x; w = newValue.y; z = newValue.z } }
    @inlinable public var ywzx:Vector4f { get { return Vector4f(y,w,z,x) } set { y = newValue.x; w = newValue.y; z = newValue.z; x = newValue.w } }
    @inlinable public var zx:Vector2f { get { return Vector2f(z,x) } set { z = newValue.x; x = newValue.y } }
    @inlinable public var zxy:Vector3f { get { return Vector3f(z,x,y) } set { z = newValue.x; x = newValue.y; y = newValue.z } }
    @inlinable public var zxyw:Vector4f { get { return Vector4f(z,x,y,w) } set { z = newValue.x; x = newValue.y; y = newValue.z; w = newValue.w } }
    @inlinable public var zxw:Vector3f { get { return Vector3f(z,x,w) } set { z = newValue.x; x = newValue.y; w = newValue.z } }
    @inlinable public var zxwy:Vector4f { get { return Vector4f(z,x,w,y) } set { z = newValue.x; x = newValue.y; w = newValue.z; y = newValue.w } }
    @inlinable public var zy:Vector2f { get { return Vector2f(z,y) } set { z = newValue.x; y = newValue.y } }
    @inlinable public var zyx:Vector3f { get { return Vector3f(z,y,x) } set { z = newValue.x; y = newValue.y; x = newValue.z } }
    @inlinable public var zyxw:Vector4f { get { return Vector4f(z,y,x,w) } set { z = newValue.x; y = newValue.y; x = newValue.z; w = newValue.w } }
    @inlinable public var zyw:Vector3f { get { return Vector3f(z,y,w) } set { z = newValue.x; y = newValue.y; w = newValue.z } }
    @inlinable public var zywx:Vector4f { get { return Vector4f(z,y,w,x) } set { z = newValue.x; y = newValue.y; w = newValue.z; x = newValue.w } }
    @inlinable public var zw:Vector2f { get { return Vector2f(z,w) } set { z = newValue.x; w = newValue.y } }
    @inlinable public var zwx:Vector3f { get { return Vector3f(z,w,x) } set { z = newValue.x; w = newValue.y; x = newValue.z } }
    @inlinable public var zwxy:Vector4f { get { return Vector4f(z,w,x,y) } set { z = newValue.x; w = newValue.y; x = newValue.z; y = newValue.w } }
    @inlinable public var zwy:Vector3f { get { return Vector3f(z,w,y) } set { z = newValue.x; w = newValue.y; y = newValue.z } }
    @inlinable public var zwyx:Vector4f { get { return Vector4f(z,w,y,x) } set { z = newValue.x; w = newValue.y; y = newValue.z; x = newValue.w } }
    @inlinable public var wx:Vector2f { get { return Vector2f(w,x) } set { w = newValue.x; x = newValue.y } }
    @inlinable public var wxy:Vector3f { get { return Vector3f(w,x,y) } set { w = newValue.x; x = newValue.y; y = newValue.z } }
    @inlinable public var wxyz:Vector4f { get { return Vector4f(w,x,y,z) } set { w = newValue.x; x = newValue.y; y = newValue.z; z = newValue.w } }
    @inlinable public var wxz:Vector3f { get { return Vector3f(w,x,z) } set { w = newValue.x; x = newValue.y; z = newValue.z } }
    @inlinable public var wxzy:Vector4f { get { return Vector4f(w,x,z,y) } set { w = newValue.x; x = newValue.y; z = newValue.z; y = newValue.w } }
    @inlinable public var wy:Vector2f { get { return Vector2f(w,y) } set { w = newValue.x; y = newValue.y } }
    @inlinable public var wyx:Vector3f { get { return Vector3f(w,y,x) } set { w = newValue.x; y = newValue.y; x = newValue.z } }
    @inlinable public var wyxz:Vector4f { get { return Vector4f(w,y,x,z) } set { w = newValue.x; y = newValue.y; x = newValue.z; z = newValue.w } }
    @inlinable public var wyz:Vector3f { get { return Vector3f(w,y,z) } set { w = newValue.x; y = newValue.y; z = newValue.z } }
    @inlinable public var wyzx:Vector4f { get { return Vector4f(w,y,z,x) } set { w = newValue.x; y = newValue.y; z = newValue.z; x = newValue.w } }
    @inlinable public var wz:Vector2f { get { return Vector2f(w,z) } set { w = newValue.x; z = newValue.y } }
    @inlinable public var wzx:Vector3f { get { return Vector3f(w,z,x) } set { w = newValue.x; z = newValue.y; x = newValue.z } }
    @inlinable public var wzxy:Vector4f { get { return Vector4f(w,z,x,y) } set { w = newValue.x; z = newValue.y; x = newValue.z; y = newValue.w } }
    @inlinable public var wzy:Vector3f { get { return Vector3f(w,z,y) } set { w = newValue.x; z = newValue.y; y = newValue.z } }
    @inlinable public var wzyx:Vector4f { get { return Vector4f(w,z,y,x) } set { w = newValue.x; z = newValue.y; y = newValue.z; x = newValue.w } }
    @inlinable public var rg:Vector2f { get { return Vector2f(x,y) } set { x = newValue.x; y = newValue.y } }
    @inlinable public var rgb:Vector3f { get { return Vector3f(x,y,z) } set { x = newValue.x; y = newValue.y; z = newValue.z } }
    @inlinable public var rgba:Vector4f { get { return Vector4f(x,y,z,w) } set { x = newValue.x; y = newValue.y; z = newValue.z; w = newValue.w } }
    @inlinable public var rga:Vector3f { get { return Vector3f(x,y,w) } set { x = newValue.x; y = newValue.y; w = newValue.z } }
    @inlinable public var rgab:Vector4f { get { return Vector4f(x,y,w,z) } set { x = newValue.x; y = newValue.y; w = newValue.z; z = newValue.w } }
    @inlinable public var rb:Vector2f { get { return Vector2f(x,z) } set { x = newValue.x; z = newValue.y } }
    @inlinable public var rbg:Vector3f { get { return Vector3f(x,z,y) } set { x = newValue.x; z = newValue.y; y = newValue.z } }
    @inlinable public var rbga:Vector4f { get { return Vector4f(x,z,y,w) } set { x = newValue.x; z = newValue.y; y = newValue.z; w = newValue.w } }
    @inlinable public var rba:Vector3f { get { return Vector3f(x,z,w) } set { x = newValue.x; z = newValue.y; w = newValue.z } }
    @inlinable public var rbag:Vector4f { get { return Vector4f(x,z,w,y) } set { x = newValue.x; z = newValue.y; w = newValue.z; y = newValue.w } }
    @inlinable public var ra:Vector2f { get { return Vector2f(x,w) } set { x = newValue.x; w = newValue.y } }
    @inlinable public var rag:Vector3f { get { return Vector3f(x,w,y) } set { x = newValue.x; w = newValue.y; y = newValue.z } }
    @inlinable public var ragb:Vector4f { get { return Vector4f(x,w,y,z) } set { x = newValue.x; w = newValue.y; y = newValue.z; z = newValue.w } }
    @inlinable public var rab:Vector3f { get { return Vector3f(x,w,z) } set { x = newValue.x; w = newValue.y; z = newValue.z } }
    @inlinable public var rabg:Vector4f { get { return Vector4f(x,w,z,y) } set { x = newValue.x; w = newValue.y; z = newValue.z; y = newValue.w } }
    @inlinable public var gr:Vector2f { get { return Vector2f(y,x) } set { y = newValue.x; x = newValue.y } }
    @inlinable public var grb:Vector3f { get { return Vector3f(y,x,z) } set { y = newValue.x; x = newValue.y; z = newValue.z } }
    @inlinable public var grba:Vector4f { get { return Vector4f(y,x,z,w) } set { y = newValue.x; x = newValue.y; z = newValue.z; w = newValue.w } }
    @inlinable public var gra:Vector3f { get { return Vector3f(y,x,w) } set { y = newValue.x; x = newValue.y; w = newValue.z } }
    @inlinable public var grab:Vector4f { get { return Vector4f(y,x,w,z) } set { y = newValue.x; x = newValue.y; w = newValue.z; z = newValue.w } }
    @inlinable public var gb:Vector2f { get { return Vector2f(y,z) } set { y = newValue.x; z = newValue.y } }
    @inlinable public var gbr:Vector3f { get { return Vector3f(y,z,x) } set { y = newValue.x; z = newValue.y; x = newValue.z } }
    @inlinable public var gbra:Vector4f { get { return Vector4f(y,z,x,w) } set { y = newValue.x; z = newValue.y; x = newValue.z; w = newValue.w } }
    @inlinable public var gba:Vector3f { get { return Vector3f(y,z,w) } set { y = newValue.x; z = newValue.y; w = newValue.z } }
    @inlinable public var gbar:Vector4f { get { return Vector4f(y,z,w,x) } set { y = newValue.x; z = newValue.y; w = newValue.z; x = newValue.w } }
    @inlinable public var ga:Vector2f { get { return Vector2f(y,w) } set { y = newValue.x; w = newValue.y } }
    @inlinable public var gar:Vector3f { get { return Vector3f(y,w,x) } set { y = newValue.x; w = newValue.y; x = newValue.z } }
    @inlinable public var garb:Vector4f { get { return Vector4f(y,w,x,z) } set { y = newValue.x; w = newValue.y; x = newValue.z; z = newValue.w } }
    @inlinable public var gab:Vector3f { get { return Vector3f(y,w,z) } set { y = newValue.x; w = newValue.y; z = newValue.z } }
    @inlinable public var gabr:Vector4f { get { return Vector4f(y,w,z,x) } set { y = newValue.x; w = newValue.y; z = newValue.z; x = newValue.w } }
    @inlinable public var br:Vector2f { get { return Vector2f(z,x) } set { z = newValue.x; x = newValue.y } }
    @inlinable public var brg:Vector3f { get { return Vector3f(z,x,y) } set { z = newValue.x; x = newValue.y; y = newValue.z } }
    @inlinable public var brga:Vector4f { get { return Vector4f(z,x,y,w) } set { z = newValue.x; x = newValue.y; y = newValue.z; w = newValue.w } }
    @inlinable public var bra:Vector3f { get { return Vector3f(z,x,w) } set { z = newValue.x; x = newValue.y; w = newValue.z } }
    @inlinable public var brag:Vector4f { get { return Vector4f(z,x,w,y) } set { z = newValue.x; x = newValue.y; w = newValue.z; y = newValue.w } }
    @inlinable public var bg:Vector2f { get { return Vector2f(z,y) } set { z = newValue.x; y = newValue.y } }
    @inlinable public var bgr:Vector3f { get { return Vector3f(z,y,x) } set { z = newValue.x; y = newValue.y; x = newValue.z } }
    @inlinable public var bgra:Vector4f { get { return Vector4f(z,y,x,w) } set { z = newValue.x; y = newValue.y; x = newValue.z; w = newValue.w } }
    @inlinable public var bga:Vector3f { get { return Vector3f(z,y,w) } set { z = newValue.x; y = newValue.y; w = newValue.z } }
    @inlinable public var bgar:Vector4f { get { return Vector4f(z,y,w,x) } set { z = newValue.x; y = newValue.y; w = newValue.z; x = newValue.w } }
    @inlinable public var ba:Vector2f { get { return Vector2f(z,w) } set { z = newValue.x; w = newValue.y } }
    @inlinable public var bar:Vector3f { get { return Vector3f(z,w,x) } set { z = newValue.x; w = newValue.y; x = newValue.z } }
    @inlinable public var barg:Vector4f { get { return Vector4f(z,w,x,y) } set { z = newValue.x; w = newValue.y; x = newValue.z; y = newValue.w } }
    @inlinable public var bag:Vector3f { get { return Vector3f(z,w,y) } set { z = newValue.x; w = newValue.y; y = newValue.z } }
    @inlinable public var bagr:Vector4f { get { return Vector4f(z,w,y,x) } set { z = newValue.x; w = newValue.y; y = newValue.z; x = newValue.w } }
    @inlinable public var ar:Vector2f { get { return Vector2f(w,x) } set { w = newValue.x; x = newValue.y } }
    @inlinable public var arg:Vector3f { get { return Vector3f(w,x,y) } set { w = newValue.x; x = newValue.y; y = newValue.z } }
    @inlinable public var argb:Vector4f { get { return Vector4f(w,x,y,z) } set { w = newValue.x; x = newValue.y; y = newValue.z; z = newValue.w } }
    @inlinable public var arb:Vector3f { get { return Vector3f(w,x,z) } set { w = newValue.x; x = newValue.y; z = newValue.z } }
    @inlinable public var arbg:Vector4f { get { return Vector4f(w,x,z,y) } set { w = newValue.x; x = newValue.y; z = newValue.z; y = newValue.w } }
    @inlinable public var ag:Vector2f { get { return Vector2f(w,y) } set { w = newValue.x; y = newValue.y } }
    @inlinable public var agr:Vector3f { get { return Vector3f(w,y,x) } set { w = newValue.x; y = newValue.y; x = newValue.z } }
    @inlinable public var agrb:Vector4f { get { return Vector4f(w,y,x,z) } set { w = newValue.x; y = newValue.y; x = newValue.z; z = newValue.w } }
    @inlinable public var agb:Vector3f { get { return Vector3f(w,y,z) } set { w = newValue.x; y = newValue.y; z = newValue.z } }
    @inlinable public var agbr:Vector4f { get { return Vector4f(w,y,z,x) } set { w = newValue.x; y = newValue.y; z = newValue.z; x = newValue.w } }
    @inlinable public var ab:Vector2f { get { return Vector2f(w,z) } set { w = newValue.x; z = newValue.y } }
    @inlinable public var abr:Vector3f { get { return Vector3f(w,z,x) } set { w = newValue.x; z = newValue.y; x = newValue.z } }
    @inlinable public var abrg:Vector4f { get { return Vector4f(w,z,x,y) } set { w = newValue.x; z = newValue.y; x = newValue.z; y = newValue.w } }
    @inlinable public var abg:Vector3f { get { return Vector3f(w,z,y) } set { w = newValue.x; z = newValue.y; y = newValue.z } }
    @inlinable public var abgr:Vector4f { get { return Vector4f(w,z,y,x) } set { w = newValue.x; z = newValue.y; y = newValue.z; x = newValue.w } }
    @inlinable public var st:Vector2f { get { return Vector2f(x,y) } set { x = newValue.x; y = newValue.y } }
    @inlinable public var stp:Vector3f { get { return Vector3f(x,y,z) } set { x = newValue.x; y = newValue.y; z = newValue.z } }
    @inlinable public var stpq:Vector4f { get { return Vector4f(x,y,z,w) } set { x = newValue.x; y = newValue.y; z = newValue.z; w = newValue.w } }
    @inlinable public var stq:Vector3f { get { return Vector3f(x,y,w) } set { x = newValue.x; y = newValue.y; w = newValue.z } }
    @inlinable public var stqp:Vector4f { get { return Vector4f(x,y,w,z) } set { x = newValue.x; y = newValue.y; w = newValue.z; z = newValue.w } }
    @inlinable public var sp:Vector2f { get { return Vector2f(x,z) } set { x = newValue.x; z = newValue.y } }
    @inlinable public var spt:Vector3f { get { return Vector3f(x,z,y) } set { x = newValue.x; z = newValue.y; y = newValue.z } }
    @inlinable public var sptq:Vector4f { get { return Vector4f(x,z,y,w) } set { x = newValue.x; z = newValue.y; y = newValue.z; w = newValue.w } }
    @inlinable public var spq:Vector3f { get { return Vector3f(x,z,w) } set { x = newValue.x; z = newValue.y; w = newValue.z } }
    @inlinable public var spqt:Vector4f { get { return Vector4f(x,z,w,y) } set { x = newValue.x; z = newValue.y; w = newValue.z; y = newValue.w } }
    @inlinable public var sq:Vector2f { get { return Vector2f(x,w) } set { x = newValue.x; w = newValue.y } }
    @inlinable public var sqt:Vector3f { get { return Vector3f(x,w,y) } set { x = newValue.x; w = newValue.y; y = newValue.z } }
    @inlinable public var sqtp:Vector4f { get { return Vector4f(x,w,y,z) } set { x = newValue.x; w = newValue.y; y = newValue.z; z = newValue.w } }
    @inlinable public var sqp:Vector3f { get { return Vector3f(x,w,z) } set { x = newValue.x; w = newValue.y; z = newValue.z } }
    @inlinable public var sqpt:Vector4f { get { return Vector4f(x,w,z,y) } set { x = newValue.x; w = newValue.y; z = newValue.z; y = newValue.w } }
    @inlinable public var ts:Vector2f { get { return Vector2f(y,x) } set { y = newValue.x; x = newValue.y } }
    @inlinable public var tsp:Vector3f { get { return Vector3f(y,x,z) } set { y = newValue.x; x = newValue.y; z = newValue.z } }
    @inlinable public var tspq:Vector4f { get { return Vector4f(y,x,z,w) } set { y = newValue.x; x = newValue.y; z = newValue.z; w = newValue.w } }
    @inlinable public var tsq:Vector3f { get { return Vector3f(y,x,w) } set { y = newValue.x; x = newValue.y; w = newValue.z } }
    @inlinable public var tsqp:Vector4f { get { return Vector4f(y,x,w,z) } set { y = newValue.x; x = newValue.y; w = newValue.z; z = newValue.w } }
    @inlinable public var tp:Vector2f { get { return Vector2f(y,z) } set { y = newValue.x; z = newValue.y } }
    @inlinable public var tps:Vector3f { get { return Vector3f(y,z,x) } set { y = newValue.x; z = newValue.y; x = newValue.z } }
    @inlinable public var tpsq:Vector4f { get { return Vector4f(y,z,x,w) } set { y = newValue.x; z = newValue.y; x = newValue.z; w = newValue.w } }
    @inlinable public var tpq:Vector3f { get { return Vector3f(y,z,w) } set { y = newValue.x; z = newValue.y; w = newValue.z } }
    @inlinable public var tpqs:Vector4f { get { return Vector4f(y,z,w,x) } set { y = newValue.x; z = newValue.y; w = newValue.z; x = newValue.w } }
    @inlinable public var tq:Vector2f { get { return Vector2f(y,w) } set { y = newValue.x; w = newValue.y } }
    @inlinable public var tqs:Vector3f { get { return Vector3f(y,w,x) } set { y = newValue.x; w = newValue.y; x = newValue.z } }
    @inlinable public var tqsp:Vector4f { get { return Vector4f(y,w,x,z) } set { y = newValue.x; w = newValue.y; x = newValue.z; z = newValue.w } }
    @inlinable public var tqp:Vector3f { get { return Vector3f(y,w,z) } set { y = newValue.x; w = newValue.y; z = newValue.z } }
    @inlinable public var tqps:Vector4f { get { return Vector4f(y,w,z,x) } set { y = newValue.x; w = newValue.y; z = newValue.z; x = newValue.w } }
    @inlinable public var ps:Vector2f { get { return Vector2f(z,x) } set { z = newValue.x; x = newValue.y } }
    @inlinable public var pst:Vector3f { get { return Vector3f(z,x,y) } set { z = newValue.x; x = newValue.y; y = newValue.z } }
    @inlinable public var pstq:Vector4f { get { return Vector4f(z,x,y,w) } set { z = newValue.x; x = newValue.y; y = newValue.z; w = newValue.w } }
    @inlinable public var psq:Vector3f { get { return Vector3f(z,x,w) } set { z = newValue.x; x = newValue.y; w = newValue.z } }
    @inlinable public var psqt:Vector4f { get { return Vector4f(z,x,w,y) } set { z = newValue.x; x = newValue.y; w = newValue.z; y = newValue.w } }
    @inlinable public var pt:Vector2f { get { return Vector2f(z,y) } set { z = newValue.x; y = newValue.y } }
    @inlinable public var pts:Vector3f { get { return Vector3f(z,y,x) } set { z = newValue.x; y = newValue.y; x = newValue.z } }
    @inlinable public var ptsq:Vector4f { get { return Vector4f(z,y,x,w) } set { z = newValue.x; y = newValue.y; x = newValue.z; w = newValue.w } }
    @inlinable public var ptq:Vector3f { get { return Vector3f(z,y,w) } set { z = newValue.x; y = newValue.y; w = newValue.z } }
    @inlinable public var ptqs:Vector4f { get { return Vector4f(z,y,w,x) } set { z = newValue.x; y = newValue.y; w = newValue.z; x = newValue.w } }
    @inlinable public var pq:Vector2f { get { return Vector2f(z,w) } set { z = newValue.x; w = newValue.y } }
    @inlinable public var pqs:Vector3f { get { return Vector3f(z,w,x) } set { z = newValue.x; w = newValue.y; x = newValue.z } }
    @inlinable public var pqst:Vector4f { get { return Vector4f(z,w,x,y) } set { z = newValue.x; w = newValue.y; x = newValue.z; y = newValue.w } }
    @inlinable public var pqt:Vector3f { get { return Vector3f(z,w,y) } set { z = newValue.x; w = newValue.y; y = newValue.z } }
    @inlinable public var pqts:Vector4f { get { return Vector4f(z,w,y,x) } set { z = newValue.x; w = newValue.y; y = newValue.z; x = newValue.w } }
    @inlinable public var qs:Vector2f { get { return Vector2f(w,x) } set { w = newValue.x; x = newValue.y } }
    @inlinable public var qst:Vector3f { get { return Vector3f(w,x,y) } set { w = newValue.x; x = newValue.y; y = newValue.z } }
    @inlinable public var qstp:Vector4f { get { return Vector4f(w,x,y,z) } set { w = newValue.x; x = newValue.y; y = newValue.z; z = newValue.w } }
    @inlinable public var qsp:Vector3f { get { return Vector3f(w,x,z) } set { w = newValue.x; x = newValue.y; z = newValue.z } }
    @inlinable public var qspt:Vector4f { get { return Vector4f(w,x,z,y) } set { w = newValue.x; x = newValue.y; z = newValue.z; y = newValue.w } }
    @inlinable public var qt:Vector2f { get { return Vector2f(w,y) } set { w = newValue.x; y = newValue.y } }
    @inlinable public var qts:Vector3f { get { return Vector3f(w,y,x) } set { w = newValue.x; y = newValue.y; x = newValue.z } }
    @inlinable public var qtsp:Vector4f { get { return Vector4f(w,y,x,z) } set { w = newValue.x; y = newValue.y; x = newValue.z; z = newValue.w } }
    @inlinable public var qtp:Vector3f { get { return Vector3f(w,y,z) } set { w = newValue.x; y = newValue.y; z = newValue.z } }
    @inlinable public var qtps:Vector4f { get { return Vector4f(w,y,z,x) } set { w = newValue.x; y = newValue.y; z = newValue.z; x = newValue.w } }
    @inlinable public var qp:Vector2f { get { return Vector2f(w,z) } set { w = newValue.x; z = newValue.y } }
    @inlinable public var qps:Vector3f { get { return Vector3f(w,z,x) } set { w = newValue.x; z = newValue.y; x = newValue.z } }
    @inlinable public var qpst:Vector4f { get { return Vector4f(w,z,x,y) } set { w = newValue.x; z = newValue.y; x = newValue.z; y = newValue.w } }
    @inlinable public var qpt:Vector3f { get { return Vector3f(w,z,y) } set { w = newValue.x; z = newValue.y; y = newValue.z } }
    @inlinable public var qpts:Vector4f { get { return Vector4f(w,z,y,x) } set { w = newValue.x; z = newValue.y; y = newValue.z; x = newValue.w } }
}
