//
//  CommandEndActions.swift
//  SubstrateRender  
//
//  Created by Thomas Roughton on 9/05/21.
//

import Foundation
import SubstrateUtilities

enum CommandEndActionType {
    case release(Unmanaged<AnyObject>)
    
    func execute() {
        switch self {
        case .release(let reference):
            reference.release()
        }
    }
}

struct CommandEndAction {
    let type: CommandEndActionType
    let after: QueueCommandIndices
}

struct QueueEndAction {
    let type: CommandEndActionType
    let after: UInt64
}

final class CommandEndActionManager {
    static let manager = CommandEndActionManager()
    let queue = DispatchQueue(label: "CommandEndActionManager Queue")
    
    var deviceCommandEndActions = RingBuffer<CommandEndAction>()
    var queueCommandEndActions = (0..<QueueRegistry.maxQueues).map { _ in RingBuffer<QueueEndAction>() }
    
    func enqueue(action: CommandEndActionType, after commandIndices: QueueCommandIndices = QueueRegistry.lastSubmittedCommands) {
        self.queue.sync {
            self.deviceCommandEndActions.append(CommandEndAction(type: action, after: commandIndices))
        }
    }
    
    func enqueue(action: CommandEndActionType, after commandIndex: UInt64, on queue: Queue) {
        self.queue.sync {
            self.queueCommandEndActions[Int(queue.index)].append(QueueEndAction(type: action, after: commandIndex))
        }
    }
    
    func didCompleteCommand(_ command: UInt64, on queue: Queue) {
        // NOTE: this must be synchronous since we need to release any used resources before CPU-side observers
        // are notified that the command is completed; this is particularly important when the CPU
        // is waiting for resources to be freed from a heap.
        self.queue.sync {
            do {
                var processedCount = 0
                for action in self.deviceCommandEndActions {
                    let requirement = action.after
                    let isComplete = QueueRegistry.allQueues.enumerated()
                        .allSatisfy { i, queue in queue.lastCompletedCommand >= requirement[i] }
                    if !isComplete {
                        break
                    }
                    action.type.execute()
                    processedCount += 1
                }
                self.deviceCommandEndActions.removeFirst(processedCount)
            }
            
            do {
                var processedCount = 0
                for action in self.queueCommandEndActions[Int(queue.index)] {
                    guard action.after <= command else {
                        break
                    }
                    action.type.execute()
                    processedCount += 1
                }
                self.queueCommandEndActions[Int(queue.index)].removeFirst(processedCount)
            }
        }
    }
}
