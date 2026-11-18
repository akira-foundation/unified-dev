import Foundation

public extension AgentAccountLaunch {
    func resumeCommand(
        for session: Session,
        in workspace: Workspace,
        resuming externalSession: String,
        chrome: Bool,
        base: URL? = nil
    ) -> String? {
        guard case .runs(let account) = self else { return nil }
        return try? session.agentKind.prepareInteractiveCommand(
            directory: workspace.path, prompt: "", sessionID: session.id,
            model: session.model, effort: session.effort,
            permissionMode: session.permissionMode, resuming: externalSession,
            account: account,
            orchestrates: workspace.isOrchestrator,
            chrome: chrome,
            base: base
        )
    }
}
