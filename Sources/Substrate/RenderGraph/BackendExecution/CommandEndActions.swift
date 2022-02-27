//
//  CommandEndActions.swift
//  SubstrateRender  
//
//  Created by Thomas Roughton on 9/05/21.
//

import Foundation
import SubstrateUtilities

enum CommandEndActionType: @unchecked Sendable {
    case release(Unmanaged<AnyObject>)
    
    func execute() {
        switch self {
        case .release(let reference):
            reference.release()
        }
    }
}

struct CommandEndAction: Sendable {
    let type: CommandEndActionType
    let after: QueueCommandIndices
}

struct QueueEndAction: Sendable {
    let type: CommandEndActionType
    let after: UInt64
}

@globalActor
final actor CommandEndActionManager {
    static let shared = CommandEndActionManager()
    
    var deviceCommandEndActions = RingBuffer<CommandEndAction>()
    var queueCommandEndActions = (0..<QueueRegistry.maxQueues).map { _ in RingBuffer<QueueEndAction>() }
    
    func enqueue(action: CommandEndActionType, after commandIndices: QueueCommandIndices) {
        self.deviceCommandEndActions.append(CommandEndAction(type: action, after: commandIndices))
    }
    
    func enqueue(deviceAction: CommandEndAction) { // FIXME: Swift Assertion failed: (Layout->getElementOffset(F.LayoutFieldIndex) == F.Offset), function finish, file CoroFrame.cpp, line 771.
        self.deviceCommandEndActions.append(deviceAction)
    }
    
    func enqueue(action: CommandEndActionType, after commandIndex: UInt64, on queue: Queue) {
        self.queueCommandEndActions[Int(queue.index)].append(QueueEndAction(type: action, after: commandIndex))
    }
    
    func didCompleteCommand(_ command: UInt64, on queue: Queue) {
        do {
            var lastCompletedCommands = QueueRegistry.lastCompletedCommands
            lastCompletedCommands[Int(queue.index)] = command // We have a more recent lastCompletedCommand than the queue does.
            
            var processedCount = 0
            for action in self.deviceCommandEndActions {
                let requirement = action.after
                let isComplete = all(lastCompletedCommands .>= requirement)
                
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
    
    static nonisolated func enqueue(action: CommandEndActionType, after commandIndices: QueueCommandIndices = QueueRegistry.lastSubmittedCommands) {
        let action = CommandEndAction(type: action, after: commandIndices)
        Task { @CommandEndActionManager in
            await shared.enqueue(deviceAction: action)
        }
    }
    
    static nonisolated func enqueue(action: CommandEndActionType, after commandIndex: UInt64, on queue: Queue) {
        Task { @CommandEndActionManager in
            await shared.enqueue(action: action, after: commandIndex, on: queue)
        }
    }
    
    static nonisolated func didCompleteCommand(_ command: UInt64, on queue: Queue) {
        Task { @CommandEndActionManager in
            await shared.didCompleteCommand(command, on: queue)
        }
    }
}
