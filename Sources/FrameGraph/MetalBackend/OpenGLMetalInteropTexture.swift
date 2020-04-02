//
//  OpenGLMetalInteropTexture.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 12/07/19.
//

#if canImport(Metal) && !targetEnvironment(macCatalyst)

import Metal

#if os(macOS)
import AppKit
import Cocoa
import OpenGL
public typealias PlatformGLContext = NSOpenGLContext
#elseif os(iOS) || os(tvOS) || os(watchOS)
import UIKit
public typealias PlatformGLContext = EAGLContext
#endif

import CoreVideo

struct MetalGLTextureFormatInfo {
    var cvPixelFormat : OSType
    var mtlFormat : MTLPixelFormat
    var glInternalFormat : GLuint
    var glFormat : GLuint
    var glType : GLuint
    
    init(_ cvPixelFormat: OSType, _ mtlFormat: MTLPixelFormat, _ glInternalFormat: GLuint, _ glFormat: GLuint, _ glType: GLuint) {
        self.cvPixelFormat = cvPixelFormat
        self.mtlFormat = mtlFormat
        self.glInternalFormat = glInternalFormat
        self.glFormat = glFormat
        self.glType = glType
    }
}

#if os(iOS) || os(tvOS) || os(watchOS)
let GL_UNSIGNED_INT_8_8_8_8_REV : GLuint = 0x8367
#else
let GL_RGBA : GLuint = 0x1908
let GL_RGB10_A2 : GLuint = 0x8059
let GL_BGRA : GLuint = 0x80E1
let GL_BGRA_EXT : GLuint = 0x80E1
let GL_SRGB8_ALPHA8 : GLuint = 0x8C43
let GL_UNSIGNED_INT_8_8_8_8_REV : GLuint = 0x8367
let GL_UNSIGNED_INT_2_10_10_10_REV : GLuint = 0x8368
let GL_HALF_FLOAT : GLuint = 0x140B
let GL_FLOAT : GLuint = 0x1406
let GL_R : GLuint = 0x2002
let GL_R32F : GLuint = 0x822E
let GL_DEPTH_COMPONENT : GLuint = 0x1902
#endif

public final class OpenGLMetalInteropTexture {
    // Table of equivalent formats across CoreVideo, Metal, and OpenGL
    #if os(iOS) || os(tvOS)
    static let interopFormatTable : [MetalGLTextureFormatInfo] = [
        //                  Core Video Pixel Format,               Metal Pixel Format,            GL internalformat, GL format,   GL type
        MetalGLTextureFormatInfo( kCVPixelFormatType_32BGRA,              .bgra8Unorm,      GLuint(GL_RGBA),           GLuint(GL_BGRA_EXT), GL_UNSIGNED_INT_8_8_8_8_REV ),
        MetalGLTextureFormatInfo( kCVPixelFormatType_32BGRA,              .bgra8Unorm_srgb, GLuint(GL_RGBA),           GLuint(GL_BGRA_EXT), GL_UNSIGNED_INT_8_8_8_8_REV ),
        MetalGLTextureFormatInfo( kCVPixelFormatType_DepthFloat32,        .depth32Float,    GLuint(GL_DEPTH_COMPONENT),  GLuint(GL_DEPTH_COMPONENT),     GLuint(GL_FLOAT) ),
    ]
    #else
    static let interopFormatTable : [MetalGLTextureFormatInfo] = [
        //                  Core Video Pixel Format,               Metal Pixel Format,            GL internalformat, GL format,   GL type
        MetalGLTextureFormatInfo( kCVPixelFormatType_32BGRA,              .bgra8Unorm,      GL_RGBA,           GL_BGRA_EXT, GL_UNSIGNED_INT_8_8_8_8_REV ),
        MetalGLTextureFormatInfo( kCVPixelFormatType_ARGB2101010LEPacked, .bgr10a2Unorm,    GL_RGB10_A2,       GL_BGRA,     GL_UNSIGNED_INT_2_10_10_10_REV ),
        MetalGLTextureFormatInfo( kCVPixelFormatType_32BGRA,              .bgra8Unorm_srgb, GL_SRGB8_ALPHA8,   GL_BGRA,     GL_UNSIGNED_INT_8_8_8_8_REV ),
        MetalGLTextureFormatInfo( kCVPixelFormatType_64RGBAHalf,          .rgba16Float,     GL_RGBA,           GL_RGBA,     GL_HALF_FLOAT ),
        MetalGLTextureFormatInfo( kCVPixelFormatType_DepthFloat32,        .r32Float,        GL_R32F,           GL_R,        GL_FLOAT ),
    ]
    #endif
    
    static func textureFormatInfoFromMetalPixelFormat(_ pixelFormat: MTLPixelFormat) -> MetalGLTextureFormatInfo? {
        for format in interopFormatTable {
            if pixelFormat == format.mtlFormat {
                return format
            }
        }
        return nil
    }
    
    public let metalDevice: MTLDevice
    public let glContext: PlatformGLContext
    public var metalTexture : MTLTexture! = nil
    public var glTexture : GLuint = 0
    
    public let size : Size
    
    // Internals:
    
    private let formatInfo : MetalGLTextureFormatInfo
    private var cvPixelBuffer : CVPixelBuffer! = nil
    private var cvMTLTexture : CVMetalTexture! = nil
    
