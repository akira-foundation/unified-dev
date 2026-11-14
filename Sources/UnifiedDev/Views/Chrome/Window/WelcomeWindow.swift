import AppKit
import SwiftUI
import Core

@MainActor
enum WelcomeWindow {
    private static var window: NSWindow?
    private static var inspection: SetupInspection?
    private static var registration: CommandLineRegistration?
    private static var agentDefault: WelcomeAgentDefault?
    private static var closeWatch: NSObjectProtocol?
    private static var ownerWatch: [NSObjectProtocol] = []

    private static weak var app: AppModel?

    static func attach(_ model: AppModel) {
        app = model
    }

    static func show(
        trigger: OnboardingTrigger = .none,
        mayActivate: Bool = true,
        restarting: Bool = false
    ) {
        let existing = prepare(trigger: trigger, restarting: restarting)
        if !existing.isVisible {
            centre(existing)
            followOwnerWhileItSettles(existing)
        }
        existing.makeKeyAndOrderFront(nil)
        if mayActivate || NSApp.isActive { NSApp.activate() }
        inspection?.start()
        registration?.resolve()
    }

    private static func centre(_ window: NSWindow) {
        let owner = NSApp.orderedWindows.first {
            $0 !== window && WelcomeAnchor.canAnchor(WindowRoles.anchorCandidate($0))
        }
        guard let screen = owner?.screen ?? window.screen ?? NSScreen.main else { return }
        let anchor = owner.map { $0.convertToScreen($0.contentLayoutRect) } ?? screen.visibleFrame
        window.setFrame(CentredWindowPlacement.frame(
            size: window.frame.size, around: anchor, visible: screen.visibleFrame
        ), display: false)
    }

    private static func followOwnerWhileItSettles(_ welcome: NSWindow) {
        ownerWatch.forEach(NotificationCenter.default.removeObserver)
        let welcomeID = ObjectIdentifier(welcome)
        let names: [Notification.Name] = [
            NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didBecomeMainNotification,
        ]
        let watching = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                guard let moved = (note.object as? NSWindow).map(ObjectIdentifier.init) else { return }
                MainActor.assumeIsolated {
                    guard moved != welcomeID,
                          let current = window, ObjectIdentifier(current) == welcomeID, current.isVisible,
                          let owner = NSApp.windows.first(where: { ObjectIdentifier($0) == moved }),
                          WelcomeAnchor.canAnchor(WindowRoles.anchorCandidate(owner))
                    else { return }
                    centre(current)
                }
            }
        }
        ownerWatch = watching
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            watching.forEach(NotificationCenter.default.removeObserver)
            guard ownerWatch.count == watching.count,
                  zip(ownerWatch, watching).allSatisfy({ $0 as AnyObject === $1 as AnyObject })
            else { return }
            ownerWatch = []
        }
    }

    static func prepare(trigger: OnboardingTrigger, restarting: Bool = false) -> NSWindow {
        if restarting {
            if let closeWatch { NotificationCenter.default.removeObserver(closeWatch) }
            closeWatch = nil
            inspection?.cancel()
            registration?.cancel()
            agentDefault?.cancel()
            window?.close()
            window?.contentViewController = nil
            window = nil
            inspection = nil
            registration = nil
            agentDefault = nil
        }
        let existing = window ?? make(trigger: trigger)
        window = existing
        return existing
    }

    static func close() {
        window?.close()
    }

    private static func make(trigger: OnboardingTrigger) -> NSWindow {
        let model = SetupInspection(
            rehearsal: SetupRehearsal.report,
            agentOverrides: { await waitForAgentOverrides() }
        )
        inspection = model

        let offer = CommandLineRegistration(source: { app?.bridge?.ownerAttachment() })
        registration = offer

        let chosenAgent = WelcomeAgentDefault(store: { await waitForStore() })
        agentDefault = chosenAgent

        let host = WelcomeHostingController(rootView: WelcomeView(
            inspection: model,
            registration: offer,
            agentDefault: chosenAgent,
            start: OnboardingFlow.firstStep(trigger: trigger),
            onFinish: { close() }
        ), contentWidth: WelcomeView.contentWidth)
        let size = host.fittingContentSize()

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "Welcome to Unified Dev"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.contentViewController = host
        window.center()
        closeWatch = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                WelcomeLaunch.recordDismissal(verdict: inspection?.truth.verdict)
            }
        }
        WindowRoles.mark(window, as: .utility)
        return window
    }

    private static func waitForStore(timeout: Duration = .seconds(3)) async -> Store? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let store = app?.store { return store }
            try? await Task.sleep(for: .milliseconds(150))
            if Task.isCancelled { return nil }
        }
        return app?.store
    }

    fileprivate static func waitForAgentOverrides(
        timeout: Duration = .seconds(3)
    ) async -> [AgentKind: String] {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let store = app?.store {
                return await AgentCatalog.executablePathOverrides(in: store)
            }
            try? await Task.sleep(for: .milliseconds(150))
            if Task.isCancelled { return [:] }
        }
        return await AgentCatalog.executablePathOverrides(in: app?.store)
    }
}

