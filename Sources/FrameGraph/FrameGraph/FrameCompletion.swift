//
//  FrameCompletion.swift
//  LlamaCore
//
//  Created by Thomas Roughton on 29/05/18.
//

import Foundation

//import Atomics
//
//public struct FrameCompletion {
//
//    private static var lastCompletedFrame : AtomicUInt64 = {
//        var value = AtomicUInt64()
//        value.initialize(0)
//        return value
//    }()
//
//    public static var currentCPURenderFrame : UInt64 = 0
//
//    public static func waitForFrame(_ frame: UInt64) {
//        while lastCompletedFrame.value < frame {
//            #if os(Windows)
//            sleep(0)
//            #else
//            sched_yield()
//            #endif
//        }
//    }
//
//    public static func frameIsComplete(_ frame: UInt64) -> Bool {
//        return lastCompletedFrame.value >= frame
//    }
//
//    public static func markFrameComplete(frame: UInt64) {
//        repeat {
//            let testValue = lastCompletedFrame.value
//            if testValue < frame {
//                if lastCompletedFrame.CAS(current: testValue, future: frame) {
//                    break
//                }
//            } else {
//                break
//            }
//        } while true
//    }
//}

public struct FrameCompletion {
    private static var lastCompletedFrame : OSAtomic_int64_aligned64_t = 0
    
    public static func waitForFrame(_ frame: UInt64) {
        while lastCompletedFrame < frame {
            #if os(Windows)
            sleep(0)
            #else
            sched_yield()
            #endif
        }
    }
    
    public static func frameIsComplete(_ frame: UInt64) -> Bool {
        return lastCompletedFrame >= frame
    }
    
    public static func markFrameComplete(frame: UInt64) {
        repeat {
            let testValue = UInt64(bitPattern: lastCompletedFrame)
            if testValue < frame {
                if OSAtomicCompareAndSwap64(Int64(bitPattern: testValue), Int64(bitPattern: frame), &lastCompletedFrame) {
                    break
                }
            } else {
                break
            }
        } while true
    }
}
