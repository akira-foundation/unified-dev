import Foundation

public struct PermissionRule: Sendable, Hashable, Codable {
    public var toolName: String
    public var ruleContent: String?

    public init(toolName: String, ruleContent: String? = nil) {
        self.toolName = toolName
        self.ruleContent = ruleContent
    }

    public var displayText: String {
        guard let ruleContent, !ruleContent.isEmpty else { return toolName }
        return "\(toolName)(\(ruleContent))"
    }

    public var isWholeTool: Bool { ruleContent?.isEmpty ?? true }

    public static func decode(_ json: JSONValue) -> PermissionRule? {
        guard let toolName = json["toolName"]?.stringValue, !toolName.isEmpty else { return nil }
        return PermissionRule(toolName: toolName, ruleContent: json["ruleContent"]?.stringValue)
    }
}

public struct PermissionSuggestion: Sendable, Hashable {
    public var type: String
    public var behavior: String
    public var destination: String
    public var rules: [PermissionRule]
    public var raw: JSONValue

    public init(
        type: String,
        behavior: String = "",
        destination: String = "",
        rules: [PermissionRule] = [],
        raw: JSONValue = .object([:])
    ) {
        self.type = type
        self.behavior = behavior
        self.destination = destination
        self.rules = rules
        self.raw = raw
    }

    public var isAllowRules: Bool { type == "addRules" && behavior == "allow" && !rules.isEmpty }

    public static func decode(_ json: JSONValue) -> PermissionSuggestion? {
        guard let type = json["type"]?.stringValue else { return nil }
        return PermissionSuggestion(
            type: type,
            behavior: json["behavior"]?.stringValue ?? "",
            destination: json["destination"]?.stringValue ?? "",
            rules: (json["rules"]?.arrayValue ?? []).compactMap(PermissionRule.decode),
            raw: json
        )
    }

    public func aimed(at destination: PermissionDestination) -> PermissionSuggestion {
        var copy = self
        copy.destination = destination.rawValue
        if case .object(var object) = raw {
            object["destination"] = .string(destination.rawValue)
            copy.raw = .object(object)
        }
        return copy
    }
}

public enum PermissionDestination: String, Sendable, Hashable, CaseIterable, Codable {
    case userSettings
    case projectSettings
    case localSettings
    case session
    case cliArg
}

public struct PermissionAsk: Sendable, Hashable, Identifiable {
    public var requestID: String
    public var toolName: String
    public var displayName: String
    public var toolUseID: String
    public var input: JSONValue
    public var summary: String
    public var reason: String
    public var reasonType: String
    public var blockedPath: String?
    public var suggestions: [PermissionSuggestion]
    public var suppressesAlwaysAllow: Bool
    public var requiresUserInteraction: Bool
    public var classifierApprovable: Bool?
    public var implementationMode: PermissionMode?
    public var raw: Data

    public var id: String { requestID }

    public init(
        requestID: String,
        toolName: String,
        displayName: String = "",
        toolUseID: String = "",
        input: JSONValue = .object([:]),
        summary: String = "",
        reason: String = "",
        reasonType: String = "",
        blockedPath: String? = nil,
        suggestions: [PermissionSuggestion] = [],
        suppressesAlwaysAllow: Bool = false,
        requiresUserInteraction: Bool = false,
        classifierApprovable: Bool? = nil,
        implementationMode: PermissionMode? = nil,
        raw: Data = Data()
    ) {
        self.requestID = requestID
        self.toolName = toolName
        self.displayName = displayName
        self.toolUseID = toolUseID
        self.input = input
        self.summary = summary
        self.reason = reason
        self.reasonType = reasonType
        self.blockedPath = blockedPath
        self.suggestions = suggestions
        self.suppressesAlwaysAllow = suppressesAlwaysAllow
        self.requiresUserInteraction = requiresUserInteraction
        self.classifierApprovable = classifierApprovable
        self.implementationMode = implementationMode
        self.raw = raw
    }

