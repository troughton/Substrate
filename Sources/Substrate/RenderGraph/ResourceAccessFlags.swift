//
//  File.swift
//  
//
//  Created by Thomas Roughton on 7/07/22.
//

import Foundation

public struct ResourceAccessFlags: OptionSet {
    public let rawValue: Int
    
    @inlinable
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    @inlinable
    public static var shaderRead: ResourceAccessFlags { .init(rawValue: 1 << 0) }
    
    @inlinable
    public static var shaderWrite: ResourceAccessFlags { .init(rawValue: 1 << 1) }
    
    @inlinable
    public static var colorAttachmentRead: ResourceAccessFlags { .init(rawValue: 1 << 2) }
    
    @inlinable
    public static var colorAttachmentWrite: ResourceAccessFlags { .init(rawValue: 1 << 3) }
    
    @inlinable
    public static var depthStencilAttachmentRead: ResourceAccessFlags { .init(rawValue: 1 << 4) }
    
    @inlinable
    public static var depthStencilAttachmentWrite: ResourceAccessFlags { .init(rawValue: 1 << 5) }
    
    @inlinable
    public static var inputAttachment: ResourceAccessFlags { .init(rawValue: 1 << 6) }
    
    @inlinable
    public static var vertexBuffer: ResourceAccessFlags { .init(rawValue: 1 << 7) }
    
    @inlinable
    public static var indexBuffer: ResourceAccessFlags { .init(rawValue: 1 << 8) }
    
    @inlinable
    public static var constantBuffer: ResourceAccessFlags { .init(rawValue: 1 << 9) }
    
    @inlinable
    public static var indirectBuffer: ResourceAccessFlags { .init(rawValue: 1 << 10) }
    
    @inlinable
    public static var blitSource: ResourceAccessFlags { .init(rawValue: 1 << 11) }
    
    @inlinable
    public static var blitDestination: ResourceAccessFlags { .init(rawValue: 1 << 12) }
    
    @inlinable
    public static var cpuRead: ResourceAccessFlags { .init(rawValue: 1 << 13) }
    
    @inlinable
    public static var cpuWrite: ResourceAccessFlags { .init(rawValue: 1 << 14) }
    
    // MARK: - Convenience Accessors
    
    @inlinable
    public static var shaderReadWrite: ResourceAccessFlags { [.shaderRead, .shaderWrite] }
    
    @inlinable
    public static var colorAttachment: ResourceAccessFlags { [.colorAttachmentRead, .colorAttachmentWrite] }
    
    @inlinable
    public static var depthStencilAttachment: ResourceAccessFlags { [.depthStencilAttachmentRead, .depthStencilAttachmentWrite] }
    
    @inlinable
    public static var cpuReadWrite: ResourceAccessFlags { [.cpuRead, .cpuWrite] }
    
    @inlinable
    public var isRead: Bool {
        return !self.isDisjoint(with: [.shaderRead, .colorAttachmentRead, .depthStencilAttachmentRead, .inputAttachment, .vertexBuffer, .indexBuffer, .constantBuffer, .indirectBuffer, .blitSource, .cpuRead])
    }
    
    @inlinable
    public var isWrite: Bool {
        return !self.isDisjoint(with: [.shaderWrite, .colorAttachmentWrite, .depthStencilAttachmentWrite, .blitDestination, .cpuWrite])
    }
}

public struct BufferAccessFlags: OptionSet {
    public let rawValue: Int
    
    @inlinable
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    @inlinable
    public static var shaderRead: BufferAccessFlags { .init(rawValue: ResourceAccessFlags.shaderRead.rawValue) }
    
    @inlinable
    public static var shaderWrite: BufferAccessFlags { .init(rawValue: ResourceAccessFlags.shaderWrite.rawValue) }
    
    @inlinable
    public static var vertexBuffer: BufferAccessFlags { .init(rawValue: ResourceAccessFlags.vertexBuffer.rawValue) }
    
    @inlinable
    public static var indexBuffer: BufferAccessFlags { .init(rawValue: ResourceAccessFlags.indexBuffer.rawValue) }
    
