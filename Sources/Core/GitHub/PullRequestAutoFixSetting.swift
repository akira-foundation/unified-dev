import Foundation

public enum PullRequestAutoFixSetting {
    public static let settingTitle = "Ask to fix conflicts and failed checks automatically"

    public static let settingHeader = "Automatic fixes"

    public static let caveat = "The agent gets the same request as Ask to fix without waiting for you, once per commit "
        + "and reason, and it can commit and push. A chat in Bypass permissions never gets it. After three in a row without the checks passing it stops and tells "
        + "you. Only pull requests you opened from this repository, with every commit attributed to you, are covered. "
        + "Text in a failed check's log or in the branch can still steer the agent, and you would not see it first."

    public static let saveFailure = "This could not be saved, so it is as it was."

    private static let storedOn = "on"

    static func key(repoID: RepoID) -> String {
        "repo.\(repoID).pullRequestAutoFix"
    }

    public static func parse(_ stored: String?) -> Bool {
        stored == storedOn
    }

    public static func isOn(repoID: RepoID, in store: Store) async -> Bool {
        parse(try? await store.setting(key(repoID: repoID)))
    }

    public static func save(_ isOn: Bool, repoID: RepoID, to store: Store) async throws {
        try await store.setSetting(key(repoID: repoID), isOn ? storedOn : nil)
    }
}
