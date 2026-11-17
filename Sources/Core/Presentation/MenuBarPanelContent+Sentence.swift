import Foundation

extension MenuBarPanelContent {
    static let lowercasedTitles: Set<String> = ["Session", "Weekly"]

    static let noAgentsInProfileLine = "No agents running in this profile."

    static let awakeFromElsewherePhrase = "The Mac stays awake until agents in other profiles finish."

    static func sentence(
        running: Int,
        workspaces: Int,
        waiting: Int,
        notices: [LimitNotice],
        hold: KeepAwake.Hold,
        hasAgentsElsewhere: Bool = false,
        needsSetup: Bool,
        now: Date
    ) -> String {
        let isHeldFromElsewhere = isHeldFromElsewhere(hold: hold, running: running, hasAgentsElsewhere: hasAgentsElsewhere)
        var parts: [String] = []
        if running > 0 { parts.append(runningPhrase(agents: running, workspaces: workspaces)) }
        if waiting > 0 { parts.append("\(Counted.of(waiting, "agent")) waiting on you.") }
        if parts.isEmpty { parts.append(isHeldFromElsewhere ? noAgentsInProfileLine : noAgentsLine + ".") }
        parts += notices.map { limitPhrase($0, now: now) }
        if let awake = isHeldFromElsewhere ? awakeFromElsewherePhrase : awakePhrase(hold, now: now) {
            parts.append(awake)
        }
        if needsSetup { parts.append(setupSentence) }
        return parts.joined(separator: " ")
    }

    static let noAgentsInProfileHeadline = "No agents in this profile"
    static let awakeSuffix = "awake"

    static func headline(
        running: Int,
        workspaces: Int,
        waiting: Int,
        hold: KeepAwake.Hold,
        hasAgentsElsewhere: Bool = false
    ) -> String {
        var parts: [String] = []
        if running > 0 {
            let count = Counted.of(running, "agent")
            parts.append(workspaces > 0 ? "\(count) in \(Counted.of(workspaces, "workspace"))" : "\(count) running")
        }
        if waiting > 0 { parts.append("\(waiting.formatted()) waiting on you") }
        if parts.isEmpty {
            let held = isHeldFromElsewhere(hold: hold, running: running, hasAgentsElsewhere: hasAgentsElsewhere)
            parts.append(held ? noAgentsInProfileHeadline : noAgentsLine)
        }
        if hold.isOn { parts.append(awakeSuffix) }
        return parts.joined(separator: ", ")
    }

    static func isHeldFromElsewhere(hold: KeepAwake.Hold, running: Int, hasAgentsElsewhere: Bool) -> Bool {
        hold == .whileAgentsRun && running == 0 && hasAgentsElsewhere
    }

    static func runningPhrase(agents: Int, workspaces: Int) -> String {
        let count = Counted.of(agents, "agent")
        guard workspaces > 0 else { return "\(count) running." }
        return "\(count) running in \(Counted.of(workspaces, "workspace"))."
    }

    static func limitPhrase(_ notice: LimitNotice, now: Date) -> String {
        let title = lowercasedTitles.contains(notice.title) ? notice.title.lowercased() : notice.title
        let limit = "\(notice.provider.label) \(title) limit reached"
        guard let resetsAt = notice.resetsAt else { return limit + "." }
        return "\(limit), resets \(QuotaCountdown.phrase(until: resetsAt, from: now))."
    }

    static func awakePhrase(_ hold: KeepAwake.Hold, now: Date) -> String? {
        switch hold {
        case .none: nil
        case .whileAgentsRun: "The Mac stays awake until they finish."
        case .until(let end): "Keep Awake is on for \(UsageFormat.compactDuration(end.timeIntervalSince(now))) more."
        case .indefinitely: "Keep Awake is on until you turn it off."
        }
    }
}
