//
//  MetalSwapchain.swift
//
//
//  Created by Thomas Roughton on 18/09/23.
//

#if canImport(Metal)
import Metal
import MetalKit

struct CAMetalDrawableWrapper: Drawable {
    let drawable: CAMetalDrawable
    
    var texture: UnsafeRawPointer {
        return UnsafeRawPointer(Unmanaged.passUnretained(self.drawable.texture).toOpaque())
    }
    
    func present() {
        self.drawable.present()
    }
    
    func addPresentedHandler(_ onPresented: @escaping () -> Void) {
#if os(visionOS) && targetEnvironment(simulator)
        unsafeBitCast(self.drawable, to: MTLDrawableExtensions.self).addPresentedHandler { drawable in
            withExtendedLifetime(drawable) {
                onPresented()
            }
        }
#else
        self.drawable.addPresentedHandler { _ in
            onPresented()
        }
#endif
    }
}

enum CAMetalLayerDrawableError: Error {
    case nilDrawable
}

extension CAMetalLayer: Swapchain {
    @_disfavoredOverload
    public var drawablePixelFormat: PixelFormat {
        return PixelFormat(self.pixelFormat)
    }
    
    @_disfavoredOverload
    public func nextDrawable() throws -> Drawable {
        guard let drawable = (self as CAMetalLayer).nextDrawable() else {
            throw CAMetalLayerDrawableError.nilDrawable
        }
        
        return CAMetalDrawableWrapper(drawable: drawable)
    }
}

#if canImport(RealityKit)
import RealityKit

@available(macOS 12.0, iOS 15.0, tvOS 15.0, *)
extension TextureResource.DrawableQueue: Swapchain {
    @_disfavoredOverload
    public var drawablePixelFormat: PixelFormat {
        return PixelFormat(self.pixelFormat)
    }
    
    @_disfavoredOverload
    public func nextDrawable() throws -> Substrate.Drawable {
        while true {
            do {
                let result = TextureResource.Drawable.DrawableWrapper(drawable: try (self as TextureResource.DrawableQueue).nextDrawable())
                return result
            } catch let error as NSError {
                if !self.allowsNextDrawableTimeout, String(describing: error).hasSuffix("timeoutReached") {
                    // Work around TextureResource.DrawableQueue not always respecting allowsNextDrawableTimeout.
                    continue
                }
                throw error
            }
        }
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, *)
extension TextureResource.Drawable {
    final class DrawableWrapper: Drawable {
        let drawable: TextureResource.Drawable
        var presentedHandlers: [() -> Void] = []
        
        init(drawable: TextureResource.Drawable) {
            self.drawable = drawable
        }
        
        var texture: UnsafeRawPointer {
            return UnsafeRawPointer(Unmanaged.passUnretained(self.drawable.texture).toOpaque())
        }
        
        func present() {
            self.drawable.present()
            
            for handler in self.presentedHandlers {
                handler()
            }
        }
        
        func addPresentedHandler(_ onPresented: @escaping () -> Void) {
            self.presentedHandlers.append(onPresented)
        }
    }
}

#endif // canImport(RealityKit)

#endif // canImport(Metal)
