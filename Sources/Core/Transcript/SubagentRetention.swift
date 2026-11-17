import Foundation

public enum SubagentRetention: Sendable {
    public static let lingerSeconds: Double = 2.5

    public static let failureLimit = 3

    public static func rows(
        _ roster: SubagentRoster, now: Date, opened: SubagentID? = nil
    ) -> [SubagentRow] {
        var failuresKept = 0
        return roster.subagents.compactMap { subagent in
            guard keeps(subagent, now: now, opened: opened, failuresKept: &failuresKept) else {
                return nil
            }
            return SubagentRow(subagent)
        }
    }

    public static func failureCount(_ roster: SubagentRoster) -> Int {
        roster.subagents.count { $0.kind == .agent && $0.state == .failed }
    }

    public static func nextChange(
        _ roster: SubagentRoster, now: Date, opened: SubagentID? = nil
    ) -> Date? {
        var failuresKept = 0
        var earliest: Date?
        for subagent in roster.subagents {
            guard keeps(subagent, now: now, opened: opened, failuresKept: &failuresKept) else {
                continue
            }
            guard let expiry = expiry(of: subagent, opened: opened) else { continue }
            earliest = min(earliest ?? expiry, expiry)
        }
        return earliest
    }

    private static func keeps(
        _ subagent: Subagent, now: Date, opened: SubagentID?, failuresKept: inout Int
    ) -> Bool {
        guard subagent.kind == .agent else { return false }

        if subagent.state == .failed {
            let kept = subagent.id == opened || failuresKept < failureLimit
            if kept { failuresKept += 1 }
            return kept
        }
        guard let expiry = expiry(of: subagent, opened: opened) else { return true }
        return now < expiry
    }

    private static func expiry(of subagent: Subagent, opened: SubagentID?) -> Date? {
        guard subagent.state != .running, subagent.id != opened else { return nil }
        guard subagent.state != .failed else { return nil }
        guard let finishedAt = subagent.finishedAt else { return nil }
        return finishedAt.addingTimeInterval(lingerSeconds)
    }
}
