import Foundation

public enum SubagentPane: Sendable {
    public static let refreshSeconds: Double = 1.0

    public static func refreshes(_ subagent: Subagent?) -> Bool {
        subagent?.state == .running
    }

    private static let notPrintedYet = "It has not printed anything yet."

    public static func nothingToShow(
        _ failure: SubagentOutput.Failure, kind: SubagentKind, isRunning: Bool
    ) -> String {
        guard isRunning else { return failure.sentence(kind) }
        switch kind {
        case .agent: return "It has not said anything yet."
        case .command: return notPrintedYet
        }
    }

    public static func subtitle(_ subagent: Subagent, now: Date = Date()) -> String {
        var parts: [String] = []
        switch subagent.kind {
        case .command:
            parts.append(subagent.kind.noun)
        case .agent:
            let type = subagent.type.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append(type.isEmpty ? subagent.kind.noun : type)
            if subagent.spawnDepth > 1 {
                parts.append("spawned by a subagent, depth \(subagent.spawnDepth)")
            }
        }
        let elapsed = SubagentRow.duration(subagent.secondsElapsed(at: now))
        if !elapsed.isEmpty { parts.append(elapsed) }
        return parts.joined(separator: " · ")
    }

    public struct Fact: Sendable, Hashable, Identifiable {
        public let label: String
        public let value: String

        public var id: String { label }
    }

    public static func status(_ subagent: Subagent, now: Date = Date()) -> String {
        subagent.state == .running ? "Running" : SubagentRow(subagent).mark.word
    }

    public static func facts(_ subagent: Subagent, now: Date = Date()) -> [Fact] {
        let type = subagent.type.trimmingCharacters(in: .whitespacesAndNewlines)
        var facts = [
            Fact(label: "Status", value: status(subagent, now: now)),
            Fact(label: "Type", value: subagent.kind == .agent && !type.isEmpty ? type : subagent.kind.title),
        ]
        if subagent.kind == .agent, subagent.spawnDepth > 1 {
            facts.append(Fact(label: "Spawned at depth", value: String(subagent.spawnDepth)))
        }
        let elapsed = SubagentRow.duration(subagent.secondsElapsed(at: now))
        if !elapsed.isEmpty { facts.append(Fact(label: "Duration", value: elapsed)) }
        return facts
    }

    public static func distinctSummary(_ subagent: Subagent) -> String? {
        let summary = subagent.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty, summary != SubagentRow.title(of: subagent) else { return nil }
        return summary
    }

    public static func commandOutputNote(failure: SubagentOutput.Failure?, isRunning: Bool) -> String {
        if isRunning { return notPrintedYet }
        switch failure {
        case nil: return "No output."
        case .noFile?, .missing?: return "Output not captured."
        case let failure?: return failure.sentence(.command)
        }
    }

    public static let briefCollapseLimit = 500

    public static func briefCollapses(_ brief: String) -> Bool {
        brief.count > briefCollapseLimit
    }

    public static let briefPreviewLimit = 280

    public static func briefPreview(_ brief: String) -> String? {
        guard briefCollapses(brief) else { return nil }
        let oneLine = brief.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard oneLine.count > briefPreviewLimit else { return oneLine }
        let head = oneLine.prefix(briefPreviewLimit)
        let cut = head.lastIndex(where: \.isWhitespace).map { head[..<$0] } ?? head
        return String(cut).trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }

    public static func commandLine(inPayload payload: Data) -> String? {
        guard let line = String(data: payload, encoding: .utf8),
              case .toolUse(let use)? = AgentEvent.decode(line: line)
        else { return nil }
        let command = (use.input["command"]?.stringValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return command.isEmpty ? nil : command
    }
}
