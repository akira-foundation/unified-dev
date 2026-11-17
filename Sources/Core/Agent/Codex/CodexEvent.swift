import Foundation

public enum CodexItem: Sendable, Hashable {
    case userMessage(CodexUserMessage)
    case agentMessage(CodexAgentMessage)
    case reasoning(CodexReasoning)
    case plan(CodexPlan)
    case commandExecution(CodexCommandExecution)
    case fileChange(CodexFileChange)
    case mcpToolCall(CodexMcpToolCall)
    case webSearch(CodexWebSearch)
    case subAgentActivity(CodexSubAgentActivity)
    case contextCompaction(id: String)
    case other(type: String, id: String, json: JSONValue)

    public var id: String {
        switch self {
        case .userMessage(let item): item.id
        case .agentMessage(let item): item.id
        case .reasoning(let item): item.id
        case .plan(let item): item.id
        case .commandExecution(let item): item.id
        case .fileChange(let item): item.id
        case .mcpToolCall(let item): item.id
        case .webSearch(let item): item.id
        case .subAgentActivity(let item): item.id
        case .contextCompaction(let id): id
        case .other(_, let id, _): id
        }
    }

    public var typeName: String {
        switch self {
        case .userMessage: "userMessage"
        case .agentMessage: "agentMessage"
        case .reasoning: "reasoning"
        case .plan: "plan"
        case .commandExecution: "commandExecution"
        case .fileChange: "fileChange"
        case .mcpToolCall: "mcpToolCall"
        case .webSearch: "webSearch"
        case .subAgentActivity: "subAgentActivity"
        case .contextCompaction: "contextCompaction"
        case .other(let type, _, _): type
        }
    }

    public static func decode(_ json: JSONValue) -> CodexItem? {
        guard let type = json["type"]?.stringValue else { return nil }
        let id = json["id"]?.stringValue ?? ""

        switch type {
        case "userMessage":
            return .userMessage(CodexUserMessage(
                id: id,
                text: CodexUserMessage.renderText(json["content"]),
                imagePaths: CodexUserMessage.imagePaths(json["content"]),
                clientID: json["clientId"]?.stringValue
            ))

        case "agentMessage":
            return .agentMessage(CodexAgentMessage(
                id: id,
                text: json["text"]?.stringValue ?? "",
                phase: CodexMessagePhase(json["phase"]?.stringValue)
            ))

        case "reasoning":
            return .reasoning(CodexReasoning(
                id: id,
                summary: (json["summary"] ?? .null).stringArray,
                content: (json["content"] ?? .null).stringArray
            ))

        case "plan":
            return .plan(CodexPlan(id: id, text: json["text"]?.stringValue ?? ""))

        case "commandExecution":
            return .commandExecution(CodexCommandExecution(
                id: id,
                command: json["command"]?.stringValue ?? "",
                cwd: json["cwd"]?.stringValue ?? "",
                aggregatedOutput: json["aggregatedOutput"]?.stringValue ?? "",
                exitCode: json["exitCode"]?.intValue,
                durationMS: json["durationMs"]?.intValue,
                status: CodexRunStatus(json["status"]?.stringValue),
                processID: json["processId"]?.stringValue
            ))

        case "fileChange":
            return .fileChange(CodexFileChange(
                id: id,
                changes: (json["changes"]?.arrayValue ?? []).compactMap(CodexFileUpdate.decode),
                status: CodexRunStatus(json["status"]?.stringValue)
            ))

        case "mcpToolCall":
            return .mcpToolCall(CodexMcpToolCall(
                id: id,
                server: json["server"]?.stringValue ?? "",
                tool: json["tool"]?.stringValue ?? "",
                arguments: json["arguments"] ?? .null,
                status: CodexRunStatus(json["status"]?.stringValue),
                errorMessage: json["error"]?["message"]?.stringValue,
                durationMS: json["durationMs"]?.intValue
            ))

        case "webSearch":
            return .webSearch(CodexWebSearch(
                id: id,
                query: json["query"]?.stringValue ?? "",
                action: json["action"]?["type"]?.stringValue ?? "",
                url: json["action"]?["url"]?.stringValue
            ))

        case "subAgentActivity":
            return .subAgentActivity(CodexSubAgentActivity(
                id: id,
                agentPath: json["agentPath"]?.stringValue ?? "",
                agentThreadID: json["agentThreadId"]?.stringValue ?? "",
                kind: json["kind"]?.stringValue ?? ""
            ))

        case "contextCompaction":
            return .contextCompaction(id: id)

        default:
            return .other(type: type, id: id, json: json)
        }
    }
}

