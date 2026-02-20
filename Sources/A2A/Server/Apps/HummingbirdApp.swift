import Foundation
import Hummingbird
import HTTPTypes
import NIOCore
import SSEKit
import JSONRPC
import AnyCodable

/// Creates a JSONEncoder configured per A2A spec Section 5.6.1 (ISO 8601 timestamps)
/// Note: Do NOT use .convertToSnakeCase - A2A spec requires camelCase field names
/// The CodingKeys in our types already handle the correct naming
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

/// A2A Hummingbird Application that wraps Hummingbird server
/// and adds A2A-specific routes for JSON-RPC endpoints and SSE streaming.
public struct A2AHummingbirdApplication {
    private let agentCard: AgentCard
    private let jsonrpcHandler: JSONRPCHandler
    private let requestHandler: RequestHandler
    private let hostname: String
    private let port: Int
    
    public init(
        agentCard: AgentCard,
        requestHandler: RequestHandler,
        hostname: String = "127.0.0.1",
        port: Int = 8080
    ) {
        self.agentCard = agentCard
        self.requestHandler = requestHandler
        self.jsonrpcHandler = JSONRPCHandler(
            agentCard: agentCard,
            requestHandler: requestHandler
        )
        self.hostname = hostname
        self.port = port
    }
    
    /// Build and configure the Hummingbird application
    /// - Returns: Configured Hummingbird application
    public func build() -> some ApplicationProtocol {
        let router = Router()
        
        // Capture references for closures
        let agentCard = self.agentCard
        let jsonrpcHandler = self.jsonrpcHandler
        let requestHandler = self.requestHandler
        
        // Agent card endpoint
        router.get("/.well-known/agent.json") { request, context -> Response in
            let encoder = makeA2AEncoder()
            let data = try encoder.encode(agentCard)
            let allocator = ByteBufferAllocator()
            var buffer = allocator.buffer(capacity: data.count)
            buffer.writeBytes(data)
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: buffer)
            )
        }
        
        // JSON-RPC endpoint
        router.post("/") { request, context -> Response in
            let allocator = ByteBufferAllocator()
            // Collect request body
            let bodyData = try await collectRequestBody(request, allocator: allocator)
            
            guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                  let method = json["method"] as? String else {
                return badRequestResponse("Invalid JSON-RPC request", allocator: allocator)
            }
            
            // Handle streaming requests with SSE response
            // A2A Inspector sends message/send but expects SSE response when streaming is enabled
            let isStreamingMethod = method == "message.stream" || method == "message/stream" || 
                                    method == "message.send" || method == "message/send"
            if isStreamingMethod {
                // Support both formats:
                // 1. JSON-RPC style: { "params": { "message": {...} } }
                // 2. A2A Inspector style: { "message": {...} }
                let params = json["params"] as? [String: Any]
                let messageDict: [String: Any]
                if let paramsMsg = params?["message"] as? [String: Any] {
                    messageDict = paramsMsg
                } else if let msg = json["message"] as? [String: Any] {
                    messageDict = msg
                } else {
                    return badRequestResponse("Invalid request: missing message", allocator: allocator)
                }
                
                // Parse message
                let message: Message
                do {
                    message = try parseMessage(from: messageDict)
                } catch {
                    return badRequestResponse("Invalid message format: \(error)", allocator: allocator)
                }
                
                // Extract task_id and context_id from params or top level
                let taskID = (params?["task_id"] as? String) ?? 
                             (params?["taskId"] as? String) ?? 
                             (json["task_id"] as? String) ?? 
                             (json["taskId"] as? String)
                let contextID = (params?["context_id"] as? String) ?? 
                                (params?["contextId"] as? String) ?? 
                                (json["context_id"] as? String) ?? 
                                (json["contextId"] as? String)
                
                let tenant: String? = request.uri.queryParameters["tenant"].map { String($0) }
                let serverContext = ServerCallContext(tenant: tenant)
                
                // Get the JSON-RPC request ID for wrapping SSE events
                let requestId = parseJSONRPCId(json["id"]) ?? .stringId(UUID().uuidString)
                
                // Get event stream from request handler
                let eventStream = requestHandler.onMessageSendStream(
                    message: message,
                    taskID: taskID,
                    contextID: contextID,
                    context: serverContext
                )
                
                var headers = HTTPFields()
                headers[.contentType] = "text/event-stream"
                headers[.cacheControl] = "no-cache"
                headers[.connection] = "keep-alive"
                
                return Response(
                    status: .ok,
                    headers: headers,
                    body: .init { writer in
                        do {
                            for try await event in eventStream {
                                // Wrap in JSON-RPC response format per spec Section 9.4.2
                                let sseEvent = ServerSentEvent(data: encodeEventToJSONRPCSSE(event, requestId: requestId))
                                let buffer = sseEvent.makeBuffer(allocator: allocator)
                                try await writer.write(buffer)
                            }
                        } catch {
                            // Stream ended with error, finish gracefully
                        }
                        try await writer.finish(nil)
                    }
                )
            }
            
            // Create JSON-RPC request for non-streaming methods
            // Use a default ID if none provided (for notifications)
            let requestId = parseJSONRPCId(json["id"]) ?? .stringId(UUID().uuidString)
            let jsonrpcRequest = JSONRPCRequest<AnyCodable>(
                id: requestId,
                method: method,
                params: parseParams(json["params"])
            )
            
            // Get server call context
            let tenant: String? = request.uri.queryParameters["tenant"].map { String($0) }
            let serverContext = ServerCallContext(tenant: tenant)
            
            // Handle request
            do {
                let response = try await jsonrpcHandler.handleRequest(jsonrpcRequest, context: serverContext)
                return try jsonResponse(response, status: .ok, allocator: allocator)
            } catch {
                let errorResponse = JSONRPCErrorResponse(
                    id: jsonrpcRequest.id,
                    code: -32603,
                    message: error.localizedDescription
                )
                return try jsonResponse(errorResponse, status: .internalServerError, allocator: allocator)
            }
        }
        
        // SSE streaming endpoint
        router.post("/message:stream") { request, context -> Response in
            let allocator = ByteBufferAllocator()
            // Collect request body
            let bodyData = try await collectRequestBody(request, allocator: allocator)
            
            guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                  let params = json["params"] as? [String: Any],
                  let messageDict = params["message"] as? [String: Any] else {
                return badRequestResponse("Invalid request", allocator: allocator)
            }
            
            // Parse message
            let message: Message
            do {
                message = try parseMessage(from: messageDict)
            } catch {
                return badRequestResponse("Invalid message format", allocator: allocator)
            }
            
            let taskID = params["task_id"] as? String
            let contextID = params["context_id"] as? String
            
            let tenant: String? = request.uri.queryParameters["tenant"].map { String($0) }
            let serverContext = ServerCallContext(tenant: tenant)
            
            // Get event stream from request handler
            let eventStream = requestHandler.onMessageSendStream(
                message: message,
                taskID: taskID,
                contextID: contextID,
                context: serverContext
            )
            
            var sseHeaders = HTTPFields()
            sseHeaders[.contentType] = "text/event-stream"
            sseHeaders[.cacheControl] = "no-cache"
            sseHeaders[.connection] = "keep-alive"
            
            return Response(
                status: .ok,
                headers: sseHeaders,
                body: .init { writer in
                    do {
                        for try await event in eventStream {
                            let sseEvent = ServerSentEvent(data: encodeEventToSSEValue(event))
                            let buffer = sseEvent.makeBuffer(allocator: allocator)
                            try await writer.write(buffer)
                        }
                    } catch {
                        // Stream ended with error, finish gracefully
                    }
                    try await writer.finish(nil)
                }
            )
        }
        
        return Application(
            router: router,
            configuration: .init(address: .hostname(hostname, port: port))
        )
    }
}

