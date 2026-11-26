import Foundation

public enum LostAgentAccountChoiceNotice {
    public static func notice(_ ids: [RepoID], repos: [Repo]) -> Notice? {
        let names = ids.compactMap { id in repos.first { $0.id == id }?.name }
        guard !names.isEmpty else { return nil }
        let subject = ProseList.joined(names)
        let message = names.count > 1
            ? "\(subject) run the default account now, because the accounts chosen for them no longer exist. "
                + "Choose others in each project's settings."
            : "\(subject) runs the default account now, because the account chosen for it no longer exists. "
                + "Choose another in the project's settings."
        return Notice(message: message, tone: .warning, dismissal: .untilDismissed)
    }
}
