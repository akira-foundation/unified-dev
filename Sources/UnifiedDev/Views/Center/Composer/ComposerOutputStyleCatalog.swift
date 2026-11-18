import Foundation
import Observation
import Core

@MainActor
@Observable
final class ComposerOutputStyleCatalog: AccountBound {
    private(set) var styles: [OutputStyle] = OutputStyle.builtIns

    private let claudeAccount: AgentAccountHome?
    private let refused: Set<AgentKind>

    init(account: AgentAccountHome? = nil, refusing refused: Set<AgentKind> = []) {
        claudeAccount = account
        self.refused = refused
    }

    private var loadedPath: String?
    private var loadedAt: Date?
    private var running: Task<[OutputStyle], Never>?
    private var runningPath: String?

    static let stalenessWindow: TimeInterval = 3

    static let shelves = OutputStyleShelves<ComposerOutputStyleCatalog>()

    static func forDefaultAccount() -> ComposerOutputStyleCatalog {
        ComposerOutputStyleCatalog(account: SpendAccounts.defaultHomes().first { $0.provider == .claudeCode })
    }

    func refreshIfStale(project: String?, now: Date = Date()) async {
        if loadedPath == project,
           let loadedAt,
           now.timeIntervalSince(loadedAt) < Self.stalenessWindow {
            return
        }
        await scan(project: project)
    }

    func options(includingCurrent current: String) -> [ComposerOption] {
        let known = styles.map { style in
            ComposerOption(
                id: style.name,
                label: style.name == OutputStyle.defaultName ? "Default" : style.name,
                detail: style.detail
            )
        }
        return ComposerOption.adding([current], to: known)
    }

    func detail(of name: String) -> String? {
        styles.first { $0.name == name }?.detail
    }

    private func scan(project: String?) async {
        let task: Task<[OutputStyle], Never>
        if let running, runningPath == project {
            task = running
        } else {
            let home = NSHomeDirectory()
            let claudeHome = claudeAccount?.directory.path
            let refusing = refused
            task = Task.detached(priority: .utility) {
                OutputStyleIndex.discover(home: home, project: project, claudeHome: claudeHome, refusing: refusing)
            }
            running = task
            runningPath = project
        }

        let found = await task.value
        guard running == task else { return }
        running = nil
        runningPath = nil

        loadedPath = project
        loadedAt = Date()
        if found != styles { styles = found }
    }
}
