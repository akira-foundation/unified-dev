import Foundation
import Testing
@testable import Core

@Suite("Asking Grok whether an account has a session")
struct GrokAccountLivenessTests {
    private let grokHome = AgentAccountHome(
        provider: .grok,
        id: AgentAccountID("work"),
        directory: URL(filePath: "/support/AgentAccounts/grok/work"),
        isDefault: false
    )

    private func liveness(printing output: [String]) -> AgentAccountLiveness {
        AgentAccountLiveness(cwd: "/scratch", environment: [:], makeProcess: { _ in ScriptedStatus(printing: output) })
    }

    @Test func grokSayingItIsLoggedInClaimsASession() async {
        let asked = liveness(printing: ["You are logged in with grok.com.", "", "Default model: grok-4.6"])
        #expect(await asked.report(for: grokHome) == .claimsSession)
    }

    @Test func grokSayingItIsNotAuthenticatedClaimsNoSessionThoughItExitsZero() async {
        let asked = liveness(printing: ["You are not authenticated.", "", "Default model: grok-4.6"])
        #expect(await asked.report(for: grokHome) == .claimsNoSession)
    }

    @Test(arguments: [
        "You are authenticated via deployment key.",
        "You are authenticated via XAI_API_KEY (environment variable).",
    ])
    func grokAuthenticatedAnotherWayClaimsASession(line: String) async {
        let asked = liveness(printing: [line])
        #expect(await asked.report(for: grokHome) == .claimsSession)
    }

    @Test func grokPrintingNothingItRecognisesIsUnansweredAndNeverNoSession() async {
        let asked = liveness(printing: ["error: unrecognized subcommand 'models'"])
        #expect(await asked.report(for: grokHome) == .unanswered)
    }

    @Test func theGrokCommandIsAimedAtTheAccountDirectoryAndInheritsNoIdentity() async throws {
        let launches = Launches()
        let inherited = ["PATH": "/usr/bin", "XAI_API_KEY": "made-up-key", "GROK_HOME": "/the/hosts/own"]
        let asked = AgentAccountLiveness(
            grokExecutable: "/opt/grok/bin/grok",
            cwd: "/scratch",
            environment: inherited,
            makeProcess: { launch in
                launches.record(launch)
                return ScriptedStatus(printing: ["You are logged in with grok.com."])
            }
        )

        _ = await asked.report(for: grokHome)

        let launch = try #require(launches.all.first)
        #expect(launches.all.count == 1)
        #expect(launch.executable == "/opt/grok/bin/grok")
        #expect(launch.arguments == ["models"])
        #expect(launch.environment["GROK_HOME"] == grokHome.directory.path)
        #expect(launch.environment["XAI_API_KEY"] == nil)
        #expect(launch.environment["PATH"] == "/usr/bin")
    }

    @Test func grokIsAskedWithTheExecutableTheOwnerConfiguredOrItsBareName() async {
        let launches = Launches()
        let make: @Sendable (AgentLaunch) -> any AgentProcessing = { launch in
            launches.record(launch)
            return ScriptedStatus(printing: ["You are logged in with grok.com."])
        }

        _ = await AgentAccountLiveness.using(executables: [.grok: "/opt/grok/bin/grok"], makeProcess: make)
            .report(for: grokHome)
        _ = await AgentAccountLiveness.using(executables: [:], makeProcess: make).report(for: grokHome)

        #expect(launches.all.map(\.executable) == ["/opt/grok/bin/grok", "grok"])
    }
}