    #if os(macOS)
    private var cvGLTextureCache : CVOpenGLTextureCache! = nil
    private var cvGLTexture : CVOpenGLTexture! = nil
    private var cglPixelFormat : CGLPixelFormatObj! = nil
    #else // if!(TARGET_IOS || TARGET_TVOS)
    private var cvGLTexture : CVOpenGLESTexture! = nil
    private var cvGLTextureCache : CVOpenGLESTextureCache! = nil
    #endif // !(TARGET_IOS || TARGET_TVOS)
    
    // Metal
    private var cvMTLTextureCache : CVMetalTextureCache! = nil
    
    public init(metalDevice: MTLDevice, glContext: PlatformGLContext, pixelFormat: PixelFormat, size: Size) {
        guard let formatInfo = OpenGLMetalInteropTexture.textureFormatInfoFromMetalPixelFormat(MTLPixelFormat(pixelFormat)) else {
            fatalError("OpenGL format mapping not defined for PixelFormat \(pixelFormat)")
        }
        self.formatInfo = formatInfo
        
        self.size = size
        self.metalDevice = metalDevice
        self.glContext = glContext
        
        #if os(macOS)
        self.cglPixelFormat = glContext.pixelFormat.cglPixelFormatObj
        #endif
        
        let cvBufferProperties = [
            kCVPixelBufferOpenGLCompatibilityKey : true,
            kCVPixelBufferMetalCompatibilityKey : true
        ]
        
        let cvRet = CVPixelBufferCreate(kCFAllocatorDefault,
                                        Int(size.width), Int(size.height),
                                        formatInfo.cvPixelFormat,
                                        cvBufferProperties as CFDictionary,
                                        &self.cvPixelBuffer);
        assert(cvRet == kCVReturnSuccess, "Failed to create CVPixelBuffer");
        
        self.createGLTexture()
        self.createMetalTexture()
    }
    
    
    #if os(macOS)
    
    func createGLTexture() {
        // 1. Create an OpenGL CoreVideo texture cache from the pixel buffer.
        var cvret  = CVOpenGLTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            self.glContext.cglContextObj!,
            self.cglPixelFormat,
            nil,
            &self.cvGLTextureCache);
        
        assert(cvret == kCVReturnSuccess, "Failed to create OpenGL Texture Cache");
        
        // 2. Create a CVPixelBuffer-backed OpenGL texture image from the texture cache.
        cvret = CVOpenGLTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            self.cvGLTextureCache,
            self.cvPixelBuffer,
            nil,
            &self.cvGLTexture);
        
        assert(cvret == kCVReturnSuccess, "Failed to create OpenGL Texture From Image");
        
        // 3. Get an OpenGL texture name from the CVPixelBuffer-backed OpenGL texture image.
        self.glTexture = CVOpenGLTextureGetName(self.cvGLTexture);
    }
    
    #else // if!(TARGET_IOS || TARGET_TVOS)
    
    /**
     On iOS, create an OpenGL ES texture from the CoreVideo pixel buffer using the following steps, and as annotated in the code listings below:
     */
    func createGLTexture() {
        // 1. Create an OpenGL ES CoreVideo texture cache from the pixel buffer.
        var cvret = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault,
                                                 nil,
                                                 self.glContext,
                                                 nil,
                                                 &self.cvGLTextureCache);
        
        assert(cvret == kCVReturnSuccess, "Failed to create OpenGL ES Texture Cache");
        
        // 2. Create a CVPixelBuffer-backed OpenGL ES texture image from the texture cache.
        cvret = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                             self.cvGLTextureCache,
                                                             self.cvPixelBuffer,
                                                             nil,
                                                             GLenum(GL_TEXTURE_2D),
                                                             GLint(self.formatInfo.glInternalFormat),
                                                             GLsizei(self.size.width), GLsizei(self.size.height),
                                                             self.formatInfo.glFormat,
                                                             self.formatInfo.glType,
                                                             0,
                                                             &self.cvGLTexture)
        
        
        assert(cvret == kCVReturnSuccess, "Failed to create OpenGL ES Texture From Image");
        
        // 3. Get an OpenGL ES texture name from the CVPixelBuffer-backed OpenGL ES texture image.
        self.glTexture = CVOpenGLESTextureGetName(self.cvGLTexture);
    }
    
    #endif // !(TARGET_IOS || TARGET_TVOS)
    
    /**
     Create a Metal texture from the CoreVideo pixel buffer using the following steps, and as annotated in the code listings below:
     */
    func createMetalTexture() {
        // 1. Create a Metal Core Video texture cache from the pixel buffer.
        var cvret = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            self.metalDevice,
            nil,
            &self.cvMTLTextureCache);
        
        assert(cvret == kCVReturnSuccess, "Failed to create Metal texture cache");
        
        // 2. Create a CoreVideo pixel buffer backed Metal texture image from the texture cache.
        
        cvret = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            self.cvMTLTextureCache,
            self.cvPixelBuffer, nil,
            self.formatInfo.mtlFormat,
            Int(self.size.width), Int(self.size.height),
            0,
            &self.cvMTLTexture);
        
        assert(cvret == kCVReturnSuccess, "Failed to create CoreVideo Metal texture from image");
        
        // 3. Get a Metal texture using the CoreVideo Metal texture reference.
        self.metalTexture = CVMetalTextureGetTexture(self.cvMTLTexture);
        
        assert(self.metalTexture != nil, "Failed to create Metal texture CoreVideo Metal Texture");
    }
    
}

#endif // canImport(Metal)