public enum CodexMessagePhase: String, Sendable, Hashable {
    case commentary
    case finalAnswer
    case unknown

    init(_ raw: String?) {
        switch raw {
        case "commentary": self = .commentary
        case "final_answer": self = .finalAnswer
        default: self = .unknown
        }
    }
}

public enum CodexRunStatus: String, Sendable, Hashable {
    case inProgress
    case completed
    case failed
    case declined
    case unknown

    init(_ raw: String?) {
        self = raw.flatMap(CodexRunStatus.init(rawValue:)) ?? .unknown
    }
}

public struct CodexUserMessage: Sendable, Hashable {
    public let id: String
    public let text: String
    public let imagePaths: [String]
    public let clientID: String?

    public init(id: String, text: String, imagePaths: [String] = [], clientID: String? = nil) {
        self.id = id
        self.text = text
        self.imagePaths = imagePaths
        self.clientID = clientID
    }

    static func renderText(_ content: JSONValue?) -> String {
        (content?.arrayValue ?? [])
            .filter { $0["type"]?.stringValue == "text" }
            .compactMap { $0["text"]?.stringValue }
            .joined(separator: "\n")
    }

    static func imagePaths(_ content: JSONValue?) -> [String] {
        (content?.arrayValue ?? []).compactMap { entry in
            switch entry["type"]?.stringValue {
            case "localImage": entry["path"]?.stringValue
            case "image": entry["url"]?.stringValue
            default: nil
            }
        }
    }
}

public struct CodexAgentMessage: Sendable, Hashable {
    public let id: String
    public let text: String
    public let phase: CodexMessagePhase

    public init(id: String, text: String, phase: CodexMessagePhase = .unknown) {
        self.id = id
        self.text = text
        self.phase = phase
    }
}

public struct CodexReasoning: Sendable, Hashable {
    public let id: String
    public let summary: [String]
    public let content: [String]

    public init(id: String, summary: [String] = [], content: [String] = []) {
        self.id = id
        self.summary = summary
        self.content = content
    }

    public var displayText: String {
        let parts = summary.isEmpty ? content : summary
        return parts.joined(separator: "\n\n")
    }
}

public struct CodexPlan: Sendable, Hashable {
    public let id: String
    public let text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

public struct CodexCommandExecution: Sendable, Hashable {
    public let id: String
    public let command: String
    public let cwd: String
    public let aggregatedOutput: String
    public let exitCode: Int?
    public let durationMS: Int?
    public let status: CodexRunStatus
    public let processID: String?

