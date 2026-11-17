import Core
import SwiftUI

struct CommandLineOffer: View {
    let command: String
    var fill: Color = Palette.surface

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spacingSmall) {
            Text(command)
                .font(Typo.codeSmall)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Metrics.spacing)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                        .fill(fill)
                        .overlay(
                            RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                                .strokeBorder(Palette.border, lineWidth: Metrics.outline)
                        )
                )

            HStack(spacing: Metrics.gutter) {
                Text(
                    "Appears as \(BridgeRegistration.ownerServerName). Sessions already running "
                        + "will not see it."
                )
                .modifier(CommandLineNote())

                Spacer()

                Button(didCopy ? "Copied" : "Copy command") { copy() }
                    .disabled(didCopy)
            }
        }
        .padding(.vertical, Metrics.spacingSmall)
    }

    private func copy() {
        Clipboard.copy(.command(command))
        didCopy = true
        Task {
            try? await Task.sleep(for: Clipboard.flashDuration)
            didCopy = false
        }
    }
}

struct CommandLineInstruction: View {
    var supportsMultipleClients = false

    var body: some View {
        Text(sentence).modifier(CommandLineNote())
    }

    private var sentence: String {
        if supportsMultipleClients {
            return "Run either command once, and that client can list your projects, add a "
                + "repository and start a workspace."
        }
        return "Run this once, and Claude Code in your terminal can list your projects, add a "
            + "repository and start a workspace."
    }
}

struct CommandLineWarning: View {
    var body: some View {
        Label {
            Text(
                "Registers at user scope, in your own configuration file. Never paste it into "
                    + "a project's .mcp.json: that file is committed, and the token in it lets "
                    + "anything that can reach this Mac create projects and workspaces in your "
                    + "Unified Dev."
            )
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .modifier(CommandLineNote())
    }
}

private struct CommandLineNote: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Typo.caption)
            .foregroundStyle(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
