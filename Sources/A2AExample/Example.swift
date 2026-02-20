// A2A Swift SDK Example
//
// This example demonstrates how to create a simple A2A agent server
// and a client that communicates with it.

import A2A
import Foundation
import Hummingbird

// MARK: - Simple Echo Agent Executor

/// A simple agent executor that echoes back messages with some processing.
final class EchoAgentExecutor: AgentExecutor, @unchecked Sendable {
    
    func execute(context: A2A.RequestContext, eventQueue: EventQueue) async throws {
        let message = context.message
        let taskID = context.taskID ?? UUID().uuidString
        let contextID = context.contextID ?? UUID().uuidString
        
        print("📨 Received message: \(message.messageID)")
        
        // First, send a status update that we're working
        let workingStatus = TaskStatus(
            state: .working,
            message: nil,
            timestamp: Date()
        )
        let workingEvent = TaskStatusUpdateEvent(
            taskID: taskID,
            contextID: contextID,
            status: workingStatus,
            isFinal: false
        )
        await eventQueue.enqueueEvent(.taskStatusUpdate(workingEvent))
        
        // Simulate some processing time
        try await _Concurrency.Task.sleep(for: .milliseconds(500))
        
        // Extract text from the input message
        let inputText = message.parts.compactMap { part -> String? in
            if case .text(let text) = part {
                return text
            }
            return nil
        }.joined(separator: " ")
        
        print("📝 Input text: \(inputText)")
        
        // Create a response message to include in the completed status
        // Note: Messages are NOT sent as separate stream events after the initial Task.
        // They should be included in TaskStatus.message or TaskArtifactUpdateEvent.
        let responseMessage = Message(
            messageID: UUID().uuidString,
            contextID: contextID,
            taskID: taskID,
            role: .agent,
            parts: [.text("🤖 Echo Agent received: \"\(inputText)\"")]
        )
        
        // Send final status update with the response message
        let completedStatus = TaskStatus(
            state: .completed,
            message: responseMessage,
            timestamp: Date()
        )
        let completedEvent = TaskStatusUpdateEvent(
            taskID: taskID,
            contextID: contextID,
            status: completedStatus,
            isFinal: true
        )
        await eventQueue.enqueueEvent(.taskStatusUpdate(completedEvent))
        
        print("✅ Task completed: \(taskID)")
    }
    
    func cancel(context: A2A.RequestContext, eventQueue: EventQueue) async throws {
        let taskID = context.taskID ?? "unknown"
        let contextID = context.contextID ?? UUID().uuidString
        
        print("📛 Cancel requested for task: \(taskID)")
        
        // Send cancelled status
        let cancelledStatus = TaskStatus(
            state: .cancelled,
            message: nil,
            timestamp: Date()
        )
        let cancelledEvent = TaskStatusUpdateEvent(
            taskID: taskID,
            contextID: contextID,
            status: cancelledStatus,
            isFinal: true
        )
        await eventQueue.enqueueEvent(.taskStatusUpdate(cancelledEvent))
    }
}

// MARK: - Main Entry Point

@main
struct A2AExampleApp {
    static func main() async throws {
        print("🚀 A2A Swift SDK Example")
        print("========================\n")
        
        let baseURL = "http://localhost:8090"
        
        // Create the agent card that describes this agent
        let agentCard = AgentCard(
            name: "Echo Agent",
            url: baseURL,
            description: "A simple agent that echoes back messages",
            version: "1.0.0",
            capabilities: AgentCapabilities(
                streaming: true,
                pushNotifications: false,
                stateTransitionHistory: true
            ),
            defaultInputModes: ["text"],
            defaultOutputModes: ["text"],
            skills: [
                AgentSkill(
                    id: "echo",
                    name: "Echo",
                    description: "Echoes back any message sent to it",
                    tags: ["echo", "test", "demo"]
                )
            ]
        )
        
        print("📋 Agent Card:")
        print("   Name: \(agentCard.name)")
        print("   URL: \(agentCard.url)")
        print("   Description: \(agentCard.description)")
        print("   Version: \(agentCard.version)")
        print("   Skills: \(agentCard.skills.map { $0.name }.joined(separator: ", "))")
        print()
        
        // Create the agent components
        let agentExecutor = EchoAgentExecutor()
        let taskStore = InMemoryTaskStore()
        let requestHandler = DefaultRequestHandler(
            agentExecutor: agentExecutor,
            taskStore: taskStore
        )
        
        // Create the Hummingbird application
        let a2aApp = A2AHummingbirdApplication(
            agentCard: agentCard,
            requestHandler: requestHandler,
            port: 8090
        )
        
        let app = a2aApp.build()
        
        print("🌐 Starting server on \(baseURL)")
        print("   Agent Card: \(baseURL)/.well-known/agent.json")
        print("   JSON-RPC: POST \(baseURL)/")
        print()
        
        // Start the server
        print("💡 Example requests:")
        print()
        print("1. Get Agent Card:")
        print("   curl \(baseURL)/.well-known/agent.json | jq")
        print()
        print("2. Send a message:")
        print("""
           curl -X POST \(baseURL)/ \\
             -H "Content-Type: application/json" \\
             -d '{
               "jsonrpc": "2.0",
               "id": "1",
               "method": "message.send",
               "params": {
                 "message": {
                   "message_id": "msg-1",
                   "role": "ROLE_USER",
                   "parts": [{"text": "Hello, A2A Agent!"}]
                 }
               }
             }' | jq
        """)
        print()
        print("Press Ctrl+C to stop the server.\n")
        
        // Run the application
        try await app.run()
    }
}
