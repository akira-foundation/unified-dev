import Foundation

public struct DecidedMessage: Sendable {
    public let message: Message
    public let parentToolUseID: String?
    public let result: ToolResultSummary
    public let ask: PermissionAsk?

    public init(_ message: Message) {
        self.message = message
        let object = try? JSONSerialization.jsonObject(with: message.payload) as? [String: Any]
        parentToolUseID = object?["parent_tool_use_id"] as? String
        result = message.kind == .toolResult ? object.map(ToolResultSummary.decode(object:)) ?? ToolResultSummary() : ToolResultSummary()
        ask = message.kind == .permissionAsk ? PermissionAsk.decode(payload: message.payload) : nil
    }

    @concurrent
    public static func deciding(_ messages: [Message]) async -> [DecidedMessage] {
        messages.map(DecidedMessage.init)
    }
}