    public init(
        id: String,
        command: String,
        cwd: String = "",
        aggregatedOutput: String = "",
        exitCode: Int? = nil,
        durationMS: Int? = nil,
        status: CodexRunStatus = .unknown,
        processID: String? = nil
    ) {
        self.id = id
        self.command = command
        self.cwd = cwd
        self.aggregatedOutput = aggregatedOutput
        self.exitCode = exitCode
        self.durationMS = durationMS
        self.status = status
        self.processID = processID
    }
}

public struct CodexFileUpdate: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case add
        case delete
        case update(movedTo: String?)
        case unknown(String)
    }

    public let path: String
    public let diff: String
    public let kind: Kind

    public init(path: String, diff: String, kind: Kind) {
        self.path = path
        self.diff = diff
        self.kind = kind
    }

    public var addedLines: Int {
        switch kind {
        case .add: Self.lineCount(diff)
        case .delete: 0
        case .update, .unknown: Self.hunkCount(diff, marker: "+")
        }
    }

    public var removedLines: Int {
        switch kind {
        case .add: 0
        case .delete: Self.lineCount(diff)
        case .update, .unknown: Self.hunkCount(diff, marker: "-")
        }
    }

    static func lineCount(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var trimmed = text
        if trimmed.hasSuffix("\n") { trimmed.removeLast() }
        return trimmed.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    static func hunkCount(_ diff: String, marker: Character) -> Int {
        diff.split(separator: "\n", omittingEmptySubsequences: false).count { line in
            guard line.first == marker else { return false }
            return !line.hasPrefix("+++") && !line.hasPrefix("---")
        }
    }

    static func decode(_ json: JSONValue) -> CodexFileUpdate? {
        guard let path = json["path"]?.stringValue else { return nil }
        let kind: Kind = switch json["kind"]?["type"]?.stringValue {
        case "add": .add
        case "delete": .delete
        case "update": .update(movedTo: json["kind"]?["move_path"]?.stringValue)
        case let other?: .unknown(other)
        case nil: .unknown("")
        }
        return CodexFileUpdate(path: path, diff: json["diff"]?.stringValue ?? "", kind: kind)
    }
}

public struct CodexFileChange: Sendable, Hashable {
    public let id: String
    public let changes: [CodexFileUpdate]
    public let status: CodexRunStatus

    public init(id: String, changes: [CodexFileUpdate], status: CodexRunStatus = .unknown) {
        self.id = id
        self.changes = changes
        self.status = status
    }
}

public struct CodexMcpToolCall: Sendable, Hashable {
    public let id: String
    public let server: String
    public let tool: String
    public let arguments: JSONValue
    public let status: CodexRunStatus
    public let errorMessage: String?
    public let durationMS: Int?

    public init(
        id: String,
        server: String,
        tool: String,
        arguments: JSONValue = .null,
        status: CodexRunStatus = .unknown,
        errorMessage: String? = nil,
        durationMS: Int? = nil
    ) {
        self.id = id
        self.server = server
        self.tool = tool
        self.arguments = arguments
        self.status = status
        self.errorMessage = errorMessage
        self.durationMS = durationMS
    }
}

public struct CodexWebSearch: Sendable, Hashable {
    public let id: String
    public let query: String
    public let action: String
    public let url: String?

    public init(id: String, query: String, action: String = "", url: String? = nil) {
        self.id = id
        self.query = query
        self.action = action
        self.url = url
    }
}

public struct CodexSubAgentActivity: Sendable, Hashable {
    public let id: String
    public let agentPath: String
    public let agentThreadID: String
    public let kind: String

    public init(id: String, agentPath: String, agentThreadID: String, kind: String) {
        self.id = id
        self.agentPath = agentPath
        self.agentThreadID = agentThreadID
        self.kind = kind
    }
}

public struct CodexItemEvent: Sendable, Hashable {
    public let item: CodexItem
    public let threadID: String
    public let turnID: String
    public let raw: Data

    public init(item: CodexItem, threadID: String, turnID: String, raw: Data = Data()) {
        self.item = item
        self.threadID = threadID
        self.turnID = turnID
        self.raw = raw
    }
}

public struct CodexTextDelta: Sendable, Hashable {
    public let itemID: String
    public let threadID: String
    public let turnID: String
    public let text: String

    public init(itemID: String, threadID: String, turnID: String, text: String) {
        self.itemID = itemID
        self.threadID = threadID
        self.turnID = turnID
        self.text = text
    }
}

public struct CodexTurn: Sendable, Hashable {
    public enum Status: String, Sendable, Hashable {
        case inProgress
        case completed
        case interrupted
        case failed
        case unknown
    }

