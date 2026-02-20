import Foundation
@preconcurrency import AnyCodable

/// Event types that can be enqueued
public enum Event: Sendable {
    case message(Message)
    case task(Task)
    case taskStatusUpdate(TaskStatusUpdateEvent)
    case taskArtifactUpdate(TaskArtifactUpdateEvent)
}

/// TaskStatusUpdateEvent represents a task status change
public struct TaskStatusUpdateEvent: Codable, Sendable {
    public var taskID: String
    public var contextID: String
    public var status: TaskStatus
    public var isFinal: Bool
    // Store as AnyCodable for Sendable/Codable conformance
    public var metadata: [String: AnyCodable]?
    
    /// Access metadata as [String: Any]
    public var metadataValue: [String: Any]? {
        get { metadata?.mapValues { $0.value } }
        set { metadata = newValue?.mapValues { AnyCodable($0) } }
    }
    
    // Per spec Section 5.5: JSON uses camelCase field names
    private enum CodingKeys: String, CodingKey {
        case taskID = "taskId"
        case contextID = "contextId"
        case status
        case isFinal = "final"
        case metadata
    }
    
    public init(
        taskID: String,
        contextID: String,
        status: TaskStatus,
        isFinal: Bool,
        metadata: [String: Any]? = nil
    ) {
        self.taskID = taskID
        self.contextID = contextID
        self.status = status
        self.isFinal = isFinal
        self.metadata = metadata?.mapValues { AnyCodable($0) }
    }
}

/// TaskArtifactUpdateEvent represents an artifact update
public struct TaskArtifactUpdateEvent: Codable, Sendable {
    public var taskID: String
    public var contextID: String
    public var artifact: Artifact
    public var append: Bool
    public var lastChunk: Bool
    // Store as AnyCodable for Sendable/Codable conformance
    public var metadata: [String: AnyCodable]?
    
    /// Access metadata as [String: Any]
    public var metadataValue: [String: Any]? {
        get { metadata?.mapValues { $0.value } }
        set { metadata = newValue?.mapValues { AnyCodable($0) } }
    }
    
    // Per spec Section 5.5: JSON uses camelCase field names
    private enum CodingKeys: String, CodingKey {
        case taskID = "taskId"
        case contextID = "contextId"
        case artifact
        case append
        case lastChunk
        case metadata
    }
    
    public init(
        taskID: String,
        contextID: String,
        artifact: Artifact,
        append: Bool = false,
        lastChunk: Bool = false,
        metadata: [String: Any]? = nil
    ) {
        self.taskID = taskID
        self.contextID = contextID
        self.artifact = artifact
        self.append = append
        self.lastChunk = lastChunk
        self.metadata = metadata?.mapValues { AnyCodable($0) }
    }
}

/// Default maximum queue size
public let defaultMaxQueueSize = 1024

/// EventQueue is an actor-based event queue for A2A responses from agent.
/// Acts as a buffer between the agent's asynchronous execution and the
/// server's response handling (e.g., streaming via SSE). Supports tapping
/// to create child queues that receive the same events.
public actor EventQueue {
    private let maxQueueSize: Int
    private var events: [Event] = []
    private var children: [EventQueue] = []
    private var isClosed = false
    private var continuation: AsyncStream<Event>.Continuation?
    private var stream: AsyncStream<Event>?
    
    /// Initialize the EventQueue
    /// - Parameter maxQueueSize: Maximum number of events in the queue (must be > 0)
    public init(maxQueueSize: Int = defaultMaxQueueSize) {
        guard maxQueueSize > 0 else {
            fatalError("maxQueueSize must be greater than 0")
        }
        self.maxQueueSize = maxQueueSize
        let (stream, continuation) = AsyncStream.makeStream(of: Event.self)
        self.stream = stream
        self.continuation = continuation
    }
    
    /// Enqueue an event to this queue and all its children
    /// - Parameter event: The event to enqueue
    public func enqueueEvent(_ event: Event) async {
        guard !isClosed else {
            // Queue is closed, ignore event
            return
        }
        
        // Add to local events if there's room
        if events.count < maxQueueSize {
            events.append(event)
        }

        // Send to stream continuation
        continuation?.yield(event)
        
        // Forward to all children
        for child in children {
            await child.enqueueEvent(event)
        }
    }
    
    /// Dequeue an event from the queue
    /// - Parameter noWait: If true, return immediately or nil if empty
    /// - Returns: The next event, or nil if empty and noWait is true
    public func dequeueEvent(noWait: Bool = false) async -> Event? {
        if isClosed && events.isEmpty {
            return nil
        }
        
        if noWait {
            return events.isEmpty ? nil : events.removeFirst()
        }
        
        // Wait for event from stream
        guard let stream = stream else {
            return nil
        }
        
        // If we have buffered events, return one
        if !events.isEmpty {
            return events.removeFirst()
        }
        
        // Otherwise wait for next event from stream
        for await event in stream {
            return event
        }
        
        return nil
    }
    
    /// Tap the event queue to create a new child queue that receives all future events
    /// - Returns: A new EventQueue instance that will receive all events enqueued to this parent queue
    public func tap() -> EventQueue {
        let child = EventQueue(maxQueueSize: maxQueueSize)
        children.append(child)
        return child
    }
    
    /// Close the queue for future push events and also close all child queues
    /// - Parameter immediate: If true, immediately closes and clears events. If false, waits for queue to drain.
    public func close(immediate: Bool = false) async {
        guard !isClosed || immediate else {
            return
        }

        isClosed = true
        
        if immediate {
            events.removeAll()
            continuation?.finish()
            continuation = nil
            stream = nil
        } else {
            // Wait for events to be consumed
            // In Swift, we can't easily wait for AsyncStream to drain,
            // so we'll just mark as closed and let consumers finish
            continuation?.finish()
            continuation = nil
        }
        
        // Close all children
        for child in children {
            await child.close(immediate: immediate)
        }
    }
    
    /// Check if the queue is closed
    public func isQueueClosed() -> Bool {
        isClosed
    }
    
    /// Clear all events from the current queue and optionally all child queues
    /// - Parameter clearChildQueues: If true, clear all child queues as well
    public func clearEvents(clearChildQueues: Bool = true) async {
        events.removeAll()
        
        if clearChildQueues {
            for child in children {
                await child.clearEvents(clearChildQueues: true)
            }
        }
    }
    
    /// Get an AsyncStream for consuming events
    /// - Returns: An AsyncStream of events
    public func eventStream() -> AsyncStream<Event> {
        guard let stream = stream else {
            // Return an empty stream if closed
            return AsyncStream { continuation in
                continuation.finish()
            }
        }
        return stream
    }
}
