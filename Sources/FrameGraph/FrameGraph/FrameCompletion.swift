//
//  FrameCompletion.swift
//  LlamaCore
//
//  Created by Thomas Roughton on 29/05/18.
//

import Foundation
import FrameGraphCExtras
import CAtomics

public struct FrameCompletion {
    @usableFromInline
    static var _lastCompletedFrame : UnsafeMutablePointer<AtomicUInt64>! = nil
    
    public static func initialise() {
        if _lastCompletedFrame == nil {
            _lastCompletedFrame = .allocate(capacity: 1)
            _lastCompletedFrame.initialize(to: AtomicUInt64(0))
        }
    }
    
    public static func waitForFrame(_ frame: UInt64) {
        while CAtomicsLoad(_lastCompletedFrame, .relaxed) < frame {
            #if os(Windows)
            _sleep(0)
            #else
            sched_yield()
            #endif
        }
    }

    @inlinable
    public static func frameIsComplete(_ frame: UInt64) -> Bool {
        return CAtomicsLoad(_lastCompletedFrame, .relaxed) >= frame
    }
    
    @inlinable
    public static var lastCompletedFrame : UInt64 {
        return CAtomicsLoad(_lastCompletedFrame, .relaxed)
    }
    
    public static func markFrameComplete(frame: UInt64) {
        repeat {
            var testValue = CAtomicsLoad(_lastCompletedFrame, .relaxed)
            if testValue < frame {
                if CAtomicsCompareAndExchange(_lastCompletedFrame, &testValue, frame, .weak, .relaxed, .relaxed) {
                    break
                }
            } else {
                break
            }
        } while true
    }
}