    public let id: String
    public let threadID: String
    public let status: Status
    public let items: [CodexItem]
    public let errorMessage: String?
    public let errorCode: String?
    public let durationMS: Int?
    public let raw: Data

    public init(
        id: String,
        threadID: String,
        status: Status,
        items: [CodexItem] = [],
        errorMessage: String? = nil,
        errorCode: String? = nil,
        durationMS: Int? = nil,
        raw: Data = Data()
    ) {
        self.id = id
        self.threadID = threadID
        self.status = status
        self.items = items
        self.errorMessage = errorMessage
        self.errorCode = errorCode
        self.durationMS = durationMS
        self.raw = raw
    }

    public var succeeded: Bool { status == .completed }

    static func decode(_ json: JSONValue, threadID: String, raw: Data) -> CodexTurn {
        CodexTurn(
            id: json["id"]?.stringValue ?? "",
            threadID: threadID,
            status: Status(rawValue: json["status"]?.stringValue ?? "") ?? .unknown,
            items: (json["items"]?.arrayValue ?? []).compactMap(CodexItem.decode),
            errorMessage: json["error"]?["message"]?.stringValue,
            errorCode: json["error"]?["codexErrorInfo"]?.stringValue,
            durationMS: json["durationMs"]?.intValue,
            raw: raw
        )
    }
}

public struct CodexThreadStatus: Sendable, Hashable {
    public enum State: String, Sendable, Hashable {
        case notLoaded
        case idle
        case active
        case systemError
        case unknown
    }

    public let threadID: String
    public let state: State
    public let activeFlags: [String]

    public init(threadID: String, state: State, activeFlags: [String] = []) {
        self.threadID = threadID
        self.state = state
        self.activeFlags = activeFlags
    }

    public var isWaitingOnApproval: Bool { activeFlags.contains("waitingOnApproval") }
    public var isBusy: Bool { state == .active }
}

public struct CodexTokenUsage: Sendable, Hashable {
    public let threadID: String
    public let turnID: String
    public let inputTokens: Int
    public let cachedInputTokens: Int
    public let cacheWriteInputTokens: Int
    public let outputTokens: Int
    public let reasoningOutputTokens: Int
    public let totalTokens: Int
    public let contextWindow: Int

    public init(
        threadID: String = "",
        turnID: String = "",
        inputTokens: Int = 0,
        cachedInputTokens: Int = 0,
        cacheWriteInputTokens: Int = 0,
        outputTokens: Int = 0,
        reasoningOutputTokens: Int = 0,
        totalTokens: Int = 0,
        contextWindow: Int = 0
    ) {
        self.threadID = threadID
        self.turnID = turnID
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheWriteInputTokens = cacheWriteInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
        self.contextWindow = contextWindow
    }

    static func decode(_ json: JSONValue, threadID: String, turnID: String) -> CodexTokenUsage {
        let breakdown = json["last"] ?? .object([:])
        return CodexTokenUsage(
            threadID: threadID,
            turnID: turnID,
            inputTokens: breakdown["inputTokens"]?.intValue ?? 0,
            cachedInputTokens: breakdown["cachedInputTokens"]?.intValue ?? 0,
            cacheWriteInputTokens: breakdown["cacheWriteInputTokens"]?.intValue ?? 0,
            outputTokens: breakdown["outputTokens"]?.intValue ?? 0,
            reasoningOutputTokens: breakdown["reasoningOutputTokens"]?.intValue ?? 0,
            totalTokens: breakdown["totalTokens"]?.intValue ?? 0,
            contextWindow: json["modelContextWindow"]?.intValue ?? 0
        )
    }

    public var agentUsage: AgentUsage {
        AgentUsage(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            thinkingTokens: reasoningOutputTokens,
            costUSD: 0,
            contextTokens: contextWindow
        )
    }
}

