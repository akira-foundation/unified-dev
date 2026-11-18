import Testing
@testable import Core

private func report(
    git: SetupOutcome = .ready(detail: "2.51.0"),
    claude: SetupOutcome = .ready(detail: "ada@example.com"),
    codex: SetupOutcome = .missing,
    grok: SetupOutcome = .missing,
    antigravity: SetupOutcome = .missing,
    gitHub: SetupOutcome = .needsSignIn(detail: nil),
    bitbucket: SetupOutcome = .missing
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

@Suite("Setup check presentation")
struct SetupCheckPresentationTests {
    @Test("A tool the app can live without reads optional, and so does the detail opened from it")
    func optionalStaysOptional() throws {
        let ready = report()
        let grok = SetupCheckPresentation(tool: .grok, in: ready)
        #expect(grok.tone == .optional)
        #expect(grok.status == "Optional, not installed")
        let fix = try #require(grok.fix)
        #expect(!fix.isInteractive)
        #expect(SetupCheckPresentation(tool: .gitHub, in: ready).status == "Optional, not signed in")
    }

    @Test("A blocking tool is needed in the row and in its detail alike")
    func blockingIsNeeded() {
        let blocked = report(git: .missing)
        let git = SetupCheckPresentation(tool: .git, in: blocked)
        #expect(git.tone == .needed)
        #expect(git.status == "Not installed")
    }

    @Test("An absent agent is only needed when no other agent can run a workspace")
    func agentsDependOnEachOther() {
        #expect(SetupCheckPresentation(tool: .codex, in: report()).tone == .optional)
        let none = report(claude: .missing)
        #expect(SetupCheckPresentation(tool: .codex, in: none).tone == .needed)
        #expect(SetupCheckPresentation(tool: .claudeCode, in: none).tone == .needed)
    }

    @Test("While the report is still settling nothing is called optional yet")
    func notOptionalBeforeSettling() {
        let settling = report(claude: .pending)
        let codex = SetupCheckPresentation(tool: .codex, in: settling)
        #expect(codex.status == "Not installed")
        #expect(SetupCheckPresentation(tool: .claudeCode, in: settling).tone == .checking)
        #expect(SetupCheckPresentation(tool: .claudeCode, in: settling).status == "Checking")
    }

    @Test("A ready tool shows what the probe found, or Ready when it found nothing to show")
    func readyDetail() {
        #expect(SetupCheckPresentation(tool: .claudeCode, in: report()).status == "ada@example.com")
        #expect(SetupCheckPresentation(tool: .git, in: report(git: .ready(detail: nil))).status == "Ready")
        #expect(SetupCheckPresentation(tool: .git, in: report()).tone == .ready)
    }

    @Test("A sign-in that blocks is urgent and says so plainly")
    func blockingSignIn() {
        let blocked = report(claude: .needsSignIn(detail: "2.1.234"))
        let claude = SetupCheckPresentation(tool: .claudeCode, in: blocked)
        #expect(claude.tone == .needed)
        #expect(claude.isUrgent)
        #expect(claude.status == "Not signed in")
        #expect(!SetupCheckPresentation(tool: .gitHub, in: blocked).isUrgent)
    }

    @Test("Only a ready tool with something found draws it as code")
    func detailInCode() {
        #expect(SetupCheckPresentation(tool: .git, in: report()).showsDetailInCode)
        #expect(!SetupCheckPresentation(tool: .git, in: report(git: .ready(detail: nil))).showsDetailInCode)
        let signedOut = report(claude: .needsSignIn(detail: "2.1.234"), codex: .ready(detail: nil))
        #expect(!SetupCheckPresentation(tool: .claudeCode, in: signedOut).showsDetailInCode)
    }

    @Test("A report presents a check it holds the same way as the tool's own row")
    func presentationForCheck() throws {
        let blocked = report(git: .missing)
        let git = try #require(blocked.checks.first { $0.tool == .git })
        #expect(blocked.presentation(for: git) == SetupCheckPresentation(tool: .git, in: blocked))
        #expect(blocked.presentation(for: git).tone == .needed)
    }

    @Test("Reading a later report is what moves a detail on after a sign-in")
    func laterReportMovesOn() {
        let before = SetupCheckPresentation(tool: .gitHub, in: report())
        let after = SetupCheckPresentation(tool: .gitHub, in: report(gitHub: .ready(detail: "Signed in")))
        #expect(before.status == "Optional, not signed in")
        #expect(after.tone == .ready)
        #expect(after.status == "Signed in")
    }
}
