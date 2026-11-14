import Foundation

public struct ACPTranslation: Sendable {
    public struct Context: Sendable, Hashable {
        public var agentKind: AgentKind
        public var model: String
        public var cwd: String
        public var permissionMode: String
        public var version: String

        public init(
            agentKind: AgentKind,
            model: String = "",
            cwd: String = "",
            permissionMode: String = "",
            version: String = ""
        ) {
            self.agentKind = agentKind
            self.model = model
            self.cwd = cwd
            self.permissionMode = permissionMode
            self.version = version
        }
    }

    public var context: Context
    public private(set) var usage = AgentUsage()
    public private(set) var sessionID = ""

    private var text = ""
    private var thought = ""
    private var tools: [String: ACPToolCall] = [:]
    private var textMessageID = ""
    private var thoughtMessageID = ""

    public init(context: Context) {
        self.context = context
    }

    public static let itemKey = "grokItem"

    public static func isACPCall(_ input: JSONValue) -> Bool {
        input[itemKey] != nil
    }

    public static func toolName(for call: ACPToolCall, kind: AgentKind) -> String {
        let raw = call.toolName.isEmpty ? call.title : call.toolName
        switch raw {
        case "read_file", "view_file", "Read": return "Read"
        case "write_file", "write_to_file", "Write": return "Write"
        case "search_replace", "str_replace", "edit_file", "Edit": return "Edit"
        case "run_terminal_cmd", "run_command", "bash", "shell", "Bash": return "Bash"
        case "grep", "grep_search", "Grep": return "Grep"
        case "glob_file_search", "glob", "Glob": return "Glob"
        case "list_dir": return "Glob"
        case "web_search", "search_web", "WebSearch": return "WebSearch"
        case "web_fetch", "read_url_content", "WebFetch": return "WebFetch"
        case "todo_write", "TodoWrite": return "TodoWrite"
        case "spawn_subagent", "Agent", "Task": return "Task"
        default:
            if raw.hasPrefix("mcp__") { return raw }
            if let named = mcpName(raw) { return named }
            return raw.isEmpty ? "\(kind.label).\(call.kind.isEmpty ? "tool" : call.kind)" : raw
        }
    }

    static func mcpName(_ raw: String) -> String? {
        guard raw.hasPrefix("mcp_") else { return nil }
        let rest = raw.dropFirst(4)
        guard let split = rest.firstIndex(of: "_") else { return nil }
        let server = rest[..<split]
        let tool = rest[rest.index(after: split)...]
        guard !server.isEmpty, !tool.isEmpty else { return nil }
        return "mcp__\(server)__\(tool)"
    }

    private static let inputAliases: [(String, String)] = [
        ("path", "file_path"), ("Path", "file_path"),
        ("cmd", "command"), ("CommandLine", "command"),
        ("Content", "content"), ("Target", "old_string"), ("Replacement", "new_string"),
    ]

    public static func input(for call: ACPToolCall) -> JSONValue {
        var members = call.rawInput.objectValue ?? [:]
        for (alias, name) in inputAliases where members[name] == nil {
            if let value = members[alias] { members[name] = value }
        }
        if members["file_path"] == nil, !call.path.isEmpty {
            members["file_path"] = .string(call.path)
        }
        if members["query"] == nil, let query = members["search_term"] ?? members["pattern"] {
            members["query"] = query
        }
        members[itemKey] = call.json
        return .object(members)
    }

    public mutating func translate(_ event: ACPEvent) -> [AgentEvent] {
        switch event {
        case .sessionReady(let session):
            sessionID = session.id
            if context.model.isEmpty, !session.currentModelID.isEmpty {
                context.model = session.currentModelID
            }
            return [.initialized(AgentInit(
                sessionID: session.id,
                cwd: context.cwd,
                model: context.model,
                permissionMode: context.permissionMode,
                agentKind: context.agentKind,
                version: context.version,
                raw: Self.initLine(sessionID: session.id, context: context)
            ))]

        case .update(let update):
            if !update.sessionID.isEmpty { sessionID = update.sessionID }
            return updateEvents(update)

        case .promptCompleted(let result):
            if !result.sessionID.isEmpty { sessionID = result.sessionID }
            usage.adopt(turnUsage: result.raw["usage"])
            var events = flushOpenBlocks()
            events.append(.result(self.result(for: result)))
            tools.removeAll()
            return events

        case .closed(let reason):
            return finishInterruptedTurn()
                + [.error(AgentError(message: reason, raw: Self.errorLine(message: reason, kind: context.agentKind)))]

        case .permission, .unknown:
            return []
        }
    }

