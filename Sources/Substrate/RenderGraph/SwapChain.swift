//
//  Swapchain.swift
//  RenderAPI
//
//  Created by Thomas Roughton on 20/01/18.
//

public protocol Swapchain: AnyObject, Sendable {
    var drawablePixelFormat : PixelFormat { get }
    func nextDrawable() throws -> Drawable
}

public protocol Drawable: Sendable {
    var texture: UnsafeRawPointer { get } // Unmanaged, unretained.
    func present()
    func addPresentedHandler(_ onPresented: @escaping @Sendable () -> Void)
}
