import AppKit
import SwiftUI
import Core

struct WelcomeCheckSubject {
    let tool: SetupTool
    let fix: SetupFix
}

struct WelcomeCheckDetailStep: View {
    let subject: WelcomeCheckSubject
    let session: LoginTerminalSession?
    let footer: WelcomeFooter

    @State private var didCopy = false

    var body: some View {
        WelcomeStage(
            hero: .symbol(subject.fix.isInteractive ? "lock.circle.fill" : "arrow.down.circle.fill", Palette.warning),
            title: subject.tool.title,
            subtitle: subject.tool.purpose,
            link: subject.fix.url.map { url in
                WelcomeLink(title: "Instructions", action: { NSWorkspace.shared.open(url) })
            },
            footer: footer
        ) {
            VStack(alignment: .leading, spacing: Metrics.inset + Metrics.spacingSmall) {
                Text(subject.fix.summary)
                    .font(Typo.bodyEmphasis)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let session {
                    terminal(session)
                } else {
                    if subject.fix.isInteractive {
                        Text("Unified Dev could not start \(subject.fix.command ?? subject.tool.executableName) here, so run it in your own terminal.")
                            .font(Typo.label)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let command = subject.fix.command {
                        commandLine(command)
                    }
                }
            }
        }
        .accessibilityIdentifier("welcome-check-detail")
    }

    private func commandLine(_ command: String) -> some View {
        HStack(spacing: Metrics.spacingWide) {
            Text(command)
                .font(Typo.code)
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Metrics.spacing)

            Button(didCopy ? "Copied" : "Copy") { copy(command) }
                .disabled(didCopy)
                .accessibilityIdentifier("welcome-copy-command")
        }
        .padding(.horizontal, Metrics.inset)
        .padding(.vertical, Metrics.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: Metrics.outline)
        )
    }

    private func terminal(_ session: LoginTerminalSession) -> some View {
        VStack(spacing: 0) {
            Text(session.isRunning ? "Running \(session.label)" : "\(session.label) finished")
                .font(Typo.code)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Metrics.inset)
                .frame(height: Metrics.barHeight)
                .background(Palette.surfaceSunken)

            Hairline()

            LoginTerminal(session: session)
                .frame(height: WelcomeMetrics.terminal)
        }
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: Metrics.outline)
        )
    }

    private func copy(_ command: String) {
        Clipboard.copy(.command(command))
        didCopy = true
        Task {
            try? await Task.sleep(for: Clipboard.flashDuration)
            didCopy = false
        }
    }
}
