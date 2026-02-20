import Foundation
import AsyncHTTPClient

/// ClientFactory creates A2A clients from AgentCards
public class ClientFactory {
    private let config: ClientConfig
    
    public init(config: ClientConfig = ClientConfig()) {
        self.config = config
    }
    
    /// Create a client from an AgentCard
    /// - Parameter agentCard: The agent card describing the agent
    /// - Returns: A configured Client instance
    public func create(agentCard: AgentCard) throws -> Client {
        let url = agentCard.url
        
        // Check if JSON-RPC is supported
        let supportsJSONRPC = agentCard.supportedInterfaces.contains { $0.transport == .jsonrpc }
        guard supportsJSONRPC else {
            throw A2AClientInvalidStateError("Agent does not support JSON-RPC transport")
        }
        
        // Get JSON-RPC URL
        let jsonrpcURL = agentCard.supportedInterfaces.first { $0.transport == .jsonrpc }?.url ?? url
        
        // Create HTTP client if not provided
        let httpClient = config.httpClient ?? HTTPClient(eventLoopGroupProvider: .createNew)
        
        // Create transport
        let transport = JSONRPCTransport(
            httpClient: httpClient,
            url: jsonrpcURL,
            agentCard: agentCard
        )
        
        // Create base client
        return BaseClient(
            agentCard: agentCard,
            transport: transport,
            supportsStreaming: config.streaming && (agentCard.capabilities.streaming == true)
        )
    }
    
    /// Convenience method to connect to an agent by URL
    /// - Parameter url: The base URL of the agent
    /// - Returns: A configured Client instance
    public static func connect(url: String) async throws -> Client {
        let resolver = AgentCardResolver()
        let agentCard = try await resolver.getAgentCard(url: url)
        let factory = ClientFactory()
        return try factory.create(agentCard: agentCard)
    }
}

