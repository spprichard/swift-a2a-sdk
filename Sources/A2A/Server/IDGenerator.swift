import Foundation

/// Protocol for generating unique identifiers
public protocol IDGenerator: Sendable {
    func generate() -> String
}

/// UUID implementation of IDGenerator
public struct UUIDGenerator: IDGenerator {
    public init() {}
    
    public func generate() -> String {
        return UUID().uuidString
    }
}

