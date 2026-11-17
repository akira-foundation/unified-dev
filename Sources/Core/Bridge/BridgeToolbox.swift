import Foundation

public struct BridgeToolbox: Sendable {
    public let handlers: [any BridgeToolHandling]

    public init(handlers: [any BridgeToolHandling]) {
        self.handlers = handlers
    }

    public static let standard = BridgeToolbox(handlers: [
        WhoamiTool(),
        ProjectListTool(),
        ProjectAddTool(),
        ProjectHideTool(),
        ProjectUnhideTool(),
        WorkspaceListTool(),
        ChatListTool(),
        ChatReadTool(),
        WorkspaceDiffTool(),
        WorkspaceRenameTool(),
        QuickPromptListTool(),
        QuickPromptCreateTool(),
        QuickPromptUpdateTool(),
        QuickPromptDeleteTool(),
        AgentListTool(),
        WorkSuggestTool(),
        WorkWithdrawTool(),
    ])

    public func tools(for role: BridgeRole) -> [BridgeTool] {
        handlers.filter { $0.roles.contains(role) }.map(\.tool).sorted { $0.name < $1.name }
    }

    public func tools(for identity: BridgeIdentity, store: Store) async -> [BridgeTool] {
        var served: [BridgeTool] = []
        for handler in handlers where handler.roles.contains(identity.role) {
            if await handler.isServed(to: identity, store: store) { served.append(handler.tool) }
        }
        return served.sorted { $0.name < $1.name }
    }

    public func handler(
        named name: String, for identity: BridgeIdentity, store: Store
    ) async -> (any BridgeToolHandling)? {
        guard let handler = handler(named: name, for: identity.role),
              await handler.isServed(to: identity, store: store)
        else { return nil }
        return handler
    }

    public func handler(named name: String, for role: BridgeRole) -> (any BridgeToolHandling)? {
        handlers.first { $0.tool.name == name && $0.roles.contains(role) }
    }
}
