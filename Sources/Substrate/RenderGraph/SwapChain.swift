//
//  Swapchain.swift
//  RenderAPI
//
//  Created by Thomas Roughton on 20/01/18.
//

public protocol Swapchain: AnyObject {
    var drawablePixelFormat : PixelFormat { get }
    func nextDrawable() throws -> Drawable
}

public protocol Drawable {
    var texture: UnsafeRawPointer { get } // Unmanaged, unretained.
    func present()
    func addPresentedHandler(_ onPresented: @escaping () -> Void)
}
