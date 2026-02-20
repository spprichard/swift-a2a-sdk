import Foundation
import SwiftProtobuf
@preconcurrency import AnyCodable

// Note: This file references generated protobuf types from A2A_Protobuf module
// The protobuf types will be generated from a2a.proto and placed in Sources/A2A/Protobuf/
// For now, we define the types that will wrap the protobuf types once generated.

/// Task state enum matching the A2A protocol
/// Per spec Section 5.5: Enum values use lower kebab-case after removing type name prefixes
public enum TaskState: String, Codable, CaseIterable, Sendable {
    case unspecified = "unspecified"
    case submitted = "submitted"
    case working = "working"
    case completed = "completed"
    case failed = "failed"
    case cancelled = "cancelled"
    case inputRequired = "input-required"
    case rejected = "rejected"
    case authRequired = "auth-required"
    
    /// Check if this is a terminal state
    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled, .rejected:
            return true
        default:
            return false
        }
    }
}

/// Role enum for message sender
/// Per spec Section 5.5: Enum values use lowercase after removing type name prefixes
public enum Role: String, Codable, Sendable {
    case unspecified = "unspecified"
    case user = "user"
    case agent = "agent"
}

/// Transport protocol enum
public enum TransportProtocol: String, Codable, Sendable {
    case jsonrpc = "JSONRPC"
    case grpc = "GRPC"
    case httpJson = "HTTP+JSON"
}

/// Part represents a container for a section of communication content
/// Per spec Appendix A.2.1: Uses member name as discriminator
/// - TextPart: `{ "text": "..." }`
/// - FilePart: `{ "file": { ... } }`
/// - DataPart: `{ "data": { ... } }`
public enum Part: Codable, Sendable {
    case text(String)
    case file(FilePart)
    case data(DataPart)
    
    private enum CodingKeys: String, CodingKey {
        case text
        case file
        case data
    }
    
    public init(from decoder: Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if let textValue = try container.decodeIfPresent(String.self, forKey: .text) {
            self = .text(textValue)
        } else if let fileValue = try container.decodeIfPresent(FilePart.self, forKey: .file) {
            self = .file(fileValue)
        } else if let dataValue = try container.decodeIfPresent(DataPart.self, forKey: .data) {
            self = .data(dataValue)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Part must have one of: text, file, or data"
                )
            )
        }
    }
    
    public func encode(to encoder: Swift.Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .text(let textValue):
            try container.encode(textValue, forKey: .text)
        case .file(let fileValue):
            try container.encode(fileValue, forKey: .file)
        case .data(let dataValue):
            try container.encode(dataValue, forKey: .data)
        }
    }
}

/// FilePart represents file content
public struct FilePart: Sendable {
    public enum FileContent: Sendable {
        case uri(String)
        case bytes(Data)
    }

    public let content: FileContent
    public let mediaType: String?
    public let name: String?

    // 2. CHANGED: 'private' -> 'fileprivate' (or remove access modifier for internal)
    // This ensures the extension below can verify conformance for the generic container.
    // Per spec Section 5.5: JSON uses camelCase field names
    fileprivate enum CodingKeys: String, CodingKey {
        case fileWithURI = "fileWithUri"
        case fileWithBytes = "fileWithBytes"
        case mediaType
        case name
    }

    public init(content: FileContent, mediaType: String? = nil, name: String? = nil) {
        self.content = content
        self.mediaType = mediaType
        self.name = name
    }
}

extension FilePart: Decodable {
    // 3. SAFEGUARD: Use Swift.Decoder in case you have a local "Decoder" type
    public init(from decoder: Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedContent: FileContent

        if let uri = try container.decodeIfPresent(String.self, forKey: .fileWithURI) {
            decodedContent = .uri(uri)
        } else if let bytesString = try container.decodeIfPresent(String.self, forKey: .fileWithBytes),
                  let bytes = Data(base64Encoded: bytesString) {
            decodedContent = .bytes(bytes)
        } else if let bytes = try? container.decodeIfPresent(Data.self, forKey: .fileWithBytes) {
            decodedContent = .bytes(bytes)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "FilePart must have either file_with_uri or file_with_bytes"
                )
            )
        }

        let decodedMediaType = try container.decodeIfPresent(String.self, forKey: .mediaType)
        let decodedName = try container.decodeIfPresent(String.self, forKey: .name)

        self.init(content: decodedContent, mediaType: decodedMediaType, name: decodedName)
    }
}

