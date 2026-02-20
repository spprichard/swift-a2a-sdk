import JSONRPC
import AnyCodable
import Foundation

/// Creates a JSONEncoder configured per A2A spec Section 5.6.1 (ISO 8601 timestamps)
private func makeA2AEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}

/// JSONRPCHandler maps incoming JSON-RPC requests to the appropriate request handler method
/// and formats responses according to JSON-RPC 2.0 specification.
public final class JSONRPCHandler: Sendable {
    private let agentCard: AgentCard
    private let requestHandler: RequestHandler
    
    public init(agentCard: AgentCard, requestHandler: RequestHandler) {
        self.agentCard = agentCard
        self.requestHandler = requestHandler
    }
    
    /// Handle a JSON-RPC request
    /// - Parameters:
    ///   - request: The JSON-RPC request
    ///   - context: Optional server call context
    /// - Returns: A JSON-RPC response
    public func handleRequest(
        _ request: JSONRPCRequest<AnyCodable>,
        context: ServerCallContext? = nil
    ) async throws -> JSONRPCResponse<AnyCodable> {
        let method = request.method
        let params = request.params
        
        switch method {
        case "message.send":
            return try await handleMessageSend(request: request, params: params, context: context)
            
        case "message.stream":
            // Streaming is handled separately via SSE
            throw UnsupportedOperationError(message: "Use SSE endpoint for streaming")
            
        case "tasks.get":
            return try await handleGetTask(request: request, params: params, context: context)
            
        default:
            throw InvalidParamsError(message: "Unknown method: \(method)")
        }
    }
    
    private func handleMessageSend(
        request: JSONRPCRequest<AnyCodable>,
        params: AnyCodable?,
        context: ServerCallContext?
    ) async throws -> JSONRPCResponse<AnyCodable> {
        // Parse message from params
        guard let paramsDict = params?.value as? [String: Any],
              let messageDict = paramsDict["message"] as? [String: Any],
              let message = try? parseMessage(from: messageDict) else {
            throw InvalidParamsError(message: "Invalid message parameter")
        }
        
        let taskID = paramsDict["task_id"] as? String
        let contextID = paramsDict["context_id"] as? String
        
        do {
            let result = try await requestHandler.onMessageSend(
                message: message,
                taskID: taskID,
                contextID: contextID,
                context: context
            )
            
            let resultValue: [String: AnyCodable]
            switch result {
            case .task(let task):
                resultValue = try encodeTaskToAnyCodable(task)
            case .message(let message):
                resultValue = try encodeMessageToAnyCodable(message)
            }
            
            return JSONRPCResponse<AnyCodable>(
                id: request.id,
                result: AnyCodable(resultValue)
            )
        } catch let error as A2AError {
            let responseError = JSONRPCResponseError<JSONValue>(
                code: error.code,
                message: error.message,
                data: error.data.map { convertToJSONValue($0) }
            )
            return JSONRPCResponse<AnyCodable>(
                id: request.id,
                content: .failure(responseError)
            )
        }
    }
    
    private func handleGetTask(
        request: JSONRPCRequest<AnyCodable>,
        params: AnyCodable?,
        context: ServerCallContext?
    ) async throws -> JSONRPCResponse<AnyCodable> {
        guard let paramsDict = params?.value as? [String: Any],
              let taskID = paramsDict["id"] as? String else {
            throw InvalidParamsError(message: "Missing task id parameter")
        }
        
        do {
            if let task = try await requestHandler.onGetTask(taskID: taskID, context: context) {
                return JSONRPCResponse<AnyCodable>(
                    id: request.id,
                    result: AnyCodable(try encodeTaskToAnyCodable(task))
                )
            } else {
                throw TaskNotFoundError()
            }
        } catch let error as A2AError {
            let responseError = JSONRPCResponseError<JSONValue>(
                code: error.code,
                message: error.message,
                data: error.data.map { convertToJSONValue($0) }
            )
            return JSONRPCResponse<AnyCodable>(
                id: request.id,
                content: .failure(responseError)
            )
        }
    }
    
    // Helper methods for encoding/decoding
    private func parseMessage(from dict: [String: Any]) throws -> Message {
        // Simplified parsing - in production would use proper Codable
        guard let messageID = dict["message_id"] as? String,
              let roleString = dict["role"] as? String,
              let role = Role(rawValue: roleString),
              let partsArray = dict["parts"] as? [[String: Any]] else {
            throw InvalidParamsError(message: "Invalid message format")
        }
        
        let parts = try partsArray.map { try parsePart(from: $0) }
        
        return Message(
            messageID: messageID,
            contextID: dict["context_id"] as? String,
            taskID: dict["task_id"] as? String,
            role: role,
            parts: parts,
            metadata: dict["metadata"] as? [String: Any],
            extensions: dict["extensions"] as? [String],
            referenceTaskIDs: dict["reference_task_ids"] as? [String]
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
            return FilePart(content: .uri(uri), mediaType: dict["media_type"] as? String, name: dict["name"] as? String)
        } else if let bytesString = dict["file_with_bytes"] as? String,
                  let bytes = Data(base64Encoded: bytesString) {
            return FilePart(content: .bytes(bytes), mediaType: dict["media_type"] as? String, name: dict["name"] as? String)
        } else {
            throw InvalidParamsError(message: "Invalid file part format")
        }
    }
    
    private func encodeTaskToAnyCodable(_ task: Task) throws -> [String: AnyCodable] {
        let encoder = makeA2AEncoder()
        let data = try encoder.encode(task)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json.mapValues { AnyCodable($0) }
    }
    
    private func encodeMessageToAnyCodable(_ message: Message) throws -> [String: AnyCodable] {
        let encoder = makeA2AEncoder()
        let data = try encoder.encode(message)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json.mapValues { AnyCodable($0) }
    }
    
    // Helper function to convert AnyCodable to JSONValue
    private func convertToJSONValue(_ value: AnyCodable) -> JSONValue {
        let anyValue = value.value
        
        if anyValue is NSNull {
            return .null
        } else if let bool = anyValue as? Bool {
            return .bool(bool)
        } else if let number = anyValue as? Double {
            return .number(number)
        } else if let number = anyValue as? Int {
            return .number(Double(number))
        } else if let string = anyValue as? String {
            return .string(string)
        } else if let array = anyValue as? [Any] {
            return .array(array.map { convertToJSONValue(AnyCodable($0)) })
        } else if let dict = anyValue as? [String: Any] {
            return .hash(dict.mapValues { convertToJSONValue(AnyCodable($0)) })
        } else {
            return .null
        }
    }
}

