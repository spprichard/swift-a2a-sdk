import Foundation
@preconcurrency import AnyCodable

/// Server call context for request handling
public struct ServerCallContext: Sendable {
    public var tenant: String?
    // Store as AnyCodable for Sendable conformance
    public var metadata: [String: AnyCodable]?
    
    /// Access metadata as [String: Any]
    public var metadataValue: [String: Any]? {
        get { metadata?.mapValues { $0.value } }
        set { metadata = newValue?.mapValues { AnyCodable($0) } }
    }
    
    public init(tenant: String? = nil, metadata: [String: Any]? = nil) {
        self.tenant = tenant
        self.metadata = metadata?.mapValues { AnyCodable($0) }
    }
}

