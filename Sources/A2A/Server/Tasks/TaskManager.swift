import Foundation

/// TaskManager helps manage a task's lifecycle during execution of a request.
/// Responsible for retrieving, saving, and updating the Task object based on
/// events received from the agent.
public class TaskManager {
    private var taskID: String?
    private var contextID: String?
    private let taskStore: TaskStore
    private let initialMessage: Message?
    private let callContext: ServerCallContext?
    private var currentTask: Task?
    
    /// Initialize the TaskManager
    /// - Parameters:
    ///   - taskID: The ID of the task, if known from the request
    ///   - contextID: The ID of the context, if known from the request
    ///   - taskStore: The TaskStore instance for persistence
    ///   - initialMessage: The Message that initiated the task, if any
    ///   - context: The ServerCallContext that this task is produced under
    public init(
        taskID: String? = nil,
        contextID: String? = nil,
        taskStore: TaskStore,
        initialMessage: Message? = nil,
        context: ServerCallContext? = nil
    ) {
        if let taskID = taskID, taskID.isEmpty {
            fatalError("Task ID must be a non-empty string")
        }
        
        self.taskID = taskID
        self.contextID = contextID
        self.taskStore = taskStore
        self.initialMessage = initialMessage
        self.callContext = context
    }
    
    /// Retrieve the current task object, either from memory or the store
    /// - Returns: The Task object if found, otherwise nil
    public func getTask() async throws -> Task? {
        guard let taskID = taskID else {
            return nil
        }
        
        if let currentTask = currentTask {
            return currentTask
        }
        
        currentTask = try await taskStore.get(taskID: taskID, context: callContext)
        return currentTask
    }
    
    /// Process a task-related event and save the updated task state
    /// - Parameter event: The task-related event
    /// - Returns: The updated Task object after processing the event
    public func saveTaskEvent(_ event: Event) async throws -> Task? {
        let taskIDFromEvent: String
        let contextIDFromEvent: String
        
        switch event {
        case .task(let task):
            taskIDFromEvent = task.id
            contextIDFromEvent = task.contextID
        case .taskStatusUpdate(let update):
            taskIDFromEvent = update.taskID
            contextIDFromEvent = update.contextID
        case .taskArtifactUpdate(let update):
            taskIDFromEvent = update.taskID
            contextIDFromEvent = update.contextID
        default:
            return nil
        }
        
        // Validate task ID matches if already set
        if let existingTaskID = taskID, existingTaskID != taskIDFromEvent {
            throw InvalidParamsError(
                message: "Task in event doesn't match TaskManager \(existingTaskID) : \(taskIDFromEvent)"
            )
        }
        
        if taskID == nil {
            taskID = taskIDFromEvent
        }
        
        // Validate context ID matches if already set
        if let existingContextID = contextID, existingContextID != contextIDFromEvent {
            throw InvalidParamsError(
                message: "Context in event doesn't match TaskManager \(existingContextID) : \(contextIDFromEvent)"
            )
        }
        
        if contextID == nil {
            contextID = contextIDFromEvent
        }
        
        // Handle different event types
        switch event {
        case .task(let task):
            try await saveTask(task)
            return task
            
        case .taskStatusUpdate(let update):
            let task = try await ensureTask(update)
            var updatedTask = task
            
            // Move current status message to history if present
            if let statusMessage = updatedTask.status.message {
                if updatedTask.history.isEmpty {
                    updatedTask.history = [statusMessage]
                } else {
                    updatedTask.history.append(statusMessage)
                }
            }
            
            // Update metadata if present
            if let metadata = update.metadata {
                if updatedTask.metadata == nil {
                    updatedTask.metadata = [:]
                }
                // Merge metadata (simplified - in real implementation would need proper merging)
                // For now, we just ensure metadata exists
            }
            
            updatedTask.status = update.status
            try await saveTask(updatedTask)
            return updatedTask
            
        case .taskArtifactUpdate(let update):
            let task = try await ensureTask(update)
            var updatedTask = task
            
            if update.append {
                // Append to existing artifact
                if let existingIndex = updatedTask.artifacts.firstIndex(where: { $0.artifactID == update.artifact.artifactID }) {
                    // Merge artifact parts (simplified)
                    updatedTask.artifacts[existingIndex] = update.artifact
                } else {
                    updatedTask.artifacts.append(update.artifact)
                }
            } else {
                updatedTask.artifacts.append(update.artifact)
            }
            
            try await saveTask(updatedTask)
            return updatedTask
            
        default:
            return nil
        }
    }
    
    /// Ensure a Task object exists in memory, loading from store or creating new if needed
    /// - Parameter event: The task-related event triggering the need for a Task object
    /// - Returns: An existing or newly created Task object
    private func ensureTask(_ event: TaskStatusUpdateEvent) async throws -> Task {
        var task = currentTask
        
        if task == nil, let taskID = taskID {
            task = try await taskStore.get(taskID: taskID, context: callContext)
        }
        
        if task == nil {
            // Create new task
            task = initTaskObject(taskID: event.taskID, contextID: event.contextID)
            try await saveTask(task!)
        }
        
        return task!
    }
    
    private func ensureTask(_ event: TaskArtifactUpdateEvent) async throws -> Task {
        var task = currentTask
        
        if task == nil, let taskID = taskID {
            task = try await taskStore.get(taskID: taskID, context: callContext)
        }
        
        if task == nil {
            // Create new task
            task = initTaskObject(taskID: event.taskID, contextID: event.contextID)
            try await saveTask(task!)
        }
        
        return task!
    }
    
    /// Process an event, update task state if applicable, store it, and return the event
    /// - Parameter event: The event object received from the agent
    /// - Returns: The same event object that was processed
    public func process(_ event: Event) async throws -> Event {
        switch event {
        case .task, .taskStatusUpdate, .taskArtifactUpdate:
            _ = try await saveTaskEvent(event)
        default:
            break
        }
        return event
    }
    
    /// Initialize a new task object in memory
    /// - Parameters:
    ///   - taskID: The ID for the new task
    ///   - contextID: The context ID for the new task
    /// - Returns: A new Task object with initial status
    private func initTaskObject(taskID: String, contextID: String) -> Task {
        let history = initialMessage != nil ? [initialMessage!] : []
        return Task(
            id: taskID,
            contextID: contextID,
            status: TaskStatus(state: .submitted),
            artifacts: [],
            history: history
        )
    }
    
    /// Save the given task to the task store and update the in-memory currentTask
    /// - Parameter task: The Task object to save
    private func saveTask(_ task: Task) async throws {
        try await taskStore.save(task, context: callContext)
        currentTask = task
        if self.taskID == nil {
            self.taskID = task.id
            self.contextID = task.contextID
        }
    }
    
    /// Update a task object in memory by adding a new message to its history
    /// - Parameters:
    ///   - message: The new Message to add to the history
    ///   - task: The Task object to update
    /// - Returns: The updated Task object
    public func updateWithMessage(_ message: Message, task: Task) -> Task {
        var updatedTask = task
        
        // Move current status message to history if present
        if let statusMessage = updatedTask.status.message {
            if updatedTask.history.isEmpty {
                updatedTask.history = [statusMessage]
            } else {
                updatedTask.history.append(statusMessage)
            }
            updatedTask.status.message = nil
        }
        
        // Add new message to history
        updatedTask.history.append(message)
        currentTask = updatedTask
        return updatedTask
    }
}

