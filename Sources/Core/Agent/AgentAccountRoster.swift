import Foundation

public struct AgentAccountStanding: Sendable, Hashable {
    public let home: AgentAccountHome
    public let identity: AgentAccountIdentity
    public let cliReport: AgentAccountLiveness.CliReport
    public let isolationDoubt: String?
    public let directoryExists: Bool

    public var isolationIsGuaranteed: Bool { isolationDoubt == nil }

    public func reporting(_ answers: [AgentAccountID: AgentAccountLiveness.CliReport]) -> AgentAccountStanding {
        AgentAccountStanding(
            home: home,
            identity: identity,
            cliReport: answers[home.id] ?? cliReport,
            isolationDoubt: isolationDoubt,
            directoryExists: directoryExists
        )
    }

    public init(
        home: AgentAccountHome,
        identity: AgentAccountIdentity,
        cliReport: AgentAccountLiveness.CliReport,
        isolationDoubt: String?,
        directoryExists: Bool = true
    ) {
        self.home = home
        self.identity = identity
        self.cliReport = cliReport
        self.isolationDoubt = isolationDoubt
        self.directoryExists = directoryExists
    }
}

public enum AgentAccountRoster {
    public static func homes(rows: [AgentAccountRow], defaults: [AgentAccountHome]) -> [AgentAccountHome] {
        let defaultIDs = Set(defaults.map(\.id))
        return defaults + rows.filter { !defaultIDs.contains($0.id) }.map(AgentAccountHome.init)
    }

    public static func standings(
        rows: [AgentAccountRow],
        defaults: [AgentAccountHome],
        read: (AgentAccountHome) -> (identity: Data?, credential: Data?),
        codexStorageMode: CodexAuthStorageMode,
        exists: (AgentAccountHome) -> Bool,
        report: @escaping @Sendable (AgentAccountHome) async -> AgentAccountLiveness.CliReport
    ) async -> [AgentAccountStanding] {
        let homes = Self.homes(rows: rows, defaults: defaults)
        let identities = homes.map { home in
            let files = read(home)
            return AgentAccountIdentity.read(home, identity: files.identity, credential: files.credential)
        }
        let present = homes.map(exists)
        let reports = await reports(for: homes, askable: present, report: report)
        return homes.indices.map { index in
            AgentAccountStanding(
                home: homes[index],
                identity: identities[index],
                cliReport: reports[index],
                isolationDoubt: isolationDoubt(for: homes[index].provider, codexStorageMode: codexStorageMode),
                directoryExists: present[index]
            )
        }
    }

    static func isolationDoubt(for provider: AgentKind, codexStorageMode: CodexAuthStorageMode) -> String? {
        switch provider {
        case .claudeCode:
            nil
        case .codex:
            switch codexStorageMode {
            case .file: nil
            case .keyring:
                "Codex keeps its login in the system keychain here, which a separate directory does not keep apart."
            }
        case .grok:
            nil
        case .antigravity:
            "Antigravity keeps its login under HOME alone, and a separate HOME would move every other setting the agent reads."
        case .cursor:
            "Cursor can move its configuration to another directory, but its login is not documented to move with it."
        case .openCode:
            "Whether a directory of its own keeps an OpenCode login apart has not been measured yet."
        }
    }

    private static func reports(
        for homes: [AgentAccountHome],
        askable: [Bool],
        report: @escaping @Sendable (AgentAccountHome) async -> AgentAccountLiveness.CliReport
    ) async -> [AgentAccountLiveness.CliReport] {
        await withTaskGroup(of: (Int, AgentAccountLiveness.CliReport).self) { group in
            for (index, home) in homes.enumerated() where askable[index] {
                group.addTask { (index, await report(home)) }
            }
            var answers = [AgentAccountLiveness.CliReport](repeating: .unanswered, count: homes.count)
            for await (index, answer) in group { answers[index] = answer }
            return answers
        }
    }
}
