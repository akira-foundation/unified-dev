import SwiftUI
import Core

struct PullRequestBadge: View {
    var number: Int
    var title: String
    var url: String
    var tint: Color?

    private var ink: Color { tint ?? Palette.textSecondary }

    private var host: String { ForgeRepository.kind(ofRemote: url).displayName }

    var body: some View {
        Button(action: open) {
            HStack(spacing: Metrics.spacingSmall) {
                Text(verbatim: "#\(number)")
                    .font(Typo.label)
                    .monospacedDigit()

                Image(systemName: "arrow.up.forward")
                    .font(Typo.caption)
            }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(ink)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Pull request \(number), \(title)")
        .accessibilityHint("Opens on \(host)")
        .help("Open #\(number) on \(host): \(title)")
    }

    private func open() {
        GitHubBridge.open(url)
    }
}
