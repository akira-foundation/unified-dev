import Core
import Foundation

extension AppModel {
    func tellOfLostAgentAccountChoices() async {
        guard let store else { return }
        do {
            let lost = try await store.takeLostAgentAccountChoices()
            guard let told = LostAgentAccountChoiceNotice.notice(lost, repos: repos) else { return }
            notice = told
        } catch {
            Log.launch.error("could not read lost account choices: \(error.readableMessage, privacy: .public)")
        }
    }
}
