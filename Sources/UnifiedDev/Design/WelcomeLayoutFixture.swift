import AppKit
import Core
import Observation
import SwiftUI

#if DEBUG
enum WelcomeLayoutStage {
    case greeting
    case checks
    case agent
    case extras
    case detail

    var progress: OnboardingProgress {
        switch self {
        case .greeting: OnboardingProgress(position: 1, count: 4)
        case .checks, .detail: OnboardingProgress(position: 2, count: 4)
        case .agent: OnboardingProgress(position: 3, count: 4)
        case .extras: OnboardingProgress(position: 4, count: 4)
        }
    }

    var forwardTitle: String {
        switch self {
        case .greeting: OnboardingFlow.startTitle
        case .extras: OnboardingFlow.finishTitle
        case .checks, .agent, .detail: OnboardingFlow.forwardTitle
        }
    }
}

@MainActor
@Observable
final class WelcomeLayoutFixture {
    var stage: WelcomeLayoutStage = .greeting
    var showsCommand = true
    let registration: CommandLineRegistration
    let showsKeepAwake: Bool
    let session: LoginTerminalSession?
    let agentDefault = WelcomeAgentDefault(store: { nil })

    init(
        showsKeepAwake: Bool = false,
        registration: CommandLineRegistration = CommandLineRegistration(source: { nil }),
        session: LoginTerminalSession? = nil
    ) {
        self.showsKeepAwake = showsKeepAwake
        self.registration = registration
        self.session = session
    }
}

struct WelcomeLayoutContent: View {
    let fixture: WelcomeLayoutFixture

    private static let subject = WelcomeCheckSubject(
        presentation: SetupCheckPresentation(tool: .gitHub, in: SetupRehearsal.report ?? .pending),
        fix: SetupFix(summary: "Sign in to GitHub", command: "gh auth login", isInteractive: true)
    )

    var body: some View {
        Group {
            switch fixture.stage {
            case .greeting:
                WelcomeGreetingStep(footer: footer, onSubmitPrompt: {})
            case .extras:
                WelcomeExtrasStep(
                    registration: fixture.registration,
                    showsKeepAwake: fixture.showsKeepAwake,
                    showsCommand: Binding(
                        get: { fixture.showsCommand },
                        set: { shown in MainActor.assumeIsolated { fixture.showsCommand = shown } }
                    ),
                    footer: footer
                )
            case .checks:
                WelcomeChecksStep(
                    report: SetupRehearsal.report ?? .pending,
                    isRunning: false,
                    footer: footer,
                    checkAgain: {},
                    openDetail: { _ in }
                )
            case .agent:
                WelcomeAgentStep(
                    candidates: AgentKind.allCases,
                    report: SetupRehearsal.report ?? .pending,
                    agentDefault: fixture.agentDefault,
                    footer: footer
                )
            case .detail:
                WelcomeCheckDetailStep(subject: Self.subject, session: fixture.session, footer: footer)
            }
        }
        .frame(width: WelcomeView.contentWidth)
        .transition(.opacity)
    }

    private var footer: WelcomeFooter {
        WelcomeFooter(
            backTitle: OnboardingFlow.backTitle,
            forwardTitle: fixture.stage.forwardTitle,
            progress: fixture.stage.progress,
            canGoBack: fixture.stage != .greeting,
            back: {},
            forward: {}
        )
    }
}
#endif
