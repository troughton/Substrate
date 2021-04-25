//
//  Threading.swift
//  
//
//  Created by Thomas Roughton on 23/12/20.
//

import Atomics
import Dispatch
import Foundation

// FIXME: this entire file is terribly hacky.
public enum Threading {
    static var _threadCount: ManagedAtomic<Int>! = nil
    static var threadIndexKey = pthread_key_t()
    
    static func initialise() {
        self._threadCount = .init(0)
        pthread_key_create(&self.threadIndexKey, nil)
            
        let threadIndex = _threadCount.unsafelyUnwrapped.loadThenWrappingIncrement(ordering: .relaxed)
        pthread_setspecific(threadIndexKey, UnsafeRawPointer(bitPattern: threadIndex &+ 1))
    }
    
    public static var threadCount: Int {
        return 256 // _threadCount.load(ordering: .relaxed)
    }
    
    public static var threadIndex: Int {
        if pthread_getspecific(threadIndexKey) == nil {
            let threadIndex = _threadCount.unsafelyUnwrapped.loadThenWrappingIncrement(ordering: .relaxed)
            pthread_setspecific(threadIndexKey, UnsafeRawPointer(bitPattern: threadIndex + 1))
            assert(threadIndex < self.threadCount)
        }
        return Int(bitPattern: pthread_getspecific(threadIndexKey)) &- 1
    }
}
