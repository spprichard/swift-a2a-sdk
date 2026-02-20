import Foundation

/// TaskStore protocol for persisting and retrieving Task objects
public protocol TaskStore: Sendable {
    /// Save or update a task in the store
    /// - Parameters:
    ///   - task: The task to save
    ///   - context: Optional server call context
    func save(_ task: Task, context: ServerCallContext?) async throws
    
    /// Retrieve a task from the store by ID
    /// - Parameters:
    ///   - taskID: The task ID to retrieve
    ///   - context: Optional server call context
    /// - Returns: The task if found, nil otherwise
    func get(taskID: String, context: ServerCallContext?) async throws -> Task?
    
    /// Delete a task from the store by ID
    /// - Parameters:
    ///   - taskID: The task ID to delete
    ///   - context: Optional server call context
    func delete(taskID: String, context: ServerCallContext?) async throws
}