@MainActor
enum WelcomeLaunch {
    static func presentIfNeeded() {
        if OnboardingGate.trigger(hasCompletedBefore: hasCompletedBefore, verdict: nil) == .firstRun {
            WelcomeWindow.show(trigger: .firstRun)
            return
        }

        Task {
            let overrides = await WelcomeWindow.waitForAgentOverrides()
            let report = await SetupProbe(agentOverrides: overrides).report()
            guard OnboardingGate.trigger(hasCompletedBefore: true, verdict: report.verdict) == .blocked
            else { return }
            WelcomeWindow.show(trigger: .blocked, mayActivate: false)
        }
    }

    static var hasCompletedBefore: Bool {
        UserDefaults.standard.bool(forKey: OnboardingGate.completedKey)
    }

    static func recordCompletion() {
        UserDefaults.standard.set(true, forKey: OnboardingGate.completedKey)
    }

    static func recordDismissal(verdict: SetupVerdict?) {
        guard OnboardingGate.completes(verdict: verdict) else { return }
        recordCompletion()
    }
}

enum SetupRehearsal {
    static var report: SetupReport? {
        #if DEBUG
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--setup-rehearsal"), index + 1 < arguments.count
        else { return nil }
        return named(arguments[index + 1])
        #else
        return nil
        #endif
    }

    #if DEBUG
    private static func named(_ name: String) -> SetupReport? {
        switch name {
        case "all-clear":
            return make()
        case "signed-out-github":
            return make(gitHub: .needsSignIn(detail: nil))
        case "no-github":
            return make(gitHub: .missing)
        case "no-codex":
            return make(codex: .missing)
        case "signed-out-claude":
            return make(claude: .needsSignIn(detail: "2.1.234"), codex: .missing)
        case "no-agent":
            return make(claude: .missing, codex: .missing, gitHub: .missing)
        case "no-git":
            return make(git: .missing)
        default:
            return nil
        }
    }

    private static func make(
        git: SetupOutcome = .ready(detail: "2.51.0"),
        claude: SetupOutcome = .ready(detail: "you@example.com"),
        codex: SetupOutcome = .ready(detail: "you@example.com"),
        grok: SetupOutcome = .missing,
        antigravity: SetupOutcome = .missing,
        gitHub: SetupOutcome = .ready(detail: "Signed in"),
        bitbucket: SetupOutcome = .ready(detail: "Signed in")
    ) -> SetupReport {
        SetupReport(checks: [
            SetupCheck(tool: .git, outcome: git),
            SetupCheck(tool: .claudeCode, outcome: claude),
            SetupCheck(tool: .codex, outcome: codex),
            SetupCheck(tool: .grok, outcome: grok),
            SetupCheck(tool: .antigravity, outcome: antigravity),
            SetupCheck(tool: .gitHub, outcome: gitHub),
            SetupCheck(tool: .bitbucket, outcome: bitbucket),
        ])
    }
    #endif
}
