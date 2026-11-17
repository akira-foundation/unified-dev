import Foundation

public struct CodexTranslation: Sendable {
    public struct Context: Sendable, Hashable {
        public var model: String
        public var cwd: String
        public var permissionMode: String
        public var version: String

        public init(model: String = "", cwd: String = "", permissionMode: String = "", version: String = "") {
            self.model = model
            self.cwd = cwd
            self.permissionMode = permissionMode
            self.version = version
        }
    }

    public var context: Context
    public private(set) var usage: CodexTokenUsage = CodexTokenUsage()

    public init(context: Context = Context()) {
        self.context = context
    }

    public static func toolName(for item: CodexItem) -> String {
        switch item {
        case .commandExecution: "Shell"
        case .fileChange: "ApplyPatch"
        case .mcpToolCall(let call): "mcp__\(call.server)__\(call.tool)"
        case .webSearch: "WebSearch"
        case .plan: "Plan"
        case .subAgentActivity: "SubAgent"
        case .contextCompaction: "Compact"
        case .other(let type, _, _): "Codex.\(type)"
        case .userMessage, .agentMessage, .reasoning: ""
        }
    }

    public static let itemKey = "codexItem"

    public static func isCodexCall(_ input: JSONValue) -> Bool {
        input[itemKey] != nil
    }

    public static func item(in input: JSONValue) -> CodexItem? {
        guard let json = input[itemKey] else { return nil }
        return CodexItem.decode(json)
    }

    public static func isCall(_ item: CodexItem) -> Bool {
        switch item {
        case .userMessage, .agentMessage, .reasoning: false
        default: true
        }
    }

    public static func input(for item: CodexItem) -> JSONValue {
        var members: [String: JSONValue] = [:]

        switch item {
        case .commandExecution(let run):
            members["command"] = .string(run.command)
            if !run.cwd.isEmpty { members["cwd"] = .string(run.cwd) }
        case .fileChange(let change):
            if let first = change.changes.first { members["file_path"] = .string(first.path) }
        case .mcpToolCall(let call):
            members["server"] = .string(call.server)
            members["tool"] = .string(call.tool)
        case .webSearch(let search):
            members["query"] = .string(search.query)
            if let url = search.url { members["url"] = .string(url) }
        case .plan(let plan):
            members["text"] = .string(plan.text)
        default:
            break
        }

        members[itemKey] = json(of: item)
        return .object(members)
    }

    static func json(of item: CodexItem) -> JSONValue {
        switch item {
        case .other(_, _, let payload):
            return payload

        case .commandExecution(let run):
            return .object(omittingNil: [
                "type": .string("commandExecution"),
                "id": .string(run.id),
                "command": .string(run.command),
                "cwd": run.cwd.isEmpty ? nil : .string(run.cwd),
                "aggregatedOutput": run.aggregatedOutput.isEmpty ? nil : .string(run.aggregatedOutput),
                "exitCode": run.exitCode.map { .integer($0) },
                "durationMs": run.durationMS.map { .integer($0) },
                "status": .string(run.status.rawValue),
            ])

        case .fileChange(let change):
            return .object([
                "type": .string("fileChange"),
                "id": .string(change.id),
                "status": .string(change.status.rawValue),
                "changes": .array(change.changes.map { update in
                    .object(omittingNil: [
                        "path": .string(update.path),
                        "diff": .string(update.diff),
                        "kind": .object(omittingNil: [
                            "type": .string(update.kind.wireName),
                            "move_path": update.kind.movedTo.map { .string($0) },
                        ]),
                    ])
                }),
            ])

        case .mcpToolCall(let call):
            return .object(omittingNil: [
                "type": .string("mcpToolCall"),
                "id": .string(call.id),
                "server": .string(call.server),
                "tool": .string(call.tool),
                "arguments": call.arguments,
                "status": .string(call.status.rawValue),
                "error": call.errorMessage.map { .object(["message": .string($0)]) },
                "durationMs": call.durationMS.map { .integer($0) },
            ])

        case .webSearch(let search):
            return .object(omittingNil: [
                "type": .string("webSearch"),
                "id": .string(search.id),
                "query": .string(search.query),
                "action": .object(omittingNil: [
                    "type": .string(search.action),
                    "url": search.url.map { .string($0) },
                ]),
            ])

        case .plan(let plan):
            return .object([
                "type": .string("plan"), "id": .string(plan.id), "text": .string(plan.text),
            ])

        case .subAgentActivity(let activity):
            return .object([
                "type": .string("subAgentActivity"),
                "id": .string(activity.id),
                "agentPath": .string(activity.agentPath),
                "agentThreadId": .string(activity.agentThreadID),
                "kind": .string(activity.kind),
            ])

        case .contextCompaction(let id):
            return .object(["type": .string("contextCompaction"), "id": .string(id)])

        case .userMessage(let message):
            return .object([
                "type": .string("userMessage"),
                "id": .string(message.id),
                "text": .string(message.text),
            ])

        case .agentMessage(let message):
            return .object([
                "type": .string("agentMessage"),
                "id": .string(message.id),
                "text": .string(message.text),
            ])

        case .reasoning(let reasoning):
            return .object([
                "type": .string("reasoning"),
                "id": .string(reasoning.id),
                "summary": .array(reasoning.summary.map { .string($0) }),
                "content": .array(reasoning.content.map { .string($0) }),
            ])
        }
    }

