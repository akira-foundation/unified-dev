import SwiftUI
import Core

struct WelcomeAgentStep: View {
    let candidates: [AgentKind]
    let report: SetupReport
    let agentDefault: WelcomeAgentDefault
    let footer: WelcomeFooter

    static let title = "Which agent should Unified Dev start with?"
    static let subtitle = "You can change this later, and every workspace can run a different one."

    var body: some View {
        WelcomeStage(
            hero: .symbol("sparkles", Palette.controlAccent),
            title: Self.title,
            subtitle: Self.subtitle,
            footer: footer
        ) {
            VStack(alignment: .leading, spacing: Metrics.inset) {
                if candidates.isEmpty {
                    HStack(spacing: Metrics.inset) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Looking for the agents on this Mac")
                            .font(Typo.label)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }

                ForEach(candidates, id: \.self) { kind in
                    WelcomeAgentCard(
                        kind: kind,
                        signedIn: OnboardingAgentChoice.signedInLine(for: kind, in: report),
                        isSelected: kind == shown,
                        choose: { agentDefault.choose(kind) }
                    )
                }

                if let failure = agentDefault.failure {
                    Text(failure)
                        .font(Typo.label)
                        .foregroundStyle(Palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear { agentDefault.load() }
        .accessibilityIdentifier("welcome-agent-choice")
    }

    private var shown: AgentKind {
        OnboardingAgentChoice.selection(
            among: candidates, current: agentDefault.selected ?? AppDefaults.fallbackBackend
        ) ?? AppDefaults.fallbackBackend
    }

}

struct WelcomeAgentCard: View {
    let kind: AgentKind
    let signedIn: String?
    let isSelected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(spacing: Metrics.inset + Metrics.spacingSmall) {
                VStack(alignment: .leading, spacing: Metrics.spacingTight) {
                    Text(kind.label)
                        .font(Typo.bodyEmphasis)
                        .foregroundStyle(Palette.textPrimary)

                    if let signedIn {
                        Text(signedIn)
                            .font(Typo.label)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: Metrics.inset)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Palette.controlAccent : Palette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Metrics.inset + Metrics.spacingSmall)
            .padding(.vertical, Metrics.inset + Metrics.spacingTight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cornerLarge, style: .continuous)
                    .fill(isSelected ? Palette.controlAccent.opacity(0.10) : Palette.surfaceSunken)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cornerLarge, style: .continuous)
                    .strokeBorder(
                        isSelected ? Palette.controlAccent : Palette.border,
                        lineWidth: isSelected ? Metrics.hairline : Metrics.outline
                    )
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("welcome-agent-\(kind.rawValue)")
    }
}