    public mutating func finishInterruptedTurn() -> [AgentEvent] {
        let events = flushOpenBlocks()
        tools.removeAll()
        return events
    }

    private mutating func updateEvents(_ update: ACPSessionUpdate) -> [AgentEvent] {
        switch update.kind {
        case .text(let chunk):
            guard !chunk.isEmpty else { return [] }
            var events = flushThought()
            if text.isEmpty { textMessageID = UUID().uuidString }
            text += chunk
            events.append(.streamDelta(.text(chunk)))
            return events

        case .thought(let chunk):
            guard !chunk.isEmpty else { return [] }
            if thought.isEmpty { thoughtMessageID = UUID().uuidString }
            thought += chunk
            return [.streamDelta(.thinking(chunk))]

        case .toolCall(let call):
            var events = flushOpenBlocks()
            tools[call.id] = merged(call, onto: tools[call.id])
            let stored = tools[call.id] ?? call
            let input = Self.input(for: stored)
            let name = Self.toolName(for: stored, kind: context.agentKind)
            let block = JSONValue.object([
                "type": .string("tool_use"),
                "id": .string(stored.id),
                "name": .string(name),
                "input": input,
            ])
            events.append(.toolUse(AgentToolUse(
                id: stored.id,
                name: name,
                input: input,
                raw: Self.assistantLine(
                    blocks: [block],
                    messageID: stored.id,
                    model: context.model,
                    usage: usage,
                    sessionID: sessionID
                ),
                messageID: stored.id,
                sessionID: sessionID
            )))
            if stored.isFinished {
                events.append(contentsOf: toolResult(for: stored))
            }
            return events

        case .toolCallUpdate(let call):
            let stored = merged(call, onto: tools[call.id])
            tools[call.id] = stored
            guard stored.isFinished else { return [] }
            return toolResult(for: stored)

        case .usage(let used, let size):
            usage.inputTokens = used
            usage.contextTokens = size
            return []

        case .other:
            return []
        }
    }

    private mutating func flushOpenBlocks() -> [AgentEvent] {
        flushThought() + flushText()
    }

    private mutating func flushText() -> [AgentEvent] {
        let finished = text
        text = ""
        guard !finished.isEmpty else { return [] }
        let messageID = textMessageID
        textMessageID = ""
        return [.assistantText(AgentTextBlock(
            text: finished,
            raw: Self.assistantLine(
                blocks: [.object(["type": .string("text"), "text": .string(finished)])],
                messageID: messageID,
                model: context.model,
                usage: usage,
                sessionID: sessionID
            ),
            messageID: messageID,
            model: context.model,
            usage: usage,
            sessionID: sessionID
        ))]
    }

    private mutating func flushThought() -> [AgentEvent] {
        let finished = thought
        thought = ""
        guard !finished.isEmpty else { return [] }
        let messageID = thoughtMessageID
        thoughtMessageID = ""
        return [.thinking(AgentTextBlock(
            text: finished,
            raw: Self.assistantLine(
                blocks: [.object(["type": .string("thinking"), "thinking": .string(finished)])],
                messageID: messageID,
                model: context.model,
                usage: usage,
                sessionID: sessionID
            ),
            messageID: messageID,
            model: context.model,
            usage: usage,
            sessionID: sessionID
        ))]
    }

    private func toolResult(for call: ACPToolCall) -> [AgentEvent] {
        let text = call.contentText.isEmpty
            ? (call.rawOutput.stringValue ?? call.rawOutput.prettyPrinted)
            : call.contentText
        let display = text == "null" ? "" : text
        return [.toolResult(AgentToolResult(
            toolUseID: call.id,
            text: display,
            isError: call.isError,
            refusal: call.status == "cancelled" ? .denied : nil,
            raw: Self.toolResultLine(
                toolUseID: call.id,
                text: display,
                isError: call.isError,
                refusalKind: call.status == "cancelled" ? "user-rejected" : nil,
                sessionID: sessionID
            ),
            sessionID: sessionID
        ))]
    }

    private func merged(_ incoming: ACPToolCall, onto existing: ACPToolCall?) -> ACPToolCall {
        guard let existing else { return incoming }
        return ACPToolCall(
            id: incoming.id.isEmpty ? existing.id : incoming.id,
            title: incoming.title.isEmpty ? existing.title : incoming.title,
            kind: incoming.kind.isEmpty ? existing.kind : incoming.kind,
            status: incoming.status.isEmpty ? existing.status : incoming.status,
            toolName: incoming.toolName.isEmpty ? existing.toolName : incoming.toolName,
            rawInput: incoming.rawInput.objectValue?.isEmpty == false ? incoming.rawInput : existing.rawInput,
            rawOutput: incoming.rawOutput.isNull ? existing.rawOutput : incoming.rawOutput,
            contentText: incoming.contentText.isEmpty ? existing.contentText : incoming.contentText,
            path: incoming.path.isEmpty ? existing.path : incoming.path,
            json: incoming.json
        )
    }

