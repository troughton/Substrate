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
    let resource: AnyObject & NSObjectProtocol
    let state: MTLPurgeableState
    let after: QueueCommandIndices
}

// A utility to ensure that volatile/empty purgeable states only get applied once all GPU commands in-flight have completed.
final class MetalResourcePurgeabilityManager {
    static let instance = MetalResourcePurgeabilityManager()
    
    let lock = DispatchSemaphore(value: 1)
    var pendingPurgabilityChanges: OrderedDictionary<ObjectIdentifier, MTLPendingPurgeabilityChange> = [:]
    
    @discardableResult
    func setPurgeableState(resource: AnyObject & NSObjectProtocol, setState: (MTLPurgeableState) -> MTLPurgeableState, to state: MTLPurgeableState) -> MTLPurgeableState {
        self.lock.withSemaphore {
            let pendingValue = self.pendingPurgabilityChanges.removeValue(forKey: ObjectIdentifier(resource))
            switch state {
            case .volatile, .empty:
                let pendingCommands = QueueRegistry.lastSubmittedCommands
                if !all(QueueRegistry.lastCompletedCommands .>= pendingCommands) {
                    self.pendingPurgabilityChanges.updateValue(MTLPendingPurgeabilityChange(resource: resource, state: state, after: pendingCommands), forKey: ObjectIdentifier(resource))
                    return setState(.keepCurrent)
                } else {
                    fallthrough
                }
            default:
                let trueValue = setState(state)
                return pendingValue?.state == .empty ? .empty : trueValue
            }
        }
    }
    
    @discardableResult
    func setPurgeableState(on resource: MTLResource, to state: MTLPurgeableState) -> MTLPurgeableState {
        self.setPurgeableState(resource: resource, setState: { newState in
            resource.setPurgeableState(newState)
        }, to: state)
    }
    
    @discardableResult
    func setPurgeableState(on heap: MTLHeap, to state: MTLPurgeableState) -> MTLPurgeableState {
        self.setPurgeableState(resource: heap, setState: { newState in
            heap.setPurgeableState(newState)
        }, to: state)
    }
    
    func processPurgeabilityChanges() {
        guard self.lock.wait(timeout: .now()) == .success else { return }
        var processedCount = 0
        let lastCompletedCommands = QueueRegistry.lastCompletedCommands
        for (_, value) in self.pendingPurgabilityChanges {
            let requirement = value.after
            let isComplete = all(lastCompletedCommands .>= requirement)
            if !isComplete {
                break
            }
            if let heap = value.resource as? MTLHeap {
                heap.setPurgeableState(value.state)
            } else {
                unsafeBitCast(value.resource, to: MTLResource.self).setPurgeableState(value.state)
            }
            processedCount += 1
        }
        self.pendingPurgabilityChanges.removeFirst(processedCount)
        self.lock.signal()
    }
}

#endif