// MARK: - Helper Functions

private func collectRequestBody(_ request: Request, allocator: ByteBufferAllocator) async throws -> Data {
    var data = Data()
    for try await buffer in request.body {
        var mutableBuffer = buffer
        if let bytes = mutableBuffer.readBytes(length: mutableBuffer.readableBytes) {
            data.append(contentsOf: bytes)
        }
    }
    return data
}

private func badRequestResponse(_ message: String, allocator: ByteBufferAllocator) -> Response {
    var buffer = allocator.buffer(capacity: message.utf8.count)
    buffer.writeString(message)
    return Response(
        status: .badRequest,
        headers: [.contentType: "text/event-stream"],
        body: .init(byteBuffer: buffer)
    )
}

private func jsonResponse<T: Encodable>(_ value: T, status: HTTPResponse.Status, allocator: ByteBufferAllocator) throws -> Response {
    let encoder = makeA2AEncoder()
    let data = try encoder.encode(value)
    var buffer = allocator.buffer(capacity: data.count)
    buffer.writeBytes(data)
    return Response(
        status: status,
        // headers: [.contentType: "application/json"],
        headers: [.contentType: "text/event-stream"],
        body: .init(byteBuffer: buffer)
    )
}

private func parseJSONRPCId(_ value: Any?) -> JSONId? {
    if let intId = value as? Int {
        return .numericId(intId)
    } else if let stringId = value as? String {
        return .stringId(stringId)
    }
    return nil
}

