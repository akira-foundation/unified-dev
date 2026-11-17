import Foundation
import Core

@MainActor
final class TerminalPersistence {
    static let defaultsKey = "terminal.persistSessions"

    let command: TmuxCommand?

    private var knownSessions: Set<String> = []

    static var tmuxPath: String? { Shell.which("tmux") }

    static var isTmuxInstalled: Bool { tmuxPath != nil }

    static var isSwitchedOn: Bool { UserDefaults.standard.bool(forKey: defaultsKey) }

    var isAvailable: Bool { command != nil }

    init(databasePath: String) {
        guard let executable = Self.tmuxPath else {
            command = nil
            return
        }

        let directory = (databasePath as NSString).deletingLastPathComponent
        let configPath = (directory as NSString).appendingPathComponent("tmux.conf")
        command = TmuxCommand(
            executable: executable,
            socketName: TmuxSessions.socketName(databasePath: databasePath),
            configPath: configPath
        )
        writeConfiguration(to: configPath)
    }

    private func writeConfiguration(to path: String) {
        let text = TmuxSessions.configuration(defaultShell: LoginShell.path())
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    func decision(workspaceID: WorkspaceID, paneID: String) -> TerminalStartDecision {
        TmuxSessions.decide(
            workspaceID: workspaceID,
            paneID: paneID,
            persistenceEnabled: Self.isSwitchedOn,
            tmuxAvailable: isAvailable,
            existingSessions: knownSessions
        )
    }

    func refresh() async {
        guard let command else { return }
        knownSessions = Set(await sessionNames())
        guard !knownSessions.isEmpty else { return }
        _ = try? await Shell.run(command.executable, command.sourceConfiguration, timeout: .seconds(5))
    }

    private func sessionNames() async -> [String] {
        await sessions() ?? []
    }

    func sessions() async -> [String]? {
        guard let command else { return [] }
        guard let result = try? await Shell.run(
            command.executable, command.listSessions, timeout: .seconds(5)
        ) else { return nil }
        return TmuxSessions.parseSessionList(result.stdout)
    }

    private lazy var paneReading = SharedReading<[String: Int32]> { [command] in
        await Self.readPanePIDs(command)
    }

    func panePIDs(notOlderThan maxAge: Duration) async -> [String: Int32] {
        await panePIDSnapshot(notOlderThan: maxAge) ?? [:]
    }

    func panePIDSnapshot(notOlderThan maxAge: Duration) async -> [String: Int32]? {
        await paneReading.value(notOlderThan: maxAge)
    }

    private nonisolated static func readPanePIDs(_ command: TmuxCommand?) async -> [String: Int32]? {
        guard let command else { return [:] }
        guard let result = try? await Shell.run(
            command.executable, command.listPanes, timeout: .seconds(5)
        ) else { return nil }
        guard result.ok || result.stderr.contains("no server running")
            || result.stderr.contains("No such file or directory") else { return nil }
        return TmuxSessions.parsePanePIDs(result.stdout)
    }

    func kill(workspaceID: WorkspaceID, paneIDs: [String]) async {
        await kill(sessions: paneIDs.map {
            TmuxSessions.sessionName(workspaceID: workspaceID, paneID: $0)
        })
    }

    func killEverything(workspaceID: WorkspaceID) async {
        guard command != nil else { return }
        let sessions = await sessionNames()
        await kill(sessions: TmuxSessions.sessions(ofWorkspace: workspaceID, in: sessions))
    }

    func kill(sessions: [String]) async {
        guard let command, !sessions.isEmpty else { return }
        for session in sessions {
            _ = try? await Shell.run(
                command.executable, command.killSession(session), timeout: .seconds(5)
            )
            knownSessions.remove(session)
        }
        await paneReading.invalidate()
    }

    func sweepOrphans(livePaneIDs: Set<String>, doubtful: Set<WorkspaceID>) async {
        guard command != nil else { return }
        let sessions = await sessionNames()
        knownSessions = Set(sessions)
        let reachable = TmuxSessions.reachablePanes(livePaneIDs, persistenceEnabled: Self.isSwitchedOn)
        await kill(sessions: TmuxSessions.orphans(
            sessions: sessions, livePaneIDs: reachable, sparing: doubtful
        ))
    }
}
