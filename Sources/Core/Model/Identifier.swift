import Foundation

public protocol Identifier: Hashable, Sendable, Codable, RawRepresentable,
                            CustomStringConvertible, Comparable
where RawValue == String {
    init(_ rawValue: String)
}

extension Identifier {
    public init(rawValue: String) { self.init(rawValue) }

    public var description: String { rawValue }

    public static func new() -> Self { Self(newID()) }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct UsageMetricID: Identifier {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct RepoID: Identifier {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct WorkspaceID: Identifier {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct SessionID: Identifier {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct TerminalTabID: Identifier {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct ReviewCommentID: Identifier {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct ReplyQuoteID: Identifier {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct QuickPromptID: Identifier {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct ModelPresetID: Identifier {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct DeliveryID: Identifier {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct PermissionGrantID: Identifier {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct SubagentID: Identifier {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct WorkSuggestionID: Identifier {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct AgentAccountID: Identifier {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct SessionSegmentID: Identifier {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct InboxNotificationID: Identifier {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct ProfileID: Identifier {
    public static let initial = ProfileID("unified")

    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}