private func parseParams(_ params: Any?) -> AnyCodable? {
    return params.map { AnyCodable($0) }
}

private func parseMessage(from dict: [String: Any]) throws -> Message {
    // Support both snake_case and camelCase field names
    let messageID = (dict["message_id"] as? String) ?? (dict["messageId"] as? String)
    guard let messageID = messageID else {
        throw InvalidParamsError(message: "Invalid message format: missing message_id/messageId")
    }
    
    guard let roleString = dict["role"] as? String else {
        throw InvalidParamsError(message: "Invalid message format: missing role")
    }
    
    // Support both "ROLE_USER" format and lowercase "user" format
    let role: Role
    if let r = Role(rawValue: roleString) {
        role = r
    } else if roleString.lowercased() == "user" {
        role = .user
    } else if roleString.lowercased() == "agent" {
        role = .agent
    } else {
        throw InvalidParamsError(message: "Invalid message format: invalid role '\(roleString)'")
    }
    
    guard let partsArray = dict["parts"] as? [[String: Any]] else {
        throw InvalidParamsError(message: "Invalid message format: missing parts")
    }
    
    let parts = try partsArray.map { try parsePart(from: $0) }
    
    return Message(
        messageID: messageID,
        contextID: (dict["context_id"] as? String) ?? (dict["contextId"] as? String),
        taskID: (dict["task_id"] as? String) ?? (dict["taskId"] as? String),
        role: role,
        parts: parts,
        metadata: dict["metadata"] as? [String: Any],
        extensions: dict["extensions"] as? [String],
        referenceTaskIDs: (dict["reference_task_ids"] as? [String]) ?? (dict["referenceTaskIds"] as? [String])
    )
}

private func parsePart(from dict: [String: Any]) throws -> Part {
    if let text = dict["text"] as? String {
        return .text(text)
    } else if let fileDict = dict["file"] as? [String: Any] {
        let filePart = try parseFilePart(from: fileDict)
        return .file(filePart)
    } else if let dataDict = dict["data"] as? [String: Any] {
        let dataPart = DataPart(data: dataDict)
        return .data(dataPart)
    } else {
        throw InvalidParamsError(message: "Invalid part format")
    }
}

private func parseFilePart(from dict: [String: Any]) throws -> FilePart {
    if let uri = dict["file_with_uri"] as? String {
        return FilePart(
            content: .uri(uri),
            mediaType: dict["media_type"] as? String,
            name: dict["name"] as? String
        )
    } else if let bytesString = dict["file_with_bytes"] as? String,
              let bytes = Data(base64Encoded: bytesString) {
        return FilePart(
            content: .bytes(bytes),
            mediaType: dict["media_type"] as? String,
            name: dict["name"] as? String
        )
    } else {
        throw InvalidParamsError(message: "Invalid file part format")
    }
}

