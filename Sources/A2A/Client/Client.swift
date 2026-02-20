import Foundation

/// Client protocol for interacting with A2A agents
public protocol Client {
    /// Send a message to the agent
    /// - Parameters:
    ///   - message: The message to send
    ///   - taskID: Optional task ID if continuing an existing task
    ///   - contextID: Optional context ID
    /// - Returns: An AsyncSequence yielding either TaskOrMessage or individual Events for streaming
    func sendMessage(
        message: Message,
        taskID: String?,
        contextID: String?
    ) -> AsyncStream<TaskOrMessageOrEvent>
    
    /// Get a task by ID
    /// - Parameter taskID: The task ID to retrieve
    /// - Returns: The Task object
    func getTask(taskID: String) async throws -> Task
    
    /// Close the client
    func close() async throws
}

/// Union type for Task, Message, or Event
public enum TaskOrMessageOrEvent: Sendable {
    case taskOrMessage(TaskOrMessage)
    case event(Event)
}

/// Base client implementation with transport-independent logic
public class BaseClient: Client {
    private let agentCard: AgentCard
    private let transport: ClientTransport
    private let supportsStreaming: Bool
    
    public init(
        agentCard: AgentCard,
        transport: ClientTransport,
        supportsStreaming: Bool = true
    ) {
        self.agentCard = agentCard
        self.transport = transport
        self.supportsStreaming = supportsStreaming
    }
    
    public func sendMessage(
        message: Message,
        taskID: String?,
        contextID: String?
    ) -> AsyncStream<TaskOrMessageOrEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: TaskOrMessageOrEvent.self)
        
        // Capture properties explicitly to avoid capturing 'self'
        let supportsStreaming = self.supportsStreaming
        let agentCard = self.agentCard
        let transport = self.transport
        
        _Concurrency.Task { @Sendable in
            do {
                if supportsStreaming && agentCard.capabilities.streaming == true {
                    // Use streaming
                    let eventStream = transport.sendMessageStreaming(
                        message: message,
                        taskID: taskID,
                        contextID: contextID
                    )
                    
                    var firstEvent: Event?
                    for await event in eventStream {
                        if firstEvent == nil {
                            firstEvent = event
                            // Check if first event is a Message (non-streaming response)
                            if case .message(let msg) = event {
                                continuation.yield(.taskOrMessage(.message(msg)))
                                continuation.finish()
                                return
                            }
                        }
                        
                        continuation.yield(.event(event))
                        
                        // Check if this is a final event
                        if case .taskStatusUpdate(let update) = event, update.isFinal {
                            // Get final task state
                            if let task = try? await transport.getTask(taskID: update.taskID) {
                                continuation.yield(.taskOrMessage(.task(task)))
                            }
                            break
                        }
                    }
                    
                    continuation.finish()
                } else {
                    // Use non-streaming
                    let result = try await transport.sendMessage(
                        message: message,
                        taskID: taskID,
                        contextID: contextID
                    )
                    continuation.yield(.taskOrMessage(result))
                    continuation.finish()
                }
            } catch {
                continuation.finish()
            }
        }
        
        return stream
    }
    
    public func getTask(taskID: String) async throws -> Task {
        return try await transport.getTask(taskID: taskID)
    }
    
    public func close() async throws {
        try await transport.close()
    }
}

