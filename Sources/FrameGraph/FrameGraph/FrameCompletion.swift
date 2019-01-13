//
//  FrameCompletion.swift
//  LlamaCore
//
//  Created by Thomas Roughton on 29/05/18.
//

import Foundation
import FrameGraphCExtras
import Atomics


public struct FrameCompletion {
    private static var lastCompletedFrame : AtomicUInt64 = {
        var frame = AtomicUInt64()
        frame.initialize(0)
        return frame
    }()
    
    public static func waitForFrame(_ frame: UInt64) {
        while lastCompletedFrame.value < frame {
            #if os(Windows)
            _sleep(0)
            #else
            sched_yield()
            #endif
        }
    }
    
    public static func frameIsComplete(_ frame: UInt64) -> Bool {
        return lastCompletedFrame.value >= frame
    }
    
    public static func markFrameComplete(frame: UInt64) {
        repeat {
            var testValue = self.lastCompletedFrame.value
            if testValue < frame {
                if self.lastCompletedFrame.loadCAS(current: &testValue, future: frame, type: .weak, orderSwap: .relaxed, orderLoad: .relaxed) {
                    break
                }
            } else {
                break
            }
        } while true
    }
}
