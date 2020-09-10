//
//  ResourceReference.swift
//  
//
//  Created by Thomas Roughton on 7/04/20.
//

/// RefCountedResource is a property wrapper that automatically manages the lifetime of its wrapped resource.
@propertyWrapper
public final class RefCountedResource<R: ResourceProtocol>: Hashable {
    public var wrappedValue: R {
        didSet {
            if oldValue != wrappedValue {
                oldValue.dispose()
            }
        }
    }
    
    @inlinable
    public init(wrappedValue resource: R) {
        self.wrappedValue = resource
    }
    
    
    @inlinable
    public init(_ resource: R) {
        self.wrappedValue = resource
    }
    
    public var resource: R {
        return self.wrappedValue
    }
    
    deinit {
        self.wrappedValue.dispose()
    }
    
    public func hash(into hasher: inout Hasher) {
        self.wrappedValue.hash(into: &hasher)
    }
    
    public static func ==(lhs: RefCountedResource<R>, rhs: RefCountedResource<R>) -> Bool {
        return lhs.wrappedValue == rhs.wrappedValue
    }
}
