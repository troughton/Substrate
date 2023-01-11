//
//  File.swift
//  
//
//  Created by Thomas Roughton on 7/07/22.
//

import Foundation

public struct ResourceUsageType: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    
    @inlinable
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    @inlinable
    public static var shaderRead: ResourceUsageType { .init(rawValue: 1 << 0) }
    
    @inlinable
    public static var shaderWrite: ResourceUsageType { .init(rawValue: 1 << 1) }
    
    @inlinable
    public static var colorAttachmentRead: ResourceUsageType { .init(rawValue: 1 << 2) }
    
    @inlinable
    public static var colorAttachmentWrite: ResourceUsageType { .init(rawValue: 1 << 3) }
    
    @inlinable
    public static var depthStencilAttachmentRead: ResourceUsageType { .init(rawValue: 1 << 4) }
    
    @inlinable
    public static var depthStencilAttachmentWrite: ResourceUsageType { .init(rawValue: 1 << 5) }
    
    @inlinable
    public static var inputAttachment: ResourceUsageType { .init(rawValue: 1 << 6) }
    
    @inlinable
    public static var vertexBuffer: ResourceUsageType { .init(rawValue: 1 << 7) }
    
    @inlinable
    public static var indexBuffer: ResourceUsageType { .init(rawValue: 1 << 8) }
    
    @inlinable
    public static var constantBuffer: ResourceUsageType { .init(rawValue: 1 << 9) }
    
    @inlinable
    public static var indirectBuffer: ResourceUsageType { .init(rawValue: 1 << 10) }
    
    @inlinable
    public static var blitSource: ResourceUsageType { .init(rawValue: 1 << 11) }
    
    @inlinable
    public static var blitDestination: ResourceUsageType { .init(rawValue: 1 << 12) }
    
    @inlinable
    public static var cpuRead: ResourceUsageType { .init(rawValue: 1 << 13) }
    
    @inlinable
    public static var cpuWrite: ResourceUsageType { .init(rawValue: 1 << 14) }
    
    @inlinable
    public static var textureView: ResourceUsageType { .init(rawValue: 1 << 15) }
    
    // MARK: - Convenience Accessors
    
    @inlinable
    public static var shaderReadWrite: ResourceUsageType { [.shaderRead, .shaderWrite] }
    
    @inlinable
    public static var colorAttachment: ResourceUsageType { [.colorAttachmentRead, .colorAttachmentWrite] }
    
    @inlinable
    public static var depthStencilAttachment: ResourceUsageType { [.depthStencilAttachmentRead, .depthStencilAttachmentWrite] }
    
    @inlinable
    public static var cpuReadWrite: ResourceUsageType { [.cpuRead, .cpuWrite] }
    
    @inlinable
    public var isRead: Bool {
        return !self.isDisjoint(with: [.shaderRead, .colorAttachmentRead, .depthStencilAttachmentRead, .inputAttachment, .vertexBuffer, .indexBuffer, .constantBuffer, .indirectBuffer, .blitSource, .cpuRead])
    }
    
    @inlinable
    public var isWrite: Bool {
        return !self.isDisjoint(with: [.shaderWrite, .colorAttachmentWrite, .depthStencilAttachmentWrite, .blitDestination, .cpuWrite])
    }
    
    @inlinable
    public var isRenderTarget : Bool {
        return !self.isDisjoint(with: [.colorAttachment, .depthStencilAttachment, .inputAttachment])
    }
}

public struct ArgumentBufferUsage: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    
    @inlinable
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    @inlinable
    public static var shaderRead: ArgumentBufferUsage { .init(rawValue: ResourceUsageType.shaderRead.rawValue) }
    
    @inlinable
    public static var shaderWrite: ArgumentBufferUsage { .init(rawValue: ResourceUsageType.shaderWrite.rawValue) }
    
    @inlinable
    public static var blitSource: ArgumentBufferUsage { .init(rawValue: ResourceUsageType.blitSource.rawValue) }
    
    @inlinable
    public static var blitDestination: ArgumentBufferUsage { .init(rawValue: ResourceUsageType.blitDestination.rawValue) }
    
    @inlinable
    public static var cpuRead: ArgumentBufferUsage { .init(rawValue: ResourceUsageType.cpuRead.rawValue) }
    
    @inlinable
    public static var cpuWrite: ArgumentBufferUsage { .init(rawValue: ResourceUsageType.cpuWrite.rawValue) }
    
    // MARK: - Convenience Accessors
    
    @inlinable
    public static var shaderReadWrite: ArgumentBufferUsage { [.shaderRead, .shaderWrite] }
    
    @inlinable
    public static var cpuReadWrite: ArgumentBufferUsage { [.cpuRead, .cpuWrite] }
}

