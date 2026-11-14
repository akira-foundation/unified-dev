import Foundation
import Core

enum PreviewScenarioTrouble {
    case alert(AppAlert)
    case notice(Notice)
}

@MainActor
enum PreviewScenarioLaunch {
    private static var request: Result<(scenario: PreviewScenario, root: String, path: String), Error>?

    static func prepare() {
        forgetSeededState()
        guard let path = PreviewLaunch.scenarioPath() else { return }
        do {
            let root = try PreviewLaunch.root()
            let scenario = try PreviewLaunch.scenario(at: path)
            if !scenario.welcome {
                UserDefaults.standard.set(true, forKey: OnboardingGate.completedKey)
            }
            UserDefaults.standard.set(scenario.holdsSeededQuotas, forKey: PreviewScenario.holdsQuotasKey)
            UserDefaults.standard.set(
                scenario.silentAgents.map(\.rawValue),
                forKey: PreviewScenario.silentAgentsKey
            )
            UserDefaults.standard.set(
                scenario.agentsWithoutLimits.map(\.rawValue),
                forKey: PreviewScenario.agentsWithoutLimitsKey
            )
            seedUpdate(scenario.update)
            PreviewScenario.AgentSettings.adopt(scenario.agentSettings)
            request = .success((scenario, root, path))
        } catch {
            seedUpdate(nil)
            request = .failure(error)
        }
    }

    private static func seedUpdate(_ update: PreviewScenario.Update?) {
        UserDefaults.standard.set(
            update.flatMap { try? JSONEncoder().encode($0) },
            forKey: PreviewScenario.seededUpdateKey
        )
        UserDefaults.standard.removeObject(forKey: SoftwareUpdate.lastCheckedKey)
        UserDefaults.standard.removeObject(forKey: SoftwareUpdate.skippedVersionKey)
        UserDefaults.standard.removeObject(forKey: SoftwareUpdate.offerHeldSinceKey)
    }

    private static func forgetSeededState() {
        UserDefaults.standard.removeObject(forKey: PreviewScenario.holdsQuotasKey)
        UserDefaults.standard.removeObject(forKey: PreviewScenario.silentAgentsKey)
        UserDefaults.standard.removeObject(forKey: PreviewScenario.agentsWithoutLimitsKey)
        UserDefaults.standard.removeObject(forKey: PreviewScenario.seededUpdateKey)
        PreviewScenario.AgentSettings.adopt(nil)
    }

    static func seed(with manager: WorkspaceManager) async -> PreviewScenarioTrouble? {
        guard let request else { return nil }
        Self.request = nil
        let path = (try? request.get())?.path ?? ""
        do {
            let (scenario, root, _) = try request.get()
            let seeder = PreviewScenarioSeeder(manager: manager, scratchRoot: PreviewIdentity.scratch(in: root))
            let outcome = try await seeder.seed(scenario)
            for tab in outcome.browserTabs {
                CenterTabStore.shared.add(kind: .browser, workspaceID: tab.workspaceID, url: tab.address)
            }
            Log.launch.info("""
                seeded the preview scenario: \(outcome.projects, privacy: .public) projects, \
                \(outcome.workspaces, privacy: .public) workspaces, \(outcome.chats, privacy: .public) chats, \
                \(outcome.transcripts, privacy: .public) transcripts
                """)
            return nil
        } catch PreviewScenarioError.alreadySeeded(let projects) {
            Log.launch.info("the preview already holds projects, so the scenario was left alone")
            return .notice(PreviewScenarioIgnored.notice(scenarioPath: path, projects: projects))
        } catch {
            return .alert(AppAlert(
                title: "Could not set up the preview scenario",
                message: String(describing: error) + "\n\nRun `make preview-clean` in the worktree, build the preview again and reopen it."
            ))
        }
    }
}
