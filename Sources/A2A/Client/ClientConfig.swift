import Foundation
import AsyncHTTPClient

/// Client configuration
public struct ClientConfig {
    public var streaming: Bool
    public var httpClient: HTTPClient?
    
    public init(
        streaming: Bool = true,
        httpClient: HTTPClient? = nil
    ) {
        self.streaming = streaming
        self.httpClient = httpClient
    }
}

