import Testing
@testable import A2A

@Suite("Event Queue Tests")
struct EventQueueTests {
    @Test("Event queue enqueue and dequeue")
    func testEventQueueEnqueueDequeue() async throws {
        let queue = EventQueue()
        let message = Message(
            messageID: "msg-1",
            role: .user,
            parts: [.text("Hello")]
        )
        
        await queue.enqueueEvent(.message(message))
        
        let dequeued = await queue.dequeueEvent(noWait: true)
        #expect(dequeued != nil)
        
        if let dequeued = dequeued,
           case .message(let dequeuedMessage) = dequeued {
            #expect(dequeuedMessage.messageID == "msg-1")
        } else {
            #expect(Bool(false), "Expected message event, got: \(String(describing: dequeued))")
        }
    }


    @Test("Event queue streaming")
    func testEventQueueStreaming() async {
        let queue = EventQueue()
        let message = Message(
            messageID: "msg-1",
            role: .user,
            parts: [.text("Hello")]
        )
        
        let stream = await queue.eventStream()
        await queue.enqueueEvent(.message(message))
        
        var receivedEvents: [Event] = []
        for await event in stream {
            receivedEvents.append(event)
            if receivedEvents.count >= 1 {
                break
            }
        }
        
        #expect(receivedEvents.count == 1)
    }
    
    @Test("Event queue close")
    func testEventQueueClose() async {
        let queue = EventQueue()
        await queue.close()
        
        let isClosed = await queue.isQueueClosed()
        #expect(isClosed)
    }
}

