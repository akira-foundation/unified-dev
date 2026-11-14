import Foundation

public enum ACPEvent: Sendable, Hashable {
    case sessionReady(ACPSession)
    case update(ACPSessionUpdate)
    case permission(ACPPermissionRequest)
    case promptCompleted(ACPPromptResult)
    case closed(reason: String)
    case unknown(method: String, raw: Data)

    public var sessionID: String? {
        switch self {
        case .sessionReady(let session): session.id
        case .update(let update): update.sessionID
        case .permission(let request): request.sessionID
        case .promptCompleted(let result): result.sessionID
        case .closed, .unknown: nil
        }
    }
}

public struct ACPSession: Sendable, Hashable {
    public let id: String
    public let models: [ACPModel]
    public let currentModelID: String
    public let raw: Data

    public init(id: String, models: [ACPModel] = [], currentModelID: String = "", raw: Data = Data()) {
        self.id = id
        self.models = models
        self.currentModelID = currentModelID
        self.raw = raw
    }

    public static func decode(_ json: JSONValue, raw: Data = Data()) -> ACPSession? {
        guard let id = json["sessionId"]?.stringValue, !id.isEmpty else { return nil }
        let modelsJSON = json["models"] ?? json["_meta"]?["modelState"] ?? .null
        return ACPSession(
            id: id,
            models: ACPModel.decodeList(modelsJSON),
            currentModelID: modelsJSON["currentModelId"]?.stringValue ?? "",
            raw: raw
        )
    }
}

public struct ACPSessionUpdate: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case text(String)
        case thought(String)
        case toolCall(ACPToolCall)
        case toolCallUpdate(ACPToolCall)
        case usage(used: Int, size: Int)
        case other(String)
    }

    public let sessionID: String
    public let kind: Kind
    public let raw: JSONValue

    public static func decode(params: JSONValue) -> ACPSessionUpdate? {
        let update = params["update"] ?? params
        guard let type = update["sessionUpdate"]?.stringValue else { return nil }
        let sessionID = params["sessionId"]?.stringValue ?? ""
        let kind: Kind
        switch type {
        case "agent_message_chunk":
            kind = .text(Self.contentText(update["content"]))
        case "agent_thought_chunk":
            kind = .thought(Self.contentText(update["content"]))
        case "tool_call":
            kind = .toolCall(ACPToolCall.decode(update, isUpdate: false))
        case "tool_call_update":
            kind = .toolCallUpdate(ACPToolCall.decode(update, isUpdate: true))
        case "usage_update":
            kind = .usage(
                used: update["used"]?.intValue ?? 0,
                size: update["size"]?.intValue ?? 0
            )
        default:
            kind = .other(type)
        }
        return ACPSessionUpdate(sessionID: sessionID, kind: kind, raw: update)
    }

    static func contentText(_ json: JSONValue?) -> String {
        json?["text"]?.stringValue ?? json?.stringValue ?? ""
    }
}

public struct ACPToolCall: Sendable, Hashable {
    public let id: String
    public let title: String
    public let kind: String
    public let status: String
    public let toolName: String
    public let rawInput: JSONValue
    public let rawOutput: JSONValue
    public let contentText: String
    public let path: String
    public let json: JSONValue

    public static func decode(_ json: JSONValue, isUpdate: Bool) -> ACPToolCall {
        let locations = json["locations"]?.arrayValue ?? []
        let path = json["rawInput"]?["path"]?.stringValue
            ?? json["rawInput"]?["file_path"]?.stringValue
            ?? locations.first?["path"]?.stringValue
            ?? ""
        return ACPToolCall(
            id: json["toolCallId"]?.stringValue ?? "",
            title: json["title"]?.stringValue ?? "",
            kind: json["kind"]?.stringValue ?? "",
            status: json["status"]?.stringValue ?? (isUpdate ? "" : "pending"),
            toolName: json["toolName"]?.stringValue ?? json["name"]?.stringValue ?? "",
            rawInput: json["rawInput"] ?? .object([:]),
            rawOutput: json["rawOutput"] ?? .null,
            contentText: contentText(json["content"]),
            path: path,
            json: json
        )
    }

    static func contentText(_ json: JSONValue?) -> String {
        guard let items = json?.arrayValue else {
            return json?["text"]?.stringValue ?? json?.stringValue ?? ""
        }
        return items.compactMap { item in
            if let text = item["content"]?["text"]?.stringValue { return text }
            if let text = item["text"]?.stringValue { return text }
            if item["type"]?.stringValue == "diff", let path = item["path"]?.stringValue {
                return path
            }
            return nil
        }.joined(separator: "\n")
    }

    public var isFinished: Bool {
        status == "completed" || status == "failed" || status == "cancelled"
    }

    public var isError: Bool {
        status == "failed" || status == "cancelled"
    }
}

public struct ACPPromptResult: Sendable, Hashable {
    public let requestID: ACPRequestID
    public let sessionID: String
    public let stopReason: String
    public let raw: JSONValue

    public init(
        requestID: ACPRequestID,
        sessionID: String,
        stopReason: String,
        raw: JSONValue
    ) {
        self.requestID = requestID
        self.sessionID = sessionID
        self.stopReason = stopReason
        self.raw = raw
    }

    public var wasCancelled: Bool { stopReason == "cancelled" }
    public var isError: Bool {
        stopReason == "refusal" || stopReason == "max_tokens" || stopReason == "max_turn_requests"
    }
}

public struct ACPPermissionOption: Sendable, Hashable {
    public let id: String
    public let name: String
    public let kind: String

    public static func decode(_ json: JSONValue) -> ACPPermissionOption? {
        guard let id = json["optionId"]?.stringValue, !id.isEmpty else { return nil }
        return ACPPermissionOption(
            id: id,
            name: json["name"]?.stringValue ?? id,
            kind: json["kind"]?.stringValue ?? ""
        )
    }

    public var isAllow: Bool { kind.hasPrefix("allow") }
    public var isAlways: Bool { kind == "allow_always" || kind == "reject_always" }
}

public struct ACPPermissionRequest: Sendable, Hashable {
    public let id: ACPRequestID
    public let sessionID: String
    public let toolCall: ACPToolCall
    public let options: [ACPPermissionOption]
    public let raw: Data

    public static func decode(_ request: ACPServerRequest) -> ACPPermissionRequest? {
        guard request.method == "session/request_permission" else { return nil }
        let toolJSON = request.params["toolCall"] ?? .object([:])
        let options = (request.params["options"]?.arrayValue ?? []).compactMap(ACPPermissionOption.decode)
        return ACPPermissionRequest(
            id: request.id,
            sessionID: request.params["sessionId"]?.stringValue ?? "",
            toolCall: ACPToolCall.decode(toolJSON, isUpdate: false),
            options: options,
            raw: request.raw
        )
    }
}
