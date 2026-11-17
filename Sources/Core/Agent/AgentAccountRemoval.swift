import Foundation

public enum AgentAccountError: Error, Equatable, LocalizedError {
    case isDefault(AgentAccountID)
    case inUse(workspaces: [String])
    case folderLeftAlone(String)
    case folderAlreadyThere(String)
    case folderInUse(String)
    case folderUseUnknown(String)
    case forgottenWithFolderKept(String)
    case keychainEntriesLeft([String])
    case spendUnread(String)

    public var errorDescription: String? {
        switch self {
        case .isDefault:
            "The default account belongs to the agent itself, so Unified Dev does not remove it."
        case .inUse(let workspaces):
            "An agent is running under this account in \(workspaces.joined(separator: ", ")). Stop it first, or reopen Unified Dev if it has already stopped."
        case .folderLeftAlone(let path):
            "The folder is not where Unified Dev expected it, so it was left alone: \(path)"
        case .folderAlreadyThere(let path):
            "A folder for this account already exists, so Unified Dev did not reuse it: \(path)"
        case .folderInUse(let path):
            "A process is still using this account's folder, so Unified Dev left it alone. Stop it and remove the account again: \(path)"
        case .folderUseUnknown(let path):
            "Unified Dev could not tell whether anything is still using this account's folder, so it left it alone: \(path)"
        case .forgottenWithFolderKept(let path):
            "The account was forgotten, but its folder may still be in use, so Unified Dev left it alone. It is listed as an unfinished sign-in: \(path)"
        case .spendUnread(let path):
            "Unified Dev could not read the spend in one of this account's transcripts, so the account and its folder were kept: \(path)"
        case .keychainEntriesLeft(let services):
            "Its sign-in is still in your keychain, because Unified Dev could not delete it. Delete \(services.joined(separator: " and ")) in Keychain Access."
        }
    }
}

public enum AgentAccountRemoval {
    public struct Warning: Sendable, Equatable {
        public let title: String
        public let message: String
        public let actionTitle: String
    }

    public static func warning(
        forAccountNamed title: String, provider: AgentKind, folderExists: Bool, chosenBy projects: [String] = []
    ) -> Warning {
        let consequence = switch (folderExists, provider == .claudeCode) {
        case (true, true):
            "This deletes the account's folder on this Mac, including the conversation transcripts kept there, and the sign-in this account saved in your keychain, and no other."
        case (true, false):
            "This deletes the account's folder on this Mac, including its saved sign-in and the conversation transcripts kept there."
        case (false, true):
            "The account's folder is already gone, so this forgets the account and removes the sign-in it saved in your keychain."
        case (false, false):
            "The account's folder is already gone, so this only forgets the account."
        }
        return Warning(
            title: "Remove \(title)?",
            message: consequence + fallsBack(projects),
            actionTitle: "Remove account"
        )
    }

    private static func fallsBack(_ projects: [String]) -> String {
        let names = projects.sorted()
        guard !names.isEmpty else { return " Anything that used this account goes back to the default account." }
        let verb = names.count > 1 ? "go" : "goes"
        return " \(ProseList.joined(names)) \(verb) back to the default account of the profile."
    }

    public static func warningForUnfinishedSignIn(named title: String, provider: AgentKind) -> Warning {
        Warning(
            title: "Remove \(title)?",
            message: "This deletes the folder of a sign-in that did not finish, including anything saved in it."
                + (provider == .claudeCode ? " It also removes any sign-in it saved in your keychain." : ""),
            actionTitle: "Remove folder"
        )
    }

    public static func directory(of home: AgentAccountHome, support: URL) -> URL? {
        guard home.directory.lastPathComponent == home.id.rawValue else { return nil }
        let expected = AgentAccountHomes.directory(for: home.id, provider: home.provider, support: support)
        let settled = TranscriptHome.settled(home.directory)
        guard settled == TranscriptHome.settled(expected),
              TranscriptHome.isInside(settled: settled, of: TranscriptHome.settled(AgentAccountHomes.root(support: support)))
        else { return nil }
        return home.directory
    }