public struct CodexTurnError: Sendable, Hashable {
    public let threadID: String
    public let turnID: String
    public let message: String
    public let willRetry: Bool
    public let raw: Data

    public init(threadID: String, turnID: String, message: String, willRetry: Bool, raw: Data = Data()) {
        self.threadID = threadID
        self.turnID = turnID
        self.message = message
        self.willRetry = willRetry
        self.raw = raw
    }
}

public enum CodexEvent: Sendable {
    case threadStarted(threadID: String, raw: Data)
    case threadStatus(CodexThreadStatus)
    case turnStarted(CodexTurn)
    case turnCompleted(CodexTurn)
    case itemStarted(CodexItemEvent)
    case itemCompleted(CodexItemEvent)
    case agentMessageDelta(CodexTextDelta)
    case reasoningDelta(CodexTextDelta)
    case planDelta(CodexTextDelta)
    case commandOutputDelta(CodexTextDelta)
    case tokenUsage(CodexTokenUsage)
    case rateLimits(Data)
    case approval(CodexApprovalRequest)
    case turnError(CodexTurnError)
    case closed(reason: String)
    case unknown(method: String, raw: Data)

    public var raw: Data {
        switch self {
        case .threadStarted(_, let raw): raw
        case .turnStarted(let turn), .turnCompleted(let turn): turn.raw
        case .itemStarted(let event), .itemCompleted(let event): event.raw
        case .approval(let request): request.raw
        case .turnError(let error): error.raw
        case .rateLimits(let raw): raw
        case .unknown(_, let raw): raw
        case .threadStatus, .agentMessageDelta, .reasoningDelta, .planDelta, .commandOutputDelta,
             .tokenUsage, .closed:
            Data()
        }
    }

    public var threadID: String? {
        switch self {
        case .threadStarted(let id, _): id
        case .threadStatus(let status): status.threadID
        case .turnStarted(let turn), .turnCompleted(let turn): turn.threadID
        case .itemStarted(let event), .itemCompleted(let event): event.threadID
        case .agentMessageDelta(let delta), .reasoningDelta(let delta),
             .planDelta(let delta), .commandOutputDelta(let delta):
            delta.threadID
        case .tokenUsage(let usage): usage.threadID
        case .approval(let request): request.threadID
        case .turnError(let error): error.threadID
        case .rateLimits, .closed, .unknown: nil
        }
    }

    public var isTranscriptRow: Bool {
        switch self {
        case .agentMessageDelta, .reasoningDelta, .planDelta, .commandOutputDelta,
             .threadStatus, .tokenUsage, .threadStarted:
            false
        default: true
        }
    }

    public static func decode(_ notification: CodexServerNotification) -> CodexEvent {
        let params = notification.params
        let raw = notification.raw
        let threadID = params["threadId"]?.stringValue ?? ""
        let turnID = params["turnId"]?.stringValue ?? ""

        switch notification.method {
        case "thread/started":
            return .threadStarted(
                threadID: params["thread"]?["id"]?.stringValue ?? threadID,
                raw: raw
            )

        case "thread/status/changed":
            let status = params["status"] ?? .object([:])
            return .threadStatus(CodexThreadStatus(
                threadID: threadID,
                state: CodexThreadStatus.State(rawValue: status["type"]?.stringValue ?? "") ?? .unknown,
                activeFlags: (status["activeFlags"] ?? .null).stringArray
            ))

        case "turn/started":
            return .turnStarted(CodexTurn.decode(params["turn"] ?? .null, threadID: threadID, raw: raw))

        case "turn/completed":
            return .turnCompleted(CodexTurn.decode(params["turn"] ?? .null, threadID: threadID, raw: raw))

        case "item/started", "item/completed":
            guard let item = CodexItem.decode(params["item"] ?? .null) else {
                return .unknown(method: notification.method, raw: raw)
            }
            let event = CodexItemEvent(item: item, threadID: threadID, turnID: turnID, raw: raw)
            return notification.method == "item/started" ? .itemStarted(event) : .itemCompleted(event)

        case "item/agentMessage/delta":
            return .agentMessageDelta(delta(params, text: params["delta"]?.stringValue))

        case "item/reasoning/summaryTextDelta", "item/reasoning/textDelta":
            return .reasoningDelta(delta(params, text: params["delta"]?.stringValue))

        case "item/plan/delta":
            return .planDelta(delta(params, text: params["delta"]?.stringValue))

        case "item/commandExecution/outputDelta", "item/fileChange/outputDelta":
            return .commandOutputDelta(delta(params, text: params["delta"]?.stringValue))

        case "thread/tokenUsage/updated":
            return .tokenUsage(CodexTokenUsage.decode(
                params["tokenUsage"] ?? .null,
                threadID: threadID,
                turnID: turnID
            ))

        case "account/rateLimits/updated":
            return .rateLimits(raw)

        case "error":
            return .turnError(CodexTurnError(
                threadID: threadID,
                turnID: turnID,
                message: params["error"]?["message"]?.stringValue ?? "",
                willRetry: params["willRetry"]?.boolValue ?? false,
                raw: raw
            ))

        default:
            return .unknown(method: notification.method, raw: raw)
        }
    }

