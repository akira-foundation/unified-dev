import Foundation
import Testing
@testable import Core

actor BridgeCallLog {
    private(set) var started = 0

    func start() { started += 1 }
}

struct UnaskedSwitchOwner {
    let repo: Repo
    let lead: Workspace
    let session: Session
    let crew: Workspace
    let crewSession: Session
    let neighbour: Repo
    let store: Store

    var key: String { OrchestratorUnaskedCommands.key(repoID: repo.id) }

    static func seed(_ store: Store, repo: Repo) async throws -> UnaskedSwitchOwner {
        let lead = try await store.upsert(Workspace(
            repoID: repo.id, name: "lead", branch: "b/lead", path: TestScratch.unique("lead"), baseBranch: "main"
        ))
        _ = try await store.setOrchestrator(true, workspaceID: lead.id)
        let crew = try await store.upsert(Workspace(
            repoID: repo.id, name: "crew", branch: "b/crew", path: TestScratch.unique("crew"), baseBranch: "main"
        ))
        let neighbour = try await store.upsert(Repo(name: "neighbour", path: TestScratch.unique("neighbour")))
        try await OrchestratorUnaskedCommands.save(false, repoID: repo.id, to: store)
        try await OrchestratorUnaskedCommands.save(false, repoID: neighbour.id, to: store)
        return UnaskedSwitchOwner(
            repo: repo, lead: lead, session: try await store.upsert(Session(workspaceID: lead.id, title: "Chat")),
            crew: crew, crewSession: try await store.upsert(Session(workspaceID: crew.id, title: "Chat")),
            neighbour: neighbour, store: store
        )
    }

    var identities: [BridgeIdentity] {
        [
            BridgeIdentity(sessionID: session.id, workspaceID: lead.id, role: .workspace),
            BridgeIdentity(sessionID: crewSession.id, workspaceID: crew.id, role: .workspace),
            BridgeIdentity(ownerSession: session.id),
            BridgeIdentity.owner,
        ]
    }

    func isStillOff() async throws -> Bool {
        let grants = SessionGrants(store: store, workspaceID: lead.id)
        let answers = await grants.answersItself(
            toolName: "Bash", input: .object(["command": .string("rg x && echo \"a b\"")])
        )
        var stored: [String?] = []
        for repoID in [repo.id, neighbour.id] {
            if try await store.setting(OrchestratorUnaskedCommands.key(repoID: repoID)) != "off" { return false }
            stored.append(try await store.setting(PullRequestAutoFixSetting.key(repoID: repoID)))
            if await OrchestratorUnaskedCommands.isOn(repoID: repoID, in: store) { return false }
            if await PullRequestAutoFixSetting.isOn(repoID: repoID, in: store) { return false }
        }
        for profile in try await store.profiles() {
            stored.append(try await store.setting(ProfileBridgeSwitch.key(profile: profile.id)))
        }
        return stored.allSatisfy { $0 == nil } && !answers
    }

    var uniformFills: [JSONValue] {
        [.string(key), .string("on"), .string(lead.id.rawValue), .string(repo.path), .bool(true), .integer(1)]
    }

    func uniformArguments(for tool: BridgeTool, filling value: JSONValue) -> JSONValue {
        var arguments: [String: JSONValue] = [
            "key": .string(key), "value": .string("on"), "setting": .string(key), "enabled": .bool(true),
        ]
        for (name, shape) in Self.properties(of: tool) {
            arguments[name] = Self.shaped(value, as: shape["type"]?.stringValue ?? "")
        }
        return .object(arguments)
    }

    func knownIDs() async throws -> [String: String] {
        var ids: [String: String] = [:]
        ids["id"] = try await store.quickPrompts().first?.id.rawValue
        ids["suggestion_id"] = try await store.workSuggestions(sessionID: session.id).first?.id.rawValue
        return ids
    }

    func readableArguments(for tool: BridgeTool, ids: [String: String]) -> [JSONValue] {
        guard case .object(let schema) = tool.inputSchema else { return [.object([:])] }
        let required = Set((schema["required"]?.arrayValue ?? []).compactMap(\.stringValue))
        let every = Set(Self.properties(of: tool).map(\.0))
        return [readableArguments(for: tool, naming: required, ids: ids), readableArguments(for: tool, naming: every, ids: ids)]
    }

