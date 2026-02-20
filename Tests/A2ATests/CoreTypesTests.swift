import Testing
@testable import A2A

@Suite("Core Types Tests")
struct CoreTypesTests {
    @Test("Task state terminal checks")
    func testTaskStateIsTerminal() {
        #expect(TaskState.completed.isTerminal)
        #expect(TaskState.failed.isTerminal)
        #expect(TaskState.cancelled.isTerminal)
        #expect(TaskState.rejected.isTerminal)
        #expect(!TaskState.working.isTerminal)
        #expect(!TaskState.submitted.isTerminal)
    }
    
    @Test("Message creation")
    func testMessageCreation() {
        let message = Message(
            messageID: "msg-1",
            contextID: "ctx-1",
            taskID: "task-1",
            role: .user,
            parts: [.text("Hello")]
        )
        
        #expect(message.messageID == "msg-1")
        #expect(message.contextID == "ctx-1")
        #expect(message.taskID == "task-1")
        #expect(message.role == .user)
        #expect(message.parts.count == 1)
    }
    
    @Test("Task creation")
    func testTaskCreation() {
        let task = Task(
            id: "task-1",
            contextID: "ctx-1",
            status: TaskStatus(state: .working),
            artifacts: [],
            history: []
        )
        
        #expect(task.id == "task-1")
        #expect(task.contextID == "ctx-1")
        #expect(task.status.state == .working)
    }
    
    @Test("Agent card creation")
    func testAgentCardCreation() {
        let interface = AgentInterface(
            url: "https://example.com",
            transport: .jsonrpc
        )
        let card = AgentCard(
            name: "Test Agent",
            url: "https://example.com",
            description: "A test agent",
            supportedInterfaces: [interface],
            version: "1.0.0",
            capabilities: AgentCapabilities(streaming: true),
            defaultInputModes: ["text/plain"],
            defaultOutputModes: ["text/plain"],
            skills: []
        )
        
        #expect(card.name == "Test Agent")
        #expect(card.url == "https://example.com")
        #expect(card.preferredTransport == TransportProtocol.jsonrpc)
    }
}

