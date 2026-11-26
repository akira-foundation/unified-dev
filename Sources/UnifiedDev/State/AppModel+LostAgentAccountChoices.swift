import Core
import Foundation

extension AppModel {
    func tellOfLostAgentAccountChoices() async {
        guard let store else { return }
        do {
            let lost = try await store.lostAgentAccountChoices()
            switch LostAgentAccountChoiceNotice.step(lost: lost, repos: repos, slotIsFree: notice == nil) {
            case .hold:
                return
            case .forget:
                try await store.forgetLostAgentAccountChoices()
            case .show(let told):
                lostAccountChoiceNoticeID = told.id
                notice = told
            }
        } catch {
            Log.launch.error("could not read lost account choices: \(error.readableMessage, privacy: .public)")
        }
    }

    func forgetLostAgentAccountChoicesOnceDismissed(replacing previous: Notice?) {
        guard LostAgentAccountChoiceNotice.wasDismissed(lostAccountChoiceNoticeID, before: previous, after: notice),
              let store else { return }
        lostAccountChoiceNoticeID = nil
        Task {
            do {
                try await store.forgetLostAgentAccountChoices()
            } catch {
                Log.launch.error("could not forget lost account choices: \(error.readableMessage, privacy: .public)")
            }
        }
    }
}
