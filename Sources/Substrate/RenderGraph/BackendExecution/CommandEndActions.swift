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

final actor CommandEndActionManager {
    static let manager = CommandEndActionManager()
    
    var deviceCommandEndActions = RingBuffer<CommandEndAction>()
    var queueCommandEndActions = (0..<QueueRegistry.maxQueues).map { _ in RingBuffer<QueueEndAction>() }
    
    func enqueue(action: CommandEndActionType, after commandIndices: QueueCommandIndices = QueueRegistry.lastSubmittedCommands) {
        self.deviceCommandEndActions.append(CommandEndAction(type: action, after: commandIndices))
    }
    
    func enqueue(action: CommandEndActionType, after commandIndex: UInt64, on queue: Queue) {
        self.queueCommandEndActions[Int(queue.index)].append(QueueEndAction(type: action, after: commandIndex))
    }
    
    func didCompleteCommand(_ command: UInt64, on queue: Queue) {
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
    
    static func enqueue(action: CommandEndActionType, after commandIndices: QueueCommandIndices = QueueRegistry.lastSubmittedCommands) {
        _ = Task {
            await manager.enqueue(action: action, after: commandIndices)
        }
    }
    
    static func enqueue(action: CommandEndActionType, after commandIndex: UInt64, on queue: Queue) {
        _ = Task {
            await manager.enqueue(action: action, after: commandIndex, on: queue)
        }
    }
    
    static func didCompleteCommand(_ command: UInt64, on queue: Queue) {
        _ = Task {
            await manager.didCompleteCommand(command, on: queue)
        }
    }
}
