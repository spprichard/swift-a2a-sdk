import Foundation
import AsyncHTTPClient
import SSEKit

/// Creates a JSONEncoder configured per A2A spec Section 5.6.1 (ISO 8601 timestamps)
private func makeA2AEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}

/// Creates a JSONDecoder configured per A2A spec Section 5.6.1 (ISO 8601 timestamps)
private func makeA2ADecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

/// JSON-RPC transport implementation using AsyncHTTPClient
public final class JSONRPCTransport: ClientTransport {
    private let httpClient: HTTPClient
    private let url: String
    private let agentCard: AgentCard?
    
    public init(
        httpClient: HTTPClient,
        url: String,
        agentCard: AgentCard? = nil
    ) {
        self.httpClient = httpClient
        self.url = url
        self.agentCard = agentCard
    }
    
    public func sendMessage(
        message: Message,
        taskID: String?,
        contextID: String?
    ) async throws -> TaskOrMessage {
        // Build JSON-RPC request
        let requestID = UUID().uuidString
        var params: [String: Any] = [
            "message": try encodeMessage(message)
        ]
        
        if let taskID = taskID {
            params["task_id"] = taskID
        }
        if let contextID = contextID {
            params["context_id"] = contextID
        }
        
        let jsonrpcRequest: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestID,
            "method": "message.send",
            "params": params
        ]
        
        // Send HTTP request
        let requestBody = try JSONSerialization.data(withJSONObject: jsonrpcRequest)
        var request = try HTTPClient.Request(
            url: url,
            method: .POST,
            headers: ["Content-Type": "application/json"],
            body: .data(requestBody)
        )
        
        let response = try await httpClient.execute(request: request).get()
        
        guard response.status == .ok else {
            throw A2AClientHTTPError(
                Int(response.status.code),
                "HTTP error: \(response.status)"
            )
        }
        
        guard let body = response.body else {
            throw A2AClientJSONError("Empty response body")
        }
        
