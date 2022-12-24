//
//  File.swift
//  
//
//  Created by Thomas Roughton on 24/12/22.
//

#if canImport(Metal)

import Metal

extension Buffer {
    public var mtlBuffer: OffsetView<MTLBuffer>? {
        return self.backingResourcePointer.map { pointer in
            let buffer = Unmanaged<MTLBuffer>.fromOpaque(pointer).takeUnretainedValue()
            return OffsetView(value: buffer, offset: self[\.backingBufferOffsets] ?? 0)
        }
    }
}

extension OffsetView where Wrapped == MTLBuffer {
    public var buffer: MTLBuffer {
        return self.wrappedValue
    }
}

extension Texture {
    public var mtlTexture: MTLTexture? {
        return self.backingResourcePointer.map { pointer in
            return Unmanaged<MTLTexture>.fromOpaque(pointer).takeUnretainedValue()
        }
    }
}

extension Heap {
    public var mtlHeap: MTLHeap {
        return Unmanaged<MTLHeap>.fromOpaque(self.backingResourcePointer!).takeUnretainedValue()
    }
}

extension AccelerationStructure {
    public var mtlAccelerationStructure: MTLAccelerationStructure? {
        return Unmanaged<MTLAccelerationStructure>.fromOpaque(self.backingResourcePointer!).takeUnretainedValue()
    }
}

extension ArgumentBuffer {
    public var mtlBuffer: OffsetView<MTLBuffer>? {
        return self.backingResourcePointer.map { pointer in
            let buffer = Unmanaged<MTLBuffer>.fromOpaque(pointer).takeUnretainedValue()
            return OffsetView(value: buffer, offset: self[\.backingBufferOffsets] ?? 0)
        }
    }
}

extension VisibleFunctionTable {
    public var mtlVisibleFunctionTable: MTLVisibleFunctionTable? {
        return self.backingResourcePointer.map { pointer in
            return Unmanaged<MTLVisibleFunctionTable>.fromOpaque(pointer).takeUnretainedValue()
        }
    }
}

extension IntersectionFunctionTable {
    public var mtlIntersectionFunctionTable: MTLIntersectionFunctionTable? {
        return self.backingResourcePointer.map { pointer in
            return Unmanaged<MTLIntersectionFunctionTable>.fromOpaque(pointer).takeUnretainedValue()
        }
    }
}

#endif
