import SwiftUI
import Core

struct GitHubSignInSheet: View {
    let request: GitHubSignIn.Request
    let onFinish: (Bool) -> Void

    @State private var access: GitHubAvailability.State
    @State private var phase: Phase = .idle
    @State private var session: LoginTerminalSession?
    @State private var isShowingOptions = false

    private enum Phase: Equatable {
        case idle
        case running
        case checking
        case connected
        case failed(String)
    }

    private static let successPause = Duration.milliseconds(700)
    private static let unresolvedRefusal =
        "Unified Dev could not tell which profile this belongs to, so it did not sign in. Close this and try again."
    private static let manualURL = "https://cli.github.com/manual/gh_auth_login"
    private static let downloadURL = "https://cli.github.com"

    init(request: GitHubSignIn.Request, onFinish: @escaping (Bool) -> Void) {
        self.request = request
        self.onFinish = onFinish
        _access = State(initialValue: request.access)
        if !request.login.acceptsSignIn { _phase = State(initialValue: .failed(Self.unresolvedRefusal)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.gutter) {
            header
            if let session {
                terminal(session)
            }
            statusLine
            footer
        }
        .padding(Metrics.pane)
        .frame(width: 660)
        .background(Palette.surface)
        .onDisappear { session?.stop() }
        .task { canBrew = Shell.which("brew") != nil }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: InspectorLayout.tight) {
            Text(title)
                .font(Typo.heading)
                .foregroundStyle(Palette.textPrimary)

            Text(sentence)
                .font(Typo.label)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func terminal(_ session: LoginTerminalSession) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: InspectorLayout.gap) {
                Text("Running \(session.label)")
                    .font(Typo.codeSmall)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button("Stop", systemImage: "xmark") { stop() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(Palette.textTertiary)
                    .help("Stop and close")
            }
            .padding(.horizontal, InspectorLayout.inset)
            .frame(height: InspectorLayout.barHeight)
            .background(Palette.surfaceSunken)

            Hairline()

            LoginTerminal(session: session)
                .frame(height: 280)
        }
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.corner)
                .strokeBorder(Palette.border, lineWidth: Metrics.outline)
        )
    }

    @ViewBuilder
    private var statusLine: some View {
        switch phase {
        case .idle, .running:
            EmptyView()
        case .checking:
            HStack(spacing: InspectorLayout.gap) {
                ProgressView().controlSize(.small)
                Text("Checking with the GitHub CLI")
                    .font(Typo.label)
                    .foregroundStyle(Palette.textSecondary)
            }
        case .connected:
            Label("Connected to GitHub", systemImage: "checkmark.circle.fill")
                .font(Typo.label)
                .foregroundStyle(Palette.positive)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(Typo.label)
                .foregroundStyle(Palette.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Metrics.spacingWide) {
            if isShowingOptions { options }

            HStack(spacing: InspectorLayout.gap) {
                Button(isShowingOptions ? "Fewer options" : "Other sign-in options") {
                    isShowingOptions.toggle()
                }
                .linkButton()
                .font(Typo.label)

                Spacer(minLength: Metrics.gutter)

                Button("Cancel", role: .cancel) { stop() }
                    .keyboardShortcut(.cancelAction)

                primaryButton
            }
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: Metrics.spacingWide) {
            Text(
                "You can sign in anywhere: run gh auth login in your own terminal, or use a "
                    + "token you already have. Unified Dev re-checks on its own, and Check again asks "
                    + "straight away."
            )
            .font(Typo.micro)
            .foregroundStyle(Palette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: InspectorLayout.gap) {
                Button("Copy Sign-In Command") { Clipboard.copy(request.login.signInCommand) }
                    .disabled(!request.login.acceptsSignIn)
                Button("Check again") { recheck() }
                Button("GitHub CLI manual") { GitHubBridge.open(Self.manualURL) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(Metrics.spacingWide)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: Metrics.corner))
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch phase {
        case .idle:
            if access == .notInstalled, !canBrew {
                Button("Open cli.github.com") { GitHubBridge.open(Self.downloadURL) }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.controlAccent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(primaryTitle, systemImage: "play.fill") { start() }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.controlAccent)
                    .keyboardShortcut(.defaultAction)
            }
        case .running, .checking:
            Button(primaryTitle, systemImage: "play.fill") {}
                .buttonStyle(.borderedProminent)
                .tint(Palette.controlAccent)
                .disabled(true)
        case .connected:
            Button("Continue") { onFinish(true) }
                .buttonStyle(.borderedProminent)
                .tint(Palette.controlAccent)
                .keyboardShortcut(.defaultAction)
        case .failed:
            Button("Try again", systemImage: "arrow.clockwise") { start() }
                .buttonStyle(.borderedProminent)
                .tint(Palette.controlAccent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var title: String {
        access == .notInstalled ? "Install the GitHub CLI" : "Connect GitHub"
    }

    private var sentence: String {
        switch access {
        case .notInstalled where canBrew:
            "This action needs the gh command, and it is not installed on this Mac. "
                + "Homebrew can install it here."
        case .notInstalled:
            "This action needs the gh command, and it is not installed on this Mac. "
                + "Install it from cli.github.com, then come back."
        default:
            "This action needs GitHub access. Sign in with the GitHub CLI to continue."
        }
    }

    private var primaryTitle: String {
        access == .notInstalled ? "Run brew install gh" : "Run gh auth login"
    }

    @State private var canBrew = false

    private func start() {
        session?.stop()

        let executable = access == .notInstalled ? "brew" : "gh"
        let arguments = access == .notInstalled ? ["install", "gh"] : request.login.signInArguments
        guard request.login.acceptsSignIn else {
            phase = .failed(Self.unresolvedRefusal)
            return
        }
        do {
            try request.login.prepare()
        } catch {
            phase = .failed(error.readableMessage)
            return
        }

        guard let session = LoginTerminalSession(
            command: LoginCommand(executable: executable, arguments: arguments),
            directory: request.directory,
            provider: nil,
            account: nil,
            gitHub: request.login,
            onExit: { _ in finished() }
        ) else {
            phase = .failed("\(executable) is not on this Mac.")
            return
        }

        self.session = session
        phase = .running
    }

    private func finished() {
        phase = .checking
        Task {
            let state = await GitHubAvailability.shared.check(login: request.login, force: true)
            switch state {
            case .ready:
                phase = .connected
                try? await Task.sleep(for: Self.successPause)
                onFinish(true)
            case .signedOut where access == .notInstalled:
                access = .signedOut
                phase = .idle
            case .signedOut:
                phase = .failed("The GitHub CLI is still signed out. You can run it again.")
            case .notInstalled:
                phase = .failed("The gh command is still not on this Mac.")
            case .unknown:
                phase = .failed("Unified Dev could not tell whether that worked.")
            }
        }
    }

    private func recheck() {
        phase = .checking
        Task {
            guard await GitHubAvailability.shared.check(login: request.login, force: true) == .ready else {
                phase = .failed("Still no GitHub access.")
                return
            }
            phase = .connected
            try? await Task.sleep(for: Self.successPause)
            onFinish(true)
        }
    }

    private func stop() {
        session?.stop()
        onFinish(false)
    }
}