    public static func remove(
        _ home: AgentAccountHome,
        support: URL,
        store: Store,
        keychain: AgentAccountKeychain,
        processes: @Sendable () -> [ProcessVector]? = ProcessVectors.ofOtherProcesses
    ) async throws {
        guard !home.isDefault, !AgentAccountHome.isDefaultID(home.id) else {
            throw AgentAccountError.isDefault(home.id)
        }
        let running = try await AgentAccountUsage.runningWorkspaces(under: home, store: store)
        guard running.isEmpty else { throw AgentAccountError.inUse(workspaces: running) }
        if let directory = directory(of: home, support: support) {
            try requireNothingHolds(directory, processes: processes)
            let unread = try await SpendIndexer(store: store).read(account: home)
            try Task.checkCancellation()
            if let first = unread.first { throw AgentAccountError.spendUnread(first) }
        }
        try await store.forgetAgentAccount(home.id)
        do {
            try deleteFolder(of: home, support: support, processes: processes)
        } catch AgentAccountError.folderInUse(let path), AgentAccountError.folderUseUnknown(let path) {
            throw AgentAccountError.forgottenWithFolderKept(path)
        }
        try await deleteKeychainEntries(of: home, support: support, keychain: keychain)
    }

    public static func remove(
        _ row: AgentAccountPanel.Row,
        support: URL,
        store: Store,
        keychain: AgentAccountKeychain,
        processes: @Sendable () -> [ProcessVector]? = ProcessVectors.ofOtherProcesses
    ) async throws {
        guard row.isUnfinished else {
            try await remove(row.home, support: support, store: store, keychain: keychain, processes: processes)
            return
        }
        try await removeUnfinished(row.home, support: support, keychain: keychain, processes: processes)
    }

    public static func removeUnfinished(
        _ home: AgentAccountHome,
        support: URL,
        keychain: AgentAccountKeychain,
        processes: @Sendable () -> [ProcessVector]? = ProcessVectors.ofOtherProcesses
    ) async throws {
        guard !home.isDefault else { throw AgentAccountError.isDefault(home.id) }
        try deleteFolder(of: home, support: support, processes: processes)
        try await deleteKeychainEntries(of: home, support: support, keychain: keychain)
    }

    static func keychainEntries(
        of home: AgentAccountHome, support: URL, environment: [String: String], username: String
    ) -> [AgentAccountKeychain.Entry] {
        guard home.provider == .claudeCode,
              !home.isDefault,
              !AgentAccountHome.isDefaultID(home.id),
              directory(of: home, support: support) != nil
        else { return [] }
        return ClaudeKeychainEntries.of(
            configDirectory: home.directory.path, environment: environment, username: username
        )
    }

    private static func deleteKeychainEntries(
        of home: AgentAccountHome, support: URL, keychain: AgentAccountKeychain
    ) async throws {
        let entries = keychainEntries(
            of: home, support: support, environment: Shell.environment(), username: NSUserName()
        )
        var left: [String] = []
        for entry in entries {
            let gone = await keychain.delete(entry)
            if !gone { left.append(entry.service) }
        }
        guard left.isEmpty else { throw AgentAccountError.keychainEntriesLeft(left) }
    }

    private static func deleteFolder(
        of home: AgentAccountHome, support: URL, processes: () -> [ProcessVector]?
    ) throws {
        guard let directory = directory(of: home, support: support) else {
            throw AgentAccountError.folderLeftAlone(home.directory.path)
        }
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try requireNothingHolds(directory, processes: processes)
        try FileManager.default.removeItem(at: directory)
    }

    private static func requireNothingHolds(_ directory: URL, processes: () -> [ProcessVector]?) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try AgentAccountFolderUse.of(directory, among: processes()).requireFree(path: directory.path)
    }
}