    public var label: String { displayName.isEmpty ? toolName : displayName }

    public var allowSuggestion: PermissionSuggestion? {
        let allows = suggestions.filter(\.isAllowRules)
        if allows.count == 1 { return allows[0] }
        let ownTool = allows.filter { suggestion in
            suggestion.rules.allSatisfy { $0.toolName == toolName }
        }
        return ownTool.count == 1 ? ownTool[0] : nil
    }

    public var rules: [PermissionRule] { allowSuggestion?.rules ?? [] }

    public var ruleText: String {
        rules.map(\.displayText).joined(separator: ", ")
    }

    public var isQuestion: Bool { AgentQuestionnaire.isQuestion(toolName: toolName) }

    public var isPlanApproval: Bool { toolName == "ExitPlanMode" }

    public var canWiden: Bool {
        !isQuestion && !isPlanApproval && !rules.isEmpty && !suppressesAlwaysAllow && !requiresUserInteraction
            && !BridgeToolApproval.crossesProfile(toolName: toolName, input: input)
    }

    public var subject: String {
        ToolLiteral.of(name: toolName, input: input) ?? blockedPath ?? summary
    }

    public var subjectIsCode: Bool {
        ToolLiteral.isCode(name: toolName, input: input) || blockedPath != nil
    }

    public static func decode(_ json: JSONValue, raw: Data) -> PermissionAsk? {
        guard json["type"]?.stringValue == "control_request",
              let requestID = json["request_id"]?.stringValue,
              let request = json["request"],
              request["subtype"]?.stringValue == "can_use_tool",
              let toolName = request["tool_name"]?.stringValue
        else {
            return nil
        }

        return PermissionAsk(
            requestID: requestID,
            toolName: toolName,
            displayName: request["display_name"]?.stringValue ?? "",
            toolUseID: request["tool_use_id"]?.stringValue ?? "",
            input: request["input"] ?? .object([:]),
            summary: AgentExit.stripEscapes(request["description"]?.stringValue ?? ""),
            reason: AgentExit.stripEscapes(request["decision_reason"]?.stringValue ?? ""),
            reasonType: request["decision_reason_type"]?.stringValue ?? "",
            blockedPath: request["blocked_path"]?.stringValue,
            suggestions: (request["permission_suggestions"]?.arrayValue ?? [])
                .compactMap(PermissionSuggestion.decode),
            suppressesAlwaysAllow: request["suppress_always_allow_rule"]?.boolValue ?? false,
            requiresUserInteraction: request["requires_user_interaction"]?.boolValue ?? false,
            classifierApprovable: request["classifier_approvable"]?.boolValue,
            implementationMode: json["ud_implementation_mode"]?.stringValue.flatMap(PermissionMode.init(rawValue:)),
            raw: raw
        )
    }

    public static func decode(payload: Data) -> PermissionAsk? {
        guard let json = JSONValue.parse(payload) else { return nil }
        return decode(json, raw: payload)
    }
}

public enum PermissionScope: String, Sendable, Hashable, CaseIterable, Codable {
    case once
    case session
    case project

    public var buttonLabel: String {
        switch self {
        case .once: "Allow once"
        case .session: "Allow for this session"
        case .project: "Always allow"
        }
    }

    public func consequence(rule: String, project: String) -> String {
        switch self {
        case .once:
            "Just this call. Nothing is remembered and the same question can come back."
        case .session:
            "Any \(rule) for the rest of this session. Forgotten when the agent stops."
        case .project:
            "Any \(rule) in \(project), in every workspace, until you revoke it."
        }
    }
}

public enum PermissionDecision: Sendable, Hashable {
    case allow(scope: PermissionScope)
    case answer(input: JSONValue)
    case approvePlan(mode: PermissionMode)
    case deny(message: String, endsTurn: Bool)

    public static let defaultDenyMessage =
        "Permission was not granted for this call. Do not try it again. "
        + "Carry on with everything else you can do without it, and say at the end what you skipped."

