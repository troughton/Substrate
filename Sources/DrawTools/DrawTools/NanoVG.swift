//
//  NanoVG.swift
//  InterdimensionalLlama
//
//  Created by Thomas Roughton on 14/11/16.
//
//

// #if os(macOS)
// import Darwin
// #else
// import Glibc
// #endif

// import Swift
// import SwiftMath
//
//public let vg = NanoVG(edgeAA: 1, viewId: 0)
//
//func drawEyes(x: Float, y: Float, w: Float, h: Float) {
//    vg.beginFrame(windowWidth: 1280, windowHeight: 720, devicePixelRatio: 1.0)
//    
//    var gloss = NVGpaint()
//    var bg = NVGpaint()
//    
//    let ex = w * 0.23;
//    let ey = h * 0.5;
//    let lx = x + ex;
//    let ly = y + ey;
//    let rx = x + w - ex;
//    let ry = y + ey;
//    var dx : Float, dy : Float, d : Float;
//    let br = (ex < ey ? ex : ey) * 0.5;
//    let blink = 1 - powf(sin(0*0.5),200)*0.8;
//    
//    bg = vg.linearGradient(from: x, y+h*0.5, to: x+w*0.1, y+h, startColour: Colour(bytesR: 0, g: 0, b: 0, a: 32), endColour: Colour(bytesR: 0, g: 0, b: 0, a: 32))
// 
//    vg.beginPath()
//    vg.ellipse(centre: lx + 3.0, ly + 16, radius: ex, ey)
//    vg.ellipse(centre: rx + 3.0, ry + 16, radius: ex, ey)
//    vg.fillPaint(bg)
//    vg.fill()
//    
//    bg = vg.linearGradient(from: x, y + h * 0.25, to: x + 2 * 0.1, y + h, startColour: Colour(bytesR: 220, g: 220, b: 220, a: 255), endColour: Colour(bytesR: 128, g: 128, b: 128, a: 255))
//    vg.beginPath()
//    vg.ellipse(centre: lx, ly, radius: ex, ey)
//    vg.fillPaint(bg)
//    vg.fill()
//    
//    dx = (500 - rx) / (ex * 10);
//    dy = (500 - ry) / (ey * 10);
//    d = sqrtf(dx*dx+dy*dy);
//    if (d > 1.0) {
//        dx /= d; dy /= d;
//    }
//    dx *= ex*0.4;
//    dy *= ey*0.5;
//    
//    vg.beginPath()
//    vg.ellipse(centre: lx + dx, ly + dy + ey * 0.25 * (1 - blink), radius: br, br * blink)
//    vg.fillColour(Colour(bytesR: 32, g: 32, b: 32))
//    vg.fill()
//    
//    dx = (500 - rx) / (ex * 10);
//    dy = (500 - ry) / (ey * 10);
//    d = sqrtf(dx*dx+dy*dy);
//    if (d > 1.0) {
//        dx /= d; dy /= d;
//    }
//    dx *= ex*0.4;
//    dy *= ey*0.5;
//    vg.beginPath()
//    vg.ellipse(centre: rx + dx, ry + dy + ey * 0.25 * (1 - blink), radius: br, br * blink)
//    vg.fillColour(Colour(bytesR: 32, g: 32, b: 32))
//    vg.fill()
//    
//    gloss = vg.radialGradient(centreX: lx-ex*0.25,centreY: ly-ey*0.5, innerRadius: ex*0.1,outerRadius: ex*0.75, innerColour: Colour(bytesR: 255, g: 255, b: 255, a: 128), outerColour: Colour(bytesR: 255, g: 255, b: 255, a: 0) );
//    vg.beginPath()
//    vg.ellipse(centre: lx, ly, radius: ex, ey)
//    vg.fillPaint(gloss)
//    vg.fill()
//    
//    gloss = vg.radialGradient(centreX: rx-ex*0.25,centreY: ry-ey*0.5, innerRadius: ex*0.1,outerRadius: ex*0.75, innerColour: Colour(bytesR: 255, g: 255, b: 255, a: 128), outerColour: Colour(bytesR: 255, g: 255, b: 255, a: 0) );
//    vg.beginPath()
//    vg.ellipse(centre: rx, ry, radius: ex, ey)
//    vg.fillPaint(gloss)
//    vg.fill()
//    
//    vg.endFrame()
//}
//
//public struct Colour {
//    public var rgba : (Float, Float, Float, Float)
//    
//    public var r : Float {
//        get {
//            return self.rgba.0
//        } set (r) {
//            self.rgba.0 = r
//        }
//    }
//    
//    public var g : Float {
//        get {
//            return self.rgba.1
//        } set (g) {
//            self.rgba.1 = g
//        }
//    }
//    
//    public var b : Float {
//        get {
//            return self.rgba.2
//        } set (b) {
//            self.rgba.2 = b
//        }
//    }
//    
//    public var a : Float {
//        get {
//            return self.rgba.3
//        } set (a) {
//            self.rgba.3 = a
//        }
//    }
//    
//    fileprivate init(nvgColour: NVGcolor) {
//        self = unsafeBitCast(nvgColour, to: Colour.self)
//    }
//    
//    fileprivate var nvgColour : NVGcolor {
//        return unsafeBitCast(self, to: NVGcolor.self)
//    }
//    
//    public init(bytesR r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
//        self.init(nvgColour: nvgRGBA(r, g, b, a))
//    }
//    
//    public init(r: Float, g: Float, b: Float, a: Float = 1.0) {
//        self.init(nvgColour: nvgRGBAf(r, g, b, a))
//    }
//    
//    
//    /// Linearly interpolates from color c0 to c1, and returns resulting color value.
//    public static func lerp(from: Colour, to: Colour, t: Float) -> Colour {
//        let c1 = from.nvgColour
//        let c2 = to.nvgColour
//        return Colour(nvgColour: nvgLerpRGBA(c1, c2, t))
//    }
//    
//    public mutating func setTransparency(_ a: UInt8) {
//        self = Colour(nvgColour: nvgTransRGBA(self.nvgColour, a))
//    }
//    
//    public mutating func setTransparency(_ a: Float) {
//        self = Colour(nvgColour: nvgTransRGBAf(self.nvgColour, a))
//    }
//    
//    /// Returns color value specified by hue, saturation and lightness and alpha.
//    /// HSL values are all in range [0..1], alpha in range [0..255]
//    public init(hue: Float, saturation: Float, lightness: Float, alpha: UInt8 = 255) {
//        self.init(nvgColour: nvgHSLA(hue, saturation, lightness, alpha))
//    }
//}
//
//
//public final class NanoVG {
//    
//    private let context : OpaquePointer!
//    
//    public init(edgeAA: Int, viewId: UInt8) {
//        self.context = nvgCreate(Int32(edgeAA), viewId)
//    }
//    
//    deinit {
//        nvgDelete(self.context)
//    }
//    
//    public var viewId : UInt8 {
//        get {
//            return nvgViewId(self.context)
//        }
//        set (newValue) {
//            nvgSetViewId(self.context, newValue)
//        }
//    }
//    
//    // Helper functions to create bgfx framebuffer to render to.
//    // Example:
//    //		float scale = 2;
//    //		NVGLUframebuffer* fb = nvgluCreateFramebuffer(ctx, 100 * scale, 100 * scale, 0);
//    //		nvgluBindFramebuffer(fb);
//    //		nvgBeginFrame(ctx, 100, 100, scale);
//    //		// renders anything offscreen
//    //		nvgEndFrame(ctx);
//    //		nvgluBindFramebuffer(NULL);
//    //
//    //		// Pastes the framebuffer rendering.
//    //		nvgBeginFrame(ctx, 1024, 768, scale);
//    //		NVGpaint paint = nvgImagePattern(ctx, 0, 0, 100, 100, 0, fb->image, 1);
//    //		nvgBeginPath(ctx);
//    //		nvgRect(ctx, 0, 0, 100, 100);
//    //		nvgFillPaint(ctx, paint);
//    //		nvgFill(ctx);
//    //		nvgEndFrame(ctx);
//    
//    public func createBGFXFramebuffer(width: Int, height: Int, imageFlags: Int32) -> UnsafeMutablePointer<NVGLUframebuffer>! {
//        return nvgluCreateFramebuffer(self.context, Int32(width), Int32(height), imageFlags)
//    }
//    
//    public func bindBGFXFramebuffer(_ framebuffer: UnsafeMutablePointer<NVGLUframebuffer>!) {
//        nvgluBindFramebuffer(framebuffer)
//    }
//    
//    public func deleteBGFXFramebuffer(_ framebuffer: UnsafeMutablePointer<NVGLUframebuffer>!) {
//        nvgluDeleteFramebuffer(framebuffer)
//    }
//    
//    public enum Winding : Int32 {
//        case counterClockwise = 1
//        case clockwise = 2
//    }
//    
//    public enum Solidity : Int32 {
//        case solid = 1
//        case hole = 2
//    }
//    
//    public enum LineCap : Int32 {
//        case butt
//        case round
//        case square
//        case bevel
//        case miter
//    }
//    
//    public struct Align : OptionSet {
//        public let rawValue: Int32
//        
//        public init(rawValue: Int32) {
//            self.rawValue = rawValue
//        }
//        
//        /// Default, align text horizontally to left.
//        public static let left = Align(rawValue: 1)
//        
//        /// Align text horizontally to centre.
//        public static let centre = Align(rawValue: 2)
//        
//        /// Align text horizontally to right.
//        public static let right = Align(rawValue: 4)
//        
//        /// Align text vertically to top.
//        public static let top = Align(rawValue: 8)
//        
//        /// Align text vertically to middle
//        public static let middle = Align(rawValue: 16)
//        
//        /// Align text vertically to bottom.
//        public static let bottom = Align(rawValue: 32)
//        
//        /// Default, align text vertically to baseline.
//        public static let baseline = Align(rawValue: 64)
//    }
//    
//    public enum BlendFactor : Int32 {
//        case zero = 1
//        case one = 2
//        case sourceColour = 4
//        case oneMinusSourceColour = 8
//        case destinationColour = 16
//        case oneMinusDestinationColour = 32
//        case sourceAlpha = 64
//        case oneMinusSourceAlpha = 128
//        case destinationAlpha = 256
//        case oneMinusDestinationAlpha = 512
//        case sourceAlphaSaturate = 1024
//    }
//    
//    public enum CompositeOperation : Int32 {
//        case sourceOver
//        case sourceIn
//        case sourceOut
//        case atop
//        case destinationOver
//        case destinationIn
//        case destinationOut
//        case destinationAtop
//        case lighter
//        case copy
//        case xor
//    }
//    
//    public struct ImageFlags : OptionSet {
//        public let rawValue : Int32
//        
//        public init(rawValue: Int32) {
//            self.rawValue = rawValue
//        }
//        
//        /// Generate mipmaps during creation of the image.
//        public static let generateMipmaps = ImageFlags(rawValue: 1)
//        /// Repeat image in X direction.
//        public static let repeatX = ImageFlags(rawValue: 2)
//        /// Repeat image in Y direction.
//        public static let repeatY = ImageFlags(rawValue: 4)
//        /// Flips (inverses) image in Y direction when rendered.
//        public static let flipY = ImageFlags(rawValue: 8)
//        /// Image data has premultiplied alpha
//        public static let premultiplied = ImageFlags(rawValue: 16)
//    }
//    
//    
//    /// Begin drawing a new frame
//    /// Calls to nanovg drawing API should be wrapped in nvgBeginFrame() & nvgEndFrame()
//    /// nvgBeginFrame() defines the size of the window to render to in relation currently
//    /// set viewport (i.e. glViewport on GL backends). Device pixel ration allows to
//    /// control the rendering on Hi-DPI devices.
//    /// For example, GLFW returns two dimension for an opened window: window size and
//    /// frame buffer size. In that case you would set windowWidth/Height to the window size
//    /// devicePixelRatio to: frameBufferWidth / windowWidth.
//    public func beginFrame(windowWidth: Int, windowHeight: Int, devicePixelRatio: Float) {
//        
//        nvgBeginFrame(self.context, Int32(windowWidth), Int32(windowHeight), devicePixelRatio)
//    }
//    
//    
//    /// Cancels drawing the current frame.
//    public func cancelFrame() {
//        nvgCancelFrame(self.context)
//    }
//    
//    
//    /// Ends drawing flushing remaining render state.
//    public func endFrame() {
//        nvgEndFrame(self.context)
//    }
//    
//    //
//    // Composite operation
//    //
//    // The composite operations in NanoVG are modeled after HTML Canvas API, and
//    // the blend func is based on OpenGL (see corresponding manuals for more info).
//    // The colors in the blending state have premultiplied alpha.
//    
//    /// Sets the composite operation. The op parameter should be one of CompositeOperation.
//    public func setCompositeOperation(_ compositeOperation: CompositeOperation) {
//        nvgGlobalCompositeOperation(self.context, compositeOperation.rawValue)
//    }
//    
//    /// Sets the composite operation with custom pixel arithmetic. The parameters should be one of NVGblendFactor.
//    public func setCompositeBlendFunc(sfactor: BlendFactor, dfactor: BlendFactor) {
//        nvgGlobalCompositeBlendFunc(self.context, sfactor.rawValue, dfactor.rawValue)
//    }
//    
//    /// Sets the composite operation with custom pixel arithmetic for RGB and alpha components separately. The parameters should be one of NVGblendFactor.
//    public func setCompositeBlendFunc(srcRGB: BlendFactor, dstRGB: BlendFactor, srcAlpha: BlendFactor, dstAlpha: BlendFactor) {
//        nvgGlobalCompositeBlendFuncSeparate(self.context, srcRGB.rawValue, dstRGB.rawValue, srcAlpha.rawValue, dstAlpha.rawValue)
//    }
//    
//    
//    //
//    // State Handling
//    //
//    // NanoVG contains state which represents how paths will be rendered.
//    // The state contains transform, fill and stroke styles, text and font styles,
//    // and scissor clipping.
//    
//    /// Pushes and saves the current render state into a state stack.
//    /// A matching nvgRestore() must be used to restore the state.
//    public func save() {
//       nvgSave(self.context)
//    }
//    
//    /// Pops and restores current render state.
//    public func restore() {
//        nvgRestore(self.context)
//    }
//    
//    /// Resets current render state to default values. Does not affect the render state stack.
//    public func reset() {
//        nvgReset(self.context)
//    }
//    
//    //
//    // Render styles
//    //
//    // Fill and stroke render style can be either a solid color or a paint which is a gradient or a pattern.
//    // Solid color is simply defined as a color value, different kinds of paints can be created
//    // using nvgLinearGradient(), nvgBoxGradient(), nvgRadialGradient() and nvgImagePattern().
//    //
//    // Current render style can be saved and restored using nvgSave() and nvgRestore().
//    
//    /// Sets current stroke style to a solid color.
//    public func strokeColour(_ colour: Colour) {
//        nvgStrokeColor(self.context, colour.nvgColour)
//    }
//    
//    /// Sets current stroke style to a paint, which can be a one of the gradients or a pattern.
//    public func strokePaint(_ paint: NVGpaint) {
//        nvgStrokePaint(self.context, paint)
//    }
//    
//    /// Sets current fill style to a solid color.
//    public func fillColour(_ colour: Colour) {
//        nvgFillColor(self.context, colour.nvgColour)
//    }
//    
//    /// Sets current fill style to a paint, which can be a one of the gradients or a pattern.
//    public func fillPaint( _ paint: NVGpaint) {
//        nvgFillPaint(self.context, paint)
//    }
//    
//    /// Sets the miter limit of the stroke style.
//    /// Miter limit controls when a sharp corner is beveled.
//    public func miterLimit(_ limit: Float) {
//        nvgMiterLimit(self.context, limit)
//    }
//    
//    
//    /// Sets the stroke width of the stroke style.
//    public func strokeWidth(_ size: Float) {
//        nvgStrokeWidth(self.context, size)
//    }
//    
//    /// Sets how the end of the line (cap) is drawn,
//    /// Can be one of: NVG_BUTT (default), NVG_ROUND, NVG_SQUARE.
//    public func lineCap(_ cap: LineCap) {
//        nvgLineCap(self.context, cap.rawValue)
//    }
//    
//    /// Sets how sharp path corners are drawn.
//    /// Can be one of NVG_MITER (default), NVG_ROUND, NVG_BEVEL.
//    public func lineJoin(_ join: LineCap) {
//        nvgLineJoin(self.context, join.rawValue)
//    }
//    
//    /// Sets the transparency applied to all rendered shapes.
//    /// Already transparent paths will get proportionally more transparent as well.
//    public func globalAlpha(_ alpha: Float) {
//        nvgGlobalAlpha(self.context, alpha)
//    }
//    
//    //
//    // Transforms
//    //
//    // The paths, gradients, patterns and scissor region are transformed by an transformation
//    // matrix at the time when they are passed to the API.
//    // The current transformation matrix is a affine matrix:
//    //   [sx kx tx]
//    //   [ky sy ty]
//    //   [ 0  0  1]
//    // Where: sx,sy define scaling, kx,ky skewing, and tx,ty translation.
//    // The last row is assumed to be 0,0,1 and is not stored.
//    //
//    // Apart from nvgResetTransform(), each transformation function first creates
//    // specific transformation matrix and pre-multiplies the current transformation by it.
//    //
//    // Current coordinate system (transformation) can be saved and restored using nvgSave() and nvgRestore().
//    
//    /// Resets current transform to a identity matrix.
//    public func resetTransform() {
//        nvgResetTransform(self.context)
//    }
//    
//    /// Premultiplies current coordinate system by specified matrix.
//    /// The parameters are interpreted as matrix as follows:
//    ///   [a c e]
//    ///   [b d f]
//    ///   [0 0 1]
//    public func transform(by a: Float, _ b: Float, _ c: Float, _ d: Float, _ e: Float, _ f: Float) {
//        nvgTransform(self.context, a, b, c, d, e, f)
//    }
//    
//    /// Translates current coordinate system.
//    public func translate(x: Float, y: Float) {
//        nvgTranslate(self.context, x, y)
//    }
//    
//    /// Rotates current coordinate system. Angle is specified in radians.
//    public func rotate(by angle: Angle) {
//        nvgRotate(self.context, angle.radians)
//    }
//    
//    /// Skews the current coordinate system along X axis. Angle is specified in radians.
//    public func skewX(by angle: Angle) {
//        nvgSkewX(self.context, angle.radians)
//    }
//    
//    /// Skews the current coordinate system along Y axis. Angle is specified in radians.
//    public func skewY(by angle: Angle) {
//        nvgSkewY(self.context, angle.radians)
//    }
//    
//    /// Scales the current coordinate system.
//    public func scaleBy(x: Float, y: Float) {
//        nvgScale(self.context, x, y)
//    }
//    
//    public struct Transform {
//        public var elements : [Float]
//        
//        public init() {
//            self.elements = [Float](repeating: 0, count: 6)
//        }
//        
//        init(elements: [Float]) {
//            assert(elements.count == 6)
//            self.elements = elements
//        }
//        
//        public static let identity = { () -> NanoVG.Transform in 
//            var transform = Transform()
//            nvgTransformIdentity(&transform.elements)
//            return transform
//        }
//        
//        public init(translationByX x: Float, y: Float) {
//            self = Transform()
//            nvgTransformTranslate(&self.elements, x, y)
//        }
//        
//        public init(scaleByX x: Float, y: Float) {
//            self = Transform()
//            nvgTransformScale(&self.elements, x, y)
//        }
//        
//        public init(rotationBy angle: Angle) {
//            self = Transform()
//            nvgTransformRotate(&self.elements, angle.radians)
//        }
//        
//        public init(skewX angle: Angle) {
//            self = Transform()
//            nvgTransformSkewX(&self.elements, angle.radians)
//        }
//        
//        public init(skewY angle: Angle) {
//            self = Transform()
//            nvgTransformSkewY(&self.elements, angle.radians)
//        }
//        
//        public static func *(lhs: Transform, rhs: Transform) -> Transform {
//            var result = lhs
//            nvgTransformMultiply(&result.elements, rhs.elements)
//            return result
//        }
//        
//        public static func *=(lhs: inout Transform, rhs: Transform) {
//            nvgTransformMultiply(&lhs.elements, rhs.elements)
//        }
//        
//        public var inverse : Transform {
//            var result = Transform()
//            if nvgTransformInverse(&result.elements, self.elements) != 0 {
//                return result
//            }
//            fatalError("No inverse for transform.")
//        }
//        
//        public func transformPoint(_ point: Vector2f) -> Vector2f {
//            var result = Vector2f()
//            nvgTransformPoint(&result.x, &result.y, self.elements, point.x, point.y)
//            return result
//        }
//    }
//    
//    /// Stores the top part (a-f) of the current transformation matrix in to the specified buffer.
//    ///   [a c e]
//    ///   [b d f]
//    ///   [0 0 1]
//    /// There should be space for 6 floats in the return buffer for the values a-f.
//    public var currentTransform : Transform {
//        var buffer = [Float](repeating: 0, count: 6)
//        nvgCurrentTransform(self.context, &buffer)
//        return Transform(elements: buffer)
//    }
//    
//    //
//    // Images
//    //
//    // NanoVG allows you to load jpg, png, psd, tga, pic and gif files to be used for rendering.
//    // In addition you can upload your own image. The image loading is provided by stb_image.
//    // The parameter imageFlags is combination of flags defined in NVGimageFlags.
//    
//    public final class Image {
//        let handle : Int32
//        let context : NanoVG
//        
//        init(context: NanoVG, handle: Int32) {
//            self.handle = handle
//            self.context = context
//        }
//        
//        deinit {
//            nvgDeleteImage(self.context.context, self.handle)
//        }
//        
//        
//        /// Updates image data specified by image handle.
//        public func updateData(_ data: UnsafePointer<UInt8>) {
//            nvgUpdateImage(self.context.context, self.handle, data)
//        }
//        
//        public var dimensions : (width: Int, height: Int) {
//            var w = Int32(0)
//            var h = Int32(0)
//            
//            nvgImageSize(self.context.context, self.handle, &w, &h)
//            return (Int(w), Int(h))
//        }
//    }
//    
//    
//    
//    /// Creates image by loading it from the disk from specified file name.
//    /// Returns handle to the image.
//    public func createImage(filename: String, flags: ImageFlags) -> Image {
//        let handle = nvgCreateImage(self.context, filename, flags.rawValue)
//        return Image(context: self, handle: handle)
//    }
//    
//    /// Creates image by loading it from the specified chunk of memory.
//    /// Returns handle to the image.
//    public func createImageFromMemory(_ data: UnsafeMutablePointer<UInt8>!, dataSize: Int, flags: ImageFlags) -> Image {
//        let handle = nvgCreateImageMem(self.context, flags.rawValue, data, Int32(dataSize))
//        return Image(context: self, handle: handle)
//    }
//    
//    /// Creates image from specified image data.
//    /// Returns handle to the image.
//    public func createImageRGBA(width: Int, height: Int, flags: ImageFlags, data: UnsafePointer<UInt8>!) -> Image {
//        let handle = nvgCreateImageRGBA(self.context, Int32(width), Int32(height), flags.rawValue, data)
//        return Image(context: self, handle: handle)
//    }
//    
//    
//    //
//    // Paints
//    //
//    // NanoVG supports four types of paints: linear gradient, box gradient, radial gradient and image pattern.
//    // These can be used as paints for strokes and fills.
//    
//    /// Creates and returns a linear gradient. Parameters (sx,sy)-(ex,ey) specify the start and end coordinates
//    /// of the linear gradient, icol specifies the start color and ocol the end color.
//    /// The gradient is transformed by the current transform when it is passed to nvgFillPaint() or nvgStrokePaint().
//    public func linearGradient(from sx: Float, _ sy: Float, to ex: Float, _ ey: Float, startColour icol: Colour, endColour ocol: Colour) -> NVGpaint {
//        return nvgLinearGradient(self.context, sx, sy, ex, ey, icol.nvgColour, ocol.nvgColour)
//    }
//    
//    /// Creates and returns a box gradient. Box gradient is a feathered rounded rectangle, it is useful for rendering
//    /// drop shadows or hilights for boxes. Parameters (x,y) define the top-left corner of the rectangle,
//    /// (w,h) define the size of the rectangle, r defines the corner radius, and f feather. Feather defines how blurry
//    /// the border of the rectangle is. Parameter icol specifies the inner color and ocol the outer color of the gradient.
//    /// The gradient is transformed by the current transform when it is passed to nvgFillPaint() or nvgStrokePaint().
//    public func boxGradient(left x: Float, top y: Float, width: Float, height: Float, cornerRadius: Float, feather: Float, innerColour: Colour, outerColour: Colour) -> NVGpaint {
//        return nvgBoxGradient(self.context, x, y, width, height, cornerRadius, feather, innerColour.nvgColour, outerColour.nvgColour)
//    }
//    
//    /// Creates and returns a radial gradient. Parameters (cx,cy) specify the center, inr and outr specify
//    /// the inner and outer radius of the gradient, icol specifies the start color and ocol the end color.
//    /// The gradient is transformed by the current transform when it is passed to nvgFillPaint() or nvgStrokePaint().
//    public func radialGradient(centreX cx: Float, centreY cy: Float, innerRadius: Float, outerRadius: Float, innerColour icol: Colour, outerColour ocol: Colour) -> NVGpaint {
//        return nvgRadialGradient(self.context, cx, cy, innerRadius, outerRadius, icol.nvgColour, ocol.nvgColour)
//    }
//    
//    /// Creates and returns an image patter. Parameters (ox,oy) specify the left-top location of the image pattern,
//    /// (ex,ey) the size of one image, angle rotation around the top-left corner, image is handle to the image to render.
//    /// The gradient is transformed by the current transform when it is passed to nvgFillPaint() or nvgStrokePaint().
//    public func imagePattern(image: Image, left ox: Float, top oy: Float, width ex: Float, height ey: Float, angle: Angle, alpha: Float) -> NVGpaint {
//        return nvgImagePattern(self.context, ox, oy, ex, ey, angle.radians, image.handle, alpha)
//    }
//    
//    //
//    // Scissoring
//    //
//    // Scissoring allows you to clip the rendering into a rectangle. This is useful for various
//    // user interface cases like rendering a text edit or a timeline.
//    
//    /// Sets the current scissor rectangle.
//    /// The scissor rectangle is transformed by the current transform.
//    public func scissor(x: Float, y: Float, width: Float, height: Float) {
//       nvgScissor(self.context, x, y, width, height)
//    }
//    
//    /// Intersects current scissor rectangle with the specified rectangle.
//    /// The scissor rectangle is transformed by the current transform.
//    /// Note: in case the rotation of previous scissor rect differs from
//    /// the current one, the intersection will be done between the specified
//    /// rectangle and the previous scissor rectangle transformed in the current
//    /// transform space. The resulting shape is always rectangle.
//    public func intersectScissor(x: Float, y: Float, width: Float, height: Float) {
//        nvgIntersectScissor(self.context, x, y, width, height)
//    }
//    
//    /// Reset and disables scissoring.
//    public func resetScissor() {
//        nvgResetScissor(self.context)
//    }
//    
//    //
//    // Paths
//    //
//    // Drawing a new shape starts with nvgBeginPath(), it clears all the currently defined paths.
//    // Then you define one or more paths and sub-paths which describe the shape. The are functions
//    // to draw common shapes like rectangles and circles, and lower level step-by-step functions,
//    // which allow to define a path curve by curve.
//    //
//    // NanoVG uses even-odd fill rule to draw the shapes. Solid shapes should have counter clockwise
//    // winding and holes should have counter clockwise order. To specify winding of a path you can
//    // call nvgPathWinding(). This is useful especially for the common shapes, which are drawn CCW.
//    //
//    // Finally you can fill the path using current fill style by calling nvgFill(), and stroke it
//    // with current stroke style by calling nvgStroke().
//    //
//    // The curve segments and sub-paths are transformed by the current transform.
//    
//    /// Clears the current path and sub-paths.
//    public func beginPath() {
//        nvgBeginPath(self.context)
//    }
//    
//    /// Starts new sub-path with specified point as first point.
//    public func moveTo(x: Float, y: Float) {
//        nvgMoveTo(self.context, x, y)
//    }
//    
//    /// Adds line segment from the last point in the path to the specified point.
//    public func lineTo(x: Float, y: Float) {
//        nvgLineTo(self.context, x, y)
//    }
//    
//    /// Adds cubic bezier segment from last point in the path via two control points to the specified point.
//    public func bezier(to x: Float, y: Float, via c1x: Float, _ c1y: Float, and c2x: Float, _ c2y: Float) {
//        nvgBezierTo(self.context, c1x, c1y, c2x, c2y, x, y)
//    }
//    
//    /// Adds quadratic bezier segment from last point in the path via a control point to the specified point.
//    public func quad(to x: Float, y: Float, via cx: Float, _ cy: Float) {
//        nvgQuadTo(self.context, cx, cy, x, y)
//    }
//    
//    /// Adds an arc segment at the corner defined by the last path point, and two specified points.
//    public func arc(to x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, radius: Float) {
//        nvgArcTo(self.context, x1, y1, x2, y2, radius)
//    }
//    
//    /// Closes current sub-path with a line segment.
//    public func closePath() {
//        nvgClosePath(self.context)
//    }
//    
//    /// Sets the current sub-path winding, see NVGwinding and NVGsolidity.
//    public func pathWinding(_ winding: Winding) {
//        nvgPathWinding(self.context, winding.rawValue)
//    }
//    
//    /// Creates new circle arc shaped sub-path. The arc center is at cx,cy, the arc radius is r,
//    /// and the arc is drawn from angle a0 to a1, and swept in direction dir (NVG_CCW, or NVG_CW).
//    /// Angles are specified in radians.
//    public func arc(centre cx: Float, _ cy: Float, radius: Float, startAngle: Angle, endAngle: Angle, direction: Winding) {
//        nvgArc(self.context, cx, cy, radius, startAngle.radians, endAngle.radians, direction.rawValue)
//    }
//    
//    /// Creates new rectangle shaped sub-path.
//    public func rect(x: Float, y: Float, width: Float, height: Float) {
//        nvgRect(self.context, x, y, width, height)
//    }
//    
//    /// Creates new rounded rectangle shaped sub-path.
//    public func roundedRect(x: Float, y: Float, width: Float, height: Float, cornerRadius: Float) {
//        nvgRoundedRect(self.context, x, y, width, height, cornerRadius)
//    }
//    
//    /// Creates new ellipse shaped sub-path.
//    public func ellipse(centre centreX: Float, _ centreY: Float, radius radiusX: Float, _ radiusY: Float) {
//        nvgEllipse(self.context, centreX, centreY, radiusX, radiusY)
//    }
//    
//    /// Creates new circle shaped sub-path.
//    public func circle(centre cx: Float, _ cy: Float, radius: Float) {
//        nvgCircle(self.context, cx, cy, radius)
//    }
//    
//    /// Fills the current path with current fill style.
//    public func fill() {
//        nvgFill(self.context)
//    }
//    
//    /// Fills the current path with current stroke style.
//    public func stroke() {
//        nvgStroke(self.context)
//    }
//    
//    //
//    // Text
//    //
//    // NanoVG allows you to load .ttf files and use the font to render text.
//    //
//    // The appearance of the text can be defined by setting the current text style
//    // and by specifying the fill color. Common text and font settings such as
//    // font size, letter spacing and text align are supported. Font blur allows you
//    // to create simple text effects such as drop shadows.
//    //
//    // At render time the font face can be set based on the font handles or name.
//    //
//    // Font measure functions return values in local space, the calculations are
//    // carried in the same resolution as the final rendering. This is done because
//    // the text glyph positions are snapped to the nearest pixels sharp rendering.
//    //
//    // The local space means that values are not rotated or scale as per the current
//    // transformation. For example if you set font size to 12, which would mean that
//    // line height is 16, then regardless of the current scaling and rotation, the
//    // returned line height is always 16. Some measures may vary because of the scaling
//    // since aforementioned pixel snapping.
//    //
//    // While this may sound a little odd, the setup allows you to always render the
//    // same way regardless of scaling. I.e. following works regardless of scaling:
//    //
//    //		const char* txt = "Text me up.";
//    //		nvgTextBounds(vg, x,y, txt, NULL, bounds);
//    //		nvgBeginPath(vg);
//    //		nvgRoundedRect(vg, bounds[0],bounds[1], bounds[2]-bounds[0], bounds[3]-bounds[1]);
//    //		nvgFill(vg);
//    //
//    // Note: currently only solid color fill is supported for text.
//    
//    public struct Font {
//        let handle : Int32
//    }
//    
//    /// Creates font by loading it from the disk from specified file name.
//    /// Returns handle to the font.
//    public func createFont(name: String, filename: String) -> Font {
//        return Font(handle: nvgCreateFont(self.context, name, filename))
//    }
//    
//    /// Creates font by loading it from the specified memory chunk.
//    /// Returns handle to the font.
//    public func createFont(name: String, data: UnsafeMutablePointer<UInt8>!, dataSize: Int, freeData: Bool) -> Font {
//        let handle = nvgCreateFontMem(self.context, name, data, Int32(dataSize), freeData ? 1 : 0)
//        return Font(handle: handle)
//    }
//    
//    /// Finds a loaded font of specified name, and returns handle to it, or -1 if the font is not found.
//    public func fontNamed(_ name: String) -> Font? {
//        let handle = nvgFindFont(self.context, name)
//        return (handle != -1) ? Font(handle: handle) : nil
//    }
//    
//    /// Adds a fallback font by handle.
//    public func addFallbackFont(baseFont: Font, fallbackFont: Font) -> Bool {
//        return nvgAddFallbackFontId(self.context, baseFont.handle, fallbackFont.handle) != 0
//    }
//    
//    /// Adds a fallback font by name.
//    public func addFallbackFont(baseFont: String, fallbackFont: String) -> Bool {
//        return nvgAddFallbackFont(self.context, baseFont, fallbackFont) != 0
//    }
//    
//    /// Sets the font size of current text style.
//    public func fontSize(_ size: Float) {
//        nvgFontSize(self.context, size)
//    }
//    
//    /// Sets the blur of current text style.
//    public func fontBlur(_ blur: Float) {
//        nvgFontBlur(self.context, blur)
//    }
//    
//    /// Sets the letter spacing of current text style.
//    public func textLetterSpacing(_ spacing: Float) {
//        nvgTextLetterSpacing(self.context, spacing)
//    }
//    
//    /// Sets the proportional line height of current text style. The line height is specified as multiple of font size.
//    public func textLineHeight(_ lineHeight: Float) {
//        nvgTextLineHeight(self.context, lineHeight)
//    }
//    
//    /// Sets the text align of current text style, see NVGalign for options.
//    public func textAlign(_ align: Align) {
//        nvgTextAlign(self.context, align.rawValue)
//    }
//    
//    /// Sets the font face based on specified id of current text style.
//    public func fontFace(_ font: Font) {
//        nvgFontFaceId(self.context, font.handle)
//    }
//    
//    /// Sets the font face based on specified name of current text style.
//    public func fontFace(_ font: String) {
//        nvgFontFace(self.context, font)
//    }
//    
//    /// Draws text string at specified location. If end is specified only the sub-string up to the end is drawn.
//    public func text(_ string: String, x: Float, y: Float) -> Float {
//        return nvgText(self.context, x, y, string, nil)
//    }
//    
//    /// Draws multi-line text string at specified location wrapped at the specified width. If end is specified only the sub-string up to the end is drawn.
//    /// White space is stripped at the beginning of the rows, the text is split at word boundaries or when new-line characters are encountered.
//    /// Words longer than the max width are slit at nearest character (i.e. no hyphenation).
//    public func textBox(text: String, x: Float, y: Float, breakRowWidth: Float) {
//        nvgTextBox(self.context, x, y, breakRowWidth, text, nil)
//    }
//    
//    /// Measures the specified text string. Parameter bounds should be a pointer to float[4],
//    /// if the bounding box of the text should be returned. The bounds value are [xmin,ymin, xmax,ymax]
//    /// Returns the horizontal advance of the measured text (i.e. where the next character should drawn).
//    /// Measured values are returned in local coordinate space.
//    public func textBounds(text: String, x: Float, y: Float, _ bounds: UnsafeMutablePointer<Float>!) -> (min: Vector2f, max: Vector2f, horizontalAdvance: Float) {
//        var bounds : (Float, Float, Float, Float) = (0.0, 0.0, 0.0, 0.0)
//        let advance = nvgTextBounds(self.context, x, y, text, nil, &bounds.0)
//        return (min: Vector2f(bounds.0, bounds.1), max: Vector2f(bounds.2, bounds.3), horizontalAdvance: advance)
//    }
//    
//    /// Measures the specified multi-text string. Parameter bounds should be a pointer to float[4],
//    /// if the bounding box of the text should be returned. The bounds value are [xmin,ymin, xmax,ymax]
//    /// Measured values are returned in local coordinate space.
//    public func textBoxBounds(text: String, x: Float, y: Float, breakRowWidth: Float) -> (min: Vector2f, max: Vector2f) {
//        var bounds : (Float, Float, Float, Float) = (0.0, 0.0, 0.0, 0.0)
//        nvgTextBoxBounds(self.context, x, y, breakRowWidth, text, nil, &bounds.0)
//        return (min: Vector2f(bounds.0, bounds.1), max: Vector2f(bounds.2, bounds.3))
//    }
//    
//    /// Calculates the glyph x positions of the specified text. If end is specified only the sub-string will be used.
//    /// Measured values are returned in local coordinate space.
//    public func textGlyphPositions(text: String, x: Float, y: Float, maxPositions: Int) -> [NVGglyphPosition] {
//        var buffer = [NVGglyphPosition](repeating: NVGglyphPosition(), count: maxPositions)
//        let numFound = Int(nvgTextGlyphPositions(self.context, x, y, text, nil, &buffer, Int32(maxPositions)))
//        return numFound == maxPositions ? buffer : Array(buffer.prefix(numFound))
//    }
//    
//    /// Returns the vertical metrics based on the current text style.
//    /// Measured values are returned in local coordinate space.
//    public var textMetrics : (ascender: Float, descender: Float, lineHeight: Float) {
//        var ascender : Float = 0
//        var descender : Float = 0
//        var lineH : Float = 0
//        nvgTextMetrics(self.context, &ascender, &descender, &lineH)
//        return (ascender, descender, lineH)
//    }
//    
//    /// Breaks the specified text into lines. If end is specified only the sub-string will be used.
//    /// White space is stripped at the beginning of the rows, the text is split at word boundaries or when new-line characters are encountered.
//    /// Words longer than the max width are slit at nearest character (i.e. no hyphenation).
//    public func breakIntoLines(text string: String, breakRowWidth: Float, maxRows: Int) -> [NVGtextRow] {
//        var buffer = [NVGtextRow](repeating: NVGtextRow(), count: maxRows)
//        let numFound = Int(nvgTextBreakLines(self.context, string, nil, breakRowWidth, &buffer, Int32(maxRows)))
//        return numFound == maxRows ? buffer : Array(buffer.prefix(numFound))
//    }
//    
//
//}
