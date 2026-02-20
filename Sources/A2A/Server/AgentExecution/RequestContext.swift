import Foundation

/// RequestContext contains information about the current request being processed
public struct RequestContext: Sendable {
    public var message: Message
    public var taskID: String?
    public var contextID: String?
    public var callContext: ServerCallContext?
    
    public init(
        message: Message,
        taskID: String? = nil,
        contextID: String? = nil,
        callContext: ServerCallContext? = nil
    ) {
        self.message = message
        self.taskID = taskID
        self.contextID = contextID
        self.callContext = callContext
    }
}

