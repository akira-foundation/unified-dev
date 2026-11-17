import SwiftUI
import Core

struct PullRequestBarLine: View {
    var standing: PullRequestStanding
    var branchActions: BranchActionAvailability
    var worktree: String

    @State private var login: GitHubLogin?
    @State private var forge: ForgeKind?

    private var github: GitHubAvailability.State {
        login.map { GitHubAvailability.shared.state(for: $0) } ?? .unknown
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spacingTight) {
            headline
            secondary
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(helpText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .task(id: worktree) {
            forge = nil
            forge = await Forge.kind(forDirectory: worktree)
            let resolved = await GitHub.login(forDirectory: worktree)
            login = resolved
            await GitHubAvailability.shared.check(login: resolved)
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.spacingSmall) {
            Text(standing.headline)
                .font(Typo.body)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(standing.number == nil ? .head : .tail)

            if let number = standing.number, let url = standing.url {
                Button("#\(number)") { GitHubBridge.open(url) }
                    .linkButton()
                    .font(Typo.caption)
                    .monospacedDigit()
                    .fixedSize()
                    .help("Open #\(number) on \(standing.hostName): \(standing.headline)")
                    .accessibilityHint("Opens on \(standing.hostName)")
            }
        }
    }

    @ViewBuilder
    private var secondary: some View {
        switch aside {
        case .sentence(let text):
            Text(text)
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)

        case .connectGitHub:
            Button("Connect GitHub") { GitHubSignIn.shared.present(directory: worktree) }
                .linkButton()
                .font(Typo.caption)
                .lineLimit(1)
                .help(
                    github == .notInstalled
                        ? "The gh command is not installed, so Unified Dev cannot tell whether this"
                            + " branch has a pull request."
                        : "The GitHub CLI is signed out, so Unified Dev cannot tell whether this"
                            + " branch has a pull request."
                )
        }
    }

    private enum Aside: Equatable {
        case sentence(String)
        case connectGitHub
    }

    private var aside: Aside {
        if let note = branchActions.note { return .sentence(note) }
        if forge == .gitHub, standing.number == nil, !standing.path.isEmpty, !github.isUsable {
            return .connectGitHub
        }
        return .sentence(standing.secondary)
    }

    private var helpText: String {
        [branchActions.reason, standing.sentence].compactMap { $0 }.joined(separator: "\n")
    }

    private var accessibilityText: String {
        [
            standing.number.map { "Pull request \($0), \(standing.headline)" } ?? standing.headline,
            standing.state,
            standing.secondary,
        ].compactMap { $0 }.joined(separator: ", ")
    }
}