    private func result(for prompt: ACPPromptResult) -> AgentResult {
        let summary = prompt.isError ? prompt.raw["message"]?.stringValue ?? "" : ""
        let subtype = prompt.wasCancelled ? "error_during_execution"
            : prompt.isError ? prompt.stopReason
            : "success"
        return AgentResult(
            usage: usage,
            summary: summary,
            isError: prompt.isError,
            subtype: subtype,
            durationMS: 0,
            numTurns: 1,
            stopReason: prompt.stopReason,
            raw: Self.resultLine(
                subtype: subtype,
                isError: prompt.isError,
                summary: summary,
                durationMS: 0,
                usage: usage,
                model: context.model,
                sessionID: sessionID
            ),
            sessionID: sessionID
        )
    }

    static func assistantLine(
        blocks: [JSONValue],
        messageID: String,
        model: String,
        usage: AgentUsage,
        sessionID: String
    ) -> Data {
        line(.object([
            "type": .string("assistant"),
            "session_id": .string(sessionID),
            "message": .object([
                "id": .string(messageID),
                "model": .string(model),
                "role": .string("assistant"),
                "content": .array(blocks),
                "usage": encode(usage),
            ]),
        ]))
    }

    static func toolResultLine(
        toolUseID: String,
        text: String,
        isError: Bool,
        refusalKind: String?,
        sessionID: String
    ) -> Data {
        var members: [String: JSONValue] = [
            "type": .string("user"),
            "session_id": .string(sessionID),
            "message": .object([
                "role": .string("user"),
                "content": .array([.object([
                    "type": .string("tool_result"),
                    "tool_use_id": .string(toolUseID),
                    "content": .string(text),
                    "is_error": .bool(isError),
                ])]),
            ]),
        ]
        if let refusalKind {
            members["tool_result_meta"] = .array([.object([
                "id": .string(toolUseID),
                "non_execution_kind": .string(refusalKind),
            ])])
        }
        return line(.object(members))
    }

    static func resultLine(
        subtype: String,
        isError: Bool,
        summary: String,
        durationMS: Int,
        usage: AgentUsage,
        model: String,
        sessionID: String
    ) -> Data {
        var result: [String: JSONValue] = [
            "type": .string("result"),
            "subtype": .string(subtype),
            "is_error": .bool(isError),
            "result": .string(summary),
            "duration_ms": .integer(durationMS),
            "num_turns": .integer(1),
            "session_id": .string(sessionID),
            "usage": encode(usage),
        ]
        if usage.contextTokens > 0 {
            result["modelUsage"] = .object([
                model: .object(["contextWindow": .integer(usage.contextTokens)]),
            ])
        }
        return line(.object(result))
    }

    static func initLine(sessionID: String, context: Context) -> Data {
        line(.object([
            "type": .string("system"),
            "subtype": .string("init"),
            "session_id": .string(sessionID),
            "cwd": .string(context.cwd),
            "model": .string(context.model),
            "permissionMode": .string(context.permissionMode),
            "agent_kind": .string(context.agentKind.rawValue),
        ]))
    }

    static func errorLine(message: String, kind: AgentKind) -> Data {
        line(.object([
            "type": .string("error"),
            "subtype": .string(kind.rawValue),
            "stderr": .string(message),
        ]))
    }

    static func encode(_ usage: AgentUsage) -> JSONValue {
        .object([
            "input_tokens": .integer(usage.inputTokens),
            "output_tokens": .integer(usage.outputTokens),
            "cache_read_input_tokens": .integer(usage.cacheReadTokens),
            "cache_creation_input_tokens": .integer(usage.cacheCreationTokens),
            "output_tokens_details": .object(["thinking_tokens": .integer(usage.thinkingTokens)]),
        ])
    }

    static func line(_ json: JSONValue) -> Data {
        Data(json.compactJSON.utf8)
    }
}

private extension AgentUsage {
    mutating func adopt(turnUsage json: JSONValue?) {
        guard let json, let input = json["inputTokens"]?.intValue else { return }
        inputTokens = input
        outputTokens = json["outputTokens"]?.intValue ?? outputTokens
        cacheReadTokens = json["cachedReadTokens"]?.intValue ?? cacheReadTokens
        cacheCreationTokens = json["cachedWriteTokens"]?.intValue ?? cacheCreationTokens
        thinkingTokens = json["thoughtTokens"]?.intValue ?? thinkingTokens
    }
}
