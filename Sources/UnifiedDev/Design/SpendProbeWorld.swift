import Foundation
import Core

#if DEBUG
struct SpendProbeWorld {
    let home: URL
    let support: URL
    let store: Store

    init(at path: String) throws {
        let root = URL(filePath: path, directoryHint: .isDirectory)
        try ProbeFolder.renew(root)
        home = root.appending(path: "home", directoryHint: .isDirectory)
        support = root.appending(path: "support", directoryHint: .isDirectory)
        for directory in [home, support] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        store = try Store(path: root.appending(path: "unifieddev.sqlite").path)
    }

    var defaults: [AgentAccountHome] { SpendAccounts.defaultHomes(home: home, environment: [:]) }

    func defaultHome(_ provider: AgentKind) throws -> AgentAccountHome {
        guard let found = defaults.first(where: { $0.provider == provider }) else {
            throw ProbeError.noDefault(provider)
        }
        return found
    }

    func createAccount(_ provider: AgentKind, label: String) async throws -> AgentAccountHome {
        let reservation = try AgentAccountCreation.reserve(
            provider: provider,
            label: label,
            existing: try await store.agentAccounts().map(\.id),
            support: support
        )
        let plan = reservation.plan
        try await store.add(AgentAccountRow(
            id: plan.id, provider: plan.provider, directory: plan.directory.path, label: plan.label
        ))
        return plan.home
    }

    func removeAccount(_ account: AgentAccountHome) async throws {
        try await AgentAccountRemoval.remove(account, support: support, store: store, keychain: .untouched, processes: { [] })
    }

    func signIn(_ account: AgentAccountHome, as email: String) throws {
        let data: Data
        switch account.provider {
        case .claudeCode:
            data = Data(#"{"oauthAccount":{"emailAddress":"\#(email)"}}"#.utf8)
        default:
            data = Data(#"{"tokens":{"id_token":"\#(Self.token(email: email))"}}"#.utf8)
        }
        try FileManager.default.createDirectory(
            at: account.identityPath.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: account.identityPath)
    }

    func claude(
        _ output: Int, in account: AgentAccountHome, project: String, on day: Date, as name: String
    ) throws {
        let file = account.directory.appending(path: "projects/-Users-ada-\(project)/\(name).jsonl")
        let line = #"{"type":"assistant","timestamp":"\#(Self.stamp(day))","cwd":"/Users/ada/\#(project)","#
            + #""message":{"id":"msg_\#(name)","model":"claude-opus-5","usage":{"input_tokens":\#(output),"#
            + #""output_tokens":\#(output),"cache_read_input_tokens":\#(output * 20),"#
            + #""cache_creation_input_tokens":0}}}"#
        try write([line], to: file)
    }

    func codex(_ prompt: Int, in account: AgentAccountHome, project: String, on day: Date, as name: String) throws {
        let file = account.directory.appending(
            path: "sessions/2026/10/rollout-2026-10-20T10-00-00-\(Self.identifier(name)).jsonl"
        )
        let stamp = Self.stamp(day)
        let context = #"{"timestamp":"\#(stamp)","ordinal":1,"type":"turn_context","#
            + #""payload":{"turn_id":"t","cwd":"/Users/ada/\#(project)","model":"gpt-6-sol"}}"#
        let count = #"{"timestamp":"\#(stamp)","ordinal":2,"type":"event_msg","#
            + #""payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":\#(prompt),"#
            + #""cached_input_tokens":\#(prompt * 3 / 4),"cache_write_input_tokens":0,"output_tokens":\#(prompt / 20)}}}}"#
        try write([context, count], to: file)
    }

    func index() async throws {
        _ = try await SpendIndexer(store: store, home: home, environment: [:]).refresh()
    }

    func screen(days window: SpendSpan = .week) async throws -> (board: SpendBoard, accounts: [SpendAccountLine]) {
        let since = SpendSpan.month.start(from: Date(), calendar: .current)
        let census = try await store.setting(SpendCensus.settingKey)
            .flatMap { try? JSONDecoder().decode(SpendCensus.self, from: Data($0.utf8)) } ?? SpendCensus()
        let input = SpendBoard.Input(
            days: try await store.spendDays(since: since),
            census: census,
            installed: [.claudeCode, .codex],
            window: window
        )
        return (
            SpendBoard.make(input),
            try await SpendBoard.accounts(input, reading: store, defaults: defaults)
        )
    }

    private func write(_ lines: [String], to file: URL) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
    }

    private static func stamp(_ day: Date) -> String {
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: noon)
    }

    private static func identifier(_ name: String) -> String {
        let hex = name.utf8.map { String(format: "%02x", $0) }.joined()
        let padded = (hex + String(repeating: "0", count: 32)).prefix(32)
        let parts = [8, 4, 4, 4, 12]
        var cursor = padded.startIndex
        return parts.map { length in
            let end = padded.index(cursor, offsetBy: length)
            defer { cursor = end }
            return String(padded[cursor..<end])
        }.joined(separator: "-")
    }

    private static func token(email: String) -> String {
        func encode(_ text: String) -> String {
            Data(text.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return [#"{"alg":"none"}"#, #"{"email":"\#(email)"}"#, "signature"].map(encode).joined(separator: ".")
    }

    enum ProbeError: Error {
        case noDefault(AgentKind)
    }
}
#endif
