//
//  ActiveResourceRange.swift
//  
//
//  Created by Thomas Roughton on 18/09/20.
//

import FrameGraphUtilities

public enum ActiveResourceRange {
    case inactive
    case fullResource
    case buffer(Range<Int>)
    case texture(SubresourceMask)
    
    @inlinable
    init(_ range: ActiveResourceRange, subresourceCount: Int, allocator: AllocatorType) {
        switch range {
        case .texture(let textureMask):
            self = .texture(SubresourceMask(source: textureMask, subresourceCount: subresourceCount, allocator: allocator))
        default:
            self = range
        }
    }
    
    func deallocateStorage(subresourceCount: Int, allocator: AllocatorType) {
        switch self {
        case .texture(let mask):
            mask.deallocateStorage(subresourceCount: subresourceCount, allocator: allocator)
        default:
            break
        }
    }
    
    @inlinable
    mutating func formUnion(with range: ActiveResourceRange, resource: Resource, allocator: AllocatorType) {
        self.formUnion(with: range, subresourceCount: resource.subresourceCount, allocator: allocator)
    }
    
    @inlinable
    mutating func formUnion(with range: ActiveResourceRange, subresourceCount: Int, allocator: AllocatorType) {
        if case .fullResource = self {
            return
        }
        switch (self, range) {
        case (.inactive, _):
            self = range
        case (_, .inactive):
            break
        case (.fullResource, _),
             (_, .fullResource):
            self = .fullResource
        case (.buffer(let rangeA), .buffer(let rangeB)):
            self = .buffer(min(rangeA.lowerBound, rangeB.lowerBound)..<max(rangeA.upperBound, rangeB.upperBound))
        case (.texture(var maskA), .texture(let maskB)):
            maskA.formUnion(with: maskB, subresourceCount: subresourceCount, allocator: allocator)
            self = .texture(maskA)
        default:
            fatalError("Incompatible resource ranges \(self) and \(range)")
        }
    }
    
    func union(with range: ActiveResourceRange, resource: Resource, allocator: AllocatorType) -> ActiveResourceRange {
        return self.union(with: range, subresourceCount: resource.subresourceCount, allocator: allocator)
    }
    
    func union(with range: ActiveResourceRange, subresourceCount: Int, allocator: AllocatorType) -> ActiveResourceRange {
        var result = ActiveResourceRange(self, subresourceCount: subresourceCount, allocator: allocator)
        result.formIntersection(with: range, subresourceCount: subresourceCount, allocator: allocator)
        return result
    }
    
    @inlinable
    mutating func formIntersection(with range: ActiveResourceRange, resource: Resource, allocator: AllocatorType) {
        self.formIntersection(with: range, subresourceCount: resource.subresourceCount, allocator: allocator)
    }
    
    @inlinable
    mutating func formIntersection(with range: ActiveResourceRange, subresourceCount: Int, allocator: AllocatorType) {
        if case .fullResource = self {
            self = ActiveResourceRange(range, subresourceCount: subresourceCount, allocator: allocator)
        }
        switch (self, range) {
        case (.inactive, _), (_, .inactive):
            self = .inactive
        case (.fullResource, _):
            self = ActiveResourceRange(range, subresourceCount: subresourceCount, allocator: allocator)
        case (_, .fullResource):
            return
        case (.buffer(let rangeA), .buffer(let rangeB)):
            self = rangeA.overlaps(rangeB) ? .buffer(max(rangeA.lowerBound, rangeB.lowerBound)..<min(rangeA.upperBound, rangeB.upperBound)) : .inactive
        case (.texture(var maskA), .texture(let maskB)):
            maskA.formIntersection(with: maskB, subresourceCount: subresourceCount, allocator: allocator)
            self = .texture(maskA)
        default:
            fatalError("Incompatible resource ranges \(self) and \(range)")
        }
    }
    
    func intersection(with range: ActiveResourceRange, resource: Resource, allocator: AllocatorType) -> ActiveResourceRange {
        return self.intersection(with: range, subresourceCount: resource.subresourceCount, allocator: allocator)
    }
    
    func intersection(with range: ActiveResourceRange, subresourceCount: Int, allocator: AllocatorType) -> ActiveResourceRange {
        var result = ActiveResourceRange(self, subresourceCount: subresourceCount, allocator: allocator)
        result.formIntersection(with: range, subresourceCount: subresourceCount, allocator: allocator)
        return result
    }
    
    func intersects(with range: ActiveResourceRange, resource: Resource) -> Bool {
        return self.intersects(with: range, subresourceCount: resource.subresourceCount)
    }
    
