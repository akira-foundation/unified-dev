import SwiftUI
import AppKit
import Core

@MainActor
@Observable
final class LoginTerminalSession {
    let label: String

    @ObservationIgnored let terminal: AppTerminalView
    private(set) var isRunning = true

    private let launch: TerminalLaunch
    private var hasStarted = false

    init?(
        command: LoginCommand,
        directory: String,
        account: AgentAccountHome?,
        gitHub: GitHubLogin = .thisMac,
        bitbucket: BitbucketLogin = .thisMac,
        onExit: @escaping @MainActor (TerminalExit) -> Void
    ) {
        guard let path = Shell.which(command.executable) else { return nil }

        let inherited = gitHub.signInEnvironment(from: Shell.environment())
        let variables = AgentAccountEnvironment.login(
            for: account, inheriting: bitbucket.isOwn ? BitbucketSignIn.environment(inherited, login: bitbucket) : inherited
        )

        label = command.label
        launch = TerminalLaunch(
            executable: path,
            execName: command.executable,
            arguments: command.arguments,
            environment: variables.map { "\($0.key)=\($0.value)" }.sorted(),
            directory: FileManager.default.fileExists(atPath: directory)
                ? directory
                : AgentScratchDirectory.current()
        )

        terminal = AppTerminalView(frame: .zero)
        terminal.onExit = { [weak self] exit in
            guard let self, self.isRunning else { return }
            self.isRunning = false
            onExit(exit)
        }
    }

    func start() {
        guard !hasStarted, isRunning else { return }
        hasStarted = true
        terminal.start(launch)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        terminal.shutdown()
    }
}

struct LoginTerminal: NSViewRepresentable {
    let session: LoginTerminalSession

    @AppStorage(TerminalGhostty.defaultsKey) private var usesGhosttyTheme = true
    @AppStorage(TerminalTextSize.defaultsKey) private var fontSize = 0.0

    func makeNSView(context: Context) -> TerminalHostView {
        let host = TerminalHostView()
        host.attach(session.terminal)
        configure()
        session.start()
        return host
    }

    func updateNSView(_ nsView: TerminalHostView, context: Context) {
        nsView.attach(session.terminal)
        configure()
        session.start()
    }

    private func configure() {
        session.terminal.usesGhosttyTheme = usesGhosttyTheme
        session.terminal.fontSizeOverride = fontSize > 0 ? CGFloat(fontSize) : nil
    }
}
