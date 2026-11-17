import Testing
import Foundation
@testable import Core

@Suite("The Bitbucket CLI in the setup check")
struct SetupBitbucketTests {
    private func report(bitbucket: SetupOutcome, gitHub: SetupOutcome = .ready(detail: "Signed in")) -> SetupReport {
        SetupReport(checks: SetupTool.displayOrder.map { tool in
            switch tool {
            case .bitbucket: SetupCheck(tool: tool, outcome: bitbucket)
            case .gitHub: SetupCheck(tool: tool, outcome: gitHub)
            default: SetupCheck(tool: tool, outcome: .ready(detail: nil))
            }
        })
    }

    @Test("it is checked last, beside the GitHub CLI, and runs bkt")
    func listed() {
        #expect(SetupTool.displayOrder.suffix(2) == [.gitHub, .bitbucket])
        #expect(SetupTool.bitbucket.executableName == "bkt")
        #expect(SetupTool.bitbucket.agentKind == nil)
        #expect(SetupTool.bitbucket.isOptional)
        #expect(!SetupTool.gitHub.isOptional)
    }

    @Test("without it nothing is blocked and the sentence does not name it", arguments: [
        SetupOutcome.missing, .needsSignIn(detail: nil),
    ])
    func optional(outcome: SetupOutcome) {
        let setup = report(bitbucket: outcome)

        #expect(setup.verdict == .readyWithNotes)
        #expect(setup.sentence.hasPrefix("Unified Dev has what it needs."))
        #expect(setup.blocking.isEmpty)
        #expect(setup.severity(for: .bitbucket) == .note)
        #expect(!setup.sentence.contains("Bitbucket"))
    }

    @Test("a quiet GitHub CLI is still named, and the Bitbucket CLI beside it is not")
    func onlyGitHubNamed() {
        let sentence = report(bitbucket: .missing, gitHub: .missing).sentence

        #expect(sentence.contains("The GitHub CLI is not set up"))
        #expect(!sentence.contains("Bitbucket"))
    }

    @Test("it offers the install, then the sign-in to Bitbucket Cloud in the browser")
    func fixes() {
        let install = SetupCheck(tool: .bitbucket, outcome: .missing).fix
        let signIn = SetupCheck(tool: .bitbucket, outcome: .needsSignIn(detail: nil)).fix

        #expect(install?.command == "brew install bitbucket-cli")
        #expect(install?.isInteractive == false)
        #expect(signIn?.command == "bkt auth login https://bitbucket.org --kind cloud --web")
        #expect(signIn?.isInteractive == true)
        #expect(SetupCheck(tool: .bitbucket, outcome: .ready(detail: nil)).fix == nil)
    }

    @Test("a sign-in to Bitbucket Cloud is ready, and anything less asks for one", arguments: [
        (#"{"hosts": [{"key": "api.bitbucket.org", "kind": "cloud"}], "contexts": null}"#, 0, true),
        (#"{"hosts": [{"key": "bitbucket.example.com", "kind": "dc"}], "contexts": []}"#, 0, false),
        (#"{"hosts": null, "contexts": null}"#, 0, false),
        (#"{"hosts": [{"key": "api.bitbucket.org", "kind": "cloud"}], "contexts": null}"#, 1, false),
        ("", 1, false),
    ] as [(String, Int32, Bool)])
    func readsStatus(stdout: String, status: Int32, ready: Bool) {
        let outcome = SetupProbe.bitbucketOutcome(status: ShellResult(status: status, stdout: stdout, stderr: ""))

        #expect(outcome.isReady == ready)
        #expect(SetupProbe.bitbucketOutcome(status: nil) == .needsSignIn(detail: nil))
    }
}
