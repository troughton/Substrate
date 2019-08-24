//
//  FrameCompletion.swift
//  LlamaCore
//
//  Created by Thomas Roughton on 29/05/18.
//

import Foundation
import FrameGraphCExtras
import SwiftAtomics


public struct FrameCompletion {
    @usableFromInline
    static var _lastCompletedFrame : AtomicUInt64 = {
        var frame = AtomicUInt64(0)
        return frame
    }()
    
    public static func waitForFrame(_ frame: UInt64) {
        while _lastCompletedFrame.load() < frame {
            #if os(Windows)
            _sleep(0)
            #else
            sched_yield()
            #endif
        }
    }

    @inlinable
    public static func frameIsComplete(_ frame: UInt64) -> Bool {
        return _lastCompletedFrame.load() >= frame
    }
    
    @inlinable
    public static var lastCompletedFrame : UInt64 {
        return _lastCompletedFrame.load()
    }
    
    public static func markFrameComplete(frame: UInt64) {
        repeat {
            var testValue = self._lastCompletedFrame.load()
            if testValue < frame {
                if self._lastCompletedFrame.loadCAS(current: &testValue, future: frame, type: .weak, orderSwap: .relaxed, orderLoad: .relaxed) {
                    break
                }
            } else {
                break
            }
        } while true
    }
}
