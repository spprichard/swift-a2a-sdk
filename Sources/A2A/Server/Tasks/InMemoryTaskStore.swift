import Foundation

/// In-memory implementation of TaskStore.
/// Stores task objects in a dictionary in memory. Task data is lost when the
/// server process stops.
public actor InMemoryTaskStore: TaskStore {
    private var tasks: [String: Task] = [:]
    
    public init() {}
    
    public func save(_ task: Task, context: ServerCallContext?) async throws {
        tasks[task.id] = task
    }
    
    public func get(taskID: String, context: ServerCallContext?) async throws -> Task? {
        return tasks[taskID]
    }
    
    public func delete(taskID: String, context: ServerCallContext?) async throws {
        tasks.removeValue(forKey: taskID)
    }
}

