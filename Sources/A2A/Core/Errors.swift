import Foundation
@preconcurrency import AnyCodable

/// Base protocol for A2A errors
public protocol A2AError: Error {
    var code: Int { get }
    var message: String { get }
    var data: AnyCodable? { get }
}

/// Task not found error
public struct TaskNotFoundError: A2AError, Sendable {
    public let code: Int = -32004
    public let message: String
    public let data: AnyCodable?
    
    public init(message: String = "Task not found", data: Any? = nil) {
        self.message = message
        self.data = data.map { AnyCodable($0) }
    }
}

/// Invalid parameters error
public struct InvalidParamsError: A2AError, Sendable {
    public let code: Int = -32602
    public let message: String
    public let data: AnyCodable?
    
    public init(message: String = "Invalid params", data: Any? = nil) {
        self.message = message
        self.data = data.map { AnyCodable($0) }
    }
}

/// Internal server error
public struct InternalError: A2AError, Sendable {
    public let code: Int = -32603
    public let message: String
    public let data: AnyCodable?
    
    public init(message: String = "Internal error", data: Any? = nil) {
        self.message = message
        self.data = data.map { AnyCodable($0) }
    }
}

/// Content type not supported error
public struct ContentTypeNotSupportedError: A2AError, Sendable {
    public let code: Int = -32001
    public let message: String
    public let data: AnyCodable?
    
    public init(message: String = "Content type not supported", data: Any? = nil) {
        self.message = message
        self.data = data.map { AnyCodable($0) }
    }
}

/// Unsupported operation error
public struct UnsupportedOperationError: A2AError, Sendable {
    public let code: Int = -32002
    public let message: String
    public let data: AnyCodable?
    
    public init(message: String = "Unsupported operation", data: Any? = nil) {
        self.message = message
        self.data = data.map { AnyCodable($0) }
    }
}

/// Client error for invalid state
public struct A2AClientInvalidStateError: Error {
    public let message: String
    
    public init(_ message: String) {
        self.message = message
    }
}

/// Client HTTP error
public struct A2AClientHTTPError: Error {
    public let statusCode: Int
    public let message: String
    
    public init(_ statusCode: Int, _ message: String) {
        self.statusCode = statusCode
        self.message = message
    }
}

/// Client JSON error
public struct A2AClientJSONError: Error {
    public let message: String
    
    public init(_ message: String) {
        self.message = message
    }
}

/// Client JSON-RPC error
public struct A2AClientJSONRPCError: Error, Sendable {
    public let code: Int
    public let message: String
    public let data: AnyCodable?
    
    public init(code: Int, message: String, data: Any? = nil) {
        self.code = code
        self.message = message
        self.data = data.map { AnyCodable($0) }
    }
}

/// Client timeout error
public struct A2AClientTimeoutError: Error {
    public let message: String
    
    public init(_ message: String = "Request timeout") {
        self.message = message
    }
}

