import SwiftUI
import Core

struct WelcomeView: View {
    let inspection: SetupInspection
    let registration: CommandLineRegistration
    let agentDefault: WelcomeAgentDefault
    let showsKeepAwake: Bool
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flow: OnboardingFlow
    @State private var subject: WelcomeCheckSubject?
    @State private var login: LoginTerminalSession?
    @State private var showsCommand = false
    @State private var autoOpen = SetupDetailAutoOpen()

    init(
        inspection: SetupInspection,
        registration: CommandLineRegistration,
        agentDefault: WelcomeAgentDefault,
        start: OnboardingStep,
        showsKeepAwake: Bool = Machine.isPortable,
        onFinish: @escaping () -> Void
    ) {
        self.inspection = inspection
        self.registration = registration
        self.agentDefault = agentDefault
        self.showsKeepAwake = showsKeepAwake
        self.onFinish = onFinish
        _flow = State(initialValue: OnboardingFlow(step: start))
    }

    static let contentWidth: CGFloat = WelcomeMetrics.windowWidth

    private var report: SetupReport { inspection.shown }

    private var settled: SetupReport { inspection.truth }

    private var candidates: [AgentKind] { OnboardingAgentChoice.candidates(in: settled) }

    private var offersAgentChoice: Bool {
        guard let hasDefaultPreset = agentDefault.hasDefaultPreset else { return false }
        return OnboardingAgentChoice.isOffered(
            in: settled,
            hasCompletedOnboarding: WelcomeLaunch.hasCompletedBefore,
            hasDefaultPreset: hasDefaultPreset
        )
    }

    private var offersExtras: Bool { showsKeepAwake || registration.isOffered }

    private var offersAreKnown: Bool {
        settled.isSettled && registration.isResolved && agentDefault.hasDefaultPreset != nil
    }

    var body: some View {
        ZStack(alignment: .top) {
            step
        }
        .frame(width: Self.contentWidth)
        .accessibilityIdentifier("welcome-step-\(flow.step.rawValue)")
        .onAppear {
            inspection.revealsInstantly = reduceMotion
            inspection.start()
            flow.offerAgentChoice(offersAgentChoice)
            flow.offerExtras(offersExtras)
            flow.settleOffers(offersAreKnown)
        }
        .task { await agentDefault.loadPresets() }
        .onChange(of: offersAgentChoice) { _, offered in flow.offerAgentChoice(offered) }
        .onChange(of: offersExtras) { _, offered in flow.offerExtras(offered) }
        .onChange(of: offersAreKnown) { _, known in flow.settleOffers(known) }
        .onChange(of: report) { openBlockingCheck() }
        .onChange(of: flow.step) { openBlockingCheck() }
        .onDisappear {
            closeDetail()
            inspection.cancel()
            registration.cancel()
            agentDefault.cancel()
        }
    }

    @ViewBuilder
    private var step: some View {
        switch flow.step {
        case .greeting:
            WelcomeGreetingStep(footer: footer, onSubmitPrompt: submitAPrompt)
                .transition(reduceMotion ? .identity : .opacity)
        case .checks:
            checksStep
        case .agent:
            WelcomeAgentStep(
                candidates: candidates,
                report: settled,
                agentDefault: agentDefault,
                footer: footer
            )
            .transition(reduceMotion ? .identity : .opacity)
        case .extras:
            WelcomeExtrasStep(
                registration: registration,
                showsKeepAwake: showsKeepAwake,
                showsCommand: $showsCommand,
                footer: footer
            )
            .transition(reduceMotion ? .identity : .opacity)
        }
    }

    @ViewBuilder
    private var checksStep: some View {
        if let subject {
            WelcomeCheckDetailStep(subject: subject.reading(report), session: login, footer: footer)
                .transition(reduceMotion ? .identity : .opacity)
        } else {
            WelcomeChecksStep(
                report: report,
                isRunning: inspection.isRunning,
                footer: footer,
                checkAgain: checkAgain,
                openDetail: { check in
                    autoOpen.readerNavigated()
                    openDetail(check)
                }
            )
            .transition(reduceMotion ? .identity : .opacity)
            .onAppear { inspection.presentChecks() }
            .onDisappear { inspection.dismissChecks() }
        }
    }

    private var footer: WelcomeFooter {
        WelcomeFooter(
            backTitle: flow.backButtonTitle,
            forwardTitle: subject == nil ? flow.forwardButtonTitle : OnboardingFlow.forwardTitle,
            progress: flow.progress,
            canGoBack: subject != nil || flow.canGoBack,
            isForwardEnabled: login?.isRunning != true && flow.canGoForward,
            back: goBack,
            forward: goForward
        )
    }

    private func move(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : Motion.pane) { change() }
    }

    private func goBack() {
        leaveChecks()
        move {
            guard subject == nil else {
                closeDetail()
                return
            }
            flow.goBack()
        }
    }

    private func goForward() {
        leaveChecks()
        guard subject == nil else {
            move { closeDetail() }
            return
        }
        guard !flow.isLastStep else {
            finish()
            return
        }
        move { flow.advance() }
    }

    private func leaveChecks() {
        autoOpen.readerLeft(flow.step)
    }

    private func checkAgain() {
        autoOpen.readerNavigated()
        inspection.start()
    }

    private func openBlockingCheck() {
        guard let check = autoOpen.check(toOpenIn: report, on: flow.step, isShowingDetail: subject != nil)
        else { return }
        openDetail(check)
    }

    private func openDetail(_ check: SetupCheck) {
        guard let opened = WelcomeCheckSubject(report.presentation(for: check)) else { return }
        let fix = opened.fix
        stopLogin()
        move { subject = opened }
        guard fix.isInteractive else { return }
        login = Self.session(for: fix, onExit: { inspection.start() })
    }

    private func closeDetail() {
        stopLogin()
        subject = nil
    }

    private static func session(
        for fix: SetupFix,
        onExit: @escaping @MainActor () -> Void
    ) -> LoginTerminalSession? {
        guard let command = LoginCommand(parsing: fix.command) else { return nil }
        return LoginTerminalSession(
            command: command,
            directory: AgentScratchDirectory.current(),
            account: nil,
            onExit: { _ in Task { @MainActor in onExit() } }
        )
    }

    private func stopLogin() {
        login?.stop()
        login = nil
    }

    private func finish() {
        closeDetail()
        if OnboardingGate.completes(verdict: settled.verdict) {
            WelcomeLaunch.recordCompletion()
        }
        onFinish()
    }

    private func submitAPrompt() {
        closeDetail()
        onFinish()
        FeedbackPresenter.shared.open(.prompt)
    }
}
