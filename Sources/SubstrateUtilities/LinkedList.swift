//
//  LinkedList.swift
//  Raytracer
//
//  Created by Thomas Roughton on 23/07/17.
//

public final class LinkedList<T> : Collection {
    
    @usableFromInline
    struct LinkedListNode {
        @usableFromInline var element: T!
        @usableFromInline var next: UnsafeMutablePointer<LinkedListNode>?
        @usableFromInline var previous: UnsafeMutablePointer<LinkedListNode>?
        
        @inlinable
        init() {
            self.element = nil
        }
        
        @inlinable
        public init(value: T) {
            self.element = value
        }
    }
    
    public class LinkedListIterator : IteratorProtocol {
        public typealias Element = T
        
        @usableFromInline let list : LinkedList<T>
        @usableFromInline var current : UnsafeMutablePointer<LinkedListNode>?
        @usableFromInline var index : Int = -1
        
        @inlinable
        init(list: LinkedList<T>) {
            self.list = list // Keep a strong reference to the list.
            self.current = list.head
        }
        
        @inlinable
        public func next() -> T? {
            self.index += 1
            if index >= list.count {
                return nil
            }
            
            assert(self.current?.pointee.next != nil)
            self.current = self.current!.pointee.next
            
            let element = self.current!.pointee.element
            return element
        }
        
        @inlinable
        public func removeLast() {
            let previous = self.current!.pointee.previous!
            
            list.removeNode(self.current!)
            self.current = previous
            self.index -= 1
        }
    }
    
    @usableFromInline var _count : Int = 0
    
    @inlinable
    public internal(set) var count : Int {
        get {
            return self._count
        }
        set {
            self._count = newValue
        }
    }
    @usableFromInline var head : UnsafeMutablePointer<LinkedListNode> //Keep a dummy node at the start.
    @usableFromInline var tail : UnsafeMutablePointer<LinkedListNode>
    
    @inlinable
    public init() {
        self.head = UnsafeMutablePointer<LinkedListNode>.allocate(capacity: 1)
        self.head.initialize(to: LinkedListNode())
        self.tail = self.head
    }
    
    deinit {
        while self.count > 0 {
            self.removeLast()
        }
        self.head.deinitialize(count: 1)
        self.head.deallocate()
    }
    
    @inlinable
    public var startIndex: Int {
        return 0
    }
    
    @inlinable
    public var endIndex: Int {
        return self.count
    }
    
    @inlinable
    public func index(after i: Int) -> Int {
        return i &+ 1
    }
    
    
    @inlinable
    func node(at index: Int) -> UnsafeMutablePointer<LinkedListNode> {
        precondition(index < self.count, "Index out of bounds")
        
        var current = self.head
        for _ in 0...index {
            current = current.pointee.next!
        }
        
        return current
    }
    
    
    @inlinable
    public subscript(index: Int) -> T {
        get {
            return self.node(at: index).pointee.element
        }
        set {
            self.node(at: index).pointee.element = newValue
        }
    }
    
    
    @inlinable
    public var last : T? {
        return self.tail.pointee.element
    }
    
    
    @inlinable
    public var mutableLast : T {
        get {
            return self.tail.pointee.element
        } set {
            self.tail.pointee.element = newValue
        }
    }
    
    private func validateList() {
        if self.isEmpty {
            assert(self.head == self.tail)
            assert(self.head.pointee.previous == nil)
            assert(self.head.pointee.next == nil)
            return
        }
        
        var current = self.head.pointee.next!
        var previous = self.head
        
        var i = 0
        while i < self.count - 1 {
            assert(current.pointee.previous == previous)
            previous = current
            current = current.pointee.next!
            i += 1
        }
        
        assert(current == self.tail)
        assert(current.pointee.next == nil)
        assert(current.pointee.previous == previous)
    }
    
    @inlinable
    public func append(_ element: T) {
        let newNode = UnsafeMutablePointer<LinkedListNode>.allocate(capacity: 1)
        newNode.initialize(to: LinkedListNode(value: element))
        newNode.pointee.previous = self.tail
        newNode.pointee.next = nil
        
        self.tail.pointee.next = newNode
        self.tail = newNode
        
        self.count += 1
    }
    
    @discardableResult
    @inlinable
    public func removeLast() -> Element {
        guard self.count > 0 else {
            fatalError("Cannot remove from an empty list.")
        }
        
        let node = self.tail
        let previous = node.pointee.previous!
        
        previous.pointee.next = nil
        let element = node.pointee.element!
        
        self.tail.deinitialize(count: 1)
        self.tail.deallocate()
        self.tail = previous
        
        self.count -= 1
        
        return element
    }
    
    @inlinable
    func removeNode(_ node: UnsafeMutablePointer<LinkedListNode>) {
        
        if node == self.tail {
            self.tail = node.pointee.previous!
        }
        
        let previous = node.pointee.previous!
        let next = node.pointee.next
        
        previous.pointee.next = next
        next?.pointee.previous = previous
        
        self.count -= 1
        
        node.deinitialize(count: 1)
        node.deallocate()
    }
    
    @inlinable
    public func prependAndClear(contentsOf list: LinkedList<T>) {
        if list.isEmpty {
            return
        }
        
        self.count += list.count
        list.count = 0
        
        let firstElement = list.head.pointee.next!
        list.head.pointee.next = nil
        
        let lastElement = list.tail
        list.tail = list.head
        
        if let currentFirst = self.head.pointee.next {
            currentFirst.pointee.previous = lastElement
            lastElement.pointee.next = currentFirst
        } else {
            self.tail = lastElement
        }
        
        self.head.pointee.next = firstElement
        firstElement.pointee.previous = self.head
    }
    
    @inlinable
    public func makeIterator() -> LinkedListIterator {
        return LinkedListIterator(list: self)
    }
}
