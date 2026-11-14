import Foundation

public struct ACPDialect: Sendable, Hashable {
    public let kind: AgentKind
    public let subcommand: [String]
    public let transport: [String]
    public let approveEverythingFlag: String
    public let modelFlag: String?
    public let effortFlag: String?
    public let quietEnvironment: [String: String]
    public let effortOption: String?
    public let wrapsConfigValues: Bool
    public let sendsSessionMeta: Bool
    public let setsMode: Bool

    public static let grok = ACPDialect(
        kind: .grok,
        subcommand: ["agent"],
        transport: ["--no-leader", "stdio"],
        approveEverythingFlag: "--always-approve",
        modelFlag: "--model",
        effortFlag: "--reasoning-effort",
        quietEnvironment: ["GROK_DISABLE_AUTOUPDATER": "1"],
        effortOption: "reasoning_effort",
        wrapsConfigValues: true,
        sendsSessionMeta: true,
        setsMode: false
    )

    public static func speaking(_ kind: AgentKind) -> ACPDialect? {
        [grok, antigravity].first { $0.kind == kind }
    }

    public static let antigravity = ACPDialect(
        kind: .antigravity,
        subcommand: ["acp"],
        transport: [],
        approveEverythingFlag: "--dangerously-skip-permissions",
        modelFlag: nil,
        effortFlag: nil,
        quietEnvironment: ["AGY_CLI_DISABLE_AUTO_UPDATE": "true"],
        effortOption: nil,
        wrapsConfigValues: false,
        sendsSessionMeta: false,
        setsMode: true
    )

    public var name: String { kind.label }

    public func arguments(model: String, effort: String, alwaysApprove: Bool) -> [String] {
        var arguments = subcommand
        if alwaysApprove { arguments.append(approveEverythingFlag) }
        if let modelFlag, !model.isEmpty { arguments += [modelFlag, model] }
        if let effortFlag, !effort.isEmpty { arguments += [effortFlag, effort] }
        return arguments + transport
    }

    public func configValue(_ value: String) -> JSONValue {
        wrapsConfigValues ? .object(["value": .string(value)]) : .string(value)
    }

    public func mode(for permissionMode: PermissionMode, asksEveryCall: Bool) -> String? {
        guard setsMode else { return nil }
        if asksEveryCall { return "default" }
        return switch permissionMode {
        case .acceptEdits: "accept-edits"
        case .auto, .autoReview, .bypassPermissions: "auto"
        case .plan: "plan"
        }
    }
}