    private static func delta(_ params: JSONValue, text: String?) -> CodexTextDelta {
        CodexTextDelta(
            itemID: params["itemId"]?.stringValue ?? "",
            threadID: params["threadId"]?.stringValue ?? "",
            turnID: params["turnId"]?.stringValue ?? "",
            text: text ?? ""
        )
    }
}

public struct CodexApprovalRequest: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case commandExecution
        case fileChange
        case permissions
        case mcpElicitation
        case toolUserInput

        init?(method: String) {
            switch method {
            case "item/commandExecution/requestApproval": self = .commandExecution
            case "item/fileChange/requestApproval": self = .fileChange
            case "item/permissions/requestApproval": self = .permissions
            case "mcpServer/elicitation/request": self = .mcpElicitation
            case "item/tool/requestUserInput": self = .toolUserInput
            default: return nil
            }
        }
    }

    public let id: CodexRequestID
    public let kind: Kind
    public let threadID: String
    public let turnID: String
    public let itemID: String
    public let params: JSONValue
    public let raw: Data

    public init(
        id: CodexRequestID,
        kind: Kind,
        threadID: String,
        turnID: String,
        itemID: String,
        params: JSONValue,
        raw: Data = Data()
    ) {
        self.id = id
        self.kind = kind
        self.threadID = threadID
        self.turnID = turnID
        self.itemID = itemID
        self.params = params
        self.raw = raw
    }

    public static func decode(_ request: CodexServerRequest) -> CodexApprovalRequest? {
        guard let kind = Kind(method: request.method) else { return nil }
        return CodexApprovalRequest(
            id: request.id,
            kind: kind,
            threadID: request.params["threadId"]?.stringValue ?? "",
            turnID: request.params["turnId"]?.stringValue ?? "",
            itemID: request.params["itemId"]?.stringValue ?? "",
            params: request.params,
            raw: request.raw
        )
    }

    public var command: String? { params["command"]?.stringValue }
}

public enum CodexApprovalDecision: String, Sendable, Hashable, CaseIterable {
    case accept
    case acceptForSession
    case decline
    case cancel

    public func result(for kind: CodexApprovalRequest.Kind) -> JSONValue {
        switch kind {
        case .commandExecution, .fileChange:
            return .object(["decision": .string(rawValue)])

        case .mcpElicitation:
            let action = self == .acceptForSession ? Self.accept : self
            return .object(["action": .string(action == .cancel ? "cancel" : action.rawValue)])

        case .toolUserInput:
            return .object(["answers": .object([:])])

        case .permissions:
            return .object([
                "permissions": .object([:]),
                "scope": .string(self == .acceptForSession ? "session" : "turn"),
            ])
        }
    }
}