public struct BufferUsage: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    
    @inlinable
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    @inlinable
    public static var shaderRead: BufferUsage { .init(rawValue: ResourceUsageType.shaderRead.rawValue) }
    
    @inlinable
    public static var shaderWrite: BufferUsage { .init(rawValue: ResourceUsageType.shaderWrite.rawValue) }
    
    @inlinable
    public static var vertexBuffer: BufferUsage { .init(rawValue: ResourceUsageType.vertexBuffer.rawValue) }
    
    @inlinable
    public static var indexBuffer: BufferUsage { .init(rawValue: ResourceUsageType.indexBuffer.rawValue) }
    
    @inlinable
    public static var constantBuffer: BufferUsage { .init(rawValue: ResourceUsageType.constantBuffer.rawValue) }
    
    @inlinable
    public static var indirectBuffer: BufferUsage { .init(rawValue: ResourceUsageType.indirectBuffer.rawValue) }
    
    @inlinable
    public static var blitSource: BufferUsage { .init(rawValue: ResourceUsageType.blitSource.rawValue) }
    
    @inlinable
    public static var blitDestination: BufferUsage { .init(rawValue: ResourceUsageType.blitDestination.rawValue) }
    
    @inlinable
    public static var cpuRead: BufferUsage { .init(rawValue: ResourceUsageType.cpuRead.rawValue) }
    
    @inlinable
    public static var cpuWrite: BufferUsage { .init(rawValue: ResourceUsageType.cpuWrite.rawValue) }
    
    @inlinable
    public static var textureView: BufferUsage { .init(rawValue: ResourceUsageType.textureView.rawValue) }
    
    // MARK: - Convenience Accessors
    
    @inlinable
    public static var shaderReadWrite: BufferUsage { [.shaderRead, .shaderWrite] }
    
    @inlinable
    public static var cpuReadWrite: BufferUsage { [.cpuRead, .cpuWrite] }
}

public struct TextureUsage: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    
    @inlinable
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    @inlinable
    public static var shaderRead: TextureUsage { .init(rawValue: ResourceUsageType.shaderRead.rawValue) }
    
    @inlinable
    public static var shaderWrite: TextureUsage { .init(rawValue: ResourceUsageType.shaderWrite.rawValue) }
    
    @inlinable
    public static var colorAttachmentRead: TextureUsage { .init(rawValue: ResourceUsageType.colorAttachmentRead.rawValue) }
    
    @inlinable
    public static var colorAttachmentWrite: TextureUsage { .init(rawValue: ResourceUsageType.colorAttachmentWrite.rawValue) }
    
    @inlinable
    public static var depthStencilAttachmentRead: TextureUsage { .init(rawValue: ResourceUsageType.depthStencilAttachmentRead.rawValue) }
    
    @inlinable
    public static var depthStencilAttachmentWrite: TextureUsage { .init(rawValue: ResourceUsageType.depthStencilAttachmentWrite.rawValue) }
    
    @inlinable
    public static var inputAttachment: TextureUsage { .init(rawValue: ResourceUsageType.inputAttachment.rawValue) }
    
    @inlinable
    public static var blitSource: TextureUsage { .init(rawValue: ResourceUsageType.blitSource.rawValue) }
    
    @inlinable
    public static var blitDestination: TextureUsage { .init(rawValue: ResourceUsageType.blitDestination.rawValue) }
    
    @inlinable
    public static var cpuRead: TextureUsage { .init(rawValue: ResourceUsageType.cpuRead.rawValue) }
    
    @inlinable
    public static var cpuWrite: TextureUsage { .init(rawValue: ResourceUsageType.cpuWrite.rawValue) }
    
    @inlinable
    public static var pixelFormatView: TextureUsage { .init(rawValue: ResourceUsageType.textureView.rawValue) }
    
    // MARK: - Convenience Accessors
    
    @inlinable
    public static var shaderReadWrite: TextureUsage { [.shaderRead, .shaderWrite] }
    
    @inlinable
    public static var colorAttachment: TextureUsage { [.colorAttachmentRead, .colorAttachmentWrite] }
    
    @inlinable
    public static var depthStencilAttachment: TextureUsage { [.depthStencilAttachmentRead, .depthStencilAttachmentWrite] }
    
    @inlinable
    public static var cpuReadWrite: TextureUsage { [.cpuRead, .cpuWrite] }
}


extension ResourceUsageType {
    @inlinable
    public init(_ argumentBufferUsage: ArgumentBufferUsage) {
        self.init(rawValue: argumentBufferUsage.rawValue)
    }
    
    @inlinable
    public init(_ bufferUsage: BufferUsage) {
        self.init(rawValue: bufferUsage.rawValue)
    }
    
    @inlinable
    public init(_ textureUsage: TextureUsage) {
        self.init(rawValue: textureUsage.rawValue)
    }
}