extension FilePart: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch content {
        case .uri(let uri):
            try container.encode(uri, forKey: .fileWithURI)
        case .bytes(let bytes):
            try container.encode(bytes, forKey: .fileWithBytes)
        }

        try container.encodeIfPresent(mediaType, forKey: .mediaType)
        try container.encodeIfPresent(name, forKey: .name)
    }
}

/// DataPart represents structured data
public struct DataPart: Codable, Sendable {
    // Store as AnyCodable internally for Sendable conformance
    // Compiler-generated Codable will encode/decode this as "data" in JSON
    public let data: [String: AnyCodable]
    
    /// Access the data as [String: Any]
    public var dataValue: [String: Any] {
        data.mapValues { $0.value }
    }
    
    public init(data: [String: Any]) {
        self.data = data.mapValues { AnyCodable($0) }
    }
}

// Using Flight-School/AnyCodable library instead of custom implementation
// Note: The library is archived (read-only) but still functional
// The library's AnyCodable type is imported and used directly

/// Helper for dynamic coding keys
private struct DynamicCodingKeys: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init?(stringValue: String) {
        self.stringValue = stringValue
    }
    
    init?(intValue: Int) {
        self.intValue = intValue
        self.stringValue = "\(intValue)"
    }
}

/// TaskStatus represents the status of a task
public struct TaskStatus: Codable, Sendable {
    public let state: TaskState
    public var message: Message?
    public let timestamp: Date?

    public init(state: TaskState, message: Message? = nil, timestamp: Date? = nil) {
        self.state = state
        self.message = message
        self.timestamp = timestamp
    }
}

/// Message represents a single turn of communication
public struct Message: Codable, Sendable {
    public let messageID: String
    public let contextID: String?
    public let taskID: String?
    public let role: Role
    public let parts: [Part]
    // Store as AnyCodable for Sendable/Codable conformance
    public let metadata: [String: AnyCodable]?
    public let extensions: [String]?
    public let referenceTaskIDs: [String]?
    
    /// Access metadata as [String: Any]
    public var metadataValue: [String: Any]? {
        metadata?.mapValues { $0.value }
    }

    // Per spec Section 5.5: JSON uses camelCase field names
    private enum CodingKeys: String, CodingKey {
        case messageID = "messageId"
        case contextID = "contextId"
        case taskID = "taskId"
        case role
        case parts
        case metadata
        case extensions
        case referenceTaskIDs = "referenceTaskIds"
    }
    
    public init(
        messageID: String,
        contextID: String? = nil,
        taskID: String? = nil,
        role: Role,
        parts: [Part],
        metadata: [String: Any]? = nil,
        extensions: [String]? = nil,
        referenceTaskIDs: [String]? = nil
    ) {
        self.messageID = messageID
        self.contextID = contextID
        self.taskID = taskID
        self.role = role
        self.parts = parts
        self.metadata = metadata?.mapValues { AnyCodable($0) }
        self.extensions = extensions
        self.referenceTaskIDs = referenceTaskIDs
    }
}

/// Artifact represents task outputs
public struct Artifact: Codable, Sendable {
    public var artifactID: String
    public var name: String?
    public var description: String?
    public var parts: [Part]
    // Store as AnyCodable for Sendable/Codable conformance
    public var metadata: [String: AnyCodable]?
    public var extensions: [String]?
    
    /// Access metadata as [String: Any]
    public var metadataValue: [String: Any]? {
        get { metadata?.mapValues { $0.value } }
        set { metadata = newValue?.mapValues { AnyCodable($0) } }
    }
    
    // Per spec Section 5.5: JSON uses camelCase field names
    private enum CodingKeys: String, CodingKey {
        case artifactID = "artifactId"
        case name
        case description
        case parts
        case metadata
        case extensions
    }
    
    public init(
        artifactID: String,
        name: String? = nil,
        description: String? = nil,
        parts: [Part],
        metadata: [String: Any]? = nil,
        extensions: [String]? = nil
    ) {
        self.artifactID = artifactID
        self.name = name
        self.description = description
        self.parts = parts
        self.metadata = metadata?.mapValues { AnyCodable($0) }
        self.extensions = extensions
    }
}

/// Task is the core unit of action for A2A
public struct Task: Codable, Sendable {
    public let id: String
    public let contextID: String
    public var status: TaskStatus
    public var artifacts: [Artifact]
    public var history: [Message]
    // Store as AnyCodable for Sendable/Codable conformance
    public var metadata: [String: AnyCodable]?
    
    /// Access metadata as [String: Any]
    public var metadataValue: [String: Any]? {
        metadata?.mapValues { $0.value }
    }