    func intersects(with range: ActiveResourceRange, subresourceCount: Int) -> Bool {
        switch (self, range) {
        case (.inactive, _), (_, .inactive):
            return false
        case (.fullResource, _),
             (_, .fullResource):
            return true
        case (.buffer(let rangeA), .buffer(let rangeB)):
            return rangeA.overlaps(rangeB)
        case (.texture(let maskA), .texture(let maskB)):
            return maskA.intersects(with: maskB, subresourceCount: subresourceCount)
        default:
            fatalError("Incompatible resource ranges \(self) and \(range)")
        }
    }
    
    
    func intersects(textureSlice slice: Int, level: Int, descriptor: TextureDescriptor) -> Bool {
        switch self {
        case .inactive:
            return false
        case .fullResource:
            return true
        case .texture(let mask):
            return mask[slice: slice, level: level, descriptor: descriptor]
        default:
            fatalError("\(self) is not a texture range")
        }
    }
    
    @inlinable
    mutating func subtract(range: ActiveResourceRange, resource: Resource, allocator: AllocatorType) {
        self.subtract(range: range, subresourceCount: resource.subresourceCount, allocator: allocator)
    }
    
    @inlinable
    mutating func subtract(range: ActiveResourceRange, subresourceCount: Int, allocator: AllocatorType) {
        switch (self, range) {
        case (.inactive, _):
            self = .inactive
        case (_, .inactive):
            return
        case (_, .fullResource):
            self = .inactive
        case (.fullResource, .texture(let textureRange)):
            var result = SubresourceMask()
            result.removeAll(in: textureRange, subresourceCount: subresourceCount, allocator: allocator)
            self = .texture(result)
        case (.buffer, .buffer),
             (.fullResource, .buffer):
            fatalError("Subtraction for buffer ranges is not implemented; we really need a RangeSet type (or a SubresourceMask-like coarse tracking for the buffer) to handle this properly.")
        case (.texture(var maskA), .texture(let maskB)):
            maskA.removeAll(in: maskB, subresourceCount: subresourceCount, allocator: allocator)
            self = .texture(maskA)
        default:
            fatalError("Incompatible resource ranges \(self) and \(range)")
        }
    }
    
    @inlinable
    func subtracting(range: ActiveResourceRange, resource: Resource, allocator: AllocatorType) -> ActiveResourceRange {
        return self.subtracting(range: range, subresourceCount: resource.subresourceCount, allocator: allocator)
    }
    
    @inlinable
    func subtracting(range: ActiveResourceRange, subresourceCount: Int, allocator: AllocatorType) -> ActiveResourceRange {
        var result = ActiveResourceRange(self, subresourceCount: subresourceCount, allocator: allocator)
        result.subtract(range: range, subresourceCount: subresourceCount, allocator: allocator)
        return result
    }


    public func isEqual(to other: ActiveResourceRange, resource: Resource) -> Bool {
        return self.isEqual(to: other, subresourceCount: resource.subresourceCount)
    }

    public func isEqual(to other: ActiveResourceRange, subresourceCount: Int) -> Bool {
        switch (self, other) {
        case (.inactive, .inactive):
            return true
        case (.fullResource, .fullResource):
            return true
        case (.inactive, .fullResource), (.fullResource, .inactive):
            return false
        case (.buffer(let rangeA), .buffer(let rangeB)):
            return rangeA == rangeB
        case (.texture(let maskA), .texture(let maskB)):
            return maskA.isEqual(to: maskB, subresourceCount: subresourceCount)
            
        case (.buffer(let range), .fullResource), (.fullResource, .buffer(let range)):
            return range.count == subresourceCount
        case (.buffer(let range), .inactive), (.inactive, .buffer(let range)):
            return range.isEmpty
            
        case (.texture(let mask), .fullResource), (.fullResource, .texture(let mask)):
            return mask.value == .max
        case (.texture(let mask), .inactive), (.inactive, .texture(let mask)):
            return mask.value == 0
            
        default:
            fatalError("Incompatible resource ranges \(self) and \(other)")
        }
    }
    
    func offset(by offset: Int) -> ActiveResourceRange {
        if case .buffer(let range) = self {
            return .buffer((range.lowerBound + offset)..<(range.upperBound + offset))
        }
        return self
    }
    
    
}

extension ResourceProtocol {
    @inlinable
    var subresourceCount: Int {
        switch self.type {
        case .texture:
            return Texture(handle: self.handle).descriptor.subresourceCount
        case .buffer:
            return Buffer(handle: self.handle).descriptor.length
        default:
            return 0
        }
    }
}