    public static func resultText(for item: CodexItem) -> String {
        switch item {
        case .commandExecution(let run):
            if !run.aggregatedOutput.isEmpty { return run.aggregatedOutput }
            guard let code = run.exitCode else { return "" }
            return code == 0 ? "" : "Exited \(code)"

        case .fileChange(let change):
            return change.changes.map(\.diff).joined(separator: "\n")

        case .mcpToolCall(let call):
            return call.errorMessage ?? ""

        case .plan(let plan):
            return plan.text

        case .webSearch(let search):
            return search.url ?? ""

        case .subAgentActivity(let activity):
            return "\(activity.agentPath) \(activity.kind)"

        default:
            return ""
        }
    }

    public static func status(of item: CodexItem) -> CodexRunStatus {
        switch item {
        case .commandExecution(let run): run.status
        case .fileChange(let change): change.status
        case .mcpToolCall(let call): call.status
        default: .completed
        }
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
        sessionID: String,
        errorCode: String? = nil
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
        if let errorCode { result[TurnStopCause.codexErrorField] = .string(errorCode) }
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
            "claude_code_version": .string(context.version),
            "agent_kind": .string(AgentKind.codex.rawValue),
        ]))
    }

    static func errorLine(message: String) -> Data {
        line(.object([
            "type": .string("error"),
            "subtype": .string("codex"),
            "stderr": .string(message),
        ]))
    }

    static func rateLimitLine(_ payload: Data) -> Data {
        line(.object([
            "type": .string("rate_limit_event"),
            "codex": JSONValue.parse(payload) ?? .null,
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

    public mutating func translate(_ event: CodexEvent) -> [AgentEvent] {
        switch event {
        case .threadStarted(let threadID, _):
            return [.initialized(AgentInit(
                sessionID: threadID,
                cwd: context.cwd,
                model: context.model,
                permissionMode: context.permissionMode,
                agentKind: .codex,
                version: context.version,
                raw: Self.initLine(sessionID: threadID, context: context)
            ))]

        case .itemStarted(let started):
            guard Self.isCall(started.item) else { return [] }
            let input = Self.input(for: started.item)
            let block = JSONValue.object([
                "type": .string("tool_use"),
                "id": .string(started.item.id),
                "name": .string(Self.toolName(for: started.item)),
                "input": input,
            ])
            return [.toolUse(AgentToolUse(
                id: started.item.id,
                name: Self.toolName(for: started.item),
                input: input,
                raw: Self.assistantLine(
                    blocks: [block],
                    messageID: started.item.id,
                    model: context.model,
                    usage: usage.agentUsage,
                    sessionID: started.threadID
                ),
                messageID: started.item.id,
                sessionID: started.threadID
            ))]

        case .itemCompleted(let completed):
            return completedEvents(completed)

        case .agentMessageDelta(let delta):
            return [.streamDelta(.text(delta.text))]

        case .reasoningDelta(let delta):
            return [.streamDelta(.thinking(delta.text))]

        case .tokenUsage(let value):
            usage = value
            return []

        case .rateLimits(let raw):
            return [.rateLimit(Self.rateLimitLine(raw))]

        case .threadStatus(let status):
            guard status.state == .active else { return [] }
            return [.status(status.isWaitingOnApproval ? "Waiting on you" : "Working")]

        case .turnCompleted(let turn):
            return [.result(result(for: turn))]

        case .turnError(let failure):
            guard !failure.willRetry else { return [] }
            return [.error(AgentError(
                message: failure.message,
                raw: Self.errorLine(message: failure.message)
            ))]

        case .closed(let reason):
            return [.error(AgentError(message: reason, raw: Self.errorLine(message: reason)))]

        case .turnStarted, .planDelta, .commandOutputDelta, .approval, .unknown:
            return []
        }
    }

    private func completedEvents(_ completed: CodexItemEvent) -> [AgentEvent] {
        switch completed.item {
        case .userMessage:
            return []

        case .agentMessage(let message):
            guard !message.text.isEmpty else { return [] }
            return [.assistantText(AgentTextBlock(
                text: message.text,
                raw: Self.assistantLine(
                    blocks: [.object(["type": .string("text"), "text": .string(message.text)])],
                    messageID: message.id,
                    model: context.model,
                    usage: usage.agentUsage,
                    sessionID: completed.threadID
                ),
                messageID: message.id,
                model: context.model,
                usage: usage.agentUsage,
                sessionID: completed.threadID
            ))]

        case .reasoning(let reasoning):
            let text = reasoning.displayText
            guard !text.isEmpty else { return [] }
            return [.thinking(AgentTextBlock(
                text: text,
                raw: Self.assistantLine(
                    blocks: [.object(["type": .string("thinking"), "thinking": .string(text)])],
                    messageID: reasoning.id,
                    model: context.model,
                    usage: usage.agentUsage,
                    sessionID: completed.threadID
                ),
                messageID: reasoning.id,
                model: context.model,
                usage: usage.agentUsage,
                sessionID: completed.threadID
            ))]

        default:
            let status = Self.status(of: completed.item)
            let isError = status == .failed || status == .declined
            let refusalKind = status == .declined ? "user-rejected" : nil
            let text = Self.resultText(for: completed.item)
            return [.toolResult(AgentToolResult(
                toolUseID: completed.item.id,
                text: text,
                isError: isError,
                refusal: status == .declined ? .denied : nil,
                raw: Self.toolResultLine(
                    toolUseID: completed.item.id,
                    text: text,
                    isError: isError,
                    refusalKind: refusalKind,
                    sessionID: completed.threadID
                ),
                sessionID: completed.threadID
            ))]
        }
    }

    private func result(for turn: CodexTurn) -> AgentResult {
        let subtype = turn.status == .completed ? "success" : turn.status.rawValue
        let summary = turn.errorMessage ?? ""
        return AgentResult(
            usage: usage.agentUsage,
            summary: summary,
            isError: turn.status == .failed,
            subtype: subtype,
            durationMS: turn.durationMS ?? 0,
            numTurns: 1,
            stopReason: turn.status == .interrupted ? "interrupted" : nil,
            raw: Self.resultLine(
                subtype: subtype,
                isError: turn.status == .failed,
                summary: summary,
                durationMS: turn.durationMS ?? 0,
                usage: usage.agentUsage,
                model: context.model,
                sessionID: turn.threadID,
                errorCode: turn.status == .failed ? turn.errorCode : nil
            ),
            sessionID: turn.threadID
        )
    }
}

extension CodexFileUpdate.Kind {
    var wireName: String {
        switch self {
        case .add: "add"
        case .delete: "delete"
        case .update: "update"
        case .unknown(let raw): raw
        }
    }

    var movedTo: String? {
        if case .update(let path) = self { return path }
        return nil
    }

    public var label: String {
        switch self {
        case .add: "Created"
        case .delete: "Deleted"
        case .update(let movedTo): movedTo == nil ? "Edited" : "Moved"
        case .unknown: "Changed"
        }
    }
}