    // Per spec Section 5.5: JSON uses camelCase field names
    private enum CodingKeys: String, CodingKey {
        case id
        case contextID = "contextId"
        case status
        case artifacts
        case history
        case metadata
    }
    
    public init(
        id: String,
        contextID: String,
        status: TaskStatus,
        artifacts: [Artifact] = [],
        history: [Message] = [],
        metadata: [String: Any]? = nil
    ) {
        self.id = id
        self.contextID = contextID
        self.status = status
        self.artifacts = artifacts
        self.history = history
        self.metadata = metadata?.mapValues { AnyCodable($0) }
    }
}

/// AgentInterface declares a combination of URL and transport protocol
public struct AgentInterface: Codable, Sendable {
    public var url: String
    public var transport: TransportProtocol
    public var tenant: String?
    
    public init(url: String, transport: TransportProtocol, tenant: String? = nil) {
        self.url = url
        self.transport = transport
        self.tenant = tenant
    }
}

/// AgentCard represents an agent's capabilities and metadata
public struct AgentCard: Codable, Sendable {
    public var protocolVersion: String
    public var name: String
    public var url: String  // Required top-level URL for the agent
    public var description: String
    public var supportedInterfaces: [AgentInterface]
    public var version: String
    public var documentationURL: String?
    public var capabilities: AgentCapabilities
    public var defaultInputModes: [String]
    public var defaultOutputModes: [String]
    public var skills: [AgentSkill]
    public var supportsExtendedAgentCard: Bool?
    public var iconURL: String?
    
    // Per spec Section 5.5: JSON uses camelCase field names
    private enum CodingKeys: String, CodingKey {
        case protocolVersion
        case name
        case url
        case description
        case supportedInterfaces
        case version
        case documentationURL = "documentationUrl"
        case capabilities
        case defaultInputModes
        case defaultOutputModes
        case skills
        case supportsExtendedAgentCard
        case iconURL = "iconUrl"
    }
    
    public init(
        protocolVersion: String = A2AConstants.protocolVersion,
        name: String,
        url: String,
        description: String,
        supportedInterfaces: [AgentInterface]? = nil,
        version: String,
        documentationURL: String? = nil,
        capabilities: AgentCapabilities,
        defaultInputModes: [String],
        defaultOutputModes: [String],
        skills: [AgentSkill],
        supportsExtendedAgentCard: Bool? = nil,
        iconURL: String? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.name = name
        self.url = url
        self.description = description
        // If no supportedInterfaces provided, create a default one from the URL
        self.supportedInterfaces = supportedInterfaces ?? [
            AgentInterface(url: url, transport: .jsonrpc)
        ]
        self.version = version
        self.documentationURL = documentationURL
        self.capabilities = capabilities
        self.defaultInputModes = defaultInputModes
        self.defaultOutputModes = defaultOutputModes
        self.skills = skills
        self.supportsExtendedAgentCard = supportsExtendedAgentCard
        self.iconURL = iconURL
    }
    
    /// Convenience property to get the preferred transport
    public var preferredTransport: TransportProtocol? {
        supportedInterfaces.first?.transport
    }
}

/// AgentCapabilities defines optional capabilities
public struct AgentCapabilities: Codable, Sendable {
    public var streaming: Bool?
    public var pushNotifications: Bool?
    public var stateTransitionHistory: Bool?
    
    // Per spec Section 5.5: JSON uses camelCase field names
    private enum CodingKeys: String, CodingKey {
        case streaming
        case pushNotifications
        case stateTransitionHistory
    }
    
    public init(streaming: Bool? = nil, pushNotifications: Bool? = nil, stateTransitionHistory: Bool? = nil) {
        self.streaming = streaming
        self.pushNotifications = pushNotifications
        self.stateTransitionHistory = stateTransitionHistory
    }
}

/// AgentSkill represents a distinct capability
public struct AgentSkill: Codable, Sendable {
    public var id: String
    public var name: String
    public var description: String
    public var tags: [String]
    public var examples: [String]?
    public var inputModes: [String]?
    public var outputModes: [String]?
    
    // Per spec Section 5.5: JSON uses camelCase field names
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case tags
        case examples
        case inputModes
        case outputModes
    }
    
    public init(
        id: String,
        name: String,
        description: String,
        tags: [String],
        examples: [String]? = nil,
        inputModes: [String]? = nil,
        outputModes: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.tags = tags
        self.examples = examples
        self.inputModes = inputModes
        self.outputModes = outputModes
    }
}

