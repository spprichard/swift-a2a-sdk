import Foundation

/// A2A request handler protocol.
/// This interface defines the methods that an A2A server implementation must
/// provide to handle incoming JSON-RPC requests.
public protocol RequestHandler: Sendable {
    /// Handles the 'tasks/get' method.
    /// Retrieves the state and history of a specific task.
    /// - Parameters:
    ///   - taskID: The task ID to retrieve
    ///   - context: Context provided by the server
    /// - Returns: The Task object if found, otherwise nil
    func onGetTask(taskID: String, context: ServerCallContext?) async throws -> Task?
    
    /// Handles the 'message/send' method (non-streaming).
    /// Sends a message to the agent to create, continue, or restart a task,
    /// and waits for the final result (Task or Message).
    /// - Parameters:
    ///   - message: The message to send
    ///   - taskID: Optional task ID if continuing an existing task
    ///   - contextID: Optional context ID
    ///   - context: Context provided by the server
    /// - Returns: The final Task object or a final Message object
    func onMessageSend(
        message: Message,
        taskID: String?,
        contextID: String?,
        context: ServerCallContext?
    ) async throws -> TaskOrMessage
    
    /// Handles the 'message/stream' method (streaming).
    /// Sends a message to the agent and yields stream events as they are
    /// produced (Task updates, Message chunks, Artifact updates).
    /// - Parameters:
    ///   - message: The message to send
    ///   - taskID: Optional task ID if continuing an existing task
    ///   - contextID: Optional context ID
    ///   - context: Context provided by the server
    /// - Returns: An AsyncThrowingStream of Event objects from the agent's execution
    func onMessageSendStream(
        message: Message,
        taskID: String?,
        contextID: String?,
        context: ServerCallContext?
    ) -> AsyncThrowingStream<Event, Error>
}

/// Union type for Task or Message response
public enum TaskOrMessage: Sendable {
    case task(Task)
    case message(Message)
}

