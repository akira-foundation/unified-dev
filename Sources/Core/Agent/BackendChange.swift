import Foundation

public enum BackendChange: Sendable, Equatable {
    case unchanged
    case changeInPlace(AgentKind)
    case switchInPlace(AgentKind)
    case fork(AgentKind)

    public static func decide(
        from current: AgentKind, to wanted: AgentKind, hasSpoken: Bool, isInteractiveTerminal: Bool
    ) -> BackendChange {
        guard current != wanted else { return .unchanged }
        guard wanted.canRunWorkspaces else { return .unchanged }
        if isInteractiveTerminal { return .fork(wanted) }
        return hasSpoken ? .switchInPlace(wanted) : .changeInPlace(wanted)
    }

    public static func interactiveForkNotice(to wanted: AgentKind) -> String {
        "Opened a new chat with \(wanted.label). This chat runs in a terminal, so another agent cannot take it over."
    }

    public static func newChatLabel(to wanted: AgentKind) -> String {
        "Open in a new chat with \(wanted.label)"
    }

    public static func newChatProviders(from current: AgentKind, offered: [AgentKind]) -> [AgentKind] {
        offered.filter { $0 != current && $0.canRunWorkspaces }
    }

    public static func newChatControls(
        from controls: ComposerControls,
        on wanted: AgentKind,
        models: [AgentKind: [AgentModel]],
        firstOffered: String? = nil
    ) -> ComposerControls? {
        let visible = (models[wanted] ?? []).filter { !$0.hidden }
        guard let model = visible.first(where: \.isDefault)?.id ?? visible.first?.id
            ?? firstOffered.map({ ModelIdentifier.resolve($0, models: models).model }) else {
            return nil
        }
        var opening = controls
        opening.agentKind = wanted
        opening.model = model
        opening.effort = DefaultBackend.effort(controls.effort, on: wanted, model: model, models: models)
        return opening
    }

    public static func hasSpoken(
        rowCount: Int,
        agentSessionID: String?,
        isTranscriptLoaded: Bool
    ) -> Bool {
        if !(agentSessionID ?? "").isEmpty { return true }
        if rowCount > 0 { return true }
        return !isTranscriptLoaded
    }

    public static func forkNotice(title: String, from current: AgentKind) -> String {
        "Opened `\(title)`. Your original \(current.label) conversation is still available."
    }

    public static func forkFailureNotice(to wanted: AgentKind) -> String {
        "Could not open a \(wanted.label) conversation. Your current conversation is unchanged."
    }

    public static func forkedTitle(_ title: String, to kind: AgentKind) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let base = trimmed.isEmpty ? "New session" : trimmed
        let stem = base.components(separatedBy: " on ").first ?? base
        return "\(stem) on \(kind.label)"
    }
}
