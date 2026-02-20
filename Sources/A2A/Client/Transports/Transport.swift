import Foundation

/// ClientTransport protocol for client transport implementations
public protocol ClientTransport: Sendable {
    /// Send a non-streaming message request to the agent
    /// - Parameters:
    ///   - message: The message to send
    ///   - taskID: Optional task ID
    ///   - contextID: Optional context ID
    /// - Returns: Either a Task or Message response
    func sendMessage(
        message: Message,
        taskID: String?,
        contextID: String?
    ) async throws -> TaskOrMessage
    
    /// Send a streaming message request to the agent
    /// - Parameters:
    ///   - message: The message to send
    ///   - taskID: Optional task ID
    ///   - contextID: Optional context ID
    /// - Returns: An AsyncSequence of events
    func sendMessageStreaming(
        message: Message,
        taskID: String?,
        contextID: String?
    ) -> AsyncStream<Event>
    
    /// Retrieve the current state and history of a specific task
    /// - Parameter taskID: The task ID to retrieve
    /// - Returns: The Task object
    func getTask(taskID: String) async throws -> Task
    
    /// Close the transport
    func close() async throws
}

