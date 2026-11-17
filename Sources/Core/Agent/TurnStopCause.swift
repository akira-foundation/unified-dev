import Foundation

public enum TurnStopCause: Sendable, Equatable {
    case usageLimit
    case other

    static let measuredSyntheticModel = "<synthetic>"
    static let measuredError = "rate_limit"
    static let measuredStatus = 429
    static let measuredWords = "You've hit your"
    static let measuredAPIError = "usage_limit_reached"
    static let codexErrorField = "codex_error"
    static let codexUsageLimit = "usageLimitExceeded"

    public static func ofLastTurn(messages: [Message], agent: AgentKind) -> TurnStopCause {
        let rows = messages.sorted { $0.seq < $1.seq }
        let turn = rows.reversed().prefix { !$0.kind.opensTurn }
        switch agent {
        case .claudeCode:
            guard let last = turn.first(where: { carriesOutput($0) || isResumeMark($0) }),
                  !isResumeMark(last) else { return .other }
            return reportsClaudeUsageLimit(last) ? .usageLimit : .other
        case .codex:
            guard let last = turn.first(where: { carriesOutput($0) || isResumeMark($0) || $0.kind == .result }),
                  !isResumeMark(last) else { return .other }
            return reportsCodexUsageLimit(last) ? .usageLimit : .other
        case .grok, .antigravity, .cursor, .openCode:
            return .other
        }
    }

    static func noModelWrote(_ line: JSONValue) -> Bool {
        hasSyntheticModel(line) || isAPIError(line)
    }

    private static func hasSyntheticModel(_ line: JSONValue) -> Bool {
        line["message"]?["model"]?.stringValue == measuredSyntheticModel
    }

    private static func isAPIError(_ line: JSONValue) -> Bool {
        line["is_api_error_message"]?.boolValue == true
    }

    private static func isResumeMark(_ row: Message) -> Bool {
        row.kind == .handoff && HandoffMark.decode(row.payload) == .resuming
    }

    private static func carriesOutput(_ row: Message) -> Bool {
        switch row.kind {
        case .assistantText, .thinking, .toolUse, .toolResult, .permissionAsk: true
        default: false
        }
    }

    private static func reportsCodexUsageLimit(_ row: Message) -> Bool {
        guard row.kind == .result, let json = JSONValue.parse(row.payload) else { return false }
        return json["type"]?.stringValue == "result"
            && json["is_error"]?.boolValue == true
            && json[codexErrorField]?.stringValue == codexUsageLimit
    }

    private static func reportsClaudeUsageLimit(_ row: Message) -> Bool {
        guard row.kind == .assistantText,
              let json = JSONValue.parse(row.payload),
              json["type"]?.stringValue == "assistant",
              hasSyntheticModel(json),
              json["error"]?.stringValue == measuredError
        else { return false }
        if let typed = json["api_error"]?.stringValue { return typed == measuredAPIError }
        guard isAPIError(json),
              json["api_error_status"]?.intValue == measuredStatus,
              let text = json["message"]?["content"]?[0]?["text"]?.stringValue
        else { return false }
        return text.range(of: measuredWords, options: [.anchored, .caseInsensitive]) != nil
            && text.localizedCaseInsensitiveContains("limit")
    }
}