    private func readableArguments(for tool: BridgeTool, naming names: Set<String>, ids: [String: String]) -> JSONValue {
        var arguments: [String: JSONValue] = [:]
        for (name, shape) in Self.properties(of: tool) where names.contains(name) {
            if let first = shape["enum"]?.arrayValue?.first {
                arguments[name] = first
                continue
            }
            let value = ids[name].map(JSONValue.string) ?? readable(name)
            arguments[name] = Self.shaped(value, as: shape["type"]?.stringValue ?? "")
        }
        return .object(arguments)
    }

    private func readable(_ name: String) -> JSONValue {
        let lowered = name.lowercased()
        if lowered == "symbol" { return .string(QuickPrompt.defaultSymbol) }
        if lowered.contains("workspace") { return .string(lead.id.rawValue) }
        if lowered.contains("chat") || lowered.contains("session") { return .string(session.id.rawValue) }
        if lowered.contains("path") { return .string(repo.path) }
        if lowered.contains("project") { return .string(repo.name) }
        return .string(key)
    }

    private static func properties(of tool: BridgeTool) -> [(String, [String: JSONValue])] {
        guard case .object(let schema) = tool.inputSchema, case .object(let properties)? = schema["properties"] else {
            return []
        }
        return properties.compactMap { name, property in property.objectValue.map { (name, $0) } }
    }

    private static func shaped(_ value: JSONValue, as type: String) -> JSONValue {
        switch type {
        case "array": .array([value])
        case "object": .object(["key": value, "value": .string("on")])
        case "integer", "number": value.stringValue == nil ? value : .integer(1)
        case "boolean": .bool(true)
        default: value
        }
    }
}

extension OrchestratorUnaskedReachTests {
    struct NotStarted: Error {}

    static func appHandlers(_ log: BridgeCallLog) -> [any BridgeToolHandling] {
        [
            WorkspaceStartTool(
                start: { _, _, _, _ in
                    await log.start()
                    throw NotStarted()
                },
                resolvePullRequest: { _, _ in .failure("") }
            ),
            PaneOpenTool { _, _ in .opened("") },
            TerminalStartTool { _, _ in .opened("") },
            TerminalReadTool { _, _ in .refused("") },
            TerminalWriteTool { _, _ in .refused("") },
            TerminalSendKeyTool { _, _ in .refused("") },
            MediaShowTool { _, _ in .refused("") },
            CanvasShowTool { _, _ in .refused("") },
            CanvasReadTool { _, _ in .refused("") },
            CanvasEditTool { _, _, _ in .refused("") },
            CanvasRenderTool { _, _, _ in .refused("") },
            CanvasCommentResolveTool { _, _ in .refused("") },
            PaneSplitTool { _, _, _, _ in .opened("") },
            PaneCloseTool { _, _ in .opened("") },
            PaneRenameTool { _, _, _ in .opened("") },
            PaneListTool { _ in nil },
            WorkspaceTabsTool { _ in nil },
            WorkspaceTabSelectTool { _, _ in .refused("") },
            BrowserReadTool { _, _ in .refused("") },
            BrowserReloadTool { _, _ in .refused("") },
            BrowserGoTool { _, _ in .refused("") },
            BrowserScrollTool { _, _ in .refused("") },
            BrowserScreenshotTool { _, _ in .refused("") },
            BrowserTextTool { _, _ in .refused("") },
            BrowserPageOutlineTool { _, _ in .refused("") },
            BrowserClickTool { _, _ in .refused("") },
            BrowserFillTool { _, _ in .refused("") },
            BrowserPressTool { _, _ in .refused("") },
            BrowserWaitTool { _, _ in .refused("") },
            WorkspaceArchiveTool { _ in .refused("") },
            WorkspaceMergeTool(read: { _ in .noPullRequest }) { _, _, _ in .refused("") },
            RevealTool { _ in .refused("") },
            AgentStartTool { _, _, _ in .refused("") },
            AgentSayTool { _, _, _, _ in .refused("") },
            AgentStopTool { _, _, _ in .refused("") },
            WorkspaceSayTool { _ in .refused("") },
        ]
    }
}
