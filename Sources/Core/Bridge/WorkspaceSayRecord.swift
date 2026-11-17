import Foundation

public struct WorkspaceSayRecord: Sendable, Hashable {
    public let messageID: WorkspaceMessageID
    public let text: String
    public let target: WorkspaceMessageEnd

    public init?(toolName: String, input: JSONValue, resultText: String) {
        guard Self.isWorkspaceSay(toolName),
              let text = input["message"]?.stringValue,
              let answer = JSONValue.parse(resultText)
                ?? BridgeWorkspaceQuote.json(inside: resultText).flatMap(JSONValue.parse),
              let id = answer[WorkspaceSayTool.Key.messageID]?.stringValue
        else { return nil }

        messageID = WorkspaceMessageID(id)
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        target = WorkspaceMessageEnd(
            workspaceID: answer[WorkspaceSayTool.Key.workspaceID]?.stringValue.map(WorkspaceID.init),
            workspace: answer[WorkspaceSayTool.Key.workspace]?.stringValue ?? "",
            project: answer[WorkspaceSayTool.Key.project]?.stringValue ?? "",
            chat: answer[WorkspaceSayTool.Key.chat]?.stringValue ?? "",
            profile: answer[WorkspaceSayTool.Key.profile]?.stringValue
        )
    }

    public static func isWorkspaceSay(_ toolName: String) -> Bool {
        toolName.hasPrefix("mcp__") && toolName.hasSuffix("__\(WorkspaceSayTool.name)")
    }
}
