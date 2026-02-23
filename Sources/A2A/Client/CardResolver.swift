import Foundation
import AsyncHTTPClient
import NIOFoundationCompat

/// AgentCardResolver discovers agent cards from well-known paths
public actor AgentCardResolver {
    private let httpClient: HTTPClient
    
    public init(httpClient: HTTPClient? = nil) {
        self.httpClient = httpClient ?? HTTPClient(eventLoopGroupProvider: .createNew)
    }
    
    /// Get agent card from a URL
    /// - Parameter url: The base URL of the agent
    /// - Returns: The AgentCard
    public func getAgentCard(url: String) async throws -> AgentCard {
        // Try well-known path first
        let wellKnownURL = url + A2AConstants.agentCardWellKnownPath
        
        var request = try HTTPClient.Request(
            url: wellKnownURL,
            method: .GET,
            headers: ["Accept": "application/json"]
        )
        
        let response = try await httpClient.execute(request: request).get()
        
        guard response.status == .ok else {
            throw A2AClientHTTPError(
                Int(response.status.code),
                "Failed to fetch agent card: \(response.status)"
            )
        }
        
        guard let body = response.body else {
            throw A2AClientJSONError("Empty response body")
        }
        
        // Convert ByteBuffer to Data
        let data = Data(buffer: body)

        let decoder = JSONDecoder()
        do {
            let agentCard = try decoder.decode(AgentCard.self, from: data)
            return agentCard
        } catch {
            throw A2AClientJSONError("Failed to parse agent card: \(error.localizedDescription)")
        }
    }
    
    deinit {
        // Cleanup HTTP client if we created it
        try? httpClient.syncShutdown()
    }
}

