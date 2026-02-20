import Foundation

/// Default request handler for all incoming requests.
/// This handler provides default implementations for all A2A JSON-RPC methods,
/// coordinating between the AgentExecutor, TaskStore, and EventQueue.
public final class DefaultRequestHandler: RequestHandler, @unchecked Sendable {
    private let agentExecutor: AgentExecutor
    private let taskStore: TaskStore
    private let idGenerator: IDGenerator
    
    public init(
        agentExecutor: AgentExecutor,
        taskStore: TaskStore,
        idGenerator: IDGenerator = UUIDGenerator()
    ) {
        self.agentExecutor = agentExecutor
        self.taskStore = taskStore
        self.idGenerator = idGenerator
    }
    
    public func onGetTask(taskID: String, context: ServerCallContext?) async throws -> Task? {
        return try await taskStore.get(taskID: taskID, context: context)
    }
    
    public func onMessageSend(
        message: Message,
        taskID: String?,
        contextID: String?,
        context: ServerCallContext?
    ) async throws -> TaskOrMessage {
        // Create or get task
        let taskManager = TaskManager(
            taskID: taskID,
            contextID: contextID ?? message.contextID,
            taskStore: taskStore,
            initialMessage: message,
            context: context
        )
        
        // Check if task exists and is in terminal state
        if let existingTask = try await taskManager.getTask() {
            if existingTask.status.state.isTerminal {
                throw InvalidParamsError(
                    message: "Task \(existingTask.id) is in terminal state: \(existingTask.status.state)"
                )
            }
        } else if taskID != nil {
            throw TaskNotFoundError(message: "Task \(taskID!) was specified but does not exist")
        }
        
        // Create event queue
        let eventQueue = EventQueue()
        
        // Build request context
        let requestContext = RequestContext(
            message: message,
            taskID: taskID ?? message.taskID ?? idGenerator.generate(),
            contextID: contextID ?? message.contextID ?? idGenerator.generate(),
            callContext: context
        )
        
        // Execute agent
        try await agentExecutor.execute(context: requestContext, eventQueue: eventQueue)
        
        // Consume events and get final result
        var finalResult: TaskOrMessage?
        var finalTask: Task?
        
        let eventStream = await eventQueue.eventStream()
        for await event in eventStream {
            switch event {
            case .message(let msg):
                finalResult = .message(msg)
                break
            case .task(let task):
                finalTask = task
                _ = try await taskManager.process(event)
            case .taskStatusUpdate(let update):
                _ = try await taskManager.process(event)
                if update.isFinal {
                    finalTask = try await taskManager.getTask()
                }
            case .taskArtifactUpdate:
                _ = try await taskManager.process(event)
            }
            
            if finalResult != nil {
                break
            }
        }
        
        // Close queue
        await eventQueue.close()
        
        // Return final result
        if let result = finalResult {
            return result
        }
        
        // Get final task if not already set
        let task: Task
        if let finalTask = finalTask {
            task = finalTask
        } else {
            guard let fetchedTask = try await taskManager.getTask() else {
                throw InternalError(message: "Agent did not return a valid response")
            }
            task = fetchedTask
        }
        return .task(task)
    }
    
    public func onMessageSendStream(
        message: Message,
        taskID: String?,
        contextID: String?,
        context: ServerCallContext?
    ) -> AsyncThrowingStream<Event, Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: Event.self)
        
        // Capture properties explicitly to avoid capturing 'self'
        let taskStore = self.taskStore
        let idGenerator = self.idGenerator
        let agentExecutor = self.agentExecutor
        
        _Concurrency.Task { @Sendable in
            do {
                // Generate IDs for this request
                let resolvedTaskID = taskID ?? message.taskID ?? idGenerator.generate()
                let resolvedContextID = contextID ?? message.contextID ?? idGenerator.generate()
                
                // Create or get task
                let taskManager = TaskManager(
                    taskID: resolvedTaskID,
                    contextID: resolvedContextID,
                    taskStore: taskStore,
                    initialMessage: message,
                    context: context
                )
                
                // Check if task exists and is in terminal state
                if let existingTask = try await taskManager.getTask() {
                    if existingTask.status.state.isTerminal {
                        continuation.finish(throwing: InvalidParamsError(
                            message: "Task \(existingTask.id) is in terminal state: \(existingTask.status.state)"
                        ))
                        return
                    }
                } else if taskID != nil {
                    continuation.finish(throwing: TaskNotFoundError(
                        message: "Task \(taskID!) was specified but does not exist"
                    ))
                    return
                }
                
                // Create event queue
                let eventQueue = EventQueue()
                
                // Build request context
                let requestContext = RequestContext(
                    message: message,
                    taskID: resolvedTaskID,
                    contextID: resolvedContextID,
                    callContext: context
                )
                
                // Per A2A spec Section 3.1.2: stream MUST begin with a Task object
                // Create an initial task with "submitted" state
                let initialTask = Task(
                    id: resolvedTaskID,
                    contextID: resolvedContextID,
                    status: TaskStatus(
                        state: .submitted,
                        message: nil,
                        timestamp: Date()
                    ),
                    artifacts: [],
                    history: [message]
                )
                
                // Save initial task and yield it as the first event
                try await taskStore.save(initialTask, context: context)
                continuation.yield(.task(initialTask))
                
                // Start agent execution in background
                let agentTask = _Concurrency.Task { @Sendable in
                    do {
                        try await agentExecutor.execute(context: requestContext, eventQueue: eventQueue)
                        await eventQueue.close()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                
                // Stream events from queue
                let eventStream = await eventQueue.eventStream()
                for await event in eventStream {
                    continuation.yield(event)
                    
                    // Process event through task manager
                    _ = try? await taskManager.process(event)
                    
                    // Check if this is a final event
                    if case .taskStatusUpdate(let update) = event, update.isFinal {
                        break
                    }
                }

                continuation.finish()
                await agentTask.value
            } catch {
                continuation.finish(throwing: error)
            }
        }
        
        return stream
    }

}
