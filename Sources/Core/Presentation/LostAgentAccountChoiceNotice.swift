import Foundation

public enum LostAgentAccountChoiceNotice {
    public enum Step: Equatable, Sendable {
        case hold
        case show(Notice)
        case forget
    }

    public static func step(lost: [RepoID], repos: [Repo], slotIsFree: Bool) -> Step {
        guard !lost.isEmpty else { return .hold }
        guard let notice = notice(lost, repos: repos) else { return repos.isEmpty ? .hold : .forget }
        return slotIsFree ? .show(notice) : .hold
    }

    public static func wasDismissed(_ shown: Notice.ID?, before: Notice?, after: Notice?) -> Bool {
        guard let shown else { return false }
        return before?.id == shown && after == nil
    }

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
