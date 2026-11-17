import Foundation
import Core

extension AppModel {
    func menuBarPanelInput(
        layout: UsageLayout,
        session: KeepAwakeSession?,
        whileAgentsRun: Bool,
        at now: Date
    ) -> MenuBarPanelContent.Input {
        let shown = shownQuotas
        return MenuBarPanelContent.Input(
            workspaces: workspaces,
            running: runningWorkspaceIDs,
            waiting: waitingWorkspaceIDs,
            agentsByWorkspace: workingAgentsByWorkspace,
            quotas: shown.quotas,
            accounts: shown.accounts,
            unanswered: shown.unanswered,
            withoutLimits: shown.withoutLimits,
            lastReported: shown.lastReported,
            pending: shown.pending,
            layout: layout,
            hold: KeepAwake.Hold.of(
                session: session,
                whileAgentsRun: whileAgentsRun,
                runningCount: runningAgentCount,
                at: now
            ),
            now: now,
            offers: quotaAccountOffers(at: now),
            askIsWorking: askStatus == .running,
            profile: activeProfile
        )
        .scoped(to: profileWorkspaces)
    }

    func revealRunningOnHome() {
        homeFilter = HomeFilter(scope: .running)
        selection = .home
    }
}
