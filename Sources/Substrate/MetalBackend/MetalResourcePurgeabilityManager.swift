//
//  File.swift
//  
//
//  Created by Thomas Roughton on 6/05/21.
//

#if canImport(Metal)

import Foundation
import Metal
import OrderedCollections
import SubstrateUtilities

struct MTLPendingPurgeabilityChange {
    let resource: MTLResource
    let state: MTLPurgeableState
    let after: QueueCommandIndices
}

// A utility to ensure that volatile/empty purgeable states only get applied once all GPU commands in-flight have completed.
final class MetalResourcePurgeabilityManager {
    static let instance = MetalResourcePurgeabilityManager()
    
    let lock = DispatchSemaphore(value: 1)
    var pendingPurgabilityChanges: OrderedDictionary<ObjectIdentifier, MTLPendingPurgeabilityChange> = [:]
    
    @discardableResult
    func setPurgeableState(on resource: MTLResource, to state: MTLPurgeableState) -> MTLPurgeableState {
        // Possibly due to bugs in the MTLPurgeableStates returned by Metal, scheduling purgeability changes for after a resource has finished being used seems to cause more issues than it prevents.
        // Just forward the calls directly to Metal instead.
        return resource.setPurgeableState(state)
        
        
//        self.lock.withSemaphore {
//            switch state {
//            case .volatile, .empty:
//                let pendingCommands = QueueRegistry.lastSubmittedCommands
//                if !all(QueueRegistry.lastCompletedCommands .>= pendingCommands) {
//                    self.pendingPurgabilityChanges.updateValue(MTLPendingPurgeabilityChange(resource: resource, state: state, after: pendingCommands), forKey: ObjectIdentifier(resource))
//                    return resource.setPurgeableState(.keepCurrent)
//                } else {
//                    fallthrough
//                }
//            default:
//                let pendingValue = self.pendingPurgabilityChanges.removeValue(forKey: ObjectIdentifier(resource))
//                let trueValue = resource.setPurgeableState(state)
//                return pendingValue?.state == .empty ? .empty : trueValue
//            }
//        }
    }
    
    @discardableResult
    func setPurgeableState(on heap: MTLHeap, to state: MTLPurgeableState) -> MTLPurgeableState {
        self.setPurgeableState(on: unsafeBitCast(heap, to: MTLResource.self), to: state) // We only call updatePurgeableState, and it's an Objective-C protocol (meaning the function is accessed through objc_msgsend, so the unsafe cast is fine.
    }
    
    func processPurgeabilityChanges() {
        // Possibly due to bugs in the MTLPurgeableStates returned by Metal, scheduling purgeability changes for after a resource has finished being used seems to cause more issues than it prevents.
        // Since we just forward the calls directly to Metal instead, this can be a no-op.
        return;
        
        guard self.lock.wait(timeout: .now()) == .success else { return }
        var processedCount = 0
        let lastCompletedCommands = QueueRegistry.lastCompletedCommands
        for (_, value) in self.pendingPurgabilityChanges {
            let requirement = value.after
            let isComplete = all(lastCompletedCommands .>= requirement)
            if !isComplete {
                break
            }
            value.resource.setPurgeableState(value.state)
            processedCount += 1
        }
        self.pendingPurgabilityChanges.removeFirst(processedCount)
        self.lock.signal()
    }
}

#endif
