import Foundation

public enum OrchestratorUnaskedCommands {
    public static let settingTitle = "Run commands without asking"

    public static let settingHeader = "Orchestrator"

    public static let caveat = "Only a short list of programs that read runs without asking: listing and reading files, "
        + "searching text, and the reads of git and gh. Anything else asks you first, builds, scripts and network tools "
        + "included, and edits, commits, pushes, merges and rebases it can recognise stay refused. "
        + "Text planted in a file or an issue the orchestrator reads can still choose which of those reads run, "
        + "and you would not see them first. A chat in a terminal still asks."

    public static let saveFailure = "This could not be saved, so it is as it was."

    private static let storedOn = "on"

    static func key(repoID: RepoID) -> String {
        "repo.\(repoID).orchestratorRunsCommandsUnasked"
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
