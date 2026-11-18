import Foundation

public enum OnboardingAgentChoice {
    public static func candidates(in report: SetupReport) -> [AgentKind] {
        let agents = SetupTool.displayOrder.filter { $0.agentKind?.canRunWorkspaces == true }
        guard agents.allSatisfy({ report.outcome(for: $0).isSettled }) else { return [] }
        return agents.filter { report.outcome(for: $0).isReady }.compactMap(\.agentKind)
    }

    public static func isOffered(
        in report: SetupReport,
        hasCompletedOnboarding: Bool,
        hasDefaultPreset: Bool = false
    ) -> Bool {
        guard !hasCompletedOnboarding, !hasDefaultPreset else { return false }
        return candidates(in: report).count > 1
    }

    public static func signedInLine(for kind: AgentKind, in report: SetupReport) -> String? {
        guard let tool = SetupTool.displayOrder.first(where: { $0.agentKind == kind }),
              case .ready(let detail) = report.outcome(for: tool) else { return nil }
        guard let detail, !detail.isEmpty, !isVersion(detail) else { return "Signed in" }
        return detail
    }

    private static func isVersion(_ text: String) -> Bool {
        text.range(of: #"^v?\d+(\.\d+)+"#, options: .regularExpression) != nil
    }

    public static func selection(among candidates: [AgentKind], current: AgentKind) -> AgentKind? {
        candidates.contains(current) ? current : candidates.first
    }

    public static func needsModelList(for kind: AgentKind) -> Bool {
        kind != .claudeCode
    }

    public static func defaults(
        choosing kind: AgentKind,
        from current: AppDefaults,
        models: [AgentKind: [AgentModel]] = [:]
    ) -> AppDefaults? {
        guard kind != current.backend else { return current }
        guard let picked = pick(kind, keeping: current, models: models) else { return nil }

        var next = current
        let reviewFollows = current.reviewBackend == current.backend
            && current.reviewModel == current.model
            && current.reviewEffort == current.effort
        next.model = picked.model
        next.effort = picked.effort
        next.backend = kind
        if reviewFollows {
            next.reviewModel = picked.model
            next.reviewEffort = picked.effort
            next.reviewBackend = kind
        }
        return next
    }

    private static func pick(
        _ kind: AgentKind,
        keeping current: AppDefaults,
        models: [AgentKind: [AgentModel]]
    ) -> (model: String, effort: String)? {
        let owner = DefaultBackend.kind(ofModel: current.model, running: current.backend, models: models)
        if owner == kind {
            let effort = DefaultBackend.effort(
                current.effort, on: kind, model: current.model, models: models
            )
            return (current.model, settled(effort, or: current.effort))
        }
        guard needsModelList(for: kind) else {
            return (AppDefaults.fallbackModel, AppDefaults.fallbackEffort)
        }
        guard let chosen = AgentModel.selection(requested: nil, from: models[kind] ?? []) else { return nil }
        let resolved = DefaultBackend.effort(current.effort, on: kind, model: chosen.id, models: models)
        return (chosen.id, settled(resolved, or: current.effort))
    }

    private static func settled(_ effort: String, or previous: String) -> String {
        if !effort.isEmpty { return effort }
        return previous.isEmpty ? AppDefaults.fallbackEffort : previous
    }
}