    @inlinable
    public static var constantBuffer: BufferAccessFlags { .init(rawValue: ResourceAccessFlags.constantBuffer.rawValue) }
    
    @inlinable
    public static var indirectBuffer: BufferAccessFlags { .init(rawValue: ResourceAccessFlags.indirectBuffer.rawValue) }
    
    @inlinable
    public static var blitSource: BufferAccessFlags { .init(rawValue: ResourceAccessFlags.blitSource.rawValue) }
    
    @inlinable
    public static var blitDestination: BufferAccessFlags { .init(rawValue: ResourceAccessFlags.blitDestination.rawValue) }
    
    @inlinable
    public static var cpuRead: BufferAccessFlags { .init(rawValue: ResourceAccessFlags.cpuRead.rawValue) }
    
    @inlinable
    public static var cpuWrite: BufferAccessFlags { .init(rawValue: ResourceAccessFlags.cpuWrite.rawValue) }
    
    // MARK: - Convenience Accessors
    
    @inlinable
    public static var shaderReadWrite: BufferAccessFlags { [.shaderRead, .shaderWrite] }
    
    @inlinable
    public static var cpuReadWrite: BufferAccessFlags { [.cpuRead, .cpuWrite] }
}

public struct TextureAccessFlags: OptionSet {
    public let rawValue: Int
    
    @inlinable
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    @inlinable
    public static var shaderRead: TextureAccessFlags { .init(rawValue: ResourceAccessFlags.shaderRead.rawValue) }
    
    @inlinable
    public static var shaderWrite: TextureAccessFlags { .init(rawValue: ResourceAccessFlags.shaderWrite.rawValue) }
    
    @inlinable
    public static var colorAttachmentRead: TextureAccessFlags { .init(rawValue: ResourceAccessFlags.colorAttachmentRead.rawValue) }
    
    @inlinable
    public static var colorAttachmentWrite: TextureAccessFlags { .init(rawValue: ResourceAccessFlags.colorAttachmentWrite.rawValue) }
    
    @inlinable
    public static var depthStencilAttachmentRead: TextureAccessFlags { .init(rawValue: ResourceAccessFlags.depthStencilAttachmentRead.rawValue) }
    
    @inlinable
    public static var depthStencilAttachmentWrite: TextureAccessFlags { .init(rawValue: ResourceAccessFlags.depthStencilAttachmentWrite.rawValue) }
    
    @inlinable
    public static var inputAttachment: TextureAccessFlags { .init(rawValue: ResourceAccessFlags.inputAttachment.rawValue) }
    
    @inlinable
    public static var blitSource: TextureAccessFlags { .init(rawValue: ResourceAccessFlags.blitSource.rawValue) }
    
    @inlinable
    public static var blitDestination: TextureAccessFlags { .init(rawValue: ResourceAccessFlags.blitDestination.rawValue) }
    
    @inlinable
    public static var cpuRead: TextureAccessFlags { .init(rawValue: ResourceAccessFlags.cpuRead.rawValue) }
    
    @inlinable
    public static var cpuWrite: TextureAccessFlags { .init(rawValue: ResourceAccessFlags.cpuWrite.rawValue) }
    
    // MARK: - Convenience Accessors
    
    @inlinable
    public static var shaderReadWrite: TextureAccessFlags { [.shaderRead, .shaderWrite] }
    
    @inlinable
    public static var colorAttachment: TextureAccessFlags { [.colorAttachmentRead, .colorAttachmentWrite] }
    
    @inlinable
    public static var depthStencilAttachment: TextureAccessFlags { [.depthStencilAttachmentRead, .depthStencilAttachmentWrite] }
    
    @inlinable
    public static var cpuReadWrite: TextureAccessFlags { [.cpuRead, .cpuWrite] }
}


extension ResourceAccessFlags {
    @inlinable
    public init(_ bufferFlags: BufferAccessFlags) {
        self.init(rawValue: bufferFlags.rawValue)
    }
    
    @inlinable
    public init(_ textureFlags: TextureAccessFlags) {
        self.init(rawValue: textureFlags.rawValue)
    }
}
