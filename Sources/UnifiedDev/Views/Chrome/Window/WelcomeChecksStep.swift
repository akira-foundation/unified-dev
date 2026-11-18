import SwiftUI
import Core

struct WelcomeChecksStep: View {
    let report: SetupReport
    let isRunning: Bool
    let footer: WelcomeFooter
    let checkAgain: () -> Void
    let openDetail: (SetupCheck) -> Void

    static let checkAgainTitle = OnboardingFlow.checkAgainTitle

    var body: some View {
        WelcomeStage(
            hero: .symbol(hero.symbol, hero.ink),
            title: report.headline,
            subtitle: report.sentence,
            link: WelcomeLink(title: Self.checkAgainTitle, isEnabled: !isRunning, action: checkAgain),
            footer: footer
        ) {
            VStack(alignment: .leading, spacing: WelcomeMetrics.rowSpacing) {
                ForEach(report.checks) { check in
                    WelcomeCheckRow(
                        presentation: report.presentation(for: check),
                        openDetail: { openDetail(check) }
                    )
                }
            }
        }
        .accessibilityIdentifier("welcome-checks")
    }

    private var hero: (symbol: String, ink: Color) {
        switch report.verdict {
        case .checking: ("magnifyingglass.circle.fill", Palette.textTertiary)
        case .ready, .readyWithNotes: ("checkmark.circle.fill", WelcomeCheckRow.ink(for: .ready))
        case .blocked: ("exclamationmark.triangle.fill", WelcomeCheckRow.ink(for: .needed))
        }
    }
}
