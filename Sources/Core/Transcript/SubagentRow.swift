import Foundation

public struct SubagentRow: Sendable, Hashable, Identifiable {
    public enum Mark: Sendable, Hashable {
        case working
        case done
        case failed
        case stopped

        public var word: String {
            switch self {
            case .working: "Working"
            case .done: "Finished"
            case .failed: "Failed"
            case .stopped: "Stopped"
            }
        }
    }

    public enum Detail: Sendable, Hashable {
        case elapsed(since: Date)
        case retrying(AgentRetry)
        case summary(String)
        case none

        public var workingSince: Date? {
            guard case .elapsed(let since) = self else { return nil }
            return since
        }

        public func text(at now: Date) -> String {
            switch self {
            case .elapsed(let since): SubagentRow.duration(max(0, Int(now.timeIntervalSince(since))))
            case .retrying(let retry): retry.readout
            case .summary(let summary): summary
            case .none: ""
            }
        }
    }

    public let id: SubagentID
    public let title: String
    public let mark: Mark
    public let detail: Detail
    public let opensOutput: Bool
    let spokenState: String

    static let detailLimit = 28

    public static func rows(_ roster: SubagentRoster) -> [SubagentRow] {
        roster.subagents.map { SubagentRow($0) }
    }

    public init(_ subagent: Subagent) {
        id = subagent.id
        title = Self.title(of: subagent)
        mark = switch subagent.state {
        case .running: .working
        case .completed: .done
        case .failed: .failed
        case .stopped: .stopped
        }
        detail = Self.detail(of: subagent)
        opensOutput = subagent.kind == .agent || subagent.hasOutput
        spokenState = Self.spokenState(of: subagent)
    }

    public func spokenValue(at now: Date) -> String {
        let text = detail.text(at: now)
        return text.isEmpty ? spokenState : "\(spokenState), \(text)"
    }

    public static func title(of subagent: Subagent) -> String {
        let description = subagent.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty { return description }
        let type = subagent.type.trimmingCharacters(in: .whitespacesAndNewlines)
        return type.isEmpty ? "Subagent" : type
    }

    static func detail(of subagent: Subagent) -> Detail {
        switch subagent.state {
        case .running:
            if let retry = subagent.retry { return .retrying(retry) }
            return .elapsed(since: subagent.workingSince)
        case .completed, .failed, .stopped:
            let summary = shorten(subagent.summary)
            return summary.isEmpty ? .none : .summary(summary)
        }
    }

    static func shorten(_ text: String) -> String {
        let line = text
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard line.count > detailLimit else { return line }
        let cut = line.index(line.startIndex, offsetBy: detailLimit)
        let head = line[line.startIndex..<cut]
        if let space = head.lastIndex(of: " "), head.distance(from: space, to: head.endIndex) < 10 {
            return head[head.startIndex..<space].trimmingCharacters(in: .whitespaces) + "..."
        }
        return head.trimmingCharacters(in: .whitespaces) + "..."
    }

    public static func duration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        guard seconds >= 60 else { return "\(seconds)s" }
        let minutes = seconds / 60
        guard minutes < 60 else { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m \(seconds % 60)s"
    }

    static func spokenState(of subagent: Subagent) -> String {
        switch subagent.state {
        case .running: subagent.retry == nil ? "working" : "working, being retried"
        case .completed: "finished"
        case .failed: "failed"
        case .stopped: "stopped"
        }
    }
}
