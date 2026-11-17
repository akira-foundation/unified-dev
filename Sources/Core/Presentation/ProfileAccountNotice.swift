import Foundation

public enum ProfileAccountNotice {
    public static func cleared(_ ids: [RepoID], repos: [Repo]) -> String? {
        let names = ids.compactMap { id in repos.first { $0.id == id }?.name }
        guard !names.isEmpty else { return nil }
        let subject = ProseList.joined(names)
        let verb = names.count > 1 ? "go" : "goes"
        return "\(subject) \(verb) back to the profile's default account, "
            + "because the account chosen there is no longer one this profile uses."
    }

    public static func moved(
        _ repo: Repo, to profile: Profile, holderName: String, book: AgentAccountChoiceBook
    ) -> String? {
        let stray = book.accounts.strayChoices(book.repos[repo.id] ?? [:], in: profile.id)
        guard !stray.isEmpty else { return nil }
        let agents = ProseList.joined(stray.map(\.label))
        return "\(repo.name) now runs the default \(agents) account of \(holderName), "
            + "because the account it chose is not one \(profile.name) uses."
    }
}
