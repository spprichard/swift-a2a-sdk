import Foundation

/// ClientTaskManager helps manage a task's lifecycle on the client side.
/// Responsible for tracking and updating the Task object based on
/// events received from the agent.
public class ClientTaskManager {
    private var currentTask: Task?
    private var taskID: String?
    private var contextID: String?
    
    public init() {}
    
    /// Retrieve the current task object
    /// - Returns: The Task object if found, otherwise nil
    public func getTask() -> Task? {
        guard taskID != nil else {
            return nil
        }
        return currentTask
    }
    
    /// Retrieve the current task object or throw an error
    /// - Returns: The Task object
    /// - Throws: A2AClientInvalidStateError if no task is available
    public func getTaskOrThrow() throws -> Task {
        guard let task = getTask() else {
            throw A2AClientInvalidStateError("no current Task")
        }
        return task
    }
    
    /// Process a task-related event and update the task state
    /// - Parameter event: The task-related event
    /// - Returns: The updated Task object after processing the event
    public func process(_ event: Event) async throws -> Task? {
        switch event {
        case .task(let task):
            if currentTask != nil {
                throw A2AClientInvalidStateError("Task is already set, create new manager for new tasks")
            }
            return try await saveTaskEvent(task)
            
        case .taskStatusUpdate(let update):
            return try await saveTaskEvent(update)
            
        case .taskArtifactUpdate(let update):
            return try await saveTaskEvent(update)
            
        case .message:
            // Messages don't update task state directly
            return currentTask
        }
    }
    
    private func saveTaskEvent(_ task: Task) async throws -> Task {
        let taskIDFromEvent = task.id
        
        if let existingTaskID = taskID, existingTaskID != taskIDFromEvent {
            throw A2AClientInvalidStateError(
                "Task in event doesn't match TaskManager \(existingTaskID) : \(taskIDFromEvent)"
            )
        }
        
        if taskID == nil {
            taskID = taskIDFromEvent
        }
        if contextID == nil {
            contextID = task.contextID
        }
        
        currentTask = task
        return task
    }
    
    private func saveTaskEvent(_ update: TaskStatusUpdateEvent) async throws -> Task {
        let taskIDFromEvent = update.taskID
        
        if let existingTaskID = taskID, existingTaskID != taskIDFromEvent {
            throw A2AClientInvalidStateError(
                "Task in event doesn't match TaskManager \(existingTaskID) : \(taskIDFromEvent)"
            )
        }
        
        if taskID == nil {
            taskID = taskIDFromEvent
        }
        if contextID == nil {
            contextID = update.contextID
        }
        
        var task = currentTask
        if task == nil {
            // Create new task from update
            task = Task(
                id: taskIDFromEvent,
                contextID: update.contextID,
                status: update.status,
                artifacts: [],
                history: []
            )
        } else {
            // Update existing task
            if let statusMessage = update.status.message {
                if task!.history.isEmpty {
                    task!.history = [statusMessage]
                } else {
                    task!.history.append(statusMessage)
                }
            }
            
            if let metadata = update.metadata {
                if task!.metadata == nil {
                    task!.metadata = [:]
                }
                // Merge metadata (simplified)
                // For now, we just ensure metadata exists
            }
            
            task!.status = update.status
        }
        
        currentTask = task
        return task!
    }
    
    private func saveTaskEvent(_ update: TaskArtifactUpdateEvent) async throws -> Task {
        let taskIDFromEvent = update.taskID
        
        if let existingTaskID = taskID, existingTaskID != taskIDFromEvent {
            throw A2AClientInvalidStateError(
                "Task in event doesn't match TaskManager \(existingTaskID) : \(taskIDFromEvent)"
            )
        }
        
        if taskID == nil {
            taskID = taskIDFromEvent
        }
        if contextID == nil {
            contextID = update.contextID
        }
        
        var task = currentTask
        if task == nil {
            // Create new task from update
            task = Task(
                id: taskIDFromEvent,
                contextID: update.contextID,
                status: TaskStatus(state: .working),
                artifacts: [],
                history: []
            )
        }
        
        // Append or update artifact
        if update.append {
            if let existingIndex = task!.artifacts.firstIndex(where: { $0.artifactID == update.artifact.artifactID }) {
                task!.artifacts[existingIndex] = update.artifact
            } else {
                task!.artifacts.append(update.artifact)
            }
        } else {
            task!.artifacts.append(update.artifact)
        }
        
        currentTask = task
        return task!
    }
}

