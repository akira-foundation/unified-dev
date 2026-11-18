import Foundation
import Observation
import Core

@MainActor
@Observable
final class SlashCommandCatalog {
    private(set) var commands: [SlashCommand] = []
    private(set) var isLoaded = false

    private var loadedPath: String?
    private var loadedAt: Date?
    private var byName: [String: SlashCommand] = [:]
    private var running: Task<[SlashCommand], Never>?
    private var runningPath: String?
    private var codexCatalog: CodexSkillCatalog?
    private var codexPath: String?

    var account: AgentAccountHome? {
        didSet {
            guard account != oldValue else { return }
            restartScan()
            codexPath = nil
        }
    }

    var refused: Set<AgentKind> = [] {
        didSet {
            guard refused != oldValue else { return }
            restartScan()
            codexPath = nil
        }
    }

    var claudeAccount: AgentAccountHome? {
        didSet {
            guard claudeAccount != oldValue else { return }
            restartScan()
        }
    }

    static let stalenessWindow: TimeInterval = 3

    private static var byPath: [String: SlashCommandCatalog] = [:]

    static func shared(for workspacePath: String) -> SlashCommandCatalog {
        if let held = byPath[workspacePath] { return held }
        let made = SlashCommandCatalog()
        byPath[workspacePath] = made
        return made
    }

    private func restartScan() {
        running?.cancel()
        running = nil
        runningPath = nil
        loadedPath = nil
        loadedAt = nil
    }

    func load(workspacePath: String) async {
        guard loadedPath != workspacePath else { return }
        await scan(workspacePath: workspacePath)
    }

    func refreshIfStale(workspacePath: String, now: Date = Date()) async {
        if loadedPath == workspacePath,
           let loadedAt,
           now.timeIntervalSince(loadedAt) < Self.stalenessWindow {
            return
        }
        await scan(workspacePath: workspacePath)
    }

    func reload(workspacePath: String) async {
        loadedAt = nil
        await scan(workspacePath: workspacePath)
    }

    func command(named name: String) -> SlashCommand? {
        byName[name]
    }

    func matches(_ query: String) -> [SlashCommandMatch] {
        SlashCommand.rank(commands, query: query)
    }

    private func scan(workspacePath: String) async {
        let task: Task<[SlashCommand], Never>
        if let running, runningPath == workspacePath {
            task = running
        } else {
            let home = NSHomeDirectory()
            let claudeHome = claudeAccount?.directory.path
            let codexHome = AgentAccountEnvironment.codexHome(for: account, inheriting: Shell.environment())
            let refused = refused
            if codexPath != workspacePath {
                codexCatalog = refused.contains(.codex)
                    ? nil : CodexSkillCatalog.live(project: workspacePath, account: account)
                codexPath = workspacePath
            }
            let codex = codexCatalog
            task = Task.detached(priority: .utility) {
                let skills = await codex?.skills()
                return SlashCommandIndex.discover(
                    home: home, project: workspacePath, codexSkills: skills,
                    codexHome: codexHome, claudeHome: claudeHome, refusing: refused
                )
            }
            running = task
            runningPath = workspacePath
        }

        let found = await task.value
        guard running == task else { return }
        running = nil
        runningPath = nil

        loadedPath = workspacePath
        loadedAt = Date()
        isLoaded = true
        guard found != commands else { return }
        commands = found
        byName = Dictionary(found.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