        // Convert ByteBuffer to Data
        let responseData = body.getData(at: body.readerIndex, length: body.readableBytes) ?? Data()
        
        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw A2AClientJSONError("Failed to parse response")
        }
        
        // Check for JSON-RPC error
        if let error = json["error"] as? [String: Any] {
            let code = error["code"] as? Int ?? -32603
            let message = error["message"] as? String ?? "Unknown error"
            throw A2AClientJSONRPCError(code: code, message: message, data: error["data"])
        }
        
        // Parse result
        guard let result = json["result"] as? [String: Any] else {
            throw A2AClientJSONError("Missing result in response")
        }
        
        // Determine if result is Task or Message
        if result["id"] != nil && result["context_id"] != nil {
            // It's a Task
            let task = try decodeTask(from: result)
            return .task(task)
        } else if result["message_id"] != nil {
            // It's a Message
            let message = try decodeMessage(from: result)
            return .message(message)
        } else {
            throw A2AClientJSONError("Unable to determine result type")
        }
    }
    
    public func sendMessageStreaming(
        message: Message,
        taskID: String?,
        contextID: String?
    ) -> AsyncStream<Event> {
        let (stream, continuation) = AsyncStream.makeStream(of: Event.self)
        
        _Concurrency.Task {
            do {
                // Build JSON-RPC request
                var params: [String: Any] = [
                    "message": try encodeMessage(message)
                ]
                
                if let taskID = taskID {
                    params["task_id"] = taskID
                }
                if let contextID = contextID {
                    params["context_id"] = contextID
                }
                
                let jsonrpcRequest: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": UUID().uuidString,
                    "method": "message.stream",
                    "params": params
                ]
                
                // Send HTTP request with SSE
                let requestBody = try JSONSerialization.data(withJSONObject: jsonrpcRequest)
                var request = try HTTPClient.Request(
                    url: url + "/message:stream",
                    method: .POST,
                    headers: [
                        "Content-Type": "application/json",
                        "Accept": "text/event-stream"
                    ],
                    body: .data(requestBody)
                )
                
                let response = try await httpClient.execute(request: request).get()
                
                guard response.status == .ok else {
                    throw A2AClientHTTPError(
                        Int(response.status.code),
                        "HTTP error: \(response.status)"
                    )
                }
                
                // Parse SSE stream
                guard let body = response.body else {
                    continuation.finish()
                    return
                }
                
                // Read SSE events - convert ByteBuffer to Data
                let bodyData = body.getData(at: body.readerIndex, length: body.readableBytes) ?? Data()
                let bodyString = String(data: bodyData, encoding: .utf8) ?? ""
                
                // Simple SSE parsing (for MVP)
                let lines = bodyString.components(separatedBy: "\n")
                var currentEvent: [String: String] = [:]
                
                for line in lines {
                    if line.isEmpty {
                        // Process event
                        if let data = currentEvent["data"], !data.isEmpty {
                            if let event = try? parseEvent(from: data) {
                                continuation.yield(event)
                            }
                        }
                        currentEvent = [:]
                    } else if line.hasPrefix("data: ") {
                        let data = String(line.dropFirst(6))
                        currentEvent["data"] = (currentEvent["data"] ?? "") + data
                    }
                }
                
                continuation.finish()
            } catch {
                // AsyncStream doesn't support throwing - just finish
                continuation.finish()
            }
        }
        
        return stream
    }
    
    public func getTask(taskID: String) async throws -> Task {
        let requestID = UUID().uuidString
        let jsonrpcRequest: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestID,
            "method": "tasks.get",
            "params": ["id": taskID]
        ]
        
        let requestBody = try JSONSerialization.data(withJSONObject: jsonrpcRequest)
        var request = try HTTPClient.Request(
            url: url,
            method: .POST,
            headers: ["Content-Type": "application/json"],
            body: .data(requestBody)
        )
        
        let response = try await httpClient.execute(request: request).get()
        
        guard response.status == .ok else {
            throw A2AClientHTTPError(
                Int(response.status.code),
                "HTTP error: \(response.status)"
            )
        }
        
        guard let body = response.body else {
            throw A2AClientJSONError("Empty response body")
        }
        
        // Convert ByteBuffer to Data
        let responseData = body.getData(at: body.readerIndex, length: body.readableBytes) ?? Data()
        
        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw A2AClientJSONError("Failed to parse response")
        }
        
        if let error = json["error"] as? [String: Any] {
            let code = error["code"] as? Int ?? -32603
            let message = error["message"] as? String ?? "Unknown error"
            throw A2AClientJSONRPCError(code: code, message: message, data: error["data"])
        }
        
        guard let result = json["result"] as? [String: Any] else {
            throw A2AClientJSONError("Missing result in response")
        }
        
        return try decodeTask(from: result)
    }
    
    public func close() async throws {
        try await httpClient.shutdown()
    }
    
    // Helper methods
    private func encodeMessage(_ message: Message) throws -> [String: Any] {
        let encoder = makeA2AEncoder()
        let data = try encoder.encode(message)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
    
    private func decodeMessage(from dict: [String: Any]) throws -> Message {
        let decoder = makeA2ADecoder()
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try decoder.decode(Message.self, from: data)
    }
    
    private func decodeTask(from dict: [String: Any]) throws -> Task {
        let decoder = makeA2ADecoder()
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try decoder.decode(Task.self, from: data)
    }
    
    private func parseEvent(from jsonString: String) throws -> Event {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw A2AClientJSONError("Invalid event JSON")
        }

        if let result = json["result"] as? [String: Any] {
            return try parseEventObject(from: result)
        }

        if let messageDict = json["message"] as? [String: Any] {
            let message = try decodeMessage(from: messageDict)
            return .message(message)
        }
        if let taskDict = json["task"] as? [String: Any] {
            let task = try decodeTask(from: taskDict)
            return .task(task)
        }
        if let updateDict = json["statusUpdate"] as? [String: Any] {
            let update = try decodeTaskStatusUpdate(from: updateDict)
            return .taskStatusUpdate(update)
        }
        if let updateDict = json["artifactUpdate"] as? [String: Any] {
            let update = try decodeTaskArtifactUpdate(from: updateDict)
            return .taskArtifactUpdate(update)
        }

        return try parseEventObject(from: json)
    }

    private func parseEventObject(from json: [String: Any]) throws -> Event {
        if json["message_id"] != nil {
            let message = try decodeMessage(from: json)
            return .message(message)
        } else if json["id"] != nil && json["context_id"] != nil {
            let task = try decodeTask(from: json)
            return .task(task)
        } else if json["task_id"] != nil && json["status"] != nil {
            let update = try decodeTaskStatusUpdate(from: json)
            return .taskStatusUpdate(update)
        } else if json["task_id"] != nil && json["artifact"] != nil {
            let update = try decodeTaskArtifactUpdate(from: json)
            return .taskArtifactUpdate(update)
        } else {
            throw A2AClientJSONError("Unknown event type")
        }
    }
    
    private func decodeTaskStatusUpdate(from dict: [String: Any]) throws -> TaskStatusUpdateEvent {
        let decoder = makeA2ADecoder()
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try decoder.decode(TaskStatusUpdateEvent.self, from: data)
    }
    
    private func decodeTaskArtifactUpdate(from dict: [String: Any]) throws -> TaskArtifactUpdateEvent {
        let decoder = makeA2ADecoder()
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try decoder.decode(TaskArtifactUpdateEvent.self, from: data)
    }
}
