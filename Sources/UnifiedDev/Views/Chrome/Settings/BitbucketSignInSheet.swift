import SwiftUI
import Core

struct BitbucketSignInSheet: View {
    struct Request: Identifiable {
        let id = UUID()
        var login: BitbucketLogin
        var method: BitbucketLogin.Method
        var profileName: String
    }

    let request: Request
    let onFinish: () -> Void

    @State private var session: LoginTerminalSession?
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.gutter) {
            VStack(alignment: .leading, spacing: InspectorLayout.tight) {
                Text("Sign in to Bitbucket for \(request.profileName)")
                    .font(Typo.heading)
                    .foregroundStyle(Palette.textPrimary)
                Text(ProfileBitbucketWording.methodSummary(request.method))
                    .font(Typo.label)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let session {
                LoginTerminal(session: session)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
            }
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(Typo.label)
                    .foregroundStyle(Palette.warning)
            }
            HStack {
                Spacer()
                Button(session?.isRunning == false ? "Done" : "Cancel") {
                    session?.stop()
                    onFinish()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Metrics.pane)
        .frame(width: 660)
        .background(Palette.surface)
        .onAppear(perform: start)
        .onDisappear { session?.stop() }
    }

    private func start() {
        guard session == nil else { return }
        do {
            try request.login.prepare()
        } catch {
            failure = error.readableMessage
            return
        }
        session = LoginTerminalSession(
            command: LoginCommand(executable: Bitbucket.executable, arguments: request.login.signInArguments(request.method)),
            directory: AgentScratchDirectory.current(),
            provider: nil,
            account: nil,
            bitbucket: request.login,
            onExit: { _ in }
        )
        if session == nil { failure = "bkt is not on this Mac." }
    }
}
