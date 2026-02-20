import Testing
@testable import A2A

@Suite("Task Manager Tests")
struct TaskManagerTests {
    @Test("Task manager initialization")
    func testTaskManagerInitialization() async throws {
        let taskStore = InMemoryTaskStore()
        let taskManager = TaskManager(
            taskStore: taskStore,
            initialMessage: nil
        )
        
        let task = try await taskManager.getTask()
        #expect(task == nil) // No task ID set initially
    }
    
    @Test("Task manager save task")
    func testTaskManagerSaveTask() async throws {
        let taskStore = InMemoryTaskStore()
        let taskManager = TaskManager(
            taskID: "task-1",
            contextID: "ctx-1",
            taskStore: taskStore
        )
        
        let task = Task(
            id: "task-1",
            contextID: "ctx-1",
            status: TaskStatus(state: .working),
            artifacts: [],
            history: []
        )
        
        _ = try await taskManager.saveTaskEvent(.task(task))
        
        let retrieved = try await taskManager.getTask()
        #expect(retrieved != nil)
        #expect(retrieved?.id == "task-1")
    }
}

