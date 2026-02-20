import Foundation

/// AgentExecutor protocol for agent implementations.
/// Implementations of this interface contain the core logic of the agent,
/// executing tasks based on requests and publishing updates to an event queue.
public protocol AgentExecutor: Sendable {
    /// Execute the agent's logic for a given request context.
    /// The agent should read necessary information from the context and
    /// publish Task or Message events, or TaskStatusUpdateEvent /
    /// TaskArtifactUpdateEvent to the eventQueue. This method should
    /// return once the agent's execution for this request is complete or
    /// yields control (e.g., enters an input-required state).
    /// - Parameters:
    ///   - context: The request context containing the message, task ID, etc.
    ///   - eventQueue: The queue to publish events to.
    func execute(context: RequestContext, eventQueue: EventQueue) async throws
    
    /// Request the agent to cancel an ongoing task.
    /// The agent should attempt to stop the task identified by the task_id
    /// in the context and publish a TaskStatusUpdateEvent with state
    /// cancelled to the eventQueue.
    /// - Parameters:
    ///   - context: The request context containing the task ID to cancel.
    ///   - eventQueue: The queue to publish the cancellation status update to.
    func cancel(context: RequestContext, eventQueue: EventQueue) async throws
}