    public static let quittingMessage =
        "Unified Dev is closing this session, so this could not be answered. Stop here."

    public static let stoppedMessage =
        "The turn was stopped before this could be answered."

    public static let repliedInChatMessage =
        "The user replied in the chat instead of answering this. Read their message first, "
        + "and ask again only if it still matters after it."

    public static let repliedInChat = PermissionDecision.deny(message: repliedInChatMessage, endsTurn: false)

    public var isAllow: Bool {
        switch self {
        case .allow, .answer, .approvePlan: true
        case .deny: false
        }
    }

    public var label: String {
        switch self {
        case .allow(.once): "allowed once"
        case .allow(.session): "allowed for the session"
        case .allow(.project): "always allowed"
        case .answer: "answered"
        case .approvePlan: "approved for implementation"
        case .deny: "denied"
        }
    }

    public static let answeredName = "answered"

    public var answers: [String: String] {
        guard case .answer(let input) = self else { return [:] }
        return AgentQuestionnaire.masked(
            AgentQuestionnaire.answers(in: input), forQuestionsIn: input
        )
    }

    public var storedName: String {
        switch self {
        case .allow(let scope): "allow-\(scope.rawValue)"
        case .answer: Self.answeredName
        case .approvePlan(let mode): "approve-plan-\(mode.rawValue)"
        case .deny(_, let endsTurn): endsTurn ? "deny-stop" : "deny"
        }
    }
}

public enum PermissionAnswer {
    public static func encode(ask: PermissionAsk, decision: PermissionDecision, orchestrates: Bool = false) throws -> String {
        var response: [String: JSONValue] = [:]

        switch decision {
        case .approvePlan(let mode):
            guard ask.isPlanApproval, PlanApproval.modes.contains(mode) else {
                throw PlanApprovalError.invalidDecision
            }
            response["behavior"] = .string("allow")
            response["updatedInput"] = ask.input
            response["updatedPermissions"] = .array([.object([
                "type": .string("setMode"),
                "mode": .string(OrchestratorToolGuard.claudeMode(mode, orchestrates: orchestrates)),
                "destination": .string("session"),
            ])])
            response["decision"] = .string("user_temporary")

        case .answer(let input):
            response["behavior"] = .string("allow")
            response["updatedInput"] = input
            response["decision"] = .string("user_temporary")

        case .allow(let scope):
            response["behavior"] = .string("allow")
            response["updatedInput"] = ask.input
            if scope != .once, ask.canWiden, let suggestion = ask.allowSuggestion {
                response["updatedPermissions"] = .array([suggestion.aimed(at: .session).raw])
            }
            response["decision"] = .string(scope == .once ? "user_temporary" : "user_permanent")

        case .deny(let message, let endsTurn):
            response["behavior"] = .string("deny")
            let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
            response["message"] = .string(text.isEmpty ? PermissionDecision.defaultDenyMessage : text)
            response["interrupt"] = .bool(endsTurn)
            response["decision"] = .string("user_reject")
        }

        let envelope = JSONValue.object([
            "type": .string("control_response"),
            "response": .object([
                "subtype": .string("success"),
                "request_id": .string(ask.requestID),
                "response": .object(response),
            ]),
        ])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return String(decoding: try encoder.encode(envelope), as: UTF8.self)
    }
}

public extension PermissionAsk {
    func standing(in decisions: [String: String], inWorkspace: Bool) -> String? {
        if let decision = decisions[requestID] { return decision }
        return wasAnsweredByTheRunner(inWorkspace: inWorkspace) ? PermissionAskOutcome.selfApproved : nil
    }

    private func wasAnsweredByTheRunner(inWorkspace: Bool) -> Bool {
        guard BridgeToolApproval.isSelfApproved(toolName: toolName, input: input, inWorkspace: inWorkspace)
        else { return false }
        return JSONValue.parse(raw)?["agent_kind"] == nil
    }
}
