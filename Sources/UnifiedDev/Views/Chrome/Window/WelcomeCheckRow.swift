import SwiftUI
import Core

struct WelcomeCheckRow: View {
    let presentation: SetupCheckPresentation
    let openDetail: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let glyphColumn: CGFloat = 22
    private static let glyphSize: CGFloat = 16

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.inset + Metrics.spacingSmall) {
            glyph
                .frame(width: Self.glyphColumn, alignment: .center)
                .accessibilityHidden(true)

            Text(presentation.tool.title)
                .font(Typo.bodyEmphasis)
                .foregroundStyle(Palette.textPrimary)

            Spacer(minLength: Metrics.inset)

            status
                .lineLimit(1)
                .truncationMode(.middle)

            if let fix = presentation.fix {
                Button(Self.openTitle(for: fix)) { openDetail() }
                    .buttonStyle(.plain)
                    .font(Typo.label)
                    .foregroundStyle(Palette.link)
                    .accessibilityIdentifier("welcome-check-open-\(presentation.tool.rawValue)")
            }
        }
        .contentShape(.rect)
    }

    static func openTitle(for fix: SetupFix) -> String {
        fix.isInteractive ? "Sign in…" : "Install…"
    }

    @ViewBuilder
    private var glyph: some View {
        switch presentation.check.outcome {
        case .pending:
            ProgressView()
                .controlSize(.mini)
        case .ready:
            mark("checkmark.circle.fill", ink: Self.ink(for: .ready))
        case .needsSignIn:
            mark(presentation.tone == .needed ? "lock.circle.fill" : "lock.circle", ink: stateInk)
        case .missing:
            mark(presentation.tone == .needed ? "exclamationmark.circle.fill" : "circle.dotted", ink: stateInk)
        }
    }

    private func mark(_ name: String, ink: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: Self.glyphSize))
            .foregroundStyle(ink)
            .transition(reduceMotion ? .identity : .scale(scale: 0.6).combined(with: .opacity))
    }

    private var stateInk: Color {
        Self.ink(for: presentation.tone)
    }

    static func ink(for tone: SetupCheckTone) -> Color {
        switch tone {
        case .needed: Palette.warning
        case .ready: Palette.accent(beside: [.warning])
        case .checking, .optional: Palette.textTertiary
        }
    }

    private var status: some View {
        Text(presentation.status)
            .font(presentation.check.outcome.detail != nil && presentation.tone == .ready ? Typo.code : Typo.label)
            .foregroundStyle(presentation.tone == .ready ? Palette.textTertiary : stateInk)
    }
}