/// Wraps an event in the A2A StreamResponse format per spec Section 3.2.3
/// The wrapper uses the appropriate key: "task", "message", "statusUpdate", or "artifactUpdate"
private func encodeEventToSSEValue(_ event: Event) -> SSEValue {
    let encoder = makeA2AEncoder()
    do {
        // Create the wrapper dictionary with the appropriate key per A2A spec
        let wrapperKey: String
        let innerData: Data
        
        switch event {
        case .message(let message):
            wrapperKey = "message"
            innerData = try encoder.encode(message)
        case .task(let task):
            wrapperKey = "task"
            innerData = try encoder.encode(task)
        case .taskStatusUpdate(let update):
            wrapperKey = "statusUpdate"
            innerData = try encoder.encode(update)
        case .taskArtifactUpdate(let update):
            wrapperKey = "artifactUpdate"
            innerData = try encoder.encode(update)
        }
        
        // Wrap in StreamResponse format: {"task": {...}} or {"statusUpdate": {...}} etc.
        if let innerJson = try JSONSerialization.jsonObject(with: innerData) as? [String: Any] {
            let wrapper: [String: Any] = [wrapperKey: innerJson]
            let wrapperData = try JSONSerialization.data(withJSONObject: wrapper)
            if let jsonString = String(data: wrapperData, encoding: .utf8) {
                return .init(string: jsonString)
            }
        }
    } catch {
        // Fallback to empty JSON
    }
    return .init(string: "{}")
}

/// Wraps an event in JSON-RPC response format for SSE streaming
/// The Python SDK expects result to be the DIRECT object (Task/Message/Event),
/// not wrapped in a discriminator key like {"task": {...}}
/// Format: {"jsonrpc": "2.0", "id": <requestId>, "result": <Task|Message|Event>}
private func encodeEventToJSONRPCSSE(_ event: Event, requestId: JSONId) -> SSEValue {
    let encoder = makeA2AEncoder()
    do {
        let innerData: Data
        
        switch event {
        case .message(let message):
            innerData = try encoder.encode(message)
        case .task(let task):
            innerData = try encoder.encode(task)
        case .taskStatusUpdate(let update):
            innerData = try encoder.encode(update)
        case .taskArtifactUpdate(let update):
            innerData = try encoder.encode(update)
        }
        
        // Result is the DIRECT object, not wrapped in a discriminator key
        if let resultJson = try JSONSerialization.jsonObject(with: innerData) as? [String: Any] {
            // Wrap in JSON-RPC response format
            var jsonRpcResponse: [String: Any] = [
                "jsonrpc": "2.0",
                "result": resultJson  // Direct object, not {"task": resultJson}
            ]
            
            // Add the request ID
            switch requestId {
            case .stringId(let strId):
                jsonRpcResponse["id"] = strId
            case .numericId(let numId):
                jsonRpcResponse["id"] = numId
            }
            
            let responseData = try JSONSerialization.data(withJSONObject: jsonRpcResponse)
            if let jsonString = String(data: responseData, encoding: .utf8) {
                return .init(string: jsonString)
            }
        }
    } catch {
        // Fallback to empty JSON-RPC error
    }
    return .init(string: "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32603,\"message\":\"Internal error encoding event\"}}")
}

/// Helper struct for JSON-RPC error responses
private struct JSONRPCErrorResponse: Encodable {
    let jsonrpc: String = "2.0"
    let id: JSONId?
    let error: ErrorDetail
    
    struct ErrorDetail: Encodable {
        let code: Int
        let message: String
    }
    
    init(id: JSONId?, code: Int, message: String) {
        self.id = id
        self.error = ErrorDetail(code: code, message: message)
    }
}
