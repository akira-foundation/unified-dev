import Foundation

public enum ClaudeResolvedModel {
    private static let settingPrefix = "claude.resolved-model"
    private static let firstDatedNumber = 100

    public static func version(
        ofAlias alias: String,
        listed: [AgentModel],
        reported: [String: String]
    ) -> String? {
        if let stored = reported[alias] { return parsed(stored, alias: alias).map(label) }
        let listedVersions = listed.filter { $0.unavailable == nil }.compactMap { parsed($0.id, alias: alias) }
        return listedVersions.max { $1.isAbove($0) }.map(label)
    }

    static func version(of id: String, alias: String) -> String? {
        parsed(id, alias: alias).map(label)
    }

    private static func parsed(_ id: String, alias: String) -> ClaudeModelRank.Version? {
        guard id.hasPrefix("claude-"),
              let family = ClaudeModelRank.families.firstIndex(of: alias),
              var version = ClaudeModelRank.version(after: family, in: ClaudeModelRank.tokens(of: id)),
              version.major < firstDatedNumber else { return nil }
        if version.minor >= firstDatedNumber { version.minor = 0 }
        return version
    }

    private static func label(_ version: ClaudeModelRank.Version) -> String {
        version.minor > 0 ? "\(version.major).\(version.minor)" : "\(version.major)"
    }

    public static func record(
        requested alias: String,
        reported model: String,
        cliVersion: String,
        account: AgentAccountHome?,
        in store: Store
    ) async {
        guard version(of: model, alias: alias) != nil else { return }
        let key = settingKey(alias: alias, account: accountID(account))
        let observed = comparable(cliVersion) ?? unversionedTurn
        try? await store.changeSettings([key, turnKey(key)]) { _ in [key: model, turnKey(key): observed] }
    }

    static func record(
        _ answers: ClaudeAliasAnswers,
        cliVersion: String?,
        account: AgentAccountHome?,
        in store: Store
    ) async {
        let id = accountID(account)
        let installed = cliVersion.flatMap(comparable)
        for (alias, model) in answers.all.sorted(by: { $0.key < $1.key }) {
            let pinned = answers.pinned[alias] != nil
            guard pinned || version(of: model, alias: alias) != nil else { continue }
            let key = settingKey(alias: alias, account: id)
            let marker = turnKey(key)
            try? await store.changeSettings([key, marker]) { current in
                guard pinned || !turnOutranksProbe(current[marker], installed: installed) else { return [:] }
                return [key: model, marker: nil]
            }
        }
    }

    static func turnOutranksProbe(_ turn: String?, installed: String?) -> Bool {
        guard let turn else { return false }
        return installed == nil || turn == installed || turn == unversionedTurn
    }

    static let unversionedTurn = "unversioned"

    static func comparable(_ cliVersion: String) -> String? {
        let token = cliVersion.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        return token.isEmpty ? nil : token
    }

    public static func reported(account: AgentAccountHome?, in store: Store) async -> [String: String] {
        let id = accountID(account)
        var models: [String: String] = [:]
        for alias in ClaudeModelCatalog.builtIn.map(\.id) {
            models[alias] = try? await store.setting(settingKey(alias: alias, account: id))
        }
        return models
    }

    static func settingKeys(account: AgentAccountID) -> [String] {
        ClaudeModelCatalog.builtIn.flatMap {
            let key = settingKey(alias: $0.id, account: account)
            return [key, turnKey(key)]
        }
    }

    private static func turnKey(_ key: String) -> String {
        key + ".turn-cli"
    }

    private static func settingKey(alias: String, account: AgentAccountID) -> String {
        "\(settingPrefix).\(account.rawValue).\(alias)"
    }

    static func accountID(_ account: AgentAccountHome?) -> AgentAccountID {
        account?.id ?? AgentAccountHome.defaultID(for: .claudeCode)
    }
}
